# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the inertial properties of a thigh, a shank and a foot."""

from extensions.humanoid.sex import MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.limb.inertia import (
    FOOT_SEGMENT,
    SHANK,
    THIGH,
    LimbSegment,
    segment_inertia,
)
from extensions.humanoid.skeleton.soft_tissue import (
    ADIPOSE,
    adipose_tissue,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    FOOT,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    Length,
    MILLIMETER,
)

# A coarse grid keeps the suite quick. The values move by a few percent.
comptime COARSE = Length(15.0, MILLIMETER)


def _person() -> HumanoidSpec:
    """Return the six-foot male the suite measures."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def test_segments_are_named() raises:
    assert_true(THIGH.is_valid())
    assert_true(SHANK.is_valid())
    assert_true(FOOT_SEGMENT.is_valid())
    assert_false(LimbSegment(3).is_valid())
    with assert_raises(contains="thigh, the shank or the foot"):
        _ = segment_inertia(_person(), LimbSegment(7))
    with assert_raises():
        _ = segment_inertia(_person(), THIGH, step=Length(1.0, MILLIMETER))


def test_adipose_tissue_is_lighter_than_water() raises:
    var fat = adipose_tissue()
    fat.validate()
    assert_true(fat.kind == ADIPOSE)
    assert_almost_equal(
        fat.wet_density.to(GRAM_PER_CUBIC_CENTIMETER), 0.92, atol=1.0e-4
    )


def test_segments_sit_between_their_joints() raises:
    var person = _person()
    var pose = assemble_leg(person)
    var thigh = segment_inertia(person, THIGH, step=COARSE)
    var shank = segment_inertia(person, SHANK, step=COARSE)
    var foot = segment_inertia(person, FOOT_SEGMENT, step=COARSE)
    # A thigh outweighs a shank, and a shank a foot, as de Leva (1996)
    # reports for adult men.
    assert_true(thigh.mass.to(KILOGRAM) > shank.mass.to(KILOGRAM))
    assert_true(shank.mass.to(KILOGRAM) > foot.mass.to(KILOGRAM))
    assert_true(thigh.mass.to(KILOGRAM) > 6)
    assert_true(thigh.mass.to(KILOGRAM) < 14)
    # Each center of mass lies within its segment, nearer its middle
    # than its ends, as de Leva reports.
    var hip = pose.hip_center().y
    var knee = thigh.center.y - (thigh.center.y - shank.center.y) * 0.5
    assert_true(thigh.center.y < hip)
    assert_true(thigh.center.y > shank.center.y)
    assert_true(shank.center.y > foot.center.y)
    assert_true(knee < hip)
    var from_hip = (hip - thigh.center.y) / thigh.length.value
    assert_true(from_hip > Float32(0.33))
    assert_true(from_hip < Float32(0.55))
    # The foot's center lies in front of the ankle.
    assert_true(foot.center.z > pose.ankle_center().z)


def test_a_segment_resists_turning_least_about_its_length() raises:
    var person = _person()
    var thigh = segment_inertia(person, THIGH, step=COARSE)
    assert_true(thigh.xx.to(KILOGRAM_SQUARE_METER) > 0)
    assert_true(thigh.yy.value < thigh.xx.value)
    assert_true(thigh.yy.value < thigh.zz.value)
    # De Leva's radii of gyration for the thigh are a third of its
    # length across it and a seventh along it.
    var across = thigh.gyration(thigh.xx).value / thigh.length.value
    var along = thigh.gyration(thigh.yy).value / thigh.length.value
    assert_true(across > Float32(0.24))
    assert_true(across < Float32(0.40))
    assert_true(along > Float32(0.10))
    assert_true(along < Float32(0.20))
    var foot = segment_inertia(person, FOOT_SEGMENT, step=COARSE)
    # The foot is long in z, so it turns least about z.
    assert_true(foot.zz.value < foot.xx.value)
    assert_true(abs(foot.xy.value) < foot.xx.value)
    assert_true(abs(foot.xz.value) < foot.xx.value)
    assert_true(abs(foot.yz.value) < foot.xx.value)


def test_a_left_limb_mirrors_a_right_one() raises:
    var person = _person()
    var right = segment_inertia(person, SHANK, RIGHT, COARSE)
    var left = segment_inertia(person, SHANK, LEFT, COARSE)
    assert_almost_equal(
        left.mass.value, right.mass.value, atol=Float64(0.05 * right.mass.value)
    )
    assert_almost_equal(left.center.x, -right.center.x, atol=0.004)
    assert_almost_equal(left.center.y, right.center.y, atol=0.004)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
