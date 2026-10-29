# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Villagers a player can talk to, and the errands they give.

A `Speaker` is a villager with a name and some lines to say. A speaker
can also have an `Errand`: things to bring, and coins to pay for them.
`Talk` keeps each errand's state, an `ErrandState`:

| State | The speaker's marker | A word with the speaker |
|---|---|---|
| `OFFERED` | A gold `!` turns over their head | They ask for the things. The errand is taken. |
| `TAKEN` | A silver `!` | With enough of the things in the satchel, they take them, pay, and thank the player. The errand is done. Without, they say how many more they need. |
| `DONE` | None | They say their lines, one after another. |

A speaker with no errand says their lines, one after another.

The nearest speaker within `Talk.reach` of the player's feet is the
focus. A new press of the use button speaks to the focus. What the
speaker says shows for `SPEECH_SECONDS`, after their name.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.ordinal import ordinal_valid
from core.scene import Scene
from extensions.village.gathering import (
    BERRIES,
    CHEST,
    GatherKind,
    HERBS,
    MUSHROOMS,
    ORE,
    Satchel,
    kind_name,
)
from extensions.village.sheet import Sheet
from extensions.village.surfaces import HouseLooks
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import sin
from units.si import RADIAN, SECOND, Angle, Duration

comptime SPEECH_SECONDS = Float32(5)
"""How long a speaker's words show, in seconds."""
comptime MARKER_LIFT = Float32(0.55)
"""How far over a speaker's head their marker turns, in meters."""
comptime OFFER_GOLD = Vector3(1.0, 0.78, 0.15)
"""The color of the marker of an errand offered, drawn unlit."""
comptime TAKEN_SILVER = Vector3(0.75, 0.78, 0.82)
"""The color of the marker of an errand taken, drawn unlit."""


@fieldwise_init
struct ErrandState(Equatable, ImplicitlyCopyable, Writable):
    """How far along an errand is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three states there are.

        Returns:
            Whether the value names a state.
        """
        return ordinal_valid(self.value, 2)


comptime OFFERED = ErrandState(0)
comptime TAKEN = ErrandState(1)
comptime DONE = ErrandState(2)


@fieldwise_init
struct Errand(Copyable, Movable):
    """Things a speaker wants brought, and what they pay."""

    # What the speaker wants, and how many.
    var wants: GatherKind
    var count: Int
    # How many coins they pay.
    var reward: Int
    # What they say when they ask, and when they are paid.
    var ask: String
    var thanks: String

    def check(self) raises:
        """Refuse an errand that cannot be done.

        Raises:
            Error: If the things wanted are not a kind, are coins, or are
                fewer than one; or the reward is negative.
        """
        if not self.wants.is_valid() or self.wants == CHEST:
            raise Error(
                "An errand must want herbs, mushrooms, berries, ore or trinkets"
            )
        if self.count < 1:
            raise Error("An errand must want one thing or more")
        if self.reward < 0:
            raise Error("An errand's reward must not be negative")


@fieldwise_init
struct Speaker(Copyable, Movable):
    """A villager who talks, and the errand they give, if any."""

    # The villager's place among the residents' people.
    var villager: Int
    var name: String
    # What they say, one line a word with them.
    var lines: List[String]
    var errand: Optional[Errand]


def default_speakers() -> List[Speaker]:
    """Return the speakers of the default village.

    Returns:
        The woman by the brick house, a herbalist who wants five herbs;
        the man on the trail, a smith who wants three ore; the child by
        the pond, who wants six berries; the old man by the framed
        cottage, a forager who wants four mushrooms; and the woman by the
        framed house, who has no errand.
    """
    return [
        Speaker(
            0,
            "Maud",
            [
                "The herbs by the trail cure a cough.",
                "Mind the deer, they startle.",
            ],
            Errand(
                HERBS,
                5,
                20,
                "Bring me five herbs and I will pay you well.",
                "Fresh herbs! Here are your coins.",
            ),
        ),
        Speaker(
            1,
            "Osric",
            ["My forge is cold today.", "Copper shows green in the rock."],
            Errand(
                ORE,
                3,
                30,
                "Three ore from the boulders, and I will pay.",
                "Good ore. Take these coins.",
            ),
        ),
        Speaker(
            2,
            "Wren",
            ["I can run round the pond twice!", "Did you see the rabbits?"],
            Errand(
                BERRIES,
                6,
                8,
                "Will you pick me six berries? I can pay!",
                "Berries! Thank you, here.",
            ),
        ),
        Speaker(
            3,
            "Aldous",
            [
                "The old chest by the barn is not mine.",
                "Rain is coming, I feel it.",
            ],
            Errand(
                MUSHROOMS,
                4,
                15,
                "Four red mushrooms for my stew, if you please.",
                "A fine stew tonight. Your coins.",
            ),
        ),
        Speaker(
            4,
            "Edith",
            [
                "Good day to you.",
                "The well water is sweet.",
                "Lost trinkets glint in the grass.",
            ],
            None,
        ),
    ]


def _bang(color: Vector3) -> Sheet:
    """Return an `!` 40 centimeters tall, its foot at the origin: a bar
    over a dot."""
    var sheet = Sheet(1)
    sheet.box(
        Vector3(0, 0.25, 0),
        Vector3(0.04, 0, 0),
        Vector3(0, 0.15, 0),
        Vector3(0, 0, 0.04),
        color,
    )
    sheet.box(
        Vector3(0, 0.04, 0),
        Vector3(0.04, 0, 0),
        Vector3(0, 0.04, 0),
        Vector3(0, 0, 0.04),
        color,
    )
    return sheet^


struct Talk(Movable):
    """The village's speakers, their errands, and what was last said."""

    var speakers: List[Speaker]
    var states: List[ErrandState]
    # The next of each speaker's lines.
    var next_line: List[Int]
    # How near a speaker the player's feet must be, in meters.
    var reach: Float32
    # The speaker in reach, or -1.
    var focus: Int
    # What was last said, with the speaker's name, and how long ago, in
    # seconds.
    var speech: String
    var age: Float32
    # Whether the use button was held last frame.
    var held: Bool
    var clock: Float32
    # Each speaker's two markers, offered and taken.
    var offers: List[NodeId]
    var takens: List[NodeId]

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        looks: HouseLooks,
        var speakers: List[Speaker],
        people: Int,
    ) raises:
        """Add the markers of each speaker who is one of the villagers.

        A speaker who is not one of the villagers is left out, so a
        village with fewer villagers keeps the speakers it has.

        Args:
            scene: The scene. Two nodes and two meshes are added for each
                speaker kept, with or without an errand.
            assets: The stores for the geometries.
            looks: The village's materials: the markers are unlit.
            speakers: The speakers.
            people: How many villagers there are.

        Raises:
            Error: If two speakers are one villager, or an errand does not
                check.
        """
        var gold = assets.geometries.add(_bang(OFFER_GOLD).geometry())
        var silver = assets.geometries.add(_bang(TAKEN_SILVER).geometry())
        self.states = List[ErrandState]()
        self.next_line = List[Int]()
        self.offers = List[NodeId]()
        self.takens = List[NodeId]()
        var taken = List[Bool](length=max(people, 0), fill=False)
        var kept = List[Speaker]()
        for index in range(len(speakers)):
            ref speaker = speakers[index]
            if speaker.villager < 0 or speaker.villager >= people:
                continue
            if taken[speaker.villager]:
                raise Error("Two speakers must not be one villager")
            taken[speaker.villager] = True
            if speaker.errand:
                speaker.errand.value().check()
                self.states.append(OFFERED)
            else:
                self.states.append(DONE)
            self.next_line.append(0)
            var offer = Object3D()
            offer.visible = Bool(speaker.errand)
            var at = scene.add(offer^)
            scene.add_mesh(Mesh(gold, looks.daylight, at, cast_shadow=False))
            self.offers.append(at)
            var wait = Object3D()
            wait.visible = False
            var waiting = scene.add(wait^)
            scene.add_mesh(
                Mesh(silver, looks.daylight, waiting, cast_shadow=False)
            )
            self.takens.append(waiting)
            kept.append(speaker.copy())
        self.speakers = kept^
        self.reach = 2.2
        self.focus = -1
        self.speech = String()
        self.age = SPEECH_SECONDS
        self.held = False
        self.clock = 0

    def nearest(self, feet: Vector3, places: List[Vector3]) -> Int:
        """Return the speaker nearest a player's feet, within reach.

        Args:
            feet: Where the player's feet are.
            places: Where each villager's feet are.

        Returns:
            The speaker's place in `speakers`, or -1 if none is within
            `reach`, and within 1.5 meters above or below the feet.
        """
        var best = -1
        var nearest = self.reach * self.reach
        for index in range(len(self.speakers)):
            ref p = places[self.speakers[index].villager]
            if abs(p.y - feet.y) > 1.5:
                continue
            var dx = p.x - feet.x
            var dz = p.z - feet.z
            var d = dx * dx + dz * dz
            if d <= nearest:
                nearest = d
                best = index
        return best

    def speak(mut self, index: Int, mut satchel: Satchel) raises -> String:
        """Have a speaker say their next words to the player, and move
        their errand on.

        Args:
            index: The speaker's place in `speakers`.
            satchel: What the player holds: an errand's things come out of
                it, and its coins go in.

        Returns:
            What they say.

        Raises:
            Error: If the speaker is not one.
        """
        if index < 0 or index >= len(self.speakers):
            raise Error("A speaker must be one of the village's")
        ref speaker = self.speakers[index]
        var state = self.states[index]
        if state == OFFERED:
            self.states[index] = TAKEN
            return speaker.errand.value().ask.copy()
        if state == TAKEN:
            ref errand = speaker.errand.value()
            var held = satchel.count(errand.wants)
            if held >= errand.count:
                satchel.counts[errand.wants.value] -= errand.count
                satchel.counts[CHEST.value] += errand.reward
                self.states[index] = DONE
                return errand.thanks.copy()
            return String(
                "I still need ",
                errand.count - held,
                " more ",
                kind_name(errand.wants),
                ".",
            )
        var line = speaker.lines[self.next_line[index] % len(speaker.lines)]
        self.next_line[index] += 1
        return line

    def update(
        mut self,
        mut scene: Scene,
        feet: Vector3,
        places: List[Vector3],
        heads: List[Float32],
        use: Bool,
        mut satchel: Satchel,
        delta: Duration,
    ) raises -> Bool:
        """Run one frame: find the speaker in reach, speak to them on a
        new press of the use button, and turn each marker over its
        speaker's head.

        Args:
            scene: The scene the markers are in.
            feet: Where the player's feet are.
            places: Where each villager's feet are.
            heads: How tall each villager is, in meters.
            use: Whether the use button is held, and free for talk: not
                used for a spot this frame.
            satchel: What the player holds.
            delta: The frame's time.

        Returns:
            Whether a speaker spoke this frame.

        Raises:
            Error: If the time is negative.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        self.clock += seconds
        self.age += seconds
        var pressed = use and not self.held
        self.held = use
        self.focus = self.nearest(feet, places)
        var spoke = False
        if pressed and self.focus >= 0:
            var words = self.speak(self.focus, satchel)
            self.speech = String(self.speakers[self.focus].name, ": ", words)
            self.age = 0
            spoke = True
        var bob = 0.06 * sin(self.clock * 2.5)
        var turn = Angle(self.clock * 1.8, RADIAN)
        for index in range(len(self.speakers)):
            var v = self.speakers[index].villager
            ref p = places[v]
            var y = p.y + heads[v] + MARKER_LIFT + bob
            ref offer = scene.node(self.offers[index])
            offer.visible = self.states[index] == OFFERED
            offer.set_position(p.x, y, p.z)
            offer.set_rotation_from_axis_angle(Vector3(0, 1, 0), turn)
            ref waiting = scene.node(self.takens[index])
            waiting.visible = self.states[index] == TAKEN
            waiting.set_position(p.x, y, p.z)
            waiting.set_rotation_from_axis_angle(Vector3(0, 1, 0), turn)
        return spoke

    def prompt(self) -> String:
        """Return what the use button does with the speaker in reach.

        Returns:
            "E  TALK TO" and their name, or an empty string if no speaker
            is in reach.
        """
        if self.focus < 0:
            return String()
        return String("E  TALK TO ", self.speakers[self.focus].name)

    def errands(self, satchel: Satchel) raises -> List[String]:
        """Return a line for each errand taken and not yet done.

        Args:
            satchel: What the player holds.

        Returns:
            The things and how many the player holds of how many are
            wanted, and for whom, such as "HERBS FOR MAUD 2/5".

        Raises:
            Error: Never: each errand's kind checks.
        """
        var lines = List[String]()
        for index in range(len(self.speakers)):
            if self.states[index] != TAKEN:
                continue
            ref errand = self.speakers[index].errand.value()
            var held = min(satchel.count(errand.wants), errand.count)
            lines.append(
                String(
                    kind_name(errand.wants),
                    " for ",
                    self.speakers[index].name,
                    " ",
                    held,
                    "/",
                    errand.count,
                )
            )
        return lines^
