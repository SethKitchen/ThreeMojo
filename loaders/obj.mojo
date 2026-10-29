# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wavefront OBJ files, from three.js `examples/jsm/loaders/OBJLoader.js`.

The oldest model format still in use, and the plainest: a text file of
vertex positions, texture coordinates and normals, then faces that name
them by number. `parse_obj` turns the text into a model of named objects,
each a `BufferGeometry`, and `read_obj` reads a file first.

What is read is what three.js's loader reads and this renderer can draw:

- `v x y z`, `vt u v` and `vn x y z`, into three pools the faces index.
  A fourth coordinate on any of them is ignored, as three.js ignores it.
  `v x y z r g b` also gives the vertex an sRGB color, as three.js reads
  it: an object with a colored vertex gets a linear `color` attribute,
  and a vertex with no color is white in it.
- `f` with three or more corners, each `v`, `v/vt`, `v//vn` or `v/vt/vn`.
  A polygon is cut into a fan of triangles from its first corner, as
  three.js cuts it, and so it must be convex: a fan covers a convex
  polygon and only that, and a concave one, or one with no area, is
  refused rather than drawn wrong, as three.js draws it. An index counts
  from one, and a negative one counts back from the last entry so far,
  as the format allows.
- `o name` and `g name` start a new object. An object with no faces is
  left out, as three.js leaves it out. A name, here and in `usemtl` and
  `mtllib`, is the rest of the line, trimmed: a `#` and the spaces in it
  are kept, as three.js keeps them.
- `usemtl name` starts a new run of faces under that material, in the
  same object. An object that uses more than one material gets a group
  per run, and run `i` wears material `i` of `ObjObject.materials`, as
  three.js's `startMaterial` and its multi-material mesh do. A run with
  no faces is dropped. The material in force carries into a new object.
- `mtllib name` names a material library, kept in `material_libraries`
  as three.js keeps it in `materialLibraries`. The rest of the line is one
  file name, as three.js reads it. `loaders.mtl` reads the library and
  gives each object its material.
- A line that ends in a backslash goes on into the next, as three.js
  joins it, so a long face can be written over several lines.
- `s`, and anything else, are skipped. Lines and points, `l` and
  `p`, are skipped too: nothing here draws them yet.

The geometries come out non-indexed, as three.js's do: a corner per face
corner, with a `normal` attribute when the faces name normals and a `uv`
attribute when they name texture coordinates. A geometry without normals
shades flat by the renderer's fallback, which is what a file without them
asked for. Within one object every face must say the same about normals
and texture coordinates: a file that names a normal on one face and not
the next is refused rather than padded, because a zero normal would light
a corner black without a word.

A number that cannot be read or is not finite once it is a `Float32`, a
face with fewer than three corners or that is not convex, and an index
that names nothing are refused, with the line they were found on.

`read_obj` reads the file as UTF-8. A byte that is not UTF-8 becomes
U+FFFD, as three.js's `FileLoader` decodes the text, so a comment or a
name in another encoding does not refuse the file.
"""

from std.math import isfinite, isnan
from std.utils.numerics import nan

from core.ordinal import index_in_count

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    MaterialIndex,
)
from loaders.fan import fan_problem
from loaders.js_text import comment_start, split_fields, without_bom
from loaders.text_number import file_line
from math.vector3 import Vector3
from render.srgb import srgb_to_linear
from std.pathlib import Path


struct ObjObject(Movable):
    """One object of an OBJ file: its name, the materials it asks for by
    name, and its geometry."""

    # From `o` or `g`; empty for faces before either.
    var name: String
    # The first of `materials`: the one material of an object that uses
    # one. Empty when no `usemtl` came before its faces.
    var material: String
    # From `usemtl`, one a run of faces, in file order: names in the
    # file's material library, which `loaders.mtl.set_materials` matches
    # to `MaterialId`s. One entry, possibly empty, when the object uses
    # one material. With more, the geometry has a group a run, and group
    # `i` wears entry `i`.
    var materials: List[String]
    var geometry: BufferGeometry

    def __init__(
        out self,
        var name: String,
        var materials: List[String],
        var geometry: BufferGeometry,
    ):
        """Bundle a finished object.

        Args:
            name: Its name, from `o` or `g`.
            materials: The materials it asks for, from `usemtl`, one a
                run of faces; at least one.
            geometry: Its triangles.
        """
        self.name = name^
        self.material = materials[0]
        self.materials = materials^
        self.geometry = geometry^

    def is_multi_material(self) -> Bool:
        """Return True if the object uses more than one material, and so
        has a group a material."""
        return len(self.materials) > 1

    def take_geometry(mut self) -> BufferGeometry:
        """Give up this object's geometry, to go into a `GeometryStore`.

        A `BufferGeometry` moves and does not copy, so it is swapped out
        for an empty one: the object keeps its name and material and is
        left with no triangles.

        Returns:
            The geometry.
        """
        var taken = BufferGeometry()
        swap(self.geometry, taken)
        return taken^


struct ObjModel(Movable):
    """Everything an OBJ file described: its objects, in file order, and
    the material libraries it names."""

    var objects: List[ObjObject]
    # From `mtllib`, in file order, as written: relative to the OBJ file's
    # own directory.
    var material_libraries: List[String]

    def __init__(out self):
        """Start an empty model."""
        self.objects = List[ObjObject]()
        self.material_libraries = List[String]()

    def count(self) -> Int:
        """Return how many objects the model has."""
        return len(self.objects)


@fieldwise_init
struct _Run(Copyable, Movable):
    """A run of an object's corners under one `usemtl`, three.js's
    material entry in `startMaterial`."""

    var name: String
    var start: Int
    # Minus one while the run is still open.
    var end: Int


struct _Part(Movable):
    """An object being read: its corners so far, and what each carries."""

    var name: String
    # The runs of corners under each material so far.
    var runs: List[_Run]
    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var colors: List[Float32]
    # Whether a corner's vertex had a color, which makes the part carry a
    # `color` attribute.
    var with_color: Bool
    # Decided by the first corner: whether every corner names a normal, and
    # a texture coordinate. Meaningless until `corners` is positive.
    var with_normal: Bool
    var with_uv: Bool
    var corners: Int

    def __init__(out self, var name: String, var material: String):
        """Start an object with no faces yet.

        Args:
            name: Its name.
            material: The material in force, carried from the object
                before, or empty for none.
        """
        self.name = name^
        self.runs = List[_Run]()
        if material != "":
            self.runs.append(_Run(material^, 0, -1))
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.colors = List[Float32]()
        self.with_color = False
        self.with_normal = False
        self.with_uv = False
        self.corners = 0

    def material(self) -> String:
        """Return the material in force: the last run's, or empty."""
        if len(self.runs) == 0:
            return String()
        return self.runs[len(self.runs) - 1].name

    def _close(mut self):
        """Close the last run at the corners read so far, three.js's
        `_finalize` of its last material. The last run is always open:
        a run is closed only here, and only before a new one opens or the
        part is finished."""
        if len(self.runs) > 0:
            self.runs[len(self.runs) - 1].end = self.corners

    def use_material(mut self, var name: String):
        """Start a run under a new material, three.js's `startMaterial`.

        The run before it is dropped if it has no corners. The new one
        starts where the run before it ended, dropped or not, as in
        three.js: so a first `usemtl` after some faces takes those faces
        too.

        Args:
            name: The material's name.
        """
        self._close()
        var start = 0
        if len(self.runs) > 0:
            var last = self.runs.pop()
            start = last.end
            if last.end - last.start > 0:
                self.runs.append(last^)
        self.runs.append(_Run(name^, start, -1))

    def finish(mut self) raises -> ObjObject:
        """Return this part as an object, its corners as a non-indexed
        geometry, and leave the part empty.

        The lists are swapped out rather than moved out, because a value
        is taken apart whole or not at all, and a part is replaced right
        after anyway.

        Returns:
            The object.

        Raises:
            Error: If the geometry refuses its attributes, which built
                three or two floats at a time they are not.
        """
        var name = String()
        swap(name, self.name)
        # Runs with no corners are dropped when there is more than one,
        # and an object with none still has one material, empty, as
        # three.js's `_finalize( true )` leaves it.
        self._close()
        var kept = List[_Run]()
        for run in self.runs:
            if len(self.runs) == 1 or run.end - run.start > 0:
                kept.append(run.copy())
        if len(kept) == 0:
            kept.append(_Run(String(), 0, self.corners))
        self.runs.clear()
        var positions = List[Float32]()
        swap(positions, self.positions)
        var normals = List[Float32]()
        swap(normals, self.normals)
        var uvs = List[Float32]()
        swap(uvs, self.uvs)
        var colors = List[Float32]()
        swap(colors, self.colors)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        if self.with_normal:
            geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        if self.with_uv:
            geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
        if self.with_color:
            geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
        self.with_color = False
        var materials = List[String]()
        for index in range(len(kept)):  # pragma: no branch
            materials.append(kept[index].name)
            if len(kept) > 1:
                geometry.add_group(
                    kept[index].start,
                    kept[index].end - kept[index].start,
                    MaterialIndex(index),
                )
        self.corners = 0
        return ObjObject(name^, materials^, geometry^)


def _where(line: Int) -> String:
    """Return the prefix an error names its line with."""
    return file_line("OBJ", line)


def _number(field: String, line: Int) raises -> Float32:
    """Return one coordinate read from a field.

    Read wide, then narrowed to the `Float32` a geometry holds, and
    refused if either step gives something that is not a finite number:
    `1e100` reads as a finite Float64 and narrows to infinity, and an
    infinity in a position would reach every bound, projection and
    normal downstream without a word.

    Args:
        field: The text.
        line: Which line it is on, for the error.

    Returns:
        The number.

    Raises:
        Error: If the field is not a number, or is not finite once it is
            a `Float32`.
    """
    var wide: Float64
    try:
        wide = Float64(field)
    except reason:
        raise Error(
            _where(line)
            + "not a number: "
            + field
            + " ("
            + String(reason)
            + ")"
        )
    var value = Float32(wide)
    if not isfinite(value):
        raise Error(
            _where(line) + "a coordinate must be a finite number: " + field
        )
    return value


def _index(field: String, pool: Int, line: Int) raises -> Int:
    """Return which entry of a pool a face field names, from zero.

    Args:
        field: The text: a count from one, or a negative count back from
            the last entry.
        pool: How many entries the pool has so far.
        line: Which line it is on, for the error.

    Returns:
        The entry's index, from zero.

    Raises:
        Error: If the field is not a whole number, is zero, or names an
            entry the pool does not have.
    """
    var value: Int
    try:
        value = Int(field)
    except reason:
        raise Error(
            _where(line)
            + "not an index: "
            + field
            + " ("
            + String(reason)
            + ")"
        )
    if value < 0:
        value += pool
    else:
        value -= 1
    if not index_in_count(value, pool):
        raise Error(
            _where(line)
            + "a face names an entry the file does not have: "
            + field
        )
    return value


def _rest(line: String, keyword: String) -> String:
    """Return the name an `o`, `g`, `usemtl` or `mtllib` line gives: the
    rest of the line after its keyword, trimmed, as three.js reads it. A
    `#` and the spaces inside the name are kept.

    Args:
        line: The line, with any comment still on it.
        keyword: Its first field.

    Returns:
        The name, or an empty string for a line with nothing after the
        keyword.
    """
    var trimmed = String(line.strip())
    return String(trimmed[byte = keyword.byte_length() :].strip())


def _read_coordinates(
    mut pool: List[Float32], fields: List[String], count: Int, line: Int
) raises:
    """Read `count` coordinates from a `v`, `vt` or `vn` line into a
    pool, ignoring any beyond.

    Args:
        pool: Where they go.
        fields: The line, split on whitespace, the keyword first.
        count: How many coordinates the line must have.
        line: Which line, for the error.

    Raises:
        Error: If the line has fewer than `count` coordinates, or one of
            them is not a number.
    """
    if len(fields) < count + 1:
        raise Error(
            _where(line)
            + fields[0]
            + " needs "
            + String(count)
            + " coordinates"
        )
    # Two or three coordinates: the loop always runs.
    for index in range(1, count + 1):  # pragma: no branch
        pool.append(_number(fields[index], line))


def _read_corner(
    mut part: _Part,
    field: String,
    vertices: List[Float32],
    texcoords: List[Float32],
    normals: List[Float32],
    colors: List[Float32],
    line: Int,
) raises:
    """Add one face corner to the part being read.

    Args:
        part: The object being read.
        field: The corner: `v`, `v/vt`, `v//vn` or `v/vt/vn`.
        vertices: The position pool so far.
        texcoords: The texture coordinate pool so far.
        normals: The normal pool so far.
        colors: The linear color of each vertex so far, NaN for none.
        line: Which line, for the error.

    Raises:
        Error: If the corner has more than three parts, an index cannot be
            read or names nothing, or the corner disagrees with the
            object's earlier corners about normals or texture coordinates.
    """
    var parts = List[String]()
    # A split yields at least one piece, even of nothing: the loop always
    # runs.
    for piece in field.split("/"):  # pragma: no branch
        parts.append(String(piece))
    if len(parts) > 3:
        raise Error(
            _where(line) + "a face corner has at most three parts: " + field
        )
    var has_uv = len(parts) >= 2 and parts[1] != ""
    var has_normal = len(parts) == 3 and parts[2] != ""
    if part.corners == 0:
        part.with_uv = has_uv
        part.with_normal = has_normal
    elif has_uv != part.with_uv or has_normal != part.with_normal:
        raise Error(
            _where(line)
            + "a face names normals or texture coordinates where an earlier"
            " face of the object did not, or the other way round"
        )
    var vertex = _index(parts[0], len(vertices) // 3, line)
    for axis in range(3):  # pragma: no branch
        part.positions.append(vertices[vertex * 3 + axis])
    # A vertex with no color is white beside one with a color.
    var colored = not isnan(colors[vertex * 3])
    part.with_color = part.with_color or colored
    for axis in range(3):  # pragma: no branch
        part.colors.append(colors[vertex * 3 + axis] if colored else 1.0)
    if has_uv:
        var texcoord = _index(parts[1], len(texcoords) // 2, line)
        part.uvs.append(texcoords[texcoord * 2])
        part.uvs.append(texcoords[texcoord * 2 + 1])
    if has_normal:
        var normal = _index(parts[2], len(normals) // 3, line)
        for axis in range(3):  # pragma: no branch
            part.normals.append(normals[normal * 3 + axis])
    part.corners += 1


def _corner_position(
    field: String, vertices: List[Float32], line: Int
) raises -> Vector3:
    """Return the position a face corner names, before the corner is
    read in full.

    Args:
        field: The corner: `v`, `v/vt`, `v//vn` or `v/vt/vn`.
        vertices: The position pool so far.
        line: Which line, for the error.

    Returns:
        The position.

    Raises:
        Error: If the position index cannot be read or names nothing.
    """
    var parts = List[String]()
    # A split yields at least one piece: the loop always runs.
    for piece in field.split("/"):  # pragma: no branch
        parts.append(String(piece))
    var vertex = _index(parts[0], len(vertices) // 3, line)
    return Vector3(
        vertices[vertex * 3], vertices[vertex * 3 + 1], vertices[vertex * 3 + 2]
    )


def _read_face(
    mut part: _Part,
    fields: List[String],
    vertices: List[Float32],
    texcoords: List[Float32],
    normals: List[Float32],
    colors: List[Float32],
    line: Int,
) raises:
    """Add a face's triangles to the part being read, as a fan from its
    first corner.

    Args:
        part: The object being read.
        fields: The line, split on whitespace, the keyword first.
        vertices: The position pool so far.
        texcoords: The texture coordinate pool so far.
        normals: The normal pool so far.
        colors: The vertex color pool so far; see `_read_corner`.
        line: Which line, for the error.

    Raises:
        Error: If the face has fewer than three corners, or a corner is
            refused; see `_read_corner`.
    """
    var corners = len(fields) - 1
    if corners < 3:
        raise Error(_where(line) + "a face needs at least three corners")
    if corners > 3:
        var points = List[Vector3]()
        for which in range(corners):  # pragma: no branch
            points.append(_corner_position(fields[which + 1], vertices, line))
        var problem = fan_problem(points)
        if problem:
            raise Error(_where(line) + problem)
    # Three corners or more: the loop always runs.
    for triangle in range(corners - 2):  # pragma: no branch
        for which in [0, triangle + 1, triangle + 2]:  # pragma: no branch
            _read_corner(
                part,
                fields[which + 1],
                vertices,
                texcoords,
                normals,
                colors,
                line,
            )


def parse_obj(text: String) raises -> ObjModel:
    """Read an OBJ file's text into a model.

    A byte order mark at the start is dropped, as three.js's `trimStart`
    drops it from the first line.

    Args:
        text: The whole file.

    Returns:
        Its objects, in file order, each with a non-indexed geometry.

    Raises:
        Error: If a `v`, `vt` or `vn` line has too few coordinates or one
            that is not a number; a face has fewer than three corners, a
            corner with more than three parts, or an index that is not a
            whole number, is zero, or names nothing; or a face names a
            normal or a texture coordinate where an earlier face of the
            same object did not, or the other way round; or an `mtllib`
            line names no file.
    """
    var model = ObjModel()
    var vertices = List[Float32]()
    var texcoords = List[Float32]()
    var normals = List[Float32]()
    # Three a vertex, linear, or NaN for a vertex that names no color.
    var colors = List[Float32]()
    var part = _Part(String(), String())
    # Whether an `o` or `g` line has been read yet; see below.
    var declared = False
    var line = 0
    var lines = List[String]()
    # A split yields at least one piece, even of an empty file: the loops
    # always run.
    for raw in without_bom(text).split("\n"):  # pragma: no branch
        lines.append(String(raw))
    # A line that ends in a backslash goes on into the next, three.js's
    # `replace( /\\\n/g, '' )`, so a statement is read, and named in an
    # error, on the line it ends on. A backslash on the last line goes on
    # into nothing.
    var pending = String()
    for index in range(len(lines)):  # pragma: no branch
        line += 1
        var physical = lines[index]
        if physical.endswith("\r"):
            var trimmed = String(physical[byte = : physical.byte_length() - 1])
            physical = trimmed^
        if physical.endswith("\\"):
            pending += physical[byte = : physical.byte_length() - 1]
            if index < len(lines) - 1:
                continue
            physical = String()
        var joined = pending + physical
        pending = String()
        var stripped = String(joined.strip())
        # A comment runs from a `#` that starts a word to the end of the
        # line; the format allows one after the data, and three.js reads a
        # trailing one as a corner. A name keeps the whole rest of its
        # line, a `#` too, as three.js's does: see `_rest`.
        var comment = comment_start(stripped)
        if comment >= 0:
            var data = String(stripped[byte=0:comment].strip())
            stripped = data^
        if stripped == "":
            continue
        # The line is not empty here, so it has a first field.
        var fields = split_fields(stripped)
        var keyword = fields[0]
        if keyword == "v":
            _read_coordinates(vertices, fields, 3, line)
            # Six numbers are a position and an sRGB color, as three.js
            # reads `v x y z r g b`.
            for axis in range(4, 7):  # pragma: no branch
                if len(fields) >= 7:
                    colors.append(srgb_to_linear(_number(fields[axis], line)))
                else:
                    colors.append(nan[DType.float32]())
        elif keyword == "vt":
            _read_coordinates(texcoords, fields, 2, line)
        elif keyword == "vn":
            _read_coordinates(normals, fields, 3, line)
        elif keyword == "f":
            _read_face(part, fields, vertices, texcoords, normals, colors, line)
        elif keyword == "o" or keyword == "g":
            if not declared:
                # The first declaration names what was read before it
                # rather than starting afresh, as three.js's `startObject`
                # renames the object it began with: a file that lists
                # faces and then says `o Cube` means those faces are the
                # cube's. No part is finished before it: only an `o` or
                # a `g` finishes one.
                declared = True
                part.name = _rest(joined, keyword)
                continue
            # A new object, under the material in force, as three.js
            # carries it over. One with no faces is dropped.
            var material = part.material()
            if part.corners > 0:
                model.objects.append(part.finish())
            part = _Part(_rest(joined, keyword), material^)
        elif keyword == "mtllib":
            var library = _rest(joined, keyword)
            if library == "":
                raise Error(_where(line) + "mtllib names no file")
            model.material_libraries.append(library^)
        elif keyword == "usemtl":
            # A new material starts a new run of the same object.
            part.use_material(_rest(joined, keyword))
    if part.corners > 0:
        model.objects.append(part.finish())
    return model^


def read_obj(path: String) raises -> ObjModel:
    """Read an OBJ file into a model.

    A byte that is not UTF-8 becomes U+FFFD, as three.js decodes it.

    Args:
        path: The file to read.

    Returns:
        Its objects; see `parse_obj`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_obj`
            refuses.
    """
    return parse_obj(String(from_utf8_lossy=Path(path).read_bytes()))
