# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Parser diagnostics remain lazy and retain their original text and order."""

from core.ordinal import require_draw_ids
from loaders.gltf import _Loader
from loaders.json import parse_json
from loaders.lut_cube import _number as lut_number
from loaders.text_number import read_finite_float32
from std.testing import TestSuite, assert_equal, assert_true


def test_lut_invalid_number_does_not_append_parser_exception() raises:
    var seen = String()
    try:
        _ = lut_number("bad", 7)
    except reason:
        seen = String(reason)
    assert_equal(seen, "LUT line 7: not a number: bad")
    seen = String()
    try:
        _ = lut_number("1e100", 8)
    except reason:
        seen = String(reason)
    assert_equal(seen, "LUT line 8: a number must be finite: 1e100")
    assert_equal(lut_number("0.25", 9), Float32(0.25))


def test_shared_number_error_preserves_the_parser_reason() raises:
    for field in [String("bad"), String("")]:
        var parser_reason = String()
        try:
            _ = Float64(field)
        except reason:
            parser_reason = String(reason)
        assert_true(parser_reason.byte_length() > 0)
        var seen = String()
        try:
            _ = read_finite_float32(field, "OBJ line 7: ", "finite required")
        except reason:
            seen = String(reason)
        assert_equal(
            seen,
            "OBJ line 7: not a number: " + field + " (" + parser_reason + ")",
        )


def test_shared_narrowing_keeps_finite_failure_text() raises:
    var seen = String()
    try:
        _ = read_finite_float32("1e100", "Prefix: ", "finite required")
    except reason:
        seen = String(reason)
    assert_equal(seen, "Prefix: finite required: 1e100")
    assert_equal(
        read_finite_float32("2.5", "Prefix: ", "finite required"), Float32(2.5)
    )


def test_draw_ids_keep_node_geometry_material_refusal_order() raises:
    var seen = String()
    try:
        require_draw_ids(-1, -1, -1, "Draw")
    except reason:
        seen = String(reason)
    assert_equal(seen, "Draw must name a scene node")
    seen = String()
    try:
        require_draw_ids(0, -1, -1, "Draw")
    except reason:
        seen = String(reason)
    assert_equal(seen, "Draw must name a geometry")
    seen = String()
    try:
        require_draw_ids(0, 0, -1, "Draw")
    except reason:
        seen = String(reason)
    assert_equal(seen, "Draw must name a material")
    require_draw_ids(0, 0, 0, "Draw")


def test_gltf_dynamic_fields_keep_exact_errors_and_valid_values() raises:
    var loader = _Loader(
        parse_json('{"bad":0,"ok":[1,2],"whole":3}'), List[UInt8](), ""
    )
    var seen = String()
    try:
        _ = loader.list("bad")
    except reason:
        seen = String(reason)
    assert_equal(seen, "glTF: bad must be an array")
    seen = String()
    try:
        _ = loader.required_integer(0, "absent")
    except reason:
        seen = String(reason)
    assert_equal(seen, "glTF: absent is required")
    seen = String()
    try:
        _ = loader.number_list(0, "bad")
    except reason:
        seen = String(reason)
    assert_equal(seen, "glTF: bad must be an array of numbers")
    assert_equal(loader.required_integer(0, "whole"), 3)
    var numbers = loader.number_list(0, "ok")
    assert_equal(len(numbers), 2)
    assert_equal(numbers[0], Float32(1))
    assert_equal(numbers[1], Float32(2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
