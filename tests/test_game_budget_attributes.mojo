# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skipping an empty attribute transfer preserves the original budget result."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR
from extensions.humanoid.rig.game import _budgeted, carry_attributes
from extensions.humanoid.skeleton.head.skin.tint import THINNESS
from extensions.humanoid.skeleton.simplify import simplify
from geometries.sphere import sphere
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Length


def test_budget_transfer_matches_unguarded_path_for_all_attribute_sets() raises:
    for attributes in range(4):
        var source = sphere(Length(0.02), 8, 4)
        var count = source.vertex_count()
        if (attributes & 1) != 0:
            source.set_attribute(
                String(COLOR),
                BufferAttribute(List[Float32](length=count * 3, fill=0.5), 3),
            )
        if (attributes & 2) != 0:
            source.set_attribute(
                String(THINNESS),
                BufferAttribute(List[Float32](length=count, fill=0.25), 1),
            )
        var expected = simplify(source, 12)
        carry_attributes(source, expected)
        var actual = _budgeted(source.clone(), 12)
        assert_true(actual.triangle_count() < source.triangle_count())
        assert_equal(actual.index, expected.index)
        assert_equal(actual.names, expected.names)
        for name in expected.names:
            assert_equal(
                actual.attribute_view(name).packed(),
                expected.attribute_view(name).packed(),
            )
        for name in [String(COLOR), String(THINNESS)]:
            assert_equal(actual.has_attribute(name), source.has_attribute(name))
            if actual.has_attribute(name):
                var expected_value = Float32(0.5) if name == COLOR else Float32(
                    0.25
                )
                for value in actual.attribute_view(name).packed():
                    assert_equal(value, expected_value)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
