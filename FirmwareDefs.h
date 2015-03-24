/*
File:   FirmwareDefs.h
Author: J. Ian Lindsay
Date:   2015.03.01

This is one of the files that the application author is required to provide. This is where definition of
  (application or device)-specific event codes ought to go. We also define some fields that will be used
  during communication with other devices, so some things here are mandatory.

*/

#ifndef __FIRMWARE_DEFS_H
#define __FIRMWARE_DEFS_H


/*
* These are required fields.
*
* PROTOCOL_MTU is required for constraining communication length due to memory restrictions at
*   one-or-both sides. Since the protocol currently supports up to (2^24)-1 bytes in a single transaction,
*   a microcontroller would want to limit it's counterparty's use of precious RAM. PROTOCOL_MTU, therefore,
*   determines the effective maximum packet size for this device.
*/
#define PROTOCOL_MTU              20000                  // See MTU notes above....
#define VERSION_STRING            "0.0.3"                // We should be able to communicate version so broken behavior can be isolated.
#define HW_VERSION_STRING         "0"                    // Because we are strictly-software, we report as such.
#define IDENTITY_STRING           "MurumLux"             // Might also be a hash....
#define EXTENDED_DETAIL_STRING    ""                     // Optional. User-defined.



/* Codes that are specific to MurumLux */
  #define MURUM_LUX_WHEEL_CLOCKWISE            0x9100 // 
  #define MURUM_LUX_WHEEL_COUNTER_CLOCKWISE    0x9101 // 
  #define MURUM_LUX_GESTURE_0                  0x9102 // 
  #define MURUM_LUX_GESTURE_1                  0x9103 // 
  #define MURUM_LUX_GESTURE_2                  0x9104 // 
  #define MURUM_LUX_GESTURE_3                  0x9105 // 
  #define MURUM_LUX_GESTURE_APPROACH           0x9106 // 
  #define MURUM_LUX_TAP                        0x9107 // 
  #define MURUM_LUX_DOUBLE_TAP                 0x9108 // 

  /* Note: intentional conflict with ViamSonus. */
  #define MURUM_LUX_MSG_AMBIENT_LIGHT_LEVEL    0x9030 // 
  #define MURUM_LUX_MSG_ADC_SCAN               0x9040 // 



#ifdef __cplusplus
extern "C" {
#endif

// Function prototypes
volatile void jumpToBootloader(void);
volatile void reboot(void);

unsigned long millis(void);
unsigned long micros(void);


#ifdef __cplusplus
}
#endif

#endif
