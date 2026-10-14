import asyncio
import json
import socket

import serial
import serial.tools.list_ports
import websockets
from zeroconf.asyncio import AsyncZeroconf, AsyncServiceInfo

BAUD_RATE = 9600
WS_PORT = 8765

SERVICE_TYPE = "_smartfarm._tcp.local."
SERVICE_NAME = "Smart Farm Gateway._smartfarm._tcp.local."

HEARTBEAT = {
    "soil": 0,
    "rain": 0,
    "temp": 0.0,
    "hum": 0.0,
    "p1_auto": True,
    "p1_state": False,
    "p2_state": False,
    "servo_auto": True,
    "servo_angle": 90,
}

CONNECTED_CLIENTS = set()
ser = None

HEARTBEAT_JSON = json.dumps(HEARTBEAT)

TELEMETRY_KEYS = frozenset(HEARTBEAT)


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


def auto_detect_serial_port():
    physical = []
    for p in serial.tools.list_ports.comports():
        hwid = p.hwid.lower()
        desc = p.description.lower()
        if "bthenum" in hwid or "bluetooth" in desc:
            continue
        physical.append(p)

    if not physical:
        return None

    for p in physical:
        desc = p.description.lower()
        if any(k in desc for k in ("arduino", "ch340", "ft232", "cp210", "usb serial", "cdc")):
            return p.device

    return physical[0].device


async def serial_connection_manager():
    global ser
    announced_waiting = False
    while True:
        if ser is None or not ser.is_open:
            port = auto_detect_serial_port()
            if port:
                try:
                    ser = serial.Serial(port, BAUD_RATE, timeout=1)
                    print(f"\n[SERIAL] Connected to board on {port}")
                    announced_waiting = False
                except Exception:
                    ser = None
            elif not announced_waiting:
                print("\n[SERIAL] Waiting for the board (plug in USB)…")
                announced_waiting = True
        await asyncio.sleep(2)


async def broadcast(message):
    if not CONNECTED_CLIENTS:
        return
    await asyncio.gather(
        *(client.send(message) for client in list(CONNECTED_CLIENTS)),
        return_exceptions=True,
    )


async def serial_to_clients():
    global ser
    loop = asyncio.get_running_loop()
    while True:
        if ser is None or not ser.is_open:
            await asyncio.sleep(0.5)
            continue

        try:
            line = await loop.run_in_executor(None, ser.readline)
        except (serial.SerialException, OSError):
            print("\n[SERIAL] Link lost, waiting for the board…")
            try:
                if ser:
                    ser.close()
            except Exception:
                pass
            ser = None
            continue

        if not line:
            continue

        text = line.decode("utf-8", errors="ignore").strip()
        if text.startswith("{") and text.endswith("}"):
            await broadcast(text)


async def clients_to_serial(websocket):
    global ser
    async for message in websocket:
        if isinstance(message, bytes):
            message = message.decode("utf-8", errors="ignore")

        if ser is None or not ser.is_open:
            print("[GATEWAY] Command dropped — the board is not connected.")
            continue

        try:
            ser.write((message.strip() + "\n").encode("utf-8"))
        except (serial.SerialException, OSError):
            print("[GATEWAY] Failed to write to the board — link lost.")
            try:
                if ser:
                    ser.close()
            except Exception:
                pass
            ser = None


async def ws_handler(websocket):
    CONNECTED_CLIENTS.add(websocket)
    print(f"\n[APP CONNECTED] Client from {websocket.remote_address}")
    try:
        await clients_to_serial(websocket)
    except Exception as exc:
        print(f"[APP] Connection error: {exc}")
    finally:
        CONNECTED_CLIENTS.discard(websocket)
        print("[APP DISCONNECTED] Client disconnected.")


async def heartbeat_loop():
    while True:
        if ser is None or not ser.is_open:
            await broadcast(HEARTBEAT_JSON)
        await asyncio.sleep(1)


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

    background = [
        asyncio.create_task(serial_connection_manager()),
        asyncio.create_task(serial_to_clients()),
        asyncio.create_task(heartbeat_loop()),
    ]

    async with websockets.serve(ws_handler, "0.0.0.0", WS_PORT):
        print("[SERVER] Gateway online. Waiting for app connections…")
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
        print("\n[SHUTDOWN] Gateway stopped.")
        if ser and ser.is_open:
            ser.close()