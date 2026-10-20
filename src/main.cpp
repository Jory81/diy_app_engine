// Multi-mode firmware: one ESP32 runs either the BBQ controller or the greenhouse controller.
// The mode is chosen in the web page or the companion app (POST /mode) and stored in flash;
// each mode keeps its own settings, so switching back restores the earlier values.

#include <Arduino.h>
#include "common/mode.h"

namespace bbq { void setup(); void loop(); }
namespace greenhouse { void setup(); void loop(); }

static bool greenhouseMode = false;

void setup(){
  migrateSingleModeSettings();
  greenhouseMode = loadMode() == MODE_GREENHOUSE;
  if (greenhouseMode){
    greenhouse::setup();
  }
  else {
    bbq::setup();
  }
}

void loop(){
  if (greenhouseMode){
    greenhouse::loop();
  }
  else {
    bbq::loop();
  }
  handlePendingModeSwitch();
}
