// plasma demo for Adafruit RGBmatrixPanel library.
// Demonstrates unbuffered animation on our 32x32 RGB LED matrix:
// http://www.adafruit.com/products/607

// Written by Limor Fried/Ladyada & Phil Burgess/PaintYourDragon
// for Adafruit Industries.
// BSD license, all text above must be included in any redistribution.


// 

/* DMA code was taken from Keith Vogel's LMBling.
*  This is a terrible mess. I've basically eviscerated the original AdaFruit library and
*  stitched it back together as needed, but there are still guts hanging out.
*/


#include <ManuvrOS.h>
#include <StringBuilder.h>
#include "StaticHub.h"
#include <Arduino.h>

#include <Adafruit_GFX.h>   // Core graphics library
#include <RGBmatrixPanel.h> // Hardware-specific library

uint32_t    tStart  = 0;
uint32_t    led     = HIGH;


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

#define    depth_per_channel 5
#define    panel_width  192
#define    panel_height 16   // Actual panel height is twice this, because we pack bits.
#define    control_bytes_per_row 8

const uint16_t plane_size = panel_height * (panel_width + control_bytes_per_row) * 2;
const uint16_t tail_length = (panel_width + control_bytes_per_row) * 2;
const uint16_t fb_size    = depth_per_channel * plane_size + tail_length;
uint8_t        framebuffer[fb_size];

RGBmatrixPanel matrix(framebuffer, fb_size, false);


void setPixel(int x, int y, uint16_t color) {
  if ((x > 63) || (y > 95)) return;
  uint8_t r = color >> 11;         // RRRRRggggggbbbbb
  uint8_t g = (color >> 6) & 0x1F; // rrrrrGGGGGgbbbbb
  uint8_t b = color & 0x1F;         // rrrrrggggggBBBBB
  
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
  uint16_t planar_offset = y * ((panel_width * 2) + control_bytes_per_row) + (x*2);

  uint8_t temp_byte = 0;
  uint8_t nu_byte   = 0;
  for (int plane = 0; plane < depth_per_channel; plane++) {
    temp_byte = framebuffer[(plane * plane_size)+planar_offset] & ~(0x07 << shift_offset);
    nu_byte   = ((r & 0x01) << shift_offset) + ((g & 0x01) << shift_offset+1) + ((b & 0x01) << shift_offset+2);
    framebuffer[(plane * plane_size)+planar_offset] = nu_byte | temp_byte;
    framebuffer[(plane * plane_size)+planar_offset+1] = nu_byte | temp_byte | 0x40;
    r = r >> 1;
    g = g >> 1;
    b = b >> 1;
  }
}


void setup() {
  Serial.begin(115200);
  
  uint8_t color = 0;

  // We need to init the framebuffer with our clock signals (since we haven't got any
  // broken out on the WiFire).
  
  int total_row_length = (panel_width * 2) + control_bytes_per_row;
  for (int plane = 0; plane < depth_per_channel; plane++) {
    for (int _cur_row = 0; _cur_row < panel_height; _cur_row++) {
      for (int k = 0; k < (panel_width * 2); k+=2) {
        // Zero-out the color information and install the panel clock band...
        framebuffer[((plane * plane_size) + (_cur_row * total_row_length) + k) + 0] = 0;
        framebuffer[((plane * plane_size) + (_cur_row * total_row_length) + k) + 1] = 64;
      }
      
      // Set ABCD and our clock band for the flip flops driving them.
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 0] = _cur_row + 32;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 1] = _cur_row + 32 + 128;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 2] = _cur_row + 16 + 32;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 3] = _cur_row + 16 + 32 + 128;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 4] = _cur_row + 32;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 5] = _cur_row + 32 + 128;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 6] = _cur_row;
      framebuffer[((plane * plane_size) + _cur_row * total_row_length) + (panel_width * 2) + 7] = _cur_row + 128;
    }
  }
  
  for (int i = 0; i < (panel_width * 2); i++) {
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

  //  0  1  2  3  4  5  6   7 
  //                   STB CLK
  // r1 g1 b1 r2 g2 b2
  // A  B  C  D  LA OE
  //
  for (int i = 0; i < panel_height; i++) {
    for (int k = 0; k < (panel_width * 2); k+=2) {
//      framebuffer[(i*total_row_length + k) + 0] = color + (color << 3);
//      framebuffer[(i*total_row_length + k) + 1] = color + (color << 3) + 64;
    }
    
    color = (color + 1) % 8;
  }
  
//  setPixel(50,  19, 0x001F);
//  setPixel(191,  0, 0xFFFF);
//  setPixel(0,    0, 0x7F00);

//  setPixel(51,  19, 0x007F);
//  setPixel(190,  0, 0x07F0);
//  setPixel(0,    1, 0x7F88);

  tStart = millis();

  pinMode(PIN_LED1, OUTPUT); 
  digitalWrite(PIN_LED1, led);

  pinMode(34, OUTPUT); 
  digitalWrite(34, 0);
  digitalWrite(34, 1);  // Hold MS inactive.
}


typedef enum {
    TAKE,
    LOADPAT,
    SHIFT,
    WAIT,
    SPIN
} STATE;

STATE state = TAKE;
uint32_t tWaitShift = 0;
#define MSSHIFT 250

uint32_t    iLoad = 0;


const float radius1  = 16.3, radius2  = 23.0, radius3  = 40.8, radius4  = 44.2,
            centerx1 = 16.1, centerx2 = 11.6, centerx3 = 23.4, centerx4 =  4.1, 
            centery1 =  8.7, centery2 =  6.5, centery3 = 14.0, centery4 = -2.9;
float       angle1   =  0.0, angle2   =  0.0, angle3   =  0.0, angle4   =  0.0;
long        hueShift =  0;


int           x1, x2, x3, x4, _y1, _y2, _y3, _y4, sx1, sx2, sx3, sx4;

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

    angle1 += 0.03;
    angle2 -= 0.07;
    angle3 += 0.13;
    angle4 -= 0.15;
    hueShift += 2;
}



void loop() {
  unsigned char x, y;

  uint32_t tCur;
//  matrix.begin();
  
  int currentx = 0;
  int currenty = 0;
  int currentc = 0x020F;
  uint32_t last_frame_time = 0;
  uint8_t mode = 1;
  
  while (1) {
    tCur = millis();
    
    if (Serial.available()) {
      char c = Serial.read();
      switch (c) {
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
          mode = c - 0x30;
          matrix.fillScreen(0);
          break;
      }
      
    }

    if(tCur - tStart > 30) {
      led ^= HIGH;
      tStart = tCur;
      digitalWrite(PIN_LED1, led);
      if (mode == 1) advance_plasma();
      else if (mode == 2) setPixel(currentx++, currenty, currentc);
      if (currentx == 64) {
        currentx = 0;
        currenty++;
        if (currenty == 96) {
          currenty = 0;
          currentc = (uint16_t) random(millis());
        }
      }
      //Serial.print("Frame period: ");
      //Serial.println(last_frame_time);
      
    }

last_frame_time = micros();
matrix.updateDisplay();
last_frame_time = micros()-last_frame_time;
  }
}

