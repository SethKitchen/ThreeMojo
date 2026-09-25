# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Geometries rebuilt from their parameters, as three.js's
`ObjectLoader.parseGeometries` rebuilds them with each type's `fromJSON`.

A geometry that three.js built from parameters is written as its type and
its parameters, with no arrays. This reads the nineteen built-in types:
`BoxGeometry`, `CapsuleGeometry`, `CircleGeometry`, `ConeGeometry`,
`CylinderGeometry`, `DodecahedronGeometry`, `ExtrudeGeometry`,
`IcosahedronGeometry`, `LatheGeometry`, `OctahedronGeometry`,
`PlaneGeometry`, `PolyhedronGeometry`, `RingGeometry`, `ShapeGeometry`,
`SphereGeometry`, `TetrahedronGeometry`, `TorusGeometry`,
`TorusKnotGeometry` and `TubeGeometry`. Each calls the builder of the same
name in `geometries`, with three.js's constructor default for a key that
is missing.

A shape or an extrusion names its shapes by `uuid`, and they come from
the document's `shapes` library. An extrusion's `extrudePath` is a curve
in space, or a `CurvePath` of them, which three.js writes and cannot read
back.

**Where this port differs.** three.js's `ExtrudeGeometry` turns its
bevel on by default, and so does a document read here that leaves
`bevelEnabled` out. A builder here refuses parameters three.js accepts
without complaint, such as a radius of zero; the error names the problem.
"""

from core.buffer_geometry import (
    BOX_GEOMETRY,
    BufferGeometry,
    CAPSULE_GEOMETRY,
    CIRCLE_GEOMETRY,
    CONE_GEOMETRY,
    CYLINDER_GEOMETRY,
    DODECAHEDRON_GEOMETRY,
    EXTRUDE_GEOMETRY,
    ICOSAHEDRON_GEOMETRY,
    LATHE_GEOMETRY,
    OCTAHEDRON_GEOMETRY,
    PLANE_GEOMETRY,
    POLYHEDRON_GEOMETRY,
    RING_GEOMETRY,
    SHAPE_GEOMETRY,
    SPHERE_GEOMETRY,
    TETRAHEDRON_GEOMETRY,
    TORUS_GEOMETRY,
    TORUS_KNOT_GEOMETRY,
    geometry_type_of,
)
from geometries.box import box
from geometries.capsule import capsule
from geometries.circle import circle, ring
from geometries.cylinder import cone, cylinder
from geometries.extrude import extrude
from geometries.lathe import lathe
from geometries.plane import plane
from geometries.polyhedron import (
    dodecahedron,
    icosahedron,
    octahedron,
    polyhedron,
    tetrahedron,
)
from geometries.shape import shape_geometry
from geometries.sphere import sphere
from geometries.torus import torus, torus_knot
from geometries.tube import tube
from loaders.curve_json import read_curve3, read_curve_path3
from loaders.json import ARRAY, JsonDocument, NO_NODE, OBJECT
from math.curve3 import quadratic_bezier3
from math.path import Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import pi
from units.si import Angle, Length, METER, RADIAN


def _number(
    doc: JsonDocument, item: Int, key: String, default: Float64
) raises -> Float64:
    """Return a number under `key`, or `default`. `parse_json` refuses a
    number beyond a double, so it is finite."""
    var found = doc.get(item, key)
    if found == NO_NODE:
        return default
    return doc.number(found)


def _meters(
    doc: JsonDocument, item: Int, key: String, default: Float64
) raises -> Length:
    """Return a length under `key`, or `default`, in meters."""
    return Length(Float32(_number(doc, item, key, default)), METER)


def _radians(
    doc: JsonDocument, item: Int, key: String, default: Float64
) raises -> Angle:
    """Return an angle under `key`, or `default`, in radians."""
    return Angle(Float32(_number(doc, item, key, default)), RADIAN)


def _count(
    doc: JsonDocument, item: Int, key: String, default: Int
) raises -> Int:
    """Return a whole number under `key`, or `default`."""
    var found = doc.get(item, key)
    if found == NO_NODE:
        return default
    return doc.integer(found)


def _flag(
    doc: JsonDocument, item: Int, key: String, default: Bool
) raises -> Bool:
    """Return a boolean under `key`, or `default`."""
    var found = doc.get(item, key)
    if found == NO_NODE:
        return default
    return doc.boolean(found)


def _list(doc: JsonDocument, item: Int, key: String) raises -> Int:
    """Return an array under `key`, or `NO_NODE`."""
    var found = doc.get(item, key)
    if found != NO_NODE and doc.kind(found) != ARRAY:
        raise Error("Geometry JSON: " + key + " must be an array")
    return found


def _lathe_points(doc: JsonDocument, item: Int) raises -> List[Vector2]:
    """Return a lathe's profile, three.js's `{x, y}` objects, or three.js's
    default of three points."""
    var list = _list(doc, item, "points")
    if list == NO_NODE:
        return [Vector2(0, -0.5), Vector2(0.5, 0), Vector2(0, 0.5)]
    var out = List[Vector2]()
    for at in range(doc.length(list)):  # pragma: no branch
        var point = doc.at(list, at)
        if doc.kind(point) != OBJECT:
            raise Error("Geometry JSON: a lathe point must be {x, y}")
        out.append(
            Vector2(
                Float32(doc.number(doc.get(point, "x"))),
                Float32(doc.number(doc.get(point, "y"))),
            )
        )
    return out^


def _shapes_of(
    doc: JsonDocument, item: Int, library: Dict[String, Shape]
) raises -> List[Shape]:
    """Return the shapes a geometry names, from the `shapes` library."""
    var list = _list(doc, item, "shapes")
    if list == NO_NODE:
        raise Error("Geometry JSON: a shape geometry names no shapes")
    var out = List[Shape]()
    for at in range(doc.length(list)):  # pragma: no branch
        var uuid = doc.string(doc.at(list, at))
        if uuid not in library:
            raise Error("Geometry JSON: a shape that is not there: " + uuid)
        out.append(library[uuid].copy())
    return out^


def _extruded(
    doc: JsonDocument, item: Int, library: Dict[String, Shape]
) raises -> BufferGeometry:
    """Return an `ExtrudeGeometry` from its shapes and options."""
    var shapes = _shapes_of(doc, item, library)
    var options = doc.get(item, "options")
    if options == NO_NODE or doc.kind(options) != OBJECT:
        raise Error("Geometry JSON: an extrusion needs its options")
    var steps = _count(doc, options, "steps", 1)
    var curve_segments = _count(doc, options, "curveSegments", 12)
    var path = doc.get(options, "extrudePath")
    if path != NO_NODE:
        if doc.string(doc.get(path, "type")) == "CurvePath":
            return extrude(
                shapes, read_curve_path3(doc, path), steps, curve_segments
            )
        return extrude(shapes, read_curve3(doc, path), steps, curve_segments)
    var thickness = _number(doc, options, "bevelThickness", 0.2)
    return extrude(
        shapes,
        _meters(doc, options, "depth", 1),
        steps,
        curve_segments,
        _flag(doc, options, "bevelEnabled", True),
        Length(Float32(thickness), METER),
        _meters(doc, options, "bevelSize", thickness - 0.1),
        _meters(doc, options, "bevelOffset", 0),
        _count(doc, options, "bevelSegments", 3),
    )


def geometry_from_parameters(
    doc: JsonDocument, item: Int, library: Dict[String, Shape]
) raises -> BufferGeometry:
    """Build a geometry three.js wrote as its type and parameters.

    Args:
        doc: The document.
        item: The geometry's object.
        library: The document's shapes, by `uuid`.

    Returns:
        The geometry, from the builder of its type, with the type and
        parameters that builder records.

    Raises:
        Error: If the type is not one of the nineteen, a parameter is not
            a number where one is wanted, a shape is not in the library,
            or the builder refuses the parameters.
    """
    var kind = geometry_type_of(doc.string(doc.get(item, "type")))
    var turn = 2 * pi
    if kind == BOX_GEOMETRY:
        return box(
            _meters(doc, item, "width", 1),
            _meters(doc, item, "height", 1),
            _meters(doc, item, "depth", 1),
            _count(doc, item, "widthSegments", 1),
            _count(doc, item, "heightSegments", 1),
            _count(doc, item, "depthSegments", 1),
        )
    if kind == CAPSULE_GEOMETRY:
        return capsule(
            _meters(doc, item, "radius", 1),
            _meters(doc, item, "height", 1),
            _count(doc, item, "capSegments", 4),
            _count(doc, item, "radialSegments", 8),
            _count(doc, item, "heightSegments", 1),
        )
    if kind == CIRCLE_GEOMETRY:
        return circle(
            _meters(doc, item, "radius", 1),
            _count(doc, item, "segments", 32),
            _radians(doc, item, "thetaStart", 0),
            _radians(doc, item, "thetaLength", turn),
        )
    if kind == CONE_GEOMETRY:
        return cone(
            _meters(doc, item, "radius", 1),
            _meters(doc, item, "height", 1),
            _count(doc, item, "radialSegments", 32),
            _count(doc, item, "heightSegments", 1),
            _flag(doc, item, "openEnded", False),
            _radians(doc, item, "thetaStart", 0),
            _radians(doc, item, "thetaLength", turn),
        )
    if kind == CYLINDER_GEOMETRY:
        return cylinder(
            _meters(doc, item, "radiusTop", 1),
            _meters(doc, item, "radiusBottom", 1),
            _meters(doc, item, "height", 1),
            _count(doc, item, "radialSegments", 32),
            _count(doc, item, "heightSegments", 1),
            _flag(doc, item, "openEnded", False),
            _radians(doc, item, "thetaStart", 0),
            _radians(doc, item, "thetaLength", turn),
        )
    if kind == DODECAHEDRON_GEOMETRY:
        return dodecahedron(
            _meters(doc, item, "radius", 1), _count(doc, item, "detail", 0)
        )
    if kind == ICOSAHEDRON_GEOMETRY:
        return icosahedron(
            _meters(doc, item, "radius", 1), _count(doc, item, "detail", 0)
        )
    if kind == OCTAHEDRON_GEOMETRY:
        return octahedron(
            _meters(doc, item, "radius", 1), _count(doc, item, "detail", 0)
        )
    if kind == TETRAHEDRON_GEOMETRY:
        return tetrahedron(
            _meters(doc, item, "radius", 1), _count(doc, item, "detail", 0)
        )
    if kind == POLYHEDRON_GEOMETRY:
        var vertices = List[Float32]()
        var indices = List[Int]()
        var vertex_list = _list(doc, item, "vertices")
        if vertex_list != NO_NODE:
            for at in range(doc.length(vertex_list)):  # pragma: no branch
                vertices.append(Float32(doc.number(doc.at(vertex_list, at))))
        var index_list = _list(doc, item, "indices")
        if index_list != NO_NODE:
            for at in range(doc.length(index_list)):  # pragma: no branch
                indices.append(doc.integer(doc.at(index_list, at)))
        return polyhedron(
            vertices,
            indices,
            _meters(doc, item, "radius", 1),
            _count(doc, item, "detail", 0),
        )
    if kind == LATHE_GEOMETRY:
        return lathe(
            _lathe_points(doc, item),
            _count(doc, item, "segments", 12),
            _radians(doc, item, "phiStart", 0),
            _radians(doc, item, "phiLength", turn),
        )
    if kind == PLANE_GEOMETRY:
        return plane(
            _meters(doc, item, "width", 1),
            _meters(doc, item, "height", 1),
            _count(doc, item, "widthSegments", 1),
            _count(doc, item, "heightSegments", 1),
        )
    if kind == RING_GEOMETRY:
        return ring(
            _meters(doc, item, "innerRadius", 0.5),
            _meters(doc, item, "outerRadius", 1),
            _count(doc, item, "thetaSegments", 32),
            _count(doc, item, "phiSegments", 1),
            _radians(doc, item, "thetaStart", 0),
            _radians(doc, item, "thetaLength", turn),
        )
    if kind == SPHERE_GEOMETRY:
        return sphere(
            _meters(doc, item, "radius", 1),
            _count(doc, item, "widthSegments", 32),
            _count(doc, item, "heightSegments", 16),
            _radians(doc, item, "phiStart", 0),
            _radians(doc, item, "phiLength", turn),
            _radians(doc, item, "thetaStart", 0),
            _radians(doc, item, "thetaLength", pi),
        )
    if kind == TORUS_GEOMETRY:
        return torus(
            _meters(doc, item, "radius", 1),
            _meters(doc, item, "tube", 0.4),
            _count(doc, item, "radialSegments", 12),
            _count(doc, item, "tubularSegments", 48),
            _radians(doc, item, "arc", turn),
        )
    if kind == TORUS_KNOT_GEOMETRY:
        return torus_knot(
            _meters(doc, item, "radius", 1),
            _meters(doc, item, "tube", 0.4),
            _count(doc, item, "tubularSegments", 64),
            _count(doc, item, "radialSegments", 8),
            _count(doc, item, "p", 2),
            _count(doc, item, "q", 3),
        )
    if kind == SHAPE_GEOMETRY:
        return shape_geometry(
            _shapes_of(doc, item, library),
            _count(doc, item, "curveSegments", 12),
        )
    if kind == EXTRUDE_GEOMETRY:
        return _extruded(doc, item, library)
    # The only type left is the tube; `geometry_type_of` refused the rest,
    # and `BufferGeometry` is read from its arrays before this is called.
    var path = doc.get(item, "path")
    var curve = quadratic_bezier3(
        Vector3(-1, -1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0)
    ) if path == NO_NODE else read_curve3(doc, path)
    return tube(
        curve,
        _meters(doc, item, "radius", 1),
        _count(doc, item, "tubularSegments", 64),
        _count(doc, item, "radialSegments", 8),
        _flag(doc, item, "closed", False),
    )
