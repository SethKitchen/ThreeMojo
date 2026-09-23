# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.obj`.

Every geometry is checked corner by corner against the file it came from,
and every way a file can be wrong is given to the parser and refused.
`assets/cube.obj` is the one file read from disk.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION, UV
from core.object3d import NodeId, Object3D
from core.scene import Scene
from loaders.obj import ObjModel, parse_obj, read_obj
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-6)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def one_triangle() -> String:
    """Return a file with one triangle, each corner with a texture
    coordinate and a normal."""
    return String(
        "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
        "vt 0 0\nvt 1 0\nvt 0 1\n"
        "vn 0 0 1\n"
        "f 1/1/1 2/2/1 3/3/1\n"
    )


# --- what is read ------------------------------------------------------------


def test_a_triangle_with_everything_comes_out_corner_by_corner() raises:
    var model = parse_obj(one_triangle())
    assert_equal(model.count(), 1)
    ref shape = model.objects[0].geometry
    assert_equal(shape.vertex_count(), 3)
    assert_equal(shape.triangle_count(), 1)
    assert_false(shape.is_indexed())
    assert_point(shape.corner(0, 0), 0, 0, 0)
    assert_point(shape.corner(0, 1), 1, 0, 0)
    assert_point(shape.corner(0, 2), 0, 1, 0)
    ref uvs = shape.attribute_view(String(UV))
    assert_equal(uvs.item_size, 2)
    assert_almost_equal(uvs.component(1, 0), Float32(1), atol=TOLERANCE)
    assert_almost_equal(uvs.component(2, 1), Float32(1), atol=TOLERANCE)
    ref normals = shape.attribute_view(String(NORMAL))
    assert_point(normals.vector3(2), 0, 0, 1)
    # Faces before any `o` belong to an object with no name and, before
    # any `usemtl`, no material.
    assert_equal(model.objects[0].name, String(""))
    assert_equal(model.objects[0].material, String(""))


def test_a_face_can_name_only_positions_or_positions_and_normals() raises:
    var bare = parse_obj(String("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"))
    ref plain = bare.objects[0].geometry
    assert_equal(plain.triangle_count(), 1)
    assert_false(plain.has_attribute(String(UV)))
    assert_false(plain.has_attribute(String(NORMAL)))
    var lit = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 0 1 0\nvn 0 0 1\nf 1//1 2//1 3//1\n")
    )
    ref shaded = lit.objects[0].geometry
    assert_false(shaded.has_attribute(String(UV)))
    assert_true(shaded.has_attribute(String(NORMAL)))
    assert_point(shaded.attribute_view(String(NORMAL)).vector3(0), 0, 0, 1)
    var mapped = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0.5 0.5\nf 1/1 2/1 3/1\n")
    )
    ref skinned = mapped.objects[0].geometry
    assert_true(skinned.has_attribute(String(UV)))
    assert_false(skinned.has_attribute(String(NORMAL)))


def test_a_negative_index_counts_back_from_the_last_entry() raises:
    var model = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 9 9 9\nf -4 -3 -2\n")
    )
    ref shape = model.objects[0].geometry
    assert_point(shape.corner(0, 0), 0, 0, 0)
    assert_point(shape.corner(0, 2), 0, 1, 0)


def test_a_polygon_is_cut_into_a_fan() raises:
    # A square: two triangles sharing the first corner.
    var model = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n")
    )
    ref shape = model.objects[0].geometry
    assert_equal(shape.triangle_count(), 2)
    assert_point(shape.corner(0, 0), 0, 0, 0)
    assert_point(shape.corner(0, 2), 1, 1, 0)
    assert_point(shape.corner(1, 0), 0, 0, 0)
    assert_point(shape.corner(1, 1), 1, 1, 0)
    assert_point(shape.corner(1, 2), 0, 1, 0)


def test_objects_and_groups_split_the_file_and_keep_their_names() raises:
    var model = parse_obj(
        String(
            "o first one\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
            "g second\nv 2 0 0\nf 1 2 4\nf 4 2 1\n"
            "o empty\n"
        )
    )
    # The empty object at the end is dropped, as three.js drops it.
    assert_equal(model.count(), 2)
    assert_equal(model.objects[0].name, String("first one"))
    assert_equal(model.objects[0].geometry.triangle_count(), 1)
    assert_equal(model.objects[1].name, String("second"))
    assert_equal(model.objects[1].geometry.triangle_count(), 2)
    assert_point(model.objects[1].geometry.corner(0, 2), 2, 0, 0)
    # An object declared with no name at all has an empty one.
    var unnamed = parse_obj(String("o\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"))
    assert_equal(unnamed.objects[0].name, String(""))
    # A declaration with no faces before the next is dropped, as three.js
    # drops an empty object, and the faces after belong to the next.
    var renamed = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 0 1 0\no first\no second\nf 1 2 3\n")
    )
    assert_equal(renamed.count(), 1)
    assert_equal(renamed.objects[0].name, String("second"))


def test_faces_before_the_first_declaration_belong_to_it() raises:
    # three.js renames the object it began with at the first `o` or `g`
    # rather than starting another, so faces listed before the line are
    # the named object's. A material change before the line has already
    # split those faces into parts; every one of them takes the name too.
    var model = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\no Cube\nf 3 2 1\n")
    )
    assert_equal(model.count(), 1)
    assert_equal(model.objects[0].name, String("Cube"))
    assert_equal(model.objects[0].geometry.triangle_count(), 2)
    var split = parse_obj(
        String(
            "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
            "usemtl red\nf 1 2 3\nusemtl blue\nf 3 2 1\n"
            "g Cube\nf 1 2 3\ng Other\nf 1 2 3\n"
        )
    )
    assert_equal(split.count(), 3)
    assert_equal(split.objects[0].name, String("Cube"))
    assert_equal(split.objects[0].material, String("red"))
    assert_equal(split.objects[1].name, String("Cube"))
    assert_equal(split.objects[1].material, String("blue"))
    assert_equal(split.objects[1].geometry.triangle_count(), 2)
    assert_equal(split.objects[2].name, String("Other"))


def test_a_material_splits_an_object_and_carries_into_the_next() raises:
    var model = parse_obj(
        String(
            "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
            "o thing\nusemtl red\nf 1 2 3\nusemtl blue\nf 1 2 3\nf 3 2 1\n"
            "o other\nf 1 2 3\n"
        )
    )
    assert_equal(model.count(), 3)
    assert_equal(model.objects[0].name, String("thing"))
    assert_equal(model.objects[0].material, String("red"))
    assert_equal(model.objects[0].geometry.triangle_count(), 1)
    assert_equal(model.objects[1].name, String("thing"))
    assert_equal(model.objects[1].material, String("blue"))
    assert_equal(model.objects[1].geometry.triangle_count(), 2)
    # The material in force carries into a new object, as three.js's does.
    assert_equal(model.objects[2].name, String("other"))
    assert_equal(model.objects[2].material, String("blue"))
    # A material named before any face just sets it.
    var early = parse_obj(
        String("usemtl gold\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
    )
    assert_equal(early.objects[0].material, String("gold"))


def test_comments_blank_lines_and_unknown_keywords_are_skipped() raises:
    var model = parse_obj(
        String(
            "# a comment\n\n   \nmtllib things.mtl\ns off\n"
            "v 0 0 0 1\nv 1 0 0\nv 0 1 0\r\n"
            "l 1 2\np 3\n"
            "f 1 2 3  # a comment after the data is dropped too\n"
        )
    )
    assert_equal(model.count(), 1)
    assert_equal(model.objects[0].geometry.triangle_count(), 1)


def test_material_libraries_are_kept_in_file_order() raises:
    var model = parse_obj(String("mtllib first.mtl\nmtllib my  second.mtl\n"))
    assert_equal(len(model.material_libraries), 2)
    assert_equal(model.material_libraries[0], String("first.mtl"))
    assert_equal(model.material_libraries[1], String("my second.mtl"))
    assert_equal(len(read_obj("assets/cube.obj").material_libraries), 1)
    with assert_raises(contains="OBJ line 2: mtllib names no file"):
        _ = parse_obj(String("v 0 0 0\nmtllib\n"))


def test_a_file_with_no_faces_has_no_objects() raises:
    assert_equal(parse_obj(String("v 0 0 0\nv 1 0 0\n")).count(), 0)
    assert_equal(parse_obj(String("")).count(), 0)
    assert_equal(ObjModel().count(), 0)


# --- what is refused ---------------------------------------------------------


def test_too_few_coordinates_are_refused() raises:
    with assert_raises():
        _ = parse_obj(String("v 1 2\n"))
    with assert_raises():
        _ = parse_obj(String("vt 1\n"))
    with assert_raises():
        _ = parse_obj(String("vn 1 2\n"))


def test_a_coordinate_that_is_not_a_number_is_refused() raises:
    with assert_raises():
        _ = parse_obj(String("v 1 two 3\n"))


def test_a_face_with_too_few_corners_is_refused() raises:
    with assert_raises():
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nf 1 2\n"))


def test_a_corner_with_too_many_parts_is_refused() raises:
    with assert_raises():
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/1/1/1 2 3\n"))


def test_an_index_that_names_nothing_is_refused() raises:
    var three = String("v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0 0\nvn 0 0 1\n")
    # Zero is not an index.
    with assert_raises():
        _ = parse_obj(three + "f 0 1 2\n")
    # Past the end, forward and back.
    with assert_raises():
        _ = parse_obj(three + "f 1 2 4\n")
    with assert_raises():
        _ = parse_obj(three + "f 1 2 -4\n")
    # Not a whole number at all.
    with assert_raises():
        _ = parse_obj(three + "f a b c\n")
    # A texture coordinate or a normal the file does not have.
    with assert_raises():
        _ = parse_obj(three + "f 1/2 2/1 3/1\n")
    with assert_raises():
        _ = parse_obj(three + "f 1//1 2//1 3//2\n")


def test_faces_of_one_object_must_agree_about_normals_and_uvs() raises:
    var three = String("v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0 0\nvn 0 0 1\n")
    with assert_raises():
        _ = parse_obj(three + "f 1//1 2//1 3//1\nf 1 2 3\n")
    with assert_raises():
        _ = parse_obj(three + "f 1 2 3\nf 1/1 2/1 3/1\n")
    # A new object may differ. Both are declared: faces before the first
    # `o` belong to it, as three.js has it, so one declaration would make
    # the two faces one object that disagrees with itself.
    var split = parse_obj(
        three + "o first\nf 1//1 2//1 3//1\no next\nf 1 2 3\n"
    )
    assert_equal(split.count(), 2)
    with assert_raises():
        _ = parse_obj(three + "f 1//1 2//1 3//1\no next\nf 1 2 3\n")


def test_a_refusal_names_its_line_and_the_offending_text() raises:
    var seen = String()
    try:
        _ = parse_obj(String("v 0 0 0\nv 1 not_a_number 0\n"))
    except reason:
        seen = String(reason)
    assert_true("OBJ line 2" in seen, seen)
    assert_true("not_a_number" in seen, seen)
    seen = String()
    try:
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 two 3\n"))
    except reason:
        seen = String(reason)
    assert_true("OBJ line 4" in seen, seen)
    assert_true("two" in seen, seen)
    seen = String()
    try:
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nv 0 1 0\n\nf 1 2 9\n"))
    except reason:
        seen = String(reason)
    assert_true("OBJ line 5" in seen, seen)


def test_a_coordinate_must_be_finite_as_a_float32() raises:
    # Finite as a Float64, infinite once narrowed.
    with assert_raises():
        _ = parse_obj(String("v 1e100 0 0\n"))
    with assert_raises():
        _ = parse_obj(String("v inf 0 0\n"))
    with assert_raises():
        _ = parse_obj(String("v 0 nan 0\n"))
    with assert_raises():
        _ = parse_obj(
            String("v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 1e39 0\nf 1/1 2/1 3/1\n")
        )
    # Large but within reach is kept.
    var model = parse_obj(String("v 1e30 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"))
    assert_true(model.objects[0].geometry.corner(0, 0).x > 9e29)


def test_a_polygon_must_be_convex_and_have_area() raises:
    # A U shape: a fan from its first corner covers the cutout.
    with assert_raises():
        _ = parse_obj(
            String(
                "v 0 0 0\nv 3 0 0\nv 3 3 0\nv 2 3 0\n"
                "v 2 1 0\nv 1 1 0\nv 1 3 0\nv 0 3 0\n"
                "f 1 2 3 4 5 6 7 8\n"
            )
        )
    # An arrowhead: one corner turns the other way.
    with assert_raises():
        _ = parse_obj(String("v 0 0 0\nv 2 1 0\nv 4 0 0\nv 2 3 0\nf 1 2 3 4\n"))
    # Corners on one line: no area at all.
    with assert_raises():
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nv 2 0 0\nv 3 0 0\nf 1 2 3 4\n"))
    # The refusal names the line.
    var seen = String()
    try:
        _ = parse_obj(String("v 0 0 0\nv 2 1 0\nv 4 0 0\nv 2 3 0\nf 1 2 3 4\n"))
    except reason:
        seen = String(reason)
    assert_true("OBJ line 5" in seen, seen)
    assert_true("convex" in seen, seen)
    # A convex pentagon cuts into three triangles, whichever way it is
    # wound, and a triangle is never asked.
    var pentagon = parse_obj(
        String("v 0 0 0\nv 2 0 0\nv 3 1 0\nv 1 2 0\nv -1 1 0\nf 1 2 3 4 5\n")
    )
    assert_equal(pentagon.objects[0].geometry.triangle_count(), 3)
    var clockwise = parse_obj(
        String("v 0 0 0\nv 2 0 0\nv 3 1 0\nv 1 2 0\nv -1 1 0\nf 5 4 3 2 1\n")
    )
    assert_equal(clockwise.objects[0].geometry.triangle_count(), 3)
    var sliver = parse_obj(String("v 0 0 0\nv 1 0 0\nv 2 0 0\nf 1 2 3\n"))
    assert_equal(sliver.objects[0].geometry.triangle_count(), 1)


# --- a file on disk ----------------------------------------------------------


def test_the_cube_file_reads_as_twelve_triangles_with_normals_and_uvs() raises:
    var model = read_obj("assets/cube.obj")
    assert_equal(model.count(), 1)
    assert_equal(model.objects[0].name, String("Cube"))
    assert_equal(model.objects[0].material, String("Brick"))
    ref shape = model.objects[0].geometry
    assert_equal(shape.triangle_count(), 12)
    assert_equal(shape.vertex_count(), 36)
    assert_point(shape.corner(0, 0), -0.5, -0.5, 0.5)
    assert_point(shape.attribute_view(String(NORMAL)).vector3(0), 0, 0, 1)
    ref uvs = shape.attribute_view(String(UV))
    assert_almost_equal(uvs.component(2, 0), Float32(1), atol=TOLERANCE)
    assert_almost_equal(uvs.component(2, 1), Float32(1), atol=TOLERANCE)
    # Every position is a corner of the unit cube.
    ref positions = shape.attribute_view(String(POSITION))
    for vertex in range(positions.count()):
        var point = positions.vector3(vertex)
        assert_almost_equal(abs(point.x), Float32(0.5), atol=TOLERANCE)
        assert_almost_equal(abs(point.y), Float32(0.5), atol=TOLERANCE)
        assert_almost_equal(abs(point.z), Float32(0.5), atol=TOLERANCE)


def test_a_file_that_is_not_there_is_refused() raises:
    with assert_raises():
        _ = read_obj("assets/no_such_model.obj")


def test_a_read_model_renders() raises:
    var model = read_obj("assets/cube.obj")
    var assets = Assets()
    var first = model.objects.pop()
    var shape = assets.geometries.add(first.take_geometry())
    assert_equal(first.geometry.attribute_count(), 0)
    var paint = assets.materials.add(Material(Color(200, 120, 40), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(shape, paint, node))
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(24) / Float32(18),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(1.5, 1.2, 3), Vector3(0, 0, 0))
    var renderer = Renderer(24, 18)
    var image = renderer.render(scene, assets, camera)
    var drawn = 0
    for y in range(18):
        for x in range(24):
            if image.get_pixel(x, y).r == 200:
                drawn += 1
    assert_true(drawn > 20, "the cube did not draw")
    assert_true(drawn < 24 * 18, "the cube filled the image")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
