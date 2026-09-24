# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Inverse kinematics by cyclic coordinate descent, from three.js
`examples/jsm/animation/CCDIKSolver.js`.

An IK chain turns a run of bones so that one bone, the effector, reaches
for another, the target. A hand reaches for a cup: the effector is the
hand, the target is a bone placed at the cup, and the links are the
forearm, the upper arm and the shoulder, from the hand inward.

CCD turns one link at a time. For each link it finds the turn that swings
the effector toward the target around that link, applies it, and moves to
the next link inward. One pass over the links is one iteration. The solver
stops early when no link turns in a whole pass.

The arithmetic is three.js's, step for step: the turn is measured in the
link's own world frame, a turn smaller than 1e-5 radians is skipped, the
turn is clamped by `min_angle` and `max_angle`, a link with a
`limitation` is turned about that axis only, and `rotation_min` and
`rotation_max` clamp its Euler angles. A chain with a `blend_factor`
below one is slerped from where it started toward the solved pose.

## What differs

The bones are scene nodes, so a chain names bones by their index in the
skinned mesh's skeleton, as three.js's does, and the solver reads and
writes the scene. three.js updates one link's world matrix after each
turn; this updates the whole scene, which gives the same numbers.

three.js checks that each link is the parent of the one before and warns
when it is not. This checks nothing about the parents, and solves what it
is given, as three.js does after the warning. `CCDIKHelper` is not ported.

A link's Euler bounds are an `Euler`, so they carry angle units and an
order. three.js clamps in the order of the link's own `rotation`; a node
here has no order of its own, so the bound's order is used.
"""

from core.object3d import NodeId
from core.scene import Scene
from math.euler import Euler
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import acos, sqrt
from units.si import Angle, RADIAN

# A turn smaller than this, in radians, is skipped, so that a link already
# on target does not tremble: three.js's `1e-5`.
comptime SMALLEST_TURN = Float32(1e-5)


@fieldwise_init
struct IkLink(Copyable, Movable):
    """One link of a chain: a bone the solver may turn."""

    # Which bone, as its index in the skeleton.
    var index: Int
    # Whether this link and the ones after it may turn: three.js's
    # `enabled`, which stops the pass at the first link switched off.
    var enabled: Bool
    # The one axis the link turns about, in its own frame, if it has one:
    # three.js's `limitation`.
    var limitation: Optional[Vector3]
    # The smallest and largest Euler angles the link may reach, if bounded:
    # three.js's `rotationMin` and `rotationMax`.
    var rotation_min: Optional[Euler]
    var rotation_max: Optional[Euler]

    def __init__(out self, index: Int):
        """Return a link that turns freely.

        Args:
            index: Which bone, as its index in the skeleton.
        """
        self.index = index
        self.enabled = True
        self.limitation = None
        self.rotation_min = None
        self.rotation_max = None


@fieldwise_init
struct IkChain(Copyable, Movable):
    """One chain to solve: three.js's entry in `iks`."""

    # The bone the effector reaches for, as its index in the skeleton.
    var target: Int
    # The bone that reaches, as its index in the skeleton.
    var effector: Int
    # The bones that turn, from the effector's parent inward.
    var links: List[IkLink]
    # How many passes over the links, at most: three.js's `iteration`.
    var iteration: Int
    # The smallest and largest turn one link makes in one step, if bounded:
    # three.js's `minAngle` and `maxAngle`.
    var min_angle: Optional[Angle]
    var max_angle: Optional[Angle]
    # How far toward the solved pose the chain moves, from zero to one, if
    # set: three.js's `blendFactor`. Unset, the solver's own blend is used.
    var blend_factor: Optional[Float32]

    def __init__(out self, target: Int, effector: Int, var links: List[IkLink]):
        """Return a chain of one pass, with no bounds and no blend.

        Args:
            target: The bone the effector reaches for.
            effector: The bone that reaches.
            links: The bones that turn, from the effector's parent inward.
        """
        self.target = target
        self.effector = effector
        self.links = links^
        self.iteration = 1
        self.min_angle = None
        self.max_angle = None
        self.blend_factor = None


struct CCDIKSolver(Movable):
    """Solves IK chains on one skinned mesh's skeleton: three.js's
    `CCDIKSolver`."""

    # Which skinned mesh, as its position in `scene.skinned_meshes`.
    var mesh: Int
    # The chains, solved in order.
    var iks: List[IkChain]

    def __init__(
        out self, scene: Scene, mesh: Int, var iks: List[IkChain]
    ) raises:
        """Bind chains to a skinned mesh.

        Args:
            scene: The scene the mesh is in.
            mesh: Which skinned mesh, as its position in
                `scene.skinned_meshes`.
            iks: The chains. Every bone they name must be in the mesh's
                skeleton.

        Raises:
            Error: If no skinned mesh has that index, a chain names a bone
                the skeleton does not have, a chain's iteration count is
                negative, or its blend factor is not from zero to one.
        """
        if mesh < 0 or mesh >= len(scene.skinned_meshes):
            raise Error("No skinned mesh has that index")
        var count = scene.skinned_meshes[mesh].bone_count()
        for chain in iks:
            _check_bone(chain.target, count)
            _check_bone(chain.effector, count)
            for link in chain.links:
                _check_bone(link.index, count)
            if chain.iteration < 0:
                raise Error("An IK chain cannot iterate a negative number")
            if Bool(chain.blend_factor):
                var blend = chain.blend_factor.value()
                if not (blend >= 0 and blend <= 1):
                    raise Error("An IK blend factor must be from zero to one")
        self.mesh = mesh
        self.iks = iks^

    def update(self, mut scene: Scene, blend: Float32 = 1) raises:
        """Solve every chain, in order, three.js's `update`.

        Args:
            scene: The scene the mesh is in, updated. It is updated again
                after each turn.
            blend: How far toward the solved pose a chain with no blend
                factor of its own moves, from zero to one: three.js's
                `globalBlendFactor`.

        Raises:
            Error: If the blend is not from zero to one, or for anything
                `update_one` raises for.
        """
        for index in range(len(self.iks)):
            self.update_one(scene, index, blend)

    def update_one(
        self, mut scene: Scene, chain: Int, blend: Float32 = 1
    ) raises:
        """Solve one chain, three.js's `updateOne`.

        Args:
            scene: The scene the mesh is in, updated.
            chain: Which chain, as its position in `iks`.
            blend: How far toward the solved pose the chain moves when it
                has no blend factor of its own.

        Raises:
            Error: If there is no such chain, the blend is not from zero to
                one, the mesh or a bone is no longer there, the scene is
                stale, or a link's world matrix flattens an axis.
        """
        if chain < 0 or chain >= len(self.iks):
            raise Error("No IK chain has that index")
        if not (blend >= 0 and blend <= 1):
            raise Error("An IK blend factor must be from zero to one")
        if self.mesh >= len(scene.skinned_meshes):
            raise Error("The IK solver's skinned mesh is not there")
        ref ik = self.iks[chain]
        var bones = scene.skinned_meshes[self.mesh].skeleton.copy()
        var share = ik.blend_factor.or_else(blend)
        var effector = bones.node(ik.effector)
        var aim = Vector3.from_matrix_position(
            scene.world_matrix(bones.node(ik.target))
        )
        var initial = List[Quaternion]()
        for link in ik.links:
            initial.append(scene.get(bones.node(link.index)).quaternion)
        for _ in range(ik.iteration):
            var rotated = False
            for link in ik.links:
                if not link.enabled:
                    break
                var node = bones.node(link.index)
                var at = Vector3(0, 0, 0)
                var facing = Quaternion.identity()
                var size = Vector3(0, 0, 0)
                scene.world_matrix(node).decompose(at, facing, size)
                facing.invert()
                var reach = Vector3.from_matrix_position(
                    scene.world_matrix(effector)
                )
                var to_effector = reach - at
                to_effector.apply_quaternion(facing)
                to_effector.normalize()
                var to_target = aim - at
                to_target.apply_quaternion(facing)
                to_target.normalize()
                # Rounding can carry the dot of two unit vectors past one.
                var cosine = max(
                    Float32(-1), min(Float32(1), to_target.dot(to_effector))
                )
                var angle = acos(cosine)
                if angle < SMALLEST_TURN:
                    continue
                if Bool(ik.min_angle):
                    angle = max(angle, ik.min_angle.value().value)
                if Bool(ik.max_angle):
                    angle = min(angle, ik.max_angle.value().value)
                var axis = to_effector
                axis.cross(to_target)
                axis.normalize()
                _turn(scene, node, link, axis, Angle(angle, RADIAN))
                scene.update()
                rotated = True
            if not rotated:
                break
        if share < 1:
            for index in range(len(ik.links)):
                var node = bones.node(ik.links[index].index)
                var solved = scene.get(node).quaternion
                scene.node(node).quaternion = initial[index].slerp(
                    solved, share
                )
            scene.update()


def _check_bone(bone: Int, count: Int) raises:
    """Refuse a bone index the skeleton does not have."""
    if bone < 0 or bone >= count:
        raise Error("An IK chain names a bone the skeleton does not have")


def _turn(
    mut scene: Scene, node: NodeId, link: IkLink, axis: Vector3, angle: Angle
) raises:
    """Turn one link by `angle` about `axis`, in its own frame, and apply
    its limitation and its Euler bounds, as three.js's `updateOne` does."""
    ref turned = scene.node(node)
    turned.quaternion.multiply(Quaternion.from_axis_angle(axis, angle))
    if Bool(link.limitation):
        var along = link.limitation.value()
        var c = min(turned.quaternion.w, 1)
        var c2 = sqrt(1 - c * c)
        turned.quaternion = Quaternion(
            along.x * c2, along.y * c2, along.z * c2, c
        )
    if Bool(link.rotation_min):
        var low = link.rotation_min.value()
        var now = turned.rotation(low.order)
        turned.set_rotation(
            Euler(
                Angle(max(now.x.value, low.x.value), RADIAN),
                Angle(max(now.y.value, low.y.value), RADIAN),
                Angle(max(now.z.value, low.z.value), RADIAN),
                low.order,
            )
        )
    if Bool(link.rotation_max):
        var high = link.rotation_max.value()
        var now = turned.rotation(high.order)
        turned.set_rotation(
            Euler(
                Angle(min(now.x.value, high.x.value), RADIAN),
                Angle(min(now.y.value, high.y.value), RADIAN),
                Angle(min(now.z.value, high.z.value), RADIAN),
                high.order,
            )
        )
