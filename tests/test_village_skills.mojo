# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's gathering skills, and how they grow."""

from extensions.village.gathering import (
    BERRIES,
    CHEST,
    FISH,
    HERBS,
    MUSHROOMS,
    ORE,
    STRIKES,
    TRINKET,
)
from extensions.village.skills import (
    FISHING,
    FISH_HASTE,
    FORAGE_BONUS_LEVEL,
    FORAGING,
    MAX_LEVEL,
    MINING,
    SkillKind,
    Skills,
    experience_for,
    fish_haste,
    forage_bonus,
    level_experience,
    level_of,
    ore_strikes,
    skill_name,
    skill_of,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_each_kind_trains_its_skill() raises:
    assert_true(FISHING.is_valid())
    assert_false(SkillKind(3).is_valid())
    assert_equal(skill_name(FORAGING), "FORAGING")
    assert_equal(skill_name(MINING), "MINING")
    assert_equal(skill_name(FISHING), "FISHING")
    with assert_raises(contains="one of the three"):
        _ = skill_name(SkillKind(-1))
    assert_true(skill_of(HERBS).value() == FORAGING)
    assert_true(skill_of(MUSHROOMS).value() == FORAGING)
    assert_true(skill_of(BERRIES).value() == FORAGING)
    assert_true(skill_of(ORE).value() == MINING)
    assert_true(skill_of(FISH).value() == FISHING)
    assert_false(Bool(skill_of(CHEST)))
    assert_false(Bool(skill_of(TRINKET)))
    assert_equal(experience_for(HERBS), 10)
    assert_equal(experience_for(MUSHROOMS), 6)
    assert_equal(experience_for(BERRIES), 4)
    assert_equal(experience_for(ORE), 30)
    assert_equal(experience_for(FISH), 25)
    assert_equal(experience_for(CHEST), 0)


def test_levels_and_what_they_do() raises:
    assert_equal(level_experience(1), 0)
    assert_equal(level_experience(2), 50)
    assert_equal(level_experience(3), 150)
    assert_equal(level_experience(10), 2250)
    assert_equal(level_of(0), 1)
    assert_equal(level_of(49), 1)
    assert_equal(level_of(50), 2)
    assert_equal(level_of(149), 2)
    assert_equal(level_of(150), 3)
    assert_equal(level_of(1000000), MAX_LEVEL)
    assert_equal(ore_strikes(1), STRIKES)
    assert_equal(ore_strikes(3), STRIKES)
    assert_equal(ore_strikes(4), STRIKES - 1)
    assert_equal(ore_strikes(7), 1)
    assert_equal(ore_strikes(MAX_LEVEL), 1)
    assert_equal(forage_bonus(FORAGE_BONUS_LEVEL - 1), 0)
    assert_equal(forage_bonus(FORAGE_BONUS_LEVEL), 1)
    assert_almost_equal(fish_haste(1), 1, atol=1e-6)
    assert_almost_equal(fish_haste(3), 1 - 2 * FISH_HASTE, atol=1e-6)


def test_experience_raises_a_skill() raises:
    var skills = Skills()
    assert_equal(skills.level(MINING), 1)
    assert_equal(len(skills.lines()), 0)
    # One ore is 30; the second rises to level 2.
    assert_false(Bool(skills.gain(ORE, 1)))
    var risen = skills.gain(ORE, 1)
    assert_true(risen.value() == MINING)
    assert_equal(skills.level(MINING), 2)
    # A chest trains nothing.
    assert_false(Bool(skills.gain(CHEST, 12)))
    _ = skills.gain(BERRIES, 3)
    var lines = skills.lines()
    assert_equal(len(lines), 2)
    assert_equal(lines[0], "FORAGING 1  12/50")
    assert_equal(lines[1], "MINING 2  60/150")
    # A skill at the top level shows its experience alone.
    _ = skills.gain(FISH, 200)
    assert_equal(skills.level(FISHING), MAX_LEVEL)
    assert_equal(skills.lines()[2], "FISHING 10  5000")
    with assert_raises(contains="negative"):
        _ = skills.gain(HERBS, -1)
    with assert_raises(contains="one of the three"):
        _ = skills.level(SkillKind(5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
