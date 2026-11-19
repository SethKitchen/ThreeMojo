# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shape quality of the tetrahedra of a mesh.

A flat or needle-like tetrahedron makes the stiffness matrix ill
conditioned and the stress near it wrong. Two measures show such
elements:

- The radius ratio `3 r / R`, where `r` is the radius of the inscribed
  sphere and `R` that of the circumscribed sphere. It is 1 for the
  regular tetrahedron and falls toward 0 as an element flattens.
- The dihedral angles between the faces of each edge. The regular
  tetrahedron has `arccos(1/3)`, about 70.5 degrees, at every edge. A
  sliver has an angle near 0 or near 180 degrees.

The six tetrahedra of a cube in `box_mesh` have a radius ratio of
`sqrt(3) / (1 + sqrt(2))`, about 0.717, and dihedral angles from 45 to
90 degrees. A ten-node element is measured by its corners, as its edges
are straight.
"""

from extensions.fem.elasticity import shape_gradients
from extensions.fem.ids import ElementId
from extensions.fem.mesh import TetMesh, signed_volume
from extensions.sdf.vector import V3, cross, distance, dot, length
from std.math import acos, max, min, pi, sqrt
from units.si import Angle64, RADIAN


@fieldwise_init
struct ElementQuality(Copyable, Movable):
    """The shape measures of one tetrahedron."""

    var radius_ratio: Float64
    """`3 r / R`: 1 for the regular tetrahedron, toward 0 when flat."""
    var smallest_angle: Angle64
    """The smallest of the six dihedral angles."""
    var largest_angle: Angle64
    """The largest of the six dihedral angles."""


def _area(a: V3, b: V3, c: V3) -> Float64:
    """Return the area of a triangle."""
    return 0.5 * length(cross(b - a, c - a))


def element_quality(mesh: TetMesh, element: ElementId) raises -> ElementQuality:
    """Return the radius ratio and the dihedral angles of one element.

    Args:
        mesh: The mesh.
        element: The element.

    Returns:
        The measures of the element's corners.

    Raises:
        Error: If the element id names no element.
    """
    mesh.require_element(element)
    var at = mesh.nodes_per_element() * element.value
    var p = List[V3]()
    for k in range(4):  # pragma: no branch
        p.append(mesh.nodes[mesh.corners[at + k]])
    var volume = abs(signed_volume(p[0], p[1], p[2], p[3]))
    var faces = (
        _area(p[1], p[2], p[3])
        + _area(p[0], p[2], p[3])
        + _area(p[0], p[1], p[3])
        + _area(p[0], p[1], p[2])
    )
    var inner = 3.0 * volume / faces
    # The products of the lengths of opposite edges.
    var a = distance(p[0], p[1]) * distance(p[2], p[3])
    var b = distance(p[0], p[2]) * distance(p[1], p[3])
    var c = distance(p[0], p[3]) * distance(p[1], p[2])
    var outer = sqrt(
        max((a + b + c) * (a + b - c) * (a - b + c) * (-a + b + c), 0.0)
    ) / (24.0 * volume)
    # The gradient of each shape function is normal to the opposite face.
    var g = shape_gradients(p[0], p[1], p[2], p[3])
    var smallest = pi
    var largest = 0.0
    for k in range(4):  # pragma: no branch
        for l in range(k + 1, 4):
            var cosine = -dot(g[k], g[l]) / (length(g[k]) * length(g[l]))
            var angle = acos(min(1.0, max(-1.0, cosine)))
            smallest = min(smallest, angle)
            largest = max(largest, angle)
    return ElementQuality(
        3.0 * inner / outer,
        Angle64(smallest, RADIAN),
        Angle64(largest, RADIAN),
    )


struct MeshQuality(Copyable, Movable):
    """The worst shape measures of a mesh, and where they are."""

    var worst_ratio: Float64
    """The least radius ratio of any element."""
    var worst_element: ElementId
    """The element with the least radius ratio."""
    var smallest_angle: Angle64
    """The smallest dihedral angle of any element."""
    var largest_angle: Angle64
    """The largest dihedral angle of any element."""
    var mean_ratio: Float64
    """The mean radius ratio of the elements."""

    def __init__(out self):
        """Create the measures of an empty mesh."""
        self.worst_ratio = 1.0
        self.worst_element = ElementId(-1)
        self.smallest_angle = Angle64(pi, RADIAN)
        self.largest_angle = Angle64(0.0, RADIAN)
        self.mean_ratio = 0.0


def mesh_quality(mesh: TetMesh) raises -> MeshQuality:
    """Return the worst shape measures of a mesh.

    Args:
        mesh: The mesh, with at least one element.

    Returns:
        The least radius ratio and its element, the smallest and the
        largest dihedral angles, and the mean radius ratio.

    Raises:
        Error: If the mesh has no element.
    """
    var count = mesh.element_count()
    if count == 0:
        raise Error("A mesh without elements has no quality")
    var out = MeshQuality()
    var sum = 0.0
    for e in range(count):  # pragma: no branch
        var q = element_quality(mesh, ElementId(e))
        sum += q.radius_ratio
        if out.worst_element.value < 0 or q.radius_ratio < out.worst_ratio:
            out.worst_ratio = q.radius_ratio
            out.worst_element = ElementId(e)
        if q.smallest_angle.to(RADIAN) < out.smallest_angle.to(RADIAN):
            out.smallest_angle = q.smallest_angle
        if q.largest_angle.to(RADIAN) > out.largest_angle.to(RADIAN):
            out.largest_angle = q.largest_angle
    out.mean_ratio = sum / Float64(count)
    return out^
