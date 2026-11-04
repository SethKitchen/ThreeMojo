# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI on the village game: walk, run, jump and fight in the village.

These are the functions of `window.capi_core`, with the same names and the
same meaning, so a host cannot tell the two apart. Here a call does real
work. `tm_event` holds and lets go of keys, `tm_step` runs one frame of the
game, and `tm_frame` draws the village into the window's frame. The rules
are in `window.village_app`, which has the game. It is the game of
`examples/village_walk.mojo --play`, without an X11 window.

Nothing may raise across a C boundary. Each call that can raise is caught
here, and the call then does nothing: an event that is not a key is dropped,
and a frame that cannot be drawn is the last one that could.

This module builds for the host only: the game uses lists, strings, errors
and threads. Never import this module and `window.capi_core` into one
program.

`tm_create` builds the village, and that takes seconds. It reads
`assets/pebbles.jpg` from the folder it runs in, or uses plain sand where it
cannot. The quality is named by the environment variable `THREEMOJO_QUALITY`:
`low`, `medium`, `high` or `ultra`, and `medium` where it is not set. The hour
the game begins at is `THREEMOJO_HOUR`, and its weather is `THREEMOJO_WEATHER`:
`clear`, `overcast`, `rain` or `fog`. See `window.village_app`.

A host with a GPU can draw the frame itself. The environment variable
`THREEMOJO_GPU`, set to `1`, makes a game for that: it draws at the window's
size. Each frame the host calls `tm_village_prepare`, which does the CPU's
share and describes the frame in three arrays: `tm_village_ints`,
`tm_village_floats` and `tm_village_pointers`, indexed as
`renderers.game_gpu` and `window/threemojo.h` number them. The host draws the
frame on its GPU into the image that two of the addresses name, and then calls
`tm_village_finish`, which returns the finished frame as `tm_frame` does.
A host that calls `tm_village_passes` first also draws the weather, the night,
the pond's water and the smoothing of edges on its GPU. The library then
leaves them out, and the host need not return the depths.

A host that is not a Mojo program must call `tm_init` once, before any other
function. The game's thread pool needs the runtime that `tm_init` starts, and
without it `tm_create` crashes.
"""

from std.runtime import initialize_runtime
from std.sys import stderr
from window.capi_abi import ABI_VERSION, MAX_SIDE
from window.village_app import (
    VillageApp,
    gpu_from_environment,
    hour_from_environment,
    new_app,
    play_parameters,
    quality_from_environment,
    read_bed,
    weather_from_environment,
)


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[VillageApp, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[VillageApp]()


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
) abi("C") -> OptionalPointer[VillageApp, MutUntrackedOrigin]:
    """Make the game, with a window of a size.

    Building the village takes seconds.

    Args:
        width: The window's width, in pixels, from 1 to `MAX_SIDE`.
        height: The window's height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        The app's handle, or NULL if a side is out of range, or the quality,
        the hour or the weather in the environment is not valid, or the
        village cannot be built.
    """
    var w = Int(width)
    var h = Int(height)
    if w > MAX_SIDE or h > MAX_SIDE:
        return None
    print("Building the village...", file=stderr)
    try:
        var gpu = gpu_from_environment()
        var parameters = play_parameters(quality_from_environment(), gpu)
        # A value that is not valid is refused before the village is built.
        var hour = hour_from_environment()
        var weather = weather_from_environment()
        return new_app(w, h, parameters, read_bed(), gpu, hour, weather)
    except:
        return None


@export("tm_destroy")
def tm_destroy(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> None:
    """Keep the game's progress, if it keeps it, and free an app. The handle
    must not be used again.

    Args:
        handle: A handle from `tm_create`.
    """
    var app = _app(handle)
    # The game keeps its progress as it ends, if it keeps it anywhere. A
    # file that cannot be written loses only this game's progress.
    try:
        app[].keep()
    except:
        print("The village's progress could not be kept", file=stderr)
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

    A key press holds the key, and a release lets it go. The keys are those
    of `window.village_app`: `W`, `A`, `S` and `D` move, the arrows look, the
    space bar jumps, and Shift, as `KEY_SHIFT`, runs. A pointer or a wheel
    event is dropped, and so is an event that is not a key.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels. The game does not use it.
        y: The pointer's row, in pixels. The game does not use it.
        detail: The key code of a key event.
    """
    try:
        _app(handle)[].handle(Int(kind), Int(detail))
    except:
        pass


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta.

    The player moves by what the held keys ask, the residents go about
    their day, and the weather and the hour move on. Time that is
    negative is ignored, and time over a tenth of a second counts as that.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step, in microseconds.
    """
    _app(handle)[].advance(Int(microseconds))


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Draw the village and return the frame.

    A frame that cannot be drawn is the last one that could.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The frame: RGBA, eight bits a channel, row by row from the top,
        `tm_width * tm_height * 4` bytes. It stays valid until the next
        call on this app.
    """
    var app = _app(handle)
    app[].draw()
    return Pointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(app[].game.window.pixels.unsafe_ptr())
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


@export("tm_village_passes")
def tm_village_passes(
    handle: OpaquePointer[MutUntrackedOrigin], on: Int32
) abi("C") -> Int32:
    """Let the host's GPU draw more of the frame, or take that back.

    With the passes on, the host draws the weather and the night with the sky,
    composes the pond's water over the triangles, and smooths the edges. The
    library then leaves out those passes in `tm_village_finish`, and asks for
    no depths. The host must draw each pass that the arrays of
    `tm_village_prepare` switch on. The call takes effect at the next
    `tm_village_prepare`.

    Args:
        handle: A handle from `tm_create`.
        on: 1 to take the passes, 0 to leave them to the CPU.

    Returns:
        1 if the app is one for a GPU, and the passes are as asked. 0 if it
        is not: the CPU draws everything.
    """
    if _app(handle)[].take_passes(on != 0):
        return 1
    return 0


@export("tm_village_prepare")
def tm_village_prepare(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Int32:
    """Prepare the frame that the last step left, for the host's GPU to draw.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        1 if the frame is prepared, and the three arrays describe it. 0 if
        the app is not one for a GPU, or the frame cannot be drawn: the host
        then draws nothing, and shows the last frame.
    """
    if _app(handle)[].prepare_gpu():
        return 1
    return 0


@export("tm_village_ints")
def tm_village_ints(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[Int64, MutUntrackedOrigin]:
    """Return the counts and the sizes of the prepared frame.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        `INT_COUNT` integers, by the `INT_*` numbers of `renderers.game_gpu`.
        They stay valid until the next call that prepares a frame.
    """
    return Pointer[Int64, MutUntrackedOrigin](
        unsafe_from_address=Int(_app(handle)[].frame.ints.unsafe_ptr())
    )


@export("tm_village_floats")
def tm_village_floats(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[Float32, MutUntrackedOrigin]:
    """Return the scalars of the prepared frame.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        `FLOAT_COUNT` floats, by the `FLOAT_*` numbers of
        `renderers.game_gpu`. They stay valid until the next call that
        prepares a frame.
    """
    return Pointer[Float32, MutUntrackedOrigin](
        unsafe_from_address=Int(_app(handle)[].frame.floats.unsafe_ptr())
    )


@export("tm_village_pointers")
def tm_village_pointers(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[Int64, MutUntrackedOrigin]:
    """Return the addresses of the data of the prepared frame.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        `POINTER_COUNT` addresses, by the `POINTER_*` numbers of
        `renderers.game_gpu`. The data stays valid until the next call that
        prepares a frame.
    """
    return Pointer[Int64, MutUntrackedOrigin](
        unsafe_from_address=Int(_app(handle)[].frame.pointers.unsafe_ptr())
    )


@export("tm_village_finish")
def tm_village_finish(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """End the frame that the host's GPU drew into the image of the prepared
    frame, and return it.

    The rain and the heads-up display are added on the CPU. So are the
    pond's water, the weather, the night and the smoothing of the edges,
    unless the host took them with `tm_village_passes`.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The frame, as `tm_frame` returns it. It stays valid until the next
        call on this app.
    """
    var app = _app(handle)
    app[].finish_gpu()
    return Pointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(app[].game.window.pixels.unsafe_ptr())
    )
