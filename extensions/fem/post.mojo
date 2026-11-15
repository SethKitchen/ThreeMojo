# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draw the result of a solve: the deformed outer surface, colored by stress.

`stress_geometry` draws the faces that `boundary_faces` returns. It moves
each node by its displacement times a scale, and colors each face by
the von Mises stress of its element.

The color scale runs through blue, cyan, green, yellow and red, from the
low stress to the high stress. A stress past either end takes the color
of that end.

`temperature_geometry` colors the outer surface by the temperature of
each node, on the same scale.

`dose_geometry` colors it by the thermal dose of each node, on the same
scale but logarithmic, from a low dose to a high one such as 240
minutes.

`mode_geometry` draws a mode shape the same way. It scales the shape so
that the node that moves most moves by a given amplitude, and colors
each vertex by how far its node moves, on the same scale.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, BufferGeometry
from extensions.fem.mesh import TetMesh, boundary_faces
from extensions.fem.static import StaticResult
from extensions.fem.thermal import ThermalResult
from extensions.sdf.vector import V3, cross, dot, normalize, v3
from geometries.surface import indexed_surface
from render.srgb import srgb_to_linear
from std.math import isfinite, log, max, min
from units.si import Duration64, Length64, METER, PASCAL, Pressure64, SECOND
from units.temperature import KELVIN, Temperature64


def stress_color(stress: Pressure64, low: Pressure64, high: Pressure64) -> V3:
    """Return the linear color of a stress on the blue-to-red scale.

    Args:
        stress: The stress.
        low: The stress at blue.
        high: The stress at red. Above `low`.

    Returns:
        The color, linear, each channel from zero to one.
    """
    var t = (stress.to(PASCAL) - low.to(PASCAL)) / (
        high.to(PASCAL) - low.to(PASCAL)
    )
    return _ramp(t)


def _ramp(value: Float64) -> V3:
    """Return the linear color of a place from 0 to 1 on the scale."""
    var t = min(max(value, 0.0), 1.0)
    var stops: List[V3] = [
        v3(0.1, 0.25, 0.9),
        v3(0.1, 0.8, 0.9),
        v3(0.2, 0.8, 0.25),
        v3(0.95, 0.85, 0.15),
        v3(0.9, 0.15, 0.1),
    ]
    var place = t * 4.0
    var index = min(Int(place), 3)
    var f = place - Float64(index)
    var srgb = stops[index] * (1.0 - f) + stops[index + 1] * f
    return v3(
        Float64(srgb_to_linear(Float32(srgb.x))),
        Float64(srgb_to_linear(Float32(srgb.y))),
        Float64(srgb_to_linear(Float32(srgb.z))),
    )


def stress_geometry(
    mesh: TetMesh,
    result: StaticResult,
    scale: Float64,
    low: Pressure64,
    high: Pressure64,
) raises -> BufferGeometry:
    """Return the deformed outer surface, colored by von Mises stress.

    Each face has its own three vertices, so each face has one color and
    one flat normal.

    Args:
        mesh: The mesh that was solved.
        result: Its result.
        scale: How many times the displacements are drawn. Finite.
        low: The stress at blue.
        high: The stress at red. Above `low`.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes.

    Raises:
        Error: If the result is not for this mesh, the scale is not
            finite, or `high` is not above `low`.
    """
    return deformed_geometry(
        mesh, result.displacements, result.von_mises, scale, low, high
    )


def deformed_geometry(
    mesh: TetMesh,
    displacements: List[Float64],
    von_mises: List[Pressure64],
    scale: Float64,
    low: Pressure64,
    high: Pressure64,
) raises -> BufferGeometry:
    """Return an outer surface moved by displacements, colored by stress.

    Use it for the result of any solve, such as `solve_neo_hookean`. Each
    face has its own three vertices, so each face has one color and one
    flat normal.

    Args:
        mesh: The mesh that was solved.
        displacements: Three per node, in meters.
        von_mises: The von Mises stress of each element.
        scale: How many times the displacements are drawn. Finite.
        low: The stress at blue.
        high: The stress at red. Above `low`.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes.

    Raises:
        Error: If the lists are not for this mesh, the scale is not
            finite, or `high` is not above `low`.
    """
    if len(displacements) != 3 * mesh.node_count():
        raise Error("The result is not for this mesh")
    if len(von_mises) != mesh.element_count():
        raise Error("The result is not for this mesh")
    if not isfinite(scale):
        raise Error("A displacement scale must be finite")
    if not (high.to(PASCAL) > low.to(PASCAL)):
        raise Error("A stress scale needs a high end above its low end")
    var faces = boundary_faces(mesh)
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var colors = List[Float32]()
    var indices = List[Int]()
    for face in range(len(faces) // 4):
        var corners = List[V3]()
        for k in range(3):
            var n = faces[4 * face + k]
            var moved = (
                mesh.nodes[n]
                + v3(
                    displacements[3 * n],
                    displacements[3 * n + 1],
                    displacements[3 * n + 2],
                )
                * scale
            )
            corners.append(moved)
        var normal = normalize(
            cross(corners[1] - corners[0], corners[2] - corners[0])
        )
        var color = stress_color(von_mises[faces[4 * face + 3]], low, high)
        for k in range(3):
            indices.append(len(positions) // 3)
            positions.append(Float32(corners[k].x))
            positions.append(Float32(corners[k].y))
            positions.append(Float32(corners[k].z))
            normals.append(Float32(normal.x))
            normals.append(Float32(normal.y))
            normals.append(Float32(normal.z))
            uvs.append(0)
            uvs.append(0)
            colors.append(Float32(color.x))
            colors.append(Float32(color.y))
            colors.append(Float32(color.z))
    var geometry = BufferGeometry()
    indexed_surface(geometry, positions^, normals^, uvs^, indices^)
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^


def mode_geometry(
    mesh: TetMesh, shape: List[Float64], amplitude: Length64
) raises -> BufferGeometry:
    """Return the outer surface moved by a mode shape, colored by motion.

    A mode shape has no size of its own. The shape is scaled so that the
    node that moves most moves by `amplitude`. Each vertex takes the color
    of how far its node moves, from blue at rest to red at `amplitude`.

    Args:
        mesh: The mesh.
        shape: Three numbers per node, such as a shape of `natural_modes`.
        amplitude: The largest motion to draw. Positive and finite.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes.

    Raises:
        Error: If the shape is not for this mesh, the amplitude is not
            positive and finite, or no node moves.
    """
    if len(shape) != 3 * mesh.node_count():
        raise Error("The mode shape is not for this mesh")
    var reach = amplitude.to(METER)
    if not (reach > 0) or not isfinite(reach):
        raise Error("A mode amplitude must be positive and finite")
    var largest = 0.0
    for n in range(mesh.node_count()):
        var d = v3(shape[3 * n], shape[3 * n + 1], shape[3 * n + 2])
        largest = max(largest, dot(d, d))
    if not (largest > 0):
        raise Error("A mode shape needs a node that moves")
    var scale = reach / largest**0.5
    var moved = List[V3]()
    var places = List[Float64]()
    for n in range(mesh.node_count()):  # pragma: no branch
        var d = v3(shape[3 * n], shape[3 * n + 1], shape[3 * n + 2])
        moved.append(mesh.nodes[n] + d * scale)
        places.append(dot(d, d) ** 0.5 * scale / reach)
    return _colored_surface(mesh, moved, places)


def _colored_surface(
    mesh: TetMesh, points: List[V3], places: List[Float64]
) raises -> BufferGeometry:
    """Return the outer faces at the given node points, each vertex
    colored by its node's place from 0 to 1 on the scale."""
    var faces = boundary_faces(mesh)
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var colors = List[Float32]()
    var indices = List[Int]()
    for face in range(len(faces) // 4):  # pragma: no branch
        var corners = List[V3]()
        for k in range(3):  # pragma: no branch
            corners.append(points[faces[4 * face + k]])
        var normal = normalize(
            cross(corners[1] - corners[0], corners[2] - corners[0])
        )
        for k in range(3):  # pragma: no branch
            var color = _ramp(places[faces[4 * face + k]])
            indices.append(len(positions) // 3)
            positions.append(Float32(corners[k].x))
            positions.append(Float32(corners[k].y))
            positions.append(Float32(corners[k].z))
            normals.append(Float32(normal.x))
            normals.append(Float32(normal.y))
            normals.append(Float32(normal.z))
            uvs.append(0)
            uvs.append(0)
            colors.append(Float32(color.x))
            colors.append(Float32(color.y))
            colors.append(Float32(color.z))
    var geometry = BufferGeometry()
    indexed_surface(geometry, positions^, normals^, uvs^, indices^)
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^


def temperature_geometry(
    mesh: TetMesh,
    result: ThermalResult,
    low: Temperature64,
    high: Temperature64,
) raises -> BufferGeometry:
    """Return the outer surface, each vertex colored by its temperature.

    The scale runs from blue at `low` to red at `high`. A temperature past
    either end takes the color of that end.

    Args:
        mesh: The mesh that was solved.
        result: Its temperatures.
        low: The temperature at blue.
        high: The temperature at red. Above `low`.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes.

    Raises:
        Error: If the result is not for this mesh, or `high` is not above
            `low`.
    """
    if len(result.temperatures) != mesh.node_count():
        raise Error("The result is not for this mesh")
    var cold = low.to(KELVIN)
    var hot = high.to(KELVIN)
    if not (hot > cold):
        raise Error("A temperature scale needs a high end above its low end")
    var places = List[Float64]()
    for value in result.temperatures:
        places.append((value - cold) / (hot - cold))
    return _colored_surface(mesh, mesh.nodes.copy(), places)


def dose_geometry(
    mesh: TetMesh,
    doses: List[Duration64],
    low: Duration64,
    high: Duration64,
) raises -> BufferGeometry:
    """Return the outer surface, each vertex colored by its thermal dose.

    The scale is logarithmic, because doses span many powers of ten. It
    runs from blue at `low` to red at `high`. A dose at or below `low` is
    blue, and a dose past `high` red.

    Args:
        mesh: The mesh that was solved.
        doses: The dose of each node, from `thermal_dose`.
        low: The dose at blue. Positive.
        high: The dose at red, such as 240 minutes. Above `low` and finite.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes.

    Raises:
        Error: If the doses are not for this mesh, or the scale is not
            positive, rising and finite.
    """
    if len(doses) != mesh.node_count():
        raise Error("The doses are not for this mesh")
    var least = low.to(SECOND)
    var most = high.to(SECOND)
    if not (least > 0) or not (most > least) or not isfinite(most):
        raise Error(
            "A dose scale needs a positive low end below a finite high end"
        )
    var span = log(most / least)
    var places = List[Float64]()
    for dose in doses:
        var value = dose.to(SECOND)
        if value > least:
            places.append(log(value / least) / span)
        else:
            places.append(0.0)
    return _colored_surface(mesh, mesh.nodes.copy(), places)
