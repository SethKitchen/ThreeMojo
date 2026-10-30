# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which parts of the body a garment covers, and where its hems lie.

A cover gives each joint of the rig a span along its bone, from a
start to an end, each a fraction of the bone's length from the joint:

- Zero to zero: the garment does not cover the skin that joint turns.
- Zero to one: it covers all of it, past both ends of the bone too.
- Zero to a fraction: it covers the skin from the joint to that point.
  A long sleeve reaches 0.9 of the forearm.
- A fraction to one: it covers the skin from that point to the bone's
  end and past it. A boot covers the shin from 0.45 down.

The cover value of a skin vertex is the sum of its skin weights, each
times its joint's reach there. The weights fall off smoothly between
two joints, so the value's iso-line at one half runs smoothly round the
limb. A garment is cut along it. Its hems are therefore clean curves,
not the edges of triangles.

A cover can leave the face open: a coif or a hood then has an oval
opening in front of the head.

This is not a three.js port. See Extensions.

    var sleeves = Cover()
    sleeves.reach_to(RIGHT_UPPER_ARM, 1)
    sleeves.reach_to(RIGHT_FOREARM, 0.9)
    var boot = Cover()
    boot.reach_to(RIGHT_SHIN, 1, start=0.45)
    var values = cover_values(skin, rig, sleeves)
"""

from std.math import sqrt

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.humanoid.rig.joints import (
    HEAD,
    JOINT_COUNT,
    NECK,
    HumanoidRig,
    Joint,
    require_joint,
)
from math.utils import clamp
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime HEM_LEVEL = Float32(0.5)
"""The level a garment is cut at."""
comptime HEM_WIDTH = Float32(0.08)
"""Over how many meters along a bone a span's end ramps from covered to
bare. The ramp is linear, and wider than a triangle of the skin, so the
cut at its middle runs along a plane across the bone."""
comptime TEMPLATE_STATURE = Float32(1.8288)
"""The template stature the face opening is sized for, in meters."""
comptime FACE_HALF_WIDTH = Float32(0.068)
"""The face opening: half its width and half its height, and how far above
the atlas its center lies, in meters on the template."""
comptime FACE_HALF_HEIGHT = Float32(0.09)
"""Half the face opening's height, in meters on the template."""
comptime FACE_RISE = Float32(0.07)
"""How far above the atlas the face opening's center lies, in meters on the
template."""
comptime FACE_RAMP = Float32(0.2)
"""Over what share of the opening's size the edge ramps."""


struct Cover(Copyable, Movable):
    """How far a garment reaches over each joint's skin."""

    var starts: List[Float32]
    """Where the span of each joint starts, zero through one."""
    var ends: List[Float32]
    """Where the span of each joint ends, zero through one."""
    var face_open: Bool
    """Whether the head and neck are left open in front of the face."""

    def __init__(out self):
        """Cover nothing."""
        self.starts = List[Float32](length=JOINT_COUNT, fill=0)
        self.ends = List[Float32](length=JOINT_COUNT, fill=0)
        self.face_open = False

    def reach_to(
        mut self, joint: Joint, end: Float32 = 1, start: Float32 = 0
    ) raises:
        """Set the span a garment covers along one joint's bone.

        Args:
            joint: A named joint.
            end: Where the span ends, as a fraction of the bone.
            start: Where it starts. Zero by default.

        Raises:
            Error: If `joint` is not named, or zero, `start`, `end` and
                one are not in that order.
        """
        require_joint(joint)
        if not (start >= 0 and start <= end and end <= 1):
            raise Error("A span must run from zero through one, start first")
        self.starts[joint.value] = start
        self.ends[joint.value] = end

    def covers(self, joint: Joint) raises -> Bool:
        """Return whether the garment covers any of a joint's skin.

        Args:
            joint: A named joint.

        Returns:
            True when the joint's span is longer than nothing.

        Raises:
            Error: If `joint` is not named.
        """
        require_joint(joint)
        return self.ends[joint.value] > self.starts[joint.value]


def cover_of(joints: List[Joint]) raises -> Cover:
    """Return a cover that reaches over all of each joint's skin.

    Args:
        joints: Named joints.

    Returns:
        The cover.

    Raises:
        Error: If a joint is not named.
    """
    var cover = Cover()
    for joint in joints:
        cover.reach_to(joint, 1)
    return cover^


def _ramp(value: Float32) -> Float32:
    """Return `value` plus one half, clamped to zero through one."""
    return clamp(value + 0.5, 0, 1)


def joint_cover(
    rig: HumanoidRig, cover: Cover, joint: Int, p: Vector3
) raises -> Float32:
    """Return how far the garment covers one joint's skin at a point.

    Args:
        rig: The rig the skin is bound to.
        cover: The garment's cover.
        joint: The joint's index.
        p: The point, in the pelvis frame.

    Returns:
        Zero through one.

    Raises:
        Error: If `joint` is not a joint's index.
    """
    if joint < 0 or joint >= JOINT_COUNT:
        raise Error("A skin weight names a bone the rig does not have")
    var start = cover.starts[joint]
    var end = cover.ends[joint]
    var value = Float32(1)
    if end <= start:
        value = 0
    elif start > 0 or end < 1:
        var a = rig.joints[joint]
        var bone = rig.ends[joint] - a
        var length = bone.length()
        var along = (p - a).dot(bone) / max(length, Float32(1e-6))
        if end < 1:
            value = _ramp((end * length - along) / HEM_WIDTH)
        if start > 0:
            value = min(value, _ramp((along - start * length) / HEM_WIDTH))
    if cover.face_open and (joint == HEAD.value or joint == NECK.value):
        value *= face_opening(rig, p)
    return value


def face_oval(rig: HumanoidRig, p: Vector3) -> Float32:
    """Return how far a point lies outside the face's opening.

    The opening is an oval in front of the head. It is sized for the
    template's stature and scaled with the rig's. The value is not
    clamped, so a cut along its zero runs smoothly through triangles
    larger than the opening's ramp.

    Args:
        rig: The rig.
        p: The point, in the pelvis frame.

    Returns:
        Zero on the oval, negative inside it, in the oval's half sizes.
        One behind the head's joint, where there is no opening.
    """
    var head = rig.joints[HEAD.value]
    if p.z <= head.z:
        return 1
    var scale = rig.stature / TEMPLATE_STATURE
    var dx = (p.x - head.x) / (FACE_HALF_WIDTH * scale)
    var dy = (p.y - head.y - FACE_RISE * scale) / (FACE_HALF_HEIGHT * scale)
    return sqrt(dx * dx + dy * dy) - 1


def face_opening(rig: HumanoidRig, p: Vector3) -> Float32:
    """Return one away from the face and zero inside its opening.

    Args:
        rig: The rig.
        p: The point, in the pelvis frame.

    Returns:
        Zero inside the opening, one outside it, and a ramp between.
    """
    return _ramp(face_oval(rig, p) / FACE_RAMP)


def cover_values(
    skin: BufferGeometry, rig: HumanoidRig, cover: Cover
) raises -> List[Float32]:
    """Return the cover value of each vertex of a skinned mesh.

    Args:
        skin: A mesh with positions and four skin weights a vertex.
        rig: The rig it is bound to.
        cover: The garment's cover.

    Returns:
        One value per vertex, zero through one. The garment is cut at
        `HEM_LEVEL`.

    Raises:
        Error: If the mesh has no positions or skin weights, or a weight
            names a bone the rig does not have.
    """
    ref points = skin.attribute_view(String(POSITION))
    ref bones = skin.attribute_view(String(SKIN_INDEX))
    ref weights = skin.attribute_view(String(SKIN_WEIGHT))
    var values = List[Float32](capacity=points.count())
    for v in range(points.count()):
        var p = points.vector3(v)
        var value = Float32(0)
        for k in range(4):  # pragma: no branch
            var weight = weights.component(v, k)
            if weight <= 0:
                continue
            var joint = Int(bones.component(v, k))
            value += weight * joint_cover(rig, cover, joint, p)
        values.append(value)
    return values^


def dominant_joints(skin: BufferGeometry) raises -> List[Joint]:
    """Return the joint that weighs most on each vertex.

    Args:
        skin: A mesh with four skin weights a vertex.

    Returns:
        One joint per vertex.

    Raises:
        Error: If the mesh has no skin weights.
    """
    ref bones = skin.attribute_view(String(SKIN_INDEX))
    ref weights = skin.attribute_view(String(SKIN_WEIGHT))
    var joints = List[Joint](capacity=bones.count())
    for v in range(bones.count()):
        var best = 0
        for k in range(1, 4):  # pragma: no branch
            if weights.component(v, k) > weights.component(v, best):
                best = k
        joints.append(Joint(Int(bones.component(v, best))))
    return joints^
