# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A walker: a kinematic character controller driven by `WalkerControl`.

`WalkerControl` is CARLA's record, `LibCarla/source/carla/rpc/
WalkerControl.h`: a direction, a speed and a jump flag. CARLA's walker
controller, `Carla/Walker/WalkerController.cpp` in CARLA's simulator
plugin, gives the walker these semantics, and this module keeps them:

- The walker goes along the direction at the control's speed. The speed
  is capped at CARLA's walker limit, 40.96 m/s. A direction shorter than
  one asks for that fraction of the speed.
- While `jump` is set, the walker jumps. CARLA allows two jumps before
  the walker lands again: a double jump.

The movement itself is a kinematic character controller of this port's
own design. The walker is a capsule that stands `skin` above the floor.
Each step does this:

1. Ground detection. Nine rays go down from the middle of the capsule:
   one at the axis and eight around the rim. A hit is a floor when it is
   no more than `max_step_height` above the feet, and when its slope is
   no steeper than `max_slope`. The highest floor wins. Its plane is
   carried to the axis, so a slope gives the same height from every ray.
2. On the ground, the horizontal velocity moves straight toward the
   target velocity. The change in one step is at most `max_acceleration`
   times the step while there is input, and `braking_deceleration` times
   the step when there is none. The ground's friction caps both: a foot
   cannot push harder than the friction times the weight, so the rate is
   at most mu g. The walker then follows the floor's plane and stands
   `skin` above it. That also steps it up a curb and down a step.
3. In the air, gravity pulls the walker. Input moves the horizontal
   velocity toward the target at `air_control` times `max_acceleration`.
   With no input, the walker keeps its horizontal velocity.
4. A new press of `jump` sets the upward speed to `jump_speed`, if the
   walker has a jump left. A held jump jumps once.

The walker lands when it falls to within one step's fall of the floor.
It then snaps to the floor with a speed that brings it there in the step,
so it does not hit the floor and does not bounce.

The defaults are round values from published data on adults:

- A capsule 1.8 m tall and 0.5 m wide, 75 kg. Surveys of adult body
  size give a stature of about 1.6 to 1.9 m, a shoulder breadth of about
  0.4 to 0.5 m, and a mass of about 60 to 90 kg.
- An acceleration of 1 m/s^2 and a braking deceleration of 2 m/s^2.
  Gait studies measure about 0.5 to 1.5 m/s^2 when a pedestrian starts
  to walk, and a stop from walking speed within one or two steps.
- A step height of 0.3 m. Building codes cap a stair riser at about
  0.18 to 0.2 m, and a curb is about 0.1 to 0.2 m high. A person can step
  onto a ledge a little higher without climbing.
- A walkable slope of 35 degrees. Past about 30 to 35 degrees, a slope
  is a scramble and not a walk.
- A jump speed of 3 m/s, which lifts the walker about 0.46 m. A standing
  vertical jump of a healthy adult is about 0.4 to 0.5 m.
- An air control of 0.2, and a skin of 1 cm. These two are not
  measurements. A person cannot push against the air, but a small air
  control lets a driver steer a fall a little. The skin keeps the
  capsule off the floor, so resting contacts do not flicker.

The capsule is a dynamic body that does not turn. Vehicles and props hit
it and push it. The controller then brings the velocity back toward the
target at the rates above.
"""

from extensions.carla.physics.body import (
    BodyId,
    DYNAMIC,
    RigidBody,
)
from extensions.carla.physics.shape import PhysicsMaterial, Shape
from extensions.carla.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import atan2, cos, isfinite, pi, sin
from units.si import (
    Acceleration,
    Angle,
    CENTIMETER,
    DEGREE,
    Duration,
    KILOGRAM,
    Length,
    METER,
    Mass,
    RADIAN,
    Velocity,
    VelocityUnit,
)

comptime _CENTIMETER_PER_SECOND = VelocityUnit(0.01, "cm/s")
# How many rays go around the rim of the capsule.
comptime _RIM_RAYS = 8
# How much farther than one step's fall a landing can snap, in meters.
comptime _LANDING_MARGIN = Float32(0.02)
# Below this horizontal speed, in m/s, the walker keeps its heading.
comptime _TURN_SPEED = Float32(0.01)


@fieldwise_init
struct WalkerControl(ImplicitlyCopyable):
    """Where a walker goes, CARLA's `rpc::WalkerControl`."""

    # The way to walk. Its up part is ignored.
    var direction: Vector3
    var speed: Velocity
    var jump: Bool

    def __init__(out self):
        """Create CARLA's default control: face forward, stand still."""
        self.direction = Vector3(1, 0, 0)
        self.speed = Velocity(0)
        self.jump = False


@fieldwise_init
struct WalkerParameters(ImplicitlyCopyable):
    """The capsule and the controller's settings."""

    var radius: Length
    # From the middle to the top, half spheres included.
    var half_height: Length
    var mass: Mass
    # The cap on the control's speed.
    var max_speed: Velocity
    # How fast the walker speeds up or turns on the ground.
    var max_acceleration: Acceleration
    # How fast the walker stops on the ground with no input.
    var braking_deceleration: Acceleration
    # The fraction of `max_acceleration` that input gives in the air.
    var air_control: Float32
    # The upward speed a jump sets.
    var jump_speed: Velocity
    # How many jumps the walker can make before it lands.
    var jump_max_count: Int
    # The highest floor above the feet that the walker steps onto.
    var max_step_height: Length
    # The steepest floor the walker stands on.
    var max_slope: Angle
    # The gap between the capsule and the floor it stands on.
    var skin: Length

    def __init__(out self):
        """Create the defaults: an adult, and CARLA's speed cap and jump
        count."""
        self.radius = Length(0.25, METER)
        self.half_height = Length(0.9, METER)
        self.mass = Mass(75, KILOGRAM)
        self.max_speed = Velocity(4096, _CENTIMETER_PER_SECOND)
        self.max_acceleration = Acceleration(1)
        self.braking_deceleration = Acceleration(2)
        self.air_control = 0.2
        self.jump_speed = Velocity(3)
        self.jump_max_count = 2
        self.max_step_height = Length(0.3, METER)
        self.max_slope = Angle(35, DEGREE)
        self.skin = Length(1, CENTIMETER)

    def check(self) raises:
        """Refuse settings no walker can have.

        Raises:
            Error: If the radius is not more than zero, the half height
                is less than the radius, a speed, rate or length is
                negative, the slope is not from 0 to 90 degrees, or the
                jump count is less than one.
        """
        if not (isfinite(self.radius.value) and self.radius.value > 0):
            raise Error("A walker's radius must be more than zero")
        if not (self.half_height.value >= self.radius.value):
            raise Error("A walker's half height must reach its radius")
        var values = [
            self.max_speed.value,
            self.max_acceleration.value,
            self.braking_deceleration.value,
            self.air_control,
            self.jump_speed.value,
            self.max_step_height.value,
            self.skin.value,
        ]
        for value in values:  # pragma: no branch
            if not (isfinite(value) and value >= 0):
                raise Error("A walker's speeds and rates must not be negative")
        var slope = self.max_slope.value
        if not (slope >= 0 and slope <= Float32(pi / 2)):
            raise Error("A walker's slope must be from 0 to 90 degrees")
        if self.jump_max_count < 1:
            raise Error("A walker must be able to jump once")


def _flat(v: Vector3) -> Vector3:
    """Return the horizontal part of a vector."""
    return Vector3(v.x, v.y, 0)


def _toward(current: Vector3, target: Vector3, most: Float32) -> Vector3:
    """Move a vector straight toward a target by no more than `most`."""
    var change = target - current
    var size = change.length()
    if size <= most:
        return target
    return current + change * (most / size)


struct Walker(Copyable, Movable):
    """A pedestrian's capsule and its controller state."""

    var body: BodyId
    var parameters: WalkerParameters
    var control: WalkerControl
    var grounded: Bool
    # The jumps made since the walker last stood on a floor.
    var jump_count: Int
    # Whether `jump` was set last step: a held jump jumps once.
    var jump_held: Bool
    # The floor under the walker: its height at the capsule's axis, its
    # normal and its friction. They are valid when `on_floor` is set.
    var on_floor: Bool
    var floor_height: Float32
    var floor_normal: Vector3
    var floor_friction: Float32

    def __init__(
        out self,
        mut world: PhysicsWorld,
        location: Vector3,
        parameters: WalkerParameters,
    ) raises:
        """Spawn a walker: add its capsule to the world.

        Args:
            world: The world the capsule joins.
            location: The middle of the capsule, in meters.
            parameters: The capsule and the controller's settings.

        Raises:
            Error: If the settings are refused.
        """
        parameters.check()
        var radius = parameters.radius
        var body = RigidBody(
            DYNAMIC,
            Shape.capsule(
                radius,
                Length(parameters.half_height.value - radius.value, METER),
            ),
            parameters.mass,
            location,
            Quaternion.identity(),
        )
        # The capsule stays upright, and slides along walls.
        for i in range(9):  # pragma: no branch
            body.inverse_inertia.elements[i] = 0
        body.material = PhysicsMaterial(0, 0)
        body.linear_damping = 0
        self.body = world.add_body(body^)
        self.parameters = parameters
        self.control = WalkerControl()
        self.grounded = False
        self.jump_count = 0
        self.jump_held = False
        self.on_floor = False
        self.floor_height = 0
        self.floor_normal = Vector3(0, 0, 1)
        self.floor_friction = 0

    def apply_control(mut self, control: WalkerControl) raises:
        """Take a control, as CARLA's walker controller does.

        Args:
            control: The control.

        Raises:
            Error: If the speed is negative or not finite.
        """
        if not (isfinite(control.speed.value) and control.speed.value >= 0):
            raise Error("A walker's speed must be zero or more")
        self.control = control

    def speed(self, world: PhysicsWorld) -> Velocity:
        """Return how fast the walker moves over the ground.

        Args:
            world: The world that holds the capsule.

        Returns:
            The horizontal speed.
        """
        return Velocity(
            _flat(world.bodies[self.body.value].linear_velocity).length()
        )

    def target_velocity(self) -> Vector3:
        """Return the horizontal velocity the control asks for.

        Returns:
            The direction's horizontal part times the speed, no longer
            than `max_speed`, in m/s.
        """
        var wanted = _flat(self.control.direction) * self.control.speed.value
        var most = self.parameters.max_speed.value
        if wanted.length() > most:
            return wanted * (most / wanted.length())
        return wanted

    def _probe(mut self, world: PhysicsWorld, reach_below: Float32) raises:
        """Cast the rays and keep the highest walkable floor."""
        ref body = world.bodies[self.body.value]
        var p = self.parameters
        var center = body.position
        var feet = center.z - p.half_height.value
        var step = p.max_step_height.value
        var steepest = cos(p.max_slope.value)
        self.on_floor = False
        for k in range(_RIM_RAYS + 1):  # pragma: no branch
            var offset = Vector3(0, 0, 0)
            if k > 0:
                var turn = Float32(k) * Float32(2 * pi / _RIM_RAYS)
                offset = Vector3(cos(turn), sin(turn), 0) * p.radius.value
            var hit = world.raycast(
                center + offset,
                Vector3(0, 0, -1),
                Length(p.half_height.value + reach_below, METER),
                self.body,
            )
            if not Bool(hit):
                continue
            var h = hit.value()
            if h.point.z > feet + step or h.normal.z < steepest:
                continue
            # The floor's plane at the axis: n . (x - point) = 0.
            var level = (
                h.point.z
                + (h.normal.x * offset.x + h.normal.y * offset.y) / h.normal.z
            )
            if self.on_floor and level <= self.floor_height:
                continue
            self.on_floor = True
            self.floor_height = level
            self.floor_normal = h.normal
            self.floor_friction = h.material.friction

    def update(mut self, mut world: PhysicsWorld, dt: Duration) raises:
        """Move the walker for one step: call this before `world.step`.

        Args:
            world: The world that holds the capsule.
            dt: The step. It must be more than zero.

        Raises:
            Error: If the step is not more than zero.
        """
        var h = dt.value
        if not (h > 0):
            raise Error("A walker step must be more than zero")
        var p = self.parameters
        var velocity = world.bodies[self.body.value].linear_velocity
        var fall = max(-velocity.z, 0) * h
        self._probe(world, max(p.max_step_height.value, fall))
        ref body = world.bodies[self.body.value]
        var feet = body.position.z - p.half_height.value
        var gap = feet - self.floor_height
        if self.grounded:
            self.grounded = self.on_floor
        else:
            self.grounded = (
                self.on_floor
                and velocity.z <= 0
                and gap <= p.skin.value + fall + _LANDING_MARGIN
            )
        if self.grounded:
            self.jump_count = 0
        var target = self.target_velocity()
        var v = _flat(velocity)
        var vz = velocity.z
        if self.grounded:
            var rate = p.max_acceleration.value
            if target.length() == 0:
                rate = p.braking_deceleration.value
            # The traction limit: no more than mu g.
            rate = min(rate, self.floor_friction * world.gravity.length())
            v = _toward(v, target, rate * h)
            # Stand `skin` above the floor, and move along its plane.
            var n = self.floor_normal
            vz = (self.floor_height + p.skin.value - feet) / h - (
                n.x * v.x + n.y * v.y
            ) / n.z
            body.gravity_scale = 0
        else:
            if target.length() > 0:
                var rate = p.air_control * p.max_acceleration.value
                v = _toward(v, target, rate * h)
            body.gravity_scale = 1
        var pressed = self.control.jump and not self.jump_held
        if pressed and self.jump_count < p.jump_max_count:
            vz = p.jump_speed.value
            self.jump_count += 1
            self.grounded = False
            body.gravity_scale = 1
        self.jump_held = self.control.jump
        body.linear_velocity = Vector3(v.x, v.y, vz)
        if v.length() > _TURN_SPEED:
            body.rotation = Quaternion.from_axis_angle(
                Vector3(0, 0, 1), Angle(atan2(v.y, v.x), RADIAN)
            )
