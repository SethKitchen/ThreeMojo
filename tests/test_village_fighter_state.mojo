# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fighter's state: taken from a fighter, and set on another, as plain
values."""

from extensions.vegetation.ground import Ground
from extensions.village.character import Character, CharacterParameters
from extensions.village.combat import (
    HEAVY,
    HIGH_STANCE,
    LOW_STANCE,
    WHIRLWIND,
    Fighter,
    FighterParameters,
)
from extensions.village.fighter_state import (
    FighterState,
    apply_state,
    state_of,
)
from extensions.village.styles import ARCHERY, MAGIC
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import METER, RADIAN, Angle, Length


def test_a_fighters_state_is_taken_and_set() raises:
    var terrain = Terrain(Ground(hill_height=Length(0.0, METER)))
    var character = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), terrain
    )
    var fighter = Fighter(FighterParameters())
    fighter.health = 321
    fighter.stamina = 40
    fighter.mana = 50
    fighter.combo = 4
    var taken = state_of(9, character, fighter)
    assert_equal(taken.id, 9)
    assert_equal(taken.health, 321)
    assert_almost_equal(taken.stamina, 0.4, atol=1e-6)
    assert_almost_equal(taken.mana, 0.5, atol=1e-6)
    assert_equal(taken.combo, 4)
    # A fighter with no mana has none.
    var none = FighterParameters()
    none.mana = 0
    var plain = Fighter(none)
    assert_equal(state_of(1, character, plain).mana, 0)
    # Set on another fighter, the state takes up its place and its fight.
    var copy = Fighter(FighterParameters())
    var place = Character(
        CharacterParameters(), 3, 3, Angle(1.0, RADIAN), terrain
    )
    var state = FighterState(
        513,
        Vector3(-12.345, 1.5, 200.01),
        Angle(-1.0, RADIAN),
        432,
        0.5,
        0.25,
        3.3,
        HEAVY,
        0.456,
        HIGH_STANCE,
        MAGIC,
        17,
    )
    apply_state(state, place, copy)
    assert_almost_equal(place.position.x, -12.345, atol=1e-4)
    assert_almost_equal(place.heading.to(RADIAN), -1, atol=1e-6)
    assert_equal(copy.health, 432)
    assert_almost_equal(copy.stamina, 50, atol=1e-4)
    assert_almost_equal(copy.mana, 25, atol=1e-4)
    assert_almost_equal(copy.special, 3.3, atol=1e-6)
    assert_true(copy.move == HEAVY)
    assert_almost_equal(copy.clock, 0.456, atol=1e-6)
    assert_true(copy.style == MAGIC)
    assert_true(copy.stance == HIGH_STANCE)
    assert_equal(copy.combo, 17)
    # The same style again keeps the style's traits.
    apply_state(state, place, copy)
    assert_true(copy.style == MAGIC)
    assert_true(copy.traits.ward)
    # Taken again, it is the state it was set from.
    var again = state_of(513, place, copy)
    assert_almost_equal(again.position.z, 200.01, atol=1e-4)
    assert_true(again.move == HEAVY)
    state.move = WHIRLWIND
    state.stance = LOW_STANCE
    state.style = ARCHERY
    apply_state(state, place, copy)
    assert_true(copy.style == ARCHERY)
    assert_true(copy.move == WHIRLWIND)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
