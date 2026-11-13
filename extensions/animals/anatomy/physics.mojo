# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An animal's segments as rigid bodies for `extensions/physics`.

The sculpt is `+y` up, `+z` forward and `+x` to the animal's left. The
physics world is `+z` up. `to_physics` turns the one frame into the
other: physics `x` is the animal's forward, `y` its left and `z` up. It
is a rotation, so it keeps handedness, lengths and inertia.

Each bone with flesh becomes one dynamic body. Its frame starts at the
bone's head joint with its `+z` along the bone. A capsule along the bone
is its collision shape. Its mass, center of mass and inertia tensor are
the sampled ones, not the capsule's.

`segment_chain` puts the bodies in a `PhysicsWorld` and joins each one to
the nearest bone above it that has flesh, with a ball joint at the bone's
head. The joints have no limits and no muscles, so the chain is a limp
body and not a posed one.
"""

from extensions.anatomy.inertia import SegmentInertia
from extensions.animals.anatomy.mass import BodyMass, require_sampled_rig
from extensions.animals.build import Animal
from extensions.animals.rig import NO_BONE
from extensions.physics.body import BodyId, DYNAMIC, RigidBody, rotation_matrix
from extensions.physics.joint import JointId
from extensions.physics.shape import Shape
from extensions.physics.world import PhysicsWorld
from extensions.sdf.vector import length
from math.finite import require_non_negative_finite
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3, vector3_from_float64
from std.math import pi, sqrt
from units.measure import length_meters


def to_physics(p: Vector3) -> Vector3:
    """Turn a point or a direction from the sculpt's frame to the physics
    world's.

    Args:
        p: In the sculpt's frame: `+y` up, `+z` forward.

    Returns:
        In the physics frame: `+z` up, `+x` forward.
    """
    return Vector3(p.z, p.x, p.y)


def _tensor(s: SegmentInertia) -> Matrix3:
    # The sculpt-frame tensor, permuted into the physics frame: physics
    # axis i is sculpt axis (z, x, y)[i].
    var t = Matrix3()
    var full: List[Float32] = [
        Float32(s.xx.value),
        Float32(s.xy.value),
        Float32(s.xz.value),
        Float32(s.xy.value),
        Float32(s.yy.value),
        Float32(s.yz.value),
        Float32(s.xz.value),
        Float32(s.yz.value),
        Float32(s.zz.value),
    ]
    var axis: List[Int] = [2, 0, 1]
    for i in range(3):  # pragma: no branch
        for j in range(3):  # pragma: no branch
            t.elements[3 * j + i] = full[3 * axis[i] + axis[j]]
    return t


def _into_body(world: Matrix3, turn: Quaternion) -> Matrix3:
    # R^T I R: the world-frame tensor in the body's frame.
    var r = rotation_matrix(turn)
    var out = Matrix3()
    for i in range(3):  # pragma: no branch
        for j in range(i, 3):  # pragma: no branch
            var value = Float64(0)
            for k in range(3):  # pragma: no branch
                for l in range(3):  # pragma: no branch
                    value += (
                        Float64(r.elements[3 * i + k])
                        * Float64(world.elements[3 * l + k])
                        * Float64(r.elements[3 * j + l])
                    )
            out.elements[3 * j + i] = Float32(value)
            out.elements[3 * i + j] = Float32(value)
    return out


def segment_bodies(animal: Animal, mass: BodyMass) raises -> List[RigidBody]:
    """Return one dynamic rigid body per bone that holds flesh.

    Args:
        animal: The individual, at its real size, in its bind pose.
        mass: Its mass, sampled from the same sculpt.

    Returns:
        The bodies, in bone order, skipping bones with no flesh.

    Raises:
        Error: If the mass is for another rig, or a body refuses its
            mass properties.
    """
    require_sampled_rig(len(mass.bones), len(animal.rig.bones))
    var out = List[RigidBody]()
    for i in range(len(animal.rig.bones)):  # pragma: no branch
        require_non_negative_finite(
            Float64(mass.bones[i].mass),
            "A segment mass must be finite and nonnegative",
        )
        if mass.bones[i].mass == 0.0:
            continue
        ref b = animal.rig.bones[i]
        var head = animal.rig.j(b.head)
        var tail = animal.rig.j(b.tail)
        var delta = tail - head
        var span = length(delta)
        var s = mass.bone(i, Float32(span))
        var along = to_physics(vector3_from_float64(delta.x, delta.y, delta.z))
        var turn = Quaternion.identity()
        if span > 0.0:
            along.normalize()
            turn = Quaternion.from_unit_vectors(Vector3(0, 0, 1), along)
        # A capsule of the segment's mass at a tissue's density.
        var m = Float64(s.mass.value)
        var radius = sqrt(m / (1000.0 * pi * max(span, 1e-6)))
        var shape = Shape.capsule(
            length_meters(radius),
            length_meters(0.5 * span),
        )
        var origin = to_physics(vector3_from_float64(head.x, head.y, head.z))
        var body = RigidBody(DYNAMIC, shape^, s.mass, origin, turn)
        body.set_shape_pose(
            Vector3(0, 0, Float32(0.5 * span)), Quaternion.identity()
        )
        var center = to_physics(s.center) - origin
        body.set_center_of_mass(turn.conjugate().rotate(center))
        body.set_inertia(_into_body(_tensor(s), turn))
        out.append(body^)
    return out^


@fieldwise_init
struct SegmentChain(Movable):
    """An animal's segment bodies in a world, and the joints between them."""

    # One body for each bone that holds flesh, in bone order.
    var bodies: List[BodyId]
    # One ball joint for each of those bones that has such a bone above
    # it, in bone order.
    var joints: List[JointId]


def segment_chain(
    animal: Animal, mass: BodyMass, mut world: PhysicsWorld
) raises -> SegmentChain:
    """Add an animal's segments to a world and join each to the one above.

    Each bone that holds flesh becomes one body, as `segment_bodies`
    makes it. A ball joint at the bone's head joins the body to the
    nearest bone above it that holds flesh. A bone with no such bone
    above it gets no joint. Joined bodies do not collide with each other.

    Args:
        animal: The individual, at its real size, in its bind pose.
        mass: Its mass, sampled from the same sculpt.
        world: The world the bodies and joints go into.

    Returns:
        The ids of the new bodies and joints.

    Raises:
        Error: If the mass is for another rig, or a body refuses its
            mass properties.
    """
    var made = segment_bodies(animal, mass)
    # The world body of each bone, or -1 for a bone with no flesh.
    var slot = List[Int]()
    var out = SegmentChain(List[BodyId](), List[JointId]())
    for i in range(len(animal.rig.bones)):  # pragma: no branch
        if mass.bones[i].mass == 0.0:
            slot.append(-1)
            continue
        var id = world.add_body(made[len(out.bodies)].copy())
        slot.append(id.value)
        out.bodies.append(id)
        var above = animal.rig.bones[i].parent
        while above != NO_BONE and slot[above.value] < 0:
            above = animal.rig.bones[above.value].parent
        if above == NO_BONE:
            continue
        # The body's frame starts at the bone's head.
        var head = world.bodies[id.value].position
        out.joints.append(
            world.add_ball_joint(BodyId(slot[above.value]), id, head)
        )
    return out^
