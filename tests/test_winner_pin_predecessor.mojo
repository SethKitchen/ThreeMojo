# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed winner pins restore from the live consumer files."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._border_pin_predecessor import restored_border_pins
from tests._geometry_predecessor import restored_geometry
from tests._winner_pin_predecessor import (
    restored_domain_winner,
    restored_winner_pins,
)
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/winner-sign-query-migration.json"
"""The reviewed winner and sign record."""
comptime _RECORD_SHA256 = (
    "b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3"
)
"""The SHA-256 of that record."""
comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The geometry module restored by its own predecessor."""
comptime _DOMAIN = "extensions/carla/spiral_domain_proof.mojo"
"""The domain module restored from its border pin."""
comptime _ROUNDED = "extensions/carla/curve_rounded_line.mojo"
"""A border pin that is not the winner pin."""
comptime _DISPATCH = "extensions/carla/curve_sample_dispatch.mojo"
"""A border pin that is not the winner pin."""


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


def test_live_consumers_restore_their_winner_pins() raises:
    """Restored consumers match the winner pins, and live matches stay direct.
    """
    if sha256_hex(Path(_RECORD).read_bytes()) != _RECORD_SHA256:
        raise Error("winner/sign source contract: unreviewed migration record")
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var schema = doc.at(doc.root, "schema")
    if doc.text(schema) != "1":
        raise Error("winner/sign source contract: unsupported migration schema")
    var pins = doc.at(doc.root, "canonical_source_unchanged")
    var border_paths = List[String]()
    var border_texts = List[String]()
    restored_border_pins(border_paths, border_texts)
    var paths = List[String]()
    var texts = List[String]()
    restored_winner_pins(paths, texts)
    assert_equal(len(paths), 15)
    var geometry = restored_geometry()
    var direct = 0
    var border_match = 0
    var border_differ = 0
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
            else:
                var border = _find(border_paths, name)
                if border >= 0:
                    var digest = sha256_hex(border_texts[border].as_bytes())
                    if digest == expected:
                        border_match += 1
                    else:
                        border_differ += 1
                        if name == _DOMAIN:
                            var domain = restored_domain_winner(
                                border_texts[border]
                            )
                            assert_equal(
                                sha256_hex(domain.as_bytes()), expected
                            )
                        else:
                            assert_true(name == _ROUNDED or name == _DISPATCH)
                elif sha256_hex(Path(name).read_bytes()) == expected:
                    direct += 1
        index += 1
    assert_equal(doc.length(pins), 112)
    assert_equal(border_match, 38)
    assert_equal(border_differ, 3)
    assert_equal(direct, 45)


def test_a_changed_winner_pin_is_refused() raises:
    """A changed record or restored consumer changes its digest."""
    var record = Path(_RECORD).read_text()
    assert_true(sha256_hex((record + " ").as_bytes()) != _RECORD_SHA256)
    var paths = List[String]()
    var texts = List[String]()
    restored_winner_pins(paths, texts)
    var changed = texts[0] + "\n"
    assert_true(
        sha256_hex(changed.as_bytes()) != sha256_hex(texts[0].as_bytes())
    )
    var border_paths = List[String]()
    var border_texts = List[String]()
    restored_border_pins(border_paths, border_texts)
    var domain_at = _find(border_paths, _DOMAIN)
    var domain = restored_domain_winner(border_texts[domain_at])
    assert_true(
        sha256_hex((domain + "\n").as_bytes()) != sha256_hex(domain.as_bytes())
    )


def main() raises:
    """Run the winner pin predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
