# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the village's pond shows after its water is composed.

The water of `extensions.water` is shaded by its own sky. It knows nothing
of the village round it. `PondLook` finishes a frame's water pixels with
three things from the village:

1. **The scene in the water.** Each pixel of the frame that stands above
   the water is mirrored in the water's plane and drawn where its mirror
   image falls on the water. The water's Fresnel share decides how much of
   it shows. A tremble moves the mirror image as the surface does. This is
   a screen-space planar reflection: what the frame does not show, the
   water cannot reflect, and it keeps the sky there.
2. **The fog.** The water fades into the scene's fog by its distance, as
   the triangles do.
3. **The stars.** At night the water mirrors the stars of the sky. See
   `DayCycle.night_sky`.

A pixel shows the water where the composition changed its depth.

Each step shares the frame's rows over every core. Each water pixel keeps
the nearest mirror image that any core offers it, and of equal depths the
first source, by an atomic least key, so the frame is the one that a
single core gives. The bytes are decoded by a table and encoded by
`SrgbBytes`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import FogView
from extensions.village.day import star_at
from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer, SrgbBytes
from render.tasks import TaskGroup
from renderers.renderer import available_workers
from extensions.village.air import linear_table
from std.atomic import Atomic
from std.math import floor, isinf, sin
from std.memory import bitcast
from units.si import METER, Length

comptime MIRROR_MOST = Float32(0.85)
"""The largest share of a water pixel that the mirrored scene takes."""
comptime MIRROR_FILL = 3
"""How many rows up and down a water pixel with no mirror image of its own
looks for one. A mirror image is stretched where the water is seen at a
slant, so its rows fall apart."""
comptime TREMBLE = Float32(1.5)
"""How far the mirror image trembles across, in pixels of a frame 720
pixels tall."""


def water_mask(image: Framebuffer, before: List[Float32]) raises -> List[Bool]:
    """Return which pixels of a frame show the water.

    Args:
        image: The frame, after the water was composed into it.
        before: Each pixel's depth before the water was composed.

    Returns:
        True for each pixel whose depth the composition changed.

    Raises:
        Error: If the depths are not one a pixel.
    """
    var count = image.width * image.height
    if len(before) != count or len(image.depth) != count:
        raise Error("A frame needs a depth for each pixel")
    var mask = List[Bool](length=count, fill=False)
    var now = image.depth.unsafe_ptr()
    var was = before.unsafe_ptr()
    var out = mask.unsafe_ptr()
    # A frame has a pixel or more.
    for k in range(count):  # pragma: no branch
        out[unsafe_offset=k] = now[unsafe_offset=k] != was[unsafe_offset=k]
    _ = len(image.depth)
    _ = len(before)
    return mask^


def _fresnel(cos_view: Float32) -> Float32:
    """Return Schlick's share of light that water reflects at an angle."""
    var c = min(Float32(1), max(Float32(0), cos_view))
    var m = 1 - c
    return 0.02 + 0.98 * m * m * m * m * m


struct PondLook(Copyable, Movable):
    """What finishes the pond's water in a frame: the mirrored scene, the
    fog and the stars."""

    var mirror: Float32
    """How much of the mirrored scene shows, from 0 to 1. One is the
    water's Fresnel share."""
    var clock: Float32
    """The time, in seconds, that moves the mirror image's tremble."""

    def __init__(out self):
        """Make a look that mirrors the scene at the water's full share."""
        self.mirror = 1
        self.clock = 0

    def apply(
        self,
        mut image: Framebuffer,
        before: List[Float32],
        camera: PerspectiveCamera,
        level: Length,
        fog: FogView,
        stars: Float32,
    ) raises -> Int:
        """Finish a frame's water: mirror the scene in it, mirror the
        stars, and fade it into the fog.

        Args:
            image: The frame, after the water was composed into it. Its
                water pixels are changed.
            before: Each pixel's depth before the water was composed.
            camera: The camera that drew the frame, placed.
            level: The height of the still water.
            fog: The scene's fog, as `FogView` resolves it.
            stars: How much the stars show, from 0 to 1: zero by day.

        Returns:
            How many water pixels show some of the mirrored scene.

        Raises:
            Error: If the depths are not one a pixel, the camera's matrices
                cannot be inverted, or `mirror` or `stars` is not from 0
                to 1.
        """
        if not (self.mirror >= 0 and self.mirror <= 1):
            raise Error("A pond's mirror must be from 0 to 1")
        if not (stars >= 0 and stars <= 1):
            raise Error("A pond's stars must be from 0 to 1")
        var mask = water_mask(image, before)
        var view = camera.view_matrix()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var inverse = clip
        inverse.invert()
        var mirrored = 0
        if self.mirror > 0:
            mirrored = self._mirror(image, mask, before, clip, inverse, level)
        self._sky_and_fog(image, mask, view, inverse, camera, fog, stars)
        return mirrored

    def _mirror(
        self,
        mut image: Framebuffer,
        mask: List[Bool],
        before: List[Float32],
        clip: Matrix4,
        inverse: Matrix4,
        level: Length,
    ) raises -> Int:
        """Draw the mirror image of the scene above the water into the
        water's pixels, and return how many show some of it."""
        var w = image.width
        var h = image.height
        var water = level.to(METER)
        # Each water pixel keeps the mirror image nearest the camera: the
        # least key of its depth and its source, which every core may
        # offer at once. See `_mirror_key`.
        var keys = List[UInt64](length=w * h, fill=UInt64.MAX)
        var shake = TREMBLE * Float32(h) / 720
        # Each row of the water trembles sideways by its own amount.
        var wobbles = List[Float32](capacity=h)
        for row in range(h):  # pragma: no branch
            wobbles.append(shake * sin(Float32(row) * 0.35 + self.clock * 2.1))
        var tasks = max(1, min(available_workers() * 2, h))
        var scatter = TaskGroup()
        for t in range(tasks):  # pragma: no branch
            scatter.create_task(
                _scatter_task(
                    before.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    mask.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    keys.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    w,
                    h,
                    Pointer(to=clip)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=inverse)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    water,
                    wobbles.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    t * h // tasks,
                    (t + 1) * h // tasks,
                )
            )
        scatter.wait()
        var mixed = image.pixels.copy()
        var linear = linear_table()
        var bytes = SrgbBytes()
        var counts = List[Int](length=tasks, fill=0)
        var group = TaskGroup()
        for t in range(tasks):  # pragma: no branch
            group.create_task(
                _blend_task(
                    image.pixels.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    mixed.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    mask.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    keys.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    w,
                    h,
                    Pointer(to=inverse)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self.mirror,
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
        var shown = 0
        for c in counts:  # pragma: no branch
            shown += c
        _ = len(keys)
        _ = len(wobbles)
        _ = len(mask)
        _ = len(linear)
        _ = bytes.byte(0)
        _ = inverse
        image.pixels = mixed^
        return shown

    def _sky_and_fog(
        self,
        mut image: Framebuffer,
        mask: List[Bool],
        view: Matrix4,
        inverse: Matrix4,
        camera: PerspectiveCamera,
        fog: FogView,
        stars: Float32,
    ) raises:
        """Add the mirrored stars to the water, and fade it into the fog."""
        if stars <= 0 and not fog.is_on():
            return
        var w = image.width
        var h = image.height
        var linear = linear_table()
        var bytes = SrgbBytes()
        var tasks = max(1, min(available_workers() * 2, h))
        var group = TaskGroup()
        for t in range(tasks):  # pragma: no branch
            group.create_task(
                _sky_task(
                    image.pixels.unsafe_ptr().unsafe_origin_cast[
                        MutAnyOrigin
                    ](),
                    image.depth.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    mask.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    w,
                    h,
                    Pointer(to=view)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=inverse)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    camera.position,
                    Pointer(to=fog)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    stars,
                    linear.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=bytes)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    t * h // tasks,
                    (t + 1) * h // tasks,
                )
            )
        group.wait()
        _ = len(mask)
        _ = len(linear)
        _ = bytes.byte(0)
        _ = view
        _ = inverse


__async def _blend_task(
    pixels: Pointer[UInt8, ImmutAnyOrigin],
    mixed: MutPointer[UInt8, MutAnyOrigin],
    mask: Pointer[Bool, ImmutAnyOrigin],
    keys: Pointer[UInt64, ImmutAnyOrigin],
    w: Int,
    h: Int,
    inverse: Pointer[Matrix4, ImmutAnyOrigin],
    mirror: Float32,
    linear: Pointer[Float32, ImmutAnyOrigin],
    bytes: Pointer[SrgbBytes, ImmutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    task: Int,
    first: Int,
    past: Int,
):
    """Blend the mirror image into the water pixels of rows `first` to
    `past`, and count those that show some of it."""
    var shown = 0
    for y in range(first, past):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var t = y * w + x
            if not mask[unsafe_offset=t]:
                continue
            var source = _source(keys, t)
            # A stretched mirror image leaves rows between its own.
            var step = 1
            while source < 0 and step <= MIRROR_FILL:
                if y - step >= 0 and _source(keys, t - step * w) >= 0:
                    source = _source(keys, t - step * w)
                elif y + step < h and _source(keys, t + step * w) >= 0:
                    source = _source(keys, t + step * w)
                step += 1
            if source < 0:
                continue
            var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
            var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
            var a = inverse[].transform_point(Vector3(nx, ny, -1))
            var b = inverse[].transform_point(Vector3(nx, ny, 1))
            var d = b - a
            d = d / d.length()
            var share = min(MIRROR_MOST, _fresnel(-d.y) * 1.15 * mirror)
            var p = t * 4
            var q = source * 4
            var lr = linear[unsafe_offset=Int(pixels[unsafe_offset=p])]
            var lg = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 1])]
            var lb = linear[unsafe_offset=Int(pixels[unsafe_offset=p + 2])]
            var sr = linear[unsafe_offset=Int(pixels[unsafe_offset=q])]
            var sg = linear[unsafe_offset=Int(pixels[unsafe_offset=q + 1])]
            var sb = linear[unsafe_offset=Int(pixels[unsafe_offset=q + 2])]
            # Water darkens what it mirrors a little, and greens it.
            mixed[unsafe_offset=p] = bytes[].byte(lr + (sr * 0.82 - lr) * share)
            mixed[unsafe_offset=p + 1] = bytes[].byte(
                lg + (sg * 0.86 - lg) * share
            )
            mixed[unsafe_offset=p + 2] = bytes[].byte(
                lb + (sb * 0.84 - lb) * share
            )
            shown += 1
    counts[unsafe_offset=task] = shown


__async def _sky_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    depth: Pointer[Float32, ImmutAnyOrigin],
    mask: Pointer[Bool, ImmutAnyOrigin],
    w: Int,
    h: Int,
    view: Pointer[Matrix4, ImmutAnyOrigin],
    inverse: Pointer[Matrix4, ImmutAnyOrigin],
    eye: Vector3,
    fog: Pointer[FogView, ImmutAnyOrigin],
    stars: Float32,
    linear: Pointer[Float32, ImmutAnyOrigin],
    bytes: Pointer[SrgbBytes, ImmutAnyOrigin],
    first: Int,
    past: Int,
):
    """Add the mirrored stars to the water pixels of rows `first` to
    `past`, and fade them into the fog."""
    var star = Vector3(1, 1, 0.95)
    var fogged = fog[].is_on()
    for y in range(first, past):  # pragma: no branch
        var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
        for x in range(w):  # pragma: no branch
            var k = y * w + x
            if not mask[unsafe_offset=k]:
                continue
            var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
            var at = inverse[].transform_point(
                Vector3(nx, ny, depth[unsafe_offset=k])
            )
            var p = k * 4
            var c = Vector3(
                linear[unsafe_offset=Int(pixels[unsafe_offset=p])],
                linear[unsafe_offset=Int(pixels[unsafe_offset=p + 1])],
                linear[unsafe_offset=Int(pixels[unsafe_offset=p + 2])],
            )
            if stars > 0:
                var d = at - eye
                d = d / d.length()
                var bright = star_at(Vector3(d.x, -d.y, d.z))
                if bright > 0:
                    var seen = FloatColor(
                        srgb=Color(
                            UInt8(Int(bright)),
                            UInt8(Int(bright)),
                            UInt8(Int(bright * 0.95)),
                            255,
                        )
                    )
                    # The water mirrors a star at its Fresnel share.
                    var share = (
                        stars
                        * _fresnel(-d.y)
                        * 3
                        * smoothstep(0.03, 0.12, -d.y)
                    )
                    share = min(Float32(1), share)
                    c = c + (Vector3(seen.r, seen.g, seen.b) * star - c) * share
            if fogged:
                var depth_at = -view[].transform_point(at).z
                var f = fog[].factor_at(depth_at)
                var g = fog[].color
                c = c + (Vector3(g.r, g.g, g.b) - c) * f
            pixels[unsafe_offset=p] = bytes[].byte(c.x)
            pixels[unsafe_offset=p + 1] = bytes[].byte(c.y)
            pixels[unsafe_offset=p + 2] = bytes[].byte(c.z)


@always_inline
def _source(keys: Pointer[UInt64, ImmutAnyOrigin], t: Int) -> Int:
    """Return the pixel whose mirror image a water pixel keeps, from its
    key, or -1 for none."""
    var key = keys[unsafe_offset=t]
    if key == UInt64.MAX:
        return -1
    return Int(key & 0xFFFFFFFF)


def _mirror_key(depth: Float32, source: Int) -> UInt64:
    """Return the key by which a water pixel keeps one mirror image: the
    least depth, and of equal depths the first source, as a walk over the
    sources in order with a strict `<` keeps.

    The depth's bits are turned so that they rise as the depth does, and
    stand over the source's.

    Args:
        depth: The mirror image's depth.
        source: The pixel it comes from, from 0 to below 2 to the 32.

    Returns:
        The key. A depth no less than the most float, or not a number, is
        never nearer than none: its key is the greatest, which a pixel
        with no mirror image holds.
    """
    if not (depth < Float32.MAX):
        return UInt64.MAX
    # Zero and minus zero are one depth.
    var bits = UInt64(bitcast[DType.uint32](depth + 0))
    var rising = bits | 0x80000000
    if bits & 0x80000000 != 0:
        rising = (~bits) & 0xFFFFFFFF
    return (rising << 32) | UInt64(source)


__async def _scatter_task(
    before: Pointer[Float32, ImmutAnyOrigin],
    mask: Pointer[Bool, ImmutAnyOrigin],
    keys: MutPointer[UInt64, MutAnyOrigin],
    w: Int,
    h: Int,
    clip: Pointer[Matrix4, ImmutAnyOrigin],
    inverse: Pointer[Matrix4, ImmutAnyOrigin],
    water: Float32,
    wobbles: Pointer[Float32, ImmutAnyOrigin],
    first: Int,
    past: Int,
):
    """Offer the mirror image of each pixel of rows `first` to `past` that
    stands above the water to the water pixel where it falls."""
    for y in range(first, past):  # pragma: no branch
        var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
        for x in range(w):  # pragma: no branch
            var k = y * w + x
            var z = before[unsafe_offset=k]
            if mask[unsafe_offset=k] or isinf(z):
                continue
            var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
            var at = inverse[].transform_point(Vector3(nx, ny, z))
            if not (at.y > water + 0.01):
                continue
            var image_at = clip[].transform_point(
                Vector3(at.x, 2 * water - at.y, at.z)
            )
            var ty = Int(floor((1 - image_at.y) * 0.5 * Float32(h)))
            if ty < 0 or ty >= h:
                continue
            var wobble = wobbles[unsafe_offset=ty]
            var tx = Int(floor((image_at.x + 1) * 0.5 * Float32(w) + wobble))
            if tx < 0 or tx >= w:
                continue
            var t = ty * w + tx
            if not mask[unsafe_offset=t]:
                continue
            var key = _mirror_key(image_at.z, k)
            var slot = keys.unsafe_offset(t)
            # A failed exchange loads what the slot holds into `held`. One
            # that succeeds leaves `held` as it was, so the next fails and
            # loads the key itself, which ends the loop.
            var held = Atomic[UInt64].fetch_add(slot, 0)
            while key < held:
                _ = Atomic[UInt64].compare_exchange(slot, held, key)
