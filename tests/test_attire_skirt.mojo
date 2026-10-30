# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for skirts: a garment hung below the hips as one tube round both
legs."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.mesh_ops import COVER, merge
from extensions.attire.skirt import (
    SKIRT_FOLDS,
    SKIRT_LEG_SHARE,
    SKIRT_SIDES,
    SkirtEnvelope,
    hang_skirt,
    hull_radii,
    leg_side,
    level_hull,
    segment_radii,
    skirt_envelope,
    skirt_hem,
    skirt_mesh,
    skirt_scale,
    skirt_top,
    slice_segments,
)
from extensions.humanoid.rig.joints import (
    HIPS,
    LEFT_THIGH,
    RIGHT_FOREARM,
    RIGHT_THIGH,
    SPINE,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, standing_rig, strip, tube

comptime CENTER = Vector3(0, 0, 0)


def _hips_and_legs(trunk_top: Float32 = 0.1) raises -> BufferGeometry:
    """Return a trunk tube round the hips and a tube down each leg, with an
    arm hanging beside the right leg."""
    var trunk = tube(0, 0, 0.16, trunk_top, -0.06, HIPS)
    var right = tube(-0.1, 0, 0.07, -0.06, -0.3, RIGHT_THIGH)
    var left = tube(0.1, 0, 0.07, -0.06, -0.3, LEFT_THIGH)
    var arm = tube(-0.3, 0, 0.04, 0.2, -0.4, RIGHT_FOREARM)
    return merge(merge(merge(trunk, right), left), arm)


def _covered(piece: BufferGeometry) raises -> BufferGeometry:
    """Return a piece with a cover value of one at every vertex."""
    var mesh = piece.clone()
    mesh.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=mesh.vertex_count(), fill=1), 1),
    )
    return mesh^


def test_an_empty_garment_slices_to_nothing() raises:
    var empty = empty_mesh()
    var legs = leg_side(empty)
    assert_equal(len(legs), 0)
    assert_almost_equal(skirt_hem(empty, legs, 0.5), 0.5)
    assert_equal(len(slice_segments(empty, legs, 0)), 0)
    assert_equal(hull_radii(List[Vector3](), CENTER)[0], 0)


def test_a_skirt_hangs_from_below_the_hips() raises:
    var rig = standing_rig()
    assert_almost_equal(skirt_scale(rig), 1)
    assert_almost_equal(skirt_top(rig), -0.03)


def test_the_arms_are_not_on_the_legs_side() raises:
    var mesh = merge(strip(0, 1, HIPS), strip(1, 1, RIGHT_FOREARM))
    mesh = merge(mesh, strip(2, 1, RIGHT_THIGH))
    # A vertex shared by two bones goes with the heavier, the second.
    var bones = mesh.clone_attribute(String(SKIN_INDEX))
    var weights = mesh.clone_attribute(String(SKIN_WEIGHT))
    bones.set_component(0, 1, Float32(RIGHT_FOREARM.value))
    weights.set_component(0, 0, 0.2)
    weights.set_component(0, 1, 0.8)
    mesh.set_attribute(String(SKIN_INDEX), bones^)
    mesh.set_attribute(String(SKIN_WEIGHT), weights^)
    var legs = leg_side(mesh)
    assert_false(legs[0])
    assert_true(legs[1])
    assert_false(legs[4])
    assert_true(legs[8])
    # The hem is the lowest trunk or leg vertex; the arm reaches lower
    # but does not count.
    var arm = merge(strip(0, 1, HIPS), tube(0.5, 0, 0.1, 0, -2, RIGHT_FOREARM))
    assert_almost_equal(skirt_hem(arm, leg_side(arm), 0.5), -1)
    # Nothing below the top: the top.
    assert_almost_equal(skirt_hem(arm, leg_side(arm), -1.5), -1.5)


def test_a_slice_crosses_the_trunk_and_legs() raises:
    var mesh = _hips_and_legs()
    var legs = leg_side(mesh)
    # Through both legs and not the arm: a segment for each of the 24
    # triangles of a band of each leg.
    var through = slice_segments(mesh, legs, -0.2)
    assert_equal(len(through), 2 * 2 * 24)
    for p in through:
        assert_almost_equal(p.y, -0.2)
        assert_true(p.x > -0.2)
    # Above the trunk: nothing.
    assert_equal(len(slice_segments(mesh, legs, 0.15)), 0)
    # The hull spans the gap between the legs.
    var hull = level_hull(through)
    assert_true(len(hull) > 4)
    var radii = hull_radii(hull, CENTER)
    assert_equal(len(radii), SKIRT_SIDES)
    # Front and back the hull bridges the legs, 0.07 m out.
    assert_almost_equal(radii[0], 0.07, atol=1e-4)
    # To the side it reaches the outside of a leg, 0.17 m out.
    assert_almost_equal(radii[SKIRT_SIDES // 4], 0.17, atol=1e-3)
    # The farthest crossing of the segments themselves misses the gap.
    var far = segment_radii(through, CENTER)
    assert_equal(far[0], 0)
    assert_almost_equal(far[SKIRT_SIDES // 4], 0.17, atol=1e-3)


def test_a_hull_keeps_its_corners() raises:
    var points = List[Vector3]()
    points.append(Vector3(1, 0, 1))
    points.append(Vector3(-1, 0, -1))
    points.append(Vector3(0, 0, 0))
    points.append(Vector3(1, 0, -1))
    points.append(Vector3(-1, 0, 1))
    # Two points share an x: they sort by z.
    points.append(Vector3(1, 0, 0))
    var hull = level_hull(points)
    assert_equal(len(hull), 4)
    var radii = hull_radii(hull, CENTER)
    assert_almost_equal(radii[0], 1)
    # Too few points to close: as they are.
    var two = List[Vector3]()
    two.append(Vector3(1, 0, 0))
    two.append(Vector3(0, 0, 1))
    assert_equal(len(level_hull(two)), 2)
    # A segment along a ray is parallel to it, and a segment beside it is
    # missed at either end.
    var along = List[Vector3]()
    along.append(Vector3(0, 0, 1))
    along.append(Vector3(0, 0, 2))
    along.append(Vector3(1, 0, 1))
    along.append(Vector3(2, 0, 1))
    along.append(Vector3(-2, 0, 1))
    along.append(Vector3(-1, 0, 1))
    assert_equal(segment_radii(along, CENTER)[0], 0)


def test_a_skirt_falls_and_flares() raises:
    var rig = standing_rig()
    var mesh = _hips_and_legs()
    var envelope = skirt_envelope(
        mesh, rig, 0.2, List[SkirtEnvelope](), 0.002, 0.001
    )
    var rings = envelope.rings()
    assert_true(rings >= 2)
    assert_almost_equal(envelope.heights[0], -0.03)
    assert_almost_equal(envelope.hem(), -0.3, atol=1e-4)
    assert_equal(len(envelope.radii), rings * SKIRT_SIDES)
    assert_equal(len(envelope.tucked), SKIRT_SIDES)
    # Each ring is at least as wide as the one above it, plus the flare.
    for k in range(1, rings):
        var drop = envelope.heights[k - 1] - envelope.heights[k]
        for side in range(SKIRT_SIDES):
            assert_true(
                envelope.radii[k * SKIRT_SIDES + side]
                >= envelope.radii[(k - 1) * SKIRT_SIDES + side]
                + 0.2 * drop
                - 1e-5
            )
    # The tucked ring lies just inside the trunk.
    assert_almost_equal(envelope.tucked[0], 0.158, atol=1e-3)
    # Between rings the radius is interpolated; outside them it is zero.
    var middle = (envelope.heights[0] + envelope.heights[1]) / 2
    var expected = (envelope.radii[0] + envelope.radii[SKIRT_SIDES]) / 2
    assert_almost_equal(envelope.radius_at(middle, 0), expected, atol=1e-5)
    assert_equal(envelope.radius_at(0.5, 0), 0)
    assert_equal(envelope.radius_at(-0.5, 0), 0)
    # A skirt over this one stands off it.
    var under = List[SkirtEnvelope]()
    under.append(envelope.copy())
    var over = skirt_envelope(mesh, rig, 0, under, 0.002, 0.001)
    for k in range(over.rings()):
        for side in range(SKIRT_SIDES):
            assert_true(
                over.radii[k * SKIRT_SIDES + side]
                >= envelope.radius_at(over.heights[k], side) + 0.003 - 1e-5
            )


def test_a_skirt_folds_deeper_toward_its_hem() raises:
    var rig = standing_rig()
    var mesh = _hips_and_legs()
    var plain = skirt_envelope(mesh, rig, 0.2, List[SkirtEnvelope](), 0, 0)
    var folded = skirt_envelope(
        mesh, rig, 0.2, List[SkirtEnvelope](), 0, 0, folds=0.01
    )
    var hem = (folded.rings() - 1) * SKIRT_SIDES
    # No fold at the top; the whole depth at the hem, on the folds'
    # crests, and none in their troughs. The folds stand only out.
    for side in range(SKIRT_SIDES):
        assert_almost_equal(folded.radii[side], plain.radii[side])
        assert_true(folded.radii[hem + side] >= plain.radii[hem + side])
    assert_almost_equal(folded.radii[hem], plain.radii[hem] + 0.01, atol=1e-5)
    var trough = SKIRT_SIDES // (2 * SKIRT_FOLDS)
    assert_almost_equal(
        folded.radii[hem + trough], plain.radii[hem + trough], atol=1e-5
    )


def test_a_short_skirt_does_not_lift_a_long_one() raises:
    var rig = standing_rig()
    var long = _hips_and_legs()
    var short = merge(
        tube(0, 0, 0.16, 0.1, -0.06, HIPS),
        tube(-0.1, 0, 0.07, -0.06, -0.1, RIGHT_THIGH),
    )
    var under = List[SkirtEnvelope]()
    under.append(skirt_envelope(short, rig, 0, List[SkirtEnvelope](), 0, 0))
    assert_true(under[0].rings() >= 2)
    var lifted = skirt_envelope(long, rig, 0, under, 0.002, 0.001)
    var free = skirt_envelope(long, rig, 0, List[SkirtEnvelope](), 0, 0)
    # Below the short skirt's hem, nothing lifts the long one: its hem is
    # as wide as its own slice, or as the ring above it, as it falls.
    var k = lifted.rings() - 1
    assert_almost_equal(
        lifted.radii[k * SKIRT_SIDES],
        max(free.radii[k * SKIRT_SIDES], lifted.radii[(k - 1) * SKIRT_SIDES]),
    )
    assert_true(lifted.radii[0] > free.radii[0])


def test_a_garment_that_ends_at_the_hips_hangs_no_skirt() raises:
    var rig = standing_rig()
    var trunk = tube(0, 0, 0.16, 0.1, -0.035, HIPS)
    var envelope = skirt_envelope(trunk, rig, 0.2, List[SkirtEnvelope](), 0, 0)
    assert_equal(envelope.rings(), 0)
    assert_almost_equal(envelope.hem(), envelope.center.y)
    assert_equal(envelope.radius_at(-0.03, 0), 0)
    var piece = _covered(trunk)
    var same = hang_skirt(piece, envelope, rig, True)
    assert_equal(same.triangle_count(), piece.triangle_count())
    with assert_raises(contains="two rings"):
        _ = skirt_mesh(envelope, piece, rig, True)


def test_a_trunk_that_ends_below_the_tuck_tucks_by_the_top_ring() raises:
    var rig = standing_rig()
    var envelope = skirt_envelope(
        _hips_and_legs(-0.02), rig, 0, List[SkirtEnvelope](), 0, 0
    )
    for side in range(SKIRT_SIDES):
        assert_almost_equal(
            envelope.tucked[side], envelope.radii[side] - 0.002, atol=1e-6
        )


def test_a_skirt_is_lofted_lined_and_weighted() raises:
    var rig = standing_rig()
    var piece = _covered(_hips_and_legs())
    var envelope = skirt_envelope(
        piece, rig, 0.2, List[SkirtEnvelope](), 0, 0.002
    )
    var rings = envelope.rings()
    var plain = skirt_mesh(envelope, piece, rig, False)
    assert_equal(plain.vertex_count(), (rings + 1) * SKIRT_SIDES)
    assert_equal(plain.triangle_count(), 2 * rings * SKIRT_SIDES)
    assert_true(plain.has_attribute(String(NORMAL)))
    var lined = skirt_mesh(envelope, piece, rig, True)
    assert_equal(lined.vertex_count(), 2 * (rings + 2) * SKIRT_SIDES)
    assert_equal(lined.triangle_count(), 2 * (2 * rings + 1) * SKIRT_SIDES)
    # The outer face looks out at the front.
    ref normals = plain.attribute_view(String(NORMAL))
    var front = SKIRT_SIDES  # The top ring's front.
    assert_true(normals.vector3(front).z > 0.5)
    # The hem's cover value is one half: a trim lies along it.
    ref covered = plain.attribute_view(String(COVER))
    assert_almost_equal(covered.component(rings * SKIRT_SIDES, 0), 0.5)
    assert_almost_equal(covered.component(0, 0), 1)
    # The top takes the trunk's weights; the hem passes to the thighs,
    # the right thigh on the right side.
    ref bones = plain.attribute_view(String(SKIN_INDEX))
    ref weights = plain.attribute_view(String(SKIN_WEIGHT))
    assert_equal(Int(bones.component(SKIRT_SIDES, 0)), HIPS.value)
    var right_side = rings * SKIRT_SIDES + 3 * SKIRT_SIDES // 4
    assert_equal(Int(bones.component(right_side, 0)), RIGHT_THIGH.value)
    assert_almost_equal(
        weights.component(right_side, 0), SKIRT_LEG_SHARE, atol=1e-5
    )
    # A mirrored rig puts the right thigh on the other side.
    var mirrored = standing_rig(0.1)
    var flipped = skirt_mesh(envelope, piece, mirrored, False)
    assert_equal(
        Int(
            flipped.attribute_view(String(SKIN_INDEX)).component(right_side, 0)
        ),
        LEFT_THIGH.value,
    )
    # A piece with no trunk or leg vertex gives the top to the hips.
    var arm = _covered(tube(0.3, 0, 0.04, 0.2, -0.4, RIGHT_FOREARM))
    var bare = skirt_mesh(envelope, arm, rig, False)
    assert_equal(
        Int(bare.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        HIPS.value,
    )
    var hollow = skirt_mesh(envelope, empty_mesh(), rig, False)
    assert_equal(
        Int(hollow.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        HIPS.value,
    )


def test_a_garment_hangs_its_skirt_below_the_top() raises:
    var rig = standing_rig()
    var piece = _covered(_hips_and_legs())
    var envelope = skirt_envelope(
        piece, rig, 0.2, List[SkirtEnvelope](), 0, 0.002
    )
    var hung = hang_skirt(piece, envelope, rig, False)
    var skirt = skirt_mesh(envelope, piece, rig, False)
    var cut = hang_skirt(piece, envelope, rig, False, shown=False)
    assert_equal(
        hung.triangle_count(), cut.triangle_count() + skirt.triangle_count()
    )
    # The shell keeps no trunk or leg vertex below the top, but keeps the
    # arm.
    ref placed = cut.attribute_view(String(POSITION))
    var lowest_leg = Float32(1)
    var lowest_arm = Float32(1)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if p.x < -0.2:
            lowest_arm = min(lowest_arm, p.y)
        else:
            lowest_leg = min(lowest_leg, p.y)
    assert_almost_equal(lowest_leg, -0.03, atol=1e-5)
    assert_almost_equal(lowest_arm, -0.4, atol=1e-5)
    # An empty piece hangs nothing it does not have.
    var empty = empty_mesh()
    assert_equal(
        hang_skirt(empty, envelope, rig, True, False).vertex_count(), 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
