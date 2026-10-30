# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A belt drawn as a taut band round the body.

A belt is a narrow band. Cut from its shell along its cover's iso-line,
as other garments are, it came out ragged: the band is narrower than
the ramp a hem is cut across, so its cover hovers near one half, and
the cut wanders through the skin's large triangles. A `BANDED` garment
is drawn instead as a lined band of leather `BAND_HEIGHT` deep, round
the outline of its own shell, as a belt drawn taut is. Its top and its
bottom edges are level, and it spans the hollow of the back.

The band stands where the garment's cover puts it: its middle is the
mean height of the piece the cover cuts. Each of its rows follows the
convex outline of the shell at that height, with the arms left out.
Each side takes the skin weights of the shell vertex nearest it.

    var band = belt_band(shell, piece, rig, thickness)

This is not a three.js port. See Extensions.
"""

from std.math import cos, pi, sin

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.mesh_ops import MeshWriter
from extensions.attire.skirt import (
    SKIRT_SIDES,
    hull_radii,
    leg_side,
    level_hull,
    skirt_scale,
    slice_segments,
)
from extensions.humanoid.rig.joints import HumanoidRig
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime BAND_HEIGHT = Float32(0.04)
"""How deep a band is, top to bottom, in meters on the template."""
comptime BAND_ROWS = 3
"""How many rows a band's outer face has, top to bottom."""


def _side(side: Int) -> Vector3:
    """Return the unit direction of one side, round from the front, as a
    skirt's sides run."""
    var turn = 2 * Float32(pi) * Float32(side) / Float32(SKIRT_SIDES)
    return Vector3(sin(turn), 0, cos(turn))


def _nearest(points: List[Vector3], kept: List[Bool], p: Vector3) -> Int:
    """Return the kept vertex nearest a point, or -1."""
    var best = -1
    var closest = Float32(1e30)
    for v in range(len(points)):  # pragma: no branch
        if not kept[v]:
            continue
        var d = (points[v] - p).length_sq()
        if d < closest:
            closest = d
            best = v
    return best


def belt_band(
    shell: BufferGeometry,
    piece: BufferGeometry,
    rig: HumanoidRig,
    thickness: Float32,
) raises -> BufferGeometry:
    """Return a garment drawn as a taut band round its shell.

    Args:
        shell: The garment's whole shell, uncut, with skin weights.
        piece: The piece its cover cuts from the shell; the band stands
            at its mean height.
        rig: The rig the garment was made on.
        thickness: How thick the band is, in meters.

    Returns:
        The band, with the shell's attributes and a cover of one. The
        piece as it is when it has no triangles, or when a row of the
        band does not cross the shell.

    Raises:
        Error: If a mesh has no positions or skin weights.
    """
    if piece.triangle_count() == 0:
        return piece.clone()
    ref cut = piece.attribute_view(String(POSITION))
    var middle = Float32(0)
    for v in range(cut.count()):  # pragma: no branch
        middle += cut.vector3(v).y
    middle /= Float32(cut.count())
    var half = BAND_HEIGHT * skirt_scale(rig) / 2
    var legs = leg_side(shell)
    var outlines = List[List[Vector3]]()
    for row in range(BAND_ROWS):  # pragma: no branch
        var y = middle + half - 2 * half * Float32(row) / (BAND_ROWS - 1)
        var hull = level_hull(slice_segments(shell, legs, y))
        if len(hull) < 3:
            return piece.clone()
        outlines.append(hull^)
    # Every row turns about the middle row's center.
    var center = Vector3(0, 0, 0)
    for p in outlines[BAND_ROWS // 2]:  # pragma: no branch
        center = center + p
    center = center / Float32(len(outlines[BAND_ROWS // 2]))
    ref placed = shell.attribute_view(String(POSITION))
    ref bones = shell.attribute_view(String(SKIN_INDEX))
    ref weights = shell.attribute_view(String(SKIN_WEIGHT))
    var points = List[Vector3](capacity=placed.count())
    for v in range(placed.count()):  # pragma: no branch
        points.append(placed.vector3(v))
    var builder = MeshWriter(shell)
    var outer = List[Int]()
    var inner = List[Int]()
    var top_outer = List[Int]()
    var top_inner = List[Int]()
    var low_outer = List[Int]()
    var low_inner = List[Int]()
    for row in range(BAND_ROWS):  # pragma: no branch
        var y = middle + half - 2 * half * Float32(row) / (BAND_ROWS - 1)
        var radii = hull_radii(outlines[row], center)
        for side in range(SKIRT_SIDES):  # pragma: no branch
            var direction = _side(side)
            var p = center + direction * radii[side]
            p.y = y
            var q = p - direction * thickness
            # The side's weights, from the shell where the band lies.
            var source = _nearest(points, legs, p)
            var near = List[Int]()
            var share = List[Float32]()
            for c in range(4):  # pragma: no branch
                near.append(Int(bones.component(source, c)))
                share.append(weights.component(source, c))
            outer.append(builder.add(p, 1, near, share))
            inner.append(builder.add(q, 1, near, share))
            if row == 0:
                top_outer.append(builder.add(p, 1, near, share))
                top_inner.append(builder.add(q, 1, near, share))
            if row == BAND_ROWS - 1:
                low_outer.append(builder.add(p, 1, near, share))
                low_inner.append(builder.add(q, 1, near, share))
    for row in range(BAND_ROWS - 1):  # pragma: no branch
        for side in range(SKIRT_SIDES):  # pragma: no branch
            var next = (side + 1) % SKIRT_SIDES
            var a = row * SKIRT_SIDES + side
            var b = (row + 1) * SKIRT_SIDES + side
            var c = row * SKIRT_SIDES + next
            var d = (row + 1) * SKIRT_SIDES + next
            builder.quad(outer[a], outer[b], outer[c], outer[d])
            # The inner face looks in: its corners turn the other way.
            builder.quad(inner[c], inner[d], inner[a], inner[b])
    for side in range(SKIRT_SIDES):  # pragma: no branch
        var next = (side + 1) % SKIRT_SIDES
        # The top edge looks up, and the bottom edge down.
        builder.quad(
            top_inner[side], top_outer[side], top_inner[next], top_outer[next]
        )
        builder.quad(
            low_outer[side], low_inner[side], low_outer[next], low_inner[next]
        )
    return builder.build()
