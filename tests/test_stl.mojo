# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.stl`.

Binary files are built byte by byte here, ASCII files are written inline,
and every way a file can be wrong is given to the parser and refused.
`assets/tetrahedron.stl` is the one file read from disk.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION
from core.object3d import Object3D
from core.scene import Scene
from loaders.stl import (
    StlModel,
    is_binary_stl,
    parse_stl,
    parse_stl_text,
    read_stl,
)
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import srgb_to_linear
from renderers.renderer import Renderer
from std.memory import bitcast
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


def put_u32(mut bytes: List[UInt8], value: Int):
    """Append a little-endian 32-bit word."""
    for shift in range(4):
        bytes.append(UInt8((value >> (shift * 8)) & 0xFF))


def put_f32(mut bytes: List[UInt8], value: Float32):
    """Append a little-endian `Float32`."""
    put_u32(bytes, Int(bitcast[DType.uint32](value)))


def header(text: String) -> List[UInt8]:
    """Return an 80-byte header that starts with `text`, padded with
    spaces."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    while len(bytes) < 80:
        bytes.append(0x20)
    return bytes^


def put_face(
    mut bytes: List[UInt8], normal: Vector3, corners: List[Vector3], packed: Int
):
    """Append one binary face."""
    put_f32(bytes, normal.x)
    put_f32(bytes, normal.y)
    put_f32(bytes, normal.z)
    for corner in corners:
        put_f32(bytes, corner.x)
        put_f32(bytes, corner.y)
        put_f32(bytes, corner.z)
    bytes.append(UInt8(packed & 0xFF))
    bytes.append(UInt8(packed >> 8))


def one_face(text: String, packed: Int = 0) -> List[UInt8]:
    """Return a binary file of one triangle, facing +z, under a header
    that starts with `text`."""
    var bytes = header(text)
    put_u32(bytes, 1)
    put_face(
        bytes,
        Vector3(0, 0, 1),
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)],
        packed,
    )
    return bytes^


def ascii_bytes(text: String) -> List[UInt8]:
    """Return a text as the bytes of a file."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return bytes^


def one_facet() -> String:
    """Return an ASCII file of one triangle."""
    return String(
        "solid thing\n"
        "  facet normal 0 0 1\n"
        "    outer loop\n"
        "      vertex 0 0 0\n"
        "      vertex 1 0 0\n"
        "      vertex 0 1 0\n"
        "    endloop\n"
        "  endfacet\n"
        "endsolid thing\n"
    )


# --- binary ------------------------------------------------------------------


def test_a_binary_face_comes_out_as_three_corners_with_its_normal() raises:
    var model = parse_stl(one_face("binary"))
    ref shape = model.geometry
    assert_false(shape.is_indexed())
    assert_equal(shape.triangle_count(), 1)
    assert_point(shape.corner(0, 0), 0, 0, 0)
    assert_point(shape.corner(0, 1), 1, 0, 0)
    assert_point(shape.corner(0, 2), 0, 1, 0)
    ref normals = shape.attribute_view(String(NORMAL))
    for corner in range(3):
        assert_point(normals.vector3(corner), 0, 0, 1)
    # No `COLOR=` in the header: no colors, whatever the attribute holds.
    assert_false(model.has_colors())
    assert_equal(model.alpha, Float32(1))
    assert_equal(len(model.solids), 1)
    assert_equal(model.solids[0].name, String(""))
    assert_equal(model.solids[0].start, 0)
    assert_equal(model.solids[0].count, 3)
    # three.js's `parseBinary` adds no group.
    assert_equal(len(shape.groups), 0)


def test_a_binary_file_can_have_no_faces() raises:
    var bytes = header("empty")
    put_u32(bytes, 0)
    var model = parse_stl(bytes)
    assert_equal(model.geometry.vertex_count(), 0)
    assert_equal(model.solids[0].count, 0)


def test_a_header_color_is_the_default_and_a_face_can_have_its_own() raises:
    # A header color of (255, 0, 51) at an alpha of 128, then two faces:
    # one with the top bit set, which takes the default, and one with its
    # own color of red 31, green 0, blue 15 out of 31.
    var bytes = header("made by a tool COLOR=")
    bytes[21] = 255
    bytes[22] = 0
    bytes[23] = 51
    bytes[24] = 128
    put_u32(bytes, 2)
    var corners: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    ]
    put_face(bytes, Vector3(0, 0, 1), corners, 0x8000)
    put_face(bytes, Vector3(0, 0, 1), corners, 31 | (15 << 10))
    var model = parse_stl(bytes)
    assert_true(model.has_colors())
    assert_almost_equal(model.alpha, Float32(128) / 255, atol=TOLERANCE)
    ref colors = model.geometry.attribute_view(String(COLOR))
    assert_equal(colors.count(), 6)
    for corner in range(3):
        assert_almost_equal(colors.component(corner, 0), Float32(1))
        assert_almost_equal(colors.component(corner, 1), Float32(0))
        assert_almost_equal(
            colors.component(corner, 2),
            srgb_to_linear(Float32(51) / 255),
            atol=TOLERANCE,
        )
    for corner in range(3, 6):
        assert_almost_equal(colors.component(corner, 0), Float32(1))
        assert_almost_equal(colors.component(corner, 1), Float32(0))
        assert_almost_equal(
            colors.component(corner, 2),
            srgb_to_linear(Float32(15) / 31),
            atol=TOLERANCE,
        )


def test_the_last_color_in_the_header_wins() raises:
    var bytes = one_face("COLOR=abcd COLOR=", packed=0x8000)
    for at in range(17, 21):
        bytes[at] = 255
    var model = parse_stl(bytes)
    assert_equal(model.alpha, Float32(1))
    assert_almost_equal(
        model.geometry.attribute_view(String(COLOR)).component(0, 0),
        Float32(1),
    )


def test_a_file_of_the_exact_binary_length_is_binary_even_if_it_says_solid() raises:
    # Many writers start a binary header with `solid`.
    var bytes = one_face("solid but binary")
    assert_true(is_binary_stl(bytes))
    assert_equal(parse_stl(bytes).geometry.triangle_count(), 1)
    # A binary file with trailing bytes is still read, as three.js reads
    # it, when its header does not say `solid`.
    var padded = one_face("binary")
    padded.append(0)
    assert_true(is_binary_stl(padded))
    assert_equal(parse_stl(padded).geometry.triangle_count(), 1)


def test_text_that_says_solid_near_the_start_is_ascii() raises:
    assert_false(is_binary_stl(ascii_bytes(one_facet())))
    # After a byte order mark.
    var marked: List[UInt8] = [0xEF, 0xBB, 0xBF]
    marked += ascii_bytes(one_facet())
    assert_false(is_binary_stl(marked))
    # Too short to be binary and no `solid`: binary, and refused below.
    assert_true(is_binary_stl(ascii_bytes("sol")))
    assert_true(is_binary_stl(ascii_bytes("xxxxxxxxx")))


def test_a_binary_file_too_short_for_its_header_is_refused() raises:
    var seen = String()
    try:
        _ = parse_stl(ascii_bytes("tiny"))
    except reason:
        seen = String(reason)
    assert_true("84" in seen, seen)


def test_a_binary_file_short_of_its_faces_is_refused() raises:
    var bytes = one_face("binary")
    bytes[80] = 3
    var seen = String()
    try:
        _ = parse_stl(bytes)
    except reason:
        seen = String(reason)
    assert_true("3 faces" in seen, seen)


def test_a_binary_number_must_be_finite() raises:
    var bytes = header("binary")
    put_u32(bytes, 1)
    put_face(
        bytes,
        Vector3(0, 0, 1),
        [Vector3(0, 0, 0), Vector3(Float32.MAX * 2, 0, 0), Vector3(0, 1, 0)],
        0,
    )
    var seen = String()
    try:
        _ = parse_stl(bytes)
    except reason:
        seen = String(reason)
    assert_true("STL face 0" in seen, seen)
    var bad_normal = header("binary")
    put_u32(bad_normal, 1)
    put_face(
        bad_normal,
        Vector3(0, Float32.MAX * 2, 1),
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)],
        0,
    )
    with assert_raises():
        _ = parse_stl(bad_normal)


# --- ASCII -------------------------------------------------------------------


def test_an_ascii_facet_comes_out_as_three_corners_with_its_normal() raises:
    var model = parse_stl(ascii_bytes(one_facet()))
    ref shape = model.geometry
    assert_equal(shape.triangle_count(), 1)
    assert_point(shape.corner(0, 1), 1, 0, 0)
    assert_point(shape.attribute_view(String(NORMAL)).vector3(2), 0, 0, 1)
    assert_false(model.has_colors())
    assert_equal(model.alpha, Float32(1))
    assert_equal(len(model.solids), 1)
    assert_equal(model.solids[0].name, String("thing"))


def test_several_solids_make_one_geometry_and_a_solid_each() raises:
    var text = (
        one_facet()
        + "solid second part\nfacet normal 1 0 0 outer loop vertex 0 0 0"
        " vertex 0 1 0 vertex 0 0 1 endloop endfacet\n"
        "facet normal 1 0 0\nouter loop\nvertex 0 0 0\nvertex 0 1 0\n"
        "vertex 0 0 1\nendloop\nendfacet\nendsolid\n"
        "solid\nendsolid"
    )
    var model = parse_stl_text(text)
    assert_equal(model.geometry.triangle_count(), 3)
    assert_equal(len(model.solids), 3)
    assert_equal(model.solids[0].count, 3)
    assert_equal(model.solids[1].name, String("second part"))
    assert_equal(model.solids[1].start, 3)
    assert_equal(model.solids[1].count, 6)
    assert_equal(model.solids[2].name, String(""))
    assert_equal(model.solids[2].start, 9)
    assert_equal(model.solids[2].count, 0)
    # A group a solid, as three.js's `parseASCII` adds them.
    ref groups = model.geometry.groups
    assert_equal(len(groups), 3)
    assert_equal(groups[1].start, 3)
    assert_equal(groups[1].count, 6)
    assert_equal(groups[2].material_index.value, 2)
    assert_point(
        model.geometry.attribute_view(String(NORMAL)).vector3(4), 1, 0, 0
    )


def test_an_ascii_file_with_windows_line_ends_reads() raises:
    var text = String(
        "solid a\r\nfacet normal 0 0 1\r\nouter loop\r\nvertex 0 0 0\r\n"
        "vertex 1 0 0\r\nvertex 0 1 0\r\nendloop\r\nendfacet\r\nendsolid a\r\n"
    )
    assert_equal(parse_stl_text(text).solids[0].name, String("a"))


def test_ascii_files_out_of_order_are_refused() raises:
    var facet = String(
        "facet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0"
        " vertex 0 1 0 endloop endfacet\n"
    )
    # No solid at all.
    with assert_raises():
        _ = parse_stl_text(String(""))
    # A facet outside a solid, and one inside another.
    with assert_raises():
        _ = parse_stl_text(facet)
    with assert_raises():
        _ = parse_stl_text("solid\nfacet normal 0 0 1\n" + facet + "endsolid")
    # A solid inside a solid, and one never closed.
    with assert_raises():
        _ = parse_stl_text(String("solid a\nsolid b\nendsolid\nendsolid\n"))
    with assert_raises():
        _ = parse_stl_text("solid a\n" + facet)
    # `endsolid` with no solid, and inside a facet.
    with assert_raises():
        _ = parse_stl_text(String("endsolid\n"))
    with assert_raises():
        _ = parse_stl_text(String("solid\nfacet normal 0 0 1\nendsolid\n"))
    # The words of a facet outside one.
    for word in ["outer loop", "endloop", "vertex 0 0 0", "endfacet"]:
        with assert_raises():
            _ = parse_stl_text("solid\n" + word + "\nendsolid\n")


def test_a_facet_needs_a_normal_and_three_vertices() raises:
    with assert_raises():
        _ = parse_stl_text(
            String(
                "solid\nfacet 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\n"
                "vertex 0 1 0\nendloop\nendfacet\nendsolid\n"
            )
        )
    with assert_raises():
        _ = parse_stl_text(
            String(
                "solid\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\n"
                "vertex 1 0 0\nendloop\nendfacet\nendsolid\n"
            )
        )
    var seen = String()
    try:
        _ = parse_stl_text(
            String(
                "solid\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\n"
                "vertex 1 0 0\nvertex 0 1 0\nvertex 1 1 0\nendloop\n"
                "endfacet\nendsolid\n"
            )
        )
    except reason:
        seen = String(reason)
    assert_true("STL line 7" in seen, seen)
    assert_true("more than three" in seen, seen)
    # `outer` must be followed by `loop`.
    with assert_raises():
        _ = parse_stl_text(
            String(
                "solid\nfacet normal 0 0 1\nouter space\nvertex 0 0 0\n"
                "vertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid\n"
            )
        )


def test_an_ascii_number_must_be_a_finite_number() raises:
    var seen = String()
    try:
        _ = parse_stl_text(String("solid\nfacet normal 0 zero 1\n"))
    except reason:
        seen = String(reason)
    assert_true("STL line 2" in seen, seen)
    assert_true("zero" in seen, seen)
    with assert_raises():
        _ = parse_stl_text(String("solid\nfacet normal 0 1e100 1\n"))
    # The file ends where a number should be.
    seen = String()
    try:
        _ = parse_stl_text(String("solid\nfacet normal 0 0"))
    except reason:
        seen = String(reason)
    assert_true("ends" in seen, seen)


def test_a_word_stl_does_not_have_is_refused() raises:
    var seen = String()
    try:
        _ = parse_stl_text(String("solid\ncolor 1 0 0\nendsolid\n"))
    except reason:
        seen = String(reason)
    assert_true("color" in seen, seen)


def test_text_that_is_not_utf8_is_refused() raises:
    var bytes = ascii_bytes("solid ")
    bytes.append(0xFF)
    with assert_raises():
        _ = parse_stl(bytes)


# --- a file on disk ----------------------------------------------------------


def test_the_tetrahedron_file_reads_as_four_colored_faces() raises:
    var model = read_stl("assets/tetrahedron.stl")
    assert_equal(model.geometry.triangle_count(), 4)
    assert_true(model.has_colors())
    ref positions = model.geometry.attribute_view(String(POSITION))
    assert_equal(positions.count(), 12)
    assert_point(model.geometry.corner(0, 0), 0, 0, 0)


def test_a_file_that_is_not_there_is_refused() raises:
    with assert_raises():
        _ = read_stl("assets/no_such_model.stl")


def test_a_read_model_renders() raises:
    var model = read_stl("assets/tetrahedron.stl")
    var assets = Assets()
    var shape = assets.geometries.add(model.take_geometry())
    assert_equal(model.geometry.attribute_count(), 0)
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
    camera.place(Vector3(1.5, 1.2, 3), Vector3(0.3, 0.3, 0.3))
    var renderer = Renderer(24, 18)
    var image = renderer.render(scene, assets, camera)
    var drawn = 0
    for y in range(18):
        for x in range(24):
            if image.get_pixel(x, y).r == 200:
                drawn += 1
    assert_true(drawn > 10, "the tetrahedron did not draw")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
