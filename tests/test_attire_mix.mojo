# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a crowd's clothes: outfits picked by a seed."""

from extensions.attire.kinds import (
    PARTY,
    PLATE,
    QUARTERLY,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
)
from extensions.attire.mix import (
    ARCANE_DYES,
    BARBARIAN,
    FARMER,
    FOREST_DYES,
    FUR_DYES,
    RANGER,
    ROYAL,
    SHADOW_DYES,
    WARLOCK,
    WARRIOR,
    WIZARD,
    arcane_dye,
    calling_sex,
    dressed_as,
    forest_dye,
    fur_dye,
    mixed_sex,
    shadow_dye,
    warrior_metal,
    ARCHER,
    CALLING_COUNT,
    GOODWIFE,
    KNIGHT,
    MAN_AT_ARMS,
    MERCHANT,
    MONK,
    NOBLEWOMAN,
    PEASANT,
    PLAIN_DYES,
    RICH_DYES,
    Calling,
    calling_label,
    calling_named,
    calling_outfit,
    mixed_calling,
    mixed_outfit,
    plain_dye,
    require_calling,
    rich_dye,
)
from extensions.attire.kinds import FUR, HATTED
from extensions.attire.metal import METAL_COUNT
from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.attire.preset import outfit_json
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _names(outfit: Outfit) -> List[String]:
    """Return the names of an outfit's garments, in the order added."""
    var names = List[String]()
    for garment in outfit.garments:
        names.append(garment.name)
    return names^


def _has(outfit: Outfit, name: String) -> Bool:
    """Return whether an outfit has a garment of that name."""
    return name in _names(outfit)


def test_callings_are_named() raises:
    for k in range(CALLING_COUNT):
        var calling = Calling(k)
        assert_true(calling.is_valid())
        assert_equal(calling_named(calling_label(calling)), calling)
    assert_equal(calling_label(MAN_AT_ARMS), "man-at-arms")
    assert_equal(calling_label(Calling(40)), "calling")
    assert_false(Calling(-1).is_valid())
    assert_false(Calling(CALLING_COUNT).is_valid())
    require_calling(KNIGHT)
    with assert_raises(contains="named one"):
        require_calling(Calling(40))
    with assert_raises(contains="No calling"):
        _ = calling_named("jester")
    with assert_raises(contains="named one"):
        _ = calling_outfit(Calling(40), 0)


def test_the_dyes_wrap_round() raises:
    assert_true(plain_dye(0) == plain_dye(PLAIN_DYES))
    assert_true(rich_dye(1) == rich_dye(RICH_DYES + 1))
    assert_true(plain_dye(0) != plain_dye(1))
    assert_true(rich_dye(0) != rich_dye(1))
    assert_true(fur_dye(2) == fur_dye(FUR_DYES + 2))
    assert_true(forest_dye(1) == forest_dye(FOREST_DYES + 1))
    assert_true(arcane_dye(3) == arcane_dye(ARCANE_DYES + 3))
    assert_true(shadow_dye(4) == shadow_dye(SHADOW_DYES + 4))
    assert_true(fur_dye(0) != fur_dye(1))
    assert_true(forest_dye(0) != forest_dye(1))
    assert_true(arcane_dye(0) != arcane_dye(1))
    assert_true(shadow_dye(0) != shadow_dye(1))


def test_each_calling_wears_its_own_clothes() raises:
    for seed in range(24):
        for k in range(FARMER.value):
            var outfit = calling_outfit(Calling(k), seed)
            outfit.check()
            assert_true(_has(outfit, "boots"))
            assert_true(_has(outfit, "shirt"))
        var monk = calling_outfit(MONK, seed)
        assert_true(_has(monk, "robe") and _has(monk, "hood"))
        assert_true(_has(calling_outfit(GOODWIFE, seed), "gown"))
        assert_true(_has(calling_outfit(NOBLEWOMAN, seed), "belt"))
        var archer = calling_outfit(ARCHER, seed)
        assert_true(_has(archer, "jerkin") and _has(archer, "gambeson"))
        assert_true(_has(calling_outfit(PEASANT, seed), "breeches"))
        assert_true(_has(calling_outfit(MERCHANT, seed), "tunic"))
        assert_true(_has(calling_outfit(MAN_AT_ARMS, seed), "hauberk"))
        var knight = calling_outfit(KNIGHT, seed)
        assert_true(_has(knight, "cuirass") and _has(knight, "belt"))


def test_small_choices_differ_from_seed_to_seed() raises:
    var hooded = 0
    var belted = 0
    var surcoats = 0
    var blackened = 0
    for seed in range(60):
        if _has(calling_outfit(PEASANT, seed), "hood"):
            hooded += 1
        if _has(calling_outfit(PEASANT, seed), "belt"):
            belted += 1
        if _has(calling_outfit(MAN_AT_ARMS, seed), "surcoat"):
            surcoats += 1
        var knight = calling_outfit(KNIGHT, seed)
        for garment in knight.garments:
            if garment.fabric == PLATE and garment.dyes[0].r < 100:
                blackened += 1
                break
    assert_true(hooded > 10 and hooded < 50)
    assert_true(belted > 20 and belted < 55)
    assert_true(surcoats > 15 and surcoats < 45)
    assert_true(blackened > 5 and blackened < 35)
    # Some gowns, merchants' tunics and men-at-arms' surcoats are
    # parti-colored or quartered.
    var parted = 0
    var quartered = 0
    var gowns = 0
    for seed in range(60):
        for garment in calling_outfit(MERCHANT, seed).garments:
            if garment.name == "tunic" and garment.pattern == PARTY:
                parted += 1
        for garment in calling_outfit(MAN_AT_ARMS, seed).garments:
            if garment.name == "surcoat" and garment.pattern == QUARTERLY:
                quartered += 1
        for garment in calling_outfit(NOBLEWOMAN, seed).garments:
            if garment.name == "gown" and garment.pattern == PARTY:
                gowns += 1
    assert_true(parted > 10 and parted < 40)
    assert_true(quartered > 2 and quartered < 20)
    assert_true(gowns > 8 and gowns < 30)
    # Each goodwife's hood is a chance too.
    var goodwives = 0
    for seed in range(40):
        if _has(calling_outfit(GOODWIFE, seed), "hood"):
            goodwives += 1
    assert_true(goodwives > 5 and goodwives < 35)


def test_the_rich_wear_rich_dyes() raises:
    for seed in range(12):
        var lady = calling_outfit(NOBLEWOMAN, seed)
        var gown = lady.garments[1].copy()
        var found = False
        for k in range(RICH_DYES):
            if gown.dyes[PRIMARY_DYE.value] == rich_dye(k):
                found = True
        assert_true(found)
        var knight = calling_outfit(KNIGHT, seed)
        for garment in knight.garments:
            if garment.name == "surcoat":
                assert_true(
                    garment.dyes[PRIMARY_DYE.value]
                    != garment.dyes[SECONDARY_DYE.value]
                )
                assert_true(
                    garment.dyes[TRIM_DYE.value]
                    == garment.dyes[SECONDARY_DYE.value]
                )


def test_a_crowd_is_mixed_and_repeatable() raises:
    var counts = List[Int](length=CALLING_COUNT, fill=0)
    for seed in range(400):
        counts[mixed_calling(seed).value] += 1
    for k in range(CALLING_COUNT):
        assert_true(counts[k] > 0)
    # Peasants outnumber knights.
    assert_true(counts[PEASANT.value] > 3 * counts[KNIGHT.value])
    # The same seed gives the same outfit, and seeds differ.
    assert_equal(outfit_json(mixed_outfit(7)), outfit_json(mixed_outfit(7)))
    var differ = 0
    for seed in range(10):
        if outfit_json(mixed_outfit(seed)) != outfit_json(
            mixed_outfit(seed + 10)
        ):
            differ += 1
    assert_true(differ > 5)
    # Any integer is a seed.
    mixed_outfit(-12345).check()
    mixed_outfit(Int.MAX).check()


def test_each_archetype_dresses_either_sex() raises:
    var sexes: List[Sex] = [MALE, FEMALE]
    for seed in range(16):
        for k in range(FARMER.value, CALLING_COUNT):
            for sex in sexes:
                var outfit = dressed_as(Calling(k), sex, seed)
                outfit.check()
        var farmer = dressed_as(FARMER, MALE, seed)
        assert_true(_has(farmer, "trousers"))
        assert_true(_has(farmer, "smock") or _has(farmer, "tunic"))
        assert_true(_has(dressed_as(FARMER, FEMALE, seed), "gown"))
        # A barbarian is bare-chested; a woman wears a jerkin.
        var barbarian = dressed_as(BARBARIAN, MALE, seed)
        assert_false(_has(barbarian, "shirt"))
        assert_true(_has(barbarian, "fur kilt"))
        assert_true(_has(dressed_as(BARBARIAN, FEMALE, seed), "jerkin"))
        var king = dressed_as(ROYAL, MALE, seed)
        assert_true(_has(king, "royal robe") and _has(king, "crown"))
        var queen = dressed_as(ROYAL, FEMALE, seed)
        assert_true(_has(queen, "royal gown"))
        assert_true(_has(queen, "crown") or _has(queen, "circlet"))
        var wizard = dressed_as(WIZARD, MALE, seed)
        assert_true(_has(wizard, "wizard robe") and _has(wizard, "wizard hat"))
        assert_true(_has(dressed_as(WARLOCK, FEMALE, seed), "cassock"))
        var ranger = dressed_as(RANGER, MALE, seed)
        assert_true(_has(ranger, "bracers"))
        assert_true(_has(ranger, "feathered cap") or _has(ranger, "hood"))
        # A warrior's plate is all of one metal.
        var warrior = dressed_as(WARRIOR, FEMALE, seed)
        assert_true(_has(warrior, "platebody") and _has(warrior, "plate legs"))
        var metal = warrior_metal(seed)
        for garment in warrior.garments:
            if garment.fabric == PLATE:
                assert_equal(garment.metal, metal)
    with assert_raises(contains="MALE or FEMALE"):
        _ = dressed_as(FARMER, Sex(5), 0)
    with assert_raises(contains="named one"):
        _ = dressed_as(Calling(40), MALE, 0)


def test_archetypes_choose_by_chance() raises:
    var straw = 0
    var horns = 0
    var circlets = 0
    var hoods = 0
    var caps = 0
    var bare = 0
    var trimmed = 0
    var seen = List[Bool](length=METAL_COUNT, fill=False)
    for seed in range(80):
        if _has(dressed_as(FARMER, MALE, seed), "straw hat"):
            straw += 1
        if _has(dressed_as(BARBARIAN, MALE, seed), "horned helm"):
            horns += 1
        if _has(dressed_as(ROYAL, FEMALE, seed), "circlet"):
            circlets += 1
        if _has(dressed_as(WARLOCK, MALE, seed), "hood"):
            hoods += 1
        if _has(dressed_as(RANGER, FEMALE, seed), "feathered cap"):
            caps += 1
        var warrior = dressed_as(WARRIOR, FEMALE, seed)
        var helmed = False
        for garment in warrior.garments:
            if garment.form == HATTED:
                helmed = True
            if garment.name == "platebody" and not (
                garment.dyes[2] == garment.dyes[0]
            ):
                trimmed += 1
        if not helmed:
            bare += 1
        seen[warrior_metal(seed).value] = True
    assert_true(straw > 40 and straw < 72)
    assert_true(horns > 25 and horns < 55)
    assert_true(circlets > 15 and circlets < 50)
    assert_true(hoods > 35 and hoods < 65)
    assert_true(caps > 25 and caps < 55)
    assert_true(bare > 10 and bare < 40)
    assert_true(trimmed > 20 and trimmed < 60)
    var metals = 0
    for k in range(METAL_COUNT):
        if seen[k]:
            metals += 1
    assert_true(metals >= 7)
    # A man in plate always wears a helm.
    for seed in range(40):
        var helmed = False
        for garment in dressed_as(WARRIOR, MALE, seed).garments:
            if garment.form == HATTED:
                helmed = True
        assert_true(helmed)


def test_each_person_of_a_crowd_has_a_sex() raises:
    assert_equal(calling_sex(GOODWIFE), FEMALE)
    assert_equal(calling_sex(NOBLEWOMAN), FEMALE)
    assert_equal(calling_sex(KNIGHT), MALE)
    var women = 0
    var men = 0
    for seed in range(400):
        var calling = mixed_calling(seed)
        var sex = mixed_sex(seed)
        if calling.value < FARMER.value:
            assert_equal(sex, calling_sex(calling))
        elif sex == FEMALE:
            women += 1
        else:
            men += 1
    assert_true(women > 20 and men > 30)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
