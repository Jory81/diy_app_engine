#include "mode.h"

#include <EEPROM.h>
#include <Preferences.h>

static const char *PREFS_NAMESPACE = "devmode";
static const char *PREFS_KEY = "mode";

static unsigned long restartAt = 0;

static bool isKnownMode(const String &mode){
  return mode == MODE_BBQ || mode == MODE_GREENHOUSE;
}

String loadMode(){
  Preferences prefs;
  prefs.begin(PREFS_NAMESPACE, true);
  String mode = prefs.getString(PREFS_KEY, MODE_BBQ);
  prefs.end();
  return isKnownMode(mode) ? mode : String(MODE_BBQ);
}

static void saveMode(const String &mode){
  Preferences prefs;
  prefs.begin(PREFS_NAMESPACE, false);
  prefs.putString(PREFS_KEY, mode);
  prefs.end();
}

String modeListJson(){
  return "[\"" MODE_BBQ "\",\"" MODE_GREENHOUSE "\"]";
}

static void sendModeJson(AsyncWebServerRequest *request, const String &mode, bool restarting){
  String json = "{\"mode\":\"" + mode + "\",\"modes\":" + modeListJson()
              + ",\"restarting\":" + (restarting ? "true" : "false") + "}";
  AsyncWebServerResponse *response = request->beginResponse(200, "application/json", json);
  response->addHeader("Access-Control-Allow-Origin", "*");
  request->send(response);
}

void registerModeRoutes(AsyncWebServer &server){
  server.on("/mode", HTTP_GET, [](AsyncWebServerRequest *request){
    sendModeJson(request, loadMode(), false);
  });
  server.on("/mode", HTTP_POST, [](AsyncWebServerRequest *request){
    // set=<mode> as form field or query parameter
    const AsyncWebParameter *param = request->getParam("set", true);
    if (param == nullptr){
      param = request->getParam("set");
    }
    String mode = param ? param->value() : "";
    if (!isKnownMode(mode)){
      request->send(400, "text/plain", "unknown mode");
      return;
    }
    bool changed = mode != loadMode();
    if (changed){
      saveMode(mode);
      restartAt = millis() + 500; // give the response time to reach the phone
    }
    sendModeJson(request, mode, changed);
  });
}

void handlePendingModeSwitch(){
  if (restartAt != 0 && (long)(millis() - restartAt) >= 0){
    ESP.restart();
  }
}

// Copies one EEPROM store into another (both are NVS blobs on the ESP32).
static void copyStore(EEPROMClass &from, const char *toName, size_t size){
  EEPROMClass to(toName);
  if (!to.begin(size)){
    return;
  }
  for (size_t i = 0; i < size; i++){
    to.write(i, from.read(i));
  }
  to.commit();
  to.end();
}

void migrateSingleModeSettings(){
  Preferences prefs;
  prefs.begin(PREFS_NAMESPACE, true);
  bool firstStart = prefs.getString(PREFS_KEY, "") == "";
  prefs.end();
  if (!firstStart){
    return;
  }
  // The single-mode firmwares keep their settings in the default "eeprom" store, recognisable
  // by their check code. Copy them to the store of that mode and start in that mode.
  String mode = MODE_BBQ;
  EEPROMClass legacy("eeprom");
  if (legacy.begin(512)){
    int check = legacy.readInt(0);
    if (check == 11442){        // BBQ controller
      copyStore(legacy, "eeprom_bbq", 255);
      mode = MODE_BBQ;
    }
    else if (check == 10001){   // greenhouse
      copyStore(legacy, "eeprom_gh", 512);
      mode = MODE_GREENHOUSE;
    }
    legacy.end();
  }
  saveMode(mode);
}
