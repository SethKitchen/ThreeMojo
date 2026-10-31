# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fighting styles: their traits, their moves and buttons, mana, boosts,
and what a style does to a fighter's moves, blows and guard."""

from extensions.village.combat import (
    AIMED_SHOT,
    ARROW_RAIN,
    BITE,
    BLOCKED,
    BUTTONS,
    CAST,
    COMBO_STEP,
    DEFEATED,
    DODGE,
    FREE,
    GROUND_WAVE,
    GUARD_BREAK,
    HEAVY,
    HEAVY_BUTTON,
    LEAP_SHOT,
    LIGHT_BUTTON,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MEND,
    MOVES,
    NOVA,
    PARRIED,
    PLUNGE,
    QUICK_SHOT,
    RISING_BUTTON,
    RISING_EDGE,
    SPELL_BLAST,
    SPELL_BOLT,
    THROW,
    ULTIMATE,
    ULTIMATE_BUTTON,
    VOLLEY,
    WAVE_BUTTON,
    WHIRLWIND,
    WHIRLWIND_BUTTON,
    Blow,
    CombatMove,
    FightButton,
    Fighter,
    FighterParameters,
    combo_bonus,
    is_attack,
    is_shot,
    is_special,
    is_spell,
    move_data,
    move_name,
    style_move,
    weapon_move,
)
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    STYLES,
    SWORD,
    FightingStyle,
    StyleTraits,
    is_melee,
    style_name,
    style_traits,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    SECOND,
    Duration,
    Frequency,
    Velocity,
)


def _run(mut fighter: Fighter, seconds: Float32) raises:
    """Move a fighter on by some time, in steps of a 120th of a second."""
    var steps = Int(seconds * 120 + 0.5)
    for _ in range(steps):
        fighter.update(Duration(Float32(1) / 120, SECOND))


def _in(style: FightingStyle) raises -> Fighter:
    """Return a fighter with the player's strength, in a style."""
    var f = Fighter(FighterParameters())
    _ = f.set_style(style)
    return f^


def _blow(
    damage: Float32,
    stamina: Float32,
    crush: Float32 = 0,
    guard: Float32 = 1,
) -> Blow:
    """Return a blow that pushes and throws nothing."""
    return Blow(
        damage,
        stamina,
        Velocity(0.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
        crush=crush,
        guard_damage=guard,
    )


def test_each_style_and_button_knows_its_values() raises:
    for value in [-1, STYLES]:
        assert_false(FightingStyle(value).is_valid())
    for value in [0, STYLES - 1]:
        assert_true(FightingStyle(value).is_valid())
    for value in [-1, BUTTONS]:
        assert_false(FightButton(value).is_valid())
    for value in [0, BUTTONS - 1]:
        assert_true(FightButton(value).is_valid())
    for value in [-1, MOVES]:
        assert_false(CombatMove(value).is_valid())
    assert_true(CombatMove(MOVES - 1).is_valid())


def test_styles_have_names_and_reach() raises:
    assert_equal(style_name(HAND_TO_HAND), "HAND TO HAND")
    assert_equal(style_name(SWORD), "SWORD")
    assert_equal(style_name(ARCHERY), "ARCHERY")
    with assert_raises(contains="six"):
        _ = style_name(FightingStyle(6))
    assert_true(is_melee(HAND_TO_HAND))
    assert_true(is_melee(MACE))
    assert_false(is_melee(MAGIC))
    assert_false(is_melee(FightingStyle(-1)))


def test_each_style_has_its_traits() raises:
    var sword = style_traits(SWORD)
    assert_equal(sword.pace, 1)
    assert_equal(sword.crush, 0)
    assert_almost_equal(sword.chain, 0.3, atol=1e-6)
    assert_false(sword.ward)
    var fists = style_traits(HAND_TO_HAND)
    assert_true(fists.pace < 1)
    assert_equal(fists.combo_step, 2)
    assert_equal(fists.chain, 0)
    var axe = style_traits(AXE)
    assert_true(axe.power > 1 and axe.arc > 1)
    var mace = style_traits(MACE)
    assert_true(mace.stamina_damage > 1.5 and mace.crush > 0.3)
    assert_true(style_traits(MAGIC).ward)
    assert_true(style_traits(ARCHERY).step > 1)
    with assert_raises(contains="six"):
        _ = style_traits(FightingStyle(9))
    var plain = StyleTraits()
    assert_equal(plain.power, 1)


def test_the_new_moves_are_named_and_sorted() raises:
    assert_equal(move_name(SPELL_BOLT), "SPELL BOLT")
    assert_equal(move_name(SPELL_BLAST), "SPELL BLAST")
    assert_equal(move_name(NOVA), "NOVA")
    assert_equal(move_name(MEND), "MEND")
    assert_equal(move_name(QUICK_SHOT), "QUICK SHOT")
    assert_equal(move_name(AIMED_SHOT), "AIMED SHOT")
    assert_equal(move_name(VOLLEY), "VOLLEY")
    assert_equal(move_name(LEAP_SHOT), "LEAP SHOT")
    assert_equal(move_name(ARROW_RAIN), "ARROW RAIN")
    with assert_raises(contains="twenty-seven"):
        _ = move_name(CombatMove(MOVES))
    with assert_raises(contains="twenty-seven"):
        _ = move_data(CombatMove(-1))
    assert_true(is_attack(ARROW_RAIN))
    assert_false(is_attack(DODGE))
    # The specials: the sword's run, the mage's two, and the archer's
    # three.
    assert_false(is_special(LIGHT_THREE))
    assert_true(is_special(WHIRLWIND))
    assert_false(is_special(PLUNGE))
    assert_true(is_special(NOVA))
    assert_true(is_special(MEND))
    assert_false(is_special(AIMED_SHOT))
    assert_true(is_special(VOLLEY))
    assert_true(is_special(ARROW_RAIN))
    assert_false(is_special(DODGE))
    assert_false(weapon_move(FREE))
    assert_true(weapon_move(LIGHT_ONE))
    assert_true(weapon_move(PLUNGE))
    assert_false(weapon_move(BITE))
    assert_true(is_spell(SPELL_BOLT))
    assert_true(is_spell(SPELL_BLAST))
    assert_false(is_spell(NOVA))
    assert_true(is_shot(SPELL_BOLT))
    assert_false(is_shot(THROW))
    assert_true(is_shot(QUICK_SHOT))
    assert_true(is_shot(ARROW_RAIN))
    assert_false(is_shot(DODGE))
    assert_false(is_shot(CAST))


def test_the_new_moves_have_their_data() raises:
    assert_equal(move_data(SPELL_BOLT).mana_cost, 7)
    assert_equal(move_data(SPELL_BLAST).mana_cost, 20)
    assert_equal(move_data(NOVA).hits, 1)
    assert_almost_equal(move_data(NOVA).reach.to(METER), 4.5, atol=1e-6)
    assert_equal(move_data(MEND).special_cost, 2)
    assert_equal(move_data(MEND).hits, 0)
    assert_equal(move_data(QUICK_SHOT).stamina_cost, 4)
    assert_equal(move_data(AIMED_SHOT).damage, 85)
    assert_equal(move_data(VOLLEY).special_cost, 2)
    assert_true(move_data(LEAP_SHOT).lunge.to(METER) < 0)
    assert_equal(move_data(ARROW_RAIN).special_cost, 3)
    assert_equal(move_data(LIGHT_ONE).mana_cost, 0)


def test_a_button_makes_its_styles_move() raises:
    assert_true(style_move(SWORD, LIGHT_BUTTON, True, FREE) == LIGHT_ONE)
    assert_true(style_move(AXE, LIGHT_BUTTON, True, LIGHT_ONE) == LIGHT_TWO)
    assert_true(style_move(MACE, HEAVY_BUTTON, True, FREE) == HEAVY)
    assert_true(style_move(MACE, HEAVY_BUTTON, False, FREE) == PLUNGE)
    assert_true(style_move(SWORD, RISING_BUTTON, True, FREE) == RISING_EDGE)
    assert_true(
        style_move(HAND_TO_HAND, WHIRLWIND_BUTTON, True, FREE) == WHIRLWIND
    )
    assert_true(style_move(SWORD, WAVE_BUTTON, True, FREE) == GROUND_WAVE)
    assert_true(style_move(ARCHERY, ULTIMATE_BUTTON, True, FREE) == ULTIMATE)
    assert_true(style_move(MAGIC, LIGHT_BUTTON, True, FREE) == SPELL_BOLT)
    assert_true(style_move(MAGIC, HEAVY_BUTTON, False, FREE) == SPELL_BLAST)
    assert_true(style_move(MAGIC, RISING_BUTTON, True, FREE) == MEND)
    assert_true(style_move(MAGIC, WHIRLWIND_BUTTON, True, FREE) == NOVA)
    assert_true(style_move(MAGIC, WAVE_BUTTON, True, FREE) == GROUND_WAVE)
    assert_true(style_move(ARCHERY, LIGHT_BUTTON, True, FREE) == QUICK_SHOT)
    assert_true(style_move(ARCHERY, HEAVY_BUTTON, True, FREE) == AIMED_SHOT)
    assert_true(style_move(ARCHERY, RISING_BUTTON, True, FREE) == LEAP_SHOT)
    assert_true(style_move(ARCHERY, WHIRLWIND_BUTTON, True, FREE) == VOLLEY)
    assert_true(style_move(ARCHERY, WAVE_BUTTON, True, FREE) == ARROW_RAIN)
    with assert_raises(contains="style"):
        _ = style_move(FightingStyle(7), LIGHT_BUTTON, True, FREE)
    with assert_raises(contains="button"):
        _ = style_move(SWORD, FightButton(6), True, FREE)


def test_a_fighter_takes_up_a_style_while_free() raises:
    var f = Fighter(FighterParameters())
    assert_true(f.style == SWORD)
    assert_false(f.set_style(SWORD))
    assert_true(f.set_style(AXE))
    assert_true(f.style == AXE)
    assert_almost_equal(f.traits.power, 1.3, atol=1e-6)
    _ = f.request(LIGHT_ONE)
    assert_false(f.set_style(MACE))
    assert_true(f.style == AXE)
    with assert_raises(contains="six"):
        _ = f.set_style(FightingStyle(-2))


def test_a_style_changes_its_weapons_moves() raises:
    # The axe: slower, wider and further.
    var axe = _in(AXE)
    _ = axe.request(LIGHT_ONE)
    assert_almost_equal(axe.pace, 1.12, atol=1e-6)
    _run(axe, 0.17)
    var swing = axe.swing().value()
    assert_almost_equal(swing.reach.to(METER), 2.1, atol=1e-4)
    assert_almost_equal(swing.arc.to(DEGREE), 156, atol=1e-3)
    var blow = axe.blow()
    assert_almost_equal(blow.damage, 39, atol=1e-3)
    assert_almost_equal(blow.stamina_damage, 8 * 1.3 * 1.1, atol=1e-3)
    assert_almost_equal(blow.crush, 0.1, atol=1e-6)
    assert_almost_equal(blow.guard_damage, 1.7, atol=1e-6)
    # A spin covers no more than all around.
    var spin = _in(AXE)
    _ = spin.request(WHIRLWIND)
    _run(spin, 0.25)
    assert_almost_equal(spin.swing().value().arc.to(DEGREE), 360, atol=1e-3)
    # A spell is the spell's own, in any style.
    var mage = _in(MAGIC)
    _ = mage.request(NOVA)
    _run(mage, 0.32)
    assert_almost_equal(mage.swing().value().reach.to(METER), 4.5, atol=1e-4)
    var burst = mage.blow()
    assert_equal(burst.crush, 0)
    assert_equal(burst.guard_damage, 1)


def test_a_style_changes_stamina_and_dodges() raises:
    var mace = _in(MACE)
    assert_almost_equal(mace.stamina_price(HEAVY), 22 * 1.25, atol=1e-4)
    assert_almost_equal(mace.stamina_price(DODGE), 14 * 1.25, atol=1e-4)
    # A shot's stamina is its own.
    assert_almost_equal(mace.stamina_price(QUICK_SHOT), 4, atol=1e-6)
    var archer = _in(ARCHERY)
    _ = archer.request(DODGE)
    var sword = Fighter(FighterParameters())
    _ = sword.request(DODGE)
    _run(archer, 0.05)
    _run(sword, 0.05)
    var ratio = archer.drive().to(METER_PER_SECOND) / sword.drive().to(
        METER_PER_SECOND
    )
    assert_almost_equal(ratio, 1.25, atol=1e-4)


def test_fists_chain_at_once_and_build_combos_fast() raises:
    var fists = _in(HAND_TO_HAND)
    _ = fists.request(LIGHT_ONE)
    assert_almost_equal(fists.chain_point(), fists.active_end(), atol=1e-6)
    assert_almost_equal(combo_bonus(10, 2), 1 + COMBO_STEP * 20, atol=1e-6)
    fists.combo = 10
    _run(fists, 0.12)
    var expected = 30 * 0.6 * combo_bonus(10, 2)
    assert_almost_equal(fists.blow().damage, expected, atol=1e-3)


def test_a_maces_blow_hurts_through_a_guard() raises:
    var f = Fighter(FighterParameters())
    f.hold_guard(True)
    _run(f, 0.5)
    var struck = f.receive(_blow(100, 20, 0.35, 1.4), True)
    assert_true(struck.outcome == BLOCKED)
    assert_almost_equal(struck.damage, 35, atol=1e-4)
    assert_almost_equal(struck.stamina, 20 * 0.75 * 1.4, atol=1e-4)
    assert_almost_equal(f.health, 465, atol=1e-3)
    # A crushing blow can break the guard, and can fell the guard.
    f.stamina = 5
    var broke = f.receive(_blow(10, 20, 0.5), True)
    assert_true(broke.outcome == GUARD_BREAK)
    assert_almost_equal(broke.damage, 5, atol=1e-4)
    var g = Fighter(FighterParameters())
    g.hold_guard(True)
    _run(g, 0.5)
    g.health = 10
    var fell = g.receive(_blow(100, 1, 0.5), True)
    assert_true(fell.outcome == DEFEATED)
    assert_true(g.defeated())


def test_a_mages_ward_guards_all_around() raises:
    var mage = _in(MAGIC)
    mage.hold_guard(True)
    _run(mage, 0.5)
    assert_true(mage.receive(_blow(30, 10), False).outcome == BLOCKED)
    assert_true(mage.receive(_blow(30, 10), True).outcome == BLOCKED)
    var sword = Fighter(FighterParameters())
    sword.hold_guard(True)
    _run(sword, 0.5)
    assert_false(sword.receive(_blow(30, 10), False).outcome == BLOCKED)


def test_a_styles_parry_window_is_its_own() raises:
    # A guard 0.18 seconds old parries hand to hand, and not with a sword.
    var fists = _in(HAND_TO_HAND)
    fists.hold_guard(True)
    _run(fists, 0.18)
    assert_true(fists.receive(_blow(30, 10), True).outcome == PARRIED)
    var sword = Fighter(FighterParameters())
    sword.hold_guard(True)
    _run(sword, 0.18)
    assert_true(sword.receive(_blow(30, 10), True).outcome == BLOCKED)


def test_a_spell_spends_mana_and_mana_comes_back() raises:
    var mage = _in(MAGIC)
    assert_false(mage.mana_short(SPELL_BOLT))
    assert_true(mage.request(SPELL_BOLT))
    assert_almost_equal(mage.mana, 93, atol=1e-4)
    _run(mage, 1)
    assert_almost_equal(mage.mana, 100, atol=1e-3)
    mage.mana = 5
    assert_true(mage.mana_short(SPELL_BOLT))
    assert_true(mage.free())
    assert_false(mage.request(SPELL_BOLT))
    mage.revive()
    assert_equal(mage.mana, 100)
    var p = FighterParameters()
    p.mana = -1
    with assert_raises(contains="mana"):
        _ = Fighter(p)
    var q = FighterParameters()
    q.mana_rate = Frequency(-1.0, PER_SECOND)
    with assert_raises(contains="mana"):
        _ = Fighter(q)


def test_a_boost_and_a_waiver_make_a_finisher() raises:
    var f = Fighter(FighterParameters())
    assert_true(f.request(LIGHT_ONE, 2))
    _run(f, 0.15)
    assert_almost_equal(f.blow().damage, 60, atol=1e-3)
    # A waived special spends no points, even with none.
    var g = Fighter(FighterParameters())
    g.special = 0
    assert_false(g.request(RISING_EDGE))
    assert_true(g.request(RISING_EDGE, 1, True))
    assert_equal(g.special, 0)
    # A waiting move keeps its boost and its waiver.
    var h = Fighter(FighterParameters())
    h.special = 0
    _ = h.request(LIGHT_ONE)
    assert_true(h.request(WHIRLWIND, 1.5, True))
    _run(h, 0.4)
    assert_true(h.move == WHIRLWIND)
    assert_almost_equal(h.boost, 1.5, atol=1e-6)
    # A move that starts after it has no boost.
    _run(h, 1.2)
    _ = h.request(LIGHT_ONE)
    assert_equal(h.boost, 1)
    with assert_raises(contains="boost"):
        _ = h.request(LIGHT_TWO, -1)
    with assert_raises(contains="boost"):
        _ = h.request(LIGHT_TWO, 101)


def test_only_the_heavy_and_the_aimed_and_specials_break_a_pierce() raises:
    var moves: List[CombatMove] = [
        HEAVY,
        PLUNGE,
        SPELL_BLAST,
        AIMED_SHOT,
        RISING_EDGE,
        LIGHT_ONE,
        SPELL_BOLT,
    ]
    var breaks: List[Bool] = [True, True, True, True, True, False, False]
    for k in range(len(moves)):
        var f = _in(MAGIC if k == 2 or k == 6 else SWORD)
        f.move = moves[k]
        assert_equal(f.blow().breaks_pierce, breaks[k])


def test_a_jump_cancels_an_attacks_recovery() raises:
    var f = Fighter(FighterParameters())
    assert_false(f.cancel())
    _ = f.request(LIGHT_ONE)
    _run(f, 0.1)
    assert_false(f.cancel())
    _run(f, 0.2)
    assert_true(f.cancel())
    assert_true(f.free())
    _ = f.request(LIGHT_ONE)
    _run(f, 0.3)
    f.winded = True
    assert_false(f.cancel())


def test_stamina_drains_without_a_move() raises:
    var f = Fighter(FighterParameters())
    f.drain(0)
    assert_equal(f.stamina, 100)
    f.rest = 3
    f.drain(30)
    assert_equal(f.stamina, 70)
    assert_equal(f.rest, 0)
    f.drain(200)
    assert_equal(f.stamina, 0)
    assert_false(f.winded)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
