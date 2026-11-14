# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The value of a solved field at a point inside a mesh.

A thermocouple or a strain gauge measures at a point, not at a node.
`locate_point` finds the element that holds a point, and the point's
four volume coordinates in it. `sample_field` gives a nodal field there,
one or more numbers per node. `sample_temperature` and
`sample_displacement` take a solved result directly.

The value comes from the shape functions of the element. On a four-node
element they are the volume coordinates. On a ten-node element a corner
has `L_i (2 L_i - 1)` and the node of edge `i-j` has `4 L_i L_j`. So a
field that the element holds exactly, linear or quadratic, is sampled
exactly.

A point counts as inside an element when each volume coordinate is at
least `-1e-9`. A point on a face that two elements share is in both,
and the element with the lower index counts. The field is continuous
across the face, so the value is the same to rounding.
"""

from extensions.fem.ids import ElementId
from extensions.fem.mesh import TetMesh, edge_pairs, signed_volume
from extensions.fem.static import StaticResult
from extensions.fem.thermal import ThermalResult
from extensions.sdf.vector import V3, v3
from units.temperature import KELVIN, Temperature64

# A volume coordinate this far below 0 still counts as inside.
comptime INSIDE = 1.0e-9


@fieldwise_init
struct MeshPoint(Copyable, Movable):
    """An element of a mesh, and a point's volume coordinates in it."""

    var element: ElementId
    """The element that holds the point."""
    var weights: List[Float64]
    """The four volume coordinates. They sum to 1."""


def locate_point(mesh: TetMesh, point: V3) raises -> MeshPoint:
    """Return the element that holds a point, and the point's coordinates.

    Args:
        mesh: The mesh.
        point: The point, in meters.

    Returns:
        The element with the lowest index that holds the point.

    Raises:
        Error: If no element holds the point.
    """
    var count = mesh.nodes_per_element()
    for e in range(mesh.element_count()):
        var at = count * e
        var a = mesh.nodes[mesh.corners[at]]
        var b = mesh.nodes[mesh.corners[at + 1]]
        var c = mesh.nodes[mesh.corners[at + 2]]
        var d = mesh.nodes[mesh.corners[at + 3]]
        var volume = signed_volume(a, b, c, d)
        var weights: List[Float64] = [
            signed_volume(point, b, c, d) / volume,
            signed_volume(a, point, c, d) / volume,
            signed_volume(a, b, point, d) / volume,
            signed_volume(a, b, c, point) / volume,
        ]
        var inside = True
        for w in weights:  # pragma: no branch
            if not (w >= -INSIDE):
                inside = False
        if inside:
            return MeshPoint(ElementId(e), weights^)
    raise Error("No element of the mesh holds the point")


def _shape_values(weights: List[Float64], count: Int) -> List[Float64]:
    """Return the values of the shape functions of an element at a point."""
    if count == 4:
        return weights.copy()
    var out = List[Float64]()
    for i in range(4):  # pragma: no branch
        out.append(weights[i] * (2.0 * weights[i] - 1.0))
    var pairs = edge_pairs()
    for edge in range(6):  # pragma: no branch
        out.append(
            4.0 * weights[pairs[2 * edge]] * weights[pairs[2 * edge + 1]]
        )
    return out^


def sample_field(
    mesh: TetMesh, at: MeshPoint, values: List[Float64], components: Int
) raises -> List[Float64]:
    """Return a nodal field at a located point.

    Args:
        mesh: The mesh.
        at: The point, from `locate_point`.
        values: The field: `components` numbers per node, node by node.
        components: The numbers per node: 1 for a temperature, 3 for a
            displacement. From 1 to 64.

    Returns:
        The `components` numbers of the field at the point.

    Raises:
        Error: If the element names no element of the mesh, the point has
            not four coordinates, `components` is out of range, or
            `values` has not `components` numbers per node.
    """
    mesh.require_element(at.element)
    if len(at.weights) != 4:
        raise Error("A mesh point has four volume coordinates")
    if components < 1 or components > 64:
        raise Error("A field has from 1 to 64 numbers per node")
    if len(values) != components * mesh.node_count():
        raise Error("A field needs its numbers for every node")
    var count = mesh.nodes_per_element()
    var shape = _shape_values(at.weights, count)
    var out = List[Float64](length=components, fill=0)
    for n in range(count):  # pragma: no branch
        var node = mesh.corners[count * at.element.value + n]
        for c in range(components):  # pragma: no branch
            out[c] += shape[n] * values[components * node + c]
    return out^


def sample_temperature(
    mesh: TetMesh, result: ThermalResult, point: V3
) raises -> Temperature64:
    """Return the temperature of a solved problem at a point.

    Args:
        mesh: The mesh of the problem.
        result: The result of `solve_thermal` or of a transient step.
        point: The point, in meters.

    Returns:
        The temperature at the point.

    Raises:
        Error: If no element holds the point, or the result does not fit
            the mesh.
    """
    var at = locate_point(mesh, point)
    var value = sample_field(mesh, at, result.temperatures, 1)
    return Temperature64(value[0], KELVIN)


def sample_displacement(
    mesh: TetMesh, result: StaticResult, point: V3
) raises -> V3:
    """Return the displacement of a solved problem at a point.

    Args:
        mesh: The mesh of the problem.
        result: The result of `solve_static`.
        point: The point, in meters.

    Returns:
        The displacement at the point, in meters.

    Raises:
        Error: If no element holds the point, or the result does not fit
            the mesh.
    """
    var at = locate_point(mesh, point)
    var value = sample_field(mesh, at, result.displacements, 3)
    return v3(value[0], value[1], value[2])
