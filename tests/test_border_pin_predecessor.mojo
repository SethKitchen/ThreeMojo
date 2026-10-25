# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed border pins restore from the live consumer files."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._border_pin_predecessor import restored_border_pins
from tests._geometry_predecessor import restored_geometry
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/border-parser-successor.json"
"""The reviewed border parser record."""
comptime _RECORD_SHA256 = (
    "0119f046c502021dc422f82ad602074e24cf3fa192f27fd372e80a927d94860b"
)
"""The SHA-256 of that record."""
comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The geometry module restored by its own predecessor."""


def _field(doc: PyJson, node: Int, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The document.
        node: The object.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(node, name))


def _find(paths: List[String], name: String) -> Int:
    """Return the index of `name`, or -1.

    Args:
        paths: The restored paths.
        name: The path to find.

    Returns:
        The index, or -1 when the path was not restored here.
    """
    for index in range(len(paths)):
        if paths[index] == name:
            return index
    return -1


def test_live_consumers_restore_their_border_pins() raises:
    """Forty-one consumers and the geometry module restore their border pins."""
    if sha256_hex(Path(_RECORD).read_bytes()) != _RECORD_SHA256:
        raise Error(
            "reviewed border parser successor: immutable successor record"
            " changed"
        )
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var pins = doc.at(doc.root, "unchanged_inputs")
    var paths = List[String]()
    var texts = List[String]()
    restored_border_pins(paths, texts)
    assert_equal(len(paths), 41)
    var geometry = restored_geometry()
    var direct = 0
    var index = 0
    while index < doc.length(pins):
        var name = doc.key(pins, index)
        var expected = doc.text(doc.value(pins, index))
        if name == _GEOMETRY:
            assert_equal(sha256_hex(geometry.as_bytes()), expected)
        else:
            var found = _find(paths, name)
            if found >= 0:
                assert_equal(sha256_hex(texts[found].as_bytes()), expected)
            elif sha256_hex(Path(name).read_bytes()) == expected:
                direct += 1
        index += 1
    assert_equal(direct, 50)


def test_a_changed_border_pin_is_refused() raises:
    """A changed record or restored consumer changes its digest."""
    var record = Path(_RECORD).read_text()
    assert_true(sha256_hex((record + " ").as_bytes()) != _RECORD_SHA256)
    var paths = List[String]()
    var texts = List[String]()
    restored_border_pins(paths, texts)
    var changed = texts[0] + "\n"
    assert_true(
        sha256_hex(changed.as_bytes()) != sha256_hex(texts[0].as_bytes())
    )


def main() raises:
    """Run the border pin predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
