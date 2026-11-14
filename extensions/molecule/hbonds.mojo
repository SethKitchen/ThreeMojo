# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draw the backbone hydrogen bonds of a structure as dashed sticks.

`hydrogen_bonds` in `dssp.mojo` finds the bonds. `bond_geometry` draws
each one from the N of its donor to the O of its acceptor: a thin tube
cut into dashes, as molecular viewers draw a hydrogen bond. Drawn over a
ribbon, the bonds of a helix run along its axis, and the bonds of a
sheet cross between its strands.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, BufferGeometry
from extensions.molecule.dssp import HydrogenBond
from extensions.molecule.structure import Structure
from extensions.sdf.vector import V3, cross, dot, length, normalize, v3
from geometries.surface import indexed_surface
from render.srgb import srgb_to_linear
from std.math import cos, isfinite, pi, sin
from units.si import Length64, METER

# The dashes of a bond, of which every other one is drawn.
comptime DASHES = 7


def _across(axis: V3) -> V3:
    """Return a unit direction square to a unit axis."""
    var other = v3(1, 0, 0)
    if abs(axis.x) > 0.9:
        other = v3(0, 1, 0)
    return normalize(cross(axis, other))


def bond_geometry(
    structure: Structure,
    bonds: List[HydrogenBond],
    radius: Length64,
    sides: Int,
) raises -> BufferGeometry:
    """Return a dashed tube from the donor N to the acceptor O of each bond.

    Each tube is cut into seven dashes, and the first, third, fifth and
    seventh are drawn. The tubes are a light orange.

    Args:
        structure: The structure of the bonds.
        bonds: The bonds, such as `hydrogen_bonds` gives.
        radius: The radius of a tube. Positive and finite.
        sides: The vertices around a tube, from 3 to 64.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes. It is empty when there is no bond.

    Raises:
        Error: If the radius or the sides are out of range, or a residue
            of a bond has no N or no O.
    """
    var r = radius.to(METER)
    if not (r > 0) or not isfinite(r):
        raise Error("A bond radius must be positive and finite")
    if sides < 3 or sides > 64:
        raise Error("A bond tube has from 3 to 64 sides")
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var colors = List[Float32]()
    var indices = List[Int]()
    var tint = v3(
        Float64(srgb_to_linear(Float32(1.0))),
        Float64(srgb_to_linear(Float32(0.72))),
        Float64(srgb_to_linear(Float32(0.35))),
    )
    for bond in bonds:
        var n = structure.find_atom(bond.donor, "N")
        var o = structure.find_atom(bond.acceptor, "O")
        if n.value < 0 or o.value < 0:
            raise Error(
                "A hydrogen bond needs the N of its donor and the O of its"
                " acceptor"
            )
        var start = structure.atoms[n.value].position
        var end = structure.atoms[o.value].position
        var axis = normalize(end - start)
        var e1 = _across(axis)
        var e2 = cross(axis, e1)
        for dash in range(0, DASHES, 2):  # pragma: no branch
            var first = len(positions) // 3
            for ring in range(2):  # pragma: no branch
                var t = Float64(dash + ring) / Float64(DASHES)
                var center = start + (end - start) * t
                for k in range(sides):  # pragma: no branch
                    var angle = 2.0 * pi * Float64(k) / Float64(sides)
                    var outward = e1 * cos(angle) + e2 * sin(angle)
                    var p = center + outward * r
                    positions.append(Float32(p.x))
                    positions.append(Float32(p.y))
                    positions.append(Float32(p.z))
                    normals.append(Float32(outward.x))
                    normals.append(Float32(outward.y))
                    normals.append(Float32(outward.z))
                    uvs.append(0)
                    uvs.append(0)
                    colors.append(Float32(tint.x))
                    colors.append(Float32(tint.y))
                    colors.append(Float32(tint.z))
            for k in range(sides):  # pragma: no branch
                var a = first + k
                var b = first + (k + 1) % sides
                var c = a + sides
                var d = b + sides
                indices.extend([a, b, d, a, d, c])
    var geometry = BufferGeometry()
    indexed_surface(geometry, positions^, normals^, uvs^, indices^)
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^
