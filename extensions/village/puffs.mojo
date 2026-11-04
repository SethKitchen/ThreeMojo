# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Puffs of smoke and dust, drawn over a finished frame.

The renderers draw opaque triangles only, so a soft, see-through puff is
drawn after them. `draw_puffs` blends each `Puff` into a frame as a soft
disc that faces the camera. The disc is thickest in its middle and fades
to nothing at its rim. A pixel nearer than the puff's middle keeps its
color, so a puff behind a wall does not show through it. The puffs are
drawn far to near.

A puff has no state of its own. `chimney_smoke` finds the puffs over a
chimney at a time from the time alone, so the same time gives the same
smoke. Each puff rises from the pot, drifts with the wind, grows and
fades over `SMOKE_LIFE`, and a new one leaves the pot as it goes.
`dust_puffs` finds the dust that a foot kicks up.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from std.math import cos, sin, sqrt

comptime SMOKE_PUFFS = 14
"""How many puffs a chimney's smoke shows at once."""
comptime SMOKE_LIFE = Float32(8)
"""How long a puff of smoke lasts, in seconds."""
comptime SMOKE_RISE = Float32(0.55)
"""How fast a puff of smoke rises from the pot, in meters a second."""
comptime SMOKE_GRAY = Vector3(0.62, 0.62, 0.64)
"""The linear color of chimney smoke in full daylight."""
comptime DUST_TAN = Vector3(0.42, 0.34, 0.24)
"""The linear color of dust from dry ground."""
comptime NEAREST = Float32(0.3)
"""How near the camera, in meters, a puff can come and still be drawn."""


@fieldwise_init
struct Puff(Copyable, ImplicitlyCopyable):
    """A soft, see-through ball of smoke or dust."""

    var at: Vector3
    """Its middle, in meters."""
    var radius: Float32
    """How far it reaches from its middle, in meters."""
    var opacity: Float32
    """How much it hides of what is behind its middle, from 0 to 1."""
    var color: Vector3
    """Its linear color."""


def chimney_smoke(
    top: Vector3, seconds: Float32, wind: Vector3, seed: Int
) -> List[Puff]:
    """Return the puffs of smoke over a chimney at a time.

    Args:
        top: The top of the chimney's pot, in meters.
        seconds: The time, in seconds.
        wind: The wind that carries the smoke, in meters a second. Only
            its level part moves the smoke.
        seed: Which chimney: chimneys of different seeds puff out of step.

    Returns:
        `SMOKE_PUFFS` puffs, the oldest first.
    """
    var puffs = List[Puff]()
    var step = SMOKE_LIFE / Float32(SMOKE_PUFFS)
    var shift = Float32(seed % 97) * 0.731
    for k in range(SMOKE_PUFFS):  # pragma: no branch
        var clock = seconds + shift + Float32(k) * step
        var age = clock - SMOKE_LIFE * Float32(Int(clock / SMOKE_LIFE))
        if age < 0:
            age += SMOKE_LIFE
        var t = age / SMOKE_LIFE
        # The puff slows as it rises, and the wind bends it over.
        var rise = SMOKE_RISE * age * (1 - 0.35 * t)
        var sway = 0.18 * t * sin(age * 1.3 + Float32(k) * 2.1)
        var at = (
            top
            + Vector3(wind.x * age, rise, wind.z * age) * 0.9
            + Vector3(sway, 0, 0.6 * sway * cos(age * 0.9))
        )
        # It thickens as it leaves the pot, then thins as it spreads.
        var grow = min(Float32(1), t * 16)
        var fade = (1 - t) * sqrt(1 - t)
        puffs.append(Puff(at, 0.22 + 1.2 * t, 0.75 * grow * fade, SMOKE_GRAY))
    return puffs^


def dust_puffs(
    foot: Vector3, seconds: Float32, since: Float32, seed: Int
) -> List[Puff]:
    """Return the dust that a foot kicked up `since` seconds ago.

    Args:
        foot: Where the foot struck the ground, in meters.
        seconds: The time, in seconds, which stirs the dust.
        since: How long ago the foot struck, in seconds. The dust settles
            after one second.
        seed: Which dust.

    Returns:
        Five puffs round the foot, or none once the dust settles.
    """
    var puffs = List[Puff]()
    if since < 0 or since >= 1:
        return puffs^
    for k in range(5):  # pragma: no branch
        var a = Float32(k) * 1.2566371 + Float32(seed % 13) * 0.5
        var spread = 0.15 + 0.5 * since
        var at = foot + Vector3(
            spread * cos(a), 0.1 + 0.25 * since, spread * sin(a)
        )
        var wobble = 0.02 * sin(seconds * 7 + Float32(k))
        puffs.append(
            Puff(
                at + Vector3(wobble, 0, 0),
                0.12 + 0.3 * since,
                0.35 * (1 - since),
                DUST_TAN,
            )
        )
    return puffs^


def draw_puffs(
    mut image: Framebuffer,
    puffs: List[Puff],
    camera: PerspectiveCamera,
    light: Float32,
) raises -> Int:
    """Blend puffs into a frame, far to near.

    Args:
        image: The frame, with a depth for each pixel. Its pixels are
            changed.
        puffs: The puffs.
        camera: The camera that drew the frame, placed.
        light: How much light the puffs catch, from 0 at night to 1 by
            day.

    Returns:
        How many puffs showed in the frame.

    Raises:
        Error: If the frame has no depth for each pixel, the light is not
            from 0 to 1, or the camera's matrices cannot be made.
    """
    var w = image.width
    var h = image.height
    if len(image.depth) != w * h:
        raise Error("A frame needs a depth for each pixel")
    if not (light >= 0 and light <= 1):
        raise Error("A puff's light must be from 0 to 1")
    var view = camera.view_matrix()
    var clip = camera.projection_matrix()
    clip.multiply(view)
    var eye = camera.position
    # Far to near, so a near puff covers a far one.
    var order = List[Int]()
    var far = List[Float32]()
    for k in range(len(puffs)):
        var d = (puffs[k].at - eye).length()
        var at = len(order)
        while at > 0 and far[at - 1] < d:
            at -= 1
        order.insert(at, k)
        far.insert(at, d)
    var shown = 0
    for index in order:
        ref puff = puffs[index]
        if puff.opacity <= 0:
            continue
        # A puff behind the camera, or round it, is not drawn.
        var ahead = -view.transform_point(puff.at).z
        if ahead < NEAREST + puff.radius:
            continue
        var middle = clip.transform_point(puff.at)
        if middle.z < -1 or middle.z > 1:
            continue
        var rim = clip.transform_point(puff.at + Vector3(0, puff.radius, 0))
        var cx = (middle.x + 1) * 0.5 * Float32(w)
        var cy = (1 - middle.y) * 0.5 * Float32(h)
        var ry = (rim.y - middle.y) * 0.5 * Float32(h)
        var reach = max(abs(ry), Float32(0.5))
        var x0 = max(0, Int(cx - reach))
        var x1 = min(w - 1, Int(cx + reach) + 1)
        var y0 = max(0, Int(cy - reach))
        var y1 = min(h - 1, Int(cy + reach) + 1)
        if x0 > x1 or y0 > y1:
            continue
        shown += 1
        var tint = puff.color * light
        for y in range(y0, y1 + 1):  # pragma: no branch
            for x in range(x0, x1 + 1):  # pragma: no branch
                var k = y * w + x
                # Nearer geometry hides the puff.
                if image.depth[k] < middle.z:
                    continue
                var dx = (Float32(x) + 0.5 - cx) / reach
                var dy = (Float32(y) + 0.5 - cy) / reach
                var d2 = dx * dx + dy * dy
                if d2 >= 1:
                    continue
                var soft = 1 - d2
                var alpha = puff.opacity * soft * sqrt(soft)
                var c = FloatColor(srgb=image.get_pixel(x, y))
                var mixed = FloatColor(
                    c.r + (tint.x - c.r) * alpha,
                    c.g + (tint.y - c.g) * alpha,
                    c.b + (tint.z - c.b) * alpha,
                ).encode()
                var p = k * 4
                image.pixels[p] = mixed.r
                image.pixels[p + 1] = mixed.g
                image.pixels[p + 2] = mixed.b
    return shown
