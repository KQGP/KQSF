#include <DHT.h>
#include <Servo.h>
#include <ArduinoJson.h>


#define SOIL_PIN A0
#define RAIN_PIN A1

#define DHT_PIN 10
#define DHT_TYPE DHT11

#define PUMP1_PIN 8
#define PUMP2_PIN 9

#define SERVO1_PIN 3
#define SERVO2_PIN 4

#define SOIL_THRESHOLD 600
#define RAIN_THRESHOLD 300

#define SERVO_TIME 4000

DHT dht(DHT_PIN, DHT_TYPE);

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

  digitalWrite(PUMP1_PIN, LOW);

  digitalWrite(PUMP2_PIN, HIGH);

  dht.begin();

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);

  servo1.write(90);
  servo2.write(90);

  delay(500);

  Serial.println("==============================");
  Serial.println("        SMART FARM");
  Serial.println("==============================");

  Serial.println("Soil Sensor -> A0");
  Serial.println("Rain Sensor -> A1");
  Serial.println("DHT11       -> D10");

  Serial.println("Pump 1      -> D8");
  Serial.println("Pump 2      -> D9");

  Serial.println("Servo 1     -> D3");
  Serial.println("Servo 2     -> D4");

  Serial.println("==============================");
  Serial.println("Pump 2: 1 = ON / 0 = OFF");
  Serial.println("==============================");
}

void handleCommand(char* line) {

  if (line[0] == '1' || line[0] == '0') {
    if (line[1] == '\0') {
      pump2State = (line[0] == '1');
      digitalWrite(PUMP2_PIN, pump2State ? LOW : HIGH);
    }
    return;
  }

  StaticJsonDocument<256> rxDoc;
  if (deserializeJson(rxDoc, line)) return;

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

  int soilValue = analogRead(SOIL_PIN);

  if (!pump1AutoMode) {
  } else if (soilValue < SOIL_THRESHOLD) {

    pump1State = true;

    digitalWrite(PUMP1_PIN, HIGH);

  } else {

    pump1State = false;

    digitalWrite(PUMP1_PIN, LOW);
  }

  int rainValue = analogRead(RAIN_PIN);

  bool rainState = rainValue >= RAIN_THRESHOLD;

  if (servoAutoMode && rainState && !lastRainState) {

    Serial.println("RAIN >= 300");
    Serial.println("SERVOS -> LEFT");
    Serial.println("TIME = 4 SECONDS");

    servo1.write(0);
    servo2.write(0);

    delay(SERVO_TIME);

    servo1.write(90);
    servo2.write(90);

    servoAngle = 90;

    lastRainState = true;
  }

  if (servoAutoMode && !rainState && lastRainState) {

    Serial.println("DRY < 300");
    Serial.println("SERVOS -> RIGHT");
    Serial.println("TIME = 4 SECONDS");

    servo1.write(180);
    servo2.write(180);

    delay(SERVO_TIME);

    servo1.write(90);
    servo2.write(90);

    servoAngle = 90;

    lastRainState = false;
  }

  float temperature = dht.readTemperature();
  float humidity = dht.readHumidity();

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
  txDoc["temp"] = isnan(temperature) ? 0.0 : temperature;
  txDoc["hum"] = isnan(humidity) ? 0.0 : humidity;

  txDoc["p1_auto"] = pump1AutoMode;
  txDoc["p1_state"] = pump1State;

  txDoc["p2_state"] = pump2State;

  txDoc["servo_auto"] = servoAutoMode;
  txDoc["servo_angle"] = servoAngle;

  serializeJson(txDoc, Serial);
  Serial.println();

  delay(1000);
}