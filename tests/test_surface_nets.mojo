# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the sculpting kit and the surface-nets skin mesher."""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.sculpt import Sculpt
from extensions.humanoid.skeleton.surface_nets import (
    mesh_surface,
    surface_gradient,
)
from math.vector3 import Vector3
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


@fieldwise_init
struct _Ball(Copyable, DistanceField, Movable):
    """A sphere of radius `r` at the origin."""

    var r: Float32

    def distance(self, point: Vector3) -> Float32:
        return point.length() - self.r


@fieldwise_init
struct _Flat(Copyable, DistanceField, Movable):
    """A field whose gradient vanishes on its zero set: x times |x|."""

    var r: Float32

    def distance(self, point: Vector3) -> Float32:
        return point.x * abs(point.x)


@fieldwise_init
struct _Steep(Copyable, DistanceField, Movable):
    """A plane at x = 0 whose field is a true distance below y = 0 and a
    hundred times too steep above it."""

    var r: Float32

    def distance(self, point: Vector3) -> Float32:
        if point.y > 0:
            return point.x * 100
        return point.x


def _ball_mesh(workers: Int) raises -> BufferGeometry:
    return mesh_surface(
        _Ball(0.1),
        Vector3(-0.1, -0.1, -0.1),
        Vector3(0.1, 0.1, 0.1),
        8,
        "ball",
        workers,
    )


def test_a_ball_meshes_onto_its_surface() raises:
    var mesh = _ball_mesh(1)
    assert_true(mesh.triangle_count() > 200)
    ref points = mesh.attribute_view(String(POSITION))
    ref normals = mesh.attribute_view(String(NORMAL))
    for index in range(points.count()):  # pragma: no branch
        var p = points.vector3(index)
        assert_true(abs(p.length() - 0.1) < 0.0005)
        var n = normals.vector3(index)
        assert_true(abs(n.length() - 1) < 0.001)
        # The normal points out.
        assert_true(n.dot(p) > 0)
    # The seam at the back is split: some u lie past one.
    ref uvs = mesh.attribute_view(String(UV))
    var past = 0
    for index in range(uvs.count()):  # pragma: no branch
        if uvs.component(index, 0) > 1:
            past += 1
    assert_true(past > 0)


def test_threads_make_the_same_mesh() raises:
    var one = _ball_mesh(1)
    var four = _ball_mesh(4)
    var every = _ball_mesh(0)
    assert_equal(one.triangle_count(), four.triangle_count())
    assert_equal(one.triangle_count(), every.triangle_count())
    ref a = one.attribute_view(String(POSITION))
    ref b = four.attribute_view(String(POSITION))
    for index in range(a.count()):  # pragma: no branch
        assert_true((a.vector3(index) - b.vector3(index)).length() < 1e-7)


def test_the_mesher_refuses_what_it_cannot_mesh() raises:
    with assert_raises(contains="at least eight"):
        _ = mesh_surface(
            _Ball(0.1), Vector3(-1, -1, -1), Vector3(1, 1, 1), 7, "ball"
        )
    # A box that holds none of the surface.
    with assert_raises(contains="no surface"):
        _ = mesh_surface(
            _Ball(0.1), Vector3(1, 1, 1), Vector3(1.2, 1.2, 1.2), 8, "ball"
        )


def test_odd_fields_still_mesh() raises:
    # Where the gradient vanishes, a vertex stays where it was guessed.
    var flat = mesh_surface(
        _Flat(0), Vector3(-0.1, -0.1, -0.1), Vector3(0.1, 0.1, 0.1), 8, "flat"
    )
    assert_true(flat.triangle_count() > 0)
    # Where the field overstates its distance, the blocks there are
    # skipped, and the quads that would need them are left out.
    var steep = mesh_surface(
        _Steep(0), Vector3(-0.1, -0.1, -0.1), Vector3(0.1, 0.1, 0.1), 8, "steep"
    )
    assert_true(steep.triangle_count() > 0)
    ref points = steep.attribute_view(String(POSITION))
    for index in range(points.count()):  # pragma: no branch
        assert_true(points.vector3(index).y < 0.02)


def test_the_gradient_of_a_ball_points_out() raises:
    var g = surface_gradient(_Ball(0.1), Vector3(0.2, 0, 0), 0.001)
    assert_true(abs(g.x - 1) < 0.01)
    assert_true(abs(g.y) < 0.01 and abs(g.z) < 0.01)


def test_sculpt_joins_and_carves() raises:
    var clay = Sculpt(0.01, 0.005)
    assert_true(clay.distance(Vector3(0, 0, 0)) > 1e30)
    clay.ellipsoid(Vector3(0, 0, 0), Vector3(0.1, 0.05, 0.05))
    clay.capsule(Vector3(0.2, 0, 0), Vector3(0.3, 0, 0), 0.02, 0.01)
    # Inside the ellipsoid, and outside it along its short axis.
    assert_true(clay.distance(Vector3(0.05, 0, 0)) < 0)
    assert_true(abs(clay.distance(Vector3(0, 0.05, 0))) < 0.002)
    assert_true(clay.distance(Vector3(0.25, 0, 0)) < 0)
    # Far from every piece, each is skipped and the result is huge.
    assert_true(clay.union(Vector3(5, 5, 5)) > 1)
    # Turned: an ellipsoid long along z when asked to face x.
    var turned = Sculpt(0.01, 0.005)
    turned.ellipsoid(
        Vector3(0, 0, 0),
        Vector3(0.02, 0.02, 0.1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    )
    assert_true(turned.distance(Vector3(0.08, 0, 0)) < 0)
    assert_true(turned.distance(Vector3(0, 0, 0.08)) > 0)
    assert_true(turned.distance(Vector3(0, 0, 0)) < 0)
    # A chain, a carved hollow and a carved capsule.
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 0.1, 0),
        Vector3(0, 0.2, 0),
    ]
    var radii: List[Float32] = [0.03, 0.03, 0.03]
    var chain = Sculpt(0.005, 0.002)
    chain.chain(points, radii)
    assert_true(chain.distance(Vector3(0, 0.15, 0)) < 0)
    chain.hollow_ellipsoid(Vector3(0, 0.1, 0.03), Vector3(0.02, 0.02, 0.02))
    chain.hollow_capsule(
        Vector3(-0.05, 0.2, 0), Vector3(0.05, 0.2, 0), 0.01, 0.01
    )
    assert_true(chain.distance(Vector3(0, 0.1, 0.025)) > 0)
    assert_true(chain.distance(Vector3(0, 0.2, 0)) > 0)
    assert_true(chain.distance(Vector3(0, 0.05, 0)) < 0)
    # A carving far from the point is skipped.
    assert_equal(chain.carved(-0.01, Vector3(0, -1, 0)), -0.01)
    assert_true(chain.low.y < 0 and chain.high.y > 0.2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
