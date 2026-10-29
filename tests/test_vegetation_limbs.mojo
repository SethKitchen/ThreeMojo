# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Branches grown by space colonization: the crown's shape and lobes, the
growth, the thickness, and the wood's tubes."""

from core.buffer_geometry import NORMAL, POSITION
from extensions.vegetation.limbs import (
    CrownShape,
    LimbParameters,
    Lobe,
    grow_limbs,
    limb_mesh,
    unit_or_up,
)
from math.vector3 import Vector3
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length


def _sapling() -> LimbParameters:
    """Return the limbs of a small tree: a crown 3 meters across from 1.5
    meters up, in four lobes."""
    var limbs = LimbParameters()
    limbs.shape = CrownShape(
        Length(1.5, METER),
        Length(4.5, METER),
        Length(1.5, METER),
        0.5,
        4,
        Length(0.8, METER),
        0.3,
        0.1,
    )
    limbs.points = 300
    limbs.step = Length(0.15, METER)
    limbs.reach = Length(0.8, METER)
    limbs.kill = Length(0.25, METER)
    return limbs^


def _refused(shape: CrownShape, text: String) raises:
    """Assert that the shape is refused with `text`."""
    with assert_raises(contains=text):
        shape.check()


def test_a_crown_shape_is_checked() raises:
    """The default shape passes; each field out of range is refused."""
    CrownShape().check()
    var shape = CrownShape()
    shape.bottom = Length(-1.0, METER)
    _refused(shape, "bottom")
    shape = CrownShape()
    shape.top = Length(5.05, METER)
    _refused(shape, "top")
    shape = CrownShape()
    shape.radius = Length(0.0, METER)
    _refused(shape, "radius")
    shape = CrownShape()
    shape.widest = 1
    _refused(shape, "widest")
    shape = CrownShape()
    shape.lobes = 65
    _refused(shape, "lobes")
    shape = CrownShape()
    shape.lobe_size = Length(0.0, METER)
    _refused(shape, "lobe must be")
    shape = CrownShape()
    shape.ragged = 2
    _refused(shape, "raggedness")
    shape = CrownShape()
    shape.hollow = 0.95
    _refused(shape, "hollow")


def test_a_crown_is_deepest_in_its_middle() raises:
    """A smooth crown's depth is zero at its widest point on the trunk,
    one at its skin above, below and beside, and more outside."""
    var shape = CrownShape(
        Length(2.0, METER),
        Length(10.0, METER),
        Length(3.0, METER),
        0.25,
        0,
        Length(1.0, METER),
        0,
        0,
    )
    var middle = shape.middle()
    assert_almost_equal(middle.y, 4)
    assert_almost_equal(shape.depth(middle, 1), 0)
    assert_almost_equal(shape.depth(Vector3(0, 10, 0), 1), 1, atol=1e-5)
    assert_almost_equal(shape.depth(Vector3(0, 2, 0), 1), 1, atol=1e-5)
    assert_almost_equal(shape.depth(Vector3(3, 4, 0), 1), 1, atol=1e-5)
    assert_true(shape.depth(Vector3(0, 4, 5), 1) > 1)
    var ragged = shape
    ragged.ragged = 1
    var bulges = 0
    for k in range(16):
        var round = Float32(k) * 0.4
        var p = Vector3(3 * cos(round), 4, 3 * sin(round))
        if abs(ragged.depth(p, 7) - 1) > 0.02:
            bulges += 1
    assert_true(bulges > 8)


def test_lobes_spread_through_the_crown() raises:
    """A crown has as many lobes as it asks for, each in the outer part of
    its egg and of about its lobe size. A crown of no lobe has none. Lobes
    too large to keep apart still all find a place."""
    var shape = _sapling().shape
    var balls = shape.lobe_balls(3)
    assert_equal(len(balls), 4)
    for k in range(len(balls)):
        var deep = shape.depth(balls[k].center, 3)
        assert_true(deep >= 0.45 and deep <= 0.85)
        assert_true(balls[k].radius >= 0.8 * 0.75 - 1e-5)
        assert_true(balls[k].radius <= 0.8 * 1.25 + 1e-5)
    var smooth = shape
    smooth.lobes = 0
    assert_equal(len(smooth.lobe_balls(3)), 0)
    var crowded = shape
    crowded.lobes = 12
    crowded.lobe_size = Length(3.0, METER)
    assert_equal(len(crowded.lobe_balls(3)), 12)


def test_a_point_holds_inside_a_lobe_and_out_of_the_hollow() raises:
    """With no lobe a point holds inside the egg. With lobes it holds only
    inside one, and a lobe can bulge past the egg. A point in the hollow
    never holds, and raggedness carves gaps."""
    var shape = CrownShape(
        Length(2.0, METER),
        Length(6.0, METER),
        Length(2.0, METER),
        0.5,
        0,
        Length(1.0, METER),
        0,
        0.3,
    )
    var none = List[Lobe]()
    assert_true(shape.holds(Vector3(1.5, 4, 0), none, 1))
    assert_false(shape.holds(Vector3(2.5, 4, 0), none, 1))
    assert_false(shape.holds(Vector3(0, 4, 0), none, 1))
    var lobes: List[Lobe] = [Lobe(Vector3(2, 4, 0), 0.8)]
    assert_true(shape.holds(Vector3(2.5, 4, 0), lobes, 1))
    assert_false(shape.holds(Vector3(-1.5, 4, 0), lobes, 1))
    assert_false(shape.holds(Vector3(3.5, 4, 0), lobes, 1))
    var ragged = shape
    ragged.ragged = 1
    var held = 0
    for k in range(40):
        var p = Vector3(
            1.2 + Float32(k % 5) * 0.12, 3 + Float32(k // 5) * 0.25, 0
        )
        if ragged.holds(p, none, 1):
            held += 1
    assert_true(held > 0)
    assert_true(held < 40)


def _limbs_refused(limbs: LimbParameters, text: String) raises:
    """Assert that the limbs are refused with `text`."""
    with assert_raises(contains=text):
        limbs.check()


def test_limb_parameters_are_checked() raises:
    """The default limbs pass; each field out of range is refused, and so
    is a shape that its own check refuses."""
    LimbParameters().check()
    var limbs = LimbParameters()
    limbs.shape.radius = Length(0.0, METER)
    _limbs_refused(limbs, "radius")
    limbs = LimbParameters()
    limbs.points = 0
    _limbs_refused(limbs, "points")
    limbs = LimbParameters()
    limbs.step = Length(3.0, METER)
    _limbs_refused(limbs, "step")
    limbs = LimbParameters()
    limbs.reach = Length(0.3, METER)
    _limbs_refused(limbs, "reach")
    limbs = LimbParameters()
    limbs.kill = Length(0.1, METER)
    _limbs_refused(limbs, "kill")
    limbs = LimbParameters()
    limbs.up_pull = 2
    _limbs_refused(limbs, "pull up")
    limbs = LimbParameters()
    limbs.droop = -1
    _limbs_refused(limbs, "droop")
    limbs = LimbParameters()
    limbs.fork = 1
    _limbs_refused(limbs, "fork")
    limbs = LimbParameters()
    limbs.lean = Angle(50.0, DEGREE)
    _limbs_refused(limbs, "lean")
    limbs = LimbParameters()
    limbs.bend = 2
    _limbs_refused(limbs, "bend")
    limbs = LimbParameters()
    limbs.gnarl = -1
    _limbs_refused(limbs, "gnarl")
    limbs = LimbParameters()
    limbs.tip_radius = Length(0.2, METER)
    _limbs_refused(limbs, "tip")
    limbs = LimbParameters()
    limbs.pipe = 1
    _limbs_refused(limbs, "pipe")
    limbs = LimbParameters()
    limbs.flare = 4
    _limbs_refused(limbs, "flare")


def test_limbs_grow_toward_the_points() raises:
    """The branches reach nearly every point. A parent comes before its
    children. A tip is the twig's radius and no distance from a tip; the
    root is thicker than any tip, and flares. Some branches fork."""
    var limbs = _sapling()
    var skeleton = grow_limbs(limbs)
    assert_equal(skeleton.points, 300)
    assert_true(skeleton.reached > 280)
    assert_true(skeleton.count() > 40)
    assert_true(skeleton.tips() > 5)
    assert_equal(skeleton.parent[0], -1)
    var forks = 0
    for n in range(1, skeleton.count()):
        assert_true(skeleton.parent[n] < n)
        if skeleton.first_child[n] < 0:
            assert_almost_equal(skeleton.tip_distance[n], 0)
            assert_true(skeleton.radius[n] < 0.0061)
        elif skeleton.next_sibling[skeleton.first_child[n]] >= 0:
            forks += 1
    assert_true(forks > 3)
    assert_true(skeleton.radius[0] > 4 * 0.006)
    assert_true(skeleton.radius[0] > skeleton.radius[skeleton.main_child[0]])


def test_a_trunk_climbs_to_its_fork() raises:
    """A trunk climbs past points in reach to its fork before any branch
    grows. A trunk with no fork stops at the first point in reach, well
    below that."""
    var high = _sapling()
    high.fork = 0.6
    var skeleton = grow_limbs(high)
    assert_true(
        skeleton.position[skeleton.trunk - 1].y >= 1.5 + 3.0 * 0.6 - 0.05
    )
    var low = _sapling()
    low.fork = 0
    var early = grow_limbs(low)
    assert_true(early.trunk < skeleton.trunk)
    assert_true(early.position[early.trunk - 1].y < 1.5 + 3.0 * 0.6 - 0.8)


def test_a_crown_with_no_point_grows_a_bare_pole() raises:
    """A lobe too small to catch a point leaves the crown empty. The trunk
    climbs to the crown's top and grows nothing else."""
    var limbs = _sapling()
    limbs.shape.lobes = 1
    limbs.shape.lobe_size = Length(0.1, METER)
    limbs.points = 2
    var skeleton = grow_limbs(limbs)
    assert_equal(skeleton.points, 0)
    assert_equal(skeleton.tips(), 1)
    assert_true(skeleton.position[skeleton.count() - 1].y >= 4.5)


def test_a_limb_mesh_draws_tubes_down_to_the_thinnest() raises:
    """The wood is rings of normals of unit length. Drawing only thicker
    branches draws fewer vertices. Wood thicker than the trunk, and a ring
    of too few sides, are refused."""
    var skeleton = grow_limbs(_sapling())
    var all = limb_mesh(skeleton, Length(0.001, METER), 8)
    var lean = limb_mesh(skeleton, Length(0.012, METER), 8)
    assert_true(lean.vertex_count() < all.vertex_count())
    assert_true(lean.vertex_count() > 0)
    assert_equal(len(all.index) % 3, 0)
    ref normals = all.attribute_view(String(NORMAL))
    for v in range(0, all.vertex_count(), 7):
        assert_almost_equal(normals.vector3(v).length(), 1, atol=1e-4)
    assert_true(all.has_attribute(String(POSITION)))
    with assert_raises(contains="no wood"):
        _ = limb_mesh(skeleton, Length(1.0, METER), 8)
    with assert_raises(contains="sides"):
        _ = limb_mesh(skeleton, Length(0.001, METER), 2)


def test_a_unit_vector_falls_back_to_up() raises:
    """A vector near zero has no direction, so it is taken as +y."""
    assert_almost_equal(unit_or_up(Vector3(0, 0, 0)).y, 1)
    assert_almost_equal(unit_or_up(Vector3(0, 0, 2)).z, 1)
    assert_almost_equal(unit_or_up(Vector3(3, 0, 4)).x, 0.6, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
