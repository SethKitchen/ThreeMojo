# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for hair that moves under gravity and the wind."""

from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.hair.collider import (
    FAR_AWAY,
    HairCollider,
)
from extensions.humanoid.skeleton.head.hair.groom import (
    HairGroom,
    follower_across,
)
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairPhysics,
    HairSimulation,
    HairWind,
)
from math.vector3 import Vector3
from std.math import max, min, sqrt
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


@fieldwise_init
struct _Ball(DistanceField, ImplicitlyCopyable):
    """A sphere at `center`; `flat` makes the field the same everywhere."""

    var center: Vector3
    var radius: Float32
    var flat: Bool

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the sphere."""
        if self.flat:
            return -1
        return (point - self.center).length() - self.radius


def _collider(flat: Bool = False) -> HairCollider:
    """Return a ball of ten centimeters at the origin, baked."""
    return HairCollider(
        _Ball(Vector3(0, 0, 0), 0.1, flat),
        Vector3(-0.2, -0.2, -0.2),
        Vector3(0.2, 0.2, 0.2),
    )


def _strand(mut groom: HairGroom, points: List[Vector3]):
    """Add a strand with upward normals and no depth."""
    var normals = List[Vector3](length=len(points), fill=Vector3(0, 1, 0))
    var depths = List[Float32](length=len(points), fill=0)
    groom.add(points, normals, depths, 1)


def _hanging(x: Float32, bent: Bool = False) -> HairGroom:
    """Return one strand of eight points hanging down from (x, 0.3, 0),
    or bending out toward plus z."""
    var groom = HairGroom()
    var points = List[Vector3]()
    for k in range(8):  # pragma: no branch
        var z = Float32(0)
        if bent:
            z = Float32(0.004) * Float32(k * k)
        points.append(Vector3(x, 0.3 - Float32(k) * 0.02, z))
    _strand(groom, points)
    return groom^


def test_the_collider_is_the_field_baked() raises:
    var collider = _collider()
    assert_true(abs(collider.distance(Vector3(0, 0, 0)) + 0.1) < 0.01)
    assert_true(abs(collider.distance(Vector3(0.15, 0, 0)) - 0.05) < 0.01)
    assert_equal(collider.distance(Vector3(0.5, 0, 0)), FAR_AWAY)
    assert_equal(collider.distance(Vector3(-0.5, 0, 0)), FAR_AWAY)
    assert_equal(collider.distance(Vector3(0, 0, -0.5)), FAR_AWAY)
    assert_equal(collider.distance(Vector3(0, -0.5, 0)), FAR_AWAY)
    assert_equal(collider.distance(Vector3(0, 0, 0.2)), FAR_AWAY)


def test_the_defaults_are_frostbittens() raises:
    var physics = HairPhysics()
    assert_equal(physics.iterations, 7)
    assert_true(abs(physics.step - Float32(1.0) / 30) < 1e-7)
    var wind = HairWind(Vector3(1, 0, 0), 0.5)
    assert_equal(wind.jitter, Float32(0.7))


def test_the_wind_blows_the_hair_and_the_root_holds() raises:
    var groom = _hanging(0.25, True)
    var still = HairSimulation(groom)
    var blown = HairSimulation(groom)
    var collider = _collider()
    for _ in range(30):  # pragma: no branch
        still.step(collider, HairWind(Vector3(1, 0, 0), 0))
        blown.step(collider, HairWind(Vector3(1, 0, 0), 1))
    assert_equal(blown.frame, 30)
    # The root never moves; the tip goes with the wind.
    assert_true(blown.now[0] == groom.points[0])
    assert_true(blown.now[7].x > still.now[7].x + 0.001)
    # Each segment keeps about its length.
    for k in range(7):  # pragma: no branch
        var length = (blown.now[k + 1] - blown.now[k]).length()
        var groomed = (groom.points[k + 1] - groom.points[k]).length()
        assert_true(abs(length - groomed) < 0.1 * groomed)
    blown.write(groom)
    assert_true(groom.points[7] == blown.now[7])
    var other = HairGroom()
    with assert_raises(contains="not the one"):
        blown.write(other)


def test_the_head_pushes_the_hair_out() raises:
    # A strand hanging straight through the ball comes out of it; one of
    # a single point stays put.
    var groom = HairGroom()
    var points = List[Vector3]()
    for k in range(6):  # pragma: no branch
        points.append(Vector3(0.02, 0.16 - Float32(k) * 0.03, 0))
    _strand(groom, points)
    var lone: List[Vector3] = [Vector3(0.3, 0.3, 0)]
    _strand(groom, lone)
    var hair = HairSimulation(groom)
    var collider = _collider()
    for _ in range(20):  # pragma: no branch
        hair.step(collider, HairWind(Vector3(1, 0, 0), 0))
    for k in range(3, 6):  # pragma: no branch
        assert_true(collider.distance(hair.now[k]) > -0.02)
    # A strand gathered at one point has no bend to keep, and with no
    # gravity it stays there.
    var still = HairPhysics()
    still.gravity = 0
    var gathered = HairGroom()
    var spot: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
    ]
    _strand(gathered, spot)
    var knot = HairSimulation(gathered, still)
    knot.step(collider, HairWind(Vector3(1, 0, 0), 0))
    assert_true(knot.now[2] == Vector3(0, 0, 0))
    # Where the field is the same everywhere it has no way out, and the
    # points are left where they are.
    var flat = HairSimulation(_hanging(0))
    flat.step(_collider(True), HairWind(Vector3(1, 0, 0), 0))
    assert_true(abs(flat.now[7].x) < 1e-6)


def _guided(bent: Bool = True) raises -> HairGroom:
    """Return one hanging guide and two followers offset from it."""
    var groom = _hanging(0.25, bent)
    var count = len(groom.points)
    for f in range(2):  # pragma: no branch
        var points = List[Vector3]()
        var across = List[Float32]()
        var up = List[Float32]()
        for k in range(count):  # pragma: no branch
            var side = Float32(0.004) * Float32(f + 1)
            var lift = Float32(0.001) * Float32(k)
            var p = groom.points[k]
            var turn = follower_across(
                groom.points[max(k - 1, 0)],
                groom.points[min(k + 1, count - 1)],
                groom.normals[k],
            )
            points.append(p + turn * side + groom.normals[k] * lift)
            across.append(side)
            up.append(lift)
        var normals = List[Vector3](length=count, fill=Vector3(0, 1, 0))
        var depths = List[Float32](length=count, fill=0)
        groom.add_follower(points, normals, depths, 1, 0, across, up)
    return groom^


def test_guides_only_moves_guides_as_the_full_step() raises:
    var groom = _guided()
    var full = HairSimulation(groom)
    var guided = HairSimulation(groom, guides_only=True)
    var collider = _collider()
    for _ in range(20):  # pragma: no branch
        full.step(collider, HairWind(Vector3(1, 0, 0), 1))
        guided.step(collider, HairWind(Vector3(1, 0, 0), 1))
    # The guide strand moves exactly as before; strands are independent.
    for k in range(8):  # pragma: no branch
        assert_true(guided.now[k] == full.now[k])
    # Each follower point keeps its groomed distance from its guide point.
    for f in range(2):  # pragma: no branch
        for k in range(8):  # pragma: no branch
            var side = Float32(0.004) * Float32(f + 1)
            var lift = Float32(0.001) * Float32(k)
            var gap = (guided.now[8 * (f + 1) + k] - guided.now[k]).length()
            assert_true(abs(gap - sqrt(side * side + lift * lift)) < 1e-5)
            assert_true(
                guided.previous[8 * (f + 1) + k] == guided.now[8 * (f + 1) + k]
            )
    # The followers moved with their guide.
    assert_true(guided.now[15].x > groom.points[15].x + 0.001)
    guided.write(groom)
    assert_true(groom.points[23] == guided.now[23])


def test_guides_only_lays_followers_where_they_were_groomed() raises:
    for bent in [False, True]:
        var groom = _guided(bent)
        var guided = HairSimulation(groom, guides_only=True)
        guided._lay_followers()
        for index in range(len(groom.points)):  # pragma: no branch
            assert_true(
                (guided.now[index] - groom.points[index]).length() < 1e-6
            )


def test_followers_need_a_matching_earlier_guide() raises:
    var groom = _guided()
    var points = List[Vector3](length=8, fill=Vector3(0, 0, 0))
    var normals = List[Vector3](length=8, fill=Vector3(0, 1, 0))
    var depths = List[Float32](length=8, fill=0)
    var offsets = List[Float32](length=8, fill=0)
    var short = List[Float32](length=7, fill=0)
    var shorter = List[Vector3](length=7, fill=Vector3(0, 1, 0))
    # A negative strand, one past the last, and a follower are no guide.
    for guide in [-1, len(groom), 1]:
        with assert_raises(contains="earlier guide"):
            groom.add_follower(
                points, normals, depths, 1, guide, offsets, offsets
            )
    with assert_raises(contains="point count"):
        groom.add_follower(shorter, shorter, short, 1, 0, short, short)
    with assert_raises(contains="point count"):
        groom.add_follower(points, shorter, depths, 1, 0, offsets, offsets)
    with assert_raises(contains="point count"):
        groom.add_follower(points, normals, short, 1, 0, offsets, offsets)
    with assert_raises(contains="point count"):
        groom.add_follower(points, normals, depths, 1, 0, short, offsets)
    with assert_raises(contains="point count"):
        groom.add_follower(points, normals, depths, 1, 0, offsets, short)
    assert_equal(len(groom), 3)


def test_guides_only_needs_matching_guide_records() raises:
    for change in range(3):
        var groom = _guided()
        if change == 0:
            _ = groom.guides.pop()
        elif change == 1:
            _ = groom.follow_across.pop()
        else:
            _ = groom.follow_up.pop()
        with assert_raises(contains="guide records"):
            _ = HairSimulation(groom, guides_only=True)
        _ = HairSimulation(groom)
    # An empty groom has no guide and no follower to lay.
    var empty = HairSimulation(HairGroom(), guides_only=True)
    empty.step(_collider(), HairWind(Vector3(1, 0, 0), 1))
    assert_equal(empty.frame, 1)
    assert_equal(len(empty.now), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
