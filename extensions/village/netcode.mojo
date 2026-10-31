# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The fight's messages for a game of many players: a player's commands,
the snapshots of the fighters, and which fighters each player hears of.

The server runs the fight at `TICK_RATE` ticks a second, and its rules
decide every blow. Each player sends a command each tick: the tick, and
the frame's `MoveInput`, packed into `COMMAND_BYTES` bytes. See
`pack_command`. A player keeps each command until the server says it has
it, and sends those again with the next: see `InputHistory`. So a lost
message costs nothing but its bytes.

The server sends each player a snapshot of each fighter it hears of,
packed into `SNAPSHOT_BYTES` bytes: see `pack_snapshot`.

| Part | Bytes | Kept as |
|---|---|---|
| The fighter's id | 2 | A whole number |
| Where its feet are | 6 | Centimeters, to 327 meters from the middle |
| Its heading | 2 | A turn in 65,536 steps |
| Its health | 2 | A whole point |
| Its stamina and its mana | 2 | A share in 255 steps of its most |
| Its special gauge | 1 | A fiftieth of a point |
| Its move, and its clock in the move | 3 | The move, and milliseconds |
| Its stance and its style | 1 | Two bits and three bits |
| Its combo | 1 | Up to 255 blows |

**Interest.** A player does not hear of every fighter every tick. A
fighter within `NEAR` is heard every tick, within `MIDDLE` every third
tick, and within `FAR` every tenth; further away it is not heard. A
fighter heard less often is heard at a tick of its own, by its id, so the
far fighters spread over the ticks. See `relevance` and `heard`.

**Smoothing.** A client draws the other fighters `INTERPOLATION_TICKS`
behind the newest tick it heard of. A `SnapshotBuffer` keeps each
fighter's snapshots, and `blend_snapshots` draws it between two. So a
fighter heard every tenth tick still moves smoothly, and one lost
snapshot does not make it jump.
"""

from controls.third_person_controls import wrap_angle
from core.ordinal import ordinal_valid
from extensions.village.character import Character, MoveInput, Obstacle
from extensions.village.combat import (
    CombatMove,
    CombatStance,
    Fighter,
    MOVES,
)
from extensions.village.styles import FightingStyle
from math.utils import clamp
from math.vector3 import Vector3
from std.math import pi
from extensions.village.terrain import Terrain
from units.si import RADIAN, SECOND, Angle, Duration

comptime TICK_RATE = 30
"""How many ticks a second the server runs the fight at."""
comptime COMMAND_BYTES = 12
"""How many bytes a packed command takes."""
comptime SNAPSHOT_BYTES = 20
"""How many bytes a packed snapshot takes."""
comptime BUTTON_COUNT = 23
"""How many buttons a command holds."""
comptime NEAR = Float32(30)
"""How near a fighter is heard every tick, in meters."""
comptime MIDDLE = Float32(80)
"""How near a fighter is heard every third tick, in meters."""
comptime FAR = Float32(160)
"""How near a fighter is heard every tenth tick, in meters."""
comptime CENTIMETERS = Float32(100)
"""The steps a meter of a snapshot's place is kept in."""
comptime HISTORY = 64
"""How many commands an input history keeps at most."""
comptime INTERPOLATION_TICKS = Float32(3)
"""How many ticks behind the newest it heard of a client draws the other
fighters: a tenth of a second at `TICK_RATE`."""
comptime BUFFERED = 32
"""How many snapshots of a fighter a snapshot buffer keeps at most."""
comptime PREDICTED = 64
"""How many ticks of input a predictor keeps to play again at most."""
comptime _TICK = Duration(Float32(1) / Float32(TICK_RATE), SECOND)
"""How long a tick lasts."""
comptime RELEVANCES = 4
"""How many kinds of relevance there are."""


@fieldwise_init
struct Relevance(Equatable, ImplicitlyCopyable, Writable):
    """How often a player hears of a fighter, as a type rather than a bare
    int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the relevances.

        Returns:
            True from `EVERY_TICK` to `UNHEARD`.
        """
        return ordinal_valid(self.value, RELEVANCES - 1)


comptime EVERY_TICK = Relevance(0)
"""Heard of each tick."""
comptime EVERY_THIRD = Relevance(1)
"""Heard of every third tick."""
comptime EVERY_TENTH = Relevance(2)
"""Heard of every tenth tick."""
comptime UNHEARD = Relevance(3)
"""Not heard of."""


def relevance(distance: Float32) -> Relevance:
    """Return how often a player hears of a fighter some way off.

    Args:
        distance: How far the fighter is from the player, in meters.

    Returns:
        `EVERY_TICK` within `NEAR`, `EVERY_THIRD` within `MIDDLE`,
        `EVERY_TENTH` within `FAR`, and `UNHEARD` further away.
    """
    if distance <= NEAR:
        return EVERY_TICK
    if distance <= MIDDLE:
        return EVERY_THIRD
    if distance <= FAR:
        return EVERY_TENTH
    return UNHEARD


def heard(kind: Relevance, tick: Int, id: Int) -> Bool:
    """Return whether a player hears of a fighter at a tick.

    Args:
        kind: How often the player hears of it.
        tick: The tick.
        id: The fighter's id, which picks the ticks it is heard at.

    Returns:
        True each tick, at one tick in three or in ten by the id, or never.
    """
    if kind == EVERY_TICK:
        return True
    if kind == EVERY_THIRD:
        return (tick + id) % 3 == 0
    if kind == EVERY_TENTH:
        return (tick + id) % 10 == 0
    return False


def axis_byte(value: Float32) -> UInt8:
    """Return a stick's lean as a byte.

    Args:
        value: The lean, from -1 to 1.

    Returns:
        127 plus the lean times 127, rounded: 0 for -1, 127 at rest and
        254 for 1.
    """
    var v = clamp(value, -1, 1)
    return UInt8(Int(v * 127 + 127.5))


def byte_axis(byte: UInt8) -> Float32:
    """Return a stick's lean from its byte.

    Args:
        byte: The byte, from `axis_byte`.

    Returns:
        The lean, from -1 to 1, within half a step of the one packed.
    """
    return clamp((Float32(Int(byte)) - 127) / 127, -1, 1)


def buttons_of(input: MoveInput) -> List[Bool]:
    """Return the buttons of an input, in the order a command packs them.

    Args:
        input: The input.

    Returns:
        `BUTTON_COUNT` flags: the run, the jump, the use, the light and the
        heavy attacks, the three specials, the ultimate, the dodge, the
        guard, the lock, the three stances, the assist, the heal, the
        swap, the taunt and the book, and two kept for later.
    """
    return [
        input.run,
        input.jump,
        input.use,
        input.light,
        input.heavy,
        input.rising,
        input.whirlwind,
        input.ground_wave,
        input.ultimate,
        input.dodge,
        input.guard,
        input.lock,
        input.high,
        input.middle,
        input.low,
        input.assist,
        input.heal,
        input.swap,
        input.taunt,
        input.book,
        False,
        False,
        False,
    ]


def input_of(sticks: List[Float32], buttons: List[Bool]) raises -> MoveInput:
    """Return an input from its sticks and its buttons.

    Args:
        sticks: The forward, the right, the look right and the look up
            leans.
        buttons: `BUTTON_COUNT` flags, in the order of `buttons_of`.

    Returns:
        The input.

    Raises:
        Error: If there are not four sticks and `BUTTON_COUNT` buttons.
    """
    if len(sticks) != 4 or len(buttons) != BUTTON_COUNT:
        raise Error("An input has four sticks and twenty-three buttons")
    ref b = buttons
    return MoveInput(
        sticks[0],
        sticks[1],
        sticks[2],
        sticks[3],
        b[0],
        b[1],
        b[2],
        light=b[3],
        heavy=b[4],
        rising=b[5],
        whirlwind=b[6],
        ground_wave=b[7],
        ultimate=b[8],
        dodge=b[9],
        guard=b[10],
        lock=b[11],
        high=b[12],
        middle=b[13],
        low=b[14],
        assist=b[15],
        heal=b[16],
        swap=b[17],
        taunt=b[18],
        book=b[19],
    )


def _put(mut out: List[UInt8], value: Int, count: Int):
    """Append a whole number's low bytes, the lowest first."""
    for k in range(count):  # pragma: no branch
        out.append(UInt8((value >> (8 * k)) & 0xFF))


def _get(bytes: List[UInt8], at: Int, count: Int) -> Int:
    """Read a whole number of `count` bytes from `at`, the lowest first."""
    var value = 0
    for k in range(count):  # pragma: no branch
        value |= Int(bytes[at + k]) << (8 * k)
    return value


def _signed(value: Int, count: Int) -> Int:
    """Return a whole number of `count` bytes read as a signed one."""
    var top = 1 << (8 * count - 1)
    if value >= top:
        return value - 2 * top
    return value


def pack_command(tick: Int, input: MoveInput) raises -> List[UInt8]:
    """Pack a player's command for a tick.

    Args:
        tick: The tick, from 0 to 4,294,967,295.
        input: The frame's input.

    Returns:
        `COMMAND_BYTES` bytes: the tick in four, the buttons in four, one
        bit a button, and each stick's lean in one.

    Raises:
        Error: If the tick is out of range.
    """
    if not (tick >= 0 and tick <= 0xFFFFFFFF):
        raise Error("A command's tick must fit in four bytes")
    var out = List[UInt8](capacity=COMMAND_BYTES)
    _put(out, tick, 4)
    var bits = 0
    var buttons = buttons_of(input)
    for k in range(BUTTON_COUNT):  # pragma: no branch
        if buttons[k]:
            bits |= 1 << k
    _put(out, bits, 4)
    out.append(axis_byte(input.forward))
    out.append(axis_byte(input.right))
    out.append(axis_byte(input.look_right))
    out.append(axis_byte(input.look_up))
    return out^


def unpack_command(
    bytes: List[UInt8], at: Int = 0
) raises -> Tuple[Int, MoveInput]:
    """Unpack a player's command.

    Args:
        bytes: The bytes.
        at: Where the command starts in them.

    Returns:
        The tick, and the input: each stick within half a step of the one
        packed, and each button as it was.

    Raises:
        Error: If the bytes end before the command does.
    """
    if not (at >= 0 and at + COMMAND_BYTES <= len(bytes)):
        raise Error("A command must have twelve bytes")
    var tick = _get(bytes, at, 4)
    var bits = _get(bytes, at + 4, 4)
    var buttons = List[Bool]()
    for k in range(BUTTON_COUNT):  # pragma: no branch
        buttons.append((bits >> k) & 1 == 1)
    var sticks: List[Float32] = [
        byte_axis(bytes[at + 8]),
        byte_axis(bytes[at + 9]),
        byte_axis(bytes[at + 10]),
        byte_axis(bytes[at + 11]),
    ]
    return (tick, input_of(sticks, buttons))


@fieldwise_init
struct FighterSnapshot(ImplicitlyCopyable):
    """A fighter as the server sends it: where it is, and what it does."""

    var id: Int
    var position: Vector3
    var heading: Angle
    var health: Float32
    # The shares of its most stamina and mana it has.
    var stamina: Float32
    var mana: Float32
    var special: Float32
    var move: CombatMove
    # How far into its move it is, in seconds.
    var clock: Float32
    var stance: CombatStance
    var style: FightingStyle
    var combo: Int


def snapshot_of(
    id: Int, character: Character, fighter: Fighter
) -> FighterSnapshot:
    """Return the snapshot of a fighter.

    Args:
        id: The fighter's id.
        character: Where it is.
        fighter: What it does.

    Returns:
        Its snapshot.
    """
    ref p = fighter.parameters
    return FighterSnapshot(
        id,
        character.position,
        character.heading,
        fighter.health,
        fighter.stamina / p.stamina,
        fighter.mana / p.mana if p.mana > 0 else Float32(0),
        fighter.special,
        fighter.move,
        fighter.clock,
        fighter.stance,
        fighter.style,
        fighter.combo,
    )


def _place(value: Float32) -> Int:
    """Return a coordinate in centimeters, kept to two bytes."""
    var steps = Int(clamp(value * CENTIMETERS, -32767, 32767))
    return steps & 0xFFFF


def pack_snapshot(snapshot: FighterSnapshot) raises -> List[UInt8]:
    """Pack a fighter's snapshot: see the module's table.

    Args:
        snapshot: The snapshot.

    Returns:
        `SNAPSHOT_BYTES` bytes.

    Raises:
        Error: If the id is not from 0 to 65,535, or the move, the stance
            or the style is not one.
    """
    ref s = snapshot
    if not (s.id >= 0 and s.id <= 0xFFFF):
        raise Error("A fighter's id must fit in two bytes")
    if not (s.move.is_valid() and s.stance.is_valid() and s.style.is_valid()):
        raise Error("A snapshot's move, stance and style must each be one")
    var out = List[UInt8](capacity=SNAPSHOT_BYTES)
    _put(out, s.id, 2)
    _put(out, _place(s.position.x), 2)
    _put(out, _place(s.position.y), 2)
    _put(out, _place(s.position.z), 2)
    var turn = s.heading.to(RADIAN) / Float32(2 * pi)
    turn -= Float32(Int(turn))
    if turn < 0:
        turn += 1
    _put(out, Int(turn * 65536) & 0xFFFF, 2)
    _put(out, Int(clamp(s.health, 0, 65535) + 0.5), 2)
    out.append(UInt8(Int(clamp(s.stamina, 0, 1) * 255 + 0.5)))
    out.append(UInt8(Int(clamp(s.mana, 0, 1) * 255 + 0.5)))
    out.append(UInt8(Int(clamp(s.special * 50, 0, 255) + 0.5)))
    out.append(UInt8(s.move.value))
    _put(out, Int(clamp(s.clock * 1000, 0, 65535) + 0.5), 2)
    out.append(UInt8(s.stance.value | (s.style.value << 2)))
    out.append(UInt8(min(255, max(0, s.combo))))
    return out^


def unpack_snapshot(bytes: List[UInt8], at: Int = 0) raises -> FighterSnapshot:
    """Unpack a fighter's snapshot.

    Args:
        bytes: The bytes.
        at: Where the snapshot starts in them.

    Returns:
        The snapshot, each value within half a step of the one packed.

    Raises:
        Error: If the bytes end before the snapshot does, or its move, its
            stance or its style is not one.
    """
    if not (at >= 0 and at + SNAPSHOT_BYTES <= len(bytes)):
        raise Error("A snapshot must have twenty bytes")
    var id = _get(bytes, at, 2)
    var x = Float32(_signed(_get(bytes, at + 2, 2), 2)) / CENTIMETERS
    var y = Float32(_signed(_get(bytes, at + 4, 2), 2)) / CENTIMETERS
    var z = Float32(_signed(_get(bytes, at + 6, 2), 2)) / CENTIMETERS
    var turn = Float32(_get(bytes, at + 8, 2)) / 65536 * Float32(2 * pi)
    var health = Float32(_get(bytes, at + 10, 2))
    var stamina = Float32(Int(bytes[at + 12])) / 255
    var mana = Float32(Int(bytes[at + 13])) / 255
    var special = Float32(Int(bytes[at + 14])) / 50
    var move = CombatMove(Int(bytes[at + 15]))
    var clock = Float32(_get(bytes, at + 16, 2)) / 1000
    var packed = Int(bytes[at + 18])
    var stance = CombatStance(packed & 3)
    var style = FightingStyle(packed >> 2)
    var combo = Int(bytes[at + 19])
    if not (move.is_valid() and stance.is_valid() and style.is_valid()):
        raise Error("A snapshot's move, stance and style must each be one")
    if turn > Float32(pi):
        turn -= Float32(2 * pi)
    return FighterSnapshot(
        id,
        Vector3(x, y, z),
        Angle(turn, RADIAN),
        health,
        stamina,
        mana,
        special,
        move,
        clock,
        stance,
        style,
        combo,
    )


def apply_snapshot(
    snapshot: FighterSnapshot, mut character: Character, mut fighter: Fighter
) raises:
    """Set a client's copy of a fighter from the server's snapshot.

    Args:
        snapshot: The snapshot.
        character: The client's character of the fighter.
        fighter: The client's fighter.

    Raises:
        Error: If the snapshot's style is not one.
    """
    character.position = snapshot.position
    character.heading = snapshot.heading
    ref p = fighter.parameters
    fighter.health = snapshot.health
    fighter.stamina = snapshot.stamina * p.stamina
    fighter.mana = snapshot.mana * p.mana
    fighter.special = snapshot.special
    fighter.move = snapshot.move
    fighter.clock = snapshot.clock
    fighter.stance = snapshot.stance
    if fighter.style != snapshot.style:
        var move = fighter.move
        fighter.move = CombatMove(0)
        _ = fighter.set_style(snapshot.style)
        fighter.move = move
    fighter.combo = snapshot.combo


struct InputHistory(Copyable, Movable):
    """The commands a player sent that the server has not said it has."""

    var ticks: List[Int]
    var commands: List[List[UInt8]]
    # The last tick sent, or -1.
    var last: Int

    def __init__(out self):
        """Hold no commands, and have sent none."""
        self.ticks = List[Int]()
        self.commands = List[List[UInt8]]()
        self.last = -1

    def send(mut self, tick: Int, input: MoveInput) raises -> List[UInt8]:
        """Keep a tick's command, and return every command kept, oldest
        first, for one message.

        Args:
            tick: The tick, after the last one sent.
            input: The frame's input.

        Returns:
            The packed commands kept, `COMMAND_BYTES` each. At most
            `HISTORY` are kept: the oldest goes first.

        Raises:
            Error: If the tick is not after the last one sent, or out of
                range.
        """
        if tick <= self.last:
            raise Error("A command's tick must follow the last one sent")
        var packed = pack_command(tick, input)
        self.last = tick
        self.ticks.append(tick)
        self.commands.append(packed^)
        if len(self.ticks) > HISTORY:
            _ = self.ticks.pop(0)
            _ = self.commands.pop(0)
        var out = List[UInt8]()
        for command in self.commands:  # pragma: no branch
            out.extend(command.copy())
        return out^

    def ack(mut self, tick: Int):
        """Forget each command up to a tick, which the server says it has.

        Args:
            tick: The last tick the server has.
        """
        while len(self.ticks) > 0 and self.ticks[0] <= tick:
            _ = self.ticks.pop(0)
            _ = self.commands.pop(0)

    def waiting(self) -> Int:
        """Return how many commands the server has not said it has.

        Returns:
            The count.
        """
        return len(self.ticks)


def blend_snapshots(
    a: FighterSnapshot, b: FighterSnapshot, t: Float32
) raises -> FighterSnapshot:
    """Return a fighter between two of its snapshots, as a client draws it
    between the ticks the server sent.

    Args:
        a: The earlier snapshot.
        b: The later snapshot.
        t: How far from `a` to `b`, from 0 to 1.

    Returns:
        Its place, its health, its stamina, its mana and its special gauge
        blended, and its heading turned the short way. Its move, its
        stance, its style and its combo are the nearer snapshot's. Its
        clock is blended while both have the same move.

    Raises:
        Error: If the two are not of one fighter, or `t` is not from 0
            to 1.
    """
    if a.id != b.id:
        raise Error("Two blended snapshots must be of one fighter")
    if not (t >= 0 and t <= 1):
        raise Error("A blend must be from 0 to 1")
    var out = b if t >= 0.5 else a
    out.position = a.position + (b.position - a.position) * t
    var turn = wrap_angle(
        Angle(b.heading.to(RADIAN) - a.heading.to(RADIAN), RADIAN)
    )
    out.heading = wrap_angle(
        Angle(a.heading.to(RADIAN) + turn.to(RADIAN) * t, RADIAN)
    )
    out.health = a.health + (b.health - a.health) * t
    out.stamina = a.stamina + (b.stamina - a.stamina) * t
    out.mana = a.mana + (b.mana - a.mana) * t
    out.special = a.special + (b.special - a.special) * t
    if a.move == b.move:
        out.clock = a.clock + (b.clock - a.clock) * t
    return out


struct SnapshotBuffer(Copyable, Movable):
    """A fighter's latest snapshots, by tick, so a client can draw it
    smoothly between them.

    A client draws the other fighters `INTERPOLATION_TICKS` behind the
    newest tick it heard of, so that one lost or late snapshot still
    leaves two around the tick it draws.
    """

    var ticks: List[Int]
    var snapshots: List[FighterSnapshot]

    def __init__(out self):
        """Hold no snapshots."""
        self.ticks = List[Int]()
        self.snapshots = List[FighterSnapshot]()

    def add(mut self, tick: Int, snapshot: FighterSnapshot) raises -> Bool:
        """Keep a fighter's snapshot of a tick.

        Args:
            tick: The tick the server sent it for.
            snapshot: The snapshot.

        Returns:
            Whether it was kept. A snapshot that comes late, of a tick at
            or before the newest kept, is dropped. At most `BUFFERED` are
            kept: the oldest goes first.

        Raises:
            Error: If it is of another fighter than those kept.
        """
        if len(self.snapshots) > 0 and snapshot.id != self.snapshots[0].id:
            raise Error("A snapshot buffer holds one fighter")
        if len(self.ticks) > 0 and tick <= self.ticks[len(self.ticks) - 1]:
            return False
        self.ticks.append(tick)
        self.snapshots.append(snapshot)
        if len(self.ticks) > BUFFERED:
            _ = self.ticks.pop(0)
            _ = self.snapshots.pop(0)
        return True

    def at(self, tick: Float32) raises -> Optional[FighterSnapshot]:
        """Return the fighter at a tick, which can fall between two.

        Args:
            tick: The tick to draw, as `newest - INTERPOLATION_TICKS` and
                the time since.

        Returns:
            None with no snapshot kept. The first snapshot for a tick
            before it, and the last for a tick after it: the fighter holds
            still until the server says more. Else the blend of the two
            snapshots around the tick.

        Raises:
            Error: Never: the snapshots kept are of one fighter.
        """
        var count = len(self.ticks)
        if count == 0:
            return None
        if tick <= Float32(self.ticks[0]):
            return self.snapshots[0]
        for k in range(1, count):
            if tick <= Float32(self.ticks[k]):
                var start = Float32(self.ticks[k - 1])
                var t = (tick - start) / (Float32(self.ticks[k]) - start)
                return blend_snapshots(
                    self.snapshots[k - 1], self.snapshots[k], t
                )
        return self.snapshots[count - 1]


struct Predictor(Copyable, Movable):
    """A client's own character, moved at once by each tick's input, and
    set right by the server's snapshots.

    The client does not wait for the server to move its player. It steps
    the character at once, and keeps each tick's input and the state it
    led to. When a snapshot of the player comes, `reconcile` takes the
    server's word for that tick, and plays each later input again.
    """

    var character: Character
    # Each tick stepped, its input and its camera's yaw, and the character
    # after it, oldest first.
    var ticks: List[Int]
    var inputs: List[MoveInput]
    var yaws: List[Angle]
    var states: List[Character]

    def __init__(out self, var character: Character):
        """Predict a character from where it stands.

        Args:
            character: The client's own character.
        """
        self.character = character^
        self.ticks = List[Int]()
        self.inputs = List[MoveInput]()
        self.yaws = List[Angle]()
        self.states = List[Character]()

    def step(
        mut self,
        tick: Int,
        input: MoveInput,
        yaw: Angle,
        terrain: Terrain,
        obstacles: List[Obstacle],
    ) raises:
        """Move the character by a tick's input at once, and keep the input
        to play again.

        Args:
            tick: The tick, after the last one stepped.
            input: The tick's input.
            yaw: The camera's yaw.
            terrain: The ground.
            obstacles: The round things in the way.

        Raises:
            Error: If the tick is not after the last one stepped, or the
                character cannot move.
        """
        var count = len(self.ticks)
        if count > 0 and tick <= self.ticks[count - 1]:
            raise Error("A predicted tick must follow the last one")
        self.character.step(input, yaw, _TICK, terrain, obstacles)
        self.ticks.append(tick)
        self.inputs.append(input)
        self.yaws.append(yaw)
        self.states.append(self.character.copy())
        if len(self.ticks) > PREDICTED:
            self._forget(1)

    def _forget(mut self, count: Int):
        """Drop the oldest `count` ticks kept."""
        for _ in range(count):
            _ = self.ticks.pop(0)
            _ = self.inputs.pop(0)
            _ = self.yaws.pop(0)
            _ = self.states.pop(0)

    def reconcile(
        mut self,
        tick: Int,
        snapshot: FighterSnapshot,
        terrain: Terrain,
        obstacles: List[Obstacle],
    ) raises -> Float32:
        """Take the server's word for where the character stood at a tick,
        and play each later input again from there.

        Args:
            tick: The tick of the snapshot.
            snapshot: The server's snapshot of the character.
            terrain: The ground.
            obstacles: The round things in the way.

        Returns:
            How far the character's place moved, in meters: zero when the
            server agrees with the prediction. A snapshot older than each
            tick kept changes nothing. One after each tick kept places the
            character where it says, and forgets the inputs.

        Raises:
            Error: If the character cannot move.
        """
        var before = self.character.position
        var count = len(self.ticks)
        if count == 0 or tick > self.ticks[count - 1]:
            self.character.position = snapshot.position
            self.character.heading = snapshot.heading
            self._forget(count)
            return (self.character.position - before).length()
        if tick < self.ticks[0]:
            return 0
        # The state after the snapshot's tick: that tick's, or, when the
        # client stepped no input at it, the last before it.
        var at = 0
        while self.ticks[at] < tick:
            at += 1
        if self.ticks[at] > tick:
            at -= 1
        self._forget(at)
        var base = self.states[0].copy()
        base.position = snapshot.position
        base.heading = snapshot.heading
        self.states[0] = base.copy()
        self.character = base^
        for k in range(1, len(self.ticks)):
            self.character.step(
                self.inputs[k], self.yaws[k], _TICK, terrain, obstacles
            )
            self.states[k] = self.character.copy()
        return (self.character.position - before).length()
