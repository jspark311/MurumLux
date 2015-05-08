/*
RGBmatrixPanel Arduino library for Adafruit 16x32 and 32x32 RGB LED
matrix panels.  Pick one up at:
  http://www.adafruit.com/products/420
  http://www.adafruit.com/products/607

This version uses a few tricks to achieve better performance and/or
lower CPU utilization:

- To control LED brightness, traditional PWM is eschewed in favor of
  Binary Code Modulation, which operates through a succession of periods
  each twice the length of the preceeding one (rather than a direct
  linear count a la PWM).  It's explained well here:

    http://www.batsocks.co.uk/readme/art_bcm_1.htm

  I was initially skeptical, but it works exceedingly well in practice!
  And this uses considerably fewer CPU cycles than software PWM.

- Although many control pins are software-configurable in the user's
  code, a couple things are tied to specific PORT registers.  It's just
  a lot faster this way -- port lookups take time.  Please see the notes
  later regarding wiring on "alternative" Arduino boards.

- A tiny bit of inline assembly language is used in the most speed-
  critical section.  The C++ compiler wasn't making optimal use of the
  instruction set in what seemed like an obvious chunk of code.  Since
  it's only a few short instructions, this loop is also "unrolled" --
  each iteration is stated explicitly, not through a control loop.

Written by Limor Fried/Ladyada & Phil Burgess/PaintYourDragon for
Adafruit Industries.
BSD license, all text above must be included in any redistribution.
*/

#include "RGBmatrixPanel.h"
#include "gamma.h"
#include <StringBuilder.h>


#define DMATGTADDR      (&LATE)                 // the DMA target address to write the pattern

#define    MAX_DEPTH_PER_CHANNEL  4
#define    PANEL_WIDTH  192
#define    PANEL_HEIGHT 16   // Actual panel height is twice this, because we pack bits.
#define    CONTROL_BYTES_PER_ROW 6


uint8_t    depth_per_channel = MAX_DEPTH_PER_CHANNEL;

const uint16_t plane_size = PANEL_HEIGHT * ((PANEL_WIDTH*2) + CONTROL_BYTES_PER_ROW);
const uint16_t tail_length = (PANEL_WIDTH*2) + CONTROL_BYTES_PER_ROW;
const uint16_t fb_size    = MAX_DEPTH_PER_CHANNEL * plane_size + tail_length;
uint8_t        framebuffer[fb_size];




  /*
  * If this actually works with no negative side-effects, it might be better
  *   to put it in the avr/interrupts.h file.
  *   http://chipkit.net/forum/viewtopic.php?f=7&t=2508
  *
  * ---J. Ian Lindsay   Mon Mar 16 06:46:38 MST 2015
  */
  static volatile uint32_t __irq_suspend = 0;
  
  void cli() {
    __irq_suspend = disableInterrupts();
  }

  void sei() {
    restoreInterrupts(__irq_suspend);
  }


// Constructor for 32x32 or 32x64 panel:
RGBmatrixPanel::RGBmatrixPanel() :
  Adafruit_GFX(64, 96) {

  matrixbuff[0] = framebuffer;
  matrixbuff[1] = framebuffer;
  // If not double-buffered, both buffers then point to the same address:
  //matrixbuff[1] = (dbuf) ? &matrixbuff[0][buffsize] : matrixbuff[0];

    // Disable Timers and DMA
    T4CON               = 0;
    DCH3CON             = 0;

    uint32_t i = 0;
    uint32_t * pLat = (uint32_t *) (((uint32_t) (DMATGTADDR)) - 0x20);
    uint32_t * pAddr = (uint32_t *) DMATGTADDR;

    // set the tris bits as output
    *pLat &= 0x00;
    *pAddr &= 0x00;  // Set all the output pins to zero.

    //// set up timer 4 
    //T4CONbits.SIDL      = 0;        // operate in idle mode
    //T4CONbits.TGATE     = 0;        // gated time disabled
    //T4CONbits.TCKPS     = 0b000;    // prescaler of 1:1
    //T4CONbits.T32       = 0;        // 16 bit timer
    //T4CONbits.TCS       = 0;        // use PBClk as source; would set this but the SD does not have this bit
    //TMR4                = 0;        // clear the counter2.5 MHz
    //PR4                 = ((__PIC32_pbClk + (TMRFREQ / 2)) / TMRFREQ);  // clock this at TMRFREQ

    // someone else may have already turned this on
    DMACONbits.ON       = 1;                        // ensure the DMA controller is ON

    // Set up DMA channel 3
    DCH3CONbits.CHAED   = 0;                        // do not allow events to be remembered when disabled
    DCH3CONbits.CHAEN   = 1;                        // Disallow continuous operation
    DCH3CONbits.CHPRI   = 0b11;                     // highest priority

    DCH3ECON            = 0;                        // clear it
    //DCH3ECONbits.CHSIRQ = _TIMER_4_VECTOR;          // Timer 4 event
    DCH3ECONbits.SIRQEN = 1;                        // enable IRQ transfer enables
    DCH3INT             = 0;                        // do not trigger any events

    DCH3SSA             = KVA_2_PA(framebuffer); // source address of transfer
    DCH3SSIZ            = fb_size;          // number of bytes in source
    DCH3DSA             = KVA_2_PA(DMATGTADDR);     // destination address is RE0 - RE7
    DCH3DSIZ            = 1;           // CBYTESREQUIRED bytes at the destination
    DCH3CSIZ            = fb_size;           // only transfer CBYTESREQUIRED bytes per event

//    // Set up DMA channel 4
//    DCH4CONbits.CHAED   = 0;                        // do not allow events to be remembered when disabled
//    DCH4CONbits.CHAEN   = 0;                        // Disallow continuous operation
//    DCH4CONbits.CHPRI   = 0b11;                     // highest priority
//
//    DCH4ECON            = 0;                        // clear it
//    DCH4ECONbits.CHSIRQ = _DMA3_VECTOR;          // Timer 4 event
//    DCH4ECONbits.SIRQEN = 1;                        // enable IRQ transfer enables
//    DCH4INT             = 0;                        // do not trigger any events
//
//    DCH4SSA             = KVA_2_PA(fb+(buffsize >> 2)); // source address of transfer
//    DCH4SSIZ            = buffsize >> 2;          // number of bytes in source
//    DCH4DSA             = KVA_2_PA(DMATGTADDR);     // destination address is RE0 - RE7
//    DCH4DSIZ            = 1;           // CBYTESREQUIRED bytes at the destination
//    DCH4CSIZ            = buffsize >> 2;           // only transfer CBYTESREQUIRED bytes per event

  swapflag  = false;
  backindex = 0;     // Array index of back buffer
}

void RGBmatrixPanel::begin(void) {
  backindex   = 0;                         // Back buffer
  buffptr     = matrixbuff[1 - backindex]; // -> front buffer

  _fInit = true;
  cli();                // Enable global interrupts
  sei();                // Enable global interrupts
  //T4CONbits.ON        = 1;    // turn on the timer
  DCH3CONbits.CHEN   = 1;
}


void RGBmatrixPanel::init_fb(int ctl_style) {
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
  // When we write a byte to PORTE that has bit 6 set where it was previously unset, the 
  //   data on bits 0-5 are clocked into the register that drives the control signals indicated.
  // When we write a byte to PORTE that has bit 7 set where it was previously unset, the 
  //   data on bits 0-5 are clocked into the input pins to the shift-registers in the panel.
  // This is a terrible waste of memory and bandwidth unless you have no usable clock signals
  //   broken out on your board. :-(  Fortunately, the PIC32MZ has both memory and bandwidth to burn.
  // There are some practical advantages to this... It means the data stream is inherrently 
  //   self-synchronizing. It also means that we don't need software machinary in an ISR to move the
  //   control signals, nor hardware on a board (except the hex D flipflop).
  //   The net effect is that we only worry about our control signals when we init this render buffer.
  //   As long as the bits we set for control puposes don't get clobbered by a mistake elsewhere, we
  //   can simply point DMA at this buffer and let it run forever. From then on, all changes written
  //   to the render buffer are shown automatically with no further software intervention.
  //
  // The render buffer is setup this way:
  //   C-Frame = "Control frame". Data desined for the panel's control pins (A-D, Strobe, Latch, OE)
  //   D-Frame = "Data frame".    Data desined for the panel's data pins (r0, r1, g0, g1, b0, b1)
  //   TAIL    = The tail frame is a row's worth of meaningless data that we write for timing reasons.
  //
  // /---------|-----------|---------|-----------|---------|-----------|---------|-----------|------\
  // | C-Frame | D-Frame 0 | C-Frame | D-Frame 1 | C-Frame | D-Frame 2 | C-Frame | D-Frame 3 | TAIL |
  // \---------|-----------|---------|-----------|---------|-----------|---------|-----------|------/
  //
  // 
  //
  int ren_buf_idx = 0;  // This is our accumulated index inside of the render buffer.
  for (int plane = 0; plane < depth_per_channel; plane++) {
    
    
    
if (ctl_style == 0) {
    for (int _cur_row = 0; _cur_row < PANEL_HEIGHT; _cur_row++) {
      for (int k = 0; k < PANEL_WIDTH; k++) {
        // Zero-out the D-Frame and install the panel clock band...
        framebuffer[ren_buf_idx++] = 0;
        framebuffer[ren_buf_idx++] = 64;
      }
      
      // Build the C-Frame and its clock band.
      framebuffer[ren_buf_idx++] = _cur_row + 32;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 128;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16 + 128;
      framebuffer[ren_buf_idx++] = _cur_row;
      framebuffer[ren_buf_idx++] = _cur_row + 128;
    }
}



else if (ctl_style == 1) {
    for (int _cur_row = 0; _cur_row < PANEL_HEIGHT; _cur_row++) {
      for (int k = 0; k < PANEL_WIDTH; k++) {
        // Zero-out the D-Frame and install the panel clock band...
        framebuffer[ren_buf_idx++] = 0;
        framebuffer[ren_buf_idx++] = 64;
      }
      
      // Build the C-Frame and its clock band.
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16 + 128;
      framebuffer[ren_buf_idx++] = _cur_row;
      framebuffer[ren_buf_idx++] = _cur_row + 128;
      framebuffer[ren_buf_idx++] = _cur_row;
      framebuffer[ren_buf_idx++] = _cur_row + 128;
    }
}



else if (ctl_style == 2) {
    for (int _cur_row = 0; _cur_row < PANEL_HEIGHT; _cur_row++) {
      for (int k = 0; k < PANEL_WIDTH; k++) {
        // Zero-out the D-Frame and install the panel clock band...
        framebuffer[ren_buf_idx++] = 0;
        framebuffer[ren_buf_idx++] = 64;
      }
      
      // Build the C-Frame and its clock band.
      framebuffer[ren_buf_idx++] = _cur_row + 32;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 128;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16 + 128;
      framebuffer[ren_buf_idx++] = _cur_row;
      framebuffer[ren_buf_idx++] = _cur_row + 128;
    }
}


else {
    for (int _cur_row = 0; _cur_row < PANEL_HEIGHT; _cur_row++) {
      for (int k = 0; k < PANEL_WIDTH; k++) {
        // Zero-out the D-Frame and install the panel clock band...
        framebuffer[ren_buf_idx++] = 0;
        framebuffer[ren_buf_idx++] = 64;
      }
      
      // Build the C-Frame and its clock band.
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16;
      framebuffer[ren_buf_idx++] = _cur_row + 32 + 16 + 128;
      framebuffer[ren_buf_idx++] = _cur_row;
      framebuffer[ren_buf_idx++] = _cur_row + 128;
      framebuffer[ren_buf_idx++] = _cur_row;
      framebuffer[ren_buf_idx++] = _cur_row + 128;
    }
}
  }
  // Here, we are going to set a trailing control sequence to prevent the last-drawn line from being brighter.
  // Without this (or better ISR....) we will be leaving the last row OE until we start another redraw of the panel.  
  for (int i = 0; i < PANEL_WIDTH; i++) {
    framebuffer[ren_buf_idx++] = 0;
    framebuffer[ren_buf_idx++] = 0;
  }
  framebuffer[ren_buf_idx++] = 0;
  framebuffer[ren_buf_idx++] = 0;
  framebuffer[ren_buf_idx++] = 0;
  framebuffer[ren_buf_idx++] = 0;
  framebuffer[ren_buf_idx++] = 32;
  framebuffer[ren_buf_idx++] = 32 + 128;
}





// Original RGBmatrixPanel library used 3/3/3 color.  Later version used
// 4/4/4.  Then Adafruit_GFX (core library used across all Adafruit
// display devices now) standardized on 5/6/5.  The matrix still operates
// internally on 4/4/4 color, but all the graphics functions are written
// to expect 5/6/5...the matrix lib will truncate the color components as
// needed when drawing.  These next functions are mostly here for the
// benefit of older code using one of the original color formats.

// Promote 3/3/3 RGB to Adafruit_GFX 5/6/5
uint16_t RGBmatrixPanel::Color333(uint8_t r, uint8_t g, uint8_t b) {
  // RRRrrGGGgggBBBbb
  return ((r & 0x7) << 13) | ((r & 0x6) << 10) |
         ((g & 0x7) <<  8) | ((g & 0x7) <<  5) |
         ((b & 0x7) <<  2) | ((b & 0x6) >>  1);
}

// Promote 4/4/4 RGB to Adafruit_GFX 5/6/5
uint16_t RGBmatrixPanel::Color444(uint8_t r, uint8_t g, uint8_t b) {
  // RRRRrGGGGggBBBBb
  return ((r & 0xF) << 12) | ((r & 0x8) << 8) |
         ((g & 0xF) <<  7) | ((g & 0xC) << 3) |
         ((b & 0xF) <<  1) | ((b & 0x8) >> 3);
}

// Demote 8/8/8 to Adafruit_GFX 5/6/5
// If no gamma flag passed, assume linear color
uint16_t RGBmatrixPanel::Color888(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 11) | ((g & 0xFC) << 5) | (b >> 3);
}

// 8/8/8 -> gamma -> 5/6/5
uint16_t RGBmatrixPanel::Color888(
  uint8_t r, uint8_t g, uint8_t b, boolean gflag) {
  if(gflag) { // Gamma-corrected color?
    r = pgm_read_byte(&gamma_shift_array[r]); // Gamma correction table maps
    g = pgm_read_byte(&gamma_shift_array[g]); // 8-bit input to 4-bit output
    b = pgm_read_byte(&gamma_shift_array[b]);
    return (r << 12) | ((r & 0x8) << 8) | // 4/4/4 -> 5/6/5
           (g <<  7) | ((g & 0xC) << 3) |
           (b <<  1) | ( b        >> 3);
  } // else linear (uncorrected) color
  return ((r & 0xF8) << 11) | ((g & 0xFC) << 5) | (b >> 3);
}

uint16_t RGBmatrixPanel::ColorHSV(
  long hue, uint8_t sat, uint8_t val, boolean gflag) {

  uint8_t  r, g, b, lo;
  uint16_t s1, v1;

  // Hue
  hue %= 1536;             // -1535 to +1535
  if(hue < 0) hue += 1536; //     0 to +1535
  lo = hue & 255;          // Low byte  = primary/secondary color mix
  switch(hue >> 8) {       // High byte = sextant of colorwheel
    case 0 : r = 255     ; g =  lo     ; b =   0     ; break; // R to Y
    case 1 : r = 255 - lo; g = 255     ; b =   0     ; break; // Y to G
    case 2 : r =   0     ; g = 255     ; b =  lo     ; break; // G to C
    case 3 : r =   0     ; g = 255 - lo; b = 255     ; break; // C to B
    case 4 : r =  lo     ; g =   0     ; b = 255     ; break; // B to M
    default: r = 255     ; g =   0     ; b = 255 - lo; break; // M to R
  }

  // Saturation: add 1 so range is 1 to 256, allowig a quick shift operation
  // on the result rather than a costly divide, while the type upgrade to int
  // avoids repeated type conversions in both directions.
  s1 = sat + 1;
  r  = 255 - (((255 - r) * s1) >> 8);
  g  = 255 - (((255 - g) * s1) >> 8);
  b  = 255 - (((255 - b) * s1) >> 8);

  // Value (brightness) & 16-bit color reduction: similar to above, add 1
  // to allow shifts, and upgrade to int makes other conversions implicit.
  v1 = val + 1;
  if(gflag) { // Gamma-corrected color?
    r = pgm_read_byte(&gamma_shift_array[(r * v1) >> 8]); // Gamma correction table maps
    g = pgm_read_byte(&gamma_shift_array[(g * v1) >> 8]); // 8-bit input to 4-bit output
    b = pgm_read_byte(&gamma_shift_array[(b * v1) >> 8]);
  } else { // linear (uncorrected) color
    r = (r * v1) >> 12; // 4-bit results
    g = (g * v1) >> 12;
    b = (b * v1) >> 12;
  }
  return (r << 12) | ((r & 0x8) << 8) | // 4/4/4 -> 5/6/5
         (g <<  7) | ((g & 0xC) << 3) |
         (b <<  1) | ( b        >> 3);
}


void RGBmatrixPanel::drawPixel(int16_t x, int16_t y, uint16_t color) {
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
  uint16_t planar_offset = (y * (CONTROL_BYTES_PER_ROW + (PANEL_WIDTH * 2))) + (x*2);

  uint8_t temp_byte = 0;
  uint8_t nu_byte   = 0;
  for (int plane = 0; plane < depth_per_channel; plane++) {
    temp_byte = *(framebuffer + (plane * plane_size)+planar_offset) & ~(0x07 << shift_offset);
    nu_byte   = 0;
    if (r>0) nu_byte = nu_byte + (1 << (shift_offset+0));
    if (g>0) nu_byte = nu_byte + (1 << (shift_offset+1));
    if (b>0) nu_byte = nu_byte + (1 << (shift_offset+2));

    *(framebuffer + (plane * plane_size)+planar_offset)   = nu_byte | temp_byte;
    *(framebuffer + (plane * plane_size)+planar_offset+1) = nu_byte | temp_byte | 0x40;
    r = r >> 1;
    g = g >> 1;
    b = b >> 1;
    //r--;
    //g--;
    //b--;
  }
}



void RGBmatrixPanel::fillScreen(uint16_t c) {
  if((c == 0x0000) || (c == 0xffff)) {
    // For black or white, all bits in frame buffer will be identically
    // set or unset (regardless of weird bit packing), so it's OK to just
    // quickly memset the whole thing:
    memset(matrixbuff[backindex], c, _width * nRows * 3);
  } else {
    // Otherwise, need to handle it the long way:
    Adafruit_GFX::fillScreen(c);
  }
}

// Return address of back buffer -- can then load/store data directly
uint8_t *RGBmatrixPanel::backBuffer() {
  return matrixbuff[backindex];
}

// For smooth animation -- drawing always takes place in the "back" buffer;
// this method pushes it to the "front" for display.  Passing "true", the
// updated display contents are then copied to the new back buffer and can
// be incrementally modified.  If "false", the back buffer then contains
// the old front buffer contents -- your code can either clear this or
// draw over every pixel.  (No effect if double-buffering is not enabled.)
void RGBmatrixPanel::swapBuffers(boolean copy) {
  if(matrixbuff[0] != matrixbuff[1]) {
    // To avoid 'tearing' display, actual swap takes place in the interrupt
    // handler, at the end of a complete screen refresh cycle.
    swapflag = true;                  // Set flag here, then...
    while(swapflag == true) delay(1); // wait for interrupt to clear it
    if(copy == true)
      memcpy(matrixbuff[backindex], matrixbuff[1-backindex], _width * nRows * 3);
  }
}

// Dump display contents to the Serial Monitor, adding some formatting to
// simplify copy-and-paste of data as a PROGMEM-embedded image for another
// sketch.  If using multiple dumps this way, you'll need to edit the
// output to change the 'img' name for each.  Data can then be loaded
// back into the display using a pgm_read_byte() loop.
void RGBmatrixPanel::dumpMatrix(void) {
  StringBuilder temp("Dumping FB to console:\n====================================\n");
  int i = 0;
  for (i = 0; i < fb_size; i++) {
    temp.concatf("%02x ", framebuffer[i]);
    if (i%32 == 31) {
      Serial.println((char*) temp.string());
      temp.clear();
    }
  }
  temp.concatf("\n%d bytes dumped.", i);
  Serial.println((char*) temp.string());
}

// -------------------- Interrupt handler stuff --------------------



bool RGBmatrixPanel::takePatternBuffer() {
  if(DMADone()) {
    _fHavePatternBuffer = true;
  }
  return(_fHavePatternBuffer);
}


void RGBmatrixPanel::releasePatternBuffer() {
    RunDMA();
    _tLastRun = millis();
    _fHavePatternBuffer = false;
}



void RGBmatrixPanel::updateDisplay() {
  // periodically run the DMA out
  //if(_fInit && !_fHavePatternBuffer && _updateState == WAITUPD && millis() - _tLastRun >= MSREFRESH && DMADone()) {
  //  releasePatternBuffer();
  //}
  
  if (DMADone()) RunDMA();
  
  //for (int x = 0; x < fb_size; x++) {
  //  LATE = matrixbuff[0][x];
  //}
}


