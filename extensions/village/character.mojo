# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A character who walks, runs and jumps on the village's ground, as a
game's character controller does.

`Character.step` moves a character by one frame of `MoveInput`. The input
is relative to a yaw, usually the camera's: forward is the way the camera
looks. Each step is cut into steps of at most `SUBSTEP`, so a slow frame
moves the character as far as many quick ones do. Each substep does five
things:

1. **Speed.** The wanted speed is the stick's lean times the walking speed,
   or times the running speed while `run` is held. The velocity on the
   ground turns toward it by at most `acceleration` a second. In the air
   only `air_control` of that is allowed.
2. **Heading.** The character turns toward the way it moves, by at most
   `turn_speed` a second.
3. **Jump.** A press of `jump` on the ground starts a jump at `jump_speed`.
   Holding the button does not jump again: it must be let go first.
4. **Collision.** The character is a circle of `radius` on the ground. It
   is pushed out of each house's `Lot` and each `Obstacle`, such as a
   tree's trunk. It cannot walk into water deeper than `wade_depth`, or
   further than `bounds` from the middle. Where a move is refused, the
   character slides along the edge if it can.
5. **The ground.** On the ground, the feet follow `Ground.height_at`.
   Where the ground drops away by more than `step_down`, the character
   falls. In the air, gravity pulls it down until it lands.

The stance says which clip a body plays: see `Stance`.
"""

from controls.third_person_controls import (
    ground_direction,
    turn_toward,
    yaw_of,
)
from core.ordinal import ordinal_valid
from extensions.vegetation.ground import Ground, Lot
from math.finite import require_finite, require_positive_finite
from math.utils import clamp
from math.vector3 import Vector3
from std.math import ceil, cos, sin, sqrt
from units.si import (
    DEGREE_PER_SECOND,
    METER,
    METER_PER_SECOND,
    METER_PER_SECOND_SQUARED,
    RADIAN,
    RADIAN_PER_SECOND,
    SECOND,
    STANDARD_GRAVITY,
    Acceleration,
    Angle,
    AngularVelocity,
    Duration,
    Length,
    Velocity,
)

comptime SUBSTEP = Float32(1.0 / 60.0)
"""The longest substep, in seconds."""
comptime LONGEST_FRAME = Float32(1.0)
"""The most time one step counts, in seconds. A frame that took longer, as
after a pause, moves the character only this far."""
comptime STILL = Float32(0.15)
"""Below this speed, in meters a second, a character on the ground
stands."""
comptime RUN_SHARE = Float32(1.15)
"""Above this share of the walking speed, a character on the ground
runs."""
comptime LEAN = Float32(0.05)
"""A stick that leans less than this does not turn the character."""


@fieldwise_init
struct Stance(Equatable, ImplicitlyCopyable, Writable):
    """What a character is doing, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four stances there are.

        Returns:
            Whether the value names a stance.
        """
        return ordinal_valid(self.value, 3)


# On the ground, still.
comptime STANDING = Stance(0)
# On the ground, at a walk.
comptime WALKING = Stance(1)
# On the ground, faster than a walk.
comptime RUNNING = Stance(2)
# In the air: jumping or falling.
comptime AIRBORNE = Stance(3)


@fieldwise_init
struct MoveInput(ImplicitlyCopyable):
    """One frame of a player's input: two sticks and two buttons."""

    # How far the move stick leans forward and right, from -1 to 1.
    var forward: Float32
    var right: Float32
    # How far the look stick leans right and up, from -1 to 1.
    var look_right: Float32
    var look_up: Float32
    # Whether the run and the jump buttons are held.
    var run: Bool
    var jump: Bool


def no_input() -> MoveInput:
    """Return the input of a player who touches nothing.

    Returns:
        Both sticks at rest, and neither button held.
    """
    return MoveInput(0, 0, 0, 0, False, False)


@fieldwise_init
struct Obstacle(ImplicitlyCopyable):
    """Something round that a character cannot walk through, such as a
    tree's trunk."""

    # The middle, in meters.
    var x: Float32
    var z: Float32
    # The radius, in meters.
    var radius: Float32


struct CharacterParameters(ImplicitlyCopyable):
    """How a character moves: its paces, its jump and its size."""

    var walk_speed: Velocity
    var run_speed: Velocity
    # How fast the speed on the ground changes.
    var acceleration: Acceleration
    # The share of `acceleration` that is allowed in the air.
    var air_control: Float32
    var turn_speed: AngularVelocity
    # The upward speed a jump starts with, and what pulls it down.
    var jump_speed: Velocity
    var gravity: Acceleration
    # The circle the character takes up on the ground.
    var radius: Length
    # The deepest water the character walks into.
    var wade_depth: Length
    # The farthest the ground can drop under a step before the character
    # falls.
    var step_down: Length
    # How far from the middle the character can go.
    var bounds: Length

    def __init__(out self):
        """Create a person: a walk of 1.4 meters a second, a run of 4.5,
        and a jump of about 0.9 meters."""
        self.walk_speed = Velocity(1.4, METER_PER_SECOND)
        self.run_speed = Velocity(4.5, METER_PER_SECOND)
        self.acceleration = Acceleration(14.0, METER_PER_SECOND_SQUARED)
        self.air_control = 0.3
        self.turn_speed = AngularVelocity(600.0, DEGREE_PER_SECOND)
        self.jump_speed = Velocity(4.2, METER_PER_SECOND)
        self.gravity = STANDARD_GRAVITY
        self.radius = Length(0.3, METER)
        self.wade_depth = Length(0.5, METER)
        self.step_down = Length(0.4, METER)
        self.bounds = Length(250.0, METER)

    def check(self) raises:
        """Refuse a character that cannot move.

        Raises:
            Error: If a speed, the acceleration, the gravity, the radius or
                the bounds is not positive; the run is slower than the
                walk or not below 10 kilometers a second; the air control
                is not from 0 to 1; or the jump speed, the wade depth or
                the step down is negative or not below 10 kilometers, or
                10 kilometers a second.
        """
        require_positive_finite(
            Float64(self.walk_speed.to(METER_PER_SECOND)),
            "A character's walking speed must be positive",
        )
        if not (
            self.run_speed.to(METER_PER_SECOND)
            >= self.walk_speed.to(METER_PER_SECOND)
            and self.run_speed.to(METER_PER_SECOND) < 1.0e4
        ):
            raise Error(
                "A character must run at least as fast as it walks, and slower"
                " than 10 kilometers a second"
            )
        require_positive_finite(
            Float64(self.acceleration.to(METER_PER_SECOND_SQUARED)),
            "A character's acceleration must be positive",
        )
        if not (self.air_control >= 0 and self.air_control <= 1):
            raise Error("A character's air control must be from 0 to 1")
        require_positive_finite(
            Float64(self.turn_speed.to(RADIAN_PER_SECOND)),
            "A character's turning speed must be positive",
        )
        if not (
            self.jump_speed.to(METER_PER_SECOND) >= 0
            and self.jump_speed.to(METER_PER_SECOND) < 1.0e4
        ):
            raise Error(
                "A character's jump speed must be from 0 to 10 kilometers a"
                " second"
            )
        require_positive_finite(
            Float64(self.gravity.to(METER_PER_SECOND_SQUARED)),
            "A character's gravity must be positive",
        )
        require_positive_finite(
            Float64(self.radius.to(METER)),
            "A character's radius must be positive",
        )
        for length in [self.wade_depth, self.step_down]:  # pragma: no branch
            if not (length.to(METER) >= 0 and length.to(METER) < 1.0e4):
                raise Error(
                    "A character's wade depth and step down must be from 0 to"
                    " 10 kilometers"
                )
        require_positive_finite(
            Float64(self.bounds.to(METER)),
            "A character's bounds must be positive",
        )


def lot_push(lot: Lot, x: Float32, z: Float32, radius: Float32) -> Vector3:
    """Return where a circle must move to stand clear of a lot.

    Args:
        lot: The lot.
        x: The circle's middle, in meters.
        z: The circle's middle, in meters.
        radius: Its radius, in meters.

    Returns:
        The circle's middle, as `(x, 0, z)`, moved out of the lot by the
        shortest way. The same point when it is already clear.
    """
    var c = cos(lot.turn)
    var s = sin(lot.turn)
    var dx = x - lot.x
    var dz = z - lot.z
    # The point in the lot's own frame, as `Lot.reach` reads it.
    var across = dx * c - dz * s
    var along = dx * s + dz * c
    var out_across = abs(across) - lot.half_width
    var out_along = abs(along) - lot.half_depth
    if out_across >= radius or out_along >= radius:
        return Vector3(x, 0, z)
    if out_across <= 0 and out_along <= 0:
        # Inside: out across the nearer side.
        if out_across > out_along:
            across = _sign(across) * (lot.half_width + radius)
        else:
            along = _sign(along) * (lot.half_depth + radius)
    elif out_across > 0 and out_along > 0:
        # Near a corner: out along the line from the corner.
        var gap = sqrt(out_across * out_across + out_along * out_along)
        if gap >= radius:
            return Vector3(x, 0, z)
        var scale = radius / gap
        across = _sign(across) * (lot.half_width + out_across * scale)
        along = _sign(along) * (lot.half_depth + out_along * scale)
    elif out_across > 0:
        across = _sign(across) * (lot.half_width + radius)
    else:
        along = _sign(along) * (lot.half_depth + radius)
    return Vector3(
        lot.x + across * c + along * s, 0, lot.z - across * s + along * c
    )


def obstacle_push(
    obstacle: Obstacle, x: Float32, z: Float32, radius: Float32
) -> Vector3:
    """Return where a circle must move to stand clear of an obstacle.

    Args:
        obstacle: The obstacle.
        x: The circle's middle, in meters.
        z: The circle's middle, in meters.
        radius: Its radius, in meters.

    Returns:
        The circle's middle, as `(x, 0, z)`, moved straight away from the
        obstacle's middle. The same point when it is already clear. A
        circle right on the middle moves toward +x.
    """
    var dx = x - obstacle.x
    var dz = z - obstacle.z
    var reach = radius + obstacle.radius
    var gap = sqrt(dx * dx + dz * dz)
    if gap >= reach:
        return Vector3(x, 0, z)
    if gap < 1.0e-6:
        return Vector3(obstacle.x + reach, 0, obstacle.z)
    var scale = reach / gap
    return Vector3(obstacle.x + dx * scale, 0, obstacle.z + dz * scale)


def _sign(value: Float32) -> Float32:
    """Return -1 for a negative number and 1 for any other."""
    return -1 if value < 0 else 1


struct Character(Copyable, Movable):
    """A character on the ground: where its feet are, the way it faces,
    how fast it moves, and what it is doing."""

    var parameters: CharacterParameters
    # Where the feet are, in meters.
    var position: Vector3
    # The way it faces, as a yaw: see `ground_direction`.
    var heading: Angle
    # How fast it moves, in meters a second.
    var velocity: Vector3
    var grounded: Bool
    var stance: Stance
    # Whether the jump button was held at the last step.
    var jump_held: Bool
    # How far its feet have gone on the ground, in meters: the phase of a
    # walking body's stride.
    var travelled: Float32

    def __init__(
        out self,
        parameters: CharacterParameters,
        x: Float32,
        z: Float32,
        heading: Angle,
        ground: Ground,
    ) raises:
        """Stand a character on the ground.

        Args:
            parameters: How it moves.
            x: Where it stands, in meters.
            z: Where it stands, in meters.
            heading: The way it faces.
            ground: The ground it stands on.

        Raises:
            Error: If `parameters.check` refuses a value, or the place or
                the heading is not finite.
        """
        parameters.check()
        require_finite(Float64(x), "A character must stand at a finite x")
        require_finite(Float64(z), "A character must stand at a finite z")
        require_finite(
            Float64(heading.to(RADIAN)), "A character's heading must be finite"
        )
        self.parameters = parameters
        self.position = Vector3(x, ground.height_at(x, z), z)
        self.heading = heading
        self.velocity = Vector3(0, 0, 0)
        self.grounded = True
        self.stance = STANDING
        self.jump_held = False
        self.travelled = 0

    def speed(self) -> Velocity:
        """Return how fast the character moves over the ground.

        Returns:
            The speed, without the up and down part.
        """
        var v = self.velocity
        return Velocity(sqrt(v.x * v.x + v.z * v.z), METER_PER_SECOND)

    def step(
        mut self,
        input: MoveInput,
        yaw: Angle,
        delta: Duration,
        ground: Ground,
        lots: List[Lot],
        obstacles: List[Obstacle],
    ) raises:
        """Move the character by one frame.

        Args:
            input: The frame's input. Forward is along `yaw`.
            yaw: The way forward points, usually the camera's yaw.
            delta: The frame's time. At most `LONGEST_FRAME` counts.
            ground: The ground.
            lots: The buildings' footprints.
            obstacles: The round things in the way.

        Raises:
            Error: If the time is negative or above a billion seconds, the
                yaw is not finite, or `parameters.check` refuses a value.
        """
        self.parameters.check()
        var seconds = delta.to(SECOND)
        if not (seconds >= 0 and seconds < 1.0e9):
            raise Error("A frame's time must not be negative or endless")
        require_finite(Float64(yaw.to(RADIAN)), "A yaw must be finite")
        var left = min(seconds, LONGEST_FRAME)
        var count = max(1, Int(ceil(left / SUBSTEP)))
        var h = left / Float32(count)
        var pressed = input.jump and not self.jump_held
        self.jump_held = input.jump
        for _ in range(count):  # pragma: no branch
            self._substep(input, yaw, h, pressed, ground, lots, obstacles)
            pressed = False
        self._settle()

    def _substep(
        mut self,
        input: MoveInput,
        yaw: Angle,
        h: Float32,
        jump: Bool,
        ground: Ground,
        lots: List[Lot],
        obstacles: List[Obstacle],
    ):
        """Move the character by one substep of `h` seconds."""
        ref p = self.parameters
        var wish = ground_direction(
            yaw, clamp(input.forward, -1, 1), clamp(input.right, -1, 1)
        )
        var lean = min(Float32(1), wish.length())
        var top = p.run_speed if input.run else p.walk_speed
        var want = Vector3(0, 0, 0)
        if lean > LEAN:
            want = wish * (lean * top.to(METER_PER_SECOND) / wish.length())
            var most = p.turn_speed.to(RADIAN_PER_SECOND) * h
            self.heading = turn_toward(
                self.heading, yaw_of(wish), Angle(most, RADIAN)
            )
        var rate = p.acceleration.to(METER_PER_SECOND_SQUARED) * h
        if not self.grounded:
            rate *= p.air_control
        var change = Vector3(
            want.x - self.velocity.x, 0, want.z - self.velocity.z
        )
        var size = change.length()
        if size > rate:
            change = change * (rate / size)
        self.velocity = Vector3(
            self.velocity.x + change.x,
            self.velocity.y,
            self.velocity.z + change.z,
        )
        if jump and self.grounded:
            self.velocity.y = p.jump_speed.to(METER_PER_SECOND)
            self.grounded = False
        # Across the ground, then up and down.
        var start = self.position
        var goal = self._clear(
            start.x + self.velocity.x * h,
            start.z + self.velocity.z * h,
            ground,
            lots,
            obstacles,
        )
        if not self._walkable(goal.x, goal.z, ground):
            # Slide along the edge, one axis at a time.
            goal = self._clear(
                start.x + self.velocity.x * h, start.z, ground, lots, obstacles
            )
            if not self._walkable(goal.x, goal.z, ground):
                goal = self._clear(
                    start.x,
                    start.z + self.velocity.z * h,
                    ground,
                    lots,
                    obstacles,
                )
            if not self._walkable(goal.x, goal.z, ground):
                goal = Vector3(start.x, 0, start.z)
        if h > 0:
            self.velocity.x = (goal.x - start.x) / h
            self.velocity.z = (goal.z - start.z) / h
        var floor = ground.height_at(goal.x, goal.z)
        var y = start.y
        if self.grounded:
            if start.y - floor > p.step_down.to(METER):
                self.grounded = False
                self.velocity.y = 0
            else:
                y = floor
                self.velocity.y = 0
        if not self.grounded:
            self.velocity.y -= p.gravity.to(METER_PER_SECOND_SQUARED) * h
            y = start.y + self.velocity.y * h
            if y <= floor and self.velocity.y <= 0:
                y = floor
                self.velocity.y = 0
                self.grounded = True
        if self.grounded:
            var dx = goal.x - start.x
            var dz = goal.z - start.z
            self.travelled += sqrt(dx * dx + dz * dz)
        self.position = Vector3(goal.x, y, goal.z)

    def _clear(
        self,
        x: Float32,
        z: Float32,
        ground: Ground,
        lots: List[Lot],
        obstacles: List[Obstacle],
    ) -> Vector3:
        """Return a point pushed out of every lot and obstacle, and back
        within the bounds."""
        var radius = self.parameters.radius.to(METER)
        var at = Vector3(x, 0, z)
        for index in range(len(lots)):
            at = lot_push(lots[index], at.x, at.z, radius)
        for index in range(len(obstacles)):
            at = obstacle_push(obstacles[index], at.x, at.z, radius)
        var bound = self.parameters.bounds.to(METER)
        var reach = sqrt(at.x * at.x + at.z * at.z)
        if reach > bound:
            at = Vector3(at.x * bound / reach, 0, at.z * bound / reach)
        return at

    def _walkable(self, x: Float32, z: Float32, ground: Ground) -> Bool:
        """Return whether the water at a point is shallow enough to wade."""
        if ground.pond.radius.to(METER) <= 0:
            return True
        var depth = ground.water_level() - ground.height_at(x, z)
        return depth <= self.parameters.wade_depth.to(METER)

    def _settle(mut self):
        """Set the stance from the speed and whether the feet are down."""
        if not self.grounded:
            self.stance = AIRBORNE
            return
        var speed = self.speed().to(METER_PER_SECOND)
        if speed < STILL:
            self.stance = STANDING
        elif speed > self.parameters.walk_speed.to(METER_PER_SECOND) * (
            RUN_SHARE
        ):
            self.stance = RUNNING
        else:
            self.stance = WALKING
