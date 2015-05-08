#include "pins_arduino.h"

#if ARDUINO >= 100
  #include "Arduino.h"
#else
  #include "WProgram.h"
#endif
  
#if defined(MPIDE)
  #include <p32xxxx.h>    /* this gives all the CPU/hardware definitions */
#endif

#include "Adafruit_GFX.h"

#define MSREFRESH       30                      // how many milliseconds between refreshing
#define TMRFREQ         2500000                 // 2.5 MHz, do not run over 6MHz as the DMA can't keep up


    typedef enum {
        WAITUPD,
        INIT,
        CONVGRB,
        ENDUPD
    } UST;

#define KVA_2_PA(v) (((uint32_t) (v)) & 0x1fffffff)

    
class RGBmatrixPanel : public Adafruit_GFX {
  public:
    RGBmatrixPanel();

    void begin();
    void drawPixel(int16_t x, int16_t y, uint16_t c);
    void fillScreen(uint16_t c);
    void updateDisplay();
    bool takePatternBuffer();
    void releasePatternBuffer();
    inline void     RunDMA() {    DCH3CONbits.CHEN = 1;        }
    inline uint32_t DMADone() {   return(!DCH3CONbits.CHEN);   }
    inline void haltDMA() {       DCH3CONbits.CHEN = 0;        }
  
    void init_fb(int ctl_style);


    void swapBuffers(boolean);
    void dumpMatrix(void);
    uint8_t* backBuffer(void);
  
    uint16_t Color333(uint8_t r, uint8_t g, uint8_t b);
    uint16_t Color444(uint8_t r, uint8_t g, uint8_t b);
    uint16_t Color888(uint8_t r, uint8_t g, uint8_t b);
    uint16_t Color888(uint8_t r, uint8_t g, uint8_t b, boolean gflag);
    uint16_t ColorHSV(long hue, uint8_t sat, uint8_t val, boolean gflag);

  private:
    bool            _fInit;
    bool            _fInvert;
    bool            _fHavePatternBuffer;
    
    uint16_t        fb_size;
    uint32_t        _cDevices;
    uint32_t        _iNextDevice;
    uint8_t *       _pPatternBuffer;
    uint32_t        _cbPatternBuffer;
    uint32_t        _iStr;
    uint8_t *       _pb;
    uint8_t         _mask;
    UST             _updateState;
    uint32_t        _tLastRun;

    uint8_t         *matrixbuff[2];
    uint8_t          nRows;
    volatile uint8_t backindex;
    volatile boolean swapflag;
    
    

  // PORT register pointers, pin bitmasks, pin numbers:
#if defined(MPIDE)  // This is the conditional for the ChipKIT series.
  volatile uint32_t  *latport;
  volatile uint32_t  *oeport;
  volatile uint32_t  *addraport;
  volatile uint32_t  *addrbport;
  volatile uint32_t  *addrcport;
  volatile uint32_t  *addrdport;
#else
  volatile uint8_t* latport;
  volatile uint8_t* oeport;
  volatile uint8_t* addraport;
  volatile uint8_t* addrbport;
  volatile uint8_t* addrcport;
  volatile uint8_t* addrdport;
#endif

  // Counters/pointers for interrupt handler:
  volatile uint8_t row, plane;
  volatile uint8_t *buffptr;
};

