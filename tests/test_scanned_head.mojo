# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the scanned head fitted over the modeled anatomy."""

from extensions.humanoid.genome import (
    Expression,
    FACE_SHAPE_1,
    FACE_SHAPES,
    Genome,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.skin.dimensions import (
    HeadHull,
    HeadSkinField,
)
from extensions.humanoid.skeleton.head.skin.scan import (
    SCAN_Y,
    SCAN_Z,
    SINK_TOP,
    ScannedHead,
    _walk,
    cap_hole,
    carry,
    fit_over,
    place,
    scan_model,
    scan_skin_mesh,
    scan_to_template,
    skin_triangles,
)
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import FOOT, Length


@fieldwise_init
struct _Ball(DistanceField, ImplicitlyCopyable):
    """A sphere at the origin; `cubed` makes its field flat near the
    surface, so a Newton step falls short."""

    var radius: Float32
    var cubed: Bool

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the sphere."""
        var d = point.length() - self.radius
        if self.cubed:
            return d * d * d
        return d


def _dims() raises -> HeadMuscleDimensions:
    """Return the six-foot male template's head."""
    return head_muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))


def test_the_scan_lands_on_the_template() raises:
    var eye = scan_to_template(Vector3(0, 0, 0))
    assert_equal(eye.y, SCAN_Y)
    assert_equal(eye.z, SCAN_Z)
    assert_equal(scan_to_template(Vector3(0.01, 0, 0)).x, 1)
    var model = scan_model()
    assert_equal(model.identities(), FACE_SHAPES)
    assert_equal(model.expressions(), 57)


def test_a_face_shape_gene_reshapes_the_scan() raises:
    var model = scan_model()
    var mean = place(_dims().head, model, 200)
    var genome = Genome().with_gene(FACE_SHAPE_1, Expression(1))
    var shaped = head_muscle_dimensions(
        HumanoidSpec(Length(6.0, FOOT), MALE, genome=genome)
    )
    var other = place(shaped.head, model, 200)
    var moved = 0
    for v in range(200):  # pragma: no branch
        if (other[v] - mean[v]).length() > 1e-4:
            moved += 1
    assert_true(moved > 100)


def test_a_mesh_is_pulled_over_a_solid() raises:
    # A square of two triangles at z = 0, facing +z, and a vertex no
    # triangle uses; the ball pokes up through its middle.
    var points: List[Vector3] = [
        Vector3(-1, -1, 0),
        Vector3(1, -1, 0),
        Vector3(1, 1, 0),
        Vector3(-1, 1, 0),
        Vector3(0, 0, 0),
        Vector3(9, 9, 9),
    ]
    var triangles: List[Int] = [0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4]
    var edges: List[Int] = [0, 1, 1, 2, 2, 3, 3, 0, 0, 4, 1, 4, 2, 4, 3, 4]
    fit_over(points, triangles, edges, _Ball(0.5, False), 6, 0.01, -9, -8, 0.1)
    # The middle is pushed out to the ball and a margin, the corners are
    # pulled a little, and the stray vertex does not move.
    assert_true(points[4].z >= 0.5)
    assert_true(points[0].z > 0)
    assert_equal(points[5].z, 9)
    # Only the vertices before the end move.
    var still: List[Vector3] = [
        Vector3(-1, -1, 0),
        Vector3(1, -1, 0),
        Vector3(0, 0, 0),
    ]
    var one: List[Int] = [0, 1, 2]
    var sides: List[Int] = [0, 1, 1, 2, 2, 0]
    fit_over(still, one, sides, _Ball(0.5, False), 2, 0.01, -9, -8, 0.1)
    assert_equal(still[2].z, 0)
    # In the sinking band a mesh is pulled in, to lie where the margin
    # outside and the sink inside blend: here, halfway.
    var high: List[Vector3] = [
        Vector3(-1, -1, 1),
        Vector3(1, -1, 1),
        Vector3(1, 1, 1),
        Vector3(-1, 1, 1),
        Vector3(0, 0, 1),
    ]
    fit_over(high, triangles, edges, _Ball(0.5, False), 5, 0.01, -5, 5, 0.1)
    assert_true(abs(high[4].z - 0.455) < 1e-3)


def test_a_mesh_follows_its_coarse_copy() raises:
    # Two coarse vertices move; the vertex between them follows halfway,
    # and a vertex on one follows it whole.
    var before: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    ]
    var after: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(1, 0, 3),
        Vector3(0, 1, 0),
    ]
    var points: List[Vector3] = [Vector3(0.5, 0, 0), Vector3(1, 0, 0)]
    var followed: List[Int] = [0, 1, 2, 1, 1, 1]
    var weights: List[Float32] = [0.5, 0, 0, 0]
    carry(points, followed, weights, before, after)
    assert_equal(points[0].z, 2)
    assert_equal(points[1].z, 3)


def test_a_hole_is_capped_above_the_floor() raises:
    var points: List[Vector3] = [
        Vector3(0, 1, 0),
        Vector3(1, 1, 0),
        Vector3(0, 1, 1),
    ]
    var triangles = List[Int]()
    var loop: List[Int] = [0, 1, 2]
    cap_hole(points, triangles, loop, 2.0)
    assert_equal(len(points), 3)
    assert_equal(len(triangles), 0)
    cap_hole(points, triangles, loop, 0.0)
    assert_equal(len(points), 4)
    assert_equal(len(triangles), 9)
    # The fan runs each edge backward, to the hub.
    assert_equal(triangles[0], 1)
    assert_equal(triangles[1], 0)
    assert_equal(triangles[2], 3)


def test_a_point_walks_onto_a_surface() raises:
    var low = Vector3(-5, -5, -5)
    var high = Vector3(5, 5, 5)
    var exact = _walk(_Ball(1, False), Vector3(0, 3, 0), low, high, 1e-3)
    assert_true(abs(exact.y - 1) < 1e-4)
    # A flat field takes several passes, and may still fall short.
    var flat = _walk(_Ball(1, True), Vector3(0, 3, 0), low, high, 1e-3)
    assert_true(flat.y < 3 and flat.y > 1)


def test_the_scanned_head() raises:
    var dims = _dims()
    var skin = HeadSkinField(dims)
    var scan = skin.scan.copy()
    var h = dims.head.copy()
    # Far below the floor or off the box the bound is large; inside the
    # head it is zero.
    assert_true(scan.bound(h.at(0, 30.0, 0)) > 0.1)
    assert_equal(scan.bound(h.at(0, 72.0, 0)), 0)
    assert_true(scan.distance(h.at(0, 72.0, 0)) < 0)
    assert_true(scan.distance(h.at(0, 72.0, 30.0)) > 0)
    # The ears reach out past the side of the head.
    assert_true(scan.ears.high.x > h.at(7.4, 71.0, 0).x)
    # The scan covers the vault and the neck; toward its floor it sinks
    # into the neck, and at the floor lies inside it.
    var hull = HeadHull(h)
    var rise = h.at(0, SINK_TOP, 0).y
    var inside = 0
    var sunk = 0
    for v in range(scan.mesh.count()):  # pragma: no branch
        var p = scan.mesh.point(v)
        if p.y > rise and hull.distance(p) < -h.cm(0.1):
            inside += 1
        if abs(p.y - scan.floor) < h.cm(0.6) and hull.distance(p) < 0:
            sunk += 1
    assert_equal(inside, 0)
    assert_true(sunk > 0)
    # On a field whose surface lies above the whole box, no vertex of the
    # skin can be walked onto it: each is lost, with its triangles. Only
    # the sockets, which are not walked, are left.
    var model = scan_model()
    var rough = scan_skin_mesh(
        _Ball(skin.high.y + 1, False),
        scan,
        model,
        skin.low.y,
        skin.low,
        skin.high,
        skin.epsilon,
    )
    assert_true(rough.triangle_count() > 0)
    assert_true(rough.triangle_count() * 3 < len(skin_triangles(model)) // 5)
    # The skin's mesh reaches down to the floor asked for, and no part
    # of it lies above the crown.
    with assert_raises(contains="above the floor"):
        _ = scan_skin_mesh(
            skin,
            scan,
            scan_model(),
            skin.high.y + 1,
            skin.low,
            skin.high,
            skin.epsilon,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
