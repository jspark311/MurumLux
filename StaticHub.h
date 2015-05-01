/*
File:   StaticHub.h
Author: J. Ian Lindsay
Date:   2014.07.01


Copyright (C) 2014 J. Ian Lindsay
All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA


This is the testbench version of StaticHub.

*/


#ifndef __STATIC_HUB_H__
#define __STATIC_HUB_H__

#include "FirmwareDefs.h"

  // System-level includes.
  #include <inttypes.h>
  #include <stdlib.h>
  #include <stdarg.h>
  #include <time.h>
  #include <string.h>
  #include <stdio.h>

  #define LOG_EMERG   0    /* system is unusable */
  #define LOG_ALERT   1    /* action must be taken immediately */
  #define LOG_CRIT    2    /* critical conditions */
  #define LOG_ERR     3    /* error conditions */
  #define LOG_WARNING 4    /* warning conditions */
  #define LOG_NOTICE  5    /* normal but significant condition */
  #define LOG_INFO    6    /* informational */
  #define LOG_DEBUG   7    /* debug-level messages */

  #include <ManuvrOS/EventManager.h>
  #include "ManuvrOS/Scheduler.h"
  #include "StringBuilder/StringBuilder.h"

#ifdef __cplusplus
 extern "C" {
#endif 

// Forward-decalre some things we are going to support....

/*
* These are just lables. We don't really ever care about the *actual* integers being defined here. Only
*   their consistency.
*/
#define MANUVR_RTC_STARTUP_UNINITED       0x00000000
#define MANUVR_RTC_STARTUP_UNKNOWN        0x23196400
#define MANUVR_RTC_OSC_FAILURE            0x23196401
#define MANUVR_RTC_STARTUP_GOOD_UNSET     0x23196402
#define MANUVR_RTC_STARTUP_GOOD_SET       0x23196403


/*
* These are constants where we care about the number.
*/
#define STATICHUB_RNG_CARRY_CAPACITY           10     // How many random numbers should StaticHub cache?


/*
* This is the actual class...
*/
class StaticHub : public EventReceiver {
  public:
    volatile static uint32_t millis_since_reset;
    volatile static uint8_t  watchdog_mark;

    static StringBuilder log_buffer;
    
    StaticHub(void);
    static StaticHub* getInstance(void);
    int8_t bootstrap(void);
    
    // These are functions that should be reachable from everywhere in the application.
    volatile static void log(const char *fxn_name, int severity, const char *str, ...);  // Pass-through to the logger class, whatever that happens to be.
    volatile static void log(int severity, const char *str);                             // Pass-through to the logger class, whatever that happens to be.
    volatile static void log(const char *str);                                           // Pass-through to the logger class, whatever that happens to be.
    volatile static void log(char *str);                                           // Pass-through to the logger class, whatever that happens to be.
    volatile static void log(StringBuilder *str);
    
    /*
    * Nice utility functions.
    */
    static uint32_t randomInt(void);                                // Fetches one of the stored randoms and blocks until one is available.
    static volatile bool provide_random_int(uint32_t);              // Provides a new random to StaticHub from the RNG ISR.
    static volatile uint32_t getStackPointer(void);                 // Returns the value of the stack pointer and prints some data.
    
    bool setTimeAndDate(char*);   // Takes a string of the form given by RFC-2822: "Mon, 15 Aug 2005 15:52:01 +0000"   https://www.ietf.org/rfc/rfc2822.txt
    uint32_t currentTimestamp(void);         // Returns an integer representing the current datetime.
    void currentTimestamp(StringBuilder*);   // Same, but writes a string representation to the argument.
    void currentDateTime(StringBuilder*);    // Writes a human-readable datetime to the argument.

    // Call this to accumulate characters from the USB layer into a buffer.
    // Pass terminal=true to cause StaticHub to proc an accumulated command from the host PC.
    void feedUSBBuffer(uint8_t *buf, int len, bool terminal);

    /*
    * These are global resource accessor functions. They are called once from each class that
    *   requires them. That class can technically call this accessor for each use, but this should
    *   be discouraged, as the instances fetched by these functions should never change.
    */
    // Services...
    EventManager* fetchEventManager(void);
    Scheduler* fetchScheduler(void);

    // Volatile statics that serve as ISRs...
    volatile static void advanceScheduler(void);
    

    /* Overrides from EventReceiver */
    const char* getReceiverName();
    void printDebug(StringBuilder*);
    int8_t notify(ManuvrEvent*);
    int8_t callback_proc(ManuvrEvent *);


    void disableLogCallback();


  protected:
    int8_t bootComplete();       // Called as a result of bootstrap completed being raised.

    
  private:
    volatile static StaticHub* INSTANCE;
    volatile static uint32_t next_random_int[STATICHUB_RNG_CARRY_CAPACITY];  // Stores the last 10 random numbers.

    // Global system resource handles...
    EventManager event_manager;            // This is our asynchronous message queue. 
    Scheduler __scheduler;

	StringBuilder usb_rx_buffer;
    StringBuilder last_user_input;

    bool     usb_string_waiting;

    // Scheduler PIDs that will be heavilly used...
    uint32_t pid_log_moderator;
    uint32_t pid_profiler_report;
    uint32_t pid_prog_run_delay;

    uint32_t rtc_startup_state;
    

    // These fxns do string conversion for integer type-codes, and are only useful for logging.
    const char* getRTCStateString(uint32_t code);
    
    void print_type_sizes(void);

    // These functions handle various stages of bootstrap...
    void clock_init(void) volatile;
    void gpioSetup(void) volatile;        // We call this once on bootstrap. Sets up GPIO not covered by other classes.
    void nvicConf(void) volatile;         // We call this once on bootstrap. Sets up IRQs not covered by other classes.
    void init_RNG(void) volatile;         // Fire up the random number generator.
    void initRTC(void) volatile;          // We call this once on bootstrap. Sets up the RTC.
    void initSchedules(void);    // We call this once on bootstrap. Sets up all schedules.
    
    void procDirectDebugInstruction(StringBuilder*);
    
    void off_class_interrupts(bool enable);
    void maskable_interrupts(bool enable);

    // System-wide behavior changes...
    void enableExternalClock(bool on);    // Turn on the external osciallator and switch the system clock to use it.
};

#ifdef __cplusplus
}
#endif 

#endif
