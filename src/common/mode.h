// Mode selection shared by all modes of the multi-mode firmware.
#pragma once

#include <Arduino.h>
#include <ESPAsyncWebServer.h>

// mode names, as used by /mode, /info and the companion app
#define MODE_BBQ "bbq"
#define MODE_GREENHOUSE "greenhouse"

String loadMode();                               // mode to start, from flash ("bbq" by default)
String modeListJson();                           // ["bbq","greenhouse"]
void registerModeRoutes(AsyncWebServer &server); // GET /mode, POST /mode (set=<mode>)
void handlePendingModeSwitch();                  // restarts after a mode switch; call from loop()
void migrateSingleModeSettings();                // keep settings of a previously flashed single-mode firmware
