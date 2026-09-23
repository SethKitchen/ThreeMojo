# Windowing and controls

`window/terminal.mojo` and `controls/`. A `TerminalWindow` shows frames in the terminal and reads the keys and the mouse. `OrbitControls` turns that input into a camera that orbits a target. Both use the standard library only.

three.js: a `WebGLRenderer` canvas, and `OrbitControls` from `examples/jsm/controls/`.

Run the example in a terminal:

```bash
make viewer
```

Drag with the left button to orbit. Drag with the right button to pan. Turn the wheel to dolly. Press `q`, Escape or Ctrl+C to quit.

## A loop

```mojo
from controls.orbit_controls import OrbitControls
from core.clock import Clock
from window.terminal import TerminalWindow

var window = TerminalWindow(96, 64)
var controls = OrbitControls(Vector3(0, 0, 0))
var clock = Clock()
while running:
    for event in window.poll(Duration(16.0, MILLISECOND)):
        controls.handle(event, camera, 64)
    _ = controls.update(camera, clock.delta())
    window.present(renderer.render(scene, assets, camera))
window.close()
```

`examples/viewer.mojo` is this loop with a scene, and a key that ends it.

## TerminalWindow

The window is the terminal the program runs in. Mojo's standard library has no window system. The C library's terminal calls are in every process, and `std.ffi.external_call` reaches them.

| Member | Meaning |
|---|---|
| `TerminalWindow(width, height, input_fd=0, output_fd=1)` | Open the window. The size is the frame's, in pixels. |
| `present(frame)` | Draw a `Framebuffer` of the window's size. |
| `poll(timeout) -> List[InputEvent]` | Wait up to a `Duration` for input, and return the events. |
| `request_size()` | Ask the terminal its size. The answer is a `RESIZE` event from a later `poll`. |
| `resize(width, height)` | Take frames of a new size, and clear the screen. three.js: `setSize`. |
| `close()` | Put the terminal back as it was. A second call does nothing. |
| `encode_frame(frame) -> String` | The bytes `present` writes. |

### Two pixels a cell

A terminal cell is about twice as tall as it is wide. Each cell shows two pixels, one above the other. The character is the upper half block `▀`. Its foreground is the top pixel, and its background is the bottom pixel. A frame `width` pixels wide takes `width` columns. A frame `height` pixels high takes `height / 2` rows, rounded up.

The colors are 24-bit escape sequences. Every current terminal draws them. The alpha channel is not shown. A color is sent only where it changes along a row.

### What opening does

Opening puts the terminal in raw mode, so that each key arrives when it is pressed. It switches to the alternate screen and hides the cursor. It asks for xterm's SGR mouse reports of presses, drags and the wheel. `close` undoes all of it. A window that goes out of scope open closes itself.

Raw mode has no signals. Ctrl+C arrives as the key `CTRL_C`, and the program must end its loop on it.

The window never reads `struct termios`, whose layout differs by platform. It asks `tcgetattr` to fill a buffer larger than any platform's, and `cfmakeraw` to change a copy.

### What is refused

- A size that is not positive.
- An input that is not a terminal.
- A frame of another size.
- A negative timeout.
- A `present` or a `poll` after `close`.
- A terminal that cannot be written, or that hung up.

The terminal is put back before a failure is raised.

## Input events

`controls/input.mojo`. An `InputEvent` is one of the five kinds the browser has, or a resize.

| Kind | three.js event | Fields it sets |
|---|---|---|
| `KEY_DOWN` | `keydown` | `key` |
| `POINTER_DOWN` | `pointerdown` | `button`, `x`, `y` |
| `POINTER_MOVE` | `pointermove` | `button` held or `NO_BUTTON`, `x`, `y` |
| `POINTER_UP` | `pointerup` | `button`, `x`, `y` |
| `WHEEL` | `wheel` | `wheel`: 1 a notch toward the user, -1 away |
| `RESIZE` | the window's `resize` | `x` and `y`: the size of the largest frame that fits |

Every event also carries `shift`, `alt` and `ctrl`. The window gives `x` and `y` in the frame's pixels. The decoder gives a cell's column and row, from zero.

`InputKind`, `PointerButton` and `Key` are types, not bare integers. A `Key` is an ASCII code from 0 to 127, one of `ARROW_UP`, `ARROW_DOWN`, `ARROW_LEFT` and `ARROW_RIGHT`, or `NO_KEY`. The buttons are `PRIMARY`, `MIDDLE` and `SECONDARY`, with the browser's numbers.

### The decoder

`InputDecoder.feed(bytes)` turns a terminal's bytes into events.

- A byte below 128 is its key. A byte above is dropped.
- An escape that ends the bytes is the Escape key.
- `ESC [ A` to `ESC [ D` are the arrows. `ESC [ 1 ; m A` carries modifiers.
- `ESC [ < b ; x ; y M` is a press, a drag or a wheel notch. The same with `m` is a release.
- A sequence cut off before its end is kept for the next call.
- `ESC [ 8 ; rows ; columns t` is the terminal's size, a `RESIZE` in columns and rows.
- A sequence the decoder does not know is dropped.

## OrbitControls

`controls/orbit_controls.mojo`. The controls orbit a camera around `target`. `handle` adds the change one event asks for to what is pending. `update` applies what is pending and places the camera. Call `update` once a frame.

| Input | Change |
|---|---|
| Left drag | Rotate. A drag the height of the view is a whole turn. |
| Middle drag | Dolly. Down moves away. |
| Right drag | Pan. The point under the pointer stays under it. |
| Wheel | Dolly by 0.95 a notch. |
| Arrow | Pan by `key_pan_speed` pixels. |
| Shift or Ctrl with an arrow | Rotate. |
| Shift or Ctrl with a left or right drag | The drag's rotate and pan swap. |

| Member | Default | Meaning |
|---|---|---|
| `target` | the origin | The point the camera orbits and looks at. |
| `enabled` | `True` | False ignores all input. |
| `min_distance`, `max_distance` | 0, infinity | How near and how far the camera can be, as a `Length`. |
| `min_polar_angle`, `max_polar_angle` | 0, a half turn | How far down from straight above, as an `Angle`. |
| `min_azimuth_angle`, `max_azimuth_angle` | minus and plus infinity | The limits about y, as an `Angle`. |
| `enable_damping`, `damping_factor` | `False`, 0.05 | Let a change die away over frames. |
| `enable_rotate`, `rotate_speed` | `True`, 1 | |
| `enable_zoom`, `zoom_speed` | `True`, 1 | |
| `enable_pan`, `pan_speed` | `True`, 1 | |
| `key_pan_speed` | 7 | Pixels an arrow pans by. |
| `auto_rotate`, `auto_rotate_speed` | `False`, 2 | Turns a minute while no button is held. |
| `primary_action`, `middle_action`, `secondary_action` | `ROTATE`, `DOLLY`, `PAN` | What each button does. three.js: `mouseButtons`. |
| `min_zoom`, `max_zoom` | 0, infinity | How far an orthographic camera can zoom. |
| `zoom_to_cursor` | `False` | Dolly or zoom toward the point under the pointer. |

`rotate_left`, `rotate_up`, `dolly_in`, `dolly_out` and `pan` make the same changes from code. `update(camera, delta)` returns True when the camera moved. The `delta` is a `Duration`, for the automatic rotation.

### The arithmetic

The camera's offset from the target is a radius and two angles, as three.js's `Spherical` holds them. `theta` turns about y from +z. `phi` goes down from +y. A rotation adds to the angles, and a dolly scales the radius. A pan moves the target and the camera together.

The polar angle stays a millionth of a radian away from each pole. At a pole, the camera's right is undefined. A range about y with its low limit above its high limit passes through a half turn. An angle outside it goes to the nearer limit, as in three.js.

With damping, `damping_factor` of each pending rotation and pan applies each frame. The rest waits. A dolly is not damped, as in three.js.

### Orthographic cameras

`handle(event, camera, width, height)`, `update(camera, delta)` and `pan(dx, dy, camera, width, height)` take an `OrthographicCamera` too. A dolly changes the camera's `zoom` rather than its distance, kept between `min_zoom` and `max_zoom`. A pan moves by the extent the volume covers at that zoom, over the view's size, as three.js's `pan` measures it.

### Zoom to the cursor

With `zoom_to_cursor` set, a wheel notch or a dolly drag goes toward the point under the pointer. A perspective camera moves down the ray through the pointer by what the dolly takes off the distance. An orthographic camera moves so that the point under the pointer stays under it as the zoom changes. The target then sits straight ahead of the camera at the new distance, as in three.js.

### The camera's up

The offset is turned into a frame whose y is the camera's `up` before it is read as angles, as three.js turns it. So the polar angle is measured from the camera's up, and a camera with +z up orbits about z.

### Differences from three.js

- Touch input and a limit on the target's radius are not ported.
- Panning is always in screen space, three.js's default.

## Limits

The window asks the terminal its size with xterm's `ESC [ 18 t`, which works on every platform, where `ioctl` does not. A terminal that does not answer sends no `RESIZE`. Give such a terminal a size that fits: a terminal smaller than the frame wraps or cuts it. `examples/viewer.mojo` asks once a second and follows the answer.

The window needs a terminal that speaks xterm's sequences. The current terminals on Linux and macOS do, and so does Windows Terminal under WSL 2.

A frame is drawn in full every time. The example's frame of 96 by 64 pixels is about 20 kilobytes. A frame whose every pixel differs from its neighbor is about 120 kilobytes.
