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

`mode_geometry` draws a mode shape the same way. It scales the shape so
that the node that moves most moves by a given amplitude, and colors
each vertex by how far its node moves, on the same scale.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, BufferGeometry
from extensions.fem.mesh import TetMesh, boundary_faces
from extensions.fem.static import StaticResult
from extensions.sdf.vector import V3, cross, dot, normalize, v3
from geometries.surface import indexed_surface
from render.srgb import srgb_to_linear
from std.math import isfinite, max, min
from units.si import Length64, METER, PASCAL, Pressure64


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
    if len(result.displacements) != 3 * mesh.node_count():
        raise Error("The result is not for this mesh")
    if len(result.von_mises) != mesh.element_count():
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
                    result.displacements[3 * n],
                    result.displacements[3 * n + 1],
                    result.displacements[3 * n + 2],
                )
                * scale
            )
            corners.append(moved)
        var normal = normalize(
            cross(corners[1] - corners[0], corners[2] - corners[0])
        )
        var color = stress_color(
            result.von_mises[faces[4 * face + 3]], low, high
        )
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
    var faces = boundary_faces(mesh)
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var colors = List[Float32]()
    var indices = List[Int]()
    for face in range(len(faces) // 4):  # pragma: no branch
        var corners = List[V3]()
        var motions = List[Float64]()
        for k in range(3):  # pragma: no branch
            var n = faces[4 * face + k]
            var d = v3(shape[3 * n], shape[3 * n + 1], shape[3 * n + 2])
            corners.append(mesh.nodes[n] + d * scale)
            motions.append(dot(d, d) ** 0.5 * scale / reach)
        var normal = normalize(
            cross(corners[1] - corners[0], corners[2] - corners[0])
        )
        for k in range(3):  # pragma: no branch
            var color = _ramp(motions[k])
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
