# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public Draco entry points borrow bytes and return owned decoded data."""

from core.buffer_geometry import POSITION
from loaders.draco import (
    _decode_draco_owned,
    _parse_draco_owned,
    decode_draco,
    parse_draco,
)
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_decode_borrows_input_and_matches_consuming_decoder() raises:
    var bytes = Path("assets/draco/cube.drc").read_bytes()
    var saved = bytes.copy()
    var decoded = decode_draco(bytes)
    var owned = _decode_draco_owned(bytes.copy())
    assert_equal(bytes, saved)
    assert_true(decoded.points > 0)
    assert_equal(decoded.points, owned.points)
    assert_equal(decoded.faces, owned.faces)
    assert_equal(len(decoded.attributes), len(owned.attributes))
    for index in range(len(decoded.attributes)):
        assert_equal(decoded.float32_values(index), owned.float32_values(index))
    bytes[0] = 0
    assert_equal(decoded.faces, owned.faces)
    assert_equal(decoded.float32_values(0), owned.float32_values(0))


def test_parse_borrows_reusable_input_and_returns_owned_attributes() raises:
    var bytes = Path("assets/draco/cube.drc").read_bytes()
    var saved = bytes.copy()
    var first = parse_draco(bytes)
    var second = parse_draco(bytes)
    var owned = _parse_draco_owned(bytes.copy())
    assert_equal(bytes, saved)
    assert_true(first.has_attribute(String(POSITION)))
    bytes[0] = 0
    ref a = first.attribute_view(String(POSITION))
    ref b = second.attribute_view(String(POSITION))
    ref c = owned.attribute_view(String(POSITION))
    assert_equal(a.item_size, c.item_size)
    assert_equal(a.data, b.data)
    assert_equal(a.data, c.data)


def test_failed_decodes_preserve_the_callers_bytes() raises:
    var bytes: List[UInt8] = [68, 82]
    var saved = bytes.copy()
    with assert_raises(contains="the file is not Draco"):
        _ = decode_draco(bytes)
    assert_equal(bytes, saved)
    with assert_raises(contains="the file is not Draco"):
        _ = parse_draco(bytes)
    assert_equal(bytes, saved)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
