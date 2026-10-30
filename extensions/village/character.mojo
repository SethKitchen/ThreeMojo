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
   is pushed out of each solid `Lot` of the `Terrain`, out of each of its
   `WallSpan`s that stands between its feet and `HEADROOM` above them,
   and out of each `Obstacle`, such as a tree's trunk. So it walks into a
   house only at a door, where the wall has a gap. It cannot walk into
   water deeper than `wade_depth`, or further than `bounds` from the
   middle. Where a move is refused, the character slides along the edge
   if it can.
5. **The ground.** On the ground, the feet follow `Terrain.height_at`:
   the highest floor or step that they can reach, and the ground
   elsewhere. A floor more than `CLIMB` above the feet, such as an upper
   storey, passes over them, so a character goes up a stair one tread at
   a time. Where the ground drops away by more than `step_down`, the
   character falls. In the air, gravity pulls it down until it lands.

The stance says which clip a body plays: see `Stance`.
"""

from controls.third_person_controls import (
    ground_direction,
    turn_toward,
    yaw_of,
)
from core.ordinal import ordinal_valid
from extensions.vegetation.ground import Lot
from extensions.village.terrain import Terrain, wall_push
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
comptime HEADROOM = Float32(1.5)
"""A wall stops a character when its foot is lower than this height over
the character's feet, in meters, and its top is higher than the feet."""


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


struct MoveInput(ImplicitlyCopyable):
    """One frame of a player's input: two sticks and the buttons held."""

    # How far the move stick leans forward and right, from -1 to 1.
    var forward: Float32
    var right: Float32
    # How far the look stick leans right and up, from -1 to 1.
    var look_right: Float32
    var look_up: Float32
    # Whether the run, the jump and the use buttons are held.
    var run: Bool
    var jump: Bool
    var use: Bool
    # Whether the fight's buttons are held: the light and the heavy
    # attacks, the three artes and the mystic arte, the dodge, the guard,
    # the lock, the three stances, and the companion's boost attack. See
    # `extensions.village.battle`.
    var light: Bool
    var heavy: Bool
    var rising: Bool
    var tempest: Bool
    var fang: Bool
    var mystic: Bool
    var dodge: Bool
    var guard: Bool
    var lock: Bool
    var high: Bool
    var middle: Bool
    var low: Bool
    var boost: Bool
    # Whether the button that eats herbs to heal is held.
    var heal: Bool

    def __init__(
        out self,
        forward: Float32,
        right: Float32,
        look_right: Float32,
        look_up: Float32,
        run: Bool,
        jump: Bool,
        use: Bool = False,
        *,
        light: Bool = False,
        heavy: Bool = False,
        rising: Bool = False,
        tempest: Bool = False,
        fang: Bool = False,
        mystic: Bool = False,
        dodge: Bool = False,
        guard: Bool = False,
        lock: Bool = False,
        high: Bool = False,
        middle: Bool = False,
        low: Bool = False,
        boost: Bool = False,
        heal: Bool = False,
    ):
        """Hold one frame of input.

        Args:
            forward: How far the move stick leans forward, from -1 to 1.
            right: How far it leans right, from -1 to 1.
            look_right: How far the look stick leans right, from -1 to 1.
            look_up: How far it leans up, from -1 to 1.
            run: Whether the run button is held.
            jump: Whether the jump button is held.
            use: Whether the use button is held: see
                `extensions.village.gathering`.
            light: Whether the light attack's button is held.
            heavy: Whether the heavy attack's button is held.
            rising: Whether the rising edge's buttons are held.
            tempest: Whether the tempest's buttons are held.
            fang: Whether the demon fang's buttons are held.
            mystic: Whether the mystic arte's buttons are held.
            dodge: Whether the dodge's button is held.
            guard: Whether the guard's button is held.
            lock: Whether the lock's button is held.
            high: Whether the high stance's buttons are held.
            middle: Whether the middle stance's buttons are held.
            low: Whether the low stance's buttons are held.
            boost: Whether the boost attack's buttons are held.
            heal: Whether the button that eats herbs to heal is held.
        """
        self.forward = forward
        self.right = right
        self.look_right = look_right
        self.look_up = look_up
        self.run = run
        self.jump = jump
        self.use = use
        self.light = light
        self.heavy = heavy
        self.rising = rising
        self.tempest = tempest
        self.fang = fang
        self.mystic = mystic
        self.dodge = dodge
        self.guard = guard
        self.lock = lock
        self.high = high
        self.middle = middle
        self.low = low
        self.boost = boost
        self.heal = heal


def no_input() -> MoveInput:
    """Return the input of a player who touches nothing.

    Returns:
        Both sticks at rest, and no button held.
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
        terrain: Terrain,
    ) raises:
        """Stand a character on the terrain.

        Args:
            parameters: How it moves.
            x: Where it stands, in meters.
            z: Where it stands, in meters.
            heading: The way it faces.
            terrain: What it stands on: a floor, or the ground.

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
        # It starts on the ground, or on a floor a climb above it.
        var ground = terrain.ground.height_at(x, z)
        self.position = Vector3(x, terrain.height_at(x, z, ground), z)
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
        terrain: Terrain,
        obstacles: List[Obstacle],
        skip: Int = -1,
    ) raises:
        """Move the character by one frame.

        Args:
            input: The frame's input. Forward is along `yaw`.
            yaw: The way forward points, usually the camera's yaw.
            delta: The frame's time. At most `LONGEST_FRAME` counts.
            terrain: The ground, the floors, the walls and the solid
                buildings.
            obstacles: The round things in the way.
            skip: The index of an obstacle to pass over, such as the
                character's own, or -1 for none.

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
            self._substep(input, yaw, h, pressed, terrain, obstacles, skip)
            pressed = False
        self._settle()

    def _substep(
        mut self,
        input: MoveInput,
        yaw: Angle,
        h: Float32,
        jump: Bool,
        terrain: Terrain,
        obstacles: List[Obstacle],
        skip: Int,
    ):
        """Move the character by one substep of `h` seconds, passing over
        the obstacle at `skip`."""
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
        self._travel(h, terrain, obstacles, skip)

    def drive(
        mut self,
        velocity: Vector3,
        delta: Duration,
        terrain: Terrain,
        obstacles: List[Obstacle],
        skip: Int = -1,
    ) raises:
        """Move the character by one frame at a set speed over the ground,
        as a lunge, a dodge or a blow carries it.

        The speed over the ground does not turn toward a stick, and the
        heading does not turn. Every other rule of `step` holds: the
        walls, the water and the obstacles stop the character, it slides
        along their edges, and it falls where the ground drops away.

        Args:
            velocity: The speed over the ground, in meters a second. Its y
                is not used.
            delta: The frame's time. At most `LONGEST_FRAME` counts.
            terrain: The ground, the floors, the walls and the solid
                buildings.
            obstacles: The round things in the way.
            skip: The index of an obstacle to pass over, or -1 for none.

        Raises:
            Error: If the time is negative or above a billion seconds, the
                speed is not finite, or `parameters.check` refuses a value.
        """
        self.parameters.check()
        var seconds = delta.to(SECOND)
        if not (seconds >= 0 and seconds < 1.0e9):
            raise Error("A frame's time must not be negative or endless")
        require_finite(
            Float64(velocity.x + velocity.z), "A drive's speed must be finite"
        )
        var left = min(seconds, LONGEST_FRAME)
        var count = max(1, Int(ceil(left / SUBSTEP)))
        var h = left / Float32(count)
        for _ in range(count):  # pragma: no branch
            self.velocity.x = velocity.x
            self.velocity.z = velocity.z
            self._travel(h, terrain, obstacles, skip)
        self._settle()

    def _travel(
        mut self,
        h: Float32,
        terrain: Terrain,
        obstacles: List[Obstacle],
        skip: Int,
    ):
        """Move the character by its velocity for `h` seconds: across the
        ground, out of what stands in the way, then up and down."""
        ref p = self.parameters
        var start = self.position
        var goal = self._clear(
            start.x + self.velocity.x * h,
            start.z + self.velocity.z * h,
            start.y,
            terrain,
            obstacles,
            skip,
        )
        if not self._walkable(goal.x, goal.z, start.y, terrain):
            # Slide along the edge, one axis at a time.
            goal = self._clear(
                start.x + self.velocity.x * h,
                start.z,
                start.y,
                terrain,
                obstacles,
                skip,
            )
            if not self._walkable(goal.x, goal.z, start.y, terrain):
                goal = self._clear(
                    start.x,
                    start.z + self.velocity.z * h,
                    start.y,
                    terrain,
                    obstacles,
                    skip,
                )
            if not self._walkable(goal.x, goal.z, start.y, terrain):
                goal = Vector3(start.x, 0, start.z)
        if h > 0:
            var vx = (goal.x - start.x) / h
            var vz = (goal.z - start.z) / h
            # A push out of an obstacle that it overlaps adds no speed.
            var was = self.velocity.x * self.velocity.x
            was += self.velocity.z * self.velocity.z
            var now = vx * vx + vz * vz
            if now > was:
                var keep = sqrt(was / now)
                vx *= keep
                vz *= keep
            self.velocity.x = vx
            self.velocity.z = vz
        var floor = terrain.height_at(goal.x, goal.z, start.y)
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
        foot: Float32,
        terrain: Terrain,
        obstacles: List[Obstacle],
        skip: Int,
    ) -> Vector3:
        """Return a point pushed out of every solid lot, every wall that
        stands in the way of feet at `foot`, and every obstacle but the one
        at `skip`, and back within the bounds."""
        var radius = self.parameters.radius.to(METER)
        var at = Vector3(x, 0, z)
        for index in range(len(terrain.lots)):
            at = lot_push(terrain.lots[index], at.x, at.z, radius)
        for index in range(len(terrain.walls)):
            ref span = terrain.walls[index]
            if span.blocks(foot, foot + HEADROOM):
                at = wall_push(span, at.x, at.z, radius)
        for index in range(len(obstacles)):
            if index != skip:
                at = obstacle_push(obstacles[index], at.x, at.z, radius)
        var bound = self.parameters.bounds.to(METER)
        var reach = sqrt(at.x * at.x + at.z * at.z)
        if reach > bound:
            at = Vector3(at.x * bound / reach, 0, at.z * bound / reach)
        return at

    def _walkable(
        self, x: Float32, z: Float32, foot: Float32, terrain: Terrain
    ) -> Bool:
        """Return whether the water at a point is shallow enough to wade
        for feet at `foot`. A floor stands above the water."""
        ref ground = terrain.ground
        if ground.pond.radius.to(METER) <= 0:
            return True
        var depth = ground.water_level() - terrain.height_at(x, z, foot)
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
