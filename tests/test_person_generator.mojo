# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.person`, three.js's `PersonGenerator`.

The expected numbers follow from three.js r186's
`examples/jsm/generators/city/PersonGenerator.js`. A walking figure has
86 head vertices, 15 for each ear, 12 for the neck, 62 for the jacket, 24
for a sleeve, 23 for a hand and 40 for a shoe, and 66 for the trousers
once their two legs and waist are welded. A standing figure adds a bag of
24 and a handle of 20.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from generators.person import (
    Joint,
    PERSON_BAG,
    PERSON_HANDLE,
    PERSON_HEAD,
    PERSON_LEGS,
    PERSON_SHOES,
    PersonGenerator,
    Pose,
    STAND,
    WALK,
    hip_section,
    joint,
    limb_sections,
    person_geometry,
    person_hash,
    ring,
    shoe_section,
    torso_section,
)
from generators.utils import PART_ID, Vec3d
from math.matrix4 import Matrix4
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _count(geometry: BufferGeometry, id: Int) raises -> Int:
    """Return how many vertices carry a part code."""
    ref ids = geometry.attribute_view(String(PART_ID))
    var n = 0
    for i in range(ids.count()):
        n += 1 if Int(ids.component(i, 0)) == id else 0
    return n


def test_the_helpers_match_three() raises:
    """Joints, rings and sections are three.js's."""
    var j = joint(Vec3d(0, 1, 0), 1, 0, 0)
    assert_almost_equal(j.y, 0, atol=1e-12)
    var swung = joint(Vec3d(0, 0, 0), 1, pi / 2, 0)
    assert_almost_equal(swung.z, -1, atol=1e-12)
    assert_equal(len(ring(Vec3d(0, 0, 0), 1, 1, 0, 0)), 0)
    assert_equal(len(limb_sections(List[Joint](), 4, 0)), 0)
    var points = ring(Vec3d(0, 2, 0), 1, 0.5, 4, 0)
    assert_equal(len(points), 4)
    assert_almost_equal(points[1].z, 0.5, atol=1e-12)
    assert_equal(len(torso_section(1, 0.2, 0.1)), 8)
    assert_equal(len(shoe_section(0, 0.05, 0)), 6)
    var left = hip_section(-1)
    var right = hip_section(1)
    assert_equal(len(left), 7)
    assert_equal(left[0].x, 0)
    assert_equal(left[0].y, 0.82)
    # The right leg's ring runs backward, so the two meet at the crotch.
    assert_equal(right[0].x, 0)
    assert_equal(right[0].z, -0.05)
    assert_almost_equal(left[3].x, -0.186, atol=1e-12)
    assert_almost_equal(right[3].x, 0.186, atol=1e-12)


def test_limb_rings_follow_the_limb() raises:
    """A ring of a straight limb lies across it: a limb along -y keeps
    its rings flat, a limb along +z stands them up."""
    var down: List[Joint] = [
        Joint(Vec3d(0, 1, 0), 0.1, 0.1),
        Joint(Vec3d(0, 0, 0), 0.1, 0.1),
    ]
    var flat = limb_sections(down, 4, 0)
    assert_almost_equal(flat[0][0].x, 0.1, atol=1e-12)
    assert_almost_equal(flat[0][0].y, 1, atol=1e-12)
    var up: List[Joint] = [
        Joint(Vec3d(0, 0, 0), 0.1, 0.1),
        Joint(Vec3d(0, 1, 0), 0.1, 0.1),
    ]
    var flipped = limb_sections(up, 4, 0)
    assert_almost_equal(flipped[1][0].y, 1, atol=1e-12)


def test_figures_match_three() raises:
    """The two poses have three.js's parts, a crown at 1.75 and soles on
    the ground."""
    var walk = person_geometry(WALK, Length(1.75, METER))
    assert_equal(walk.vertex_count(), 86 + 30 + 12 + 62 + 2 * (24 + 23 + 40) + 66)
    assert_equal(_count(walk, PERSON_HEAD.value), 86)
    assert_equal(_count(walk, PERSON_SHOES.value), 80)
    assert_equal(_count(walk, PERSON_LEGS.value), 66)
    assert_equal(_count(walk, PERSON_BAG.value), 0)
    var bounds = walk.bounding_box()
    assert_almost_equal(bounds.max.y, 1.75, atol=1e-5)
    var stand = person_geometry(STAND, Length(1.75, METER))
    assert_equal(stand.vertex_count(), walk.vertex_count() + 24 + 20)
    assert_equal(_count(stand, PERSON_BAG.value), 24)
    assert_equal(_count(stand, PERSON_HANDLE.value), 20)
    assert_almost_equal(stand.bounding_box().max.y, 1.75, atol=1e-5)
    var tall = person_geometry(WALK, Length(1.9, METER))
    assert_almost_equal(tall.bounding_box().max.y, 1.9, atol=1e-5)


def test_the_crowd_is_dealt_as_three() raises:
    """Poses and proportions come from three hashes of the index."""
    assert_equal(person_hash(1, 2654435761), 0.761)
    assert_equal(person_hash(3, 2654435761), 0.987)
    var moved = Matrix4()
    moved.elements[12] = 4
    var placements: List[Matrix4] = [Matrix4(), moved, Matrix4(), Matrix4()]
    var crowd = PersonGenerator().build(placements)
    assert_equal(len(crowd), 2)
    assert_equal(crowd[0].name, "People")
    assert_equal(crowd[0].count(), 2)
    assert_equal(crowd[1].count(), 2)
    assert_equal(crowd[0].values[0], 0)
    assert_equal(crowd[0].values[1], 2)
    assert_equal(crowd[1].values[0], 1)
    assert_equal(crowd[1].values[1], 3)
    var second = crowd[1].matrices[0]
    assert_almost_equal(second.elements[0], 1.02155 * 1.0602, atol=1e-6)
    assert_almost_equal(second.elements[5], 1.02155, atol=1e-6)
    assert_equal(second.elements[12], 4)
    assert_true(crowd[0].cast_shadow)
    var none = PersonGenerator().build(List[Matrix4]())
    assert_false(none[0].visible())


def test_a_bad_pose_or_height_is_refused() raises:
    """Only walking and standing figures of a positive height."""
    assert_false(Pose(2).is_valid())
    with assert_raises(contains="pose"):
        _ = person_geometry(Pose(2), Length(1.75, METER))
    with assert_raises(contains="pose"):
        _ = person_geometry(Pose(-1), Length(1.75, METER))
    with assert_raises(contains="height"):
        _ = person_geometry(WALK, Length(0, METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
