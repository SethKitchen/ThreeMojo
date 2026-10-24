# Gamepads

`extensions/gamepad/` reads Xbox, PlayStation, Nintendo and other game controllers. It is a port of the gamepad subsystem of [SDL](https://github.com/libsdl-org/SDL) 3.2.24. It names each control by its position, so one program works with every pad. It runs the pads' rumble, lights, motion sensors and touchpads. It finds pads as they are plugged in.

There are three backends:

- Linux: evdev for every pad, and SDL's HIDAPI drivers for DualSense, DualShock 4, Switch Pro and Xbox pads on hidraw.
- A browser: SDL's Emscripten driver behind the C ABI. The page reads the Gamepad API.
- macOS: the window host reads the GameController framework and feeds the same C ABI.

| Module | What it holds |
|---|---|
| `ids.mojo` | `GamepadButton`, `GamepadAxis`, `GamepadType`, `GamepadButtonLabel` and `FaceStyle`, with SDL's mapping names. |
| `guid.mojo` | `JoystickGuid`: the 16 bytes that name a kind of device, and its CRC-16. |
| `controller_type.mojo` | SDL's table of 539 known controllers, and the gamepad type of a vendor and product. |
| `names.mojo` | The name SDL gives a device, and the devices it does not treat as gamepads. |
| `mapping.mojo` | Mapping strings, `GamepadBinding` and the `MappingDatabase`. |
| `linux_mappings.mojo` | SDL's 317 built-in Linux mappings. |
| `joystick.mojo` | `Joystick`: the raw axes, buttons and hats, and their events. |
| `gamepad.mojo` | `Gamepad`: a joystick read through a mapping, and `GamepadEvent`. |
| `evdev.mojo` | The Linux evdev logic: device classes, axis scaling, hats, events and the automatic mapping. |
| `linux.mojo` | The device calls: `list_event_nodes`, `probe_joystick`, `EvdevGamepad`, `open_gamepads` and `EvdevHub`. |
| `effects.mojo` | When SDL sends rumble and light changes: `RumbleState` and `LedState`. |
| `hid.mojo` | The HID transport: `HidSource`, `HidrawFile` and `enumerate_hidraw`. |
| `hid_device.mojo` | `HidapiDevice`, what a HIDAPI driver knows about a device. |
| `hidapi.mojo` | `HidGamepad`, `HidHub`, the choice of driver and the mapping SDL makes for a HIDAPI pad. |
| `hid_ps5.mojo`, `hid_ps4.mojo`, `hid_switch.mojo`, `hid_xboxone.mojo` | The four HIDAPI drivers. |
| `web.mojo` | `WebHub`: the pads a browser or another host gives. |

SDL: `src/joystick/SDL_gamepad.c`, `SDL_joystick.c`, `controller_type.c`, `SDL_gamepad_db.h`, `linux/SDL_sysjoystick.c`, `emscripten/SDL_sysjoystick.c` and `hidapi/`.

## Read a gamepad

`open_gamepads` opens each gamepad in `/dev/input`. `update` reads the device and returns the events since the last call.

```mojo
from extensions.gamepad.gamepad import GAMEPAD_BUTTON_DOWN
from extensions.gamepad.ids import AXIS_LEFTX, AXIS_LEFTY, BUTTON_WEST
from extensions.gamepad.linux import default_mapping_database, open_gamepads

var database = default_mapping_database()
var pads = open_gamepads(database)
for ref pad in pads:
    for event in pad.update():
        if event.kind == GAMEPAD_BUTTON_DOWN and event.button == BUTTON_WEST:
            attack()
    var forward = -pad.gamepad.get_axis(AXIS_LEFTY)
    var right = pad.gamepad.get_axis(AXIS_LEFTX)
```

A stick axis is from -32768 to 32767. Up on a stick is negative. A trigger is from 0 to 32767. A button event comes once for each press, so an attack starts on `GAMEPAD_BUTTON_DOWN`.

The user must have read access to `/dev/input/event*`. Most desktop systems give it to the user at the seat. Write access lets a pad rumble.

## Find pads as they come and go

`EvdevHub` and `HidHub` keep a list of pads. Call `detect` each frame. It returns the pads that were added and removed. A hub scans its folder when the folder changed, at most every 3 seconds, as SDL does without udev.

```mojo
var database = default_mapping_database()
var hid = HidHub[HidrawFile]()
var evdev = EvdevHub[EvdevFile]()
while running:
    _ = hid.detect(database)
    _ = evdev.detect(database, hid.claimed())
    for index in range(len(hid.pads)):
        for event in hid.pads[index].update():
            ...
```

Give `hid.claimed()` to the evdev hub. The kernel also shows a HIDAPI pad as an evdev device, and SDL reads each pad once. `examples/gamepad.mojo` runs both hubs.

A hidraw node is often readable only by root. A udev rule gives the user at the seat access. Steam installs such rules for its controllers.

## Rumble, lights and sensors

```mojo
_ = pad.rumble(0xFFFF, 0x8000, Duration64(0.25, SECOND))  # low, high, duration
_ = pad.set_led_at(0, 64, 255, pad.now())                  # HIDAPI pads only
_ = pad.set_sensor_enabled(SENSOR_GYRO, True)
var turn = pad.pad.value().angular_velocity(SENSOR_GYRO, 0)  # AngularVelocity
```

A strength is from 0 to 65535. A duration of zero rumbles until the next call. SDL sends a running rumble again every 2 seconds and stops it when the duration ends. `update` does both.

The evdev backend rumbles through the kernel's force feedback. The HIDAPI drivers write the pad's own output reports, so they also set the light bar and the player lights. A HIDAPI pad shows its player number when it connects.

A gyroscope reads in radians per second, and an accelerometer in meters per second squared. A touchpad finger is from 0 to 1 across and down. `GAMEPAD_TOUCHPAD_DOWN`, `GAMEPAD_TOUCHPAD_MOTION` and `GAMEPAD_TOUCHPAD_UP` report a finger. `GAMEPAD_SENSOR_UPDATE` reports a reading.

## The HIDAPI drivers

| Driver | Pads | Links |
|---|---|---|
| `hid_ps5.mojo` | DualSense, DualSense Edge, and compatible pads | USB, Bluetooth |
| `hid_ps4.mojo` | DualShock 4, the Sony wireless adapter, and compatible pads | USB, Bluetooth |
| `hid_switch.mojo` | Switch Pro Controller and compatible pads | USB, Bluetooth |
| `hid_xboxone.mojo` | Xbox One and Xbox Series pads | Bluetooth |

A wired Xbox pad speaks GIP on a vendor interface, not HID. hidapi reaches it only through libusb, so the evdev backend reads it, with the kernel's `xpad` driver. Joy-Cons and the other Nintendo pads are not ported.

## A browser

`window/capi_gamepad.mojo` is a C ABI library for a host that has its own gamepad API. Each frame, the host stages each pad's state in the browser's standard layout and samples it. The library maps the pads with SDL's `Standard Gamepad` mapping. The app reads the pads by SDL's names, and asks the host to play each rumble. `window/threemojo.h` lists the functions.

`examples/capi/web/gamepad.js` is the page's half. Run it with `examples/capi/run.sh web gamepad`. The frame shows the first pad's sticks, triggers and buttons. Its south button rumbles it.

## macOS

The macOS window host feeds the same library from the GameController framework: `examples/capi/macos_gamepad.m`. It reads every controller that has an extended gamepad profile, on USB and Bluetooth. It plays rumble with Core Haptics. Run it with `examples/capi/run.sh native gamepad`.

The Mojo HID transport does not open IOKit devices. The coverage gate runs on Linux, and an IOKit transport in Mojo could not be measured there. So on macOS the pads give the standard layout, without the lights, the sensors and the touchpads.

## Buttons by position

`BUTTON_SOUTH` is the bottom face button on every pad: A on Xbox, Cross on PlayStation, B on Nintendo. `button_label` gives the printed label.

| Button | Xbox | PlayStation | Nintendo |
|---|---|---|---|
| `BUTTON_SOUTH` | A | Cross | B |
| `BUTTON_EAST` | B | Circle | A |
| `BUTTON_WEST` | X | Square | Y |
| `BUTTON_NORTH` | Y | Triangle | X |

The type comes from the mapping's `type:` field, or from the vendor and product id. A DualSense is `GAMEPAD_TYPE_PS5`.

## Mappings

A mapping string binds joystick inputs to gamepad controls. SDL's format is used unchanged:

```text
030000004c050000e60c000011010000,PS5 Controller,a:b1,b:b2,leftx:a0,dpup:h0.1,...
```

`default_mapping_database` holds SDL's built-in Linux mappings. Add the community file `gamecontrollerdb.txt` with `add_mappings_from_text`. It adds the lines for the platform `Linux`.

A pad in the kernel's gamepad layout needs no mapping. The kernel drivers for Xbox and PlayStation pads use that layout. `automatic_mapping` writes the mapping from the buttons and axes the driver reports, as SDL does.

## Differences from SDL

Two results differ from SDL 3.2.24. Each is an upstream defect with a test of the corrected result.

- A labeled mapping, with `hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1`, has its face buttons swapped into positions. SDL 3.2.24 searches for `x:` anywhere, so it swaps `leftx` and `lefty` and leaves `x` and `y`. This port searches for `,x:`, as SDL's main branch does from commit `3da8c67d`.
- An analog d-pad hat gets half-axis bindings, such as `dpup:-a7` and `dpdown:+a7`. SDL binds both directions to the whole axis. Then all four directions read as pressed at rest. SDL's main branch at `3da8c67d` still does this.

The port ignores three events that make SDL read or write outside its arrays. They are key code `KEY_MAX`, axis code `ABS_MAX`, and relative motion with no relative axes.

SDL's hints are not ported. The three Linux hints are arguments of `EvdevGamepad`: `use_deadzones`, `use_hat_deadzones` and `digital_hats`. A mapping's `hint:` field is read at its default value. The program has no keyboard focus, so no events are dropped.

## What is not ported

- The HIDAPI drivers other than the four above: Joy-Cons, Steam, Stadia, Luna, Shield, GameCube, Wii and PS3 pads.
- libusb, so wired Xbox pads on HIDAPI.
- The classic `js` joystick interface, and trackballs.
- Hotplug through udev or inotify. The hubs poll the device folder instead.
- The delay SDL adds to a short press of the guide button.
- `SDL_SendGamepadEffect`, the raw effect reports of the PlayStation pads.
- Windows. The Windows Subsystem for Linux uses the Linux backend.

## Tests

The tests compare against SDL 3.2.24, built from source.

- `tests/test_gamepad_ids.mojo`: GUIDs, CRCs, controller types, labels and device names.
- `tests/test_gamepad_mapping.mojo`: mapping strings, CRCs, hints, priorities and the built-in database.
- `tests/test_gamepad.mojo`: a scripted pad, step by step, against SDL's virtual joystick.
- `tests/test_gamepad_evdev.mojo`: recorded devices against SDL's own Linux driver. The SDL run linked the driver with wrappers for `open`, `ioctl`, `read` and `fstat` that answer from the same tables.
- `tests/test_gamepad_hid.mojo`: the hidraw transport on a made sysfs tree, and the HIDAPI device record.
- `tests/test_gamepad_ps5.mojo`, `test_gamepad_ps4.mojo`, `test_gamepad_switch.mojo` and `test_gamepad_xboxone.mojo`: scripts of device reports against SDL's own HIDAPI drivers. The SDL run linked the drivers with wrappers for the `SDL_hid_*` calls, the clock and the rumble thread. Both sides print one transcript, and a test compares the two whole. `tests/_gamepad_hid_script.mojo` runs a script.
- `tests/test_gamepad_web.mojo` and `tests/test_capi_gamepad.mojo`: the browser driver and its C ABI.
