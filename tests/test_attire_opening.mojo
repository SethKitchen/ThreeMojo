# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for necklines, openings and sleeves."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION
from extensions.attire.kinds import (
    BISHOP_SLEEVE,
    CLOSED,
    FITTED_SLEEVE,
    FRONT_ONLY,
    OPEN_BELOW,
    OPEN_FRONT,
    PUFFED_SHOULDER,
    ROUND_NECK,
    SCOOP_NECK,
    SLIT_NECK,
    SQUARE_NECK,
    V_NECK,
)
from extensions.attire.mesh_ops import COVER
from extensions.attire.opening import (
    KEPT,
    cut_field,
    cut_open,
    is_cut,
    neckline_field,
    opening_field,
    opening_mask,
    sleeve_lift,
    sleeve_lifts,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    NECK,
    RIGHT_FOREARM,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from tests._attire_fixtures import standing_rig, tube


def _rig() raises -> HumanoidRig:
    """Return a standing rig at the template's stature: its neck at 0.5 m,
    its waist at 0.15 m, its right arm hanging at minus x."""
    var rig = standing_rig()
    rig.joints[NECK.value] = Vector3(0, 0.5, 0)
    rig.joints[SPINE.value] = Vector3(0, 0.15, 0)
    rig.joints[CHEST.value] = Vector3(0, 0.3, 0)
    rig.joints[RIGHT_UPPER_ARM.value] = Vector3(-0.2, 0.45, 0)
    rig.ends[RIGHT_UPPER_ARM.value] = Vector3(-0.22, 0.17, 0)
    rig.joints[RIGHT_FOREARM.value] = Vector3(-0.22, 0.17, 0)
    rig.ends[RIGHT_FOREARM.value] = Vector3(-0.24, -0.1, 0)
    return rig^


def test_necklines_cut_the_front_of_the_neck() raises:
    var rig = _rig()
    var throat = Vector3(0, 0.4, 0.1)
    assert_equal(neckline_field(rig, ROUND_NECK, throat), KEPT)
    # A V reaches to 17 cm under the neck, in front alone.
    assert_true(neckline_field(rig, V_NECK, throat) < 0)
    assert_true(neckline_field(rig, V_NECK, Vector3(0, 0.25, 0.1)) > 0)
    assert_true(neckline_field(rig, V_NECK, Vector3(0, 0.4, -0.1)) > 0)
    # A square neck, 22 cm wide.
    assert_true(neckline_field(rig, SQUARE_NECK, Vector3(0.05, 0.42, 0.1)) < 0)
    assert_true(neckline_field(rig, SQUARE_NECK, Vector3(0.2, 0.42, 0.1)) > 0)
    # A scoop, wide and low.
    assert_true(neckline_field(rig, SCOOP_NECK, Vector3(0, 0.45, 0.1)) < 0)
    assert_true(neckline_field(rig, SCOOP_NECK, Vector3(0, 0.3, 0.1)) > 0)
    # A slit, narrow and closing to its foot.
    assert_true(neckline_field(rig, SLIT_NECK, Vector3(0.005, 0.45, 0.1)) < 0)
    assert_true(neckline_field(rig, SLIT_NECK, Vector3(0.05, 0.45, 0.1)) > 0)
    assert_true(neckline_field(rig, SLIT_NECK, Vector3(0, 0.3, 0.1)) > 0)


def test_openings_part_the_front() raises:
    var rig = _rig()
    assert_equal(opening_field(rig, CLOSED, Vector3(0, 0, 0.1)), KEPT)
    # Open down the front, but not at the sides or behind.
    assert_true(opening_field(rig, OPEN_FRONT, Vector3(0.02, 0, 0.1)) < 0)
    assert_true(opening_field(rig, OPEN_FRONT, Vector3(0.2, 0, 0.1)) > 0)
    assert_true(opening_field(rig, OPEN_FRONT, Vector3(0.02, 0, -0.1)) > 0)
    # Open below the waist alone, the gap widening as it falls.
    assert_true(opening_field(rig, OPEN_BELOW, Vector3(0.02, 0.3, 0.1)) > 0)
    assert_true(opening_field(rig, OPEN_BELOW, Vector3(0.12, -0.3, 0.1)) < 0)
    assert_true(opening_field(rig, OPEN_BELOW, Vector3(0.12, 0.1, 0.1)) > 0)
    # The front alone.
    assert_true(opening_field(rig, FRONT_ONLY, Vector3(0, 0, 0.1)) > 0)
    assert_true(opening_field(rig, FRONT_ONLY, Vector3(0, 0, -0.1)) < 0)
    # Both cuts at once: the garment stays where both keep it.
    var p = Vector3(0.02, 0.4, 0.1)
    assert_equal(
        cut_field(rig, V_NECK, OPEN_BELOW, p),
        min(
            neckline_field(rig, V_NECK, p),
            opening_field(rig, OPEN_BELOW, p),
        ),
    )
    assert_false(is_cut(ROUND_NECK, CLOSED))
    assert_true(is_cut(V_NECK, CLOSED) and is_cut(ROUND_NECK, FRONT_ONLY))


def test_a_mask_ramps_from_the_cut() raises:
    var rig = _rig()
    # Deep in the cut, nothing; far from it, all; on its line, half.
    assert_equal(
        opening_mask(rig, ROUND_NECK, FRONT_ONLY, Vector3(0, 0, -0.5)), 0
    )
    assert_equal(
        opening_mask(rig, ROUND_NECK, FRONT_ONLY, Vector3(0, 0, 0.5)), 1
    )
    assert_almost_equal(
        opening_mask(rig, ROUND_NECK, FRONT_ONLY, Vector3(0, 0, 0.03)),
        0.5,
        atol=1e-5,
    )
    assert_equal(opening_mask(rig, ROUND_NECK, CLOSED, Vector3(0, 0, -0.5)), 1)


def test_sleeves_swell_along_the_arm() raises:
    var rig = _rig()
    var upper = RIGHT_UPPER_ARM.value
    var fore = RIGHT_FOREARM.value
    var a = rig.joints[fore]
    var bone = rig.ends[fore] - a
    var elbow = a + bone * 0.2
    var full = a + bone * 0.75
    var cuff = a + bone * 0.99
    assert_equal(sleeve_lift(rig, FITTED_SLEEVE, fore, full), 0)
    assert_equal(sleeve_lift(rig, BISHOP_SLEEVE, CHEST.value, full), 0)
    # A bishop sleeve: fullest above the wrist, gathered at the cuff.
    var at_full = sleeve_lift(rig, BISHOP_SLEEVE, fore, full)
    assert_true(at_full > sleeve_lift(rig, BISHOP_SLEEVE, fore, elbow))
    assert_true(at_full > 0.02)
    assert_equal(sleeve_lift(rig, BISHOP_SLEEVE, fore, cuff), 0)
    var shoulder = rig.joints[upper]
    var arm = rig.ends[upper] - shoulder
    assert_true(sleeve_lift(rig, BISHOP_SLEEVE, upper, shoulder + arm) > 0)
    # A puffed shoulder: round the top of the upper arm alone.
    var top = sleeve_lift(rig, PUFFED_SHOULDER, upper, shoulder + arm * 0.21)
    assert_almost_equal(top, 0.024, atol=1e-3)
    assert_equal(
        sleeve_lift(rig, PUFFED_SHOULDER, upper, shoulder + arm * 0.7), 0
    )
    assert_equal(sleeve_lift(rig, PUFFED_SHOULDER, fore, full), 0)
    # Shared by the skin weights over a skin.
    var forearm = tube(-0.23, 0, 0.04, 0.1, -0.05, RIGHT_FOREARM, 2, 6)
    for lift in sleeve_lifts(forearm, rig, BISHOP_SLEEVE):
        assert_true(lift > 0)
    var trunk = tube(0, 0, 0.15, 0.3, 0, HIPS, 2, 6)
    for lift in sleeve_lifts(trunk, rig, BISHOP_SLEEVE):
        assert_equal(lift, 0)


def test_a_skirt_s_tube_is_cut_open_and_trimmed_down_its_edges() raises:
    var rig = _rig()
    var skirt = tube(0, 0, 0.2, 0.1, -0.6, HIPS, 12, 32)
    skirt.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=skirt.vertex_count(), fill=1), 1),
    )
    var open = cut_open(skirt, rig, ROUND_NECK, OPEN_FRONT, 0.2)
    ref placed = open.attribute_view(String(POSITION))
    ref covers = open.attribute_view(String(COVER))
    var trimmed = 0
    for v in range(placed.count()):
        var p = placed.vector3(v)
        # Nothing stays in the gap down the front.
        assert_false(abs(p.x) < 0.055 and p.z > 0.05)
        if covers.component(v, 0) < 0.6:
            trimmed += 1
    assert_true(trimmed > 0)
    assert_true(open.triangle_count() < skirt.triangle_count())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
