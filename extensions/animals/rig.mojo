# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Joints, bones and poses: procedural-animals' `core/rig/`.

A species names its joints in bind pose, in meters, with forward +z, up
+y and the animal's left +x. A joint whose name ends in `L` is mirrored
to the same name ending in `R`. A bone runs from a head joint to a tail
joint and hangs from a parent bone.

A `Pose` turns bones about their head joints. Children follow their
parents. Every sculpt primitive rides one bone, so a pose moves the
primitives rigidly and the animal is meshed again in that pose. Joints
keep their volume: there is no skinning to collapse them.
"""

from extensions.sdf.ids import BoneId
from extensions.sdf.vector import (
    Rigid,
    V3,
    identity,
    mirror,
    rotation_about,
)
from std.collections import Dict
from std.math import cos, pi, sin

# The parent of a root bone.
comptime NO_BONE = BoneId(-1)


@fieldwise_init
struct Bone(Copyable, Movable):
    """One bone: a name, its two joints and its parent."""

    var name: String
    var head: String
    var tail: String
    var parent: BoneId


struct Rig(Movable):
    """The joints and bones of one animal."""

    var joint_names: List[String]
    var joint_at: Dict[String, Int]
    var joints: List[V3]
    var bones: List[Bone]

    def __init__(out self):
        """Make an empty rig."""
        self.joint_names = List[String]()
        self.joint_at = Dict[String, Int]()
        self.joints = List[V3]()
        self.bones = List[Bone]()

    def copy(self) -> Rig:
        """Return an independent copy.

        Returns:
            The copy.
        """
        var out = Rig()
        out.joint_names = self.joint_names.copy()
        out.joint_at = self.joint_at.copy()
        out.joints = self.joints.copy()
        out.bones = self.bones.copy()
        return out^

    def find_joint(self, name: String) -> Int:
        """Return the index of a joint.

        Args:
            name: The joint's name.

        Returns:
            Its index, or -1 if the rig has no such joint.
        """
        return self.joint_at.get(name, -1)

    def set(mut self, name: String, p: V3):
        """Place a joint, adding it when it is new.

        Args:
            name: The joint's name.
            p: Where it is, in meters.
        """
        var i = self.find_joint(name)
        if i < 0:
            self.joint_at[name] = len(self.joint_names)
            self.joint_names.append(name)
            self.joints.append(p)
        else:
            self.joints[i] = p

    def j(self, name: String) raises -> V3:
        """Return where a joint is.

        Args:
            name: The joint's name.

        Returns:
            Its position in meters.

        Raises:
            Error: If the rig has no such joint.
        """
        var i = self.find_joint(name)
        if i < 0:
            raise Error("The rig has no joint " + name)
        return self.joints[i]

    def mirror_joints(mut self):
        """Add the right-side copy of every left joint the rig lacks.

        A name ending in `L` gives the same name ending in `R`, with `x`
        negated.
        """
        var count = len(self.joint_names)
        for i in range(count):
            var name = self.joint_names[i]
            if not name.endswith("L"):
                continue
            var right = String(name[byte = : name.byte_length() - 1]) + "R"
            if self.find_joint(right) < 0:
                self.set(right, mirror(self.joints[i]))

    def bone(self, name: String) raises -> BoneId:
        """Return the id of a bone.

        Args:
            name: The bone's name.

        Returns:
            Its id.

        Raises:
            Error: If the rig has no such bone.
        """
        for i in range(len(self.bones)):
            if self.bones[i].name == name:
                return BoneId(i)
        raise Error("The rig has no bone " + name)

    def add_bone(
        mut self, name: String, head: String, tail: String, parent: String
    ) raises -> BoneId:
        """Add a bone.

        Args:
            name: The bone's name.
            head: The joint it starts at.
            tail: The joint it ends at.
            parent: The bone it hangs from. Empty for a root.

        Returns:
            Its id.

        Raises:
            Error: If a joint is missing, the parent is not an earlier
                bone, or the name is taken.
        """
        _ = self.j(head)
        _ = self.j(tail)
        var up = NO_BONE if parent == "" else self.bone(parent)
        for b in self.bones:
            if b.name == name:
                raise Error("The rig already has a bone " + name)
        self.bones.append(Bone(name, head, tail, up))
        return BoneId(len(self.bones) - 1)

    def head_of(self, id: BoneId) raises -> V3:
        """Return where a bone starts.

        Args:
            id: The bone.

        Returns:
            Its head joint's position.

        Raises:
            Error: If the rig has no such bone.
        """
        self.check(id)
        return self.j(self.bones[id.value].head)

    def tail_of(self, id: BoneId) raises -> V3:
        """Return where a bone ends.

        Args:
            id: The bone.

        Returns:
            Its tail joint's position.

        Raises:
            Error: If the rig has no such bone.
        """
        self.check(id)
        return self.j(self.bones[id.value].tail)

    def check(self, id: BoneId) raises:
        """Refuse a bone id this rig does not have.

        Args:
            id: The bone.

        Raises:
            Error: If `id` is negative or past the last bone.
        """
        if not id.is_valid() or id.value >= len(self.bones):
            raise Error("Bone id names no bone of this rig")


def tail_chain(
    mut rig: Rig,
    base: String,
    angles_deg: List[Float64],
    lens: List[Float64],
    name: String = "tail",
) raises:
    """Lay a chain of joints back from a base joint.

    Joint `name0` sits on the base, and each next joint lies one length
    further back, pitched by its angle from horizontal.

    Args:
        rig: The rig to add the joints to.
        base: The joint the chain starts at.
        angles_deg: Pitch of each segment, in degrees. Up is positive.
        lens: Length of each segment, in meters.
        name: The joints' prefix.

    Raises:
        Error: If the base is missing, or the lists differ in length.
    """
    if len(angles_deg) != len(lens):
        raise Error("A tail chain needs one length per angle")
    var p = rig.j(base)
    rig.set(name + "0", p)
    for i in range(len(lens)):
        var a = angles_deg[i] * pi / 180.0
        p = V3(p.x, p.y + sin(a) * lens[i], p.z - cos(a) * lens[i])
        rig.set(name + String(i + 1), p)


def add_sided(
    mut rig: Rig, name: String, head: String, tail: String, parent: String
) raises:
    """Add a left and a right bone from one pattern.

    `{S}` in any argument becomes `L`, then `R`.

    Args:
        rig: The rig.
        name: The bone name pattern.
        head: The head joint pattern.
        tail: The tail joint pattern.
        parent: The parent bone pattern. Empty for a root.

    Raises:
        Error: If `add_bone` refuses either bone.
    """
    for side in [String("L"), String("R")]:  # pragma: no branch
        _ = rig.add_bone(
            name.replace("{S}", side),
            head.replace("{S}", side),
            tail.replace("{S}", side),
            parent.replace("{S}", side),
        )


def quadruped_bones(
    mut rig: Rig, tail_segs: Int, ears: Bool = True, jaw: Bool = True
) raises:
    """Add procedural-animals' standard quadruped skeleton.

    The axial bones are pelvis, spine1 to spine3, chest, neck1, neck2,
    head and jaw. Each front leg is scapula, humerus, radius, metacarpus
    and fpaw. Each hind leg is femur, tibia, metatarsus and hpaw.

    Args:
        rig: The rig, with its joints placed and mirrored.
        tail_segs: How many tail bones, `tail0` onward.
        ears: Whether to add an ear bone a side.
        jaw: Whether to add the lower jaw.

    Raises:
        Error: If a joint is missing.
    """
    _ = rig.add_bone("pelvis", "lumbosacral", "tailBase", "")
    _ = rig.add_bone("spine1", "lumbosacral", "lumbarMid", "pelvis")
    _ = rig.add_bone("spine2", "lumbarMid", "thoraxRear", "spine1")
    _ = rig.add_bone("spine3", "thoraxRear", "chestMid", "spine2")
    _ = rig.add_bone("chest", "chestMid", "neckBase", "spine3")
    _ = rig.add_bone("neck1", "neckBase", "neckMid", "chest")
    _ = rig.add_bone("neck2", "neckMid", "occiput", "neck1")
    _ = rig.add_bone("head", "occiput", "nose", "neck2")
    if jaw:
        _ = rig.add_bone("jaw", "jawHinge", "jawTip", "head")
    if ears:
        add_sided(rig, "ear{S}", "earBase{S}", "earTip{S}", "head")
    add_sided(rig, "scapula{S}", "scapTop{S}", "shoulder{S}", "chest")
    add_sided(rig, "humerus{S}", "shoulder{S}", "elbow{S}", "scapula{S}")
    add_sided(rig, "radius{S}", "elbow{S}", "wrist{S}", "humerus{S}")
    add_sided(rig, "metacarpus{S}", "wrist{S}", "mcp{S}", "radius{S}")
    add_sided(rig, "fpaw{S}", "mcp{S}", "ftoe{S}", "metacarpus{S}")
    add_sided(rig, "femur{S}", "hip{S}", "knee{S}", "pelvis")
    add_sided(rig, "tibia{S}", "knee{S}", "hock{S}", "femur{S}")
    add_sided(rig, "metatarsus{S}", "hock{S}", "mtp{S}", "tibia{S}")
    add_sided(rig, "hpaw{S}", "mtp{S}", "htoe{S}", "metatarsus{S}")
    for i in range(tail_segs):
        var parent = String("pelvis") if i == 0 else "tail" + String(i - 1)
        _ = rig.add_bone(
            "tail" + String(i),
            "tail" + String(i),
            "tail" + String(i + 1),
            parent,
        )


struct Pose(Movable):
    """How far each bone is turned, and where the whole animal stands.

    Each turn is about the bone's head joint, in bind space. A child bone
    rides its parent's turn first.
    """

    var local: List[Rigid]
    var root: Rigid

    def __init__(out self, bones: Int):
        """Make the bind pose.

        Args:
            bones: How many bones the rig has.
        """
        self.local = List[Rigid](length=bones, fill=identity())
        self.root = identity()

    def turn(mut self, rig: Rig, bone: String, axis: V3, angle: Float64) raises:
        """Turn one bone about its head joint, after any earlier turn.

        Args:
            rig: The rig the pose is for.
            bone: The bone's name.
            axis: The unit axis, in bind space.
            angle: How far, in radians.

        Raises:
            Error: If the rig has no such bone, or the pose is for a rig
                with another bone count.
        """
        var id = rig.bone(bone)
        if len(self.local) != len(rig.bones):
            raise Error("The pose is for another rig")
        var turn = rotation_about(rig.head_of(id), axis, angle)
        self.local[id.value] = self.local[id.value].then(turn)

    def world(self, rig: Rig) raises -> List[Rigid]:
        """Return each bone's transform from bind space to the posed world.

        Args:
            rig: The rig the pose is for.

        Returns:
            One transform per bone.

        Raises:
            Error: If the pose is for a rig with another bone count.
        """
        if len(self.local) != len(rig.bones):
            raise Error("The pose is for another rig")
        var out = List[Rigid](capacity=len(rig.bones))
        for i in range(len(rig.bones)):
            var parent = rig.bones[i].parent
            var above = self.root if parent == NO_BONE else out[parent.value]
            out.append(self.local[i].then(above))
        return out^
