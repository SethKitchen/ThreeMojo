# Gamepads

`extensions/gamepad/` reads Xbox, PlayStation, Nintendo and other game controllers on Linux. It is a port of the gamepad subsystem of [SDL](https://github.com/libsdl-org/SDL) 3.2.24. It names each control by its position, so one program works with every pad.

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
| `linux.mojo` | The device calls: `list_event_nodes`, `probe_joystick`, `EvdevGamepad` and `open_gamepads`. |

SDL: `src/joystick/SDL_gamepad.c`, `SDL_joystick.c`, `controller_type.c`, `SDL_gamepad_db.h` and `linux/SDL_sysjoystick.c`.

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

The user must have read access to `/dev/input/event*`. Most desktop systems give it to the user at the seat. `open_gamepads` does not watch for new devices. Call it again to find a pad that was plugged in later. A pad that is unplugged sets `gone`.

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

- The HIDAPI drivers, which talk to some pads without the kernel driver.
- Rumble, LEDs, motion sensors and touchpads.
- The classic `js` joystick interface, and trackballs.
- Hotplug through udev or inotify.
- The delay SDL adds to a short press of the guide button.
- Drivers for other systems. The types, the mappings and `Gamepad` work on every system. A host can feed a `Joystick` from its own API.

## Tests

The tests compare against SDL 3.2.24, built from source.

- `tests/test_gamepad_ids.mojo`: GUIDs, CRCs, controller types, labels and device names.
- `tests/test_gamepad_mapping.mojo`: mapping strings, CRCs, hints, priorities and the built-in database.
- `tests/test_gamepad.mojo`: a scripted pad, step by step, against SDL's virtual joystick.
- `tests/test_gamepad_evdev.mojo`: recorded devices against SDL's own Linux driver. The SDL run linked the driver with wrappers for `open`, `ioctl`, `read` and `fstat` that answer from the same tables.
