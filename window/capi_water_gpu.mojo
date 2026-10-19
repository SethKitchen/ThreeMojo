# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI on the water extension, shaded on a GPU.

These are the functions of `window.capi_water`, with the same names and the
same meaning, so a host cannot tell the two apart. Only the picture is made
another way: `tm_frame` runs `GpuWater`, which shades each pixel on CUDA or on
Apple Metal, and then grades the frame on the CPU. The frame still comes back
in host memory, so the hosts need no change. The rules for events and time
are in `window.water_app`, which both libraries share.

This module needs MAX and a GPU. `tm_create` returns NULL on a machine
without one. It builds for the host only, and never into one program with
`window.capi_water` or `window.capi_core`.

The pebble photograph is read from `assets/pebbles.jpg`, so the program must
run in the repository's root folder, or the bed is plain sand. A host that is
not a Mojo program must call `tm_init` once, before any other function. The
first run on Apple Metal compiles the shader, which takes minutes, and later
runs find it cached.
"""

from extensions.water.gpu import GpuWater
from extensions.water.view import FRAME
from std.memory import Layout
from std.runtime import initialize_runtime
from units.si import RADIAN, Angle
from window.capi_abi import ABI_VERSION, MAX_SIDE
from window.water_app import BED, WaterApp


struct GpuWaterApp(Movable):
    """The state that a host's handle points at: the app and its device."""

    var app: WaterApp
    """The water, the camera and the frame, as the CPU library keeps them."""
    var gpu: GpuWater
    """The device that shades the frames, holding the pebble photograph."""

    def __init__(out self, width: Int, height: Int, bed: String) raises:
        """Build the water, then open the GPU and copy the photograph to it.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            bed: The pebble photograph's path. Plain sand takes its place if
                the file cannot be read.

        Raises:
            Error: If a side is not positive, or there is no GPU.
        """
        var app = WaterApp(width, height, bed)
        var gpu = GpuWater(app.bed)
        self.app = app^
        self.gpu = gpu^


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[GpuWaterApp, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[GpuWaterApp]()


@export("tm_abi_version")
def tm_abi_version() abi("C") -> Int32:
    """Return the version of the C ABI, so that a host can check it.

    Returns:
        `ABI_VERSION`.
    """
    return Int32(ABI_VERSION)


@export("tm_init")
def tm_init() abi("C") -> None:
    """Start the Mojo runtime.

    A host that is not a Mojo program must call this once, before any other
    function.
    """
    initialize_runtime()


@export("tm_create")
def tm_create(
    width: Int32, height: Int32
) abi("C") -> OptionalPointer[GpuWaterApp, MutUntrackedOrigin]:
    """Make an app with a frame of a size, and open the GPU for it.

    Args:
        width: The frame's width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        The app's handle, or NULL if a side is out of range or there is no
        GPU.
    """
    var w = Int(width)
    var h = Int(height)
    if w > MAX_SIDE or h > MAX_SIDE:
        return None
    try:
        var app = GpuWaterApp(w, h, BED)
        var slot = alloc(Layout[GpuWaterApp](count=1)).unsafe_leak()
        slot.unsafe_write(app^)
        return slot
    except:
        return None


@export("tm_destroy")
def tm_destroy(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> None:
    """Free an app and release its GPU. The handle must not be used again.

    Args:
        handle: A handle from `tm_create`.
    """
    var app = _app(handle)
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
    """Tell an app about one input event.

    The events are those of `window.capi_water`: the space bar pauses, a
    press taps the water and starts a drag, and a drag up or down tilts the
    camera.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels.
        y: The pointer's row, in pixels.
        detail: The key code of a key event. A pointer event's button is not
            used.
    """
    _app(handle)[].app.handle(Int(kind), Int(y), Int(detail))


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta, as `window.capi_water` does.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step, in microseconds.
    """
    _app(handle)[].app.advance(Int(microseconds))


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Shade an app's water on the GPU and return the frame.

    Water that cannot be drawn, or a device step that fails, leaves the last
    frame that could be. The first frame is black in that case.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The frame: RGBA, eight bits a channel, row by row from the top,
        `tm_width * tm_height * 4` bytes. It stays valid until the next
        call on this app.
    """
    var app = _app(handle)
    try:
        app[].app.frame = app[].gpu.draw(
            app[].app.water,
            app[].app.width,
            app[].app.height,
            FRAME,
            True,
            Angle(app[].app.pitch, RADIAN),
        )
    except:
        pass
    return Pointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(app[].app.frame.pixels.unsafe_ptr())
    )


@export("tm_width")
def tm_width(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Return an app's frame width.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The width, in pixels.
    """
    return Int32(_app(handle)[].app.width)


@export("tm_height")
def tm_height(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Return an app's frame height.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The height, in pixels.
    """
    return Int32(_app(handle)[].app.height)
