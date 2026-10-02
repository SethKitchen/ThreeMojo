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

from extensions.physics.shape import (
    MESH,
    PhysicsMaterial,
    Shape,
    cross,
    _finite_vector,
    _inertia_inverse,
    _narrow_finite,
)
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isfinite
from units.si import Mass


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

    # Change modes through set_kind so effective mass stays consistent.
    var kind: BodyKind
    var _has_dynamic_state: Bool
    var _dynamic_mass: Float32
    var _dynamic_inverse_mass: Float32
    var _dynamic_inverse_inertia: Matrix3
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
        self._has_dynamic_state = False
        self._dynamic_mass = 0
        self._dynamic_inverse_mass = 0
        self._dynamic_inverse_inertia = Matrix3()
        for i in range(9):  # pragma: no branch
            self._dynamic_inverse_inertia.elements[i] = 0
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

    def set_kind(mut self, kind: BodyKind) raises:
        """Change how the body moves without losing its dynamic mass.

        Dynamic-to-kinematic changes keep velocity. Entering static stops
        velocity and split-impulse velocity. Force and torque stay pending
        until the next world step consumes them. A disabled body's local
        mass tensor is retained; its world pose can change before it
        becomes dynamic again.

        Args:
            kind: The new mode. A mesh must stay static.

        Raises:
            Error: If the kind is invalid, a mesh would move, or no valid
                dynamic state can be restored. Construct a dynamic body
                before disabling it when later restoration is needed.
        """
        if not kind.is_valid():
            raise Error("Body kind is not valid")
        if self.shape.kind == MESH and kind != STATIC:
            raise Error("A mesh body must be static")
        if kind == self.kind:
            return
        if kind == DYNAMIC:
            if not self._has_dynamic_state:
                raise Error("The body has no retained dynamic mass")
            self._check_dynamic_state(
                self._dynamic_mass,
                self._dynamic_inverse_mass,
                self._dynamic_inverse_inertia,
            )
            self.mass = self._dynamic_mass
            self.inverse_mass = self._dynamic_inverse_mass
            self.inverse_inertia = self._dynamic_inverse_inertia
        else:
            if self.kind == DYNAMIC:
                self._check_dynamic_state(
                    self.mass, self.inverse_mass, self.inverse_inertia
                )
                self._dynamic_mass = self.mass
                self._dynamic_inverse_mass = self.inverse_mass
                self._dynamic_inverse_inertia = self.inverse_inertia
                self._has_dynamic_state = True
            self.mass = 0
            self.inverse_mass = 0
            for i in range(9):  # pragma: no branch
                self.inverse_inertia.elements[i] = 0
            if kind == STATIC:
                self.linear_velocity = Vector3(0, 0, 0)
                self.angular_velocity = Vector3(0, 0, 0)
                self.push_velocity = Vector3(0, 0, 0)
                self.push_angular = Vector3(0, 0, 0)
        self.kind = kind

    def _check_dynamic_state(
        self, mass: Float32, inverse_mass: Float32, inertia: Matrix3
    ) raises:
        if not (
            isfinite(mass)
            and mass > 0
            and isfinite(inverse_mass)
            and inverse_mass > 0
            and inverse_mass == 1 / mass
        ):
            raise Error("The retained dynamic mass is invalid")
        for i in range(9):  # pragma: no branch
            if not isfinite(inertia.elements[i]):
                raise Error("The retained inverse inertia is not finite")

    def set_mass(mut self, mass: Mass) raises:
        """Give a dynamic body a mass, and the inertia of its solid shape.

        Args:
            mass: The mass. It must be more than zero and finite.

        Raises:
            Error: If the mass is not more than zero, or the body is not
                dynamic. Also if its derived center, inertia or inverse
                properties cannot be represented. A failure changes no
                mass-property field.
        """
        if self.kind != DYNAMIC:
            raise Error("Only a dynamic body has a mass")
        var state = self._mass_state(
            mass.value, self.shape_position, self.shape_rotation
        )
        self.mass = mass.value
        self.inverse_mass = state[0]
        self.center_of_mass = state[1]
        self.inverse_inertia = state[2]

    def _mass_state(
        self, mass: Float32, position: Vector3, rotation: Quaternion
    ) raises -> Tuple[Float32, Vector3, Matrix3]:
        if not (isfinite(mass) and mass > 0):
            raise Error("A dynamic body needs a mass more than zero")
        var inverse_mass = _narrow_finite(1 / Float64(mass))
        _finite_vector(position)
        var props = self.shape.mass_properties(mass)
        var turn = rotation_matrix(rotation)
        var coordinates = List[Float32]()
        for i in range(3):  # pragma: no branch
            var value = Float64(
                position.x if i == 0 else position.y if i == 1 else position.z
            )
            value += Float64(turn.elements[i]) * Float64(props.center.x)
            value += Float64(turn.elements[3 + i]) * Float64(props.center.y)
            value += Float64(turn.elements[6 + i]) * Float64(props.center.z)
            coordinates.append(_narrow_finite(value))
        var center = Vector3(coordinates[0], coordinates[1], coordinates[2])
        var inertia = Matrix3()
        # R I R^T in wide arithmetic. Store each symmetric pair once.
        for i in range(3):  # pragma: no branch
            for j in range(i, 3):  # pragma: no branch
                var value = Float64(0)
                for k in range(3):  # pragma: no branch
                    for l in range(3):  # pragma: no branch
                        value += (
                            Float64(turn.elements[3 * k + i])
                            * Float64(props.inertia.elements[3 * l + k])
                            * Float64(turn.elements[3 * l + j])
                        )
                var entry = _narrow_finite(value)
                inertia.elements[3 * i + j] = entry
                inertia.elements[3 * j + i] = entry
        var inverse = _inertia_inverse(inertia)
        return (inverse_mass, center, inverse)

    def set_inertia(mut self, inertia: Matrix3) raises:
        """Set the inertia tensor about the center of mass.

        Args:
            inertia: The tensor, in kg m^2, in the body's frame. It must be
                symmetric and positive definite.

        Raises:
            Error: If the body is not dynamic, the tensor is nonfinite,
                asymmetric or not positive definite, or its inverse
                cannot be represented. A failure leaves the old tensor.
        """
        if self.kind != DYNAMIC:
            raise Error("Only a dynamic body can set its inertia")
        var inverse = _inertia_inverse(inertia)
        self.inverse_inertia = inverse

    def set_shape_pose(
        mut self, position: Vector3, rotation: Quaternion
    ) raises:
        """Place the shape in the body's frame, and recompute the mass.

        Args:
            position: Where the shape's origin is, in meters.
            rotation: How the shape is turned. It is normalized.

        Raises:
            Error: If the pose is nonfinite, a disabled dynamic body
                retains its mass, or `set_mass` refuses the derived mass
                properties. A failure leaves the pose and mass unchanged.
        """
        if self.kind != DYNAMIC and self._has_dynamic_state:
            raise Error("Restore dynamic mode before changing the shape pose")
        _finite_vector(position)
        var turn = rotation
        for value in [turn.x, turn.y, turn.z, turn.w]:  # pragma: no branch
            if not isfinite(value):
                raise Error("A shape rotation must be finite")
        turn.normalize()
        if self.kind == DYNAMIC:
            var state = self._mass_state(self.mass, position, turn)
            self.inverse_mass = state[0]
            self.center_of_mass = state[1]
            self.inverse_inertia = state[2]
        self.shape_position = position
        self.shape_rotation = turn

    def set_center_of_mass(mut self, center: Vector3) raises:
        """Move the center of mass, keeping the inertia tensor.

        Args:
            center: The new center, in the body's frame, in meters.

        Raises:
            Error: If the center is nonfinite or a disabled dynamic body
                retains its mass.
        """
        if self.kind != DYNAMIC and self._has_dynamic_state:
            raise Error("Restore dynamic mode before changing its mass center")
        _finite_vector(center)
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
