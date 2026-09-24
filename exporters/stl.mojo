# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene's meshes written as an STL file: three.js's `STLExporter`, and
the other half of `loaders.stl`.

Every triangle of every mesh becomes one facet, in world space, with the
normal of its face: `(C - B) x (A - B)`, made unit length, as three.js
works it out. A vertex normal the geometry holds is not written, since
STL has no place for one.

`STL_ASCII`, the default as three.js's `binary: false` is, writes
`solid exported`, a `facet normal` with an `outer loop` of three `vertex`
lines for each face, and `endsolid exported`. `STL_BINARY` writes an
80-byte header of zeros, the face count, and fifty bytes a face: the
normal and the three corners as little-endian `Float32`s, and an
attribute of zero. No color is written, as three.js writes none.

Every mesh is written: a `Mesh`, an `InstancedMesh` as its one geometry
at its node, and a `SkinnedMesh` where its bones hold it now, as
three.js's `applyBoneTransform` carries it. See `exporters.common`.
"""

from core.assets import Assets
from core.scene import Scene
from exporters.common import (
    WorldOptions,
    format_js_float32,
    push_f32,
    push_word,
    world_meshes,
)
from math.vector3 import Vector3
from std.pathlib import Path


@fieldwise_init
struct StlFormat(Equatable, ImplicitlyCopyable, Writable):
    """How an STL file is encoded, as a type rather than a bare int.

    `export_stl` refuses `StlFormat(7)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two encodings there are."""
        return self == STL_ASCII or self == STL_BINARY


# Text, three.js's default.
comptime STL_ASCII = StlFormat(0)
# Fifty packed bytes a face after an 84-byte preamble.
comptime STL_BINARY = StlFormat(1)

# The binary header's length, left as zeros.
comptime _HEADER = 80


def _corner(positions: List[Float32], vertex: Int) -> Vector3:
    """Return one vertex of a flat list of positions."""
    return Vector3(
        positions[vertex * 3],
        positions[vertex * 3 + 1],
        positions[vertex * 3 + 2],
    )


def _write_point(mut out: String, prefix: String, point: Vector3) raises:
    """Write one line of three numbers after a prefix."""
    out += prefix
    out += format_js_float32(point.x) + " "
    out += format_js_float32(point.y) + " "
    out += format_js_float32(point.z) + "\n"


def export_stl(
    scene: Scene, assets: Assets, format: StlFormat = STL_ASCII
) raises -> List[UInt8]:
    """Return a scene's meshes as the bytes of an STL file.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.
        format: `STL_ASCII` or `STL_BINARY`.

    Returns:
        The file.

    Raises:
        Error: If the format is neither, or anything
            `exporters.common.world_meshes` raises.
    """
    if not format.is_valid():
        raise Error("STL: a format that is neither ASCII nor binary")
    var meshes = world_meshes(scene, assets, WorldOptions(posed=True))
    var faces = 0
    for mesh in meshes:
        faces += len(mesh.triangles) // 3
    var binary = format == STL_BINARY
    var out = List[UInt8]()
    var text = String("solid exported\n")
    if binary:
        for _ in range(_HEADER):  # pragma: no branch
            out.append(0)
        push_word(out, faces, 4, True)
    for mesh in meshes:
        for face in range(len(mesh.triangles) // 3):
            var a = _corner(mesh.positions, mesh.triangles[face * 3])
            var b = _corner(mesh.positions, mesh.triangles[face * 3 + 1])
            var c = _corner(mesh.positions, mesh.triangles[face * 3 + 2])
            var normal = c - b
            normal.cross(a - b)
            normal.normalize()
            if binary:
                # The normal, then the three corners: four points.
                for point in [normal, a, b, c]:  # pragma: no branch
                    push_f32(out, point.x, True)
                    push_f32(out, point.y, True)
                    push_f32(out, point.z, True)
                push_word(out, 0, 2, True)
            else:
                _write_point(text, "\tfacet normal ", normal)
                text += "\t\touter loop\n"
                _write_point(text, "\t\t\tvertex ", a)
                _write_point(text, "\t\t\tvertex ", b)
                _write_point(text, "\t\t\tvertex ", c)
                text += "\t\tendloop\n"
                text += "\tendfacet\n"
    if not binary:
        text += "endsolid exported\n"
        out.extend(text.as_bytes())
    return out^


def write_stl(
    path: String, scene: Scene, assets: Assets, format: StlFormat = STL_ASCII
) raises:
    """Write a scene's meshes to an STL file.

    Args:
        path: The file.
        scene: The scene. It must be current.
        assets: Where its geometries are.
        format: `STL_ASCII` or `STL_BINARY`.

    Raises:
        Error: If the file cannot be written, or anything `export_stl`
            raises.
    """
    Path(path).write_bytes(export_stl(scene, assets, format))
