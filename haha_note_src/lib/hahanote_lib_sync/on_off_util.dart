
const valueOn = "ON";
const valueOff = "OFF";
const valuesOnAndOff = [valueOn, valueOff];

String boolToOnOff(bool value) {
  return value ? valueOn : valueOff;
}

bool onOffToBool(String value) {
  return value == valueOn;
}
