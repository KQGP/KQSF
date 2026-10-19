# KQSF — Smart Farm

A **smart farm automation system**: an Arduino firmware reads soil moisture, rain, temperature/humidity (DHT11) and controls pumps and servo-operated roof covers; a Python gateway bridges the serial link to WebSocket (mDNS discovery); a Flutter app monitors and controls everything.

## ✨ Features

- 🌱 Soil moisture monitoring + auto pump control
- 🌧️ Rain detection → servo roof open/close (4s cycle)
- 🌡️ Temperature & humidity (DHT11)
- 💧 Manual pump 2 control
- 🔄 Manual/auto modes for pump 1 and servos
- 📡 Serial ↔ WebSocket gateway with mDNS (`_smartfarm._tcp`)
- 📱 Flutter app (dashboard, controls, connection bar)

## 🧱 Tech Stack

- **Firmware:** Arduino (DHT, Servo, ArduinoJson)
- **Gateway:** Python (pyserial, websockets, zeroconf)
- **App:** Flutter (Dart) in `app/`

## 📁 Project Structure

```
KQSF.ino       # Arduino firmware
KQSF.py        # Serial→WebSocket gateway
app/           # Flutter app
test/          # Test sketches/scripts
```

## 🚀 Getting Started

### Firmware
1. Open `KQSF.ino` in Arduino IDE.
2. Upload to the board (9600 baud).
3. Wire sensors/actuators per pin definitions.

### Gateway
```bash
pip install pyserial websockets zeroconf
python KQSF.py
```
The gateway auto-detects the serial port and advertises via mDNS on port 8765.

### Flutter App
```bash
cd app
flutter pub get
flutter run
```
