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
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairPhysics,
    HairSimulation,
    HairWind,
)
from math.vector3 import Vector3
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
