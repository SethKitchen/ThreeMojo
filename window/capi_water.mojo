# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI on the Clearwater water extension: a pebbled bed under ripples.

These are the functions of `window.capi_core`, with the same names and the
same meaning, so a host cannot tell the two apart. Here a call does real
work. `tm_step` runs the ripple equation of a `WaterScene`, and `tm_frame`
draws its `FRAME` view with the idle camera bob. A press of any button taps
the middle of the water, and a drag up or down tilts the camera. The space
bar pauses. The page that shows the picture is Water. The rules are in
`window.water_app`, which `window.capi_water_gpu` shares.

Nothing may raise across a C boundary. Each call that can raise is caught
here, and the call then does nothing: a step that the scene refuses leaves
the ripples as they were, and a frame that cannot be drawn is the last one
that could.

This module builds for the host only. Never import this module and
`window.capi_core` into one program.

The pebble photograph is read from `assets/pebbles.jpg` when the program runs
in the repository's root folder. Where it cannot be read, as in a browser,
which has no files, the bed is plain sand until the host gives the app the
photograph with `tm_asset`. `tm_alloc` and `tm_free` let a host that cannot
reach the module's memory any other way put the bytes there. These three
functions are not in every library. A host calls them only if it finds them.

A host that has its own GPU can draw the frame with it. `tm_gpu_prepare` makes
the arrays that the water shader reads, `tm_gpu_part` and `tm_gpu_words` say
where they are in the module's memory, and the host shades, blooms and grades
on its GPU. Only the glare stays here: the host writes the glints into the
`GPU_SAMPLES` part, calls `tm_gpu_glare`, and reads the `GPU_GRID` part. A
browser's WebGPU does it this way. These five functions are not in every
library either. A host calls them only if it finds them.

A host that is not a Mojo program must call `tm_init` once, before any other
function.
"""

from std.memory import Layout, unsafe_memcpy
from std.runtime import initialize_runtime
from window.capi_abi import ABI_VERSION, MAX_SIDE, GpuInfo, GpuPart
from window.water_app import BED, WaterApp

comptime MAX_ASSET = 67108864
"""The most bytes that `tm_alloc` gives: 64 MiB."""


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[WaterApp, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[WaterApp]()


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
) abi("C") -> OptionalPointer[WaterApp, MutUntrackedOrigin]:
    """Make an app with a frame of a size.

    Args:
        width: The frame's width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        The app's handle, or NULL if a side is out of range.
    """
    var w = Int(width)
    var h = Int(height)
    if w > MAX_SIDE or h > MAX_SIDE:
        return None
    try:
        var app = WaterApp(w, h, BED)
        var slot = alloc(Layout[WaterApp](count=1)).unsafe_leak()
        slot.unsafe_write(app^)
        return slot
    except:
        return None


@export("tm_alloc")
def tm_alloc(
    size: Int32,
) abi("C") -> OptionalPointer[UInt8, MutUntrackedOrigin]:
    """Make room for bytes that the host will hand to the app.

    Args:
        size: The bytes, from 1 to `MAX_ASSET`.

    Returns:
        The address of the room, or NULL if `size` is out of range. Give it
        back with `tm_free`.
    """
    if size <= 0 or Int(size) > MAX_ASSET:
        return None
    return alloc(Layout[UInt8](count=Int(size))).unsafe_leak()


@export("tm_free")
def tm_free(room: Pointer[UInt8, MutUntrackedOrigin]) abi("C") -> None:
    """Give back room from `tm_alloc`.

    Args:
        room: An address that `tm_alloc` returned.
    """
    room.unsafe_free()


@export("tm_asset")
def tm_asset(
    handle: OpaquePointer[MutUntrackedOrigin],
    bytes: Pointer[UInt8, MutUntrackedOrigin],
    length: Int32,
) abi("C") -> Int32:
    """Give an app its pebble photograph.

    Args:
        handle: A handle from `tm_create`.
        bytes: A JPEG file, which the app copies before it returns.
        length: The file's size, in bytes.

    Returns:
        0 if the app has the photograph. 1 if `length` is not positive, or
        the bytes are not a JPEG that the app can read. The bed is not
        changed then.
    """
    if length <= 0:
        return 1
    # One bulk copy. A byte loop here copies the photograph one byte at a
    # time and dominates the hand-off.
    var file = List[UInt8](length=Int(length), fill=0)
    unsafe_memcpy(dest=file.unsafe_ptr(), src=bytes, count=Int(length))
    try:
        _app(handle)[].set_bed(file)
    except:
        return 1
    return 0


@export("tm_destroy")
def tm_destroy(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> None:
    """Free an app. The handle must not be used again.

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

    The space bar pauses the app, and resumes it when pressed again. A press
    of any button taps the middle of the water on the next step and starts a
    drag. While a button is down, a move up or down tilts the camera. Any
    other event is dropped.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels.
        y: The pointer's row, in pixels.
        detail: The key code of a key event. A pointer event's button is not
            used.
    """
    _app(handle)[].handle(Int(kind), Int(y), Int(detail))


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta.

    The time is gathered, and one ripple step runs for each 1/30 s of it.
    Time that is negative, or that comes while the app is paused, is
    ignored. A single call counts at most 0.1 s.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step, in microseconds.
    """
    _app(handle)[].advance(Int(microseconds))


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Draw an app's water and return the frame.

    Water that cannot be drawn leaves the last frame that could be. The
    first frame is black in that case.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The frame: RGBA, eight bits a channel, row by row from the top,
        `tm_width * tm_height * 4` bytes. It stays valid until the next
        call on this app.
    """
    var app = _app(handle)
    try:
        app[].draw()
    except:
        pass
    return Pointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(app[].frame.pixels.unsafe_ptr())
    )


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


@export("tm_gpu_prepare")
def tm_gpu_prepare(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Make the arrays that a host's GPU draws the next frame from.

    The host calls this after `tm_step`, and then reads the arrays with
    `tm_gpu_part`. It draws with the camera that `tm_frame` uses. The arrays
    stay valid until the next call to this function.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        How many times the pebble photograph has been packed, which is 1 or
        more. The host uploads the photograph again when the number changes.
        It is -1 if the water cannot be prepared, and the arrays are those of
        the last frame that could.
    """
    try:
        return Int32(_app(handle)[].prepare())
    except:
        return -1


@export("tm_gpu_glare")
def tm_gpu_glare(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Spread the glints that the host wrote into the glare.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        0 if the `GPU_GRID` part now holds the glare. 1 if `tm_gpu_prepare` has
        not run, and the part is unchanged.
    """
    try:
        _app(handle)[].glare()
    except:
        return 1
    return 0


@export("tm_gpu_part")
def tm_gpu_part(
    handle: OpaquePointer[MutUntrackedOrigin], which: Int32
) abi("C") -> OptionalPointer[UInt8, MutUntrackedOrigin]:
    """Return where one array of the prepared frame is in memory.

    Take a new view of the module's memory after every call to the module,
    because the memory can grow.

    Args:
        handle: A handle from `tm_create`.
        which: A `GPU_*` part number from `window.capi_abi`.

    Returns:
        The address of the part's first byte, or NULL before `tm_gpu_prepare`
        and for a part number that does not exist.
    """
    var part = GpuPart(Int(which))
    if not part.is_valid():
        return None
    var found = _app(handle)[].part(part)
    if found[0] == 0:
        return None
    return Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=found[0])


@export("tm_gpu_words")
def tm_gpu_words(
    handle: OpaquePointer[MutUntrackedOrigin], which: Int32
) abi("C") -> Int32:
    """Return the size of one array of the prepared frame.

    Args:
        handle: A handle from `tm_create`.
        which: A `GPU_*` part number from `window.capi_abi`.

    Returns:
        The size in 32-bit words. A table of 64-bit integers counts two words
        an entry. It is 0 before `tm_gpu_prepare` and for a part number that
        does not exist.
    """
    var part = GpuPart(Int(which))
    if not part.is_valid():
        return 0
    return Int32(_app(handle)[].part(part)[1])


@export("tm_gpu_info")
def tm_gpu_info(
    handle: OpaquePointer[MutUntrackedOrigin], which: Int32
) abi("C") -> Int32:
    """Return one number about the prepared frame.

    Args:
        handle: A handle from `tm_create`.
        which: `GPU_INFO_RIPPLE_SIDE`, `GPU_INFO_GRID_WIDTH` or
            `GPU_INFO_GRID_HEIGHT`, from `window.capi_abi`.

    Returns:
        The number. It is 0 before `tm_gpu_prepare` and for another `which`.
    """
    var info = GpuInfo(Int(which))
    if not info.is_valid():
        return 0
    return Int32(_app(handle)[].info(info))
