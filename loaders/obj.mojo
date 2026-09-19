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
- `f` with three or more corners, each `v`, `v/vt`, `v//vn` or `v/vt/vn`.
  A polygon is cut into a fan of triangles from its first corner, as
  three.js cuts it, and so it must be convex: a fan covers a convex
  polygon and only that, and a concave one, or one with no area, is
  refused rather than drawn wrong, as three.js draws it. An index counts
  from one, and a negative one counts back from the last entry so far,
  as the format allows.
- `o name` and `g name` start a new object; `usemtl name` starts a new
  object under that material, keeping the name, since one geometry has one
  material here where three.js's has groups. An object with no faces is
  left out, as three.js leaves it out.
- `mtllib`, `s`, and anything else are skipped. Lines and points, `l` and
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
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from math.vector3 import Vector3
from std.math import isfinite
from std.pathlib import Path


struct ObjObject(Movable):
    """One object of an OBJ file: its name, the material it asks for by
    name, and its geometry."""

    # From `o` or `g`; empty for faces before either.
    var name: String
    # From `usemtl`; empty for faces before one. A name in the file's
    # material library, which is not read: match it to a `Material` by
    # hand.
    var material: String
    var geometry: BufferGeometry

    def __init__(
        out self,
        var name: String,
        var material: String,
        var geometry: BufferGeometry,
    ):
        """Bundle a finished object.

        Args:
            name: Its name, from `o` or `g`.
            material: The material it asks for, from `usemtl`.
            geometry: Its triangles.
        """
        self.name = name^
        self.material = material^
        self.geometry = geometry^

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
    """Everything an OBJ file described: its objects, in file order."""

    var objects: List[ObjObject]

    def __init__(out self):
        """Start an empty model."""
        self.objects = List[ObjObject]()

    def count(self) -> Int:
        """Return how many objects the model has."""
        return len(self.objects)


struct _Part(Movable):
    """An object being read: its corners so far, and what each carries."""

    var name: String
    var material: String
    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    # Decided by the first corner: whether every corner names a normal, and
    # a texture coordinate. Meaningless until `corners` is positive.
    var with_normal: Bool
    var with_uv: Bool
    var corners: Int

    def __init__(out self, var name: String, var material: String):
        """Start an object with no faces yet.

        Args:
            name: Its name.
            material: The material it asks for so far.
        """
        self.name = name^
        self.material = material^
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.with_normal = False
        self.with_uv = False
        self.corners = 0

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
        var material = String()
        swap(material, self.material)
        var positions = List[Float32]()
        swap(positions, self.positions)
        var normals = List[Float32]()
        swap(normals, self.normals)
        var uvs = List[Float32]()
        swap(uvs, self.uvs)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        if self.with_normal:
            geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        if self.with_uv:
            geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
        self.corners = 0
        return ObjObject(name^, material^, geometry^)


def _where(line: Int) -> String:
    """Return the prefix an error names its line with."""
    return "OBJ line " + String(line) + ": "


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
    if value < 0 or value >= pool:
        raise Error(
            _where(line)
            + "a face names an entry the file does not have: "
            + field
        )
    return value


def _rest(fields: List[String]) -> String:
    """Return a line's fields after the first, joined by single spaces:
    the name an `o`, `g` or `usemtl` line gives, which can hold spaces.

    Args:
        fields: The line, split on whitespace.

    Returns:
        The name, or an empty string for a line with nothing after the
        keyword.
    """
    var name = String()
    for index in range(1, len(fields)):
        if index > 1:
            name += " "
        name += fields[index]
    return name^


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
    line: Int,
) raises:
    """Add one face corner to the part being read.

    Args:
        part: The object being read.
        field: The corner: `v`, `v/vt`, `v//vn` or `v/vt/vn`.
        vertices: The position pool so far.
        texcoords: The texture coordinate pool so far.
        normals: The normal pool so far.
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


def _check_convex(points: List[Vector3], line: Int) raises:
    """Refuse a polygon of four or more corners that a fan from its first
    corner would not cover: one that is not convex, or has no area.

    The polygon's normal is Newell's sum over its edges, which is twice
    its area as a vector and is zero for corners on one line. Each corner
    then turns the same way about that normal in a convex polygon, and
    the other way somewhere in a concave one, where a fan triangle would
    cover the cutout. A corner within a millionth of straight is let
    through, since a sliver of a triangle draws nothing and a rounded
    corner should not refuse a file.

    Args:
        points: The corners, in order.
        line: Which line, for the error.

    Raises:
        Error: If the polygon has no area, or a corner turns the wrong
            way.
    """
    var count = len(points)
    var normal = Vector3(0, 0, 0)
    for index in range(count):  # pragma: no branch
        var a = points[index]
        var b = points[(index + 1) % count]
        normal.x += (a.y - b.y) * (a.z + b.z)
        normal.y += (a.z - b.z) * (a.x + b.x)
        normal.z += (a.x - b.x) * (a.y + b.y)
    var area = normal.length()
    if area == 0:
        raise Error(_where(line) + "a face has no area")
    for index in range(count):  # pragma: no branch
        var a = points[index]
        var b = points[(index + 1) % count]
        var c = points[(index + 2) % count]
        var turn = b - a
        turn.cross(c - b)
        if turn.dot(normal) < -1e-6 * area * area:
            raise Error(
                _where(line)
                + "a face is not convex, and only a convex face cuts into a"
                " fan of triangles"
            )


def _read_face(
    mut part: _Part,
    fields: List[String],
    vertices: List[Float32],
    texcoords: List[Float32],
    normals: List[Float32],
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
        _check_convex(points, line)
    # Three corners or more: the loop always runs.
    for triangle in range(corners - 2):  # pragma: no branch
        for which in [0, triangle + 1, triangle + 2]:  # pragma: no branch
            _read_corner(
                part, fields[which + 1], vertices, texcoords, normals, line
            )


def parse_obj(text: String) raises -> ObjModel:
    """Read an OBJ file's text into a model.

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
            same object did not, or the other way round.
    """
    var model = ObjModel()
    var vertices = List[Float32]()
    var texcoords = List[Float32]()
    var normals = List[Float32]()
    var part = _Part(String(), String())
    # Whether an `o` or `g` line has been read yet; see below.
    var declared = False
    var line = 0
    # A split yields at least one piece, even of an empty file: the loop
    # always runs.
    for raw in text.split("\n"):  # pragma: no branch
        line += 1
        var stripped = String(String(raw).strip())
        # A comment runs from `#` to the end of the line, wherever it
        # starts; the format allows one after the data, and three.js reads
        # a trailing one as a corner.
        var comment = stripped.find("#")
        if comment >= 0:
            var data = String(stripped[byte=0:comment].strip())
            stripped = data^
        if stripped == "":
            continue
        var fields = List[String]()
        # The line is not empty here, so it has a first field: the loop
        # always runs.
        for piece in stripped.split():  # pragma: no branch
            fields.append(String(piece))
        var keyword = fields[0]
        if keyword == "v":
            _read_coordinates(vertices, fields, 3, line)
        elif keyword == "vt":
            _read_coordinates(texcoords, fields, 2, line)
        elif keyword == "vn":
            _read_coordinates(normals, fields, 3, line)
        elif keyword == "f":
            _read_face(part, fields, vertices, texcoords, normals, line)
        elif keyword == "o" or keyword == "g":
            if not declared:
                # The first declaration names what was read before it
                # rather than starting afresh, as three.js's `startObject`
                # renames the object it began with: a file that lists
                # faces and then says `o Cube` means those faces are the
                # cube's. Every part already finished came before this
                # line too, so it takes the name as well.
                declared = True
                part.name = _rest(fields)
                for index in range(len(model.objects)):
                    model.objects[index].name = part.name
                continue
            # A new object, under the material in force, as three.js
            # carries it over. One with no faces is dropped.
            var material = part.material
            if part.corners > 0:
                model.objects.append(part.finish())
            part = _Part(_rest(fields), material^)
        elif keyword == "usemtl":
            # A new material starts a new object under the same name,
            # once the current one has faces to keep.
            if part.corners > 0:
                var name = part.name
                model.objects.append(part.finish())
                part = _Part(name^, _rest(fields))
            else:
                part.material = _rest(fields)
    if part.corners > 0:
        model.objects.append(part.finish())
    return model^


def read_obj(path: String) raises -> ObjModel:
    """Read an OBJ file into a model.

    Args:
        path: The file to read.

    Returns:
        Its objects; see `parse_obj`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_obj`
            refuses.
    """
    return parse_obj(Path(path).read_text())
