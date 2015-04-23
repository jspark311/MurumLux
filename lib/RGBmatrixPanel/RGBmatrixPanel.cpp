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

#define DMATGTADDR      (&LATE)                 // the DMA target address to write the pattern

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
RGBmatrixPanel::RGBmatrixPanel(uint8_t* fb, uint16_t buffsize, boolean dbuf, uint8_t width) :
  Adafruit_GFX(width, 32) {

  matrixbuff[0] = fb;
  matrixbuff[1] = fb;
  fb_size = buffsize;
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

    // set up timer 4 
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
    DCH3CONbits.CHAEN   = 1;                        // Allow continuous operation
    DCH3CONbits.CHPRI   = 0b11;                     // highest priority

    DCH3ECON            = 0;                        // clear it
    //DCH3ECONbits.CHSIRQ = _TIMER_4_VECTOR;          // Timer 4 event
    DCH3ECONbits.SIRQEN = 1;                        // enable IRQ transfer enables
    DCH3INT             = 0;                        // do not trigger any events

    DCH3SSA             = KVA_2_PA(fb); // source address of transfer
    DCH3SSIZ            = buffsize;          // number of bytes in source
    DCH3DSA             = KVA_2_PA(DMATGTADDR);     // destination address is RE0 - RE7
    DCH3DSIZ            = 1;           // CBYTESREQUIRED bytes at the destination
    DCH3CSIZ            = buffsize;           // only transfer CBYTESREQUIRED bytes per event

  swapflag  = false;
  backindex = 0;     // Array index of back buffer
}

void RGBmatrixPanel::begin(void) {
  backindex   = 0;                         // Back buffer
  buffptr     = matrixbuff[1 - backindex]; // -> front buffer

  _fInit = true;
  //cli();                // Enable global interrupts
  //sei();                // Enable global interrupts
  //T4CONbits.ON        = 1;    // turn on the timer
  DCH3CONbits.CHEN   = 1;
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

void RGBmatrixPanel::drawPixel(int16_t x, int16_t y, uint16_t c) {
  uint8_t r, g, b, bit, limit, *ptr;
  
  if((x < 0) || (x >= _width) || (y < 0) || (y >= _height)) return;

  uint8_t panel_number = (x/32);

  switch(rotation) {
   case 1:
    swap(x, y);
    x = WIDTH  - 1 - x;
    break;
   case 2:
    x = WIDTH  - 1 - x;
    y = HEIGHT - 1 - y;
    break;
   case 3:
    swap(x, y);
    y = HEIGHT - 1 - y;
    break;
  }

  // Adafruit_GFX uses 16-bit color in 5/6/5 format, while matrix needs
  // 4/4/4.  Pluck out relevant bits while separating into R,G,B:
  r =  c >> 12;        // RRRRrggggggbbbbb
  g = (c >>  7) & 0xF; // rrrrrGGGGggbbbbb
  b = (c >>  1) & 0xF; // rrrrrggggggBBBBb

  // Loop counter stuff
  bit   = 2;
  //limit = 1 << nPlanes;

  if(y < nRows) {
    // Data for the upper half of the display is stored in the lower
    // bits of each byte.
    //ptr = &matrixbuff[backindex][y * WIDTH * (nPlanes - 1) + x]; // Base addr

    // Plane 0 is a tricky case -- its data is spread about,
    // stored in least two bits not used by the other planes.
    ptr[_width*2] &= ~B00000011;            // Plane 0 R,G mask out in one op
    if(r & 1) ptr[_width*2] |=  B00000001;  // Plane 0 R: 64 bytes ahead, bit 0
    if(g & 1) ptr[_width*2] |=  B00000010;  // Plane 0 G: 64 bytes ahead, bit 1
    if(b & 1) ptr[_width] |=  B00000001;  // Plane 0 B: 32 bytes ahead, bit 0
    else      ptr[_width] &= ~B00000001;  // Plane 0 B unset; mask out
    // The remaining three image planes are more normal-ish.
    // Data is stored in the high 6 bits so it can be quickly
    // copied to the DATAPORT register w/6 output lines.
    for(; bit < limit; bit <<= 1) {
      *ptr &= ~B00011100;             // Mask out R,G,B in one op
      if(r & bit) *ptr |= B00000100;  // Plane N R: bit 2
      if(g & bit) *ptr |= B00001000;  // Plane N G: bit 3
      if(b & bit) *ptr |= B00010000;  // Plane N B: bit 4
      ptr  += WIDTH;                  // Advance to next bit plane
    }
  } else {
    // Data for the lower half of the display is stored in the upper
    // bits, except for the plane 0 stuff, using 2 least bits.
    //ptr = &matrixbuff[backindex][(y - nRows) * WIDTH * (nPlanes - 1) + x];
    *ptr &= ~B00000011;               // Plane 0 G,B mask out in one op
    if(r & 1)  ptr[_width] |=  B00000010; // Plane 0 R: 32 bytes ahead, bit 1
    else       ptr[_width] &= ~B00000010; // Plane 0 R unset; mask out
    if(g & 1) *ptr     |=  B00000001; // Plane 0 G: bit 0
    if(b & 1) *ptr     |=  B00000010; // Plane 0 B: bit 0
    for(; bit < limit; bit <<= 1) {
      *ptr &= ~B11100000;             // Mask out R,G,B in one op
      if(r & bit) *ptr |= B00100000;  // Plane N R: bit 5
      if(g & bit) *ptr |= B01000000;  // Plane N G: bit 6
      if(b & bit) *ptr |= B10000000;  // Plane N B: bit 7
      ptr  += WIDTH;                  // Advance to next bit plane
    }
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
  int i, buffsize = _width * nRows * 3;

  Serial.print("\n\n"
    "#include <avr/pgmspace.h>\n\n"
    "static const uint8_t PROGMEM img[] = {\n  ");

  for(i=0; i<buffsize; i++) {
    Serial.print("0x");
    if(matrixbuff[backindex][i] < 0x10) Serial.print('0');
    Serial.print(matrixbuff[backindex][i],HEX);
    if(i < (buffsize - 1)) {
      if((i & 7) == 7) Serial.print(",\n  ");
      else             Serial.print(',');
    }
  }
  Serial.println("\n};");
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
  
  //for (int x = 0; x < fb_size; x++) LATE = matrixbuff[0][x];
}

