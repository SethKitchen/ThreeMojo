# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fighter's state as plain values, for code outside the fight to take
and to set.

The village holds no networking: no sockets, no wire format, no tick rate
and no schedule. It gives hooks, and the code that uses them decides how
to carry what they give:

| Hook | What it gives |
|---|---|
| `state_of` and `apply_state` | A fighter's place and fight, to take and to set |
| `MoveInput` | A player's input for a frame, as plain values: see `Battle.tick` |
| `Character.step` | The same move for the same input, frame and ground |
| `Boss.think` | The warden's choice from a `BossSight` alone, with dice from its seed |
| `VillageGame.progress` | What a player keeps from one game to the next |

A networking layer can send states and inputs, a replay can record them,
and a test can compare them. `tests/_village_netcode.mojo` is a sample
networking layer built on these hooks alone.
"""

from extensions.village.character import Character
from extensions.village.combat import (
    CombatMove,
    CombatStance,
    Fighter,
)
from extensions.village.styles import FightingStyle
from math.vector3 import Vector3
from units.si import Angle


@fieldwise_init
struct FighterState(ImplicitlyCopyable):
    """A fighter's place and fight, as plain values."""

    # The fighter's id, which the caller gives.
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


def state_of(id: Int, character: Character, fighter: Fighter) -> FighterState:
    """Return a fighter's state.

    Args:
        id: The fighter's id, as the caller names it.
        character: Where it is.
        fighter: What it does.

    Returns:
        Its state. Its stamina and its mana are shares of its most; a
        fighter with no mana has none.
    """
    ref p = fighter.parameters
    return FighterState(
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


def apply_state(
    state: FighterState, mut character: Character, mut fighter: Fighter
) raises:
    """Set a fighter from a state: its place and heading, and its fight.

    Args:
        state: The state.
        character: The fighter's character.
        fighter: The fighter. A change of style takes up the style's
            traits; its move and clock are the state's.

    Raises:
        Error: If the state's style is not one.
    """
    character.position = state.position
    character.heading = state.heading
    ref p = fighter.parameters
    fighter.health = state.health
    fighter.stamina = state.stamina * p.stamina
    fighter.mana = state.mana * p.mana
    fighter.special = state.special
    fighter.move = state.move
    fighter.clock = state.clock
    fighter.stance = state.stance
    if fighter.style != state.style:
        var move = fighter.move
        fighter.move = CombatMove(0)
        _ = fighter.set_style(state.style)
        fighter.move = move
    fighter.combo = state.combo
