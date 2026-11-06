# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The air of a finished frame: the glow round bright light, and the mist
that lies low on the ground.

Both work on a finished frame, after the triangles and the water, and
before the frame is stretched to the window:

1. **Bloom.** `bloom` finds the light brighter than a threshold: lamps,
   lit windows, fire, glints and lightning. It blurs that light over a
   frame a quarter of the size, and adds it back, so bright light glows
   into what is round it.

Both share the rows over every core, decode the bytes by a table and
encode them by `SrgbBytes`. So each is about fifteen times as fast as a
pixel at a time with a power each way, and gives the same bytes.
2. **Ground mist.** `ground_mist` veils each pixel by how low and how far
   its point is. The mist is thickest on the ground and thins over
   `MIST_HEIGHT` above it. It fades in over distance, so the near ground
   stays clear. It lies in the fog's color.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer, SrgbBytes
from render.srgb import srgb_to_linear
from render.tasks import TaskGroup
from renderers.renderer import available_workers
from std.math import exp, isinf

comptime BLOOM_SCALE = 4
"""How many pixels across and down of the frame one texel of the bloom's
blur covers."""
comptime BLOOM_REACH = 3
"""How many texels of the blur each side of a texel its box takes, in
each of its two passes."""
comptime MIST_HEIGHT = Float32(2.5)
"""How far above its base the ground mist thins to a third, in meters."""
comptime MIST_NEAR = Float32(25)
"""How far away, in meters, the ground mist has come in to two thirds."""


def _box(source: List[Float32], w: Int, h: Int, across: Bool) -> List[Float32]:
    """Return a box blur of three floats a texel, along one axis.

    A texel at least `BLOOM_REACH` texels from both ends reads its taps
    without the clamp at the edges. Every sum adds its taps from the
    lowest to the highest, as the clamped sum does, so the blur does not
    change."""
    var blurred = List[Float32](length=len(source), fill=0)
    var span = Float32(2 * BLOOM_REACH + 1)
    var src = source.unsafe_ptr()
    var out = blurred.unsafe_ptr()
    # A step of one texel along the axis, in floats.
    var stride = 3 if across else w * 3
    var reach = w if across else h
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var along = x if across else y
            var p = (y * w + x) * 3
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            if along >= BLOOM_REACH and along + BLOOM_REACH < reach:
                var at = p - BLOOM_REACH * stride
                comptime for _ in range(2 * BLOOM_REACH + 1):
                    r += src[unsafe_offset=at]
                    g += src[unsafe_offset=at + 1]
                    b += src[unsafe_offset=at + 2]
                    at += stride
            else:
                for k in range(
                    -BLOOM_REACH, BLOOM_REACH + 1
                ):  # pragma: no branch
                    var s = min(reach - 1, max(0, along + k))
                    var at = p + (s - along) * stride
                    r += src[unsafe_offset=at]
                    g += src[unsafe_offset=at + 1]
                    b += src[unsafe_offset=at + 2]
            out[unsafe_offset=p] = r / span
            out[unsafe_offset=p + 1] = g / span
            out[unsafe_offset=p + 2] = b / span
    _ = len(source)
    return blurred^


def linear_table() -> List[Float32]:
    """Return the linear light of each sRGB byte, as `FloatColor(srgb=...)`
    decodes it.

    Returns:
        256 values, one for each byte.
    """
    var table = List[Float32](capacity=256)
    for k in range(256):  # pragma: no branch
        table.append(srgb_to_linear(Float32(k) / 255))
    return table^


__async def _bright_task(
    pixels: Pointer[UInt8, ImmutAnyOrigin],
    width: Int,
    height: Int,
    linear: Pointer[Float32, ImmutAnyOrigin],
    threshold: Float32,
    small: MutPointer[Float32, MutAnyOrigin],
    small_width: Int,
    counts: MutPointer[Int, MutAnyOrigin],
    task: Int,
    first: Int,
    past: Int,
):
    """Gather the light past the threshold into the small frame's rows
    `first` to `past`, and count the bright pixels."""
    var share = 1 / Float32(BLOOM_SCALE * BLOOM_SCALE)
    var bright = 0
    for sy in range(first, past):  # pragma: no branch
        var top = sy * BLOOM_SCALE
        # A row of the small frame covers one row of the frame at least.
        for y in range(
            top, min(height, top + BLOOM_SCALE)
        ):  # pragma: no branch
            for x in range(width):  # pragma: no branch
                var p = (y * width + x) * 4
                var r = linear[unsafe_offset=Int(pixels[unsafe_offset=p])]
                var g = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 1])]
                var b = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 2])]
                var peak = max(r, max(g, b))
                if peak <= threshold:
                    continue
                bright += 1
                # Only the light past the threshold glows.
                var keep = (peak - threshold) / (1 - threshold) / peak
                var at = (sy * small_width + x // BLOOM_SCALE) * 3
                small[unsafe_offset=at] += r * keep * share
                small[unsafe_offset=at + 1] += g * keep * share
                small[unsafe_offset=at + 2] += b * keep * share
    counts[unsafe_offset=task] = bright


__async def _glow_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    linear: Pointer[Float32, ImmutAnyOrigin],
    bytes: Pointer[SrgbBytes, ImmutAnyOrigin],
    blurred: Pointer[Float32, ImmutAnyOrigin],
    small_width: Int,
    strength: Float32,
    first: Int,
    past: Int,
):
    """Add the blurred light back over rows `first` to `past`.

    Each cell of the small frame covers a block of `BLOOM_SCALE` pixels of
    a row: its light is read, and tested, once for the block."""
    for y in range(first, past):  # pragma: no branch
        var cells = (y // BLOOM_SCALE) * small_width
        for sx in range(small_width):  # pragma: no branch
            var at = (cells + sx) * 3
            var add_r = blurred[unsafe_offset=at] * strength
            var add_g = blurred[unsafe_offset=at + 1] * strength
            var add_b = blurred[unsafe_offset=at + 2] * strength
            if add_r + add_g + add_b <= 1.0e-4:
                continue
            var left = sx * BLOOM_SCALE
            # A cell covers one pixel of the row at least.
            for x in range(
                left, min(width, left + BLOOM_SCALE)
            ):  # pragma: no branch
                var p = (y * width + x) * 4
                var r = linear[unsafe_offset=Int(pixels[unsafe_offset=p])]
                var g = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 1])]
                var b = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 2])]
                pixels[unsafe_offset=p] = bytes[].byte(
                    min(Float32(1), r + add_r)
                )
                pixels[unsafe_offset=p + 1] = bytes[].byte(
                    min(Float32(1), g + add_g)
                )
                pixels[unsafe_offset=p + 2] = bytes[].byte(
                    min(Float32(1), b + add_b)
                )


def bloom(
    mut image: Framebuffer, threshold: Float32, strength: Float32
) raises -> Int:
    """Make the light brighter than a threshold glow into what is round it.

    The rows are shared over every core: each task gathers the bright
    light of its own rows of the small frame, and adds the glow back over
    its own rows of the frame. The bytes are decoded by a table and
    encoded by `SrgbBytes`, which give what `FloatColor` gives, so the
    frame is the same whatever the count of cores.

    Args:
        image: The frame. Its pixels are changed.
        threshold: The linear light, from 0 to 1, above which a pixel
            glows.
        strength: How much of the blurred light is added back, from 0 to
            4.

    Returns:
        How many pixels were bright enough to glow.

    Raises:
        Error: If the threshold is not from 0 to below 1, or the strength
            is not from 0 to 4.
    """
    if not (threshold >= 0 and threshold < 1):
        raise Error("A bloom's threshold must be from 0 to below 1")
    if not (strength >= 0 and strength <= 4):
        raise Error("A bloom's strength must be from 0 to 4")
    var w = image.width
    var h = image.height
    var sw = (w + BLOOM_SCALE - 1) // BLOOM_SCALE
    var sh = (h + BLOOM_SCALE - 1) // BLOOM_SCALE
    var small = List[Float32](length=sw * sh * 3, fill=0)
    var linear = linear_table()
    var reading = (
        linear.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )
    var tasks = max(1, min(available_workers() * 2, sh))
    var counts = List[Int](length=tasks, fill=0)
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _bright_task(
                image.pixels.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                w,
                h,
                reading,
                threshold,
                small.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                sw,
                counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                t,
                t * sh // tasks,
                (t + 1) * sh // tasks,
            )
        )
    group.wait()
    var bright = 0
    for c in counts:  # pragma: no branch
        bright += c
    if bright == 0 or strength == 0:
        return bright
    var blurred = _box(_box(small, sw, sh, True), sw, sh, False)
    blurred = _box(_box(blurred, sw, sh, True), sw, sh, False)
    var bytes = SrgbBytes()
    var adding = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        adding.create_task(
            _glow_task(
                image.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                w,
                reading,
                Pointer(to=bytes)
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                blurred.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                sw,
                strength,
                t * h // tasks,
                (t + 1) * h // tasks,
            )
        )
    adding.wait()
    _ = len(linear)
    _ = len(blurred)
    _ = len(small)
    _ = len(counts)
    _ = bytes.byte(0)
    return bright


def ground_mist(
    mut image: Framebuffer,
    camera: PerspectiveCamera,
    base: Float32,
    thickness: Float32,
    color: Color,
) raises -> Int:
    """Veil a frame with mist that lies low on the ground.

    A pixel's point is found from its depth. Its veil is `thickness`,
    thinned by how far its point stands above `base` and by how near it
    is. A pixel of the sky keeps its color.

    Args:
        image: The frame, with a depth for each pixel. Its pixels are
            changed.
        camera: The camera that drew it, placed.
        base: The height of the mist's base, in meters.
        thickness: How much of a far, low point the mist hides, from 0 to
            1.
        color: The mist's color, in sRGB.

    Returns:
        How many pixels the mist veiled.

    Raises:
        Error: If the frame has no depth for each pixel, the thickness is
            not from 0 to 1, or the camera's matrices cannot be inverted.
    """
    var w = image.width
    var h = image.height
    if len(image.depth) != w * h:
        raise Error("A frame needs a depth for each pixel")
    if not (thickness >= 0 and thickness <= 1):
        raise Error("A mist's thickness must be from 0 to 1")
    if thickness == 0:
        return 0
    var inverse = camera.projection_matrix()
    inverse.multiply(camera.view_matrix())
    inverse.invert()
    var linear = linear_table()
    var bytes = SrgbBytes()
    var tasks = max(1, min(available_workers() * 2, h))
    var counts = List[Int](length=tasks, fill=0)
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _mist_task(
                image.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                image.depth.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                w,
                h,
                Pointer(to=inverse)
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                camera.position,
                base,
                thickness,
                FloatColor(srgb=color),
                linear.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=bytes)
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                t,
                t * h // tasks,
                (t + 1) * h // tasks,
            )
        )
    group.wait()
    var veiled = 0
    for c in counts:  # pragma: no branch
        veiled += c
    _ = len(linear)
    _ = bytes.byte(0)
    _ = inverse
    return veiled


__async def _mist_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    depth: Pointer[Float32, ImmutAnyOrigin],
    width: Int,
    height: Int,
    inverse: Pointer[Matrix4, ImmutAnyOrigin],
    eye: Vector3,
    base: Float32,
    thickness: Float32,
    mist: FloatColor,
    linear: Pointer[Float32, ImmutAnyOrigin],
    bytes: Pointer[SrgbBytes, ImmutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    task: Int,
    first: Int,
    past: Int,
):
    """Veil rows `first` to `past` with the mist, and count the pixels it
    veils."""
    var veiled = 0
    for y in range(first, past):  # pragma: no branch
        var ny = 1 - (Float32(y) + 0.5) / Float32(height) * 2
        # A row's points are mixed from its fixed terms: only `nx` and the
        # depth change along it.
        ref e = inverse[].elements
        var row_x = e[4] * ny + e[12]
        var row_y = e[5] * ny + e[13]
        var row_z = e[6] * ny + e[14]
        var row_w = e[7] * ny + e[15]
        for x in range(width):  # pragma: no branch
            var k = y * width + x
            var z = depth[unsafe_offset=k]
            if isinf(z):
                continue
            var nx = (Float32(x) + 0.5) / Float32(width) * 2 - 1
            var inv = 1 / (e[3] * nx + e[11] * z + row_w)
            var at = Vector3(
                (e[0] * nx + e[8] * z + row_x) * inv,
                (e[1] * nx + e[9] * z + row_y) * inv,
                (e[2] * nx + e[10] * z + row_z) * inv,
            )
            var high = max(Float32(0), at.y - base)
            var far = (at - eye).length()
            var share = (
                thickness
                * exp(-high / MIST_HEIGHT)
                * (1 - exp(-far / MIST_NEAR))
            )
            if share <= 1.0e-3:
                continue
            veiled += 1
            var p = k * 4
            var r = linear[unsafe_offset=Int(pixels[unsafe_offset=p])]
            var g = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 1])]
            var b = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 2])]
            pixels[unsafe_offset=p] = bytes[].byte(r + (mist.r - r) * share)
            pixels[unsafe_offset=p + 1] = bytes[].byte(g + (mist.g - g) * share)
            pixels[unsafe_offset=p + 2] = bytes[].byte(b + (mist.b - b) * share)
    counts[unsafe_offset=task] = veiled
