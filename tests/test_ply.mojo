# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.ply`.

ASCII files are written inline and binary files are built byte by byte,
in both byte orders and with every scalar type. Every way a file can be
wrong is given to the parser and refused. `assets/cube.ply` is the one
file read from disk.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from loaders.ply import (
    PLY_ASCII,
    PLY_BINARY_BIG_ENDIAN,
    PLY_BINARY_LITTLE_ENDIAN,
    PLY_FLOAT32,
    PLY_FLOAT64,
    PLY_INT16,
    PLY_INT32,
    PLY_INT8,
    PLY_UINT16,
    PLY_UINT32,
    PLY_UINT8,
    PlyFormat,
    PlyScalar,
    decode_ply_scalar,
    parse_ply,
    ply_format,
    ply_scalar,
    read_ply,
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


def text_bytes(text: String) -> List[UInt8]:
    """Return a text as the bytes of a file."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return bytes^


def put(mut bytes: List[UInt8], value: UInt64, size: Int, big: Bool):
    """Append the low `size` bytes of a value in either byte order."""
    for index in range(size):
        var shift = (size - 1 - index) * 8 if big else index * 8
        bytes.append(UInt8((value >> UInt64(shift)) & 0xFF))


def put_int(mut bytes: List[UInt8], value: Int, size: Int, big: Bool):
    """Append an integer, negative ones as two's complement."""
    put(
        bytes,
        UInt64(value) if value >= 0 else UInt64(value + (1 << (size * 8))),
        size,
        big,
    )


def put_f32(mut bytes: List[UInt8], value: Float32, big: Bool):
    """Append a `Float32`."""
    put(bytes, UInt64(bitcast[DType.uint32](value)), 4, big)


def put_f64(mut bytes: List[UInt8], value: Float64, big: Bool):
    """Append a `Float64`."""
    put(bytes, bitcast[DType.uint64](value), 8, big)


def triangle(body: String, vertex_extra: String = "") -> String:
    """Return an ASCII file of three vertices with x, y, z and the given
    extra properties, then `body`."""
    return (
        "ply\nformat ascii 1.0\nelement vertex 3\n"
        "property float x\nproperty float y\nproperty float z\n"
        + vertex_extra
        + "element face 1\nproperty list uchar int vertex_indices\nend_header\n"
        + body
    )


def parse_text(text: String) raises -> Int:
    """Parse an ASCII file and return its triangle count."""
    return parse_ply(text_bytes(text)).triangle_count()


def refusal(text: String) -> String:
    """Return why an ASCII file is refused, or an empty string."""
    try:
        _ = parse_ply(text_bytes(text))
    except reason:
        return String(reason)
    return String()


# --- the types ---------------------------------------------------------------


def test_every_scalar_name_is_known_and_has_its_size() raises:
    var names: List[String] = [
        "char",
        "uchar",
        "short",
        "ushort",
        "int",
        "uint",
        "float",
        "double",
    ]
    var sizes: List[Int] = [1, 1, 2, 2, 4, 4, 4, 8]
    var others: List[String] = [
        "int8",
        "uint8",
        "int16",
        "uint16",
        "int32",
        "uint32",
        "float32",
        "float64",
    ]
    for index in range(8):
        var scalar = ply_scalar(names[index])
        assert_equal(scalar, PlyScalar(index))
        assert_equal(ply_scalar(others[index]), scalar)
        assert_true(scalar.is_valid())
        assert_equal(scalar.size(), sizes[index])
        assert_equal(scalar.is_integer(), index < 6)
        assert_equal(scalar.is_signed(), index < 6 and index % 2 == 0)
    with assert_raises():
        _ = ply_scalar("long")


def test_a_scalar_that_is_not_one_of_the_eight_is_refused() raises:
    assert_false(PlyScalar(8).is_valid())
    assert_false(PlyScalar(-1).is_valid())
    assert_false(PlyScalar(-1).is_integer())
    assert_false(PlyScalar(8).is_signed())
    with assert_raises():
        _ = PlyScalar(8).size()
    with assert_raises():
        _ = decode_ply_scalar(
            List[UInt8](length=8, fill=0),
            0,
            PlyScalar(9),
            PLY_BINARY_LITTLE_ENDIAN,
        )


def test_every_format_name_is_known() raises:
    assert_equal(ply_format("ascii"), PLY_ASCII)
    assert_equal(ply_format("binary_little_endian"), PLY_BINARY_LITTLE_ENDIAN)
    assert_equal(ply_format("binary_big_endian"), PLY_BINARY_BIG_ENDIAN)
    assert_true(PLY_ASCII.is_valid())
    assert_true(PLY_BINARY_LITTLE_ENDIAN.is_valid())
    assert_true(PLY_BINARY_BIG_ENDIAN.is_valid())
    assert_false(PlyFormat(3).is_valid())
    with assert_raises():
        _ = ply_format("binary")


def test_decode_reads_every_type_in_both_byte_orders() raises:
    for big in [False, True]:
        var format = PLY_BINARY_BIG_ENDIAN if big else PLY_BINARY_LITTLE_ENDIAN
        var bytes = List[UInt8]()
        put_int(bytes, -2, 1, big)
        put_int(bytes, 200, 1, big)
        put_int(bytes, -300, 2, big)
        put_int(bytes, 60000, 2, big)
        put_int(bytes, -70000, 4, big)
        put_int(bytes, 4000000000, 4, big)
        put_f32(bytes, 1.5, big)
        put_f64(bytes, -2.25, big)
        put_int(bytes, 5, 1, big)
        var expected: List[Float64] = [
            -2,
            200,
            -300,
            60000,
            -70000,
            4000000000,
            1.5,
            -2.25,
            5,
        ]
        var scalars: List[PlyScalar] = [
            PLY_INT8,
            PLY_UINT8,
            PLY_INT16,
            PLY_UINT16,
            PLY_INT32,
            PLY_UINT32,
            PLY_FLOAT32,
            PLY_FLOAT64,
            PLY_INT8,
        ]
        var at = 0
        for index in range(len(scalars)):
            assert_equal(
                decode_ply_scalar(bytes, at, scalars[index], format),
                expected[index],
            )
            at += scalars[index].size()


def test_decode_refuses_text_formats_and_the_end_of_the_file() raises:
    var bytes: List[UInt8] = [1, 2, 3, 4]
    with assert_raises():
        _ = decode_ply_scalar(bytes, 0, PLY_UINT8, PLY_ASCII)
    with assert_raises():
        _ = decode_ply_scalar(bytes, 0, PLY_UINT8, PlyFormat(5))
    with assert_raises():
        _ = decode_ply_scalar(bytes, 1, PLY_UINT32, PLY_BINARY_BIG_ENDIAN)
    with assert_raises():
        _ = decode_ply_scalar(bytes, -1, PLY_UINT8, PLY_BINARY_BIG_ENDIAN)
    assert_equal(
        decode_ply_scalar(bytes, 3, PLY_UINT8, PLY_BINARY_LITTLE_ENDIAN), 4
    )


# --- ASCII -------------------------------------------------------------------


def test_an_ascii_triangle_is_indexed() raises:
    var geometry = parse_ply(
        text_bytes(triangle("0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n"))
    )
    assert_true(geometry.is_indexed())
    assert_equal(geometry.vertex_count(), 3)
    assert_equal(geometry.triangle_count(), 1)
    assert_point(geometry.corner(0, 1), 1, 0, 0)
    assert_false(geometry.has_attribute(String(NORMAL)))
    assert_false(geometry.has_attribute(String(UV)))
    assert_false(geometry.has_attribute(String(COLOR)))


def test_normals_uvs_and_colors_are_read() raises:
    var geometry = parse_ply(
        text_bytes(
            triangle(
                (
                    "0 0 0 0 0 1 0.5 0.25 255 0 51\n"
                    "1 0 0 0 0 1 1 0 0 255 0\n"
                    "0 1 0 0 0 1 0 1 0 0 0\n"
                    "3 0 1 2\n"
                ),
                (
                    "property float nx\nproperty float ny\nproperty float nz\n"
                    "property float s\nproperty float t\n"
                    "property uchar red\nproperty uchar green\n"
                    "property uchar blue\n"
                ),
            )
        )
    )
    assert_point(geometry.attribute_view(String(NORMAL)).vector3(1), 0, 0, 1)
    ref uvs = geometry.attribute_view(String(UV))
    assert_almost_equal(uvs.component(0, 0), Float32(0.5))
    assert_almost_equal(uvs.component(0, 1), Float32(0.25))
    ref colors = geometry.attribute_view(String(COLOR))
    assert_equal(colors.item_size, 3)
    assert_almost_equal(colors.component(0, 0), Float32(1))
    assert_almost_equal(
        colors.component(0, 2),
        srgb_to_linear(Float32(51) / 255),
        atol=TOLERANCE,
    )
    assert_almost_equal(colors.component(1, 1), Float32(1))


def test_other_names_for_uvs_and_colors_and_an_alpha() raises:
    var geometry = parse_ply(
        text_bytes(
            triangle(
                (
                    "0 0 0 1 0 0 0 0 51\n1 0 0 0 1 0 0 0 255\n"
                    "0 1 0 0 0 0 0 0 0\n3 0 1 2\n"
                ),
                (
                    "property float u\nproperty float v\n"
                    "property uchar diffuse_red\nproperty uchar g\n"
                    "property uchar diffuse_b\nproperty uchar alpha\n"
                ),
            )
        )
    )
    assert_almost_equal(
        geometry.attribute_view(String(UV)).component(1, 1), Float32(1)
    )
    ref colors = geometry.attribute_view(String(COLOR))
    assert_equal(colors.item_size, 4)
    assert_almost_equal(colors.component(0, 3), Float32(51) / 255)
    assert_almost_equal(colors.component(1, 3), Float32(1))


def test_a_polygon_is_cut_into_a_fan_and_vertex_index_is_read() raises:
    var geometry = parse_ply(
        text_bytes(
            "ply\nformat ascii 1.0\ncomment a square\nobj_info made here\n"
            "element vertex 4\nproperty float x\nproperty float y\n"
            "property float z\n\nelement face 1\n"
            "property list uchar uint vertex_index\n"
            "end_header\r\n0 0 0\n1 0 0\n\n1 1 0\n0 1 0\n4 0 1 2 3\n"
        )
    )
    assert_equal(geometry.triangle_count(), 2)
    assert_point(geometry.corner(1, 0), 0, 0, 0)
    assert_point(geometry.corner(1, 1), 1, 1, 0)
    assert_point(geometry.corner(1, 2), 0, 1, 0)


def test_other_elements_and_properties_are_read_past() raises:
    var geometry = parse_ply(
        text_bytes(
            "ply\nformat ascii 1.0\n"
            "element material 1\nproperty list uchar float weights\n"
            "property int id\n"
            "element vertex 3\nproperty float x\nproperty float y\n"
            "property float z\nproperty list uchar int unused\n"
            "element face 1\nproperty uchar flags\n"
            "property list uchar int vertex_indices\n"
            "property list uchar float texcoord\n"
            "element edge 0\nproperty int a\n"
            "end_header\n"
            "2 0.5 0.5 7\n"
            "0 0 0 0\n1 0 0 1 9\n0 1 0 0\n"
            "1 3 0 1 2 0\n"
            "and trailing lines are ignored\n"
        )
    )
    assert_equal(geometry.triangle_count(), 1)
    assert_equal(geometry.vertex_count(), 3)


def test_a_file_without_faces_is_a_point_cloud() raises:
    var geometry = parse_ply(
        text_bytes(
            "ply\nformat ascii 1.0\nelement vertex 2\n"
            "property double x\nproperty double y\nproperty double z\n"
            "end_header\n1 2 3\n4 5 6"
        )
    )
    assert_false(geometry.is_indexed())
    assert_equal(geometry.vertex_count(), 2)
    # No vertices at all, and a face element with no rows.
    var empty = parse_ply(
        text_bytes(
            "ply\nformat ascii 1.0\nelement vertex 0\n"
            "property float x\nproperty float y\nproperty float z\n"
            "element face 0\nproperty list uchar int vertex_indices\n"
            "end_header"
        )
    )
    assert_equal(empty.vertex_count(), 0)


def test_an_ascii_value_must_be_a_number_of_its_type() raises:
    var three = String("0 0 0\n1 0 0\n0 1 0\n")
    assert_true("not a number: one" in refusal(triangle("0 0 0\none 0 0\n")))
    assert_true("not a whole number" in refusal(triangle(three + "3 0 1 x\n")))
    assert_true("out of range" in refusal(triangle(three + "256 0 1 2\n")))
    assert_true("out of range" in refusal(triangle(three + "-1 0 1 2\n")))
    # A signed type's range.
    var signed = String(
        "ply\nformat ascii 1.0\nelement vertex 1\nproperty char x\n"
        "property char y\nproperty char z\nend_header\n"
    )
    assert_equal(
        parse_ply(text_bytes(signed + "-128 127 0\n")).vertex_count(), 1
    )
    assert_true("out of range" in refusal(signed + "-129 0 0\n"))
    assert_true("out of range" in refusal(signed + "0 128 0\n"))


def test_an_ascii_row_must_fit_its_properties() raises:
    var three = String("0 0 0\n1 0 0\n0 1 0\n")
    var seen = refusal(triangle("0 0 0\n1 0\n0 1 0\n3 0 1 2\n"))
    assert_true("`vertex` row 1" in seen, seen)
    assert_true("fewer values" in seen, seen)
    assert_true("more values" in refusal(triangle(three + "3 0 1 2 3\n")))
    assert_true("ends before" in refusal(triangle(three)))
    assert_true("ends before" in refusal(triangle(three + "\n\n")))


def test_a_coordinate_must_be_finite() raises:
    var three = String("1 0 0\n0 1 0\n3 0 1 2\n")
    assert_true("`x` must be" in refusal(triangle("1e100 0 0\n" + three)))
    assert_true("`y` must be" in refusal(triangle("0 nan 0\n" + three)))
    assert_true("`z` must be" in refusal(triangle("0 0 inf\n" + three)))
    var extra = String(
        "property float nx\nproperty float ny\nproperty float nz\n"
        "property float s\nproperty float t\n"
        "property float red\nproperty float green\nproperty float blue\n"
        "property float alpha\n"
    )
    var good = String("0 0 1 0 0 1 1 1 1")
    var rest = String("1 0 0 " + good + "\n0 1 0 " + good + "\n3 0 1 2\n")
    assert_equal(parse_text(triangle("0 0 0 " + good + "\n" + rest, extra)), 1)
    var bad: List[String] = [
        "inf 0 1 0 0 1 1 1 1",
        "0 inf 1 0 0 1 1 1 1",
        "0 0 inf 0 0 1 1 1 1",
        "0 0 1 inf 0 1 1 1 1",
        "0 0 1 0 inf 1 1 1 1",
        "0 0 1 0 0 inf 1 1 1",
        "0 0 1 0 0 1 1 1 inf",
    ]
    for row in bad:
        assert_true(
            "must be" in refusal(triangle("0 0 0 " + row + "\n" + rest, extra))
        )


# --- binary ------------------------------------------------------------------


def binary_quad(big: Bool) -> List[UInt8]:
    """Return a binary file of a square: four vertices, one of each
    integer and float type among its properties, and one quad."""
    var bytes = text_bytes(
        "ply\nformat "
        + ("binary_big_endian" if big else "binary_little_endian")
        + " 1.0\nelement vertex 4\n"
        "property float x\nproperty double y\nproperty short z\n"
        "property char nx\nproperty ushort ny\nproperty int nz\n"
        "property uint tx\nproperty uchar ty\n"
        "element face 1\nproperty list uchar int vertex_indices\n"
        "end_header\n"
    )
    var xs: List[Float32] = [0, 2, 2, 0]
    var ys: List[Float64] = [0, 0, 2, 2]
    for index in range(4):
        put_f32(bytes, xs[index], big)
        put_f64(bytes, ys[index], big)
        put_int(bytes, -1, 2, big)
        put_int(bytes, -1, 1, big)
        put_int(bytes, 0, 2, big)
        put_int(bytes, 0, 4, big)
        put_int(bytes, index, 4, big)
        put_int(bytes, 255, 1, big)
    put_int(bytes, 4, 1, big)
    for index in range(4):
        put_int(bytes, index, 4, big)
    return bytes^


def test_a_binary_file_reads_in_both_byte_orders() raises:
    for big in [False, True]:
        var geometry = parse_ply(binary_quad(big))
        assert_equal(geometry.triangle_count(), 2)
        assert_point(geometry.corner(0, 1), 2, 0, -1)
        assert_point(geometry.corner(1, 1), 2, 2, -1)
        assert_point(
            geometry.attribute_view(String(NORMAL)).vector3(0), -1, 0, 0
        )
        ref uvs = geometry.attribute_view(String(UV))
        assert_almost_equal(uvs.component(3, 0), Float32(3))
        assert_almost_equal(uvs.component(3, 1), Float32(255))


def test_a_binary_file_that_ends_early_is_refused() raises:
    var bytes = binary_quad(False)
    _ = bytes.pop()
    var seen = String()
    try:
        _ = parse_ply(bytes)
    except reason:
        seen = String(reason)
    assert_true("`face` row 0" in seen, seen)
    assert_true("ends inside a value" in seen, seen)


def test_a_binary_element_with_no_properties_takes_no_bytes() raises:
    var bytes = text_bytes(
        "ply\nformat binary_little_endian 1.0\nelement nothing 2\n"
        "element vertex 1\nproperty uchar x\nproperty uchar y\n"
        "property uchar z\nend_header\r"
    )
    bytes += [UInt8(1), 2, 3]
    var geometry = parse_ply(bytes)
    assert_point(geometry.attribute_view(String(POSITION)).vector3(0), 1, 2, 3)


def test_a_binary_list_cannot_be_negative() raises:
    var bytes = text_bytes(
        "ply\nformat binary_little_endian 1.0\n"
        "element vertex 0\nproperty uchar x\nproperty uchar y\n"
        "property uchar z\n"
        "element face 1\nproperty list char int vertex_indices\n"
        "end_header\n"
    )
    bytes.append(0xFF)
    var seen = String()
    try:
        _ = parse_ply(bytes)
    except reason:
        seen = String(reason)
    assert_true("negative length" in seen, seen)


# --- the header --------------------------------------------------------------


def test_a_header_that_is_not_ply_is_refused() raises:
    assert_true("end_header" in refusal("ply\nformat ascii 1.0\n"))
    assert_true("end_header" in refusal(""))
    assert_true("start with `ply`" in refusal("plyx\nend_header\n"))
    assert_true("no `format`" in refusal("ply\nend_header\n"))
    assert_true("no `format`" in refusal("plyend_header"))
    assert_true("no `vertex`" in refusal("ply\nformat ascii 1.0\nend_header"))
    assert_true(
        "`x`, `y` and `z`"
        in refusal("ply\nformat ascii 1.0\nelement vertex 0\nend_header")
    )
    assert_true("not known" in refusal("ply\nformat text 1.0\nend_header\n"))
    assert_true("takes" in refusal("ply\nformat ascii\nend_header\n"))
    assert_true(
        "not a header line"
        in refusal("ply\nformat ascii 1.0\nvertex 3\nend_header\n")
    )
    var bytes = text_bytes("ply\ncomment ")
    bytes.append(0xFF)
    bytes += text_bytes("\nend_header\n")
    with assert_raises():
        _ = parse_ply(bytes)


def test_malformed_elements_and_properties_are_refused() raises:
    var start = String("ply\nformat ascii 1.0\n")
    assert_true("takes" in refusal(start + "element vertex\nend_header\n"))
    assert_true(
        "not a count" in refusal(start + "element vertex x\nend_header\n")
    )
    assert_true(
        "negative" in refusal(start + "element vertex -1\nend_header\n")
    )
    assert_true(
        "named twice"
        in refusal(start + "element vertex 0\nelement vertex 0\nend_header\n")
    )
    assert_true(
        "before any element"
        in refusal(start + "property float x\nend_header\n")
    )
    var element = start + "element vertex 0\n"
    for line in [
        "property list uchar int\n",
        "property float a b c\n",
        "property list x\n",
        "property float\n",
    ]:
        assert_true(
            "`property` takes" in refusal(element + line + "end_header\n")
        )
    assert_true(
        "not known"
        in refusal(element + "property list uchar long x\nend_header\n")
    )
    assert_true(
        "not known" in refusal(element + "property real x\nend_header\n")
    )
    assert_true(
        "integer type"
        in refusal(element + "property list float int x\nend_header\n")
    )


def test_a_vertex_must_have_its_channels() raises:
    var start = String("ply\nformat ascii 1.0\n")
    assert_true(
        "no `vertex`" in refusal(start + "element face 0\nend_header\n")
    )
    var axes: List[String] = ["y z", "x z", "x y"]
    for pair in axes:
        var header = start + "element vertex 0\n"
        for name in String(pair).split():
            header += "property float " + String(name) + "\n"
        assert_true("`x`, `y` and `z`" in refusal(header + "end_header\n"))
    var xyz = (
        start
        + "element vertex 0\nproperty float x\nproperty float y\n"
        "property float z\n"
    )
    assert_true(
        "normal only"
        in refusal(xyz + "property float nx\nproperty float ny\nend_header\n")
    )
    assert_true(
        "texture coordinate only"
        in refusal(xyz + "property float t\nend_header\n")
    )
    assert_true(
        "color only" in refusal(xyz + "property uchar red\nend_header\n")
    )
    assert_true("an alpha" in refusal(xyz + "property uchar a\nend_header\n"))
    assert_true(
        "single value"
        in refusal(xyz + "property list uchar float nx\nend_header\n")
    )


def test_a_face_must_have_a_list_of_integer_indices() raises:
    var start = String(
        "ply\nformat ascii 1.0\nelement vertex 0\nproperty float x\n"
        "property float y\nproperty float z\nelement face 0\n"
    )
    assert_true("must have" in refusal(start + "end_header\n"))
    assert_true(
        "must have" in refusal(start + "property int corners\nend_header\n")
    )
    assert_true(
        "must be a list"
        in refusal(start + "property int vertex_indices\nend_header\n")
    )
    assert_true(
        "integer type"
        in refusal(
            start + "property list uchar float vertex_indices\nend_header\n"
        )
    )


# --- faces -------------------------------------------------------------------


def test_a_face_must_name_three_vertices_the_file_has() raises:
    var three = String("0 0 0\n1 0 0\n0 1 0\n")
    assert_true("three corners" in refusal(triangle(three + "2 0 1\n")))
    assert_true("three corners" in refusal(triangle(three + "0\n")))
    var seen = refusal(triangle(three + "3 0 1 3\n"))
    assert_true("PLY face 0" in seen, seen)
    assert_true("names vertex 3" in seen, seen)
    assert_true("names vertex -1" in refusal(triangle(three + "3 0 -1 2\n")))


def test_a_polygon_must_be_convex_and_have_area() raises:
    var header = String(
        "ply\nformat ascii 1.0\nelement vertex 4\nproperty float x\n"
        "property float y\nproperty float z\nelement face 1\n"
        "property list uchar int vertex_indices\nend_header\n"
    )
    # An arrowhead: one corner turns the other way.
    assert_true(
        "not convex"
        in refusal(header + "0 0 0\n2 1 0\n4 0 0\n2 3 0\n4 0 1 2 3\n")
    )
    # Corners on one line.
    assert_true(
        "no area" in refusal(header + "0 0 0\n1 0 0\n2 0 0\n3 0 0\n4 0 1 2 3\n")
    )


# --- a file on disk ----------------------------------------------------------


def test_the_cube_file_reads_as_twelve_colored_triangles() raises:
    var geometry = read_ply("assets/cube.ply")
    assert_equal(geometry.vertex_count(), 8)
    assert_equal(geometry.triangle_count(), 12)
    ref colors = geometry.attribute_view(String(COLOR))
    assert_almost_equal(colors.component(7, 0), Float32(1))
    assert_almost_equal(colors.component(0, 0), Float32(0))
    ref positions = geometry.attribute_view(String(POSITION))
    for vertex in range(positions.count()):
        var point = positions.vector3(vertex)
        assert_almost_equal(abs(point.x), Float32(0.5), atol=TOLERANCE)
        assert_almost_equal(abs(point.y), Float32(0.5), atol=TOLERANCE)
        assert_almost_equal(abs(point.z), Float32(0.5), atol=TOLERANCE)


def test_a_file_that_is_not_there_is_refused() raises:
    with assert_raises():
        _ = read_ply("assets/no_such_model.ply")


def test_a_read_model_renders() raises:
    var assets = Assets()
    var shape = assets.geometries.add(read_ply("assets/cube.ply"))
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
