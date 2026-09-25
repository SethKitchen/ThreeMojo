# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Curves, paths and shapes as three.js JSON, both ways: three.js's
`Curve.toJSON` and `fromJSON`, and those of `CurvePath`, `Path` and
`Shape`.

Each curve is written as three.js writes it: its `metadata`, its
`arcLengthDivisions` and its `type`, then the numbers its type keeps. A
plane curve is a `LineCurve`, a `QuadraticBezierCurve`, a
`CubicBezierCurve`, a `SplineCurve` or an `EllipseCurve`, and an
`ArcCurve` reads as the ellipse it is. A curve in space is a
`LineCurve3`, a `QuadraticBezierCurve3`, a `CubicBezierCurve3` or a
`CatmullRomCurve3`. A path is a `CurvePath` with a `currentPoint`, and a
shape is a path with a `uuid` and its holes.

**Where this port differs.** `arcLengthDivisions` is written as 200,
three.js's default, and read without effect: the port measures every
curve with 200 divisions. A straight run of no length is refused, as
`math.curve.line` refuses it. A `Shape` here must be closed, so an open
outline or hole is closed by a straight run back to its start when it is
read. The filled surface is the same, but the closing point is a point
more. `close_path` moves the pen back to the start here, and three.js's
`closePath` leaves `currentPoint` where it was, so the two can write a
different `currentPoint` for a path closed that way.
"""

from exporters.json_writer import JsonWriter
from loaders.json import ARRAY, JsonDocument, NO_NODE, OBJECT, parse_json
from math.curve import (
    CUBIC,
    Curve,
    ELLIPSE,
    LINE,
    QUADRATIC,
    SPLINE,
    cubic_bezier,
    ellipse,
    line,
    quadratic_bezier,
    spline,
)
from math.curve3 import (
    CATMULL_ROM3,
    CATMULLROM,
    CENTRIPETAL,
    CHORDAL,
    CUBIC3,
    CatmullRomType,
    Curve3,
    CurvePath3,
    LINE3,
    QUADRATIC3,
    catmull_rom3,
    cubic_bezier3,
    line3,
    quadratic_bezier3,
)
from math.path import Path, Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from units.si import Angle, Length, METER, RADIAN

# three.js 0.180's JSON format version, in every curve's `metadata`.
comptime CURVE_FORMAT = Float32(4.7)
# three.js's default `arcLengthDivisions`, the one this port measures by.
comptime ARC_LENGTH_DIVISIONS = 200


# --- writing -----------------------------------------------------------------


def _head(
    mut writer: JsonWriter, type_name: String, metadata: Bool = True
) raises:
    """Write three.js's `Curve.toJSON` fields: the metadata, unless a
    library leaves it out, the arc length divisions and the type."""
    if metadata:
        _metadata(writer)
    writer.key("arcLengthDivisions")
    writer.integer(ARC_LENGTH_DIVISIONS)
    writer.key("type")
    writer.string(type_name)


def _metadata(mut writer: JsonWriter) raises:
    """Write a curve's `metadata`."""
    writer.key("metadata")
    writer.begin_object()
    writer.key("version")
    writer.number(CURVE_FORMAT)
    writer.key("type")
    writer.string("Curve")
    writer.key("generator")
    writer.string("Curve.toJSON")
    writer.end_object()


def _vector2(mut writer: JsonWriter, key: String, v: Vector2) raises:
    """Write a point as three.js's `toArray`."""
    writer.key(key)
    writer.begin_array()
    writer.number(v.x)
    writer.number(v.y)
    writer.end_array()


def _vector3(mut writer: JsonWriter, key: String, v: Vector3) raises:
    """Write a point in space as three.js's `toArray`."""
    writer.key(key)
    writer.begin_array()
    writer.number(v.x)
    writer.number(v.y)
    writer.number(v.z)
    writer.end_array()


def curve_type_name(curve: Curve) -> String:
    """Return three.js's class name for a plane curve.

    Args:
        curve: The curve.

    Returns:
        `LineCurve`, `QuadraticBezierCurve`, `CubicBezierCurve`,
        `SplineCurve` or `EllipseCurve`.
    """
    if curve.kind == LINE:
        return "LineCurve"
    if curve.kind == QUADRATIC:
        return "QuadraticBezierCurve"
    if curve.kind == CUBIC:
        return "CubicBezierCurve"
    if curve.kind == SPLINE:
        return "SplineCurve"
    return "EllipseCurve"


def write_curve(mut writer: JsonWriter, curve: Curve) raises:
    """Write a plane curve as three.js's `toJSON` writes it.

    Args:
        writer: Where the curve's object goes.
        curve: The curve.

    Raises:
        Error: If the writer is not where a value can go.
    """
    writer.begin_object()
    _head(writer, curve_type_name(curve))
    if curve.kind == LINE:
        _vector2(writer, "v1", curve.points[0])
        _vector2(writer, "v2", curve.points[1])
    elif curve.kind == ELLIPSE:
        writer.key("aX")
        writer.number(curve.points[0].x)
        writer.key("aY")
        writer.number(curve.points[0].y)
        writer.key("xRadius")
        writer.number(curve.radii.x)
        writer.key("yRadius")
        writer.number(curve.radii.y)
        writer.key("aStartAngle")
        writer.number(curve.start)
        writer.key("aEndAngle")
        writer.number(curve.end)
        writer.key("aClockwise")
        writer.boolean(curve.clockwise)
        writer.key("aRotation")
        writer.number(curve.rotation)
    elif curve.kind == SPLINE:
        writer.key("points")
        writer.begin_array()
        for point in curve.points:  # pragma: no branch
            writer.begin_array()
            writer.number(point.x)
            writer.number(point.y)
            writer.end_array()
        writer.end_array()
    else:
        # A Bezier: its points are v0, v1 and on.
        for at in range(len(curve.points)):  # pragma: no branch
            _vector2(writer, "v" + String(at), curve.points[at])
    writer.end_object()


def _path_fields(
    mut writer: JsonWriter, path: Path, type_name: String, metadata: Bool
) raises:
    """Write a path's fields, three.js's `Path.toJSON` without the braces."""
    _head(writer, type_name, metadata)
    writer.key("autoClose")
    writer.boolean(False)
    writer.key("curves")
    writer.begin_array()
    for curve in path.curves:
        write_curve(writer, curve)
    writer.end_array()
    _vector2(writer, "currentPoint", path.last)


def write_path(mut writer: JsonWriter, path: Path) raises:
    """Write a path as three.js's `Path.toJSON` writes it.

    Args:
        writer: Where the path's object goes.
        path: The path.

    Raises:
        Error: If the writer is not where a value can go.
    """
    writer.begin_object()
    _path_fields(writer, path, "Path", True)
    writer.end_object()


def write_shape(
    mut writer: JsonWriter, shape: Shape, uuid: String, metadata: Bool = True
) raises:
    """Write a shape as three.js's `Shape.toJSON` writes it.

    Args:
        writer: Where the shape's object goes.
        shape: The shape.
        uuid: The name the shape is written under, three.js's `uuid`.
        metadata: False for an entry of a scene's `shapes` library, which
            three.js writes without its own `metadata`.

    Raises:
        Error: If the writer is not where a value can go.
    """
    writer.begin_object()
    _path_fields(writer, shape.outline, "Shape", metadata)
    writer.key("uuid")
    writer.string(uuid)
    writer.key("holes")
    writer.begin_array()
    for hole in shape.holes:
        write_path(writer, hole)
    writer.end_array()
    writer.end_object()


def curve3_type_name(curve: Curve3) -> String:
    """Return three.js's class name for a curve in space.

    Args:
        curve: The curve.

    Returns:
        `LineCurve3`, `QuadraticBezierCurve3`, `CubicBezierCurve3` or
        `CatmullRomCurve3`.
    """
    if curve.kind == LINE3:
        return "LineCurve3"
    if curve.kind == QUADRATIC3:
        return "QuadraticBezierCurve3"
    if curve.kind == CUBIC3:
        return "CubicBezierCurve3"
    return "CatmullRomCurve3"


def catmull_rom_type_name(curve_type: CatmullRomType) -> String:
    """Return three.js's `curveType` word.

    Args:
        curve_type: The type.

    Returns:
        `centripetal`, `chordal` or `catmullrom`.
    """
    if curve_type == CHORDAL:
        return "chordal"
    if curve_type == CATMULLROM:
        return "catmullrom"
    return "centripetal"


def write_curve3(mut writer: JsonWriter, curve: Curve3) raises:
    """Write a curve in space as three.js's `toJSON` writes it.

    Args:
        writer: Where the curve's object goes.
        curve: The curve.

    Raises:
        Error: If the writer is not where a value can go.
    """
    writer.begin_object()
    _head(writer, curve3_type_name(curve))
    if curve.kind == LINE3:
        _vector3(writer, "v1", curve.points[0])
        _vector3(writer, "v2", curve.points[1])
    elif curve.kind == CATMULL_ROM3:
        writer.key("points")
        writer.begin_array()
        for point in curve.points:  # pragma: no branch
            writer.begin_array()
            writer.number(point.x)
            writer.number(point.y)
            writer.number(point.z)
            writer.end_array()
        writer.end_array()
        writer.key("closed")
        writer.boolean(curve.closed)
        writer.key("curveType")
        writer.string(catmull_rom_type_name(curve.curve_type))
        writer.key("tension")
        writer.number(curve.tension)
    else:
        for at in range(len(curve.points)):  # pragma: no branch
            _vector3(writer, "v" + String(at), curve.points[at])
    writer.end_object()


def write_curve_path3(mut writer: JsonWriter, path: CurvePath3) raises:
    """Write a path of curves in space as three.js's `CurvePath.toJSON`
    writes it.

    Args:
        writer: Where the path's object goes.
        path: The path.

    Raises:
        Error: If the writer is not where a value can go.
    """
    writer.begin_object()
    _head(writer, "CurvePath")
    writer.key("autoClose")
    writer.boolean(False)
    writer.key("curves")
    writer.begin_array()
    for curve in path.curves:  # pragma: no branch
        write_curve3(writer, curve)
    writer.end_array()
    writer.end_object()


# --- reading -----------------------------------------------------------------


def _field(doc: JsonDocument, node: Int, key: String) raises -> Int:
    """Return a field that must be there."""
    var found = doc.get(node, key)
    if found == NO_NODE:
        raise Error("Curve JSON: a curve has no " + key)
    return found


def _numbers(
    doc: JsonDocument, node: Int, key: String, count: Int
) raises -> List[Float32]:
    """Return an array of `count` numbers."""
    var list = _field(doc, node, key)
    if doc.kind(list) != ARRAY or doc.length(list) != count:
        raise Error(
            "Curve JSON: " + key + " must hold " + String(count) + " numbers"
        )
    var out = List[Float32]()
    for at in range(count):  # pragma: no branch
        out.append(Float32(doc.number(doc.at(list, at))))
    return out^


def _point2(doc: JsonDocument, node: Int, key: String) raises -> Vector2:
    """Return a point written as `[x, y]`."""
    var xy = _numbers(doc, node, key, 2)
    return Vector2(xy[0], xy[1])


def _point3(doc: JsonDocument, node: Int, key: String) raises -> Vector3:
    """Return a point written as `[x, y, z]`."""
    var xyz = _numbers(doc, node, key, 3)
    return Vector3(xyz[0], xyz[1], xyz[2])


def _number(doc: JsonDocument, node: Int, key: String) raises -> Float32:
    """Return a number field that must be there."""
    return Float32(doc.number(_field(doc, node, key)))


def _object(doc: JsonDocument, node: Int) raises:
    """Refuse a node that is not an object."""
    if doc.kind(node) != OBJECT:
        raise Error("Curve JSON: a curve must be an object")


def _list(doc: JsonDocument, node: Int, key: String) raises -> Int:
    """Return an array field that must be there."""
    var list = _field(doc, node, key)
    if doc.kind(list) != ARRAY:
        raise Error("Curve JSON: " + key + " must be an array")
    return list


def read_curve(doc: JsonDocument, node: Int) raises -> Curve:
    """Build a plane curve from its JSON, three.js's `fromJSON`.

    Args:
        doc: The document.
        node: The curve's object.

    Returns:
        The curve.

    Raises:
        Error: If the node is not a curve of a type there is, a field is
            missing or of the wrong kind, or the curve is refused by its
            builder in `math.curve`.
    """
    _object(doc, node)
    var type_name = doc.string(_field(doc, node, "type"))
    if type_name == "LineCurve":
        return line(_point2(doc, node, "v1"), _point2(doc, node, "v2"))
    if type_name == "QuadraticBezierCurve":
        return quadratic_bezier(
            _point2(doc, node, "v0"),
            _point2(doc, node, "v1"),
            _point2(doc, node, "v2"),
        )
    if type_name == "CubicBezierCurve":
        return cubic_bezier(
            _point2(doc, node, "v0"),
            _point2(doc, node, "v1"),
            _point2(doc, node, "v2"),
            _point2(doc, node, "v3"),
        )
    if type_name == "SplineCurve":
        var list = _list(doc, node, "points")
        var points = List[Vector2]()
        for at in range(doc.length(list)):  # pragma: no branch
            var xy = doc.at(list, at)
            if doc.kind(xy) != ARRAY or doc.length(xy) != 2:
                raise Error("Curve JSON: a spline point must be [x, y]")
            points.append(
                Vector2(
                    Float32(doc.number(doc.at(xy, 0))),
                    Float32(doc.number(doc.at(xy, 1))),
                )
            )
        return spline(points^)
    if type_name == "EllipseCurve" or type_name == "ArcCurve":
        return ellipse(
            Vector2(_number(doc, node, "aX"), _number(doc, node, "aY")),
            Length(_number(doc, node, "xRadius"), METER),
            Length(_number(doc, node, "yRadius"), METER),
            Angle(_number(doc, node, "aStartAngle"), RADIAN),
            Angle(_number(doc, node, "aEndAngle"), RADIAN),
            doc.boolean(_field(doc, node, "aClockwise")),
            Angle(_number(doc, node, "aRotation"), RADIAN),
        )
    raise Error("Curve JSON: a plane curve type that is not read: " + type_name)


def read_path(doc: JsonDocument, node: Int) raises -> Path:
    """Build a path from its JSON, three.js's `Path.fromJSON`.

    The pen is left at `currentPoint`, and the path starts where its first
    curve starts, or at `currentPoint` when it has none.

    Args:
        doc: The document.
        node: The path's object.

    Returns:
        The path, open or closed as the JSON has it.

    Raises:
        Error: If a field is missing or of the wrong kind, or a curve is
            refused; see `read_curve`.
    """
    _object(doc, node)
    var list = _list(doc, node, "curves")
    var pen = _point2(doc, node, "currentPoint")
    var path = Path(pen)
    for at in range(doc.length(list)):
        path.curves.append(read_curve(doc, doc.at(list, at)))
    if len(path.curves) > 0:
        path.first = path.curves[0].point(0)
    return path^


def _closed(var path: Path) raises -> Path:
    """Return a path closed by a straight run back to its start, when it
    is open."""
    if not path.is_closed():
        path.close_path()
    return path^


def read_shape(doc: JsonDocument, node: Int) raises -> Shape:
    """Build a shape from its JSON, three.js's `Shape.fromJSON`.

    An open outline or hole is closed by a straight run back to its
    start, since a `Shape` here is closed.

    Args:
        doc: The document.
        node: The shape's object.

    Returns:
        The shape, with the `uuid` the JSON gives it.

    Raises:
        Error: If a field is missing or of the wrong kind, if a curve is
            refused, or if the outline or a hole has no curves.
    """
    var outline = _closed(read_path(doc, node))
    var shape = Shape(outline^)
    var holes = _list(doc, node, "holes")
    for at in range(doc.length(holes)):
        shape.add_hole(_closed(read_path(doc, doc.at(holes, at))))
    var uuid = doc.get(node, "uuid")
    if uuid != NO_NODE:
        shape.uuid = doc.string(uuid)
    return shape^


def catmull_rom_type_of(word: String) raises -> CatmullRomType:
    """Return the type three.js's `curveType` word names.

    Args:
        word: `centripetal`, `chordal` or `catmullrom`.

    Returns:
        The type.

    Raises:
        Error: If the word names no type.
    """
    if word == "centripetal":
        return CENTRIPETAL
    if word == "chordal":
        return CHORDAL
    if word == "catmullrom":
        return CATMULLROM
    raise Error("Curve JSON: a curveType that is not read: " + word)


def read_curve3(doc: JsonDocument, node: Int) raises -> Curve3:
    """Build a curve in space from its JSON, three.js's `fromJSON`.

    Args:
        doc: The document.
        node: The curve's object.

    Returns:
        The curve.

    Raises:
        Error: If the node is not a curve in space of a type there is, a
            field is missing or of the wrong kind, or the curve is
            refused by its builder in `math.curve3`.
    """
    _object(doc, node)
    var type_name = doc.string(_field(doc, node, "type"))
    if type_name == "LineCurve3":
        return line3(_point3(doc, node, "v1"), _point3(doc, node, "v2"))
    if type_name == "QuadraticBezierCurve3":
        return quadratic_bezier3(
            _point3(doc, node, "v0"),
            _point3(doc, node, "v1"),
            _point3(doc, node, "v2"),
        )
    if type_name == "CubicBezierCurve3":
        return cubic_bezier3(
            _point3(doc, node, "v0"),
            _point3(doc, node, "v1"),
            _point3(doc, node, "v2"),
            _point3(doc, node, "v3"),
        )
    if type_name == "CatmullRomCurve3":
        var list = _list(doc, node, "points")
        var points = List[Vector3]()
        for at in range(doc.length(list)):  # pragma: no branch
            var xyz = doc.at(list, at)
            if doc.kind(xyz) != ARRAY or doc.length(xyz) != 3:
                raise Error("Curve JSON: a spline point must be [x, y, z]")
            points.append(
                Vector3(
                    Float32(doc.number(doc.at(xyz, 0))),
                    Float32(doc.number(doc.at(xyz, 1))),
                    Float32(doc.number(doc.at(xyz, 2))),
                )
            )
        return catmull_rom3(
            points^,
            doc.boolean(_field(doc, node, "closed")),
            catmull_rom_type_of(doc.string(_field(doc, node, "curveType"))),
            _number(doc, node, "tension"),
        )
    raise Error(
        "Curve JSON: a curve type in space that is not read: " + type_name
    )


def read_curve_path3(doc: JsonDocument, node: Int) raises -> CurvePath3:
    """Build a path of curves in space from its JSON, three.js's
    `CurvePath.fromJSON`.

    Args:
        doc: The document.
        node: The path's object.

    Returns:
        The path.

    Raises:
        Error: If a field is missing or of the wrong kind, or a curve is
            refused; see `read_curve3`.
    """
    _object(doc, node)
    var list = _list(doc, node, "curves")
    var path = CurvePath3()
    for at in range(doc.length(list)):  # pragma: no branch
        path.add(read_curve3(doc, doc.at(list, at)))
    return path^


# --- whole documents ---------------------------------------------------------


def curve_to_json(curve: Curve) raises -> String:
    """Return a plane curve as a three.js JSON document.

    Args:
        curve: The curve.

    Returns:
        The document.

    Raises:
        Error: If the writer fails, which it does not for a curve.
    """
    var writer = JsonWriter()
    write_curve(writer, curve)
    return writer.finish()


def curve_from_json(text: String) raises -> Curve:
    """Return the plane curve a three.js JSON document holds.

    Args:
        text: The document.

    Returns:
        The curve.

    Raises:
        Error: If the text is not JSON, or `read_curve` refuses it.
    """
    var doc = parse_json(text)
    return read_curve(doc, doc.root())


def shape_to_json(shape: Shape) raises -> String:
    """Return a shape as a three.js JSON document, under its own `uuid`.

    Args:
        shape: The shape.

    Returns:
        The document.

    Raises:
        Error: If the shape has no `uuid`.
    """
    if shape.uuid == "":
        raise Error("Curve JSON: a shape needs a uuid to be written")
    var writer = JsonWriter()
    write_shape(writer, shape, shape.uuid)
    return writer.finish()


def shape_from_json(text: String) raises -> Shape:
    """Return the shape a three.js JSON document holds.

    Args:
        text: The document.

    Returns:
        The shape.

    Raises:
        Error: If the text is not JSON, or `read_shape` refuses it.
    """
    var doc = parse_json(text)
    return read_shape(doc, doc.root())


def curve3_to_json(curve: Curve3) raises -> String:
    """Return a curve in space as a three.js JSON document.

    Args:
        curve: The curve.

    Returns:
        The document.

    Raises:
        Error: If the writer fails, which it does not for a curve.
    """
    var writer = JsonWriter()
    write_curve3(writer, curve)
    return writer.finish()


def curve3_from_json(text: String) raises -> Curve3:
    """Return the curve in space a three.js JSON document holds.

    Args:
        text: The document.

    Returns:
        The curve.

    Raises:
        Error: If the text is not JSON, or `read_curve3` refuses it.
    """
    var doc = parse_json(text)
    return read_curve3(doc, doc.root())
