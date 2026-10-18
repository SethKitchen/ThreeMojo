# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact diagnostics when valid-path validation stops formatting errors."""

from core.user_data import UserData, json_number_text
from loaders.stl import parse_stl
from loaders.xml import parse_xml
from render.color_spaces import ColorSpaceId, color_space
from std.math import inf, nan
from std.testing import TestSuite, assert_equal
from tests.test_stl import header, put_u32, put_face
from tests.test_gltf import doc, refused
from math.vector3 import Vector3


def test_number_failures_keep_the_value_and_prefix() raises:
    var values: List[Float64] = [
        inf[DType.float64](),
        -inf[DType.float64](),
        nan[DType.float64](),
    ]
    for value in values:
        var seen = String()
        try:
            _ = json_number_text(value)
        except reason:
            seen = String(reason)
        assert_equal(
            seen, "User data: a number must be finite: " + String(value)
        )
    assert_equal(json_number_text(-0.0), "0")
    assert_equal(json_number_text(42.0), "42")


def test_key_failures_keep_position_and_json_escaping() raises:
    var data = UserData()
    data.set_number("first", 42)
    var indices: List[Int] = [-1, 1]
    for index in indices:
        var seen = String()
        try:
            _ = data.key(index)
        except reason:
            seen = String(reason)
        assert_equal(seen, "User data: no key at position " + String(index))
    var missing = String('quote"\\\n')
    var seen = String()
    try:
        _ = data.json(missing)
    except reason:
        seen = String(reason)
    assert_equal(seen, 'User data: no key "quote\\"\\\\\\n"')
    assert_equal(data.key(0), "first")
    assert_equal(data.json("first"), "42")


def test_binary_float_refusal_keeps_face_and_first_bad_value() raises:
    var bytes = header("binary")
    put_u32(bytes, 2)
    var corners: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    ]
    put_face(bytes, Vector3(0, 0, 1), corners, 0)
    put_face(
        bytes,
        Vector3(inf[DType.float32](), -inf[DType.float32](), 1),
        corners,
        0,
    )
    var seen = String()
    try:
        _ = parse_stl(bytes)
    except reason:
        seen = String(reason)
    assert_equal(
        seen,
        "STL face 1: a coordinate must be a finite number, and this one is inf",
    )


def test_xml_byte_offsets_and_element_indices_stay_exact() raises:
    var texts: List[String] = ["<root>", "<root a='abc", "<!DOCTYPE root ["]
    var endings: List[String] = [
        "<root> is not closed",
        "an attribute value is not closed",
        "a document type declaration is not closed",
    ]
    for index in range(len(texts)):
        var seen = String()
        try:
            _ = parse_xml(texts[index])
        except reason:
            seen = String(reason)
        assert_equal(
            seen,
            "XML at byte "
            + String(texts[index].byte_length())
            + ": "
            + endings[index],
        )
    var document = parse_xml("<root a='valid'>text</root>")
    assert_equal(document.attribute(0, "a"), "valid")
    assert_equal(document.text(0), "text")
    var seen = String()
    try:
        _ = document.name(1)
    except reason:
        seen = String(reason)
    assert_equal(seen, "XML: no element at index 1")


def test_invalid_color_space_keeps_numeric_diagnostic() raises:
    var seen = String()
    try:
        _ = color_space(ColorSpaceId(-1))
    except reason:
        seen = String(reason)
    assert_equal(seen, "Not a color space: -1")


def test_negative_gltf_image_is_refused_before_malformed_images() raises:
    assert_equal(
        refused(doc('"textures":[{"source":-1}],"images":0')),
        "glTF: a texture names an image that is not there",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
