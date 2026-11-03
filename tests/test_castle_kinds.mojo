# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the materials, roof kinds and provenances of a castle plan:
the numbers they carry, what is valid, and the names."""

from extensions.castle.kinds import (
    BARK,
    BRICK,
    CONE,
    DOCUMENTED,
    ESTIMATED,
    FLAT,
    FOLIAGE,
    GABLE,
    GLASS,
    GRAVEL,
    LAWN,
    MEASURED,
    METAL,
    Material,
    Provenance,
    RoofKind,
    SLATE,
    STONE,
    SURVEYED,
    WATER,
    WOOD,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_the_materials_are_eleven() raises:
    for value in range(11):
        assert_true(Material(value).is_valid())
        assert_true(Material(value).name() != "unknown")
    assert_false(Material(-1).is_valid())
    assert_false(Material(11).is_valid())
    assert_equal(BRICK.value, 0)
    assert_equal(STONE.value, 1)
    assert_equal(SLATE.value, 2)
    assert_equal(WATER.value, 3)
    assert_equal(LAWN.value, 4)
    assert_equal(GRAVEL.value, 5)
    assert_equal(FOLIAGE.value, 6)
    assert_equal(GLASS.value, 7)
    assert_equal(WOOD.value, 8)
    assert_equal(METAL.value, 9)
    assert_equal(BARK.value, 10)
    assert_equal(BRICK.name(), "brick")
    assert_equal(FOLIAGE.name(), "foliage")
    assert_equal(BARK.name(), "bark")
    assert_equal(Material(11).name(), "unknown")
    assert_true(BRICK == Material(0))
    assert_false(BRICK == STONE)


def test_the_roof_kinds_are_three() raises:
    for value in range(3):
        assert_true(RoofKind(value).is_valid())
        assert_true(RoofKind(value).name() != "unknown")
    assert_false(RoofKind(-1).is_valid())
    assert_false(RoofKind(3).is_valid())
    assert_equal(GABLE.name(), "gable")
    assert_equal(CONE.name(), "cone")
    assert_equal(FLAT.name(), "flat")
    assert_equal(RoofKind(3).name(), "unknown")
    assert_false(GABLE == CONE)


def test_the_provenances_are_four() raises:
    for value in range(4):
        assert_true(Provenance(value).is_valid())
        assert_true(Provenance(value).name() != "unknown")
    assert_false(Provenance(-1).is_valid())
    assert_false(Provenance(4).is_valid())
    assert_equal(SURVEYED.name(), "surveyed")
    assert_equal(MEASURED.name(), "measured")
    assert_equal(DOCUMENTED.name(), "documented")
    assert_equal(ESTIMATED.name(), "estimated")
    assert_equal(Provenance(4).name(), "unknown")
    assert_false(SURVEYED == ESTIMATED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
