# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI with gamepads that a host gives it, as a browser does.

A browser has the Gamepad API, and Mojo cannot reach it. A page reads
`navigator.getGamepads()` each frame and gives each pad's state to this
library, which runs SDL's browser joystick driver (`extensions.gamepad.web`)
and SDL's `Standard Gamepad` mapping. The app reads the pads by position,
as SDL names them, and asks the page to rumble them:

    tm_gamepad_connect(app, index, id, id_length, axes, buttons, rumble)
    tm_gamepad_set_axis(app, index, axis, value)            each axis
    tm_gamepad_set_button(app, index, button, pressed, value)
    tm_gamepad_sample(app, index, timestamp)                then this
    tm_gamepad_axis(app, index, TM_GAMEPAD_AXIS_LEFTX)      read
    if tm_gamepad_take_rumble(app, index): play
        tm_gamepad_rumble_strength(app, 0), (app, 1)

The frame shows the first pad: its sticks, triggers and buttons. The
library also has every function of `window/threemojo.h`, so a host loads
it as any other.
"""

from extensions.gamepad.ids import (
    AXIS_COUNT,
    BUTTON_COUNT,
    GamepadAxis,
    GamepadButton,
)
from extensions.gamepad.web import (
    WEB_DEFAULT_MAPPING,
    WebGamepadState,
    WebHub,
)
from std.memory import Layout
from units.si import Duration64, SECOND
from window.capi_abi import ABI_VERSION, MAX_SIDE

comptime MAX_ID = 1024
"""The most bytes of a pad's id that the library reads."""
comptime RUMBLE_LOW = 0
"""`tm_gamepad_rumble_strength`'s number for the low frequency motor."""
comptime RUMBLE_HIGH = 1
"""`tm_gamepad_rumble_strength`'s number for the high frequency motor."""


struct GamepadApp(Movable):
    """The state that a host's handle points at."""

    var width: Int
    """The frame's width, in pixels."""
    var height: Int
    """The frame's height, in pixels."""
    var pixels: Pointer[UInt8, MutUntrackedOrigin]
    """The frame: RGBA, row by row from the top."""
    var hub: WebHub
    """The pads the page connected."""
    var staged: List[WebGamepadState]
    """The state each pad is given before `tm_gamepad_sample`."""
    var elapsed: Int
    """The time stepped so far, in microseconds."""
    var taken: Tuple[Int, Int]
    """The rumble that `tm_gamepad_take_rumble` took."""

    def __init__(
        out self,
        width: Int,
        height: Int,
        pixels: Pointer[UInt8, MutUntrackedOrigin],
        mapping: String,
    ) raises:
        """Make an app with no pads.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            pixels: The frame's bytes, `width * height * 4` of them.
            mapping: The default mapping, SDL's `WEB_DEFAULT_MAPPING`.

        Raises:
            Error: If the mapping is not well formed.
        """
        self.width = width
        self.height = height
        self.pixels = pixels
        self.hub = WebHub(mapping)
        self.staged = List[WebGamepadState]()
        self.elapsed = 0
        self.taken = (0, 0)

    def now(self) -> Duration64:
        """Return the time the host has stepped.

        Returns:
            The time since the app was made.
        """
        return Duration64(Float64(self.elapsed) * 1e-6, SECOND)

    def stage(mut self, index: Int) -> Int:
        """Return the staged state of a connected pad.

        Args:
            index: The pad's place in `navigator.getGamepads()`.

        Returns:
            Its place in `staged`, or -1 when the pad is not connected.
        """
        for at in range(len(self.staged)):
            if self.staged[at].index == index:
                return at
        return -1


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[GamepadApp, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[GamepadApp]()


@export("tm_abi_version")
def tm_abi_version() abi("C") -> Int32:
    """Return the version of the C ABI, so that a host can check it.

    Returns:
        `ABI_VERSION`.
    """
    return Int32(ABI_VERSION)


@export("tm_init")
def tm_init() abi("C") -> None:
    """Start the runtime. This module needs no runtime. The call exists so
    that every build has the same functions."""
    pass


def create_app(
    width: Int, height: Int, mapping: String
) -> OptionalPointer[GamepadApp, MutUntrackedOrigin]:
    """Make an app with a frame of a size and a default mapping.

    Args:
        width: The frame's width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's height, in pixels, from 1 to `MAX_SIDE`.
        mapping: The default mapping.

    Returns:
        The app, or NULL if a side is out of range or the mapping is not
        well formed.
    """
    var w = width
    var h = height
    if w < 1 or h < 1 or w > MAX_SIDE or h > MAX_SIDE:
        return None
    var pixels = alloc(Layout[UInt8](count=w * h * 4)).unsafe_leak()
    try:
        var app = GamepadApp(w, h, pixels, mapping)
        var slot = alloc(Layout[GamepadApp](count=1)).unsafe_leak()
        slot.unsafe_write(app^)
        return slot
    except:
        pixels.unsafe_free()
        return None


@export("tm_create")
def tm_create(
    width: Int32, height: Int32
) abi("C") -> OptionalPointer[GamepadApp, MutUntrackedOrigin]:
    """Make an app with a frame of a size.

    Args:
        width: The frame's width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        The app's handle, or NULL if a side is out of range.
    """
    return create_app(Int(width), Int(height), WEB_DEFAULT_MAPPING)


@export("tm_destroy")
def tm_destroy(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> None:
    """Free an app and its frame. The handle must not be used again.

    Args:
        handle: A handle from `tm_create`.
    """
    var app = _app(handle)
    app[].pixels.unsafe_free()
    _ = app.unsafe_take_pointee()
    app.unsafe_free()


@export("tm_event")
def tm_event(
    handle: OpaquePointer[MutUntrackedOrigin],
    kind: Int32,
    x: Int32,
    y: Int32,
    detail: Int32,
) abi("C") -> None:
    """Tell an app about one input event. This app reads gamepads only, so
    it ignores keys and pointers.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels.
        y: The pointer's row, in pixels.
        detail: The key code, button or notches.
    """
    pass


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta, and run the rumble timers.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step. Negative time is
            ignored.
    """
    var app = _app(handle)
    if microseconds < 0:
        return
    app[].elapsed += Int(microseconds)
    var now = app[].now()
    for index in range(len(app[].hub.pads)):
        app[].hub.pads[index].tick(now)


def _put(mut app: GamepadApp, x: Int, y: Int, red: Int, green: Int, blue: Int):
    """Write one opaque pixel.

    Args:
        app: The app that owns the frame.
        x: The column, inside the frame.
        y: The row, inside the frame.
        red: The red channel, 0 to 255.
        green: The green channel, 0 to 255.
        blue: The blue channel, 0 to 255.
    """
    var at = (y * app.width + x) * 4
    app.pixels.unsafe_offset(at).unsafe_write(UInt8(red))
    app.pixels.unsafe_offset(at + 1).unsafe_write(UInt8(green))
    app.pixels.unsafe_offset(at + 2).unsafe_write(UInt8(blue))
    app.pixels.unsafe_offset(at + 3).unsafe_write(UInt8(255))


def _box(mut app: GamepadApp, x: Int, y: Int, w: Int, h: Int, shade: Int):
    """Fill the part of a gray rectangle that is inside the frame.

    Args:
        app: The app that owns the frame.
        x: The left column.
        y: The top row.
        w: The width.
        h: The height.
        shade: The gray level, 0 to 255.
    """
    for row in range(max(y, 0), min(y + h, app.height)):
        for column in range(max(x, 0), min(x + w, app.width)):
            _put(app, column, row, shade, shade, shade)


def _draw(mut app: GamepadApp):
    """Draw the first pad: two sticks, two triggers and the buttons.

    Args:
        app: The app that owns the frame.
    """
    _box(app, 0, 0, app.width, app.height, 24)
    if len(app.hub.pads) == 0:
        return
    var axes = List[Int](capacity=AXIS_COUNT)
    for axis in range(AXIS_COUNT):  # pragma: no branch
        axes.append(app.hub.pads[0].gamepad.get_axis(GamepadAxis(axis)))
    var buttons = List[Bool](capacity=BUTTON_COUNT)
    for button in range(BUTTON_COUNT):  # pragma: no branch
        buttons.append(
            app.hub.pads[0].gamepad.get_button(GamepadButton(button))
        )
    var side = max(app.height // 3, 4)
    var top = app.height // 6
    # The two sticks: a dark square with a light dot where the stick is.
    for stick in range(2):
        var left = app.width // 8 + stick * app.width // 2
        _box(app, left, top, side, side, 60)
        var dot_x = left + (axes[stick * 2] + 32768) * (side - 3) // 65535
        var dot_y = top + (axes[stick * 2 + 1] + 32768) * (side - 3) // 65535
        _box(app, dot_x, dot_y, 3, 3, 230)
        # The trigger under the stick: a bar that fills as it goes down.
        _box(app, left, top + side + 2, side, 3, 60)
        _box(app, left, top + side + 2, axes[4 + stick] * side // 32768, 3, 200)
    # The buttons, in SDL's order: lit while down.
    var cell = max(app.width // BUTTON_COUNT, 1)
    var row = app.height - cell - 2
    for button in range(BUTTON_COUNT):  # pragma: no branch
        var shade = 230 if buttons[button] else 70
        _box(app, button * cell, row, max(cell - 1, 1), cell, shade)


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Draw the first pad and return the frame.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The frame: RGBA, eight bits a channel, row by row from the top,
        `tm_width * tm_height * 4` bytes. It stays valid until the next
        call on this app.
    """
    var app = _app(handle)
    _draw(app[])
    return app[].pixels


@export("tm_width")
def tm_width(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Return an app's frame width.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The width, in pixels.
    """
    return Int32(_app(handle)[].width)


@export("tm_height")
def tm_height(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Return an app's frame height.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The height, in pixels.
    """
    return Int32(_app(handle)[].height)


@export("tm_alloc")
def tm_alloc(
    size: Int32,
) abi("C") -> OptionalPointer[UInt8, MutUntrackedOrigin]:
    """Make room for a pad's id, which the host writes there.

    Args:
        size: The bytes, from 1 to `MAX_ID`.

    Returns:
        The address of the room, or NULL if `size` is out of range. Give it
        back with `tm_free`.
    """
    if size <= 0 or Int(size) > MAX_ID:
        return None
    return alloc(Layout[UInt8](count=Int(size))).unsafe_leak()


@export("tm_free")
def tm_free(room: Pointer[UInt8, MutUntrackedOrigin]) abi("C") -> None:
    """Give back room from `tm_alloc`.

    Args:
        room: An address that `tm_alloc` returned.
    """
    room.unsafe_free()


@export("tm_gamepad_connect")
def tm_gamepad_connect(
    handle: OpaquePointer[MutUntrackedOrigin],
    index: Int32,
    id: Pointer[UInt8, MutUntrackedOrigin],
    id_length: Int32,
    axes: Int32,
    buttons: Int32,
    rumble: Int32,
) abi("C") -> Int32:
    """Connect a pad: the browser's `gamepadconnected` event.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        id: The pad's `Gamepad.id`, in UTF-8. The app copies it.
        id_length: The id's bytes, from 0 to `MAX_ID`.
        axes: How many axes it has.
        buttons: How many buttons it has.
        rumble: 1 if it has a `vibrationActuator`, else 0.

    Returns:
        1 if the pad was connected, and 0 if it is connected already or
        the id is too long.
    """
    var app = _app(handle)
    if id_length < 0 or Int(id_length) > MAX_ID:
        return 0
    var bytes = List[UInt8](capacity=Int(id_length))
    for at in range(Int(id_length)):
        bytes.append(id.unsafe_offset(at).unsafe_load())
    var state = WebGamepadState(
        Int(index),
        String(from_utf8_lossy=bytes),
        Int(axes),
        Int(buttons),
    )
    if not app[].hub.connect(state, rumble != 0):
        return 0
    app[].staged.append(state^)
    return 1


@export("tm_gamepad_disconnect")
def tm_gamepad_disconnect(
    handle: OpaquePointer[MutUntrackedOrigin], index: Int32
) abi("C") -> Int32:
    """Disconnect a pad: the browser's `gamepaddisconnected` event.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.

    Returns:
        1 if the pad was connected, else 0.
    """
    var app = _app(handle)
    var at = app[].stage(Int(index))
    if at < 0:
        return 0
    _ = app[].staged.pop(at)
    _ = app[].hub.disconnect(Int(index))
    return 1


@export("tm_gamepad_set_axis")
def tm_gamepad_set_axis(
    handle: OpaquePointer[MutUntrackedOrigin],
    index: Int32,
    axis: Int32,
    value: Float64,
) abi("C") -> None:
    """Stage one axis of a pad's next state.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        axis: The axis, as the browser numbers it. One out of range is
            ignored.
        value: `Gamepad.axes[axis]`, from -1 to 1.
    """
    var app = _app(handle)
    var at = app[].stage(Int(index))
    if at < 0 or axis < 0 or Int(axis) >= len(app[].staged[at].axes):
        return
    app[].staged[at].axes[Int(axis)] = value


@export("tm_gamepad_set_button")
def tm_gamepad_set_button(
    handle: OpaquePointer[MutUntrackedOrigin],
    index: Int32,
    button: Int32,
    pressed: Int32,
    value: Float64,
) abi("C") -> None:
    """Stage one button of a pad's next state.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        button: The button, as the browser numbers it. One out of range is
            ignored.
        pressed: `Gamepad.buttons[button].pressed`: 1 or 0.
        value: `Gamepad.buttons[button].value`, from 0 to 1.
    """
    var app = _app(handle)
    var at = app[].stage(Int(index))
    if (
        at < 0
        or button < 0
        or Int(button) >= len(app[].staged[at].digital_buttons)
    ):
        return
    app[].staged[at].digital_buttons[Int(button)] = pressed != 0
    app[].staged[at].analog_buttons[Int(button)] = value


@export("tm_gamepad_sample")
def tm_gamepad_sample(
    handle: OpaquePointer[MutUntrackedOrigin],
    index: Int32,
    timestamp: Float64,
) abi("C") -> Int32:
    """Give a pad the state staged for it. SDL: `EMSCRIPTEN_JoystickUpdate`.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        timestamp: `Gamepad.timestamp`, in milliseconds.

    Returns:
        How many gamepad events the state made, or -1 when the pad is not
        connected.
    """
    var app = _app(handle)
    var at = app[].stage(Int(index))
    if at < 0:
        return -1
    app[].staged[at].timestamp = timestamp
    var events = app[].hub.update(app[].staged[at])
    return Int32(len(events))


@export("tm_gamepad_count")
def tm_gamepad_count(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Int32:
    """Return how many pads are connected.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The number of pads.
    """
    return Int32(len(_app(handle)[].hub.pads))


@export("tm_gamepad_index")
def tm_gamepad_index(
    handle: OpaquePointer[MutUntrackedOrigin], slot: Int32
) abi("C") -> Int32:
    """Return a connected pad's `Gamepad.index`.

    Args:
        handle: A handle from `tm_create`.
        slot: The pad, from 0 to `tm_gamepad_count` - 1, in the order the
            pads connected.

    Returns:
        The index, or -1 for a slot out of range.
    """
    var app = _app(handle)
    if slot < 0 or Int(slot) >= len(app[].hub.pads):
        return -1
    return Int32(app[].hub.pads[Int(slot)].index)


@export("tm_gamepad_axis")
def tm_gamepad_axis(
    handle: OpaquePointer[MutUntrackedOrigin], index: Int32, axis: Int32
) abi("C") -> Int32:
    """Return a gamepad axis. SDL: `SDL_GetGamepadAxis`.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        axis: The axis, as SDL numbers it: `TM_GAMEPAD_AXIS_*`.

    Returns:
        The value: -32768 to 32767 for a stick, 0 to 32767 for a trigger,
        and 0 for an axis or pad that does not exist.
    """
    var app = _app(handle)
    var at = app[].hub.find(Int(index))
    if at < 0 or axis < 0 or Int(axis) >= AXIS_COUNT:
        return 0
    return Int32(app[].hub.pads[at].gamepad.get_axis(GamepadAxis(Int(axis))))


@export("tm_gamepad_button")
def tm_gamepad_button(
    handle: OpaquePointer[MutUntrackedOrigin], index: Int32, button: Int32
) abi("C") -> Int32:
    """Return a gamepad button. SDL: `SDL_GetGamepadButton`.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        button: The button, as SDL numbers it: `TM_GAMEPAD_BUTTON_*`.

    Returns:
        1 while it is down, else 0.
    """
    var app = _app(handle)
    var at = app[].hub.find(Int(index))
    if at < 0 or button < 0 or Int(button) >= BUTTON_COUNT:
        return 0
    return Int32(
        Int(app[].hub.pads[at].gamepad.get_button(GamepadButton(Int(button))))
    )


@export("tm_gamepad_rumble")
def tm_gamepad_rumble(
    handle: OpaquePointer[MutUntrackedOrigin],
    index: Int32,
    low: Int32,
    high: Int32,
    milliseconds: Int32,
) abi("C") -> Int32:
    """Rumble a pad. SDL: `SDL_RumbleGamepad`.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.
        low: The low frequency strength, 0 to 65535.
        high: The high frequency strength, 0 to 65535.
        milliseconds: How long. 0 rumbles until changed.

    Returns:
        1 if the pad rumbles, else 0.
    """
    var app = _app(handle)
    var at = app[].hub.find(Int(index))
    if at < 0:
        return 0
    var now = app[].now()
    try:
        return Int32(
            Int(
                app[]
                .hub.pads[at]
                .rumble_at(
                    Int(low),
                    Int(high),
                    Duration64(Float64(Int(milliseconds)) * 1e-3, SECOND),
                    now,
                )
            )
        )
    except:
        return 0


@export("tm_gamepad_take_rumble")
def tm_gamepad_take_rumble(
    handle: OpaquePointer[MutUntrackedOrigin], index: Int32
) abi("C") -> Int32:
    """Take the rumble the page must play on a pad.

    Args:
        handle: A handle from `tm_create`.
        index: The pad's `Gamepad.index`.

    Returns:
        1 if there is one: read it with `tm_gamepad_rumble_strength`.
        0 if there is none.
    """
    var app = _app(handle)
    var at = app[].hub.find(Int(index))
    if at < 0:
        return 0
    var request = app[].hub.pads[at].take_rumble()
    if not request:
        return 0
    app[].taken = request.value()
    return 1


@export("tm_gamepad_rumble_strength")
def tm_gamepad_rumble_strength(
    handle: OpaquePointer[MutUntrackedOrigin], motor: Int32
) abi("C") -> Int32:
    """Return a strength of the rumble that `tm_gamepad_take_rumble` took.

    Args:
        handle: A handle from `tm_create`.
        motor: `RUMBLE_LOW` (0) or `RUMBLE_HIGH` (1).

    Returns:
        The strength, 0 to 65535, or 0 for another motor number.
    """
    var app = _app(handle)
    if motor == RUMBLE_LOW:
        return Int32(app[].taken[0])
    if motor == RUMBLE_HIGH:
        return Int32(app[].taken[1])
    return 0
