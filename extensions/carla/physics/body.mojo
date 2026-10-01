# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A rigid body with six degrees of freedom.

A body has a pose, a shape and, when it is dynamic, a mass and an inertia
tensor. Its linear velocity is the velocity of its center of mass. Its
angular velocity is in the world frame, in radians per second, and a
positive turn about plus z turns plus x toward plus y: to the right, as a
CARLA yaw does.

A static body never moves. A kinematic body moves at the velocity it is
given and no force or contact changes it. A dynamic body moves under
gravity, forces and contacts.

The damping is Box2D's implicit damping: each step of h seconds divides
the velocity by one plus h times the damping, so the damping never
reverses a velocity, however large the step. Both dampings are 0 by
default, as in Box2D: a body keeps its speed unless something acts on it.
"""

from extensions.carla.physics.shape import (
    MESH,
    PhysicsMaterial,
    Shape,
    cross,
)
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isfinite
from units.si import KILOGRAM, Mass


@fieldwise_init
struct BodyId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a body in its `PhysicsWorld`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a body.

        Returns:
            Whether the index is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct BodyKind(Equatable, ImplicitlyCopyable, Writable):
    """Whether, and how, a body moves."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime STATIC = BodyKind(0)
comptime DYNAMIC = BodyKind(1)
comptime KINEMATIC = BodyKind(2)


def rotation_matrix(q: Quaternion) -> Matrix3:
    """Return the 3x3 rotation of a unit quaternion.

    Args:
        q: The rotation.

    Returns:
        Its matrix.
    """
    return Matrix3.from_matrix4(q.to_matrix())


def _transposed(m: Matrix3) -> Matrix3:
    var out = m
    out.transpose()
    return out


struct RigidBody(Copyable, Movable):
    """One body: its pose, its motion, its shape and its mass."""

    var kind: BodyKind
    var shape: Shape
    # Where the shape sits in the body's frame.
    var shape_position: Vector3
    var shape_rotation: Quaternion
    var material: PhysicsMaterial
    # The body's origin, in meters in the world.
    var position: Vector3
    var rotation: Quaternion
    # The velocity of the center of mass, in m/s.
    var linear_velocity: Vector3
    # In rad/s, in the world frame.
    var angular_velocity: Vector3
    # In kilograms. Zero for a static or kinematic body.
    var mass: Float32
    var inverse_mass: Float32
    # The center of mass, in the body's frame, in meters.
    var center_of_mass: Vector3
    # The inverse inertia about the center of mass, in the body's frame.
    var inverse_inertia: Matrix3
    # Box2D's implicit damping, per second.
    var linear_damping: Float32
    var angular_damping: Float32
    # How much of the world's gravity pulls this body.
    var gravity_scale: Float32
    # The force and torque summed since the last step, in N and N m.
    var force: Vector3
    var torque: Vector3
    # Whether the body takes part in contacts.
    var collides: Bool
    # The split-impulse velocities: they move the body out of an overlap
    # and are then forgotten, so they add no energy.
    var push_velocity: Vector3
    var push_angular: Vector3

    def __init__(
        out self,
        kind: BodyKind,
        var shape: Shape,
        mass: Mass,
        position: Vector3,
        rotation: Quaternion,
    ) raises:
        """Create a body at rest.

        Args:
            kind: Static, dynamic or kinematic.
            shape: The collision shape, in the body's frame.
            mass: The mass. It must be more than zero for a dynamic body,
                and is ignored for the other kinds.
            position: Where the body's origin is, in meters.
            rotation: How the body is turned. It is normalized.

        Raises:
            Error: If the kind is not valid, a mesh is not static, or a
                dynamic body has no mass.
        """
        if not kind.is_valid():
            raise Error("Body kind is not valid")
        if shape.kind == MESH and kind != STATIC:
            raise Error("A mesh body must be static")
        self.kind = kind
        self.shape = shape^
        self.shape_position = Vector3(0, 0, 0)
        self.shape_rotation = Quaternion.identity()
        self.material = PhysicsMaterial.default()
        self.position = position
        self.rotation = rotation
        self.rotation.normalize()
        self.linear_velocity = Vector3(0, 0, 0)
        self.angular_velocity = Vector3(0, 0, 0)
        self.mass = 0
        self.inverse_mass = 0
        self.center_of_mass = Vector3(0, 0, 0)
        self.inverse_inertia = Matrix3()
        self.inverse_inertia.elements[0] = 0
        self.inverse_inertia.elements[4] = 0
        self.inverse_inertia.elements[8] = 0
        self.linear_damping = 0
        self.angular_damping = 0
        self.gravity_scale = 1
        self.force = Vector3(0, 0, 0)
        self.torque = Vector3(0, 0, 0)
        self.collides = True
        self.push_velocity = Vector3(0, 0, 0)
        self.push_angular = Vector3(0, 0, 0)
        if kind == DYNAMIC:
            self.set_mass(mass)

    def set_mass(mut self, mass: Mass) raises:
        """Give a dynamic body a mass, and the inertia of its solid shape.

        Args:
            mass: The mass. It must be more than zero and finite.

        Raises:
            Error: If the mass is not more than zero, or the body is not
                dynamic.
        """
        if self.kind != DYNAMIC:
            raise Error("Only a dynamic body has a mass")
        if not (isfinite(mass.value) and mass.value > 0):
            raise Error("A dynamic body needs a mass more than zero")
        var props = self.shape.mass_properties(mass.value)
        var turn = rotation_matrix(self.shape_rotation)
        self.mass = mass.value
        self.inverse_mass = 1 / mass.value
        self.center_of_mass = turn.transform(props.center) + self.shape_position
        self.set_inertia(turn * props.inertia * _transposed(turn))

    def set_inertia(mut self, inertia: Matrix3):
        """Set the inertia tensor about the center of mass.

        Args:
            inertia: The tensor, in kg m^2, in the body's frame. It must be
                symmetric and positive definite.
        """
        self.inverse_inertia = inertia
        self.inverse_inertia.invert()

    def set_shape_pose(
        mut self, position: Vector3, rotation: Quaternion
    ) raises:
        """Place the shape in the body's frame, and recompute the mass.

        Args:
            position: Where the shape's origin is, in meters.
            rotation: How the shape is turned.

        Raises:
            Error: If `set_mass` refuses the body's mass.
        """
        self.shape_position = position
        self.shape_rotation = rotation
        if self.kind == DYNAMIC:
            self.set_mass(Mass(self.mass, KILOGRAM))

    def set_center_of_mass(mut self, center: Vector3):
        """Move the center of mass, keeping the inertia tensor.

        Args:
            center: The new center, in the body's frame, in meters.
        """
        self.center_of_mass = center

    def is_dynamic(self) -> Bool:
        """Return True if contacts and forces move this body.

        Returns:
            Whether the kind is `DYNAMIC`.
        """
        return self.kind == DYNAMIC

    def world_center_of_mass(self) -> Vector3:
        """Return the center of mass in the world.

        Returns:
            The point, in meters.
        """
        return self.position + self.rotation.rotate(self.center_of_mass)

    def shape_world_position(self) -> Vector3:
        """Return where the shape's origin is in the world.

        Returns:
            The point, in meters.
        """
        return self.position + self.rotation.rotate(self.shape_position)

    def shape_world_rotation(self) -> Quaternion:
        """Return how the shape is turned in the world.

        Returns:
            The body's rotation times the shape's.
        """
        return self.rotation * self.shape_rotation

    def world_inverse_inertia(self) -> Matrix3:
        """Return the inverse inertia tensor in the world frame.

        Returns:
            R I^-1 R^T.
        """
        var turn = rotation_matrix(self.rotation)
        return turn * self.inverse_inertia * _transposed(turn)

    def velocity_at(self, point: Vector3) -> Vector3:
        """Return the velocity of a point fixed to the body.

        Args:
            point: The point, in the world, in meters.

        Returns:
            The velocity v + w x r, in m/s.
        """
        return self.linear_velocity + cross(
            self.angular_velocity, point - self.world_center_of_mass()
        )

    def apply_impulse(mut self, impulse: Vector3, point: Vector3):
        """Change the velocity by an impulse at a point. A body that is not
        dynamic does not change.

        Args:
            impulse: The impulse, in N s.
            point: Where it acts, in the world.
        """
        var r = point - self.world_center_of_mass()
        self.linear_velocity = (
            self.linear_velocity + impulse * self.inverse_mass
        )
        self.angular_velocity = (
            self.angular_velocity
            + self.world_inverse_inertia().transform(cross(r, impulse))
        )

    def add_force(mut self, force: Vector3, point: Vector3):
        """Add a force at a point, for the next step only.

        Args:
            force: The force, in newtons.
            point: Where it acts, in the world.
        """
        self.force = self.force + force
        self.torque = self.torque + cross(
            point - self.world_center_of_mass(), force
        )

    def momentum(self) -> Vector3:
        """Return the linear momentum.

        Returns:
            The momentum m v, in N s.
        """
        return self.linear_velocity * self.mass

    def angular_momentum(self) -> Vector3:
        """Return the angular momentum about the center of mass.

        Returns:
            I w, in the world frame, in kg m^2/s.
        """
        var inertia = self.world_inverse_inertia()
        inertia.invert()
        return inertia.transform(self.angular_velocity)

    def kinetic_energy(self) -> Float32:
        """Return the kinetic energy of translation and rotation.

        Returns:
            The energy m v^2 / 2 + w . I w / 2, in joules.
        """
        return 0.5 * (
            self.mass * self.linear_velocity.dot(self.linear_velocity)
            + self.angular_velocity.dot(self.angular_momentum())
        )
