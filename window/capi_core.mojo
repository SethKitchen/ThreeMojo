# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI, in the part of Mojo that also builds for WebAssembly.

A program that is not written in Mojo can run ThreeMojo through flat C
functions. The host owns the window, the loop and the clock. It makes an
app, tells the app about input, steps it by a time delta, and reads back a
frame of RGBA bytes:

    tm_init(); app = tm_create(w, h); tm_event(...); tm_step(...);
    pixels = tm_frame(app)

Only scalars and one opaque handle cross the boundary. No struct, string,
array or callback does, so the calls mean the same on a 64-bit native host
and in 32-bit WebAssembly memory. `window/threemojo.h` is the C header.

This module draws one shaded triangle with `render.fillrule`, the fill
rule the CPU and GPU rasterizers share. It allocates and does integer
arithmetic, and nothing else. That is the part of ThreeMojo that builds
for WebAssembly today. `window.capi_scene` has the same functions on the
full renderer, and it builds for the host only. Never import both modules
into one program: they export the same names.

Mojo 1.1 has no WebAssembly backend. `examples/capi/build.sh` retargets
the LLVM IR of this module to wasm32. See the wiki page `C-ABI-and-hosts`.
"""

from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from std.memory import Layout
from window.capi_abi import (
    ABI_VERSION,
    KEY_DOWN,
    KEY_SPACE,
    MAX_SIDE,
    POINTER_DOWN,
    POINTER_MOVE,
)

comptime TICK_MICROSECONDS = 16667
"""One animation tick: a sixtieth of a second, in microseconds."""


struct App(Movable):
    """The state that a host's handle points at."""

    var width: Int
    """The frame's width, in pixels."""
    var height: Int
    """The frame's height, in pixels."""
    var elapsed: Int
    """The time stepped so far, in microseconds."""
    var paused: Bool
    """Whether `tm_step` ignores time."""
    var has_pointer: Bool
    """Whether a pointer event has come."""
    var pointer_x: Int
    """The pointer's column, kept inside the frame."""
    var pointer_y: Int
    """The pointer's row, kept inside the frame."""
    var pixels: Pointer[UInt8, MutUntrackedOrigin]
    """The frame: RGBA, row by row from the top."""

    def __init__(
        out self,
        width: Int,
        height: Int,
        pixels: Pointer[UInt8, MutUntrackedOrigin],
    ):
        """Make an app that shows nothing yet.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            pixels: The frame's bytes, `width * height * 4` of them.
        """
        self.width = width
        self.height = height
        self.elapsed = 0
        self.paused = False
        self.has_pointer = False
        self.pointer_x = 0
        self.pointer_y = 0
        self.pixels = pixels


def _put(mut app: App, x: Int, y: Int, red: Int, green: Int, blue: Int):
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


def _clear(mut app: App):
    """Fill the frame with a dark vertical gradient.

    Args:
        app: The app that owns the frame.
    """
    var y = 0
    while y < app.height:
        var shade = 24 + (y * 40) // app.height
        var x = 0
        while x < app.width:
            _put(app, x, y, shade // 2, shade // 2, shade)
            x += 1
        y += 1


def _triangle(
    mut app: App,
    ax: Int,
    ay: Int,
    bx: Int,
    by: Int,
    cx: Int,
    cy: Int,
):
    """Fill a triangle with a red, a green and a blue corner.

    The corners are in subpixel units. The fill rule is the one the
    rasterizers share. A triangle that is not wound positively draws
    nothing.

    Args:
        app: The app that owns the frame.
        ax: The red corner's column.
        ay: The red corner's row.
        bx: The green corner's column.
        by: The green corner's row.
        cx: The blue corner's column.
        cy: The blue corner's row.
    """
    var area = edge_at(ax, ay, bx, by, cx, cy)
    if area <= 0:
        return
    var bias_ab = bias(ax, ay, bx, by)
    var bias_bc = bias(bx, by, cx, cy)
    var bias_ca = bias(cx, cy, ax, ay)
    var left = max(min(min(ax, bx), cx) // SUBPIXEL, 0)
    var right = min(max(max(ax, bx), cx) // SUBPIXEL + 1, app.width)
    var top = max(min(min(ay, by), cy) // SUBPIXEL, 0)
    var bottom = min(max(max(ay, by), cy) // SUBPIXEL + 1, app.height)
    var y = top
    while y < bottom:
        var x = left
        while x < right:
            var px = sample(x)
            var py = sample(y)
            var weight_c = edge_at(ax, ay, bx, by, px, py)
            var weight_a = edge_at(bx, by, cx, cy, px, py)
            var weight_b = edge_at(cx, cy, ax, ay, px, py)
            if (
                weight_c + bias_ab >= 0
                and weight_a + bias_bc >= 0
                and weight_b + bias_ca >= 0
            ):
                _put(
                    app,
                    x,
                    y,
                    (weight_a * 255) // area,
                    (weight_b * 255) // area,
                    (weight_c * 255) // area,
                )
            x += 1
        y += 1


def _marker(mut app: App):
    """Draw a white square, five pixels wide, on the pointer.

    Args:
        app: The app that owns the frame.
    """
    var top = max(app.pointer_y - 2, 0)
    var bottom = min(app.pointer_y + 3, app.height)
    var left = max(app.pointer_x - 2, 0)
    var right = min(app.pointer_x + 3, app.width)
    var y = top
    while y < bottom:
        var x = left
        while x < right:
            _put(app, x, y, 255, 255, 255)
            x += 1
        y += 1


def _draw(mut app: App):
    """Draw the app's state into its frame.

    The triangle slides left and right with the time. Once a pointer event
    has come, the triangle's top corner follows the pointer instead, and a
    white square marks it.

    Args:
        app: The app that owns the frame.
    """
    _clear(app)
    # 60 falling to 0 and rising to 59 again: a triangle wave, two seconds
    # long. The shift is half a wave either side of the middle.
    var tick = app.elapsed // TICK_MICROSECONDS
    var shift = abs(tick % 120 - 60) - 30
    var width = app.width
    var base = (app.height * 85) // 100
    var apex_x = width // 2 + shift
    var apex_y = (app.height * 15) // 100
    if app.has_pointer:
        apex_x = app.pointer_x
        apex_y = app.pointer_y
    # Screen y grows downward, so this order is wound positively.
    _triangle(
        app,
        snap(Float32(apex_x)),
        snap(Float32(apex_y)),
        snap(Float32((width * 85) // 100)),
        snap(Float32(base)),
        snap(Float32((width * 15) // 100 + shift)),
        snap(Float32(base)),
    )
    if app.has_pointer:
        _marker(app)


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[App, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[App]()


@export("tm_abi_version")
def tm_abi_version() abi("C") -> Int32:
    """Return the version of the C ABI, so that a host can check it.

    Returns:
        `ABI_VERSION`.
    """
    return Int32(ABI_VERSION)


@export("tm_init")
def tm_init() abi("C") -> None:
    """Start the runtime. This module only allocates, so it has nothing to
    start. The call exists so that every build has the same functions."""
    pass


@export("tm_create")
def tm_create(
    width: Int32, height: Int32
) abi("C") -> OptionalPointer[App, MutUntrackedOrigin]:
    """Make an app with a frame of a size.

    Args:
        width: The frame's width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        The app's handle, or NULL if a side is out of range.
    """
    var w = Int(width)
    var h = Int(height)
    if w < 1 or h < 1 or w > MAX_SIDE or h > MAX_SIDE:
        return None
    var pixels = alloc(Layout[UInt8](count=w * h * 4)).unsafe_leak()
    var slot = alloc(Layout[App](count=1)).unsafe_leak()
    slot.unsafe_write(App(w, h, pixels))
    return slot


@export("tm_destroy")
def tm_destroy(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> None:
    """Free an app and its frame. The handle must not be used again.

    Args:
        handle: A handle from `tm_create`.
    """
    var app = _app(handle)
    app[].pixels.unsafe_free()
    app.unsafe_free()


@export("tm_event")
def tm_event(
    handle: OpaquePointer[MutUntrackedOrigin],
    kind: Int32,
    x: Int32,
    y: Int32,
    detail: Int32,
) abi("C") -> None:
    """Tell an app about one input event.

    A button press or a pointer move places the pointer. The space bar
    pauses the app, and pauses it no more when pressed again. An event of
    any other kind does nothing.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels. It is kept inside the frame.
        y: The pointer's row, in pixels. It is kept inside the frame.
        detail: The key code of a key event.
    """
    var app = _app(handle)
    var event = Int(kind)
    if event == POINTER_DOWN or event == POINTER_MOVE:
        app[].has_pointer = True
        app[].pointer_x = min(max(Int(x), 0), app[].width - 1)
        app[].pointer_y = min(max(Int(y), 0), app[].height - 1)
    elif event == KEY_DOWN and Int(detail) == KEY_SPACE:
        app[].paused = not app[].paused


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta.

    Time that is negative, or that comes while the app is paused, is
    ignored.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step, in microseconds.
    """
    var app = _app(handle)
    if app[].paused or microseconds < 0:
        return
    app[].elapsed += Int(microseconds)


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Draw an app's state and return the frame.

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
