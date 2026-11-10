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
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from loaders.obj import ObjModel, parse_obj, read_obj
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_scratch import TestScratch, temporary_path
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


def test_a_backslash_at_the_end_of_a_line_continues_it() raises:
    # three.js joins a line that ends in a backslash to the next, as
    # exporters write a long face over several lines. Windows line ends
    # join too, and an error names the line the statement ends on.
    var model = parse_obj(
        String("v 0 0 0\nv 1 0 0\nv 1 1 0\\\r\n\nv 0 1 0\nf 1 2 \\\n3 \\\n4\n")
    )
    ref shape = model.objects[0].geometry
    assert_equal(shape.triangle_count(), 2)
    assert_point(shape.corner(1, 2), 0, 1, 0)
    with assert_raises(contains="OBJ line 4"):
        _ = parse_obj(String("v 0 0 0\nf 1 \\\n9 \\\n9\n"))


def test_a_backslash_on_the_last_line_continues_into_nothing() raises:
    var model = parse_obj(String("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3 \\"))
    assert_equal(model.objects[0].geometry.triangle_count(), 1)


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
    # A material starts a run of the same object, not a new object.
    assert_equal(split.count(), 2)
    assert_equal(split.objects[0].name, String("Cube"))
    assert_equal(split.objects[0].material, String("red"))
    assert_equal(split.objects[0].materials[1], String("blue"))
    assert_equal(split.objects[0].geometry.triangle_count(), 3)
    assert_equal(split.objects[0].geometry.groups[1].count, 6)
    assert_equal(split.objects[1].name, String("Other"))


def test_materials_make_groups_and_carry_into_the_next_object() raises:
    var model = parse_obj(
        String(
            "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
            "o thing\nusemtl red\nf 1 2 3\nusemtl blue\nf 1 2 3\nf 3 2 1\n"
            "o other\nf 1 2 3\n"
        )
    )
    assert_equal(model.count(), 2)
    ref thing = model.objects[0]
    assert_equal(thing.name, String("thing"))
    assert_true(thing.is_multi_material())
    assert_equal(len(thing.materials), 2)
    assert_equal(thing.materials[0], String("red"))
    assert_equal(thing.materials[1], String("blue"))
    # A group a run, as three.js's `addGroup` in `OBJLoader.parse`.
    ref groups = thing.geometry.groups
    assert_equal(len(groups), 2)
    assert_equal(groups[0].start, 0)
    assert_equal(groups[0].count, 3)
    assert_equal(groups[1].start, 3)
    assert_equal(groups[1].count, 6)
    assert_equal(groups[1].material_index.value, 1)
    # The material in force carries into a new object, as three.js's does.
    assert_equal(model.objects[1].name, String("other"))
    assert_equal(model.objects[1].material, String("blue"))
    assert_false(model.objects[1].is_multi_material())
    assert_equal(len(model.objects[1].geometry.groups), 0)
    # A material named before any face just sets it.
    var early = parse_obj(
        String("usemtl gold\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
    )
    assert_equal(early.objects[0].material, String("gold"))


def test_a_run_with_no_faces_is_dropped() raises:
    var points = String("v 0 0 0\nv 1 0 0\nv 0 1 0\n")
    # A material replaced before any face, and one left with no face.
    var model = parse_obj(
        points + "usemtl a\nusemtl b\nf 1 2 3\nusemtl c\nusemtl d\n"
    )
    assert_equal(len(model.objects[0].materials), 1)
    assert_equal(model.objects[0].material, String("b"))
    assert_equal(len(model.objects[0].geometry.groups), 0)
    # A carried material with faces is kept when a new one follows.
    var carried = parse_obj(
        points + "o x\nusemtl a\nf 1 2 3\no y\nf 1 2 3\nusemtl b\nf 1 2 3\n"
    )
    ref y = carried.objects[1]
    assert_equal(len(y.materials), 2)
    assert_equal(y.materials[0], String("a"))
    assert_equal(y.geometry.groups[1].start, 3)
    # A carried material replaced before any face is dropped.
    var replaced = parse_obj(
        points + "o x\nusemtl a\nf 1 2 3\no y\nusemtl b\nf 1 2 3\n"
    )
    assert_equal(len(replaced.objects[1].materials), 1)
    assert_equal(replaced.objects[1].material, String("b"))


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
    # The rest of the line, as three.js's `substring( 7 ).trim()` reads it.
    assert_equal(model.material_libraries[1], String("my  second.mtl"))
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


def test_a_vertex_color_is_read_as_three_js_reads_it() raises:
    # `v x y z r g b` is a position and an sRGB color. An object with a
    # colored vertex gets a linear `color` attribute; a vertex that names
    # no color is white in it.
    var model = parse_obj(
        "o first\nv 0 0 0 1 0 0\nv 1 0 0 0 0.5 0\nv 0 1 0\nf 1 2 3\nv 0 0"
        " 1\nv 1 0"
        " 1\nv 0 1 1\no plain\nf 4 5 6\n"
    )
    var colored = model.objects[0].take_geometry()
    assert_true(colored.has_attribute(String(COLOR)))
    ref colors = colored.attribute_view(String(COLOR))
    assert_equal(colors.data[0], 1)
    assert_equal(colors.data[1], 0)
    assert_almost_equal(colors.data[4], 0.21404, atol=1e-4)
    assert_equal(colors.data[6], 1)
    assert_equal(colors.data[8], 1)
    # The object whose corners name no color has no attribute.
    assert_false(model.objects[1].take_geometry().has_attribute(String(COLOR)))


def test_a_hash_inside_a_word_is_not_a_comment() raises:
    # A comment starts at a `#` that starts the line or follows a space or
    # a tab, so a material named with a `#` keeps its name, as in three.js.
    var model = parse_obj(
        "# a comment\nv 0 0 0\nv 1 0 0\nv 0 1 0 # after the data\nusemtl"
        " Material#1\nf 1 2 3\t# after a tab\nusemtl Material#2\nf 1 2 3\n"
    )
    assert_equal(len(model.objects), 1)
    assert_equal(model.objects[0].materials[0], "Material#1")
    assert_equal(model.objects[0].materials[1], "Material#2")


def test_a_name_is_the_rest_of_its_line() raises:
    # three.js takes the rest of an `o`, `g`, `usemtl` or `mtllib` line,
    # trimmed, as the name: a `#` and two spaces are kept, so the names
    # match the material library's. A face's comment is still cut.
    var model = parse_obj(
        "mtllib my lib.mtl #2\no Brick  Wall #3\nv 0 0 0\nv 1 0 0\nv 0 1 0"
        "\nusemtl Mat #1\nf 1 2 3 # done\n"
    )
    assert_equal(model.material_libraries[0], "my lib.mtl #2")
    assert_equal(model.objects[0].name, "Brick  Wall #3")
    assert_equal(model.objects[0].material, "Mat #1")
    assert_equal(model.objects[0].geometry.triangle_count(), 1)


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


def turns(model: ObjModel, axis: Int) raises -> List[Float64]:
    """Return twice each triangle's area about an axis, with its sign:
    positive when the triangle turns counterclockwise seen from the tip
    of the axis."""
    ref geometry = model.objects[0].geometry
    var first = (axis + 1) % 3
    var second = (axis + 2) % 3
    var out = List[Float64]()
    for triangle in range(geometry.triangle_count()):
        var corners = List[List[Float64]]()
        for corner in range(3):
            var point = geometry.corner(triangle, corner)
            corners.append(
                [Float64(point.x), Float64(point.y), Float64(point.z)]
            )
        out.append(
            (corners[1][first] - corners[0][first])
            * (corners[2][second] - corners[0][second])
            - (corners[1][second] - corners[0][second])
            * (corners[2][first] - corners[0][first])
        )
    return out^


def assert_covers(areas: List[Float64], count: Int, twice: Float64) raises:
    """Assert that `count` triangles all turn the way of `twice`, and that
    their areas add up to it: they cover the face once and nothing else."""
    assert_equal(len(areas), count)
    var total = Float64(0)
    for area in areas:
        assert_true(area * twice > 0, "a triangle turns the other way")
        total += area
    assert_almost_equal(total / twice, 1, atol=1e-5)


def test_a_face_that_earcut_cannot_cut_is_a_fan() raises:
    # This face goes through two of its corners twice. It has an area, so
    # it is not refused, and it has no ear, so earcut gives no triangles.
    # A cut of nothing would lose the face. three.js cuts every face into
    # a fan from its first corner, and so is this one cut.
    var touching = parse_obj(
        String("v 3 1 0\nv 0 0 0\nv 1 1 0\nv 1 0 0\nf 1 2 3 1 2 4\n")
    )
    ref geometry = touching.objects[0].geometry
    assert_equal(geometry.triangle_count(), 4)
    ref positions = geometry.attribute_view(String(POSITION))
    # The corners of the fan: 0 1 2, 0 2 3, 0 3 4, 0 4 5.
    var corners: List[Int] = [0, 1, 2, 0, 2, 0, 0, 0, 1, 0, 1, 3]
    var xs: List[Float32] = [3, 0, 1, 1]
    var ys: List[Float32] = [1, 0, 1, 0]
    assert_equal(positions.count(), 12)
    for vertex in range(12):
        assert_equal(positions.component(vertex, 0), xs[corners[vertex]])
        assert_equal(positions.component(vertex, 1), ys[corners[vertex]])


def test_a_polygon_that_is_not_convex_is_cut_where_it_is() raises:
    # three.js r180's `OBJLoader` cuts every face into a fan from its
    # first corner. A fan of this U shape covers the cutout between its
    # arms: the fan draws an area of 9, and the face has 7. The face is
    # cut by earcut instead. Each triangle turns the way the face turns,
    # and their areas add up to the face's.
    var u_shape = String(
        "v 0 0 0\nv 3 0 0\nv 3 3 0\nv 2 3 0\n"
        "v 2 1 0\nv 1 1 0\nv 1 3 0\nv 0 3 0\n"
    )
    assert_covers(turns(parse_obj(u_shape + "f 1 2 3 4 5 6 7 8\n"), 2), 6, 14)
    # The same face wound the other way faces the other way.
    assert_covers(turns(parse_obj(u_shape + "f 8 7 6 5 4 3 2 1\n"), 2), 6, -14)
    # An arrowhead: its second corner turns the other way. The fan's first
    # triangle is outside the face. The cut is on the other diagonal.
    var arrow = parse_obj(
        String("v 0 0 0\nv 2 1 0\nv 4 0 0\nv 2 3 0\nf 1 2 3 4\n")
    )
    assert_covers(turns(arrow, 2), 2, 8)
    # The same arrowhead on the other two coordinate planes, each way.
    var planes: List[String] = [
        "v 0 0 0\nv 0 2 1\nv 0 4 0\nv 0 2 3\n",
        "v 0 0 0\nv 1 0 2\nv 0 0 4\nv 3 0 2\n",
    ]
    for axis in range(2):
        assert_covers(
            turns(parse_obj(planes[axis] + "f 1 2 3 4\n"), axis), 2, 8
        )
        assert_covers(
            turns(parse_obj(planes[axis] + "f 4 3 2 1\n"), axis), 2, -8
        )
    # Each corner of a cut face keeps its own texture coordinate and
    # normal: here a quarter of its x and a third of its y.
    var textured = parse_obj(
        String(
            "v 0 0 0\nv 2 1 0\nv 4 0 0\nv 2 3 0\n"
            "vt 0 0\nvt 0.5 0.333333343\nvt 1 0\nvt 0.5 1\nvn 0 0 1\n"
            "f 1/1/1 2/2/1 3/3/1 4/4/1\n"
        )
    )
    ref geometry = textured.objects[0].geometry
    assert_equal(geometry.triangle_count(), 2)
    ref positions = geometry.attribute_view(String(POSITION))
    ref uvs = geometry.attribute_view(String(UV))
    for vertex in range(positions.count()):
        assert_almost_equal(
            uvs.component(vertex, 0),
            positions.component(vertex, 0) / 4,
            atol=TOLERANCE,
        )
        assert_almost_equal(
            uvs.component(vertex, 1),
            positions.component(vertex, 1) / 3,
            atol=TOLERANCE,
        )


def test_a_polygon_with_no_area_is_refused() raises:
    # Corners on one line: no area at all.
    with assert_raises():
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nv 2 0 0\nv 3 0 0\nf 1 2 3 4\n"))
    # The refusal names the line.
    var seen = String()
    try:
        _ = parse_obj(String("v 0 0 0\nv 1 0 0\nv 2 0 0\nv 3 0 0\nf 1 2 3 4\n"))
    except reason:
        seen = String(reason)
    assert_true("OBJ line 5" in seen, seen)
    assert_true("no area" in seen, seen)


def test_a_convex_polygon_is_cut_into_a_fan() raises:
    # A convex pentagon cuts into three triangles, whichever way it is
    # wound, and a triangle is never asked.
    var pentagon = parse_obj(
        String("v 0 0 0\nv 2 0 0\nv 3 1 0\nv 1 2 0\nv -1 1 0\nf 1 2 3 4 5\n")
    )
    assert_equal(pentagon.objects[0].geometry.triangle_count(), 3)
    # Each triangle starts at the face's first corner, as three.js's does.
    for triangle in range(3):
        assert_point(pentagon.objects[0].geometry.corner(triangle, 0), 0, 0, 0)
    assert_point(pentagon.objects[0].geometry.corner(1, 1), 3, 1, 0)
    assert_point(pentagon.objects[0].geometry.corner(1, 2), 1, 2, 0)
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


def scaled_polygon(scale: Float64, concave: Bool, reversed: Bool) -> String:
    """Build the same finite polygon at several physical scales."""
    var text = String()
    var corners: List[SIMD[DType.float64, 2]] = [
        SIMD[DType.float64, 2](0, 0),
        SIMD[DType.float64, 2](2, 0),
        SIMD[DType.float64, 2](
            Float64(0.5) if concave else Float64(2),
            Float64(0.5) if concave else Float64(1),
        ),
        SIMD[DType.float64, 2](0, 1),
    ]
    for corner in corners:
        text += (
            "v "
            + String(corner[0] * scale)
            + " "
            + String(corner[1] * scale)
            + " 0\n"
        )
    text += "f 4 3 2 1\n" if reversed else "f 1 2 3 4\n"
    return text^


def test_polygon_convexity_is_independent_of_finite_scale() raises:
    for scale in [
        Float64(1e-30),
        Float64(1e-15),
        Float64(1),
        Float64(1e20),
        Float64(1e37),
    ]:
        for reversed in [False, True]:
            var convex = parse_obj(scaled_polygon(scale, False, reversed))
            assert_equal(convex.objects[0].geometry.triangle_count(), 2)
            # The concave face has an area of three quarters at a scale
            # of one. It is cut the same way at every scale.
            var twice = 1.5 * scale * scale
            assert_covers(
                turns(parse_obj(scaled_polygon(scale, True, reversed)), 2),
                2,
                -twice if reversed else twice,
            )
    var translated = parse_obj(
        "v 100000 100000 0\nv 100001 100000 0\n"
        "v 100001 100001 0\nv 100000 100001 0\nf 1 2 3 4\n"
    )
    assert_equal(translated.objects[0].geometry.triangle_count(), 2)


def t_junction(x: String, y: String) -> String:
    """Return a pentagon whose second corner is at `x y`, between the first
    and the third, near x = 5000."""
    return (
        "v 5000.1 0.1 0\nv "
        + x
        + " "
        + y
        + " 0\nv 5000.7 0.5 0\nv 5000.7 1.5 0\nv 5000.1 1.1 0\nf 1 2 3 4 5\n"
    )


def test_a_corner_straight_in_the_file_is_not_refused_far_away() raises:
    # The second corner is on the line from the first to the third in the
    # file, but `Float32` rounding near 5000 moves it off. three.js draws
    # the fan, and so must this.
    var straight = parse_obj(t_junction("5000.4", "0.3"))
    assert_equal(straight.objects[0].geometry.triangle_count(), 3)
    # A notch of a centimeter is more than rounding. The face is not
    # convex, and it is cut so that no triangle turns the other way, as
    # the first triangle of a fan would.
    var notched = turns(parse_obj(t_junction("5000.4", "0.31")), 2)
    assert_equal(len(notched), 3)
    for area in notched:
        assert_true(area > 0)


def test_a_file_that_is_not_utf8_reads_as_replacement_characters() raises:
    # A comment and a name in Windows-1252. three.js's `FileLoader` reads
    # each byte that is not UTF-8 as U+FFFD and keeps going.
    var bytes = List[UInt8]("# Export".as_bytes())
    bytes.append(0xE9)
    bytes += List[UInt8]("\no Pi".as_bytes())
    bytes.append(0xE8)
    bytes += List[UInt8]("ce\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".as_bytes())
    var path = temporary_path("latin.obj")
    Path(path).write_bytes(bytes)
    var model = read_obj(path)
    assert_equal(model.count(), 1)
    assert_equal(model.objects[0].name, "Pi" + chr(0xFFFD) + "ce")
    assert_equal(model.objects[0].geometry.triangle_count(), 1)


def test_a_leading_byte_order_mark_is_dropped() raises:
    # three.js's `TextDecoder` and `trimStart` drop a U+FEFF at the start.
    # So the first vertex is read, and the face names three vertices.
    var model = parse_obj(chr(0xFEFF) + "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
    assert_equal(model.count(), 1)
    assert_equal(model.objects[0].geometry.triangle_count(), 1)
    var path = temporary_path("marked.obj")
    Path(path).write_text(chr(0xFEFF) + "mtllib a.mtl\n")
    assert_equal(read_obj(path).material_libraries[0], "a.mtl")


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
