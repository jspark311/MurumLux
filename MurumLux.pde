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

bool update_frame = true;

RGBmatrixPanel matrix;



void blackout() {
  /* Until the render buffer is torn off the top of the framebuffer, we
     do this to prevent nasty artifacts. */
  matrix.haltDMA();
  while (!matrix.DMADone()) {}

  for (int a = 0; a < 64; a++) {
    for (int b = 0; b < 96; b++) {
      matrix.drawPixel(a, b, 0);
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
    matrix.drawPixel(((a)/96), (95-((a)%96)), *((uint16_t*)ptr_cast+a));
  }
}


void draw_cursor(int x, int y, uint16_t color) {
  matrix.drawPixel(x, y, color);
  uint8_t i = 0;
  for (uint8_t i = 1; i < 3; i++) {
    if ((x+i) < 96) matrix.drawPixel(x+i, y, color);
    if ((x-i) >= 0) matrix.drawPixel(x-i, y, color);
    if ((y+i) < 96) matrix.drawPixel(x, y+i, color);
    if ((y-i) >= 0) matrix.drawPixel(x, y-i, color);
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
      matrix.drawPixel(x, y, matrix.ColorHSV(value * 3, 255, 255, true));
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
  for(int j = GOL_BOARD_HEIGHT; j < (GOL_BOARD_HEIGHT*2); j++) {
    for(int i = GOL_BOARD_WIDTH; i < (GOL_BOARD_WIDTH*2); i++) {
      if(choice == 'm') {
        //The Moore neighborhood checks all 8 cells surrounding the current cell in the array.
        int count = 0;
        count = array[(j-1)%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] + 
	  array[(j-1)%GOL_BOARD_HEIGHT][(i-1) % GOL_BOARD_WIDTH] +
	  array[j%GOL_BOARD_HEIGHT][(i-1) % GOL_BOARD_WIDTH] +
	  array[(j+1)%GOL_BOARD_HEIGHT][(i-1) % GOL_BOARD_WIDTH] +
	  array[(j+1)%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] +
	  array[(j+1)%GOL_BOARD_HEIGHT][(i+1) % GOL_BOARD_WIDTH] +
	  array[j%GOL_BOARD_HEIGHT][(i+1) % GOL_BOARD_WIDTH] +
          array[(j-1)%GOL_BOARD_HEIGHT][(i+1) % GOL_BOARD_WIDTH];

        if(count < 2 || count > 3) temp[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] = 0;  //The cell dies.
        else if(count == 2) temp[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] = array[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH];  //The cell stays the same.
        else if(count == 3) temp[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] = 1;  //The cell either stays alive, or is "born".
      }

      else if(choice == 'v') {
        //The Von Neumann neighborhood checks only the 4 surrounding cells in the array,
        //(N, S, E, and W).
        int count = 0;
        count = array[(j-1)%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] +
          array[j%GOL_BOARD_HEIGHT][(i-1) % GOL_BOARD_WIDTH] +
          array[(j+1)%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] +
          array[j%GOL_BOARD_HEIGHT][(i+1) % GOL_BOARD_WIDTH];  
          
        if(count < 2 || count > 3) temp[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] = 0; //The cell dies.
        else if(count == 2) temp[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] = array[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH];    //The cell stays the same.
        else if(count == 3) temp[j%GOL_BOARD_HEIGHT][i % GOL_BOARD_WIDTH] = 1;   //The cell either stays alive, or is "born".
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
        matrix.drawPixel(j, i, (bu[j][i]) ? 0x0FF0 : 0x0617);
      }
      else {
        matrix.drawPixel(j, i, (bu[j][i]) ? 0xC000 : 0);
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
uint8_t currentx = 0;
uint8_t currenty = 0;
uint16_t currentc = 0x020F;

uint8_t mode = 6;

// TODO: Replace these with the Scheduler.
uint32_t time_until_action = 9001;
uint32_t action_time_marker = 9001;
  


int8_t process_string_from_counterparty(StringBuilder* in) {
  if (in == NULL) return -1;
  if (in->length() < 11) return -2;
  
  StringBuilder output;
  int8_t return_value = 0;
  const char* test = (const char*) in->string();

  if (strcasestr(test, "ATCHVAR ")) {
    // This sure looks like it should be here....
    int variable = atoi((const char*) (test+8));
    switch (variable) {
      
      case 1:   // Position from e-field box.
        in->cull(10);
        if (in->split(",") == 3) {
          // Remember... The e-field box is not kinked 90-degrees.
          currentx = 63 - (((uint16_t) in->position_as_int(1)) >> 10);   // 63 max.
          currenty = 95 - (((uint16_t) in->position_as_int(0)) / 683);   // 96 max.
          currentc = ((uint16_t) in->position_as_int(2));
          
          switch (mode) {
            case 3:
              break;
            case 5:
              //output.concatf("%s %s %s    %d %d %d    %d %d 0x%04x\n", in->position(1), in->position(0), in->position(2), (uint16_t) in->position_as_int(1), (uint16_t) in->position_as_int(0), (uint16_t) in->position_as_int(2), currentx, currenty, currentc);
              draw_cursor(currentx, currenty, 0xF81F);
            case 4:
              todo[currentx][currenty] = 1;
              break;
          }
        }
        else {
          output.concat("This is not enough broccolis.");
        }
        break;
        
      case 2:   // Airwheel
        break;
        
      case 3:   // Swipe direction
        output.concatf("Swipe 0x02x\n", atoi(test+10));
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
        output.concatf("Tap 0x02x\n", atoi(test+10));
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
        output.concatf("Double Tap 0x02x\n", atoi(test+10));
        break;
      case 6:   // Touch direction
        {
          int touch_val = atoi(test+10);
          output.concatf("Touch 0x02x\n", atoi(test+10));
          switch (mode) {
            case 4:  // Suspend GoL if we are using it.
              if (touch_val) mode = 5;
              break;
            case 5:  // Resume GoL when touch is relinquished.
              if (0 == touch_val) mode = 4;
              break;
          }
        }
        break;

      case 7:   // Special event
        break;
        
      case 9:   // Module commands
        break;
    }
  }
  if (output.length() > 0) Serial.print((char*) output.string());
  return return_value;
}





void setup() {
  pinMode(39, INPUT); 

  Serial.begin(115200);
  Serial1.begin(115200);
  matrix.init_fb(0);
  tStart = millis();

  pinMode(PIN_LED1, OUTPUT); 
  digitalWrite(PIN_LED1, led);

  // This is the reset pin for the flip-flop. We toggle it once, and never again. Piping the framebuffer
  //   into the panel will keep it in-sync if something happens.
  pinMode(34, OUTPUT); 
  digitalWrite(34, 0);
  digitalWrite(34, 1);  // Hold MS inactive.
  
  generate_random_gol_state();
  mode = 4;
}


void loop() {
  unsigned char x, y;

  uint32_t tCur;
//  matrix.begin();
  
  uint32_t last_frame_time = 0;
  
  const char* logo_list[] = {chipkit_logo, microchip_logo, mpide_logo, manuvr_logo};
  
  uint8_t logo_up = 3;

  int frame_rate = 20;

  set_logo(logo_list[3]);
  set_logo(logo_list[3]);
  mode = 5;

  while (1) {
    tCur = millis();
    
    if (Serial.available()) {
      char c = Serial.read();
      if ((c >= 0x30) && (c < 0x3A)) mode = (c - 0x30);
      
      switch (c) {
        case 'd':
          matrix.dumpMatrix();
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
          matrix.init_fb(0);
          matrix.init_fb(0);
          set_logo(logo_list[3]);
          set_logo(logo_list[3]);
        case 'q':
          mode = 0;
          break;
        case '1':
          matrix.init_fb(1);
          matrix.init_fb(1);
          set_logo(logo_list[3]);
          set_logo(logo_list[3]);
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
          matrix.init_fb(2);
          matrix.init_fb(2);
          set_logo(logo_list[3]);
          set_logo(logo_list[3]);
          break;
        case '8':
          matrix.init_fb(3);
          matrix.init_fb(3);
          set_logo(logo_list[3]);
          set_logo(logo_list[3]);
          break;
        case '9':
          set_logo(logo_list[logo_up % 4]);
          set_logo(logo_list[logo_up % 4]);
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
          matrix.drawPixel(currentx % 64, currentx/64, currentc);
          currentx++;
          if (currentx % 16 == 15) {
            currentc = (uint16_t) random(millis());
          }
          break;
        case 2:   // Coherent noise.
          advance_plasma();
          break;
        case 3:   // Paint mode.
          matrix.drawPixel(currentx, currenty, currentc);
          break;
        case 4:   // GoL
          advance_gol_states();
          break;

        case 9:   // Logo cycle
          if(millis() - action_time_marker > time_until_action) {
            set_logo(logo_list[logo_up % 4]);
            set_logo(logo_list[logo_up % 4]);
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

