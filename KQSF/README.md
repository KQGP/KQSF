# Smart Farm

A Flutter dashboard for a greenhouse controller: it discovers the gateway on the
local network, streams live telemetry, and drives two pumps and a pair of roof
servos.

## The interface

Two tabs, because reading the farm and changing it are different jobs.

**Dashboard** — read-only. The link status, what the hardware is currently doing,
and the four probes. Each sensor shows three levels of detail: the live value, a
ring gauge placing it against the threshold the firmware actually acts on, and a
two-minute sparkline. A reading like `412` means nothing on its own; the ring
says the board waters below 600, and the trend says it has been climbing.

**Controls** — everything that can change the state of the hardware. The relays
own their own mode: while the board drives a relay the app says so and offers no
switch, because a control that does nothing is worse than no control. Each pump
explains the board's reasoning in a line, and Pump 1 carries the soil trend that
causes it.

The roof is drawn rather than described. The diagram is a cross-section of the
greenhouse: closed, the panels meet on the eaves; open, they swing out and the
widening gap is the ventilation.

Navigation is a bottom bar on a phone and a rail on a wide window. The layout
runs from one column at 390px to four across on a desktop.

## Design

Three files carry the whole visual language, so no widget hard-codes a colour or
a duration:

- `lib/theme/app_tokens.dart` — the spacing scale, the nesting radii, and four
  durations that every transition draws from.
- `lib/theme/farm_palette.dart` — every colour, declared once per brightness and
  exposed as a `ThemeExtension`. Colour is assigned by subsystem: soil, rain,
  temperature, humidity, pumps and roof each own a hue that is used for that
  channel's icon, its gauge and its running state.
- `lib/theme/app_theme.dart` — the two `ThemeData`s. Flat throughout: nothing is
  raised by a shadow, separation comes from a one-pixel outline and a fill a
  shade off the canvas.

Light and dark are both first-class; the toggle in the header switches to
whichever one is not currently on screen, and the switch animates between them.

## Architecture

```
lib/
  models/      FarmTelemetry (wire format) and TelemetryHistory (trend window)
  services/    mDNS discovery and the WebSocket link to the gateway
  state/       FarmController - the single ChangeNotifier both tabs listen to
  theme/       tokens, palette, ThemeData
  views/       AppShell, the two tabs, and the widgets they compose
```

`FarmController` owns the connection, the telemetry, the trend window and the
theme choice, so both tabs share one link and one history buffer. It is
deliberately free of any `BuildContext`: failed commands are queued and drained
by the shell, which keeps the connection logic testable on its own.

`ReadingSeries` is a fixed-capacity ring buffer. A display left open for days
must not grow its memory one sample per second.

## Running it

```sh
flutter run                                              # discovers via mDNS
flutter run --dart-define=GATEWAY_ADDRESS=192.168.8.74:8765   # pinned address
```

mDNS is unavailable on the web build, and Windows cannot resolve a `.local`
name, so the web build needs a pinned address. If a link is built from an
advertised hostname the app says so and offers a one-tap fix.

## Development without hardware

`tool/fake_gateway.py` speaks the same WebSocket protocol as the real gateway:
one telemetry frame per second, with the same auto rules the firmware applies. It
walks the sensors, so the gauges and sparklines have real data to draw.

```sh
pip install websockets
python tool/fake_gateway.py
flutter run -d chrome --dart-define=GATEWAY_ADDRESS=127.0.0.1:8765
```

## Tests

```sh
flutter test
```

Covers the wire format and its lenient parsing, the ring buffer, the palette
contract, each control's behaviour in both modes, and the shell across a range
of window sizes — including that the selected tab survives being resized across
the navigation breakpoint.
