# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's companion in a fight: a swordswoman who keeps back, casts bolts of light at the player's foe,
heals the player, and makes a assist attack when the player calls for it.

A `Companion` is her mind. `Companion.think` decides what she does, frame
by frame, from an `AllySight`:

1. **Out of a fight**, she follows the player. She walks to them when
   they are more than `FOLLOW` away, and runs when they are more than
   twice as far.
2. **In a fight**, she faces the player's foe and goes to her spot:
   `KEEP` meters from the foe, `FLANK` off the line from the foe to the
   player, on the side she stands on. So she stands out of the way of a
   camera behind the player. She never strays more than `LEASH` from the
   player. Every `CAST_EVERY` seconds, she casts a bolt at a foe within
   `CAST_RANGE`.
3. **She heals.** When the player's health falls below `MEND_BELOW` of
   its most, she heals `MEND_SHARE` of it. Then she waits `MEND_EVERY`
   seconds before she heals again.
4. **The assist gauge** fills by `ASSIST_RATE` a second while the fight
   lasts, and by `ASSIST_PER_HIT` for each bolt that lands. When it is
   full, the player can call for a assist attack: a bolt that no guard
   stops, and that breaks a piercing attack. See `assist_blow`.

The foes do not attack her: she keeps out of their way. The game moves
her bolts: see `extensions.village.battle`.
"""

from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.attire.mix import RANGER, dressed_as
from extensions.village.clothes import calling_groom
from extensions.village.combat import Blow, FighterParameters
from extensions.village.foes import Bandit
from extensions.village.interior import Doorway
from math.vector3 import Vector3
from std.math import cos, sin, sqrt
from units.si import (
    DEGREE,
    INCH,
    RADIAN,
    METER_PER_SECOND,
    PER_SECOND,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
    Velocity,
)

comptime DOOR_OUTSIDE = Float32(1.5)
"""How far before a door, in meters, the companion walks to as the player
goes in."""
comptime DOOR_INSIDE = Float32(1.8)
"""How far past a door, in meters, she walks to once she is at it."""
comptime DOOR_REACH = Float32(2.2)
"""How near a door's middle, in meters, she must be to go in through it:
more than `DOOR_OUTSIDE`, so she goes in once she is before it."""
comptime DOOR_LANE = Float32(0.06)
"""How far from a door's axis, in meters, she may stand and still walk
straight through it. The jambs' round ends and her body leave a door
1 meter wide 8 centimeters each side of its axis. Farther off it, she
walks to the axis first."""
comptime DOOR_CLEAR = Float32(1.2)
"""How near a door's middle, in meters, she does not stop indoors: she
walks on in, so that those behind her come in too."""
comptime POND_MARGIN = Float32(1)
"""How far outside a pond's edge, in meters, a follower's way goes round
it."""
comptime CLIMB_REACH = Float32(0.5)
"""How near a point of the way up the stairs, in meters, on the ground and
in height, the companion must be to walk on to the next one."""
comptime CLIMB_RISE = Float32(1.5)
"""How far above her, in meters, the player must stand indoors for the
companion to climb the house's stairs to them."""
comptime FOLLOW = Float32(3)
"""How far from the player the companion keeps out of a fight, in meters."""
comptime KEEP = Float32(6)
"""How far from the player's foe she keeps in a fight, in meters."""
comptime FLANK = Angle(70.0, DEGREE)
"""How far off the line from the foe to the player she stands in a
fight."""
comptime SPOT_NEAR = Float32(1)
"""How near her spot in a fight she stops, in meters."""
comptime LEASH = Float32(10)
"""How far from the player she strays in a fight, at most, in meters."""
comptime CAST_RANGE = Float32(14)
"""How far she casts a bolt, in meters."""
comptime CAST_EVERY = Float32(2.6)
"""How long she waits between two casts, in seconds."""
comptime MEND_BELOW = Float32(0.4)
"""The share of the player's health below which she heals them."""
comptime MEND_SHARE = Float32(0.15)
"""The share of the player's health that her heal gives back."""
comptime MEND_EVERY = Float32(15)
"""How long she waits between two heals, in seconds."""
comptime ASSIST_FULL = Float32(100)
"""How much the assist gauge holds."""
comptime ASSIST_RATE = Float32(4)
"""How fast the assist gauge fills while the fight lasts, a second."""
comptime ASSIST_PER_HIT = Float32(10)
"""How much each bolt that lands fills the assist gauge."""
comptime ALLY_X = Float32(1.5)
"""How far to the side of the player's start she starts, in meters."""
comptime ALLY_Z = Float32(1.5)
"""How far behind the player's start she starts, in meters."""


def _flat_gap(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def _through(at: Vector3, door: Doorway, depth: Float32) -> Vector3:
    """Return the spot she walks to through a door: `depth` past its
    middle, positive inward.

    Off the door's axis by more than `DOOR_LANE`, she walks to the axis at
    45 degrees to it, a point of the axis as far ahead of her as she is
    beside it. A straight way to the spot from there would end square in
    the wall beside the door. At 45 degrees, a wall in her way turns her
    along it to the door."""
    var middle = door.middle()
    var into = Vector3(door.swing_x, 0, door.swing_z)
    var dx = at.x - middle.x
    var dz = at.z - middle.z
    var side = abs(dz * into.x - dx * into.z)
    if side <= DOOR_LANE:
        return middle + into * depth
    # Her depth, and the spot's, the way she goes.
    var sense = Float32(1) if depth > 0 else Float32(-1)
    var deep = (dx * into.x + dz * into.z) * sense
    return middle + into * (min(abs(depth), deep + side) * sense)


def _toward(a: Vector3, b: Vector3) -> Vector3:
    """Return the way from one point to another on the ground, of length
    one, or +z when they meet."""
    var gap = _flat_gap(a, b)
    if gap < 1.0e-4:
        return Vector3(0, 0, 1)
    return Vector3((b.x - a.x) / gap, 0, (b.z - a.z) / gap)


def nearest_door(doors: List[Doorway], player: Vector3) -> Int:
    """Return the door nearest the player on the ground.

    Args:
        doors: The houses' front doors, one or more.
        player: Where the player stands.

    Returns:
        The nearest door's index; the first of equally near ones.
    """
    var best = 0
    var nearest = Float32(1.0e30)
    for k in range(len(doors)):  # pragma: no branch
        var gap = _flat_gap(doors[k].middle(), player)
        if gap < nearest:
            nearest = gap
            best = k
    return best


def climb_step(at: Vector3, way: List[Vector3], step: Int) -> Int:
    """Return the point of a house's way up that the companion walks to
    next, as she climbs to the player.

    She starts at the first point on her own story: the foot of its
    flight. She goes on to the next point once she stands within
    `CLIMB_REACH` of the one she walks to, on the ground and in height.

    Args:
        at: Where she stands.
        way: The way up the house's stairs, one point or more, as
            `HouseInterior.climb` gives it.
        step: The point she walked to last frame, or -1 when she was not
            climbing.

    Returns:
        The point's index in `way`: the last one, at the top, once she is
        there.
    """
    var last = len(way) - 1
    var next = step
    if step < 0 or step > last:
        next = last
        for k in range(len(way)):  # pragma: no branch
            if abs(way[k].y - at.y) < CLIMB_REACH:
                next = k
                break
    ref to = way[next]
    var there = _flat_gap(at, to) < CLIMB_REACH
    if there and abs(to.y - at.y) < CLIMB_REACH:
        next = min(next + 1, last)
    return next


def follow_point(
    at: Vector3,
    player: Vector3,
    player_inside: Bool,
    ally_inside: Bool,
    doors: List[Doorway],
    keep: Float32 = FOLLOW,
) -> Vector3:
    """Return the point the companion follows out of a fight.

    She follows the player. When they are under a roof and she is not,
    she goes to the front door nearest them, and then in through it: a
    house's walls stand between her and them. Once she is inside, she
    follows them again: see `climb_step` for the stairs.

    Args:
        at: Where she stands.
        player: Where the player stands.
        player_inside: Whether the player is under a roof.
        ally_inside: Whether she is.
        doors: The houses' front doors.
        keep: How far from what she follows she stops, in meters: `FOLLOW`
            for the companion.

    Returns:
        The player's place. Or, `keep` beyond it on her way, a spot
        `DOOR_OUTSIDE` before the nearest door; and once she is within
        `DOOR_REACH` of the door, a spot `DOOR_INSIDE` past it. Off the
        door's axis by more than `DOOR_LANE`, the spot is on the axis,
        at 45 degrees from her, so that she comes onto it first.
    """
    if not player_inside or ally_inside or len(doors) == 0:
        return player
    var best = nearest_door(doors, player)
    ref door = doors[best]
    var middle = door.middle()
    var into = Vector3(door.swing_x, 0, door.swing_z)
    var spot = middle - into * DOOR_OUTSIDE
    if _flat_gap(at, middle) < DOOR_REACH:
        spot = _through(at, door, DOOR_INSIDE)
    # She stops `keep` from what she follows: the point lies that far past
    # the spot, so she stops at the spot.
    return spot + _toward(at, spot) * keep


@fieldwise_init
struct Climb(ImplicitlyCopyable):
    """Where the companion is on a house's stairs."""

    var step: Int
    """The point of the way she walks to, or -1 when she does not climb."""
    var down: Bool
    """Whether she walks the way down, from the top: its points in turn
    from the last."""


def no_climb() -> Climb:
    """Return a companion who is on no stairs.

    Returns:
        No step, and the way up.
    """
    return Climb(-1, False)


def ally_goal(
    at: Vector3,
    player: Vector3,
    player_inside: Bool,
    ally_inside: Bool,
    doors: List[Doorway],
    climbs: List[List[Vector3]],
    climb: Climb,
    keep: Float32 = FOLLOW,
) -> Tuple[Vector3, Climb]:
    """Return the point the companion follows out of a fight, and where she
    is on a house's stairs.

    - Outdoors, she follows the player, and goes in by the door nearest
      them as `follow_point` says.
    - Indoors, she does not stop within `DOOR_CLEAR` of the door: she
      walks on to `DOOR_INSIDE` past it, out of the way of those behind.
    - Indoors, when the player stands more than `CLIMB_RISE` above her,
      she climbs the stairs to them, by `climb_step`; and down them when
      they stand that far below her. Once she climbs, she climbs on until
      she is within `CLIMB_REACH` of their height.
    - Indoors, when the player has gone out, she walks down the stairs if
      she is up them, all the way to their foot, then out by the door: `DOOR_INSIDE` before it, and
      `DOOR_OUTSIDE` past it once she is within `DOOR_REACH` of it.

    The house is the one whose door is nearest the player, or nearest her
    when she goes out.

    Args:
        at: Where she stands.
        player: Where the player stands.
        player_inside: Whether the player is under a roof.
        ally_inside: Whether she is.
        doors: The houses' front doors.
        climbs: The way up each house's stairs, in the doors' order.
        climb: Where she was on the stairs last frame.
        keep: How far from what she follows she stops, in meters: `FOLLOW`
            for the companion, `FOLLOW_GAP` for a raider.

    Returns:
        The point she follows, `keep` past a spot on her way so that she
        stops at the spot; and where she is on the stairs.
    """
    var goal = follow_point(at, player, player_inside, ally_inside, doors, keep)
    if not ally_inside or len(doors) == 0:
        return (goal, no_climb())
    var leaving = not player_inside
    var house = nearest_door(doors, at if leaving else player)
    var way = List[Vector3]()
    if house < len(climbs):
        way = climbs[house].copy()
    # Once she climbs one way, she climbs on that way to the player.
    var going = climb.step >= 0
    var rise = player.y - at.y
    var up = rise > (CLIMB_REACH if going and not climb.down else CLIMB_RISE)
    var down = -rise > (CLIMB_REACH if going and climb.down else CLIMB_RISE)
    # Up the stairs: over their foot, or on the way down until she stands
    # at their foot.
    var upstairs = False
    if len(way) > 0:
        ref foot = way[0]
        var at_foot = _flat_gap(at, foot) < CLIMB_REACH
        at_foot = at_foot and abs(at.y - foot.y) < CLIMB_REACH
        var over = at.y > foot.y + CLIMB_REACH
        upstairs = not at_foot and (over or (going and climb.down))
    if leaving:
        up = False
        down = upstairs
    if (up or down) and len(way) > 0:
        if down:
            way.reverse()
        var step = climb.step if climb.down == down else -1
        var next = climb_step(at, way, step)
        ref to = way[next]
        return (to + _toward(at, to) * keep, Climb(next, down))
    ref door = doors[house]
    var middle = door.middle()
    var into = Vector3(door.swing_x, 0, door.swing_z)
    if not leaving:
        if _flat_gap(at, middle) < DOOR_CLEAR:
            var clear = middle + into * DOOR_INSIDE
            return (clear + _toward(at, clear) * keep, no_climb())
        return (goal, no_climb())
    var spot = middle + into * DOOR_INSIDE
    if _flat_gap(at, middle) < DOOR_REACH:
        spot = _through(at, door, -DOOR_OUTSIDE)
    return (spot + _toward(at, spot) * keep, no_climb())


def around_pond(
    at: Vector3,
    goal: Vector3,
    middle: Vector3,
    radius: Float32,
    keep: Float32 = FOLLOW,
) -> Vector3:
    """Return the point a follower walks to so that its way goes round a
    pond: its water is too deep to wade at the middle.

    Where the straight way from `at` to `goal` passes within
    `POND_MARGIN` of the pond's edge, the follower walks first to a point
    that far outside the edge, on the side of the pond nearest the way,
    `keep` past it so that it stops there. Its way then clears the pond.

    Args:
        at: Where the follower stands.
        goal: The point it follows.
        middle: The pond's middle; its height is not read.
        radius: The pond's radius, in meters; zero or less for no pond.
        keep: How far from what it follows the follower stops.

    Returns:
        `goal` where the way clears the pond; else the point round it.
    """
    if radius <= 0:
        return goal
    var way = Vector3(goal.x - at.x, 0, goal.z - at.z)
    var long = way.length()
    var reach = radius + POND_MARGIN
    var to = Vector3(middle.x - at.x, 0, middle.z - at.z)
    var t = (to.x * way.x + to.z * way.z) / max(long * long, Float32(1.0e-6))
    # The way's point nearest the middle, and how near it comes.
    var nearest = Vector3(at.x + way.x * t, 0, at.z + way.z * t)
    var off = Vector3(nearest.x - middle.x, 0, nearest.z - middle.z)
    var gap = off.length()
    if t <= 0 or t >= 1 or gap >= reach:
        return goal
    # Round the side the way passes, or its left where it crosses the
    # middle.
    var side = off / gap if gap > 1.0e-4 else Vector3(-way.z, 0, way.x) / long
    var round = Vector3(middle.x, at.y, middle.z) + side * (reach + POND_MARGIN)
    return round + _toward(at, round) * keep


def flank_spot(target: Vector3, player: Vector3, at: Vector3) -> Vector3:
    """Return where the companion stands in a fight.

    Args:
        target: Where the foe she casts at stands.
        player: Where the player stands.
        at: Where she stands now.

    Returns:
        The point on the ground `KEEP` from the foe, `FLANK` off the line
        from the foe to the player, on her side of that line.
    """
    var back = _toward(target, player)
    var cross = back.x * (at.z - target.z) - back.z * (at.x - target.x)
    var turn = FLANK.to(RADIAN)
    if cross < 0:
        turn = -turn
    var c = cos(turn)
    var s = sin(turn)
    var way = Vector3(back.x * c - back.z * s, 0, back.x * s + back.z * c)
    return Vector3(target.x + way.x * KEEP, target.y, target.z + way.z * KEEP)


@fieldwise_init
struct AllySight(ImplicitlyCopyable):
    """What the companion knows of the fight this frame."""

    # Where she and the player stand.
    var at: Vector3
    var player: Vector3
    # Where the foe she casts at stands, if there is one.
    var target: Optional[Vector3]
    # The share of its most that the player's health is.
    var health: Float32
    # Whether she makes no move, and whether the fight is on.
    var free: Bool
    var fighting: Bool


@fieldwise_init
struct AllyIntent(ImplicitlyCopyable):
    """What the companion means to do this frame."""

    # The way she walks, of length one or less; and whether she runs.
    var way: Vector3
    var run: Bool
    # The point she turns to face, if any.
    var face: Optional[Vector3]
    # Whether she casts a bolt, and whether she heals the player.
    var cast: Bool
    var heal: Bool


struct Companion(Copyable, Movable):
    """The companion's mind: her waits, and her assist gauge."""

    # How long until she can cast again, and heal again, in seconds.
    var cast_wait: Float32
    var mend_wait: Float32
    # How full the assist gauge is.
    var assist: Float32

    def __init__(out self):
        """Make a companion who can heal at once, casts after a second, and
        has an empty assist gauge."""
        self.cast_wait = 1
        self.mend_wait = 0
        self.assist = 0

    def charge(mut self, amount: Float32):
        """Fill the assist gauge, up to `ASSIST_FULL`.

        Args:
            amount: How much.
        """
        self.assist = min(ASSIST_FULL, self.assist + amount)

    def ready(self) -> Bool:
        """Return whether the assist gauge is full.

        Returns:
            True at `ASSIST_FULL`.
        """
        return self.assist >= ASSIST_FULL

    def spend(mut self) -> Bool:
        """Spend a full assist gauge on a assist attack.

        Returns:
            Whether the gauge was full. A full gauge empties, and the next
            plain cast waits `CAST_EVERY`.
        """
        if not self.ready():
            return False
        self.assist = 0
        self.cast_wait = CAST_EVERY
        return True

    def think(mut self, sight: AllySight, delta: Duration) -> AllyIntent:
        """Decide what to do this frame: see the module's steps.

        Args:
            sight: What she knows.
            delta: The frame's time.

        Returns:
            What she means to do.
        """
        var seconds = delta.to(SECOND)
        self.cast_wait = max(Float32(0), self.cast_wait - seconds)
        self.mend_wait = max(Float32(0), self.mend_wait - seconds)
        var out = AllyIntent(Vector3(0, 0, 0), False, None, False, False)
        var near = _flat_gap(sight.at, sight.player)
        var home = _toward(sight.at, sight.player)
        if sight.fighting:
            self.charge(ASSIST_RATE * seconds)
        if sight.fighting and sight.target:
            var target = sight.target.value()
            var gap = _flat_gap(sight.at, target)
            var spot = flank_spot(target, sight.player, sight.at)
            var off = _flat_gap(sight.at, spot)
            out.face = target
            if near > LEASH:
                out.way = home
                out.run = True
            elif off > SPOT_NEAR:
                out.way = _toward(sight.at, spot)
                out.run = off > 4
            if sight.free and self.cast_wait <= 0 and gap <= CAST_RANGE:
                out.cast = True
                self.cast_wait = CAST_EVERY
        elif near > FOLLOW:
            out.way = home
            out.run = near > 2 * FOLLOW + 1
        var low = sight.health > 0 and sight.health < MEND_BELOW
        if sight.free and low and self.mend_wait <= 0:
            out.heal = True
            self.mend_wait = MEND_EVERY
        return out


def ally_fighter() -> FighterParameters:
    """Return how strong the companion is.

    Returns:
        400 health, 100 stamina, no special gauge, bolts of the cast's own
        strength, and no surge. The foes do not attack her.
    """
    var p = FighterParameters()
    p.health = 400
    p.special_points = 0
    p.special_rate = Frequency(0.0, PER_SECOND)
    p.limit_gain = 0
    return p


def assist_blow(might: Float32) -> Blow:
    """Return what a assist attack's bolt does.

    Args:
        might: How many times its damage and stamina damage the bolt does.

    Returns:
        70 damage and 50 stamina damage, times the might; a push of 5 meters a
        second; and a blow that no guard stops, and that breaks a piercing
        attack.
    """
    return Blow(
        70 * might,
        50 * might,
        Velocity(5.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
        False,
        True,
        True,
    )


def default_allies() raises -> List[Bandit]:
    """Return the companion of the default village.

    Returns:
        One swordswoman dressed as a ranger, who starts beside the
        player: `x` and `z` are her place from the player's start, to the
        side and behind. Her seed and her heading are not used.

    Raises:
        Error: Never: the outfit checks.
    """
    return [
        Bandit(
            HumanoidSpec(Length(66.0, INCH), FEMALE, TONED, random_genome(70)),
            dressed_as(RANGER, FEMALE, 70),
            ALLY_X,
            ALLY_Z,
            Angle(0.0, DEGREE),
            70,
            ally_fighter(),
            False,
            calling_groom(RANGER, FEMALE, 70),
        )
    ]
