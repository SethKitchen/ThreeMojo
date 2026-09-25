# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the full signatures of the box, the sphere, the shape and the
extrusion, each against what three.js 0.180 builds for the same call.

`assets/geometries/three_geometries.json` holds three.js's arrays, and
`assets/geometries/three_geometries.mjs` writes it in Node.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.box import box
from geometries.extrude import UVGenerator, extrude
from geometries.shape import shape_geometry
from geometries.sphere import sphere
from loaders.json import JsonDocument, parse_json
from math.path import Path as Outline, Shape
from math.vector2 import Vector2
from std.math import inf, pi
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN


struct Reference:
    """The geometries three.js builds, by name."""

    var document: JsonDocument

    def __init__(out self) raises:
        """Read the reference file."""
        self.document = parse_json(
            Path("assets/geometries/three_geometries.json").read_text()
        )

    def check(self, name: String, geometry: BufferGeometry) raises:
        """Assert a geometry holds three.js's arrays for `name`: the same
        positions, normals and texture coordinates in the same order, the
        same index, and the same groups."""
        ref doc = self.document
        var entry = doc.get(doc.root(), name)
        var attributes: List[String] = [
            String(POSITION),
            String(NORMAL),
            String(UV),
        ]
        var keys: List[String] = ["position", "normal", "uv"]
        for at in range(3):
            var theirs = doc.get(entry, keys[at])
            ref ours = geometry.attribute_view(attributes[at])
            var size = ours.item_size
            assert_equal(
                ours.count() * size, doc.length(theirs), name + " " + keys[at]
            )
            for i in range(doc.length(theirs)):
                assert_almost_equal(
                    Float64(ours.component(i // size, i % size)),
                    doc.number(doc.at(theirs, i)),
                    atol=1e-5,
                    msg=name + " " + keys[at] + " " + String(i),
                )
        var index = doc.get(entry, "index")
        if doc.length(index) == 0:
            assert_true(not geometry.is_indexed(), name + " has an index")
        else:
            ref ours = geometry.index
            assert_equal(len(ours), doc.length(index), name + " index")
            for i in range(len(ours)):
                assert_equal(
                    ours[i], Int(doc.number(doc.at(index, i))), name + " index"
                )
        var groups = doc.get(entry, "groups")
        assert_equal(len(geometry.groups), doc.length(groups), name + " groups")
        for g in range(len(geometry.groups)):
            var triple = doc.at(groups, g)
            assert_equal(
                geometry.groups[g].start, Int(doc.number(doc.at(triple, 0)))
            )
            assert_equal(
                geometry.groups[g].count, Int(doc.number(doc.at(triple, 1)))
            )
            assert_equal(
                geometry.groups[g].material_index.value,
                Int(doc.number(doc.at(triple, 2))),
            )

    def surface(self, name: String, geometry: BufferGeometry) raises:
        """Assert a geometry is the surface three.js builds for `name`: the
        same groups, and in each group the same number of triangles, the
        same area, and the same vertices, each with its position, normal
        and texture coordinate.

        The order of the vertices and of the triangles is not compared:
        three.js triangulates a shape with earcut, and this port with its
        own ear clipping, so two triangles can take the other diagonal.
        """
        ref doc = self.document
        var entry = doc.get(doc.root(), name)
        var groups = doc.get(entry, "groups")
        assert_equal(len(geometry.groups), doc.length(groups), name + " groups")
        var theirs = _Triangles(doc, entry)
        var ours = _Triangles(geometry)
        for g in range(len(geometry.groups)):
            var triple = doc.at(groups, g)
            var start = Int(doc.number(doc.at(triple, 0)))
            var count = Int(doc.number(doc.at(triple, 1)))
            assert_equal(geometry.groups[g].count, count, name + " group")
            assert_equal(
                geometry.groups[g].material_index.value,
                Int(doc.number(doc.at(triple, 2))),
            )
            var here = geometry.groups[g].start
            assert_almost_equal(
                ours.area(here, count), theirs.area(start, count), atol=1e-4
            )
            var mine = ours.corners(here, count)
            var wanted = theirs.corners(start, count)
            assert_equal(len(mine), len(wanted), name + " vertices")
            for key in wanted:
                assert_true(key in mine, name + " lacks " + key)


struct _Triangles:
    """A geometry's corners in drawing order, each as its position, normal
    and texture coordinate, from this port or from three.js's arrays."""

    var keys: List[String]
    var positions: List[Float32]

    def __init__(out self, geometry: BufferGeometry) raises:
        """Read a geometry, through its index if it has one."""
        self.keys = List[String]()
        self.positions = List[Float32]()
        ref at = geometry.attribute_view(String(POSITION))
        ref facing = geometry.attribute_view(String(NORMAL))
        ref placed = geometry.attribute_view(String(UV))
        var total = len(geometry.index) if geometry.is_indexed() else at.count()
        for corner in range(total):
            var v = geometry.index[corner] if geometry.is_indexed() else corner
            var values = List[Float32]()
            for k in range(3):
                values.append(at.component(v, k))
                self.positions.append(at.component(v, k))
            for k in range(3):
                values.append(facing.component(v, k))
            for k in range(2):
                values.append(placed.component(v, k))
            self.keys.append(_key(values))

    def __init__(out self, doc: JsonDocument, entry: Int) raises:
        """Read three.js's arrays."""
        self.keys = List[String]()
        self.positions = List[Float32]()
        var position = doc.get(entry, "position")
        var normal = doc.get(entry, "normal")
        var uv = doc.get(entry, "uv")
        var index = doc.get(entry, "index")
        var indexed = doc.length(index) > 0
        var total = doc.length(index) if indexed else doc.length(position) // 3
        for corner in range(total):
            var v = Int(
                doc.number(doc.at(index, corner))
            ) if indexed else corner
            var values = List[Float32]()
            for k in range(3):
                var x = Float32(doc.number(doc.at(position, v * 3 + k)))
                values.append(x)
                self.positions.append(x)
            for k in range(3):
                values.append(Float32(doc.number(doc.at(normal, v * 3 + k))))
            for k in range(2):
                values.append(Float32(doc.number(doc.at(uv, v * 2 + k))))
            self.keys.append(_key(values))

    def area(self, start: Int, count: Int) -> Float64:
        """Return the summed area of the triangles of a group."""
        var total = Float64(0)
        for t in range(start // 3, (start + count) // 3):
            ref p = self.positions
            var a = t * 9
            var ux = Float64(p[a + 3] - p[a])
            var uy = Float64(p[a + 4] - p[a + 1])
            var uz = Float64(p[a + 5] - p[a + 2])
            var vx = Float64(p[a + 6] - p[a])
            var vy = Float64(p[a + 7] - p[a + 1])
            var vz = Float64(p[a + 8] - p[a + 2])
            var cx = uy * vz - uz * vy
            var cy = uz * vx - ux * vz
            var cz = ux * vy - uy * vx
            total += (cx * cx + cy * cy + cz * cz) ** 0.5 / 2
        return total

    def corners(self, start: Int, count: Int) -> List[String]:
        """Return the distinct corners of a group."""
        var seen = List[String]()
        for c in range(start, start + count):
            if not (self.keys[c] in seen):
                seen.append(self.keys[c])
        return seen^


def _key(values: List[Float32]) -> String:
    """Return values rounded to four places, as one text."""
    var out = String()
    for value in values:
        var half = Float32(0.5) if value >= 0 else Float32(-0.5)
        var rounded = Int(value * 10000 + half)
        out += String(rounded) + ","
    return out


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def radians(value: Float32) -> Angle:
    """Return an angle in radians."""
    return Angle(value, RADIAN)


# --- boxes -------------------------------------------------------------------


def test_a_box_is_three_js_box() raises:
    var three = Reference()
    three.check("box_plain", box(meters(1), meters(2), meters(3)))
    three.check("box_segments", box(meters(1), meters(2), meters(3), 2, 3, 4))


def test_a_box_needs_a_segment_a_side() raises:
    for wrong in [0, -1]:
        with assert_raises(contains="segment"):
            _ = box(meters(1), meters(1), meters(1), wrong)
        with assert_raises(contains="segment"):
            _ = box(meters(1), meters(1), meters(1), 1, wrong)
        with assert_raises(contains="segment"):
            _ = box(meters(1), meters(1), meters(1), 1, 1, wrong)


# --- spheres -----------------------------------------------------------------


def test_a_sphere_is_three_js_sphere() raises:
    var three = Reference()
    three.check("sphere_whole", sphere(meters(1.5), 8, 6))
    three.check(
        "sphere_band",
        sphere(
            meters(1.5),
            8,
            6,
            radians(0.5),
            radians(4),
            radians(0.3),
            radians(2),
        ),
    )
    # A cap from the north pole keeps its pole; a band past the south pole
    # reaches it.
    three.check(
        "sphere_cap",
        sphere(
            meters(1.5),
            8,
            6,
            radians(0),
            radians(Float32(2 * pi)),
            radians(0),
            radians(1),
        ),
    )
    three.check(
        "sphere_bottom",
        sphere(
            meters(1.5),
            8,
            6,
            radians(1),
            radians(2),
            radians(2),
            radians(Float32(pi)),
        ),
    )


def test_a_sphere_refuses_an_angle_that_is_not_finite() raises:
    var bad = radians(inf[DType.float32]())
    with assert_raises(contains="finite"):
        _ = sphere(meters(1), 8, 6, bad)
    with assert_raises(contains="finite"):
        _ = sphere(meters(1), 8, 6, radians(0), bad)
    with assert_raises(contains="finite"):
        _ = sphere(meters(1), 8, 6, radians(0), radians(1), bad)
    with assert_raises(contains="finite"):
        _ = sphere(meters(1), 8, 6, radians(0), radians(1), radians(0), bad)


# --- shapes and extrusions ----------------------------------------------------


def square(x: Float32, y: Float32, side: Float32) raises -> Shape:
    """Return a square outline from its bottom-left corner."""
    var outline = Outline(Vector2(x, y))
    outline.line_to(Vector2(x + side, y))
    outline.line_to(Vector2(x + side, y + side))
    outline.line_to(Vector2(x, y + side))
    outline.line_to(Vector2(x, y))
    return Shape(outline^)


def triangle(x: Float32, y: Float32) raises -> Shape:
    """Return a triangle outline from its bottom-left corner."""
    var outline = Outline(Vector2(x, y))
    outline.line_to(Vector2(x + 2, y))
    outline.line_to(Vector2(x + 1, y + 1.5))
    outline.line_to(Vector2(x, y))
    return Shape(outline^)


def two_shapes() raises -> List[Shape]:
    """Return the square and the triangle three_geometries.mjs makes."""
    return [square(0, 0, 1), triangle(3, 0)]


def test_a_list_of_shapes_is_three_js_shape_geometry() raises:
    # One group per shape, its material index its place in the list.
    Reference().surface("shapes_flat", shape_geometry(two_shapes(), 4))


def test_a_list_of_shapes_is_three_js_extrusion() raises:
    # Each shape adds its caps and its walls, material 0 and material 1.
    Reference().surface(
        "shapes_extruded", extrude(two_shapes(), meters(0.5), steps=2)
    )


def halving_top(
    vertices: List[Float32], a: Int, b: Int, c: Int
) -> List[Vector2]:
    """Return a cap's coordinates as its x and y, halved."""
    var out = List[Vector2]()
    for at in [a, b, c]:
        out.append(Vector2(vertices[at * 3] / 2, vertices[at * 3 + 1] / 2))
    return out^


def x_and_z(
    vertices: List[Float32], a: Int, b: Int, c: Int, d: Int
) -> List[Vector2]:
    """Return a wall's coordinates as each corner's x and z."""
    var out = List[Vector2]()
    for at in [a, b, c, d]:
        out.append(Vector2(vertices[at * 3], vertices[at * 3 + 2]))
    return out^


def test_an_extrusion_takes_a_uv_generator_of_its_own() raises:
    # three.js's `UVGenerator` option, asked as three.js asks it.
    Reference().surface(
        "extruded_uv_generator",
        extrude(
            square(0, 0, 1),
            meters(0.5),
            uv_generator=UVGenerator(halving_top, x_and_z),
        ),
    )


def too_few(vertices: List[Float32], a: Int, b: Int, c: Int) -> List[Vector2]:
    """Return one coordinate where three are owed."""
    return [Vector2(0, 0)]


def too_few_walls(
    vertices: List[Float32], a: Int, b: Int, c: Int, d: Int
) -> List[Vector2]:
    """Return one coordinate where four are owed."""
    return [Vector2(0, 0)]


def test_a_generator_owes_a_coordinate_per_corner() raises:
    var cap = UVGenerator(too_few, x_and_z)
    with assert_raises(contains="three"):
        _ = extrude(square(0, 0, 1), meters(0.5), uv_generator=cap)
    var wall = UVGenerator(halving_top, too_few_walls)
    with assert_raises(contains="four"):
        _ = extrude(square(0, 0, 1), meters(0.5), uv_generator=wall)
    with assert_raises(contains="at least one shape"):
        _ = extrude(List[Shape](), meters(0.5))
    with assert_raises(contains="at least one shape"):
        _ = shape_geometry(List[Shape]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
