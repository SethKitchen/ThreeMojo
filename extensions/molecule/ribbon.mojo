# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cartoon ribbons of protein chains.

A ribbon follows a Catmull-Rom spline through the CA atoms of a chain.
The O atom of each residue gives the direction across the ribbon. That
direction is flipped where it would turn more than a right angle from
the residue before, so the ribbon does not twist.

The cross-section is an ellipse. Its size depends on the residue's
secondary structure:

| Kind | Half width (angstroms) | Half thickness (angstroms) |
|---|---|---|
| `HELIX` | 1.2 | 0.25 |
| `STRAND` | 1.0, and an arrow on the last residue | 0.25 |
| `COIL` | 0.3 | 0.3 |

The arrow of a strand starts 1.7 angstroms wide and ends at a point. A
chain breaks where two CA atoms in a row are more than 4.2 angstroms
apart, or where a residue has no CA. A piece of one residue is not drawn.
The ends of a ribbon are open.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, BufferGeometry
from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    BY_STRUCTURE,
    HELIX,
    ModelId,
    ResidueId,
    RibbonColoring,
    STRAND,
    SecondaryKind,
    require_coloring,
)
from extensions.molecule.structure import Structure
from extensions.sdf.vector import (
    V3,
    catmull_rom,
    cross,
    distance,
    dot,
    length,
    normalize,
    v3,
)
from geometries.surface import indexed_surface
from render.srgb import srgb_to_linear
from std.math import cos, max, min, pi, sin
from units.si import Length64

# The longest CA to CA step that stays in one piece, in angstroms.
comptime MAX_CA_STEP = 4.2


@fieldwise_init
struct _Trace(Copyable, Movable):
    """The CA atoms of one unbroken piece of a chain, with their sides."""

    var points: List[V3]
    var sides: List[V3]
    var kinds: List[SecondaryKind]
    var chain: Int


def _angstrom() -> Float64:
    """Return one angstrom in meters."""
    return Length64(1.0, ANGSTROM).value


def _perpendicular(side: V3, tangent: V3) -> V3:
    """Return `side` without its part along `tangent`, made unit length."""
    var t = normalize(tangent)
    var flat = side - t * dot(side, t)
    if length(flat) == 0:
        flat = cross(t, v3(0, 0, 1))
        if length(flat) == 0:
            flat = cross(t, v3(0, 1, 0))
    return normalize(flat)


def _traces(structure: Structure, model: ModelId) raises -> List[_Trace]:
    """Return the unbroken CA pieces of every chain of a model."""
    structure.require_model(model)
    ref m = structure.models[model.value]
    var out = List[_Trace]()
    var limit = MAX_CA_STEP * _angstrom()
    for c in range(m.first_chain, m.first_chain + m.chain_count):
        ref chain = structure.chains[c]
        var piece = _Trace(List[V3](), List[V3](), List[SecondaryKind](), c)
        var start = chain.first_residue
        for r in range(start, start + chain.residue_count):
            var ca = structure.find_atom(ResidueId(r), "CA")
            var gap = ca.value < 0
            if not gap and len(piece.points) > 0:
                var p = structure.atoms[ca.value].position
                gap = distance(p, piece.points[len(piece.points) - 1]) > limit
            if gap:
                _keep(out, piece^, c)
                piece = _Trace(List[V3](), List[V3](), List[SecondaryKind](), c)
            if ca.value < 0:
                continue
            var p = structure.atoms[ca.value].position
            var o = structure.find_atom(ResidueId(r), "O")
            var side = v3(0, 0, 0)
            if o.value >= 0:
                side = structure.atoms[o.value].position - p
            piece.points.append(p)
            piece.sides.append(side)
            piece.kinds.append(structure.residues[r].secondary)
        _keep(out, piece^, c)
    return out^


def _keep(mut out: List[_Trace], var piece: _Trace, chain: Int):
    """Keep a piece of two or more residues, with its sides made smooth."""
    var count = len(piece.points)
    if count < 2:
        return
    for i in range(count):  # pragma: no branch
        var before = piece.points[_at_least_zero(i - 1)]
        var after = piece.points[min(i + 1, count - 1)]
        var side = piece.sides[i]
        if length(side) == 0 and i > 0:
            side = piece.sides[i - 1]
        side = _perpendicular(side, after - before)
        if i > 0 and dot(side, piece.sides[i - 1]) < 0:
            side = -side
        piece.sides[i] = side
    out.append(piece^)


def _at_least_zero(index: Int) -> Int:
    """Return an index held at zero or above."""
    return max(index, 0)


def _color(kind: SecondaryKind, chain: Int, coloring: RibbonColoring) -> V3:
    """Return the linear color of one sample of a ribbon."""
    var srgb: V3
    if coloring == BY_STRUCTURE:
        if kind == HELIX:
            srgb = v3(0.89, 0.25, 0.38)
        elif kind == STRAND:
            srgb = v3(0.98, 0.78, 0.2)
        else:
            srgb = v3(0.82, 0.84, 0.86)
    else:
        var palette: List[V3] = [
            v3(0.27, 0.53, 0.93),
            v3(0.93, 0.47, 0.2),
            v3(0.3, 0.75, 0.42),
            v3(0.75, 0.35, 0.85),
            v3(0.95, 0.8, 0.2),
            v3(0.2, 0.78, 0.82),
            v3(0.9, 0.3, 0.45),
            v3(0.6, 0.6, 0.62),
        ]
        srgb = palette[chain % 8]
    return v3(
        Float64(srgb_to_linear(Float32(srgb.x))),
        Float64(srgb_to_linear(Float32(srgb.y))),
        Float64(srgb_to_linear(Float32(srgb.z))),
    )


def _size(
    piece: _Trace, i: Int, t: Float64
) -> Tuple[Float64, Float64, SecondaryKind]:
    """Return the half width, half thickness and kind at `t` along span `i`."""
    var last = len(piece.kinds) - 1
    var arrow = piece.kinds[i] == STRAND and (
        piece.kinds[i + 1] != STRAND or i + 1 == last
    )
    if arrow:
        return (max(1.7 * (1.0 - t), 0.05), 0.25, STRAND)
    var kind = piece.kinds[i]
    if t >= 0.5:
        kind = piece.kinds[i + 1]
    if kind == HELIX:
        return (1.2, 0.25, kind)
    if kind == STRAND:
        return (1.0, 0.25, kind)
    return (0.3, 0.3, kind)


def ribbon_geometry(
    structure: Structure,
    model: ModelId,
    coloring: RibbonColoring,
    samples: Int,
    sides: Int,
) raises -> BufferGeometry:
    """Return the cartoon ribbon of every chain of a model.

    Args:
        structure: The structure.
        model: The model to draw.
        coloring: `BY_STRUCTURE` or `BY_CHAIN`.
        samples: Rings for each residue step, from 2 to 16.
        sides: Vertices around each ring, from 4 to 32.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes. The colors are linear.

    Raises:
        Error: If the model id names no model, the coloring is not valid,
            `samples` or `sides` is out of range, or no chain has two
            residues in a row with CA atoms.
    """
    require_coloring(coloring)
    if samples < 2 or samples > 16:
        raise Error("A ribbon needs from 2 to 16 samples a residue")
    if sides < 4 or sides > 32:
        raise Error("A ribbon needs from 4 to 32 sides")
    var traces = _traces(structure, model)
    if len(traces) == 0:
        raise Error("No chain of the model has two residues with CA atoms")
    var scale = _angstrom()
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var colors = List[Float32]()
    var indices = List[Int]()
    for piece in traces:  # pragma: no branch
        var count = len(piece.points)
        var first_ring = len(positions) // 3
        var rings = 0
        for i in range(count - 1):  # pragma: no branch
            var p0 = piece.points[_at_least_zero(i - 1)]
            var p1 = piece.points[i]
            var p2 = piece.points[i + 1]
            var p3 = piece.points[min(i + 2, count - 1)]
            var steps = samples
            if i == count - 2:
                steps = samples + 1
            for k in range(steps):  # pragma: no branch
                var t = Float64(k) / Float64(samples)
                var center = catmull_rom(p0, p1, p2, p3, t)
                var ahead = catmull_rom(p0, p1, p2, p3, min(t + 0.01, 1.0))
                var behind = catmull_rom(p0, p1, p2, p3, max(t - 0.01, 0.0))
                var tangent = normalize(ahead - behind)
                var across = _perpendicular(
                    piece.sides[i] * (1 - t) + piece.sides[i + 1] * t, tangent
                )
                var up = cross(tangent, across)
                var size = _size(piece, i, t)
                var color = _color(size[2], piece.chain, coloring)
                _ring(
                    positions,
                    normals,
                    uvs,
                    colors,
                    center,
                    across,
                    up,
                    size[0] * scale,
                    size[1] * scale,
                    sides,
                    color,
                    Float64(i) + t,
                )
                rings += 1
        for ring in range(rings - 1):  # pragma: no branch
            var a = first_ring + ring * sides
            var b = a + sides
            for s in range(sides):  # pragma: no branch
                var s1 = (s + 1) % sides
                indices.append(a + s)
                indices.append(b + s)
                indices.append(b + s1)
                indices.append(a + s)
                indices.append(b + s1)
                indices.append(a + s1)
    var geometry = BufferGeometry()
    indexed_surface(geometry, positions^, normals^, uvs^, indices^)
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^


def _ring(
    mut positions: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    mut colors: List[Float32],
    center: V3,
    across: V3,
    up: V3,
    width: Float64,
    thickness: Float64,
    sides: Int,
    color: V3,
    along: Float64,
):
    """Append one elliptic ring of vertices."""
    for s in range(sides):  # pragma: no branch
        var angle = 2.0 * pi * Float64(s) / Float64(sides)
        var c = cos(angle)
        var n = sin(angle)
        var p = center + across * (width * c) + up * (thickness * n)
        var normal = normalize(across * (thickness * c) + up * (width * n))
        positions.append(Float32(p.x))
        positions.append(Float32(p.y))
        positions.append(Float32(p.z))
        normals.append(Float32(normal.x))
        normals.append(Float32(normal.y))
        normals.append(Float32(normal.z))
        uvs.append(Float32(Float64(s) / Float64(sides)))
        uvs.append(Float32(along))
        colors.append(Float32(color.x))
        colors.append(Float32(color.y))
        colors.append(Float32(color.z))
