# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.xyz`.

`assets/xyz/fixture.json` is what three.js 0.180's `XYZLoader` gives for
`assets/xyz/colored.xyz` and `assets/xyz/plain.xyz` in node.
"""

from core.buffer_geometry import COLOR, POSITION
from loaders.json import parse_json
from loaders.xyz import parse_xyz, read_xyz
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64) raises:
    """Assert two numbers agree to a `Float32`."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= 1e-6 * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def check(name: String) raises:
    """Compare one fixture with three.js."""
    var geometry = read_xyz("assets/xyz/" + name)
    var doc = parse_json(Path("assets/xyz/fixture.json").read_text())
    var want = doc.get(doc.root(), name)
    assert_equal(geometry.attribute_count(), doc.length(want))
    for attribute in [String(POSITION), String(COLOR)]:
        if not doc.has(want, attribute):
            assert_false(geometry.has_attribute(attribute))
            continue
        var got = geometry.clone_attribute(attribute).packed()
        var values = doc.get(want, attribute)
        assert_equal(len(got), doc.length(values))
        for i in range(len(got)):
            near(Float64(got[i]), doc.number(doc.at(values, i)))


def test_the_fixtures_match_three_js() raises:
    check("colored.xyz")
    check("plain.xyz")


def test_empty_and_refused() raises:
    var empty = parse_xyz("# nothing\n\n")
    assert_equal(empty.vertex_count(), 0)
    with assert_raises(contains="is not a number"):
        _ = parse_xyz("1 x 3")
    with assert_raises(contains="is not a number"):
        _ = parse_xyz("1 2 3 4 y 6")
    with assert_raises(contains="some do not"):
        _ = parse_xyz("1 2 3\n1 2 3 4 5 6")
    with assert_raises():
        _ = read_xyz("assets/xyz/missing.xyz")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
