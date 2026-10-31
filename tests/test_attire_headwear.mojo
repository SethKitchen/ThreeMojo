# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for hats and helmets shaped round the head."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.headwear import (
    BAND_DROP,
    HAIR_ROOM,
    TRIM,
    HeadFrame,
    _away,
    hat_mesh,
    head_frame,
    press_hair,
)
from extensions.attire.kinds import (
    CIRCLET,
    CROWN,
    FEATHERED_CAP,
    GREAT_HELM,
    HALF_HELM,
    HEADWEAR_COUNT,
    HORNED_HELM,
    NO_HEADWEAR,
    STRAW_HAT,
    WIZARD_HAT,
    Headwear,
)
from extensions.attire.mesh_ops import ACCENT, COVER, merge
from extensions.humanoid.rig.joints import HEAD, NECK, RIGHT_FOREARM
from extensions.humanoid.rig.joints import HumanoidRig
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import standing_rig, tube


def _rig() raises -> HumanoidRig:
    """Return a standing rig with its skull at 1.6 m and its neck's base at
    1.45 m."""
    var rig = standing_rig()
    rig.joints[NECK.value] = Vector3(0, 1.45, 0)
    rig.joints[HEAD.value] = Vector3(0, 1.6, 0)
    return rig^


def _head() raises -> BufferGeometry:
    """Return a head as an open tube from 1.4 m to 1.85 m, an arm beside
    it, a cover value of one at each vertex."""
    var head = tube(0, 0, 0.09, 1.85, 1.4, HEAD, 9, 16)
    var arm = tube(0.3, 0, 0.04, 1.5, 1.0, RIGHT_FOREARM)
    var mesh = merge(head, arm)
    mesh.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=mesh.vertex_count(), fill=1), 1),
    )
    return mesh^


def _frame() raises -> HeadFrame:
    """Return the frame of the tube head."""
    var found = head_frame(_head(), _rig())
    return found.take()


def _span(mesh: BufferGeometry) raises -> List[Float32]:
    """Return a mesh's lowest and highest height and widest reach from
    the vertical through the origin."""
    ref placed = mesh.attribute_view(String(POSITION))
    var low = Float32(1e9)
    var high = Float32(-1e9)
    var reach = Float32(0)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        low = min(low, p.y)
        high = max(high, p.y)
        reach = max(reach, (p.x * p.x + p.z * p.z) ** 0.5)
    return [low, high, reach]


def _accents(mesh: BufferGeometry) raises -> Int:
    """Return how many vertices take the accent dye."""
    ref marks = mesh.attribute_view(String(ACCENT))
    var count = 0
    for v in range(marks.count()):
        if marks.component(v, 0) > 0.5:
            count += 1
    return count


def _trims(mesh: BufferGeometry) raises -> Int:
    """Return how many vertices take the trim."""
    ref covers = mesh.attribute_view(String(COVER))
    var count = 0
    for v in range(covers.count()):
        if covers.component(v, 0) == TRIM:
            count += 1
    return count


def test_a_head_frame_reads_the_hull() raises:
    var frame = _frame()
    assert_true(abs(frame.top - 1.85) < 1e-4)
    assert_true(abs(frame.band() - (1.85 - BAND_DROP)) < 1e-3)
    assert_true(abs(frame.width(1.7, 0) - 0.09) < 0.005)
    var front = frame.at(1.7, 0, 0.1)
    assert_true(abs(front.z - frame.center.z - 0.1) < 1e-5)
    assert_true(abs(front.y - 1.7) < 1e-6)
    # Out of the axis, level; the axis itself looks forward.
    var away = _away(frame, Vector3(0.2, 1.7, frame.center.z))
    assert_true(abs(away.x - 1) < 1e-4)
    assert_true(_away(frame, frame.center) == Vector3(0, 0, 1))
    # A shell that reaches no higher than the neck has no head.
    var arm = tube(0.3, 0, 0.04, 1.4, 1.0, RIGHT_FOREARM)
    assert_false(head_frame(arm, _rig()))
    var bare = hat_mesh(arm, _rig(), CROWN, 0.002)
    assert_equal(bare.vertex_count(), arm.vertex_count())


def test_every_hat_is_drawn_round_the_head() raises:
    var rig = _rig()
    for k in range(1, HEADWEAR_COUNT):
        var hat = hat_mesh(_head(), rig, Headwear(k), 0.002)
        assert_true(hat.triangle_count() > 50)
        assert_true(hat.has_attribute(String(ACCENT)))
        assert_true(_trims(hat) > 0)
    with assert_raises(contains="needs a headwear kind"):
        _ = hat_mesh(_head(), rig, NO_HEADWEAR, 0.002)
    with assert_raises(contains="named one"):
        _ = hat_mesh(_head(), rig, Headwear(40), 0.002)


def test_helmets_close_over_the_head() raises:
    var rig = _rig()
    var top = Float32(1.85)
    # A great helm reaches down to the base of the neck, over the head.
    var great = _span(hat_mesh(_head(), rig, GREAT_HELM, 0.002))
    assert_true(great[0] < 1.47 and great[0] > 1.44)
    assert_true(great[1] > top)
    # A half helm stops over the brow, but its nasal reaches the nose.
    var half = _span(hat_mesh(_head(), rig, HALF_HELM, 0.002))
    assert_true(half[0] > top - 0.17 and half[0] < top - 0.12)
    assert_true(half[1] > top)
    # A horned helm's horns reach out past the helmet, and take the
    # accent.
    var horned = hat_mesh(_head(), rig, HORNED_HELM, 0.002)
    assert_true(_span(horned)[2] > half[2] + 0.08)
    assert_true(_accents(horned) > 0)
    assert_equal(_accents(hat_mesh(_head(), rig, HALF_HELM, 0.002)), 0)


def test_hats_sit_on_the_band() raises:
    var rig = _rig()
    var top = Float32(1.85)
    var band = top - BAND_DROP
    # A wizard's hat stands tall and its brim droops below the band.
    var wizard = _span(hat_mesh(_head(), rig, WIZARD_HAT, 0.003))
    assert_true(wizard[1] > band + 0.24)
    assert_true(wizard[0] < band - 0.01)
    assert_true(wizard[2] > 0.09 + HAIR_ROOM + 0.08)
    # A straw hat's crown clears the top of the head.
    var straw = _span(hat_mesh(_head(), rig, STRAW_HAT, 0.002))
    assert_true(straw[1] > top + 0.02)
    # A cap has a feather in the accent; a wizard's hat has none.
    assert_true(_accents(hat_mesh(_head(), rig, FEATHERED_CAP, 0.003)) > 0)
    assert_equal(_accents(hat_mesh(_head(), rig, WIZARD_HAT, 0.003)), 0)


def test_a_crown_has_points_and_stones() raises:
    var rig = _rig()
    var band = Float32(1.85) - BAND_DROP
    var crown = hat_mesh(_head(), rig, CROWN, 0.002)
    var circlet = hat_mesh(_head(), rig, CIRCLET, 0.002)
    assert_true(_span(crown)[1] > band + 0.06)
    assert_true(_span(circlet)[1] < band + 0.02)
    # Eight stones on a crown, one on a circlet.
    assert_equal(_accents(crown), 8 * 6)
    assert_equal(_accents(circlet), 6)


def test_a_hat_presses_the_hair_under_it() raises:
    var frame = _frame()
    var groom = HairGroom()
    var band = frame.band()
    var points: List[Vector3] = [
        # Far out over the band: drawn in.
        Vector3(0.3, band + 0.02, frame.center.z),
        # Close to the head: left.
        Vector3(0.08, band + 0.02, frame.center.z),
        # Below the band: left.
        Vector3(0.3, band - 0.05, frame.center.z),
        # At the middle: left.
        frame.center,
    ]
    var normals = List[Vector3](length=4, fill=Vector3(0, 1, 0))
    var depths = List[Float32](length=4, fill=0)
    groom.add(points, normals, depths, 1)
    assert_equal(press_hair(groom, frame), 1)
    var drawn = groom.points[0] - frame.center
    assert_true(drawn.length() < (points[0] - frame.center).length() - 0.1)
    assert_true(groom.points[1] == points[1])
    assert_true(groom.points[2] == points[2])
    assert_equal(press_hair(groom, frame), 0)
    var empty = HairGroom()
    assert_equal(press_hair(empty, frame), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
