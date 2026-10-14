"""Fake smart-farm gateway used to exercise the dashboard locally.

Speaks the same WebSocket protocol as `gateway.py`: one JSON telemetry frame
per second to every connected client, and it applies control keys the same way
the firmware does, so the app's auto/manual behaviour can be checked without any
hardware attached.

    pip install websockets
    python tool/fake_gateway.py
    flutter run -d chrome --dart-define=GATEWAY_ADDRESS=127.0.0.1:8765
"""

import asyncio
import json
import math
import random

import websockets

PORT = 8765

SOIL_DRY = 600
RAIN_WET = 300

# Mutable state shared with the broadcast loop, mirroring the board's own rules.
state = {
    "soil": 412,
    "rain": 90,
    "temp": 26.4,
    "hum": 61.0,
    "p1_auto": True,
    "p1_state": False,
    "p2_state": False,
    "servo_auto": True,
    "servo_angle": 90,
}

clients = set()


def apply_command(command):
    """Applies a control key exactly the way the firmware does."""
    if "p1_auto" in command:
        state["p1_auto"] = bool(command["p1_auto"])

    # The board reads p1_auto before p1_state within one frame, so a message
    # carrying both always lands in the requested state.
    if "p1_state" in command and not state["p1_auto"]:
        state["p1_state"] = bool(command["p1_state"])

    if "p2_state" in command:
        state["p2_state"] = bool(command["p2_state"])

    if "servo_auto" in command:
        state["servo_auto"] = bool(command["servo_auto"])

    # The firmware ignores servo_angle while auto mode owns the servos.
    if "servo_angle" in command and not state["servo_auto"]:
        state["servo_angle"] = max(90, min(180, int(command["servo_angle"])))

    print("applied", command, flush=True)


def auto_logic():
    """The board's own automatic decisions."""
    if state["p1_auto"]:
        state["p1_state"] = state["soil"] < SOIL_DRY
    if state["servo_auto"]:
        state["servo_angle"] = 0 if state["rain"] >= RAIN_WET else 90


def drift(elapsed):
    """Walks the sensors so the sparklines have something to show."""
    state["soil"] = int(
        470 + 150 * math.sin(elapsed / 9.0) + random.randint(-18, 18)
    )
    state["rain"] = max(
        0, int(90 + 130 * math.sin(elapsed / 14.0) + random.randint(-25, 25))
    )
    state["temp"] = round(
        24.0 + 3.2 * math.sin(elapsed / 22.0) + random.uniform(-0.25, 0.25), 1
    )
    state["hum"] = round(
        58.0 + 9.0 * math.sin(elapsed / 17.0) + random.uniform(-1.2, 1.2), 1
    )


async def handler(socket):
    clients.add(socket)
    print("client connected", flush=True)
    try:
        async for raw in socket:
            # Browsers send text frames, the firmware's bridge sends binary.
            if isinstance(raw, bytes):
                raw = raw.decode(errors="replace")
            for document in raw.splitlines():
                document = document.strip()
                if not document:
                    continue
                try:
                    apply_command(json.loads(document))
                except json.JSONDecodeError:
                    print("bad command:", document, flush=True)
    except Exception as error:
        print("socket closed:", error, flush=True)
    finally:
        clients.discard(socket)


async def broadcast_loop():
    started = asyncio.get_event_loop().time()
    tick = 0
    while True:
        await asyncio.sleep(1)
        tick += 1
        drift(asyncio.get_event_loop().time() - started)
        auto_logic()
        frame = json.dumps(state)
        if clients:
            await asyncio.gather(
                *[client.send(frame) for client in list(clients)],
                return_exceptions=True,
            )
        if tick % 15 == 0:
            print(frame, flush=True)


async def main():
    async with websockets.serve(handler, "0.0.0.0", PORT):
        print(f"fake gateway listening on ws://0.0.0.0:{PORT}", flush=True)
        await broadcast_loop()


if __name__ == "__main__":
    asyncio.run(main())
