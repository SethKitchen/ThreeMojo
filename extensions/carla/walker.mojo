# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's walkers: the bone control records and what a world keeps.

A walker moves as the physics tier's capsule character, driven by
`WalkerControl`. This module adds CARLA's bone control data. A client
sets bone transforms with `WalkerBoneControlIn` and reads them back with
`WalkerBoneControlOut`, and blends the set pose over the walk with
`blend_pose`. The world keeps the data for the renderer; there is no
skeleton here that the bones move.

The records are CARLA's `LibCarla/source/carla/rpc/WalkerBoneControlIn.h`,
`WalkerBoneControlOut.h`, `BoneTransformDataIn.h` and
`BoneTransformDataOut.h`, and `client/Walker.cpp`.
"""

from extensions.carla.actor import compose
from extensions.carla.physics.simulation import WalkerId
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.transform import CarlaTransform
from extensions.carla.walker_gait import WalkerGait


@fieldwise_init
struct BoneTransformDataIn(ImplicitlyCopyable, Movable):
    """A bone's name and its pose relative to its parent bone."""

    var bone_name: String
    var transform: CarlaTransform


@fieldwise_init
struct BoneTransformDataOut(ImplicitlyCopyable, Movable):
    """A bone's pose in the world, in the walker and relative to its
    parent bone, `BoneTransformDataOut`."""

    var bone_name: String
    var world: CarlaTransform
    var component: CarlaTransform
    var relative: CarlaTransform


@fieldwise_init
struct WalkerBoneControlIn(Copyable, Movable):
    """Bone poses to set, `WalkerBoneControlIn`."""

    var bone_transforms: List[BoneTransformDataIn]


@fieldwise_init
struct WalkerBoneControlOut(Copyable, Movable):
    """Bone poses read back, `WalkerBoneControlOut`."""

    var bone_transforms: List[BoneTransformDataOut]


struct WalkerRecord(Copyable, Movable):
    """What a world keeps of one walker beside its physics."""

    var physics: WalkerId
    var control: WalkerControl
    var gait: WalkerGait
    var bones: List[BoneTransformDataIn]
    # How much of the set pose shows over the walk, zero to one.
    var pose_blend: Float32

    def __init__(out self, physics: WalkerId):
        """Create a walker at rest, with no bones set.

        Args:
            physics: Its walker in the physics world.
        """
        self.physics = physics
        self.control = WalkerControl()
        self.gait = WalkerGait()
        self.bones = List[BoneTransformDataIn]()
        self.pose_blend = 0

    def set_bones(mut self, control: WalkerBoneControlIn):
        """Set bone poses, `SetBonesTransform`. A bone set again takes the
        new pose.

        Args:
            control: The bones and their poses.
        """
        for b in control.bone_transforms:
            var found = False
            for i in range(len(self.bones)):
                if self.bones[i].bone_name == b.bone_name:
                    self.bones[i] = b
                    found = True
            if not found:
                self.bones.append(b)

    def blend_pose(mut self, blend: Float32) raises:
        """Set how much of the set pose shows, `BlendPose`.

        Args:
            blend: From zero, the walk only, to one, the set pose only.

        Raises:
            Error: If the blend is not from zero to one.
        """
        if not (blend >= 0 and blend <= 1):
            raise Error("A pose blend must be from zero to one")
        self.pose_blend = blend

    def bones_out(self, walker: CarlaTransform) -> WalkerBoneControlOut:
        """Return the set bones, `GetBonesTransform`.

        With no skeleton, each bone hangs from the walker's origin: its
        pose in the walker is the one set, and its pose in the world is
        that one moved by the walker's.

        Args:
            walker: The walker's pose in the world.

        Returns:
            The bones.
        """
        var out = List[BoneTransformDataOut]()
        for b in self.bones:
            out.append(
                BoneTransformDataOut(
                    b.bone_name,
                    compose(walker, b.transform),
                    b.transform,
                    b.transform,
                )
            )
        return WalkerBoneControlOut(out^)
