# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fighting styles: hand to hand, the sword, the axe, the mace, magic and
archery.

A fighter fights in one `FightingStyle` at a time. The four melee styles
use the same moves: the light chain, the heavy attack and the specials of
`extensions.village.combat`. Their `StyleTraits` change those moves:

| Style | Pace | Power | Reach | Arc | Stamina damage | Stamina | Guard damage | Through a guard | Combo step | Dodge | Parry | Chain point |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `HAND_TO_HAND` | 0.72 | 0.6 | 0.75 | 1 | 0.9 | 0.55 | 1 | 0 | 2 | 1.2 | 1.3 | 0 |
| `SWORD` | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 0.3 |
| `AXE` | 1.12 | 1.3 | 1.05 | 1.3 | 1.1 | 1.15 | 1.7 | 0.1 | 1 | 0.95 | 0.8 | 0.4 |
| `MACE` | 1.28 | 1.15 | 0.95 | 1 | 1.9 | 1.25 | 1.4 | 0.35 | 1 | 0.9 | 0.8 | 0.5 |
| `MAGIC` | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 0.6 | 0.3 |
| `ARCHERY` | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1.25 | 0.7 | 0.2 |

Pace, power, reach, arc, stamina damage and stamina are times the move's
own. Guard damage is times the stamina that a guard loses to the style's
blows. Through a guard is the share of a blow's damage that a guard does
not stop. The combo step is times the combo's step. The dodge is times the
dodge's length, and the parry times the fighter's parry window. The chain
point is the share of the recovery after which a waiting move starts.

So hand to hand is quick and cheap, and its combos grow fast. The sword is
even. The axe hits hard and wide, and tears through guards. The mace is
slow, breaks stamina and guards, and hurts through them. A mage's guard is
a ward all around it. Magic and archery have moves of their own: see
`extensions.village.combat.style_move`.
"""

from core.ordinal import ordinal_valid

comptime STYLES = 6
"""How many fighting styles there are."""


@fieldwise_init
struct FightingStyle(Equatable, ImplicitlyCopyable, Writable):
    """How a fighter fights, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the styles.

        Returns:
            True from `HAND_TO_HAND` to `ARCHERY`.
        """
        return ordinal_valid(self.value, STYLES - 1)


comptime HAND_TO_HAND = FightingStyle(0)
"""Fists and feet: quick, cheap blows whose combos grow fast."""
comptime SWORD = FightingStyle(1)
"""The sword: even in every way."""
comptime AXE = FightingStyle(2)
"""The axe: hard, wide cuts that tear through guards."""
comptime MACE = FightingStyle(3)
"""The mace: slow blows that break stamina, and hurt through a guard."""
comptime MAGIC = FightingStyle(4)
"""A staff: bolts, blasts, a nova and a mend, paid for with mana, and a
ward all around."""
comptime ARCHERY = FightingStyle(5)
"""A bow: quick shots, aimed shots, a volley, a leap back and a rain of
arrows."""


@fieldwise_init
struct StyleTraits(ImplicitlyCopyable):
    """How a style changes its moves: see the module's table."""

    # How many times its time, its damage, its reach and its arc a weapon's
    # move takes, does and covers.
    var pace: Float32
    var power: Float32
    var reach: Float32
    var arc: Float32
    # How many times its stamina damage a weapon's blow does, and how many
    # times its stamina a weapon's move spends.
    var stamina_damage: Float32
    var stamina_cost: Float32
    # How many times the stamina a guard loses to a weapon's blow, and the
    # share of the blow's damage that passes through the guard.
    var guard_damage: Float32
    var crush: Float32
    # How many times the combo's step each blow of a combo adds.
    var combo_step: Float32
    # How many times its length a dodge goes, and how many times its
    # fighter's parry window a guard parries for.
    var step: Float32
    var parry: Float32
    # Whether the guard covers all around, as a ward.
    var ward: Bool
    # The share of a move's recovery after which a waiting move starts.
    var chain: Float32

    def __init__(out self):
        """Hold the sword's traits: every move as it is, a guard of the
        fighter's own arc, and a chain point at 30 percent of the
        recovery."""
        self.pace = 1
        self.power = 1
        self.reach = 1
        self.arc = 1
        self.stamina_damage = 1
        self.stamina_cost = 1
        self.guard_damage = 1
        self.crush = 0
        self.combo_step = 1
        self.step = 1
        self.parry = 1
        self.ward = False
        self.chain = 0.3


def style_name(style: FightingStyle) raises -> String:
    """Return a style's name, in capitals for the display.

    Args:
        style: The style.

    Returns:
        "HAND TO HAND", "SWORD", "AXE", "MACE", "MAGIC" or "ARCHERY".

    Raises:
        Error: If the style is not one.
    """
    if not style.is_valid():
        raise Error("A fighting style must be one of the six")
    var names: List[String] = [
        "HAND TO HAND",
        "SWORD",
        "AXE",
        "MACE",
        "MAGIC",
        "ARCHERY",
    ]
    return names[style.value]


def is_melee(style: FightingStyle) -> Bool:
    """Return whether a style fights within arm's reach.

    Args:
        style: The style.

    Returns:
        True for hand to hand, the sword, the axe and the mace.
    """
    return style.value >= HAND_TO_HAND.value and style.value <= MACE.value


def style_traits(style: FightingStyle) raises -> StyleTraits:
    """Return how a style changes its moves: see the module's table.

    Args:
        style: The style.

    Returns:
        The style's traits.

    Raises:
        Error: If the style is not one.
    """
    if not style.is_valid():
        raise Error("A fighting style must be one of the six")
    if style == HAND_TO_HAND:
        return StyleTraits(
            0.72, 0.6, 0.75, 1, 0.9, 0.55, 1, 0, 2, 1.2, 1.3, False, 0
        )
    if style == AXE:
        return StyleTraits(
            1.12, 1.3, 1.05, 1.3, 1.1, 1.15, 1.7, 0.1, 1, 0.95, 0.8, False, 0.4
        )
    if style == MACE:
        return StyleTraits(
            1.28, 1.15, 0.95, 1, 1.9, 1.25, 1.4, 0.35, 1, 0.9, 0.8, False, 0.5
        )
    if style == MAGIC:
        return StyleTraits(1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0.6, True, 0.3)
    if style == ARCHERY:
        return StyleTraits(1, 1, 1, 1, 1, 1, 1, 0, 1, 1.25, 0.7, False, 0.2)
    return StyleTraits()
