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

A mesh that wears a material list writes each group it draws as a run
of faces after a `usemtl` line, in the order of the groups, so
`read_obj` reads the groups back. The material is named `material` and
its id in the store, since a material here has no name. three.js's
exporter writes a `usemtl` only for one named material, and no groups.

**Lines and points.** A `Line` is an `o`, its positions as `v`, and
its points joined as three.js's `OBJExporter` joins them: a `STRIP` is
one `l` through every vertex, `SEGMENTS` is one `l` a pair, and a `LOOP`
writes no `l`, since three.js's `type` of it is `LineLoop`. A `Points`
is an `o`, its positions as `v`, and one `p` of every vertex. A point's
`v` carries its color after the position when the geometry has colors,
encoded from linear light to sRGB as three.js writes it. The index of a
line or points is not read, as three.js reads none. `read_obj` skips
`l` and `p`. A color goes through the C library's `pow`, which can differ
from V8's `Math.pow` in the last digit.

Every mesh is written, in three.js's `traverse` order: a skinned mesh at
rest and an instanced mesh as its one geometry. See `exporters.common`.

Not written: the materials themselves and a material library, as
three.js writes none.
"""

from core.assets import Assets
from core.scene import Scene
from core.buffer_geometry import GeometryGroup
from exporters.common import (
    WORLD_LINE,
    WORLD_POINTS,
    WorldMesh,
    WorldOptions,
    format_js_float32,
    world_meshes,
)
from loaders.js_number import js_number_text, js_pow
from objects.line import SEGMENTS, STRIP
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
            out += format_js_float32(values[vertex * width + lane])
        out += "\n"


def _triangle_run(mesh: WorldMesh, group: GeometryGroup) -> Tuple[Int, Int]:
    """Return where a group begins in a mesh's triangles and how many
    whole triangles it holds, as `BufferGeometry.triangle_run` reads it.
    """
    var total = len(mesh.triangles)
    var first = min(group.start, total)
    var end = min(group.start + group.count, total)
    return (first, max(0, end - first) // 3)


def _write_face(
    mut out: String,
    mesh: WorldMesh,
    slot: Int,
    vertex_base: Int,
    uv_base: Int,
    normal_base: Int,
):
    """Write one `f` line: the triangle whose first corner is `slot`."""
    out += "f"
    for corner in range(3):  # pragma: no branch
        var number = mesh.triangles[slot + corner] + 1
        out += " " + String(vertex_base + number)
        if mesh.with_uvs or mesh.with_normals:
            out += "/"
            if mesh.with_uvs:
                out += String(uv_base + number)
            if mesh.with_normals:
                out += "/" + String(normal_base + number)
    out += "\n"


def srgb_channel(value: Float32) -> Float64:
    """Return a linear channel encoded to sRGB, as three.js's
    `LinearToSRGB` works it out in doubles.

    Args:
        value: The linear channel.

    Returns:
        The sRGB channel. It is not clamped, as three.js's is not.
    """
    var wide = Float64(value)
    if wide < 0.0031308:
        return wide * 12.92
    return 1.055 * js_pow(wide, 0.41666) - 0.055


def _write_vertex_list(
    mut out: String, keyword: String, first: Int, count: Int
):
    """Write one `l` or `p` line through `count` vertices from `first`,
    each followed by a space, as three.js writes it."""
    out += keyword + " "
    for vertex in range(count):
        out += String(first + vertex + 1) + " "
    out += "\n"


def _write_line(mut out: String, mesh: WorldMesh, vertex_base: Int) raises:
    """Write a line's positions and its `l` lines."""
    _write_triples(out, "v", mesh.positions, 3)
    var count = mesh.vertex_count()
    if mesh.line_mode == STRIP:
        _write_vertex_list(out, "l", vertex_base, count)
    elif mesh.line_mode == SEGMENTS:
        for pair in range(count // 2):
            var first = vertex_base + pair * 2 + 1
            out += "l " + String(first) + " " + String(first + 1) + "\n"


def _write_points(mut out: String, mesh: WorldMesh, vertex_base: Int) raises:
    """Write points' positions, with their colors, and their `p` line."""
    for vertex in range(mesh.vertex_count()):
        out += "v"
        for lane in range(3):  # pragma: no branch
            out += " " + format_js_float32(mesh.positions[vertex * 3 + lane])
        if mesh.color_size > 0:
            for lane in range(3):  # pragma: no branch
                out += " " + js_number_text(
                    srgb_channel(mesh.colors[vertex * mesh.color_size + lane])
                )
        out += "\n"
    _write_vertex_list(out, "p", vertex_base, mesh.vertex_count())


def export_obj(scene: Scene, assets: Assets) raises -> String:
    """Return a scene's meshes, lines and points as the text of an OBJ
    file.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.

    Returns:
        The text.

    Raises:
        Error: If a node's name would not read back, or anything
            `exporters.common.world_meshes` raises.
    """
    var meshes = world_meshes(
        scene, assets, WorldOptions(lines=True, points=True)
    )
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
        if mesh.kind == WORLD_LINE:
            _write_line(out, mesh, vertex_base)
            vertex_base += mesh.vertex_count()
            continue
        if mesh.kind == WORLD_POINTS:
            _write_points(out, mesh, vertex_base)
            vertex_base += mesh.vertex_count()
            continue
        _write_triples(out, "v", mesh.positions, 3)
        if mesh.with_uvs:
            _write_triples(out, "vt", mesh.uvs, 2)
        if mesh.with_normals:
            _write_triples(out, "vn", mesh.normals, 3)
        if mesh.multi_material:
            for run in range(len(mesh.runs)):
                out += (
                    "usemtl material"
                    + String(mesh.run_materials[run].value)
                    + "\n"
                )
                var span = _triangle_run(mesh, mesh.runs[run])
                for step in range(span[1]):
                    _write_face(
                        out,
                        mesh,
                        span[0] + step * 3,
                        vertex_base,
                        uv_base,
                        normal_base,
                    )
        else:
            for triangle in range(len(mesh.triangles) // 3):
                _write_face(
                    out, mesh, triangle * 3, vertex_base, uv_base, normal_base
                )
        var count = mesh.vertex_count()
        vertex_base += count
        if mesh.with_uvs:
            uv_base += count
        if mesh.with_normals:
            normal_base += count
    return out^


def write_obj(path: String, scene: Scene, assets: Assets) raises:
    """Write a scene's meshes, lines and points to an OBJ file.

    Args:
        path: The file.
        scene: The scene. It must be current.
        assets: Where its geometries are.

    Raises:
        Error: If the file cannot be written, or anything `export_obj`
            raises.
    """
    Path(path).write_text(export_obj(scene, assets))
