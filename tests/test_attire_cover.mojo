# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for what a garment covers and where its hems lie.

The line rig's joint j stands at x = j, its bone one meter straight
down, so a point's place along a bone is minus its height.
"""

from extensions.attire.cover import (
    FACE_RISE,
    HEM_LEVEL,
    HEM_WIDTH,
    Cover,
    cover_of,
    cover_values,
    dominant_joints,
    face_opening,
    joint_cover,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    JOINT_COUNT,
    NECK,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    Joint,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, line_rig, strip


def _at(joint: Joint, along: Float32) -> Vector3:
    """Return the point `along` meters down a joint's bone on the line rig."""
    return Vector3(Float32(joint.value), -along, 0)


def test_a_cover_takes_spans_in_order() raises:
    var cover = Cover()
    assert_false(cover.covers(HIPS))
    cover.reach_to(HIPS)
    cover.reach_to(RIGHT_SHIN, 1, 0.45)
    assert_true(cover.covers(HIPS))
    assert_true(cover.covers(RIGHT_SHIN))
    assert_equal(cover.starts[RIGHT_SHIN.value], 0.45)
    # A span of nothing covers nothing.
    cover.reach_to(CHEST, 0.3, 0.3)
    assert_false(cover.covers(CHEST))
    with assert_raises(contains="start first"):
        cover.reach_to(CHEST, 0.5, -0.1)
    with assert_raises(contains="start first"):
        cover.reach_to(CHEST, 0.2, 0.5)
    with assert_raises(contains="start first"):
        cover.reach_to(CHEST, 1.5, 0)
    with assert_raises(contains="start first"):
        cover.reach_to(CHEST, nan[DType.float32](), 0)
    with assert_raises(contains="named joint"):
        cover.reach_to(Joint(JOINT_COUNT))
    with assert_raises(contains="named joint"):
        _ = cover.covers(Joint(-1))
    var trunk = cover_of([HIPS, CHEST])
    assert_true(trunk.covers(CHEST))
    assert_false(trunk.covers(NECK))


def test_a_span_ramps_linearly_across_its_hem() raises:
    var rig = line_rig()
    var cover = Cover()
    cover.reach_to(RIGHT_FOREARM, 0.5)
    var j = RIGHT_FOREARM.value
    assert_almost_equal(
        joint_cover(rig, cover, j, _at(RIGHT_FOREARM, 0.5)), HEM_LEVEL
    )
    var quarter = HEM_WIDTH / 4
    assert_almost_equal(
        joint_cover(rig, cover, j, _at(RIGHT_FOREARM, 0.5 - quarter)),
        0.75,
        atol=1e-5,
    )
    assert_equal(joint_cover(rig, cover, j, _at(RIGHT_FOREARM, 0.1)), 1)
    assert_equal(joint_cover(rig, cover, j, _at(RIGHT_FOREARM, 0.9)), 0)
    # Above the joint, a span that starts at zero still covers.
    assert_equal(joint_cover(rig, cover, j, _at(RIGHT_FOREARM, -0.3)), 1)
    # A span from a start: bare above it, covered below it and past the
    # bone's end.
    var boot = Cover()
    boot.reach_to(RIGHT_FOREARM, 1, 0.45)
    assert_equal(joint_cover(rig, boot, j, _at(RIGHT_FOREARM, 0.2)), 0)
    assert_almost_equal(
        joint_cover(rig, boot, j, _at(RIGHT_FOREARM, 0.45)), HEM_LEVEL
    )
    assert_equal(joint_cover(rig, boot, j, _at(RIGHT_FOREARM, 1.4)), 1)
    # A band between two hems.
    var band = Cover()
    band.reach_to(RIGHT_FOREARM, 0.8, 0.2)
    assert_equal(joint_cover(rig, band, j, _at(RIGHT_FOREARM, 0.5)), 1)
    assert_equal(joint_cover(rig, band, j, _at(RIGHT_FOREARM, 0.9)), 0)
    assert_equal(joint_cover(rig, band, j, _at(RIGHT_FOREARM, 0.1)), 0)
    # Whole and none.
    assert_equal(joint_cover(rig, cover_of([HIPS]), 0, _at(HIPS, 7)), 1)
    assert_equal(joint_cover(rig, Cover(), 0, _at(HIPS, 0.5)), 0)
    with assert_raises(contains="bone the rig does not have"):
        _ = joint_cover(rig, cover, -1, Vector3(0, 0, 0))
    with assert_raises(contains="bone the rig does not have"):
        _ = joint_cover(rig, cover, JOINT_COUNT, Vector3(0, 0, 0))


def test_a_hood_leaves_the_face_open() raises:
    var rig = line_rig()
    var head = Float32(HEAD.value)
    var face = Vector3(head, FACE_RISE, 0.1)
    # Inside the oval, in front: open. Behind the head, or far out: closed.
    assert_equal(face_opening(rig, face), 0)
    assert_equal(face_opening(rig, Vector3(head, FACE_RISE, -0.1)), 1)
    assert_equal(face_opening(rig, Vector3(head + 0.5, FACE_RISE, 0.1)), 1)
    var hood = cover_of([NECK, HEAD])
    hood.face_open = True
    assert_equal(joint_cover(rig, hood, HEAD.value, face), 0)
    assert_equal(joint_cover(rig, hood, NECK.value, face), 0)
    # The opening is only in the head and the neck.
    hood.reach_to(CHEST)
    assert_equal(joint_cover(rig, hood, CHEST.value, face), 1)
    # A closed hood covers the face.
    hood.face_open = False
    assert_equal(joint_cover(rig, hood, HEAD.value, face), 1)


def test_cover_values_sum_the_weighted_joints() raises:
    var rig = line_rig()
    var mesh = strip(Float32(RIGHT_FOREARM.value), 4, RIGHT_FOREARM)
    var cover = Cover()
    cover.reach_to(RIGHT_FOREARM, 0.5)
    var values = cover_values(mesh, rig, cover)
    assert_equal(len(values), 10)
    # The rungs at y = 0, -0.25, -0.5, -0.75 and -1.
    assert_equal(values[0], 1)
    assert_equal(values[2], 1)
    assert_almost_equal(values[4], HEM_LEVEL)
    assert_equal(values[6], 0)
    # A vertex shared by two joints takes each joint's share.
    var bones = mesh.clone_attribute(String(SKIN_INDEX))
    var weights = mesh.clone_attribute(String(SKIN_WEIGHT))
    bones.set_component(0, 1, Float32(HIPS.value))
    weights.set_component(0, 0, 0.25)
    weights.set_component(0, 1, 0.75)
    mesh.set_attribute(String(SKIN_INDEX), bones^)
    mesh.set_attribute(String(SKIN_WEIGHT), weights^)
    var shared = cover_values(mesh, rig, cover_of([HIPS]))
    assert_almost_equal(shared[0], 0.75)
    var joints = dominant_joints(mesh)
    assert_equal(joints[0], HIPS)
    assert_equal(joints[1], RIGHT_FOREARM)


def test_nothing_covered_and_no_skin_give_no_values() raises:
    var bare = cover_of(List[Joint]())
    for j in range(JOINT_COUNT):
        assert_false(bare.covers(Joint(j)))
    assert_equal(len(cover_values(empty_mesh(), line_rig(), bare)), 0)
    assert_equal(len(dominant_joints(empty_mesh())), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
