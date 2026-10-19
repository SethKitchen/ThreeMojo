# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the kinds of `extensions.castle`.

Each kind is valid on its named range and refused one past either end. The
names are the words the wiki page uses.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.castle.kinds import (
    ARCH_THRUST,
    BEARING,
    BRICK,
    CONE,
    CRUSHING,
    FOLIAGE,
    GABLE,
    GRAVEL,
    LAWN,
    LimitState,
    OVERTURNING,
    PARAPET,
    ROUND,
    RoofForm,
    SLATE,
    SLIDING,
    SQUARE,
    STONE,
    Surface,
    TENSION,
    TRUNK,
    TowerShape,
    WATER,
    require_limit_state,
    require_roof_form,
    require_surface,
    require_tower_shape,
    roof_form_from_name,
    tower_shape_from_name,
)


def test_tower_shape_names() raises:
    assert_true(ROUND.is_valid())
    assert_true(SQUARE.is_valid())
    assert_false(TowerShape(-1).is_valid())
    assert_false(TowerShape(2).is_valid())
    assert_equal(ROUND.name(), "round")
    assert_equal(SQUARE.name(), "square")
    assert_equal(TowerShape(7).name(), "unknown")
    assert_true(ROUND != SQUARE)


def test_roof_form_names() raises:
    assert_true(CONE.is_valid())
    assert_true(GABLE.is_valid())
    assert_true(PARAPET.is_valid())
    assert_false(RoofForm(-1).is_valid())
    assert_false(RoofForm(3).is_valid())
    assert_equal(CONE.name(), "cone")
    assert_equal(GABLE.name(), "gable")
    assert_equal(PARAPET.name(), "parapet")
    assert_equal(RoofForm(9).name(), "unknown")


def test_surface_names() raises:
    var all = [BRICK, STONE, SLATE, WATER, LAWN, GRAVEL, TRUNK, FOLIAGE]
    var names: List[String] = [
        "brick",
        "stone",
        "slate",
        "water",
        "lawn",
        "gravel",
        "trunk",
        "foliage",
    ]
    for i in range(8):
        assert_true(all[i].is_valid())
        assert_equal(all[i].value, i)
        assert_equal(all[i].name(), names[i])
    assert_false(Surface(-1).is_valid())
    assert_false(Surface(8).is_valid())
    assert_equal(Surface(8).name(), "unknown")


def test_limit_state_names() raises:
    var all = [OVERTURNING, SLIDING, BEARING, CRUSHING, TENSION, ARCH_THRUST]
    var names: List[String] = [
        "overturning",
        "sliding",
        "bearing",
        "crushing",
        "tension",
        "arch_thrust",
    ]
    for i in range(6):
        assert_true(all[i].is_valid())
        assert_equal(all[i].name(), names[i])
    assert_false(LimitState(-1).is_valid())
    assert_false(LimitState(6).is_valid())
    assert_equal(LimitState(6).name(), "unknown")


def test_require_helpers_accept_named_values() raises:
    require_tower_shape(ROUND)
    require_roof_form(GABLE)
    require_surface(WATER)
    require_limit_state(SLIDING)


def test_require_helpers_refuse_unnamed_values() raises:
    with assert_raises(contains="A tower shape is not valid"):
        require_tower_shape(TowerShape(5))
    with assert_raises(contains="A roof form is not valid"):
        require_roof_form(RoofForm(5))
    with assert_raises(contains="A surface is not valid"):
        require_surface(Surface(-3))
    with assert_raises(contains="A limit state is not valid"):
        require_limit_state(LimitState(99))


def test_names_read_back_as_kinds() raises:
    assert_equal(tower_shape_from_name("round"), ROUND)
    assert_equal(tower_shape_from_name("square"), SQUARE)
    assert_equal(roof_form_from_name("cone"), CONE)
    assert_equal(roof_form_from_name("gable"), GABLE)
    assert_equal(roof_form_from_name("parapet"), PARAPET)
    # Every named kind reads back from its own name.
    for k in range(2):
        assert_equal(tower_shape_from_name(TowerShape(k).name()).value, k)
    for k in range(3):
        assert_equal(roof_form_from_name(RoofForm(k).name()).value, k)


def test_an_unknown_name_is_refused() raises:
    with assert_raises(contains="round or square, not oval"):
        _ = tower_shape_from_name("oval")
    with assert_raises(contains="cone, gable or parapet, not flat"):
        _ = roof_form_from_name("flat")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
