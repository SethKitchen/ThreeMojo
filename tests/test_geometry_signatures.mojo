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
    Reference().check("shapes_flat", shape_geometry(two_shapes(), 4))


def test_a_list_of_shapes_is_three_js_extrusion() raises:
    # Each shape adds its caps and its walls, material 0 and material 1.
    Reference().check(
        "shapes_extruded", extrude(two_shapes(), meters(0.5), steps=2)
    )


def holed() raises -> Shape:
    """Return the square with two holes three_geometries.mjs makes: one
    drawn counter-clockwise, one clockwise with a curve in it."""
    var shape = square(0, 0, 4)
    var first = Outline(Vector2(0.5, 0.5))
    first.line_to(Vector2(1.5, 0.5))
    first.line_to(Vector2(1.5, 1.5))
    first.line_to(Vector2(0.5, 1.5))
    first.line_to(Vector2(0.5, 0.5))
    shape.add_hole(first^)
    var second = Outline(Vector2(2.5, 2.5))
    second.line_to(Vector2(2.5, 3.5))
    second.quadratic_to(Vector2(3.6, 3.4), Vector2(3.4, 2.5))
    second.line_to(Vector2(2.5, 2.5))
    shape.add_hole(second^)
    return shape^


def clockwise() raises -> Shape:
    """Return the outline drawn clockwise, with a hole drawn clockwise
    too, that three_geometries.mjs makes."""
    var outline = Outline(Vector2(0, 0))
    outline.line_to(Vector2(0, 3))
    outline.line_to(Vector2(1, 4))
    outline.line_to(Vector2(3, 3))
    outline.line_to(Vector2(3, 0))
    outline.line_to(Vector2(0, 0))
    var shape = Shape(outline^)
    var hole = Outline(Vector2(1, 1))
    hole.line_to(Vector2(1, 2))
    hole.line_to(Vector2(2, 2))
    hole.line_to(Vector2(2, 1))
    hole.line_to(Vector2(1, 1))
    shape.add_hole(hole^)
    return shape^


def test_a_shape_with_holes_is_three_js_shape_geometry() raises:
    # The outline turned clockwise and both holes counter-clockwise, the
    # closing points dropped, and earcut's triangles in earcut's order.
    Reference().check("shape_holes", shape_geometry(holed(), 3))
    Reference().check("shape_clockwise", shape_geometry(clockwise(), 3))


def test_a_bevelled_extrusion_with_holes_is_three_js() raises:
    # The caps are cut from the contours moved out by the offset, and the
    # walls run from each contour's last point back.
    Reference().check(
        "extruded_holes",
        extrude(
            holed(),
            meters(1),
            steps=2,
            curve_segments=3,
            bevel_enabled=True,
            bevel_thickness=meters(0.3),
            bevel_size=meters(0.2),
            bevel_offset=meters(0.05),
            bevel_segments=2,
        ),
    )


def test_an_extrusion_keeps_a_clockwise_outline_and_its_holes() raises:
    # three.js turns the holes only when it turns the outline.
    Reference().check("extruded_clockwise", extrude(clockwise(), meters(0.5)))


def midpoints() raises -> Shape:
    """Return the outline with points midway along its edges and a spike
    that three_geometries.mjs makes."""
    var outline = Outline(Vector2(0, 0))
    for point in [
        Vector2(2, 0),
        Vector2(4, 0),
        Vector2(4, 2),
        Vector2(6, 2),
        Vector2(4, 2),
        Vector2(4, 4),
        Vector2(2, 4),
        Vector2(0, 4),
        Vector2(0, 2),
        Vector2(0, 0),
    ]:
        outline.line_to(point)
    return Shape(outline^)


def test_a_bevel_moves_points_in_a_line_as_three_js_does() raises:
    # Points on a straight run move square to it; the spike's point moves
    # straight on along it.
    Reference().check(
        "extruded_midpoints",
        extrude(
            midpoints(),
            meters(1),
            bevel_enabled=True,
            bevel_thickness=meters(0.2),
            bevel_size=meters(0.1),
            bevel_segments=1,
        ),
    )


def halving_top(
    vertices: List[Float64], a: Int, b: Int, c: Int
) -> List[Vector2]:
    """Return a cap's coordinates as its x and y, halved."""
    var out = List[Vector2]()
    for at in [a, b, c]:
        out.append(
            Vector2(
                Float32(vertices[at * 3] / 2), Float32(vertices[at * 3 + 1] / 2)
            )
        )
    return out^


def x_and_z(
    vertices: List[Float64], a: Int, b: Int, c: Int, d: Int
) -> List[Vector2]:
    """Return a wall's coordinates as each corner's x and z."""
    var out = List[Vector2]()
    for at in [a, b, c, d]:
        out.append(
            Vector2(Float32(vertices[at * 3]), Float32(vertices[at * 3 + 2]))
        )
    return out^


def test_an_extrusion_takes_a_uv_generator_of_its_own() raises:
    # three.js's `UVGenerator` option, asked as three.js asks it.
    Reference().check(
        "extruded_uv_generator",
        extrude(
            square(0, 0, 1),
            meters(0.5),
            uv_generator=UVGenerator(halving_top, x_and_z),
        ),
    )


def too_few(vertices: List[Float64], a: Int, b: Int, c: Int) -> List[Vector2]:
    """Return one coordinate where three are owed."""
    return [Vector2(0, 0)]


def too_few_walls(
    vertices: List[Float64], a: Int, b: Int, c: Int, d: Int
) -> List[Vector2]:
    """Return one coordinate where four are owed."""
    return [Vector2(0, 0)]


def test_the_default_generator_is_three_js_world_generator() raises:
    # Built at run time, and not as a default argument.
    var world = UVGenerator()
    Reference().check(
        "shapes_extruded",
        extrude(two_shapes(), meters(0.5), steps=2, uv_generator=world^),
    )


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
