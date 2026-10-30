# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a crowd's clothes: outfits picked by a seed."""

from extensions.attire.kinds import (
    PLATE,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
)
from extensions.attire.mix import (
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
from extensions.attire.outfit import Outfit
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


def test_each_calling_wears_its_own_clothes() raises:
    for seed in range(24):
        for k in range(CALLING_COUNT):
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
