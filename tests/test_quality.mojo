# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the named humanoid mesh quality levels."""

from extensions.humanoid.quality import (
    HIGH,
    LOW,
    MEDIUM,
    Quality,
    XHIGH,
    anatomy_detail,
    hand_skin_detail,
    quality_label,
    quality_named,
    skin_detail,
    triangle_budget,
)
from extensions.humanoid.skeleton.hand.skin.geometry import (
    hand_skin_from_dimensions,
)
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def test_quality_is_valid() raises:
    assert_true(LOW.is_valid())
    assert_true(MEDIUM.is_valid())
    assert_true(HIGH.is_valid())
    assert_true(XHIGH.is_valid())
    assert_false(Quality(4).is_valid())
    assert_false(Quality(-1).is_valid())


def test_levels_set_the_three_details() raises:
    assert_equal(anatomy_detail(LOW), 8)
    assert_equal(anatomy_detail(MEDIUM), 10)
    assert_equal(anatomy_detail(HIGH), 12)
    assert_equal(anatomy_detail(XHIGH), 16)
    assert_equal(skin_detail(LOW), 32)
    assert_equal(skin_detail(MEDIUM), 40)
    assert_equal(skin_detail(HIGH), 48)
    assert_equal(skin_detail(XHIGH), 56)
    assert_equal(hand_skin_detail(LOW), 24)
    assert_equal(hand_skin_detail(MEDIUM), 32)
    assert_equal(hand_skin_detail(HIGH), 40)
    assert_equal(hand_skin_detail(XHIGH), 48)
    assert_equal(triangle_budget(LOW), 90000)
    assert_equal(triangle_budget(MEDIUM), 200000)
    assert_equal(triangle_budget(HIGH), 450000)
    assert_equal(triangle_budget(XHIGH), 1000000)


def test_unnamed_quality_is_refused() raises:
    with assert_raises():
        _ = anatomy_detail(Quality(7))
    with assert_raises():
        _ = skin_detail(Quality(7))
    with assert_raises():
        _ = hand_skin_detail(Quality(7))
    with assert_raises():
        _ = quality_label(Quality(7))
    with assert_raises():
        _ = triangle_budget(Quality(7))


def test_names_round_trip() raises:
    var levels = [LOW, MEDIUM, HIGH, XHIGH]
    for index in range(len(levels)):  # pragma: no branch
        var level = levels[index]
        assert_true(quality_named(quality_label(level)) == level)
    with assert_raises():
        _ = quality_named("ultra")


def test_higher_quality_makes_more_triangles() raises:
    var arms = arm_muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    var low = hand_skin_from_dimensions(arms, RIGHT, hand_skin_detail(LOW))
    var medium = hand_skin_from_dimensions(
        arms, RIGHT, hand_skin_detail(MEDIUM)
    )
    assert_true(medium.triangle_count() > low.triangle_count())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
