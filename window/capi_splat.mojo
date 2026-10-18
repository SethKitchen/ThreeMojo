# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI on a Gaussian splat scan: the three.js tomatoes, orbited.

These are the functions of `window.capi_core`, with the same names and the
same meaning, so a host cannot tell the two apart. Here a call does real
work. `tm_event` goes to the orbit controls, `tm_step` moves the camera, and
`tm_frame` draws the scan on the CPU with `draw_gaussian_splat`. The rules
are in `window.splat_app`, which has the scene.

Nothing may raise across a C boundary. Each call that can raise is caught
here, and the call then does nothing: an event the controls refuse is
dropped, and a frame that cannot be drawn is the last one that could.

This module builds for the host and for WebAssembly. Never import this module
and `window.capi_core` into one program.

The scan is read from `assets/tomatoes/tomatoes.v4.spz` when the program runs
in the repository's root folder. Where it cannot be read, as in a browser,
which has no files, the app draws only the background until the host gives it
the scan with `tm_asset`. `tm_alloc` and `tm_free` let a host that cannot
reach the module's memory any other way put the bytes there. A host can also
change the size of the frame with `tm_resize`. These four functions are not
in every library. A host calls them only if it finds them.

A host that has its own GPU draws the scan with it. `tm_splat_prepare` sorts
the splats and writes the view, `tm_splat_part` and `tm_splat_words` say where
the scan, the order and the view are in the module's memory, and the host
projects, shades and blends the splats on its GPU. A CPU frame of the same
view is 0.2 s. These four functions are not in every library either.

A host that is not a Mojo program must call `tm_init` once, before any other
function.
"""

from std.memory import Layout, unsafe_memcpy
from std.runtime import initialize_runtime
from window.capi_abi import (
    ABI_VERSION,
    MAX_SIDE,
    SplatInfo,
    SplatPart,
)
from window.splat_app import SCAN, SplatApp

comptime MAX_ASSET = 67108864
"""The most bytes that `tm_alloc` gives: 64 MiB."""


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[SplatApp, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[SplatApp]()


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
) abi("C") -> OptionalPointer[SplatApp, MutUntrackedOrigin]:
    """Make an app with a frame of a size, and read the scan if it can.

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
        var app = SplatApp(w, h)
        _ = app.load_path(SCAN)
        var slot = alloc(Layout[SplatApp](count=1)).unsafe_leak()
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
    """Give an app its scan.

    Args:
        handle: A handle from `tm_create`.
        bytes: An `.spz` file, which the app copies before it returns.
        length: The file's size, in bytes.

    Returns:
        0 if the app has the scan, and the camera frames it. 1 if `length` is
        not positive, or the bytes are not an `.spz` file that the app can
        read. The scan is not changed then.
    """
    if length <= 0:
        return 1
    var file = List[UInt8](length=Int(length), fill=0)
    unsafe_memcpy(dest=file.unsafe_ptr(), src=bytes, count=Int(length))
    try:
        _app(handle)[].load(file)
    except:
        return 1
    return 0


@export("tm_resize")
def tm_resize(
    handle: OpaquePointer[MutUntrackedOrigin], width: Int32, height: Int32
) abi("C") -> Int32:
    """Change the size of an app's frame. The scan and the view stay.

    Args:
        handle: A handle from `tm_create`.
        width: The frame's new width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's new height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        0 if the frame has the new size. 1 if a side is out of range, and the
        frame is not changed.
    """
    var w = Int(width)
    var h = Int(height)
    if w > MAX_SIDE or h > MAX_SIDE:
        return 1
    try:
        _app(handle)[].resize(w, h)
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

    The space bar stops the camera's own turn, and starts it again when
    pressed again. Any other event goes to the orbit controls: a drag with the
    first button turns the camera, the second pans it, and the wheel dollies.
    An event that the controls refuse, such as one of an unknown kind, is
    dropped.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels.
        y: The pointer's row, in pixels.
        detail: The key code of a key event, the button of a pointer event,
            as `controls.input.PointerButton` numbers it, or -1, or the
            notches of a wheel event, positive toward the user.
    """
    _app(handle)[].handle(Int(kind), Int(x), Int(y), Int(detail))


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta.

    The controls apply what the events asked of the camera, and the camera
    turns by itself. Time that is negative is ignored. A single call counts at
    most 0.1 s.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step, in microseconds.
    """
    _app(handle)[].advance(Int(microseconds))


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Draw an app's scan on the CPU and return the frame.

    A scan that cannot be drawn leaves the last frame that could be. The
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


@export("tm_splat_prepare")
def tm_splat_prepare(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Int32:
    """Sort the splats and write the view that a host's GPU draws from.

    The host calls this after `tm_step`, and then reads the parts with
    `tm_splat_part`. It draws with the camera that `tm_frame` uses. The order
    and the view stay valid until the next call to this function.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        0 if the order and the view are ready. 1 if no scan is loaded, or the
        view cannot be prepared, and the parts are those of the last frame
        that could be.
    """
    try:
        if _app(handle)[].prepare() == 0:
            return 1
    except:
        return 1
    return 0


@export("tm_splat_part")
def tm_splat_part(
    handle: OpaquePointer[MutUntrackedOrigin], which: Int32
) abi("C") -> OptionalPointer[UInt8, MutUntrackedOrigin]:
    """Return where one array of the scan is in memory.

    Take a new view of the module's memory after every call to the module,
    because the memory can grow.

    Args:
        handle: A handle from `tm_create`.
        which: A `SPLAT_*` part number from `window.capi_abi`.

    Returns:
        The address of the part's first byte, or NULL while no scan is
        loaded, for a band that the scan lacks, for the order before
        `tm_splat_prepare`, and for a part number that does not exist.
    """
    var part = SplatPart(Int(which))
    if not part.is_valid():
        return None
    var found = _app(handle)[].part(part)
    if found[0] == 0:
        return None
    return Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=found[0])


@export("tm_splat_words")
def tm_splat_words(
    handle: OpaquePointer[MutUntrackedOrigin], which: Int32
) abi("C") -> Int32:
    """Return the size of one array of the scan.

    Args:
        handle: A handle from `tm_create`.
        which: A `SPLAT_*` part number from `window.capi_abi`.

    Returns:
        The size in 32-bit words. It is 0 where `tm_splat_part` is NULL.
    """
    var part = SplatPart(Int(which))
    if not part.is_valid():
        return 0
    return Int32(_app(handle)[].part(part)[1])


@export("tm_splat_info")
def tm_splat_info(
    handle: OpaquePointer[MutUntrackedOrigin], which: Int32
) abi("C") -> Int32:
    """Return one number about the scan.

    Args:
        handle: A handle from `tm_create`.
        which: A `SPLAT_INFO_*` number from `window.capi_abi`.

    Returns:
        The number. It is 0 for another `which`.
    """
    var info = SplatInfo(Int(which))
    if not info.is_valid():
        return 0
    return Int32(_app(handle)[].info(info))
