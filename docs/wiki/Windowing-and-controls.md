# Windowing and controls

`window/terminal.mojo` and `controls/`. A `TerminalWindow` shows frames in the terminal and reads the keys and the mouse. The controls turn that input into a camera that moves. All of them use the standard library only.

| Controls | Module | The camera |
|---|---|---|
| `OrbitControls` | `controls/orbit_controls.mojo` | Orbits a target, with poles. |
| `MapControls` | `controls/map_controls.mojo` | Pans over the ground, and orbits. |
| `TrackballControls` | `controls/trackball_controls.mojo` | Turns about a target with no poles, and can roll over the top. |
| `FlyControls` | `controls/fly_controls.mojo` | Flies and rolls on its own axes. |
| `FirstPersonControls` | `controls/first_person_controls.mojo` | Walks, and turns toward the pointer. |
| `PointerLockControls` | `controls/pointer_lock_controls.mojo` | Turns by the pointer's movement, and walks. |

three.js: a `WebGLRenderer` canvas, and the controls of the same names in `examples/jsm/controls/`. `ArcballControls` is not ported.

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

## X11Window

`window/x11.mojo` opens a native window on an X server. It loads `libX11.so.6` when the window opens. Nothing else in the project needs the library.

| Member | Meaning |
|---|---|
| `X11Window(width, height, title="ThreeMojo", display="")` | Open the window. An empty `display` uses the `DISPLAY` variable. |
| `present(frame)` | Draw a `Framebuffer` of the window's size. |
| `poll(timeout) -> List[InputEvent]` | Wait up to a `Duration` for input, and return the events. |
| `resize(width, height)` | Take frames of a new size. |
| `close()` | Close the window. A second call does nothing. |
| `close_requested` | True after the window manager asks the window to close. |

The window gives the same `InputEvent` values as `TerminalWindow`. The same loop drives both. A key press is `KEY_DOWN`, and Ctrl with a letter is its control code, as a terminal sends it. A change of size is a `RESIZE` event. The program must call `resize` to follow it.

The window manager's close button does not close the window. It sets `close_requested`, and the program must end its loop on it.

### What is refused

- A size that is not positive.
- A display that cannot be opened.
- A display whose visual is not 24-bit TrueColor with red in the high byte.
- A frame of another size.
- A `present`, a `poll` or a `resize` after `close`.

### Tests

`tests/test_x11.mojo` starts an `Xvfb` server for each test. You must install it first, for example with `apt-get install xvfb`.

## Input events

`controls/input.mojo`. An `InputEvent` is one of the six kinds the browser has, or a resize.

| Kind | three.js event | Fields it sets |
|---|---|---|
| `KEY_DOWN` | `keydown` | `key` |
| `KEY_UP` | `keyup` | `key`. A terminal never sends it. |
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

### Panning over the ground

`screen_space_panning` is `True` by default, as in three.js. A pan up the view then moves the target up the view. Set it to `False` to move the target forward instead, in the plane at right angles to the camera's `up`. A zoom to the cursor then keeps the target on that plane. A camera within 20 degrees of level keeps its target, as in three.js.

### Differences from three.js

- Touch input and a limit on the target's radius are not ported.

## MapControls

`controls/map_controls.mojo`. `MapControls(target)` returns an `OrbitControls` with three.js's map settings. Every member and method is `OrbitControls`'s.

| Setting | Value |
|---|---|
| `primary_action` | `PAN` |
| `middle_action` | `DOLLY` |
| `secondary_action` | `ROTATE` |
| `screen_space_panning` | `False` |

A drag with the left button moves over the ground. A drag with the right button orbits.

## Held keys

A terminal sends no key-up event. The controls that move while a key is held count the key as held until `key_timeout` goes by with no repeat. `controls/held_keys.mojo` keeps this record.

- A `KEY_DOWN` holds the key, or starts its time again.
- A `KEY_UP` lets the key go at once. A source that knows when a key goes up can send it.
- `update` lets go of each key that did not repeat within `key_timeout`.
- A capital letter is its small letter. `W` with Shift is `w`, as three.js's `event.code` names the key.

The default `key_timeout` is 0.3 seconds, a `Duration`. A keyboard repeats a held key about 30 times a second, so a held key stays held. Most keyboards wait about half a second before the first repeat. A held key therefore moves, stops for a moment, then moves steadily. Set `key_timeout` to 0.6 seconds to remove the stop. A longer timeout makes the camera coast after the key goes up.

## FlyControls

`controls/fly_controls.mojo`. The camera moves along its own axes and turns about them. `handle(event, width, height)` changes what is held. `update(camera, delta)` moves and turns the camera for the time `delta`.

| Input | Change |
|---|---|
| `W`, `S` | Forward, back. |
| `A`, `D` | Left, right. |
| `R`, `F` | Up, down. |
| Up and down arrows | Pitch up, pitch down. |
| Left and right arrows | Yaw left, yaw right. |
| `Q`, `E` | Roll left, roll right. |
| Left button, right button | Forward, back. |
| Pointer | Yaw and pitch by its distance from the middle of the view. |

| Member | Default | Meaning |
|---|---|---|
| `movement_speed` | 1 m/s | A `Velocity`. |
| `roll_speed` | 0.01 rad/s | An `AngularVelocity`. |
| `drag_to_look` | `False` | Turn only while a button is held. The buttons then do not move. |
| `auto_forward` | `False` | Move forward with nothing held. |
| `key_timeout` | 0.3 s | See [Held keys](#held-keys). |

A turn is three.js's quaternion `(x, y, z, 1)`, normalized. Here `x`, `y` and `z` are the pitch, yaw and roll held, times half of `roll_speed` and the time. three.js's `rollSpeed` is that half. Its default of 0.005 is 0.01 radians a second here, the same turn.

A roll changes the camera's `up`. The target stays ahead of the camera at the same distance. `update` returns `True` when the camera moved or turned past three.js's threshold.

three.js sets a speed multiplier on Shift and never reads it. The port leaves it out.

## FirstPersonControls

`controls/first_person_controls.mojo`. The camera walks, and turns toward the pointer. `FirstPersonControls(camera)` reads where the camera looks. `handle(event, width, height)` changes what is held and where the pointer is. `update(camera, delta)` moves and turns the camera.

| Input | Change |
|---|---|
| `W` or the up arrow | Forward. |
| `S` or the down arrow | Back. |
| `A` or the left arrow | Left. |
| `D` or the right arrow | Right. |
| `R`, `F` | Up, down. |
| Left button, right button | Forward, back, while `active_look` is on. |
| Pointer | Turn toward it, faster the farther it is from the middle. |

| Member | Default | Meaning |
|---|---|---|
| `movement_speed` | 1 m/s | A `Velocity`. |
| `look_speed` | 0.005 deg/s | An `AngularVelocity` for each pixel the pointer is from the middle. |
| `look_vertical` | `True` | False turns only left and right. |
| `auto_forward` | `False` | Move forward with nothing held. |
| `active_look` | `True` | False turns not at all, and the buttons do not move. |
| `height_speed`, `height_coef` | `False`, 1 per second | Move forward faster the higher the camera is. |
| `height_min`, `height_max` | 0 m, 1 m | The heights `height_speed` reads between. |
| `constrain_vertical` | `False` | Keep the angle from straight up in a range. |
| `vertical_min`, `vertical_max` | 0, a half turn | That range, as an `Angle`. |
| `key_timeout` | 0.3 s | See [Held keys](#held-keys). |

The direction is a latitude and a longitude, as in three.js. The latitude stays within 85 degrees of level. `look_at(camera, point)` turns the camera and reads the new direction. The camera keeps its `up`.

A terminal reports the pointer only while a button is held. The camera keeps turning toward where the pointer last was. A browser's camera does the same while the pointer rests.

## PointerLockControls

`controls/pointer_lock_controls.mojo`. While the controls are locked, a pointer move turns the camera at once. `lock()` and `unlock()` set `is_locked`. No browser asks for permission, so both always succeed.

A turn is 0.002 radians a pixel, times `pointer_speed`, as in three.js. Right and left turn about the world's y. Up and down turn about the camera's right. The angle from straight up stays between `min_polar_angle` and `max_polar_angle`.

A browser reports how far a locked pointer moved. A terminal reports where the pointer is, and only while a button is held. So a turn is the difference between two positions. The first position after a press or after `lock` only records where the pointer is.

| Member | Default | Meaning |
|---|---|---|
| `is_locked` | `False` | Only a locked pointer turns the camera. |
| `min_polar_angle`, `max_polar_angle` | 0, a half turn | As an `Angle`. |
| `pointer_speed` | 1 | A factor on the turn. |
| `movement_speed` | 1 m/s | How fast a held key walks. |
| `key_timeout` | 0.3 s | See [Held keys](#held-keys). |

`move_forward(camera, distance)` moves along the level ground. `move_right(camera, distance)` moves along the camera's right. The distance is a `Length`. `get_direction(camera)` returns where the camera looks.

three.js leaves the keys to its example. Here `update(camera, delta)` walks by the keys held: `W`, `A`, `S`, `D` and the arrows. As in three.js, the camera's `up` must be +y.

## TrackballControls

`controls/trackball_controls.mojo`. The camera turns about `target` like a trackball. It has no poles, and it can roll over the top. `TrackballControls(camera, target)` records the camera for `reset`. `handle(event, width, height)` records where the pointer went. `update(camera)` applies it and places the camera.

| Input | Change |
|---|---|
| Left drag | Rotate. The camera's `up` turns too. |
| Middle drag, or the wheel | Zoom. |
| Right drag | Pan. |
| Hold `A`, `S` or `D` | Any button rotates, zooms or pans. |

| Member | Default | Meaning |
|---|---|---|
| `target` | the origin | The point the camera turns about. |
| `rotate_speed`, `zoom_speed`, `pan_speed` | 1, 1.2, 0.3 | |
| `no_rotate`, `no_zoom`, `no_pan` | `False` | Turn an action off. |
| `static_moving` | `False` | Stop a change at once. |
| `dynamic_damping_factor` | 0.2 | How fast a change dies away. |
| `min_distance`, `max_distance` | 0, infinity | For a perspective camera, as a `Length`. |
| `min_zoom`, `max_zoom` | 0, infinity | For an orthographic camera. |
| `rotate_key`, `zoom_key`, `pan_key` | `a`, `s`, `d` | three.js: `keys`. |
| `primary_action`, `middle_action`, `secondary_action` | `ROTATE`, `DOLLY`, `PAN` | three.js: `mouseButtons`. |
| `key_timeout` | 0.3 s | See [Held keys](#held-keys). |

The arithmetic is three.js's. A position is read on a circle as wide as the view. A turn is the distance the pointer moved on that circle, times `rotate_speed`. A zoom scales the distance by one plus the part of the view the drag covered, times `zoom_speed`. A wheel notch is 0.025 of the view.

Unless `static_moving` is set, each frame keeps `1 - dynamic_damping_factor` of a pan or a zoom. A turn keeps the square root of it. `reset(camera)` puts the camera and the target back. A turn that is dying away goes on after a reset, as in three.js.

`update` takes no time, as in three.js. It takes an optional `delta` that only ages the held keys, a sixtieth of a second by default. An orthographic camera's pan measures both directions by the view's width, as three.js's does. Touch input is not ported.

## ArcballControls

`ArcballControls` is not ported. It is about 3,500 lines of three.js, with gizmos, animations and its own touch gestures. It needs an issue of its own.

## How the ports were checked

The tests hold each control to three.js r180's own numbers. The three.js controls ran headless in Node, with the same camera, view and input as each test.

## Limits

The window asks the terminal its size with xterm's `ESC [ 18 t`, which works on every platform, where `ioctl` does not. A terminal that does not answer sends no `RESIZE`. Give such a terminal a size that fits: a terminal smaller than the frame wraps or cuts it. `examples/viewer.mojo` asks once a second and follows the answer.

The window needs a terminal that speaks xterm's sequences. The current terminals on Linux and macOS do, and so does Windows Terminal under WSL 2.

A frame is drawn in full every time. The example's frame of 96 by 64 pixels is about 20 kilobytes. A frame whose every pixel differs from its neighbor is about 120 kilobytes.
