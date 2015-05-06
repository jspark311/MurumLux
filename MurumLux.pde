/*
*  This source file is long overdue for mitotic division. It is not forgotten. :-)
*      --- J. Ian Lindsay
*/


#define GOL_BOARD_WIDTH  96
#define GOL_BOARD_HEIGHT 64

#include <ManuvrOS.h>
#include <StringBuilder.h>
#include "StaticHub.h"
#include <Arduino.h>

#include <Adafruit_GFX.h>   // Core graphics library
#include <RGBmatrixPanel.h> // Hardware-specific library


#include "static_images.c"

uint32_t    tStart  = 0;
uint32_t    led     = HIGH;





/*****************************************************************************************
* These are things that are on-deck for migration into the panel driver.
******************************************************************************************
* DMA/Timer code in the hacked Adafruit driver was taken from Keith Vogel's LMBling.
*   This is a terrible mess. I've basically eviscerated the original AdaFruit library and
*   stitched it back together as needed, but there are still guts hanging out.
* That being said, it works pretty well. I see very little flicker, even under
*   high CPU load elsewhere. Load artifacts manifest themselves as a (very slightly) 
*   dimmer display. I could certainly get at least 15-bit color from brute-force PWM
*   once I finish stitching up the class.
*      --- J. Ian Lindsay
*
* TODO: Clean up all the indexing slice-and-dice once all the machinary is in the proper
*       place. Feels like tracing mobius loops as it is. Encapsulate the abstraction at 
*       drawPixel().
* 
*****************************************************************************************/
#define    MAX_DEPTH_PER_CHANNEL  4
#define    PANEL_WIDTH  192
#define    PANEL_HEIGHT 16   // Actual panel height is twice this, because we pack bits.
#define    CONTROL_BYTES_PER_ROW 8


uint8_t    depth_per_channel = MAX_DEPTH_PER_CHANNEL;

const uint16_t plane_size = PANEL_HEIGHT * (PANEL_WIDTH + CONTROL_BYTES_PER_ROW) * 2;
const uint16_t tail_length = (PANEL_WIDTH + CONTROL_BYTES_PER_ROW) * 2;
const uint16_t fb_size    = MAX_DEPTH_PER_CHANNEL * plane_size + tail_length;
uint8_t        framebuffer[fb_size];
bool update_frame = true;

RGBmatrixPanel matrix(framebuffer, fb_size, false);


void setPixel(int x, int y, uint16_t color) {
  if ((x > 63) || (y > 95)) return;
  
  // Experimenting with color depth...
  //uint8_t r = (color >> 11) & 0x1F;   // RRRRRggggggbbbbb
  //uint8_t g = (color >> 6)  & 0x1F;   // rrrrrGGGGGgbbbbb
  //uint8_t b = (color)       & 0x1F;   // rrrrrggggggBBBBB
  uint8_t r = (color >> 14) & 0x03;   // RRRrrggggggbbbbb
  uint8_t g = (color >> 9)  & 0x03;   // rrrrrGGGgggbbbbb
  uint8_t b = (color >> 3)  & 0x03;   // rrrrrggggggBBBbb
  
  int orig_y = y;

  // The panel is laid out in a 2x3 arrangement (64x96) So first, translate 
  // the coordinates into the 192x32 display that is reflected by the panel electronics.
  uint8_t starting_x = 192;
  y = y % 32;
  if (orig_y >= 64) {
    x += 128;
  }
  else if (orig_y >= 32) {
    x += 64;
  }
  else {
  }

  /* Because our panel layout is not a single unit, we need to correct for
     the offsets to make this function logical to the caller. */
  // We need to transpose the x-coordinate.
  if (x < 64) {
    x += 128;
  }
  else if (x >= 128) {
    x -= 128;
  }

  // Then, condense the y-coordinate, because we packed two pixels into a single byte.
  int shift_offset  = (y<16) ? 0 : 3;
  y = (y<16) ? y : y-16;
  
  // Find the byte offset within each plane.
  uint16_t planar_offset = y * ((PANEL_WIDTH * 2) + CONTROL_BYTES_PER_ROW) + (x*2);

  uint8_t temp_byte = 0;
  uint8_t nu_byte   = 0;
  for (int plane = 0; plane < depth_per_channel; plane++) {
    temp_byte = framebuffer[(plane * plane_size)+planar_offset] & ~(0x07 << shift_offset);
    nu_byte   = 0;
    if (r>0) nu_byte = nu_byte + (1 << (shift_offset+0));
    if (g>0) nu_byte = nu_byte + (1 << (shift_offset+1));
    if (b>0) nu_byte = nu_byte + (1 << (shift_offset+2));

    framebuffer[(plane * plane_size)+planar_offset] = nu_byte | temp_byte;
    framebuffer[(plane * plane_size)+planar_offset+1] = nu_byte | temp_byte | 0x40;
    r = r >> 1;
    g = g >> 1;
    b = b >> 1;
    //r--;
    //g--;
    //b--;
  }
}




void init_fb() {
  uint8_t color = 0;

  // We need to init the framebuffer with our clock signals (since we haven't got any
  // broken out on the WiFire).

  // Some ASCII art is in order....  
  // Bit 6 is the shift-register clock, bit 7 is the control signal clock.
  //
  //  0  1  2  3  4  5  6   7     <--- PORTE bit 
  //                   STB CLK
  // r1 g1 b1 r2 g2 b2            <--- Data pin mapping
  // A  B  C  D  LA OE            <--- Control signal mapping
  //
  
  int total_row_length = (PANEL_WIDTH * 2) + CONTROL_BYTES_PER_ROW;
  for (int plane = 0; plane < depth_per_channel; plane++) {
    for (int _cur_row = 0; _cur_row < PANEL_HEIGHT; _cur_row++) {
      for (int k = 0; k < (PANEL_WIDTH * 2); k+=2) {
        // Zero-out the color information and install the panel clock band...
        framebuffer[((plane * plane_size) + (_cur_row * total_row_length) + k) + 0] = 0;
        framebuffer[((plane * plane_size) + (_cur_row * total_row_length) + k) + 1] = 64;
      }
      
      // Set ABCD and our clock band for the flip flops driving them.
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 0] = _cur_row + 32;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 1] = _cur_row + 32 + 128;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 2] = _cur_row + 16 + 32;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 3] = _cur_row + 16 + 32 + 128;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 4] = _cur_row + 32;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 5] = _cur_row + 32 + 128;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 6] = _cur_row;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (PANEL_WIDTH * 2) + 7] = _cur_row + 128;
    }
  }

  // Here, we are going to set a trailing control sequence to prevent the last-drawn line from being brighter.
  // Without this (or better ISR....) we will be leaving the last row OE until we redraw the whole panel.  
  for (int i = 0; i < (PANEL_WIDTH * 2); i++) {
    framebuffer[(fb_size - tail_length) + i] = 0;
  }
  framebuffer[fb_size - 8] = 32;
  framebuffer[fb_size - 7] = 32 + 128;
  framebuffer[fb_size - 6] = 32;
  framebuffer[fb_size - 5] = 32 + 128;
  framebuffer[fb_size - 4] = 32;
  framebuffer[fb_size - 3] = 32 + 128;
  framebuffer[fb_size - 2] = 32;
  framebuffer[fb_size - 1] = 32 + 128;
}



void blackout() {
  /* Until the render buffer is torn off the top of the framebuffer, we
     do this to prevent nasty artifacts. */
  matrix.haltDMA();
  while (!matrix.DMADone()) {}

  for (int a = 0; a < 64; a++) {
    for (int b = 0; b < 96; b++) {
      setPixel(a, b, 0);
    }
  }
}


/*
* Given one of the static images, write it to the frame buffer.
*/
void set_logo(const char* logo) {
  uint16_t* ptr_cast = (uint16_t*) logo;
  /* Until the render buffer is torn off the top of the framebuffer, we
     do this to prevent nasty artifacts. */
//  matrix.haltDMA();
//  while (!matrix.DMADone()) {}

  for (int a = 0; a < 96*64; a++) {
    
    setPixel(((a)/96), (95-((a)%96)), *((uint16_t*)ptr_cast+a));
  }
}




/*****************************************************************************************
* Coherent noise
******************************************************************************************
* This was adapted from AdaFruit's GFX library demos.
*
*  // plasma demo for Adafruit RGBmatrixPanel library.
*  // Demonstrates unbuffered animation on our 32x32 RGB LED matrix:
*  // http://www.adafruit.com/products/607
*  
*  // Written by Limor Fried/Ladyada & Phil Burgess/PaintYourDragon
*  // for Adafruit Industries.
*  // BSD license, all text above must be included in any redistribution.
*****************************************************************************************/

static const int8_t sinetab[256] = {
     0,   2,   5,   8,  11,  15,  18,  21,
    24,  27,  30,  33,  36,  39,  42,  45,
    48,  51,  54,  56,  59,  62,  65,  67,
    70,  72,  75,  77,  80,  82,  85,  87,
    89,  91,  93,  96,  98, 100, 101, 103,
   105, 107, 108, 110, 111, 113, 114, 116,
   117, 118, 119, 120, 121, 122, 123, 123,
   124, 125, 125, 126, 126, 126, 126, 126,
   127, 126, 126, 126, 126, 126, 125, 125,
   124, 123, 123, 122, 121, 120, 119, 118,
   117, 116, 114, 113, 111, 110, 108, 107,
   105, 103, 101, 100,  98,  96,  93,  91,
    89,  87,  85,  82,  80,  77,  75,  72,
    70,  67,  65,  62,  59,  56,  54,  51,
    48,  45,  42,  39,  36,  33,  30,  27,
    24,  21,  18,  15,  11,   8,   5,   2,
     0,  -3,  -6,  -9, -12, -16, -19, -22,
   -25, -28, -31, -34, -37, -40, -43, -46,
   -49, -52, -55, -57, -60, -63, -66, -68,
   -71, -73, -76, -78, -81, -83, -86, -88,
   -90, -92, -94, -97, -99,-101,-102,-104,
  -106,-108,-109,-111,-112,-114,-115,-117,
  -118,-119,-120,-121,-122,-123,-124,-124,
  -125,-126,-126,-127,-127,-127,-127,-127,
  -128,-127,-127,-127,-127,-127,-126,-126,
  -125,-124,-124,-123,-122,-121,-120,-119,
  -118,-117,-115,-114,-112,-111,-109,-108,
  -106,-104,-102,-101, -99, -97, -94, -92,
   -90, -88, -86, -83, -81, -78, -76, -73,
   -71, -68, -66, -63, -60, -57, -55, -52,
   -49, -46, -43, -40, -37, -34, -31, -28,
   -25, -22, -19, -16, -12,  -9,  -6,  -3
};


const float radius1  = 16.3, radius2  = 23.0, radius3  = 40.8, radius4  = 44.2,
            centerx1 = 16.1, centerx2 = 11.6, centerx3 = 23.4, centerx4 =  4.1, 
            centery1 =  8.7, centery2 =  6.5, centery3 = 14.0, centery4 = -2.9;
float       angle1   =  0.0, angle2   =  0.0, angle3   =  0.0, angle4   =  0.0;
float       angle1_s =  0.0, angle2_s =  0.0, angle3_s =  0.0, angle4_s =  0.0;
long        hueShift =  0;
int         hue_shift_s = 2;
int         x1, x2, x3, x4, _y1, _y2, _y3, _y4, sx1, sx2, sx3, sx4;

void advance_plasma() {
  unsigned char x, y;
  long          value;
  sx1 = (int)(cos(angle1) * radius1 + centerx1);
  sx2 = (int)(cos(angle2) * radius2 + centerx2);
  sx3 = (int)(cos(angle3) * radius3 + centerx3);
  sx4 = (int)(cos(angle4) * radius4 + centerx4);
  _y1 = (int)(sin(angle1) * radius1 + centery1);
  _y2 = (int)(sin(angle2) * radius2 + centery2);
  _y3 = (int)(sin(angle3) * radius3 + centery3);
  _y4 = (int)(sin(angle4) * radius4 + centery4);

  for(y=0; y<96; y++) {
    x1 = sx1; x2 = sx2; x3 = sx3; x4 = sx4;
    for(x=0; x<64; x++) {
      value = hueShift
        + (int8_t)pgm_read_byte(sinetab + (uint8_t)((x1 * x1 + _y1 * _y1) >> 2))
        + (int8_t)pgm_read_byte(sinetab + (uint8_t)((x2 * x2 + _y2 * _y2) >> 2))
        + (int8_t)pgm_read_byte(sinetab + (uint8_t)((x3 * x3 + _y3 * _y3) >> 3))
        + (int8_t)pgm_read_byte(sinetab + (uint8_t)((x4 * x4 + _y4 * _y4) >> 3));
//      matrix.drawPixel(x, y, matrix.ColorHSV(value * 3, 255, 255, true));
      setPixel(x, y, matrix.ColorHSV(value * 3, 255, 255, true));
      x1--; x2--; x3--; x4--;
    }
    _y1--; _y2--; _y3--; _y4--;
  }

    angle1 += angle1_s;
    angle2 -= angle2_s;
    angle3 += angle3_s;
    angle4 -= angle4_s;
    hueShift += hue_shift_s;
}



/*****************************************************************************************
* GoL
******************************************************************************************
* This implementation of GoL was written by user creativename.
* His original commentary is preserved where it is still relevant.
* 
* I have mutated the original source to fit this project. The following changes 
*   are planned (in no particular order):
*   1) map the board onto a toroid. Is presently a bounded plane.
*   2) Recode to eliminate the passing of arrays as arguments.
*   3) Make birth-death colors stand out better.
*
*      --- J. Ian Lindsay
* 
*  http://runnable.com/u/creativename
*  http://runnable.com/UwQvQY99xW5AAAAQ/john-conway-s-game-of-life-for-c%2B%2B-nested-for-loops-and-2-dimensional-arrays
*
*  //A very simple C++ implementation of John Conway's Game of Life.
*  //This implementation uses several nested for loops as well as two-dimensional
*  //arrays to create a grid for the cells in the simulation to interact.
*  //The array that is displayed to the user is 50 x 100, but actual size
*  //of the array is 52 x 102.  The reason for this is to make the 
*  //calculations easier for the cells on the outermost "frame" of the grid.
*****************************************************************************************/
//Copies one array to another.
void copy(int array1[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH], int array2[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH]) {
  for(int j = 0; j < GOL_BOARD_HEIGHT; j++) {
    for(int i = 0; i < GOL_BOARD_WIDTH; i++) {
      array2[j][i] = array1[j][i];
    }
  }
}

//The life function is the most important function in the program.
//It counts the number of cells surrounding the center cell, and 
//determines whether it lives, dies, or stays the same.
void life(int array[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH], char choice)
{
  //Copies the main array to a temp array so changes can be entered into a grid
  //without effecting the other cells and the calculations being performed on them.
  int temp[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH];
  copy(array, temp);
  for(int j = 1; j < GOL_BOARD_HEIGHT-1; j++) {
    for(int i = 1; i < GOL_BOARD_WIDTH-1; i++) {
      if(choice == 'm') {
        //The Moore neighborhood checks all 8 cells surrounding the current cell in the array.
        int count = 0;
        count = array[j-1][i] + 
          array[j-1][i-1] +
          array[j][i-1] +
          array[j+1][i-1] +
          array[j+1][i] +
          array[j+1][i+1] +
          array[j][i+1] +
          array[j-1][i+1];

        if(count < 2 || count > 3) temp[j][i] = 0;  //The cell dies.
        else if(count == 2) temp[j][i] = array[j][i];  //The cell stays the same.
        else if(count == 3) temp[j][i] = 1;  //The cell either stays alive, or is "born".
      }

      else if(choice == 'v') {
        //The Von Neumann neighborhood checks only the 4 surrounding cells in the array,
        //(N, S, E, and W).
        int count = 0;
        count = array[j-1][i] +
          array[j][i-1] +
          array[j+1][i] +
          array[j][i+1];  
          
        if(count < 2 || count > 3) temp[j][i] = 0; //The cell dies.
        else if(count == 2) temp[j][i] = array[j][i];    //The cell stays the same.
        else if(count == 3) temp[j][i] = 1;   //The cell either stays alive, or is "born".
      }        
    }
   }
  //Copies the completed temp array back to the main array.
  copy(temp, array);
}

//Checks to see if two arrays are exactly the same. 
//This is used to end the simulation early, if it 
//becomes stable before the 100th generation. This
//occurs fairly often in the Von Neumann neighborhood,
//but almost never in the Moore neighborhood.
bool compare(int array1[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH], int array2[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH]) {
  int count = 0;
  for(int j = 0; j < GOL_BOARD_HEIGHT; j++) {
    for(int i = 0; i < GOL_BOARD_WIDTH; i++) {
      if(array1[j][i]==array2[j][i]) {
        count++;
      }
    }
  }
  //Since the count gets incremented every time the cells are exactly the same,
  //an easy way to check if the two arrays are equal is to compare the count to 
  //the dimensions of the array multiplied together.
  if(count == GOL_BOARD_HEIGHT*GOL_BOARD_WIDTH)
    return true;
  else
    return false;
}

//This function prints the 50 x 100 part of the array, since that's the only
//portion of the array that we're really interested in. 
void print(int array[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH], int bu[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH]) {
  for(int j = 0; j < GOL_BOARD_HEIGHT; j++) {
    for(int i = 0; i < GOL_BOARD_WIDTH; i++) {
      if(array[j][i] == 1) {
        setPixel(j, i, (bu[j][i]) ? 0xFFFF : 0x0617);
      }
      else {
        setPixel(j, i, (bu[j][i]) ? 0xC000 : 0);
      }
    }
  }
}

// Local scope stuff to migrate.
  int gen0[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH];
  int todo[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH];
  int backup[GOL_BOARD_HEIGHT][GOL_BOARD_WIDTH];
  char neighborhood = 'm';
  char cont;


void generate_random_gol_state() {
  srand(micros());
  for(int j = 1; j < GOL_BOARD_HEIGHT-1; j++) {
    for (int i = 1; i < GOL_BOARD_WIDTH-1; i++) {
      gen0[j][i] = rand() % 2;
    }
  }
  copy(gen0, todo);
}



void advance_gol_states() {
  copy(todo, backup);
  life(todo, neighborhood);
  print(todo, backup);
}


/*****************************************************************************************
*** Setup and Loop
*****************************************************************************************/

StringBuilder ipak_rx;
int currentx = 0;
int currenty = 0;
int currentc = 0x020F;

uint8_t mode = 6;

// TODO: Replace these with the Scheduler.
uint32_t time_until_action = 9001;
uint32_t action_time_marker = 9001;
  


int8_t process_string_from_counterparty(StringBuilder* in) {
  if (in == NULL) return -1;
  if (in->length() < 11) return -2;
  
  int8_t return_value = 0;
  const char* test = (const char*) in->string();

  if (strcasestr(test, "ATCHVAR ")) {
    // This sure looks like it should be here....
    int variable = atoi((const char*) (test+8));
    switch (variable) {
      case 1:   // Position from e-field box.
        Serial.print(".");
        in->cull(10);
        if (in->split(",") == 3) {
          // Remember... The e-field box is not kinked 90-degrees.
          currentx = (in->position_as_int(1)) >> 10;   // 63 max.
          currenty = (in->position_as_int(0)) / 683;   // 96 max.
          currentc = in->position_as_int(2);

          switch (mode) {
            case 3:
              break;
            case 4:
              gen0[currentx][currenty] = 1;
              break;
          }
        }
        else {
          Serial.println("This is not enough broccolis.");
        }
        break;
      case 2:   // Airwheel
        break;
      case 3:   // Swipe direction
        Serial.println("Swipe");
        switch (mode) {
          case 3:
            break;
          case 9:
            // Swipe the logos.
            action_time_marker = 0;
            break;
          default:
            break;
        }
        break;
      case 4:   // Tap direction
        Serial.println("Tap");
        switch (mode) {
          case 2:
            mode = 4;
            break;
          case 4:
            mode = 9;
            break;
          case 9:
            mode = 2;
            break;
          default:
            mode = 2;
            break;
        }
        break;
      case 5:   // Double tap direction
        Serial.println("Double tap");
        break;
      case 6:   // Touch direction
        Serial.println("Touch");
        break;
      case 7:   // Special event
        break;
        
      case 9:   // Module commands
        break;
    }
  }
  return return_value;
}





void setup() {
  pinMode(39, INPUT); 

  Serial.begin(115200);
  Serial1.begin(115200);
  init_fb();
  tStart = millis();

  pinMode(PIN_LED1, OUTPUT); 
  digitalWrite(PIN_LED1, led);

  // This is the reset pin for the flip-flop. We toggle it once, and never again. Piping the framebuffer
  //   into the panel will keep it in-sync if something happens.
  pinMode(34, OUTPUT); 
  digitalWrite(34, 0);
  digitalWrite(34, 1);  // Hold MS inactive.
}


void loop() {
  unsigned char x, y;

  uint32_t tCur;
//  matrix.begin();
  
  uint32_t last_frame_time = 0;
  
  const char* logo_list[] = {chipkit_logo, microchip_logo, mpide_logo, digilent_logo, manuvr_logo};
  
  uint8_t logo_up = 0;

  int frame_rate = 30;
  
  
  while (1) {
    tCur = millis();
    
    if (Serial.available()) {
      char c = Serial.read();
      if ((c >= 0x30) && (c < 0x3A)) mode = (c - 0x30);
      
      switch (c) {
        case '-':
          blackout();
          if (depth_per_channel > 0) depth_per_channel--;
          break;
          
        case '+':
          blackout();
          if (depth_per_channel < 5) depth_per_channel++;
          break;
          
        case 'Y': hue_shift_s += 1; break;
        case 'y': hue_shift_s -= 1; break;

        case 'U': angle1_s += 0.02; break;
        case 'u': angle1_s -= 0.02; break;

        case 'I': angle2_s += 0.02; break;
        case 'i': angle2_s -= 0.02; break;

        case 'O': angle3_s += 0.02; break;
        case 'o': angle3_s -= 0.02; break;

        case 'P': angle4_s += 0.02; break;
        case 'p': angle4_s -= 0.02; break;
        
        case 'f': 
          frame_rate++; 
          Serial.print("Frame period: ");
          Serial.println(frame_rate);
          break;
        case 'F': 
          frame_rate--; 
          Serial.print("Frame period: ");
          Serial.println(frame_rate);
          break;


        case '0':
          init_fb();
        case 'q':
          mode = 0;
          break;
        case '1':
          init_fb();
          break;
        case '2':
          blackout();
          break;
        case '3':
          blackout();
          break;
        case '4':
          generate_random_gol_state();
          break;
        case '5':
          break;
        case '6':
          break;
        case '7':
          break;
        case '8':
          break;
        case '9':
          set_logo(logo_list[logo_up % 5]);
          set_logo(logo_list[logo_up % 5]);
          logo_up++;
          action_time_marker = millis();
          //matrix.fillScreen(0);
          break;
      }
      
    }

    while (Serial1.available()) {
      char c = Serial1.read();
      ipak_rx.concat(c);
      
      if (c == '\n') {
        if (process_string_from_counterparty(&ipak_rx)) {
          ipak_rx.clear();
        }
        else {
          // If it isn't meant for the machine, it is meant for the man looking at the screen. Render it.
          ipak_rx.clear();
        }
      }
    }

    if(tCur - tStart > frame_rate) {
      led ^= HIGH;
      tStart = tCur;
      digitalWrite(PIN_LED1, led);
      switch (mode) {
        case 1:   // Pixel run mode (for debugging things)
          setPixel(currentx % 64, currentx/64, currentc);
          currentx++;
          if (currentx % 16 == 15) {
            currentc = (uint16_t) random(millis());
          }
          break;
        case 2:   // Coherent noise.
          advance_plasma();
          break;
        case 3:   // Paint mode.
          setPixel(currentx, currenty, currentc);
          break;
        case 4:   // GoL
          advance_gol_states();
          break;

        case 9:   // Logo cycle
          if(millis() - action_time_marker > time_until_action) {
            set_logo(logo_list[logo_up % 5]);
            set_logo(logo_list[logo_up % 5]);
            logo_up++;
            action_time_marker = millis();
          }
          break;
      }
    }

    update_frame = true;

    //last_frame_time = micros();
    if (update_frame) {
      matrix.updateDisplay();
      update_frame = false;
    }
    //last_frame_time = micros()-last_frame_time;
  }
}

