# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `exporters.json_writer` and `exporters.common`: every value
kind, every escape, every refusal, numbers that read back to the same
`Float32`, bytes in both orders, and every geometry check."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from exporters.common import (
    check_geometry,
    format_float32,
    push_f32,
    push_word,
)
from exporters.json_writer import JsonWriter, quote_json
from loaders.json import parse_json
from std.math import inf, nan
from std.memory import bitcast
from std.random import random_ui64, seed
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_a_number_reads_back_to_the_same_float32() raises:
    assert_equal(format_float32(0.5), "0.5")
    assert_equal(format_float32(-2), "-2.0")
    assert_equal(format_float32(1e-5), "1e-05")
    # The shortest text Mojo gives for this one reads back one unit off,
    # so the exact wide text is written instead.
    var awkward = Float32(3471.776123046875)
    assert_true(Float32(Float64(String(awkward))) != awkward)
    assert_equal(format_float32(awkward), "3471.776123046875")
    # Many numbers at random, every exponent included.
    seed(11)
    for _ in range(500):
        var bits = UInt32(random_ui64(0, 0xFFFFFFFF))
        var value = bitcast[DType.float32](bits)
        if value != value or abs(value) == inf[DType.float32]():
            continue
        assert_equal(Float32(Float64(format_float32(value))), value)


def test_a_number_that_is_not_finite_is_refused() raises:
    with assert_raises(contains="finite"):
        _ = format_float32(nan[DType.float32]())
    with assert_raises(contains="finite"):
        _ = format_float32(inf[DType.float32]())
    var bytes = List[UInt8]()
    with assert_raises(contains="finite"):
        push_f32(bytes, -inf[DType.float32](), True)
    assert_equal(len(bytes), 0)


def test_bytes_go_in_either_order() raises:
    var bytes = List[UInt8]()
    push_word(bytes, 0x01020304, 4, True)
    push_word(bytes, 0x01020304, 4, False)
    push_word(bytes, 0xABCD, 2, True)
    push_word(bytes, 0x1FF, 1, False)
    assert_equal(len(bytes), 11)
    assert_equal(bytes[0], 4)
    assert_equal(bytes[3], 1)
    assert_equal(bytes[4], 1)
    assert_equal(bytes[7], 4)
    assert_equal(bytes[8], 0xCD)
    assert_equal(bytes[9], 0xAB)
    assert_equal(bytes[10], 0xFF)
    var floats = List[UInt8]()
    push_f32(floats, 1.0, True)
    push_f32(floats, 1.0, False)
    assert_equal(floats[3], 0x3F)
    assert_equal(floats[4], 0x3F)
    assert_equal(floats[2], 0x80)


def test_every_escape_is_written_and_reads_back() raises:
    var text = String('a"b\\c\x08\x0c\n\r\t\x01\x1f/é')
    var quoted = quote_json(text)
    assert_equal(quoted, '"a\\"b\\\\c\\b\\f\\n\\r\\t\\u0001\\u001f/é"')
    var document = parse_json(quoted)
    assert_equal(document.string(document.root()), text)
    assert_equal(quote_json(""), '""')


def test_a_document_is_written_with_its_commas_and_colons() raises:
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("name")
    writer.string("cube")
    writer.key("list")
    writer.begin_array()
    writer.integer(1)
    writer.number(2.5)
    writer.boolean(True)
    writer.boolean(False)
    writer.null()
    writer.begin_object()
    writer.end_object()
    writer.begin_array()
    writer.end_array()
    writer.raw('{"x":1}')
    writer.end_array()
    writer.key("after")
    writer.integer(-3)
    writer.end_object()
    var text = writer.finish()
    assert_equal(
        text,
        '{"name":"cube","list":[1,2.5,true,false,null,{},[],{"x":1}],'
        + '"after":-3}',
    )
    var document = parse_json(text)
    var root = document.root()
    assert_equal(document.string(document.get(root, "name")), "cube")
    assert_equal(document.length(document.get(root, "list")), 8)
    # A root that is not a container is finished at once.
    var single = JsonWriter()
    single.integer(7)
    assert_equal(single.finish(), "7")


def test_what_json_has_no_place_for_is_refused() raises:
    # A second root value.
    var twice = JsonWriter()
    twice.integer(1)
    with assert_raises(contains="second root"):
        twice.integer(2)
    # A value in an object without a key.
    var keyless = JsonWriter()
    keyless.begin_object()
    with assert_raises(contains="needs a key"):
        keyless.string("x")
    # A key outside an object: at the root, and in an array.
    var bare = JsonWriter()
    with assert_raises(contains="open object"):
        bare.key("x")
    var listed = JsonWriter()
    listed.begin_array()
    with assert_raises(contains="open object"):
        listed.key("x")
    # Two keys in a row.
    var doubled = JsonWriter()
    doubled.begin_object()
    doubled.key("a")
    with assert_raises(contains="open object"):
        doubled.key("b")
    # A key whose object closes before its value.
    with assert_raises(contains="does not match"):
        doubled.end_object()
    # A close that does not match, and one with nothing open.
    var crossed = JsonWriter()
    crossed.begin_array()
    with assert_raises(contains="does not match"):
        crossed.end_object()
    var closed = JsonWriter()
    with assert_raises(contains="does not match"):
        closed.end_array()
    # A text taken before its root is finished.
    with assert_raises(contains="not finished"):
        _ = crossed.finish()
    with assert_raises(contains="not finished"):
        _ = JsonWriter().finish()
    # A number that is not finite.
    var infinite = JsonWriter()
    with assert_raises(contains="finite"):
        infinite.number(inf[DType.float32]())
    assert_false(infinite._done)


def triangle() raises -> BufferGeometry:
    """Return one triangle with every attribute an exporter writes."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 0, 1, 0], 3),
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute([Float32(0), 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(
        String(UV), BufferAttribute([Float32(0), 0, 1, 0, 0, 1], 2)
    )
    geometry.set_attribute(
        String(COLOR),
        BufferAttribute([Float32(1), 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1], 4),
    )
    return geometry^


def test_a_geometry_is_checked_before_it_is_written() raises:
    assert_equal(check_geometry(triangle()), 3)
    var indexed = triangle()
    indexed.set_index([0, 1, 2, 2, 1, 0])
    assert_equal(check_geometry(indexed), 3)
    # No positions, and positions of two numbers a vertex.
    with assert_raises(contains="needs a position"):
        _ = check_geometry(BufferGeometry())
    var flat = BufferGeometry()
    flat.set_attribute(
        String(POSITION), BufferAttribute([Float32(0), 0, 1, 1, 2, 2], 2)
    )
    with assert_raises(contains="three numbers"):
        _ = check_geometry(flat)
    # An attribute too narrow, too wide, or of the wrong count.
    var narrow = triangle()
    narrow.set_attribute(
        String(COLOR), BufferAttribute([Float32(0), 0, 1, 1, 2, 2], 2)
    )
    with assert_raises(contains="color must hold 3 to 4"):
        _ = check_geometry(narrow)
    var wide = triangle()
    wide.set_attribute(
        String(UV), BufferAttribute([Float32(0), 0, 1, 1, 2, 2], 3)
    )
    with assert_raises(contains="uv must hold 2 to 2"):
        _ = check_geometry(wide)
    var short = triangle()
    short.set_attribute(String(NORMAL), BufferAttribute([Float32(0), 0, 1], 3))
    with assert_raises(contains="one item per position"):
        _ = check_geometry(short)
    # An index past the last vertex.
    var past = triangle()
    past.set_index([0, 1, 3])
    with assert_raises(contains="past the last vertex"):
        _ = check_geometry(past)
    # No index and a partial triangle.
    var partial = BufferGeometry()
    partial.set_attribute(
        String(POSITION), BufferAttribute([Float32(0), 0, 0, 1, 1, 1], 3)
    )
    with assert_raises(contains="whole triangles"):
        _ = check_geometry(partial)
    # A geometry of positions alone, with no vertices, passes.
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    assert_equal(check_geometry(empty), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
