# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for lasts: a boot's feet closed in one smooth, convex shape."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.last import (
    LAST_RINGS,
    LAST_SECTORS,
    LAST_STAND,
    FootLast,
    foot_last,
    foot_lasts,
    foot_points,
    last_mesh,
    last_top,
    shoe,
)
from extensions.attire.mesh_ops import COVER, merge
from extensions.humanoid.rig.joints import (
    HIPS,
    LEFT_FOOT,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_SHIN,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, standing_rig, tube


def _covered(piece: BufferGeometry) raises -> BufferGeometry:
    """Return a piece with a cover value of one at every vertex."""
    var mesh = piece.clone()
    mesh.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=mesh.vertex_count(), fill=1), 1),
    )
    return mesh^


def _boots() raises -> BufferGeometry:
    """Return a shaft down each shin and a foot below each ankle, and an
    arm that hangs as low."""
    var right = merge(
        tube(-0.1, 0, 0.05, -0.6, -0.85, RIGHT_SHIN),
        tube(-0.1, 0.05, 0.05, -0.85, -0.93, RIGHT_FOOT, 2),
    )
    var left = merge(
        tube(0.1, 0, 0.05, -0.6, -0.85, RIGHT_SHIN),
        tube(0.1, 0.05, 0.05, -0.85, -0.93, LEFT_FOOT, 2),
    )
    var arm = tube(-0.3, 0, 0.04, -0.5, -0.9, RIGHT_FOREARM)
    return _covered(merge(merge(right, left), arm))


def _box() raises -> List[Vector3]:
    """Return the eight corners of a box two wide, four tall and six long,
    round the origin."""
    var corners = List[Vector3]()
    for i in range(8):
        corners.append(
            Vector3(
                Float32(2 * (i % 2) - 1),
                Float32(2 * ((i // 2) % 2) - 1) * 2,
                Float32(2 * (i // 4) - 1) * 3,
            )
        )
    return corners^


def test_a_last_reaches_above_the_ankles() raises:
    var rig = standing_rig()
    assert_almost_equal(last_top(rig), -0.83)


def test_each_foot_takes_its_own_side_below_the_top() raises:
    var rig = standing_rig()
    var boots = _boots()
    var right = foot_points(boots, rig, True)
    var left = foot_points(boots, rig, False)
    assert_true(len(right) > 4)
    assert_equal(len(right), len(left))
    # They reach up to the top, where the shell crosses it.
    var high = Float32(-10)
    for p in right:
        assert_true(p.x < 0 and p.x > -0.2)
        assert_true(p.y <= last_top(rig) + 1e-5)
        high = max(high, p.y)
    assert_almost_equal(high, last_top(rig), atol=1e-5)
    for p in left:
        assert_true(p.x > 0)
    assert_equal(len(foot_points(empty_mesh(), rig, True)), 0)
    # A shell all below the top crosses it nowhere.
    var low = tube(-0.1, 0.05, 0.05, -0.85, -0.93, RIGHT_FOOT, 2)
    var sunk = foot_points(_covered(low), rig, True)
    assert_true(len(sunk) > 0)
    for p in sunk:
        assert_true(p.y < -0.84)


def test_a_last_is_cast_onto_its_hull() raises:
    var last = foot_last(_box())
    assert_almost_equal(last.center.x, 0)
    assert_almost_equal(last.top, 2)
    assert_almost_equal(last.reach.y, 2)
    assert_almost_equal(last.reach.z, 3)
    assert_equal(len(last.normals), 12)
    assert_almost_equal(last.cast(Vector3(1, 0, 0)), 1, atol=1e-5)
    assert_almost_equal(last.cast(Vector3(0, -1, 0)), 2, atol=1e-5)
    assert_almost_equal(last.cast(Vector3(0, 0, 1)), 3, atol=1e-5)
    # Toward a corner a ray meets two faces' planes and leaves by the
    # nearer, whichever it meets first.
    var steep = Vector3(1, 4, 0) * Float32(1 / sqrt(Float32(17)))
    assert_almost_equal(last.cast(steep), 0.5 * sqrt(Float32(17)), atol=1e-4)
    var shallow = Vector3(4, 1, 0) * Float32(1 / sqrt(Float32(17)))
    assert_almost_equal(last.cast(shallow), 0.25 * sqrt(Float32(17)), atol=1e-4)
    # A last with no faces holds nothing.
    assert_equal(FootLast(Vector3(0, 0, 0), Vector3(1, 1, 1), 1).cast(steep), 0)
    # Points in one plane close nothing.
    var flat = List[Vector3]()
    for i in range(4):
        flat.append(Vector3(Float32(i % 2), 0, Float32(i // 2)))
    with assert_raises():
        _ = foot_last(flat)


def test_a_boot_has_a_last_for_each_foot() raises:
    var rig = standing_rig()
    var boots = _boots()
    var lasts = foot_lasts(boots, rig)
    assert_equal(len(lasts), 2)
    assert_true(lasts[0].center.x < 0)
    assert_true(lasts[1].center.x > 0)
    # Each reaches up to the top.
    assert_almost_equal(lasts[0].top, last_top(rig), atol=1e-5)
    # A side with fewer than four points has no last.
    var one = merge(
        tube(-0.1, 0, 0.05, -0.6, -0.85, RIGHT_SHIN),
        tube(-0.1, 0.05, 0.05, -0.85, -0.93, RIGHT_FOOT, 2),
    )
    assert_equal(len(foot_lasts(one, rig)), 1)


def test_a_last_is_meshed_smooth_and_open_at_its_top() raises:
    var rig = standing_rig()
    var boots = _boots()
    var last = foot_lasts(boots, rig)[0].copy()
    var mesh = last_mesh(last, boots)
    assert_true(mesh.triangle_count() > LAST_SECTORS * LAST_RINGS)
    assert_true(mesh.has_attribute(String(NORMAL)))
    # Its flat top is cut off level, below the hull's top.
    ref placed = mesh.attribute_view(String(POSITION))
    var highest = Float32(-1)
    var lowest = Float32(0)
    var sole = 0
    for v in range(placed.count()):
        var y = placed.vector3(v).y
        highest = max(highest, y)
        if y < lowest:
            lowest = y
            sole = v
    assert_true(highest < last.top)
    # It stands a little out of the hull below.
    assert_almost_equal(
        lowest, last.top - 2 * last.reach.y - LAST_STAND, atol=1e-4
    )
    # Each vertex takes the nearest vertex's weights: the sole the foot's.
    assert_equal(
        Int(mesh.attribute_view(String(SKIN_INDEX)).component(sole, 0)),
        RIGHT_FOOT.value,
    )
    # A shell with no vertex gives the last no weights to take.
    var bare = last_mesh(last, empty_mesh())
    assert_equal(
        Int(bare.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        HIPS.value,
    )


def test_a_boot_is_shod() raises:
    var rig = standing_rig()
    var boots = _boots()
    var lasts = foot_lasts(boots, rig)
    var shod = shoe(boots, lasts, rig)
    var cut = shoe(boots, List[FootLast](), rig)
    assert_equal(cut.triangle_count(), boots.triangle_count())
    assert_true(shod.triangle_count() > boots.triangle_count() // 2)
    # The shafts stop above the ankles, inside the lasts; the arm does
    # not.
    ref placed = shod.attribute_view(String(POSITION))
    var lowest_arm = Float32(0)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if p.x < -0.2:
            lowest_arm = min(lowest_arm, p.y)
    assert_almost_equal(lowest_arm, -0.9, atol=1e-5)
    # An empty shell keeps nothing but the lasts.
    var lasts_alone = 0
    for last in lasts:
        lasts_alone += last_mesh(last, empty_mesh()).vertex_count()
    assert_equal(shoe(empty_mesh(), lasts, rig).vertex_count(), lasts_alone)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
