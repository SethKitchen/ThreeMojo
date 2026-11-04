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
"""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import FogView
from extensions.village.day import star_at
from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from std.math import isinf, sin
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
    # A frame has a pixel or more.
    for k in range(count):  # pragma: no branch
        mask[k] = image.depth[k] != before[k]
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
        # Each water pixel keeps the mirror image nearest the camera.
        var near = List[Float32](length=w * h, fill=Float32.MAX)
        var found = List[Int](length=w * h, fill=-1)
        var shake = TREMBLE * Float32(h) / 720
        # A frame has a pixel or more.
        for y in range(h):  # pragma: no branch
            var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
            for x in range(w):  # pragma: no branch
                var k = y * w + x
                var z = before[k]
                if mask[k] or isinf(z):
                    continue
                var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
                var at = inverse.transform_point(Vector3(nx, ny, z))
                if not (at.y > water + 0.01):
                    continue
                var image_at = clip.transform_point(
                    Vector3(at.x, 2 * water - at.y, at.z)
                )
                var ty = Int((1 - image_at.y) * 0.5 * Float32(h))
                if ty < 0 or ty >= h:
                    continue
                var wobble = shake * sin(Float32(ty) * 0.35 + self.clock * 2.1)
                var tx = Int((image_at.x + 1) * 0.5 * Float32(w) + wobble)
                if tx < 0 or tx >= w:
                    continue
                var t = ty * w + tx
                if mask[t] and image_at.z < near[t]:
                    near[t] = image_at.z
                    found[t] = k
        var shown = 0
        var mixed = List[UInt8](length=len(image.pixels), fill=0)
        for k in range(len(image.pixels)):  # pragma: no branch
            mixed[k] = image.pixels[k]
        for y in range(h):  # pragma: no branch
            for x in range(w):  # pragma: no branch
                var t = y * w + x
                if not mask[t]:
                    continue
                var source = found[t]
                # A stretched mirror image leaves rows between its own.
                var step = 1
                while source < 0 and step <= MIRROR_FILL:
                    if y - step >= 0 and found[t - step * w] >= 0:
                        source = found[t - step * w]
                    elif y + step < h and found[t + step * w] >= 0:
                        source = found[t + step * w]
                    step += 1
                if source < 0:
                    continue
                var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
                var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
                var a = inverse.transform_point(Vector3(nx, ny, -1))
                var b = inverse.transform_point(Vector3(nx, ny, 1))
                var d = b - a
                d = d / d.length()
                var share = min(
                    MIRROR_MOST, _fresnel(-d.y) * 1.15 * self.mirror
                )
                var p = t * 4
                var q = source * 4
                var lit = FloatColor(srgb=image.get_pixel(x, y))
                var seen = FloatColor(
                    srgb=Color(
                        image.pixels[q],
                        image.pixels[q + 1],
                        image.pixels[q + 2],
                        255,
                    )
                )
                # Water darkens what it mirrors a little, and greens it.
                var out = Vector3(
                    lit.r + (seen.r * 0.82 - lit.r) * share,
                    lit.g + (seen.g * 0.86 - lit.g) * share,
                    lit.b + (seen.b * 0.84 - lit.b) * share,
                )
                var c = FloatColor(out.x, out.y, out.z).encode()
                mixed[p] = c.r
                mixed[p + 1] = c.g
                mixed[p + 2] = c.b
                shown += 1
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
        var star = Vector3(1, 1, 0.95)
        var eye = camera.position
        for y in range(h):  # pragma: no branch
            var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
            for x in range(w):  # pragma: no branch
                var k = y * w + x
                if not mask[k]:
                    continue
                var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
                var at = inverse.transform_point(
                    Vector3(nx, ny, image.depth[k])
                )
                var lit = FloatColor(srgb=image.get_pixel(x, y))
                var c = Vector3(lit.r, lit.g, lit.b)
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
                        c = (
                            c
                            + (Vector3(seen.r, seen.g, seen.b) * star - c)
                            * share
                        )
                if fog.is_on():
                    var depth = -view.transform_point(at).z
                    var f = fog.factor_at(depth)
                    var g = fog.color
                    c = c + (Vector3(g.r, g.g, g.b) - c) * f
                var out = FloatColor(c.x, c.y, c.z).encode()
                var p = k * 4
                image.pixels[p] = out.r
                image.pixels[p + 1] = out.g
                image.pixels[p + 2] = out.b
