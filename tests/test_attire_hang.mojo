# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for loose garments that hang from the chest."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.apparel import wizard_robe
from extensions.attire.armory import armory
from extensions.attire.garment import gambeson, gown, robe, shirt, surcoat
from extensions.attire.hang import HANG_SLOPE, hang_lifts, hangs_loose
from extensions.attire.kinds import LEATHER, OPEN_FRONT, V_NECK
from extensions.attire.tailor import ball_gown, frock_coat, laced_bodice
from extensions.humanoid.rig.joints import (
    CHEST,
    NECK,
    RIGHT_FOREARM,
    SPINE,
    HumanoidRig,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from tests._attire_fixtures import standing_rig, tube


def _rig() raises -> HumanoidRig:
    """Return a standing rig: its waist at 0.15 m, its chest at 0.3 m and
    its neck at 0.5 m, so the hang runs from 0.4 m down to 0.15 m."""
    var rig = standing_rig()
    rig.joints[SPINE.value] = Vector3(0, 0.15, 0)
    rig.joints[CHEST.value] = Vector3(0, 0.3, 0)
    rig.joints[NECK.value] = Vector3(0, 0.5, 0)
    return rig^


def _bust() raises -> BufferGeometry:
    """Return a trunk 12 cm round, bulging to 16 cm from 0.3 m to 0.34 m
    up, its rings 2 cm apart, bound to the chest."""
    var trunk = tube(0, 0, 0.12, 0.46, 0.06, CHEST, 20, 16)
    var placed = trunk.clone_attribute(String(POSITION))
    for v in range(placed.count()):
        var y = placed.component(v, 1)
        if y > 0.299 and y < 0.341:
            placed.set_component(v, 0, placed.component(v, 0) * 16 / 12)
            placed.set_component(v, 2, placed.component(v, 2) * 16 / 12)
    trunk.set_attribute(String(POSITION), placed^)
    return trunk^


def _lift_at(
    trunk: BufferGeometry, lifts: List[Float32], y: Float32
) raises -> Float32:
    """Return the most a ring of a trunk is lifted, at a height."""
    ref placed = trunk.attribute_view(String(POSITION))
    var most = Float32(0)
    for v in range(placed.count()):
        if abs(placed.vector3(v).y - y) < 1e-3:
            most = max(most, lifts[v])
    return most


def test_loose_garments_hang_and_fitted_ones_do_not() raises:
    for garment in [robe(), wizard_robe(), gown(), surcoat()]:
        assert_true(hangs_loose(garment))
    # Not skirted, armor, padded, open, or cut low at the neck.
    for garment in [shirt(), gambeson(), frock_coat(), ball_gown()]:
        assert_false(hangs_loose(garment))
    assert_false(hangs_loose(laced_bodice()))
    for garment in armory():
        assert_false(hangs_loose(garment))
    var leather = robe()
    leather.fabric = LEATHER
    assert_false(hangs_loose(leather))
    var open = robe()
    open.opening = OPEN_FRONT
    assert_false(hangs_loose(open))
    var low = robe()
    low.neckline = V_NECK
    assert_false(hangs_loose(low))


def test_cloth_falls_from_the_widest_point_above() raises:
    var rig = _rig()
    var trunk = _bust()
    var lifts = hang_lifts(trunk, rig)
    assert_equal(len(lifts), trunk.vertex_count())
    # Above the bust and on it, the cloth lies on the trunk.
    assert_almost_equal(_lift_at(trunk, lifts, 0.38), 0, atol=1e-5)
    assert_almost_equal(_lift_at(trunk, lifts, 0.32), 0, atol=1e-5)
    # Just under it, the cloth falls nearly straight.
    assert_almost_equal(
        _lift_at(trunk, lifts, 0.28), 0.04 - HANG_SLOPE * 0.02, atol=2e-3
    )
    # It fades back to the body toward the waist, and does nothing below
    # the waist or above the span.
    assert_true(_lift_at(trunk, lifts, 0.18) < _lift_at(trunk, lifts, 0.26))
    assert_almost_equal(_lift_at(trunk, lifts, 0.1), 0, atol=1e-6)
    assert_almost_equal(_lift_at(trunk, lifts, 0.44), 0, atol=1e-6)


def test_an_arm_beside_the_trunk_is_not_lifted() raises:
    var rig = _rig()
    var trunk = _bust()
    var bones = trunk.clone_attribute(String(SKIN_INDEX))
    for v in range(bones.count()):
        bones.set_component(v, 0, Float32(RIGHT_FOREARM.value))
    trunk.set_attribute(String(SKIN_INDEX), bones^)
    for lift in hang_lifts(trunk, rig):
        assert_equal(lift, 0)
    # A rig whose chest is not above its waist hangs nothing.
    var flat = standing_rig()
    for lift in hang_lifts(_bust(), flat):
        assert_equal(lift, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
