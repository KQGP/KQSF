#include <Servo.h>
#include <ArduinoJson.h>

#define SOIL_PIN A0
#define RAIN_DIGITAL_PIN 14

#define DHT_PIN 12
#define DHT_TYPE DHT11

#define PUMP1_PIN 5
#define PUMP2_PIN 4

#define SERVO1_PIN 13
#define SERVO2_PIN 15

#define SERVO_TIME 4000

Servo servo1;
Servo servo2;

bool lastRainState = false;

bool pump1AutoMode = true;
bool pump1State = false;
bool pump2State = false;

bool servoAutoMode = true;
int servoAngle = 90;

char lineBuf[96];
size_t lineLen = 0;

void setup() {
  Serial.begin(9600);

  pinMode(PUMP1_PIN, OUTPUT);
  pinMode(PUMP2_PIN, OUTPUT);
  pinMode(RAIN_DIGITAL_PIN, INPUT_PULLUP);

  digitalWrite(PUMP1_PIN, LOW);
  digitalWrite(PUMP2_PIN, HIGH);

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);

  servo1.write(90);
  servo2.write(90);

  delay(500);

  Serial.println("==============================");
  Serial.println("  SMART FARM - SIMULATION MODE");
  Serial.println("==============================");
}

void handleCommand(char* line) {
  Serial.print("[RECV CMD]: ");
  Serial.println(line);

  if (line[0] == '1' || line[0] == '0') {
    if (line[1] == '\0') {
      pump2State = (line[0] == '1');
      digitalWrite(PUMP2_PIN, pump2State ? LOW : HIGH);
    }
    return;
  }

  StaticJsonDocument<256> rxDoc;
  if (deserializeJson(rxDoc, line)) {
    Serial.println("[JSON ERROR]: Failed to parse incoming JSON");
    return;
  }

  if (rxDoc.containsKey("p1_auto")) pump1AutoMode = rxDoc["p1_auto"];
  if (rxDoc.containsKey("p1_state") && !pump1AutoMode) {
    pump1State = rxDoc["p1_state"];
    digitalWrite(PUMP1_PIN, pump1State ? HIGH : LOW);
  }

  if (rxDoc.containsKey("p2_state")) {
    pump2State = rxDoc["p2_state"];
    digitalWrite(PUMP2_PIN, pump2State ? LOW : HIGH);
  }

  if (rxDoc.containsKey("servo_auto")) {
    servoAutoMode = rxDoc["servo_auto"];
    if (servoAutoMode) {
      servoAngle = 90;
      servo1.write(90);
      servo2.write(90);
    }
  }

  if (rxDoc.containsKey("servo_angle") && !servoAutoMode) {
    servoAngle = constrain(rxDoc["servo_angle"].as<int>(), 90, 180);
    servo1.write(servoAngle);
    servo2.write(servoAngle);
  }
}

void loop() {
  int soilValue = random(200, 900);
  int rainValue = random(0, 1024);
  float temperature = random(200, 350) / 10.0;
  float humidity = random(400, 900) / 10.0;

  if (pump1AutoMode) {
    if (soilValue < 600) {
      pump1State = true;
      digitalWrite(PUMP1_PIN, HIGH);
    } else {
      pump1State = false;
      digitalWrite(PUMP1_PIN, LOW);
    }
  }

  bool rainState = rainValue >= 300;

  if (servoAutoMode && rainState && !lastRainState) {
    Serial.println("--> [SIMULATION]: RAIN DETECTED (Servos sweep left)");
    servo1.write(0);
    servo2.write(0);
    delay(500); 
    servo1.write(90);
    servo2.write(90);
    servoAngle = 90;
    lastRainState = true;
  } else if (servoAutoMode && !rainState && lastRainState) {
    Serial.println("--> [SIMULATION]: DRY CONDITIONS (Servos sweep right)");
    servo1.write(180);
    servo2.write(180);
    delay(500);
    servo1.write(90);
    servo2.write(90);
    servoAngle = 90;
    lastRainState = false;
  }

  while (Serial.available() > 0) {
    int c = Serial.read();

    if (c == '\n' || c == '\r') {
      if (lineLen > 0) {
        lineBuf[lineLen] = '\0';
        handleCommand(lineBuf);
      }
      lineLen = 0;
    } else if (lineLen < sizeof(lineBuf) - 1) {
      lineBuf[lineLen++] = (char)c;
    }
  }

  StaticJsonDocument<256> txDoc;
  txDoc["soil"] = soilValue;
  txDoc["rain"] = rainValue;
  txDoc["temp"] = temperature;
  txDoc["hum"] = humidity;

  txDoc["p1_auto"] = pump1AutoMode;
  txDoc["p1_state"] = pump1State;
  txDoc["p2_state"] = pump2State;
  txDoc["servo_auto"] = servoAutoMode;
  txDoc["servo_angle"] = servoAngle;

  serializeJson(txDoc, Serial);
  Serial.println();

  delay(1500);
}