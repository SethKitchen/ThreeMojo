# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tree crowns for the woods that stand at a distance: a whole tree in a few
hundred triangles that still reads as that tree.

A tree stands close to the camera as a branching skeleton with a card of
leaves at every twig, which costs ten thousand triangles. A wood a kilometer
away is a thousand trees a few dozen pixels high, and each of them needs the
silhouette, the layers and the shade of its kind, not its twigs. Four crowns
cover the distances.

- `spruce` is a trunk with tiers of drooping branches. A tier is a whorl of
  sprays, and the tiers narrow to the top. A few branches are missing, so the
  crown has gaps. A larch is a spruce with a wider, lighter crown, and a fir
  one with a narrow crown and close tiers.
- `broadleaf_crown` is a trunk with boughs and a crown of clusters of crossed
  leaf cards on a shell of an ellipsoid.
- `cone_crown` and `ball_crown` are the farthest trees: stacked cones and a
  squashed ball, with no card at all.

Every vertex has a color that is the shade of the tree at that place: the
inside of the crown and the lower tiers lie in the shade of the rest, and the
tips and the top catch the light. The color of an instance tints it, so one
shape stands for a wood in autumn.

The frame is that of `MeshBuilder`: z up, the foot at the origin.
"""

from extensions.castle.parts import _push, unit_noise
from extensions.castle.trees import TreeShape
from extensions.visual.mesh import MeshBuilder
from generators.utils import Vec3d
from std.math import cos, pi, pow, sin, sqrt


def _card(
    mut mesh: MeshBuilder,
    a: Vec3d,
    b: Vec3d,
    c: Vec3d,
    d: Vec3d,
    na: Vec3d,
    nb: Vec3d,
    nc: Vec3d,
    nd: Vec3d,
    ca: Vec3d,
    cb: Vec3d,
    cc: Vec3d,
    cd: Vec3d,
    v0: Float64,
    v1: Float64,
):
    """Add a card of four corners, a b c d, with the texture from v0 to v1
    along its length and from 0 to 1 across it."""
    _push(mesh, a, na, (0.0, v0), ca)
    _push(mesh, b, nb, (1.0, v0), cb)
    _push(mesh, c, nc, (1.0, v1), cc)
    _push(mesh, a, na, (0.0, v0), ca)
    _push(mesh, c, nc, (1.0, v1), cc)
    _push(mesh, d, nd, (0.0, v1), cd)


def _shade(light: Float64) -> Vec3d:
    """Return the gray of a vertex that gets a share of the light."""
    var value = min(max(light, 0.0), 1.0)
    return Vec3d(value, value * 0.98, value * 0.94)


def _spray(
    mut mesh: MeshBuilder,
    angle: Float64,
    z: Float64,
    length: Float64,
    width: Float64,
    droop: Float64,
    tier_light: Float64,
    lift: Float64,
):
    """Add a spray of needles that leaves the trunk at a height and an angle,
    sags toward its tip, and is darkest where it joins the trunk."""
    var away = Vec3d(cos(angle), sin(angle), 0.0)
    var side = Vec3d(-away.y, away.x, 0.0)
    var rows = 3
    var radius = List[Float64]()
    var height = List[Float64]()
    var half = List[Float64]()
    var light = List[Float64]()
    for k in range(rows):  # pragma: no branch
        var tau = Float64(k) / Float64(rows - 1)
        radius.append(0.12 + tau * length)
        height.append(z + lift * length * tau - droop * length * tau * tau)
        var taper = 1.0 - 0.45 * tau * tau
        half.append(
            0.5 * width * (0.62 + 0.38 * sin(pi * (0.2 + 0.8 * tau))) * taper
        )
        light.append(tier_light * (0.42 + 0.58 * tau))
    for k in range(rows - 1):  # pragma: no branch
        var p0 = away * radius[k] + Vec3d(0, 0, height[k])
        var p1 = away * radius[k + 1] + Vec3d(0, 0, height[k + 1])
        var a = p0 - side * half[k]
        var b = p0 + side * half[k]
        var c = p1 + side * half[k + 1]
        var d = p1 - side * half[k + 1]
        var slope = (p1 - p0).normalized()
        # The card is level across and slopes along the branch, so this
        # normal points up.
        var up = slope.cross(side).normalized()
        var n = (up * 0.7 + away * 0.45).normalized()
        _card(
            mesh,
            a,
            b,
            c,
            d,
            n,
            n,
            n,
            n,
            _shade(light[k]),
            _shade(light[k]),
            _shade(light[k + 1]),
            _shade(light[k + 1]),
            Float64(k) / Float64(rows - 1),
            Float64(k + 1) / Float64(rows - 1),
        )


def spruce(
    seed: Int,
    height: Float64,
    tiers: Int,
    droop: Float64,
    spread: Float64,
) raises -> TreeShape:
    """Grow a conifer of tiers of drooping sprays.

    Args:
        seed: Where the random numbers start.
        height: The height of the tree, in meters.
        tiers: The tiers of branches, 4 or more.
        droop: How far a branch sags, as a share of its length: 0.3 for a
            spruce, 0.15 for a larch.
        spread: The width of the crown as a share of a spruce's: 1 for a
            spruce, 0.7 for a fir, 1.25 for a larch.

    Returns:
        The tree, with its bark and its needles.

    Raises:
        Error: If the trunk cannot be built.
    """
    if tiers < 4:
        raise Error("A spruce needs four tiers at least")
    var bark = MeshBuilder()
    var needles = MeshBuilder()
    var white = Vec3d(1, 1, 1)
    bark.tube(
        Vec3d(0, 0, -0.4),
        Vec3d(0, 0, height * 0.32),
        0.015 * height + 0.05,
        0.0,
        7,
        white,
        white,
    )
    bark.tube(
        Vec3d(0, 0, height * 0.32),
        Vec3d(0, 0, height * 0.96),
        0.006 * height + 0.03,
        0.0,
        5,
        white,
        white,
    )
    var base = height * 0.14
    var span = height - base
    for k in range(tiers):  # pragma: no branch
        var t = Float64(k) / Float64(tiers - 1)
        var z = base + span * pow(t, 0.9)
        var reach = spread * height * 0.2 * pow(1.0 - t, 0.82) + 0.3
        var branches = 5 + Int(3.0 * (1.0 - t)) + (k % 2)
        var turn = unit_noise(Float64(k), 1.0, seed) * 2.0 * pi
        var tier_light = 0.5 + 0.5 * t
        for b in range(branches):  # pragma: no branch
            # A few branches are missing: gaps in the crown.
            if unit_noise(Float64(k * 13 + b), 3.0, seed + 1) < 0.1:
                continue
            var angle = turn + 2.0 * pi * (
                Float64(b) + 0.4 * unit_noise(Float64(k), Float64(b), seed + 2)
            ) / Float64(branches)
            var length = reach * (
                0.8 + 0.4 * unit_noise(Float64(k), Float64(b + 7), seed + 3)
            )
            var width = max(0.9, 0.5 * length)
            var shade = tier_light * (
                0.92 + 0.16 * unit_noise(Float64(k), Float64(b), seed + 4)
            )
            _spray(needles, angle, z, length, width, droop, shade, 0.0)
            # A second, shorter spray above the first on the lower tiers.
            if t < 0.6:
                _spray(
                    needles,
                    angle + 0.35,
                    z + 0.08 * length,
                    length * 0.62,
                    width * 0.7,
                    droop * 0.7,
                    shade * 1.05,
                    0.12,
                )
    return TreeShape(bark.geometry(), needles.geometry(), height)


def _cluster(
    mut mesh: MeshBuilder,
    center: Vec3d,
    outward: Vec3d,
    size: Float64,
    light: Float64,
    seed: Int,
):
    """Add a cluster of three crossed cards of leaves at a point of a crown.
    The normals bend outward so that the crown shades like a mass."""
    var up = Vec3d(0, 0, 1)
    for k in range(3):
        var turn = (
            Float64(k) * 2.0 * pi / 3.0
            + unit_noise(Float64(k), 5.0, seed) * 0.8
        )
        var tilt = 0.35 + 0.5 * unit_noise(Float64(k), 9.0, seed + 1)
        var n = Vec3d(cos(turn) * sin(tilt), sin(turn) * sin(tilt), cos(tilt))
        # The tilt is at least 0.35 radian, so the normal is never upright and
        # the cross product has a length.
        var right = n.cross(up).normalized()
        var spine = n.cross(right).normalized()
        var half = (
            size * 0.5 * (0.8 + 0.4 * unit_noise(Float64(k), 11.0, seed + 2))
        )
        var bent = (n + outward * 0.9).normalized()
        var a = center - right * half - spine * half
        var b = center + right * half - spine * half
        var c = center + right * half + spine * half
        var d = center - right * half + spine * half
        # The upper edge of a card catches more light than the lower.
        var low = _shade(light * 0.8)
        var high = _shade(light * 1.05)
        _card(
            mesh,
            a,
            b,
            c,
            d,
            bent,
            bent,
            bent,
            bent,
            low,
            low,
            high,
            high,
            0.0,
            1.0,
        )


def broadleaf_crown(
    seed: Int, height: Float64, clusters: Int
) raises -> TreeShape:
    """Grow a broadleaf tree of a trunk, boughs and a round crown of
    clusters of leaf cards.

    Args:
        seed: Where the random numbers start.
        height: The height of the tree, in meters.
        clusters: The clusters of leaves, 8 or more.

    Returns:
        The tree, with its bark and its leaves.

    Raises:
        Error: If the trunk cannot be built.
    """
    if clusters < 8:
        raise Error("A crown needs eight clusters at least")
    var bark = MeshBuilder()
    var leaves = MeshBuilder()
    var white = Vec3d(1, 1, 1)
    bark.tube(
        Vec3d(0, 0, -0.4),
        Vec3d(0, 0, height * 0.36),
        0.022 * height + 0.05,
        0.0,
        7,
        white,
        white,
    )
    var center = Vec3d(0, 0, height * 0.62)
    var rx = height * 0.4
    var rz = height * 0.34
    for k in range(4):
        var angle = (
            Float64(k) * 0.5 * pi + unit_noise(Float64(k), 2.0, seed) * 0.9
        )
        var tip = center + Vec3d(
            cos(angle) * rx * 0.55, sin(angle) * rx * 0.55, -rz * 0.25
        )
        bark.tube(
            Vec3d(0, 0, height * 0.32),
            tip,
            0.011 * height + 0.03,
            0.0,
            5,
            white,
            white,
        )
    var golden = pi * (3.0 - sqrt(5.0))
    for i in range(clusters):  # pragma: no branch
        var fraction = (Float64(i) + 0.5) / Float64(clusters)
        var polar = 1.0 - 2.0 * fraction
        var ring = sqrt(max(0.0, 1.0 - polar * polar))
        var azimuth = golden * Float64(i) + unit_noise(
            Float64(i), 1.0, seed + 6
        )
        var shell = 0.55 + 0.45 * unit_noise(Float64(i), 4.0, seed + 7)
        var direction = Vec3d(ring * cos(azimuth), ring * sin(azimuth), polar)
        var at = center + Vec3d(
            direction.x * rx * shell,
            direction.y * rx * shell,
            direction.z * rz * shell,
        )
        # Lit from above and from outside; the lower, inner clusters are dark.
        var above = (at.z - (center.z - rz)) / (2.0 * rz)
        var light = (0.42 + 0.58 * above) * (0.62 + 0.38 * shell)
        var size = (
            height * 0.3 * (0.8 + 0.45 * unit_noise(Float64(i), 8.0, seed + 8))
        )
        _cluster(leaves, at, direction, size, light, seed + 31 * i)
    return TreeShape(bark.geometry(), leaves.geometry(), height)


def cone_crown(seed: Int, height: Float64) raises -> TreeShape:
    """Make the farthest conifer: three stacked cones with no card.

    Args:
        seed: Where the random numbers start.
        height: The height of the tree, in meters.

    Returns:
        The tree. Its bark is empty; its crown has a color at each vertex.

    Raises:
        Error: If the geometry cannot be built.
    """
    var crown = MeshBuilder()
    var sides = 8
    for tier in range(3):
        var t = Float64(tier) / 3.0
        var z0 = height * (0.1 + 0.28 * t * 2.0)
        var z1 = height * (0.1 + 0.28 * t * 2.0 + 0.46 - 0.12 * Float64(tier))
        var radius = height * 0.2 * (1.0 - 0.32 * Float64(tier))
        var turn = unit_noise(Float64(tier), 1.0, seed) * pi
        var apex = Vec3d(0, 0, z1 + height * 0.1 * (1.0 if tier == 2 else 0.0))
        var light = 0.45 + 0.28 * Float64(tier)
        for k in range(sides):  # pragma: no branch
            var a0 = turn + 2.0 * pi * Float64(k) / Float64(sides)
            var a1 = turn + 2.0 * pi * Float64(k + 1) / Float64(sides)
            var p0 = Vec3d(cos(a0) * radius, sin(a0) * radius, z0)
            var p1 = Vec3d(cos(a1) * radius, sin(a1) * radius, z0)
            var mid = (a0 + a1) * 0.5
            var n = Vec3d(cos(mid), sin(mid), 0.55).normalized()
            crown.smooth_triangle(
                p0,
                p1,
                apex,
                n,
                n,
                n,
                _shade(light * 0.8),
                _shade(light * 0.8),
                _shade(light * 1.15),
            )
    return TreeShape(MeshBuilder().geometry(), crown.geometry(), height)


def _lump(
    band: Int, around_at: Int, around: Int, bands: Int, seed: Int
) -> Float64:
    """Return the radius of a vertex of a ball as a share of its mean: the
    poles stay at one, and the vertex before the seam is the first."""
    if band == 0 or band == bands:
        return 0.82
    var k = around_at % around
    return 0.8 + 0.4 * unit_noise(Float64(band), Float64(k), seed)


def ball_crown(seed: Int, height: Float64) raises -> TreeShape:
    """Make the farthest broadleaf tree: a squashed ball on a short trunk.

    Args:
        seed: Where the random numbers start.
        height: The height of the tree, in meters.

    Returns:
        The tree. Its bark is empty; its crown has a color at each vertex.

    Raises:
        Error: If the geometry cannot be built.
    """
    var crown = MeshBuilder()
    var bands = 5
    var around = 10
    var center = Vec3d(0, 0, height * 0.62)
    var rx = height * 0.38
    var rz = height * 0.36
    for band in range(bands):  # pragma: no branch
        var p0 = pi * Float64(band) / Float64(bands)
        var p1 = pi * Float64(band + 1) / Float64(bands)
        for k in range(around):  # pragma: no branch
            var a0 = 2.0 * pi * Float64(k) / Float64(around)
            var a1 = 2.0 * pi * Float64(k + 1) / Float64(around)
            var n00 = Vec3d(sin(p0) * cos(a0), sin(p0) * sin(a0), cos(p0))
            var n10 = Vec3d(sin(p0) * cos(a1), sin(p0) * sin(a1), cos(p0))
            var n01 = Vec3d(sin(p1) * cos(a0), sin(p1) * sin(a0), cos(p1))
            var n11 = Vec3d(sin(p1) * cos(a1), sin(p1) * sin(a1), cos(p1))
            # The hull is lumpy: each vertex stands at its own radius, and the
            # vertices that two cells share take the same one.
            var f00 = _lump(band, k, around, bands, seed)
            var f10 = _lump(band, k + 1, around, bands, seed)
            var f01 = _lump(band + 1, k, around, bands, seed)
            var f11 = _lump(band + 1, k + 1, around, bands, seed)
            var s00 = center + Vec3d(
                n00.x * rx * f00, n00.y * rx * f00, n00.z * rz * f00
            )
            var s10 = center + Vec3d(
                n10.x * rx * f10, n10.y * rx * f10, n10.z * rz * f10
            )
            var s01 = center + Vec3d(
                n01.x * rx * f01, n01.y * rx * f01, n01.z * rz * f01
            )
            var s11 = center + Vec3d(
                n11.x * rx * f11, n11.y * rx * f11, n11.z * rz * f11
            )
            # Lit from above, and dappled: the lumps catch and lose the light.
            var l00 = _shade(
                (0.3 + 0.55 * (n00.z * 0.5 + 0.5)) * (0.78 + 0.34 * f00 * f00)
            )
            var l10 = _shade(
                (0.3 + 0.55 * (n10.z * 0.5 + 0.5)) * (0.78 + 0.34 * f10 * f10)
            )
            var l01 = _shade(
                (0.3 + 0.55 * (n01.z * 0.5 + 0.5)) * (0.78 + 0.34 * f01 * f01)
            )
            var l11 = _shade(
                (0.3 + 0.55 * (n11.z * 0.5 + 0.5)) * (0.78 + 0.34 * f11 * f11)
            )
            crown.smooth_triangle(s00, s01, s11, n00, n01, n11, l00, l01, l11)
            crown.smooth_triangle(s00, s11, s10, n00, n11, n10, l00, l11, l10)
    var bark = MeshBuilder()
    bark.tube(
        Vec3d(0, 0, -0.3),
        Vec3d(0, 0, height * 0.42),
        0.02 * height + 0.04,
        0.0,
        5,
        Vec3d(1, 1, 1),
        Vec3d(1, 1, 1),
    )
    return TreeShape(bark.geometry(), crown.geometry(), height)
