import asyncio
import json
import random
import socket
import time

import websockets
from zeroconf.asyncio import AsyncZeroconf, AsyncServiceInfo

WS_PORT = 8765

SERVICE_TYPE = "_smartfarm._tcp.local."
SERVICE_NAME = "Smart Farm Gateway._smartfarm._tcp.local."

SOIL_THRESHOLD = 600
RAIN_THRESHOLD = 300

SERVO_REST_ANGLE = 90
SERVO_OPEN_ANGLE = 180
SERVO_RAIN_ANGLE = 0
SERVO_TIME_MS = 4000

CONNECTED_CLIENTS = set()

state = {
    "soil": 700,
    "rain": 100,
    "temp": 24.5,
    "hum": 60.0,
    "p1_auto": True,
    "p1_state": False,
    "p2_state": False,
    "servo_auto": True,
    "servo_angle": SERVO_REST_ANGLE,
}

servo_move = {"active": False, "started": 0.0, "angle": SERVO_REST_ANGLE}
last_rain_state = False


def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


LOCAL_IP = get_local_ip()


async def broadcast(message):
    if not CONNECTED_CLIENTS:
        return
    await asyncio.gather(
        *(client.send(message) for client in list(CONNECTED_CLIENTS)),
        return_exceptions=True,
    )


def set_pump2(turn_on):
    state["p2_state"] = bool(turn_on)


def set_servo_angle(angle):
    angle = max(SERVO_REST_ANGLE, min(SERVO_OPEN_ANGLE, int(angle)))
    state["servo_angle"] = angle
    servo_move["active"] = False


def park_servos():
    state["servo_angle"] = SERVO_REST_ANGLE


def set_servo_auto(enabled):
    state["servo_auto"] = bool(enabled)
    if enabled:
        park_servos()
        servo_move["active"] = False


def start_servo_move(angle):
    """Drive the cover to one end of travel and park it back after SERVO_TIME."""
    state["servo_angle"] = angle
    servo_move.update(active=True, started=time.monotonic(), angle=angle)


def tick_servo(now):
    if not servo_move["active"]:
        return
    if (now - servo_move["started"]) * 1000 >= SERVO_TIME_MS:
        servo_move["active"] = False
        park_servos()


def apply_command(command):
    if "p1_auto" in command:
        state["p1_auto"] = bool(command["p1_auto"])
    if "p1_state" in command and not state["p1_auto"]:
        state["p1_state"] = bool(command["p1_state"])

    if "p2_state" in command:
        set_pump2(command["p2_state"])

    if "servo_auto" in command:
        set_servo_auto(command["servo_auto"])
    if "servo_angle" in command and not state["servo_auto"]:
        set_servo_angle(command["servo_angle"])


def drift_sensors():
    global last_rain_state

    state["soil"] = max(0, min(1023, state["soil"] + random.randint(-15, 15)))
    state["rain"] = max(0, min(1023, state["rain"] + random.randint(-10, 10)))
    state["temp"] = round(
        max(15.0, min(40.0, state["temp"] + random.uniform(-0.5, 0.5))), 1
    )
    state["hum"] = round(
        max(30.0, min(90.0, state["hum"] + random.uniform(-1.0, 1.0))), 1
    )

    if state["p1_auto"]:
        state["p1_state"] = state["soil"] < SOIL_THRESHOLD

    rain_state = state["rain"] >= RAIN_THRESHOLD
    if state["servo_auto"] and rain_state != last_rain_state:
        start_servo_move(SERVO_RAIN_ANGLE if rain_state else SERVO_OPEN_ANGLE)
        last_rain_state = rain_state


async def board_loop():
    while True:
        tick_servo(time.monotonic())
        drift_sensors()
        await broadcast(json.dumps(state))
        await asyncio.sleep(1)


async def ws_handler(websocket):
    CONNECTED_CLIENTS.add(websocket)
    print(f"\n[APP CONNECTED] Client from {websocket.remote_address}")
    try:
        async for message in websocket:
            if isinstance(message, bytes):
                message = message.decode("utf-8", errors="ignore")

            text = message.strip()
            if not text:
                continue

            if text in ("0", "1"):
                set_pump2(text == "1")
                print(f"[COMMAND] pump 2 -> {text}")
                continue

            try:
                command = json.loads(text)
                if isinstance(command, dict):
                    apply_command(command)
                    print(f"[COMMAND] {text}")
                else:
                    print("[WARNING] Ignored a non-object command")
            except json.JSONDecodeError:
                print(f"[WARNING] Ignored a non-JSON command: {text}")
    except Exception as exc:  # noqa: BLE001 - one bad client must not kill the server
        print(f"[APP] Connection error: {exc}")
    finally:
        CONNECTED_CLIENTS.discard(websocket)
        print("[APP DISCONNECTED] Client disconnected.")


async def main():
    aiozeroconf = AsyncZeroconf()
    info = AsyncServiceInfo(
        SERVICE_TYPE,
        SERVICE_NAME,
        addresses=[socket.inet_aton(LOCAL_IP)],
        port=WS_PORT,
        properties={"version": "1.0", "ip": LOCAL_IP, "port": str(WS_PORT)},
        server="smartfarm.local.",
    )

    await aiozeroconf.async_register_service(info)
    print(f"[mDNS] Advertising 'Smart Farm Gateway' at {LOCAL_IP}:{WS_PORT}")
    print("[SIMULATOR] No board required — serving generated telemetry.")

    background = [asyncio.create_task(board_loop())]

    async with websockets.serve(ws_handler, "0.0.0.0", WS_PORT):
        print("[SERVER] Simulator online. Waiting for app connections…")
        try:
            await asyncio.Future()
        finally:
            for task in background:
                task.cancel()
            await aiozeroconf.async_unregister_service(info)
            await aiozeroconf.async_close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Simulator stopped.")