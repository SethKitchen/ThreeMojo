# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene's meshes written as a PLY file: three.js's `PLYExporter`, and
the other half of `loaders.ply`.

Every mesh goes into one `vertex` element and one `face` element, in world
space, as three.js writes them. A vertex has `x`, `y` and `z` as
`float`; `nx`, `ny` and `nz` when any mesh has normals; `s` and `t` when
any has texture coordinates; and `red`, `green` and `blue` as `uchar`
when any has colors. A mesh without one of them writes zeros for its
normal and texture coordinate and white for its color, as three.js does.
A face is `property list uchar int vertex_index`, three corners each.

The format is `loaders.ply`'s own `PlyFormat`: `PLY_ASCII`, the default,
`PLY_BINARY_LITTLE_ENDIAN` or `PLY_BINARY_BIG_ENDIAN`, the three that
three.js's `binary` and `littleEndian` options choose between.

**Colors are rounded.** A color is encoded from linear light to sRGB and
scaled to a byte, as three.js encodes it, clamped to zero through one
first. three.js then rounds down, and this rounds to the nearest byte:
`read_ply` decodes a byte into a linear value that encodes a hair below
the byte, so rounding down lost one level every time a file was read and
written again. Alpha is not written, as three.js writes none.
"""

from core.assets import Assets
from core.scene import Scene
from exporters.common import format_float32, push_f32, push_word, world_meshes
from loaders.ply import (
    PLY_ASCII,
    PLY_BINARY_BIG_ENDIAN,
    PLY_BINARY_LITTLE_ENDIAN,
    PlyFormat,
)
from render.srgb import linear_to_srgb
from std.pathlib import Path


def color_byte(value: Float32) -> Int:
    """Return a linear color channel as the sRGB byte PLY stores.

    Args:
        value: The channel, in linear light.

    Returns:
        The byte, from zero to 255: clamped, encoded and rounded.
    """
    return Int(
        linear_to_srgb(min(max(value, Float32(0)), Float32(1))) * 255 + 0.5
    )


def _format_name(format: PlyFormat) -> String:
    """Return the header's name for a valid format."""
    return "ascii" if format == PLY_ASCII else (
        "binary_little_endian" if format
        == PLY_BINARY_LITTLE_ENDIAN else "binary_big_endian"
    )


struct _Rows:
    """The body being written: text for ASCII, bytes for binary."""

    var text: Bool
    var little: Bool
    var bytes: List[UInt8]
    var line: String

    def __init__(out self, format: PlyFormat):
        self.text = format == PLY_ASCII
        self.little = format == PLY_BINARY_LITTLE_ENDIAN
        self.bytes = List[UInt8]()
        self.line = String()

    def number(mut self, value: Float32) raises:
        """Write a `float`."""
        if self.text:
            self.line += " " + format_float32(value)
        else:
            push_f32(self.bytes, value, self.little)

    def word(mut self, value: Int, size: Int):
        """Write an integer of `size` bytes."""
        if self.text:
            self.line += " " + String(value)
        else:
            push_word(self.bytes, value, size, self.little)

    def end(mut self):
        """End a row: a line of text drops the space it began with."""
        if self.text:
            self.bytes.extend(String(self.line[byte=1:]).as_bytes())
            self.bytes.append(10)
            self.line = String()


def export_ply(
    scene: Scene, assets: Assets, format: PlyFormat = PLY_ASCII
) raises -> List[UInt8]:
    """Return a scene's meshes as the bytes of a PLY file.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.
        format: `PLY_ASCII`, `PLY_BINARY_LITTLE_ENDIAN` or
            `PLY_BINARY_BIG_ENDIAN`.

    Returns:
        The file.

    Raises:
        Error: If the format is none of the three, or anything
            `exporters.common.world_meshes` raises.
    """
    if not format.is_valid():
        raise Error("PLY: a format that is none of the three")
    var meshes = world_meshes(scene, assets)
    var vertices = 0
    var faces = 0
    var normals = False
    var uvs = False
    var colors = False
    for mesh in meshes:
        vertices += mesh.vertex_count()
        faces += len(mesh.triangles) // 3
        normals = normals or mesh.with_normals
        uvs = uvs or mesh.with_uvs
        colors = colors or mesh.color_size > 0
    var header = String("ply\nformat ")
    header += _format_name(format) + " 1.0\n"
    header += "element vertex " + String(vertices) + "\n"
    header += "property float x\nproperty float y\nproperty float z\n"
    if normals:
        header += "property float nx\nproperty float ny\nproperty float nz\n"
    if uvs:
        header += "property float s\nproperty float t\n"
    if colors:
        header += (
            "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        )
    header += "element face " + String(faces) + "\n"
    header += "property list uchar int vertex_index\nend_header\n"
    var rows = _Rows(format)
    rows.bytes.extend(header.as_bytes())
    for mesh in meshes:
        for vertex in range(mesh.vertex_count()):
            for lane in range(3):  # pragma: no branch
                rows.number(mesh.positions[vertex * 3 + lane])
            if normals:
                for lane in range(3):  # pragma: no branch
                    rows.number(
                        mesh.normals[
                            vertex * 3 + lane
                        ] if mesh.with_normals else 0
                    )
            if uvs:
                for lane in range(2):  # pragma: no branch
                    rows.number(
                        mesh.uvs[vertex * 2 + lane] if mesh.with_uvs else 0
                    )
            if colors:
                for lane in range(3):  # pragma: no branch
                    rows.word(
                        color_byte(
                            mesh.colors[vertex * mesh.color_size + lane]
                        ) if mesh.color_size
                        > 0 else 255,
                        1,
                    )
            rows.end()
    var base = 0
    for mesh in meshes:
        for face in range(len(mesh.triangles) // 3):
            rows.word(3, 1)
            for corner in range(3):  # pragma: no branch
                rows.word(base + mesh.triangles[face * 3 + corner], 4)
            rows.end()
        base += mesh.vertex_count()
    var out = List[UInt8]()
    swap(out, rows.bytes)
    return out^


def write_ply(
    path: String, scene: Scene, assets: Assets, format: PlyFormat = PLY_ASCII
) raises:
    """Write a scene's meshes to a PLY file.

    Args:
        path: The file.
        scene: The scene. It must be current.
        assets: Where its geometries are.
        format: `PLY_ASCII`, `PLY_BINARY_LITTLE_ENDIAN` or
            `PLY_BINARY_BIG_ENDIAN`.

    Raises:
        Error: If the file cannot be written, or anything `export_ply`
            raises.
    """
    Path(path).write_bytes(export_ply(scene, assets, format))
