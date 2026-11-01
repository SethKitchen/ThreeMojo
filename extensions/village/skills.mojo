# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's skills, which grow with use: three of gathering, and one
for each fighting style.

Each thing gathered gives experience to one skill, a `SkillKind`:

| Skill | Gathered from | Experience for each thing | What a higher level does |
|---|---|---|---|
| `FORAGING` | Herbs, mushrooms and berries | 10, 6 and 4 | From `FORAGE_BONUS_LEVEL`, each pick gives one thing more |
| `MINING` | Ore | 30 | One strike fewer for each `MINING_STEP` levels, down to one |
| `FISHING` | Fish | 25 | A fish bites sooner: the wait is `FISH_HASTE` shorter for each level |

Coins and trinkets give no experience. Each fighting style has its own
skill, which grows as the player fights in that style: see `style_skill`.

| Style | Skill |
|---|---|
| Hand to hand | `BRAWLING` |
| The sword | `SWORDPLAY` |
| The axe | `AXEWORK` |
| The mace | `MACEWORK` |
| Magic | `SPELLCRAFT` |
| Archery | `MARKSMANSHIP` |

A fighting skill gets `BLOW_EXPERIENCE` for each of the player's blows
that lands on a foe, `PRACTICE_EXPERIENCE` for each that lands on a straw
dummy, and `DEFEAT_EXPERIENCE` for each foe felled. Each level over 1
makes the player's blows in its style `FIGHTING_MIGHT` stronger: see
`fighting_might`. A level also teaches the style's combos: see
`extensions.village.combos`.

A skill begins at level 1 and
stops at `MAX_LEVEL`. Level `L` needs `level_experience(L)`: 25 times
`L - 1` times `L`, so 50 for level 2, 150 for level 3 and 2,250 for
level 10.
"""

from core.ordinal import ordinal_valid
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    FightingStyle,
)
from extensions.village.gathering import (
    BERRIES,
    FISH,
    GatherKind,
    HERBS,
    MUSHROOMS,
    ORE,
    STRIKES,
)

comptime SKILLS = 9
"""How many skills there are."""
comptime MAX_LEVEL = 10
"""The highest level of a skill."""
comptime FORAGE_BONUS_LEVEL = 5
"""The foraging level from which each pick gives one thing more."""
comptime MINING_STEP = 3
"""How many mining levels take one strike off a boulder."""
comptime FISH_HASTE = Float32(0.06)
"""How much shorter a fish's wait is for each fishing level over 1."""
comptime FIGHTING_MIGHT = Float32(0.05)
"""How much stronger the player's blows in a style are for each level of
its skill over 1."""
comptime BLOW_EXPERIENCE = 2
"""The fighting experience of a blow that lands on a foe."""
comptime PRACTICE_EXPERIENCE = 1
"""The fighting experience of a blow that lands on a straw dummy."""
comptime DEFEAT_EXPERIENCE = 40
"""The fighting experience of a foe felled."""


@fieldwise_init
struct SkillKind(Equatable, ImplicitlyCopyable, Writable):
    """One of the player's skills, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the skills.

        Returns:
            True from `FORAGING` to `MARKSMANSHIP`.
        """
        return ordinal_valid(self.value, SKILLS - 1)


comptime FORAGING = SkillKind(0)
"""Picking herbs, mushrooms and berries."""
comptime MINING = SkillKind(1)
"""Striking ore from the boulders."""
comptime FISHING = SkillKind(2)
"""Hooking fish in the pond."""
comptime SWORDPLAY = SkillKind(3)
"""Fighting with the sword."""
comptime BRAWLING = SkillKind(4)
"""Fighting hand to hand."""
comptime AXEWORK = SkillKind(5)
"""Fighting with the axe."""
comptime MACEWORK = SkillKind(6)
"""Fighting with the mace."""
comptime SPELLCRAFT = SkillKind(7)
"""Fighting with magic."""
comptime MARKSMANSHIP = SkillKind(8)
"""Fighting with the bow."""


def skill_name(skill: SkillKind) raises -> String:
    """Return a skill's name, in capitals for the display.

    Args:
        skill: The skill.

    Returns:
        "FORAGING", "MINING", "FISHING", "SWORDPLAY", "BRAWLING",
        "AXEWORK", "MACEWORK", "SPELLCRAFT" or "MARKSMANSHIP".

    Raises:
        Error: If the skill is not one.
    """
    if not skill.is_valid():
        raise Error("A skill must be one of the nine")
    var names: List[String] = [
        "FORAGING",
        "MINING",
        "FISHING",
        "SWORDPLAY",
        "BRAWLING",
        "AXEWORK",
        "MACEWORK",
        "SPELLCRAFT",
        "MARKSMANSHIP",
    ]
    return names[skill.value]


def style_skill(style: FightingStyle) raises -> SkillKind:
    """Return the skill that fighting in a style trains.

    Args:
        style: The style.

    Returns:
        `BRAWLING`, `SWORDPLAY`, `AXEWORK`, `MACEWORK`, `SPELLCRAFT` or
        `MARKSMANSHIP`.

    Raises:
        Error: If the style is not one.
    """
    if not style.is_valid():
        raise Error("A fighting style must be one of the six")
    if style == HAND_TO_HAND:
        return BRAWLING
    if style == AXE:
        return AXEWORK
    if style == MACE:
        return MACEWORK
    if style == MAGIC:
        return SPELLCRAFT
    if style == ARCHERY:
        return MARKSMANSHIP
    return SWORDPLAY


def skill_of(kind: GatherKind) -> Optional[SkillKind]:
    """Return the skill that gathering a kind of thing trains.

    Args:
        kind: The kind of spot.

    Returns:
        `FORAGING` for herbs, mushrooms and berries, `MINING` for ore and
        `FISHING` for fish. None for a chest and a trinket.
    """
    if kind == HERBS or kind == MUSHROOMS or kind == BERRIES:
        return FORAGING
    if kind == ORE:
        return MINING
    if kind == FISH:
        return FISHING
    return None


def experience_for(kind: GatherKind) -> Int:
    """Return the experience that one thing of a kind gives.

    Args:
        kind: The kind of spot.

    Returns:
        10 for an herb, 6 for a mushroom, 4 for a berry, 30 for ore, 25
        for a fish, and 0 for a coin or a trinket.
    """
    if kind == HERBS:
        return 10
    if kind == MUSHROOMS:
        return 6
    if kind == BERRIES:
        return 4
    if kind == ORE:
        return 30
    if kind == FISH:
        return 25
    return 0


def level_experience(level: Int) -> Int:
    """Return the experience a skill needs to reach a level.

    Args:
        level: The level, from 1.

    Returns:
        25 times `level - 1` times `level`: 0 for level 1.
    """
    return 25 * (level - 1) * level


def level_of(experience: Int) -> Int:
    """Return the level of a skill with some experience.

    Args:
        experience: The skill's experience.

    Returns:
        The highest level, up to `MAX_LEVEL`, whose experience it has.
    """
    var level = 1
    while level < MAX_LEVEL and experience >= level_experience(level + 1):
        level += 1
    return level


def ore_strikes(level: Int) -> Int:
    """Return how many strikes a boulder takes to give its ore.

    Args:
        level: The mining level.

    Returns:
        `STRIKES` at levels 1 to 3, one fewer for each `MINING_STEP`
        levels more, and never less than one.
    """
    return max(1, STRIKES - (level - 1) // MINING_STEP)


def forage_bonus(level: Int) -> Int:
    """Return how many more things a pick of herbs, mushrooms or berries
    gives.

    Args:
        level: The foraging level.

    Returns:
        One from `FORAGE_BONUS_LEVEL`, and zero below it.
    """
    return 1 if level >= FORAGE_BONUS_LEVEL else 0


def fighting_might(level: Int) -> Float32:
    """Return how many times its damage the player's blow does.

    Args:
        level: The level of the style's skill.

    Returns:
        One at level 1, and `FIGHTING_MIGHT` more for each level over it.
    """
    return 1 + FIGHTING_MIGHT * Float32(level - 1)


def fish_haste(level: Int) -> Float32:
    """Return the share of a fish's usual wait that it waits.

    Args:
        level: The fishing level.

    Returns:
        One at level 1, and `FISH_HASTE` less for each level over it.
    """
    return 1 - FISH_HASTE * Float32(level - 1)


struct Skills(Copyable, Movable):
    """The experience of each of the player's skills."""

    var experience: List[Int]

    def __init__(out self):
        """Begin each skill at level 1, with no experience."""
        self.experience = List[Int](length=SKILLS, fill=0)

    def level(self, skill: SkillKind) raises -> Int:
        """Return a skill's level.

        Args:
            skill: The skill.

        Returns:
            Its level, from 1 to `MAX_LEVEL`.

        Raises:
            Error: If the skill is not one.
        """
        if not skill.is_valid():
            raise Error("A skill must be one of the nine")
        return level_of(self.experience[skill.value])

    def gain(
        mut self, kind: GatherKind, count: Int
    ) raises -> Optional[SkillKind]:
        """Give a skill the experience of some things gathered.

        Args:
            kind: The kind of spot they came from.
            count: How many things it gave.

        Returns:
            The skill, if it rose a level; else None.

        Raises:
            Error: If the count is negative.
        """
        if count < 0:
            raise Error("A count of things gathered must not be negative")
        var trained = skill_of(kind)
        if not trained:
            return None
        return self.train(trained.value(), experience_for(kind) * count)

    def train(
        mut self, skill: SkillKind, experience: Int
    ) raises -> Optional[SkillKind]:
        """Give a skill some experience.

        Args:
            skill: The skill.
            experience: How much, zero or more.

        Returns:
            The skill, if it rose a level; else None.

        Raises:
            Error: If the skill is not one, or the experience is negative.
        """
        if experience < 0:
            raise Error("A skill's experience must not be negative")
        var before = self.level(skill)
        self.experience[skill.value] += experience
        if self.level(skill) > before:
            return skill
        return None

    def lines(self) raises -> List[String]:
        """Return a line for each skill with experience, for the display.

        Returns:
            Such as "MINING 2  90/150": the name, the level, and the
            experience out of what the next level needs. A skill at
            `MAX_LEVEL` shows its experience alone.

        Raises:
            Error: Never: each skill's name is known.
        """
        var out_lines = List[String]()
        for k in range(SKILLS):  # pragma: no branch
            var xp = self.experience[k]
            if xp == 0:
                continue
            var skill = SkillKind(k)
            var level = level_of(xp)
            var line = String(skill_name(skill), " ", level, "  ", xp)
            if level < MAX_LEVEL:
                line += String("/", level_experience(level + 1))
            out_lines.append(line^)
        return out_lines^
