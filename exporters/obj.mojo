# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene's meshes written as a Wavefront OBJ file: three.js's
`OBJExporter`, and the other half of `loaders.obj`.

Each mesh is one `o` named after its node, then its positions as `v`, its
texture coordinates as `vt` when it has them, its normals as `vn` when it
has them, and its triangles as `f`. Every corner of a face is
`v`, `v/vt`, `v//vn` or `v/vt/vn`, counted from one across the whole
file, as three.js counts them. Positions and normals are in world space,
as three.js writes them; see `exporters.common.world_meshes`.

A name is written as it is, so a name that `read_obj` would read back
differently is refused: one with a `#`, which starts a comment, or with
white space other than single spaces between words, which the reader
folds.

Not written: materials and a material library, as three.js writes none,
and lines and points, which three.js writes as `l` and `p` and
`read_obj` skips.
"""

from core.assets import Assets
from core.scene import Scene
from exporters.common import format_float32, world_meshes
from std.pathlib import Path


def _is_readable_name(name: String) -> Bool:
    """Return True if `read_obj` reads a name back as it is: no `#`, and
    words split by single spaces."""
    var folded = String()
    for word in name.split():
        if folded != "":
            folded += " "
        folded += String(word)
    return name.find("#") < 0 and folded == name


def _write_triples(
    mut out: String, keyword: String, values: List[Float32], width: Int
) raises:
    """Write one line a vertex: the keyword and `width` numbers."""
    for vertex in range(len(values) // width):
        out += keyword
        for lane in range(width):  # pragma: no branch
            out += " "
            out += format_float32(values[vertex * width + lane])
        out += "\n"


def export_obj(scene: Scene, assets: Assets) raises -> String:
    """Return a scene's meshes as the text of an OBJ file.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.

    Returns:
        The text.

    Raises:
        Error: If a node's name would not read back, or anything
            `exporters.common.world_meshes` raises.
    """
    var meshes = world_meshes(scene, assets)
    var out = String()
    var vertex_base = 0
    var uv_base = 0
    var normal_base = 0
    for mesh in meshes:
        if not _is_readable_name(mesh.name):
            raise Error(
                "OBJ: a name with a # or with spaces the reader folds: "
                + mesh.name
            )
        out += "o " + mesh.name + "\n"
        _write_triples(out, "v", mesh.positions, 3)
        if mesh.with_uvs:
            _write_triples(out, "vt", mesh.uvs, 2)
        if mesh.with_normals:
            _write_triples(out, "vn", mesh.normals, 3)
        for triangle in range(len(mesh.triangles) // 3):
            out += "f"
            for corner in range(3):  # pragma: no branch
                var number = mesh.triangles[triangle * 3 + corner] + 1
                out += " " + String(vertex_base + number)
                if mesh.with_uvs or mesh.with_normals:
                    out += "/"
                    if mesh.with_uvs:
                        out += String(uv_base + number)
                    if mesh.with_normals:
                        out += "/" + String(normal_base + number)
            out += "\n"
        var count = mesh.vertex_count()
        vertex_base += count
        if mesh.with_uvs:
            uv_base += count
        if mesh.with_normals:
            normal_base += count
    return out^


def write_obj(path: String, scene: Scene, assets: Assets) raises:
    """Write a scene's meshes to an OBJ file.

    Args:
        path: The file.
        scene: The scene. It must be current.
        assets: Where its geometries are.

    Raises:
        Error: If the file cannot be written, or anything `export_obj`
            raises.
    """
    Path(path).write_text(export_obj(scene, assets))
