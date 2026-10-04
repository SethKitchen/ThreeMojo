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
the sampled ones, not the capsule's. The physics world has no joints yet,
so the bodies are the segments of a multibody model for a solver that
has them.
"""

from extensions.anatomy.inertia import SegmentInertia
from extensions.animals.anatomy.mass import BodyMass
from extensions.animals.build import Animal
from extensions.physics.body import DYNAMIC, RigidBody, rotation_matrix
from extensions.physics.shape import Shape
from extensions.sdf.vector import V3, length
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import pi, sqrt
from units.si import KILOGRAM, METER, Length, Mass


def to_physics(p: Vector3) -> Vector3:
    """Turn a point or a direction from the sculpt's frame to the physics
    world's.

    Args:
        p: In the sculpt's frame: `+y` up, `+z` forward.

    Returns:
        In the physics frame: `+z` up, `+x` forward.
    """
    return Vector3(p.z, p.x, p.y)


def _wide(v: V3) -> Vector3:
    return Vector3(Float32(v.x), Float32(v.y), Float32(v.z))


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
        for j in range(3):  # pragma: no branch
            var value = Float64(0)
            for k in range(3):  # pragma: no branch
                for l in range(3):  # pragma: no branch
                    value += (
                        Float64(r.elements[3 * i + k])
                        * Float64(world.elements[3 * l + k])
                        * Float64(r.elements[3 * j + l])
                    )
            out.elements[3 * j + i] = Float32(value)
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
    if len(mass.bones) != len(animal.rig.bones):
        raise Error("The mass was sampled from another rig")
    var out = List[RigidBody]()
    for i in range(len(animal.rig.bones)):  # pragma: no branch
        if mass.bones[i].mass <= 0.0:
            continue
        ref b = animal.rig.bones[i]
        var head = animal.rig.j(b.head)
        var tail = animal.rig.j(b.tail)
        var span = length(tail - head)
        var s = mass.bone(i, Float32(span))
        var along = to_physics(_wide(tail - head))
        var turn = Quaternion.identity()
        if span > 0.0:
            along.normalize()
            turn = Quaternion.from_unit_vectors(Vector3(0, 0, 1), along)
        # A capsule of the segment's mass at a tissue's density.
        var m = Float64(s.mass.value)
        var radius = sqrt(m / (1000.0 * pi * max(span, 1e-6)))
        var shape = Shape.capsule(
            Length(Float32(radius), METER),
            Length(Float32(0.5 * span), METER),
        )
        var origin = to_physics(_wide(head))
        var body = RigidBody(DYNAMIC, shape^, s.mass, origin, turn)
        body.set_shape_pose(
            Vector3(0, 0, Float32(0.5 * span)), Quaternion.identity()
        )
        var center = to_physics(s.center) - origin
        body.set_center_of_mass(turn.conjugate().rotate(center))
        body.set_inertia(_into_body(_tensor(s), turn))
        out.append(body^)
    return out^
