# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's everyday clothes: the natural dyes and the outfits."""

from extensions.attire.kinds import (
    FEET_SLOT,
    HEAD_SLOT,
    LEGS_SLOT,
    PRIMARY_DYE,
    TORSO_SLOT,
    TRIM_DYE,
)
from extensions.village.clothes import (
    CREAM_WOOL,
    GRAY_WOOL,
    MADDER,
    NATURAL_DYES,
    NETTLE,
    WALNUT,
    WELD,
    WOAD,
    dyed_outfit,
    natural_dye,
    village_outfit,
)
from render.framebuffer import Color
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _same(a: Color, b: Color) -> Bool:
    """Return whether two colors are the same."""
    return a.r == b.r and a.g == b.g and a.b == b.b


def test_the_natural_dyes_go_round() raises:
    var dyes = [MADDER, WOAD, WELD, WALNUT, NETTLE, GRAY_WOOL, CREAM_WOOL]
    assert_equal(len(dyes), NATURAL_DYES)
    for k in range(NATURAL_DYES):
        assert_true(_same(natural_dye(k), dyes[k]))
        # Any integer names a dye: the list goes around both ways.
        assert_true(_same(natural_dye(k + NATURAL_DYES * 3), dyes[k]))
        assert_true(_same(natural_dye(k - NATURAL_DYES * 2), dyes[k]))


def test_a_villager_wears_a_shirt_hose_a_tunic_and_boots() raises:
    var outfit = village_outfit(WOAD, WELD, WALNUT, False)
    outfit.check()
    assert_equal(len(outfit.garments), 4)
    var slots = [TORSO_SLOT, LEGS_SLOT, TORSO_SLOT, FEET_SLOT]
    for k in range(4):
        assert_true(outfit.garments[k].slot == slots[k])
    ref hose = outfit.garments[1]
    for dye in hose.dyes:
        assert_true(_same(dye, WALNUT))
    ref tunic = outfit.garments[2]
    assert_true(_same(tunic.dyes[PRIMARY_DYE.value], WOAD))
    assert_true(_same(tunic.dyes[TRIM_DYE.value], WELD))
    # The shirt and the boots keep their own colors.
    assert_false(_same(outfit.garments[0].dyes[0], WOAD))


def test_a_hood_takes_the_tunics_dye() raises:
    var outfit = village_outfit(NETTLE, MADDER, GRAY_WOOL, True)
    assert_equal(len(outfit.garments), 5)
    ref cowl = outfit.garments[4]
    assert_true(cowl.slot == HEAD_SLOT)
    for dye in cowl.dyes:
        assert_true(_same(dye, NETTLE))


def test_a_seed_picks_three_different_dyes() raises:
    for seed in range(-10, 10):
        var outfit = dyed_outfit(seed, False)
        ref tunic = outfit.garments[2]
        var body = tunic.dyes[PRIMARY_DYE.value]
        var trim = tunic.dyes[TRIM_DYE.value]
        var legs = outfit.garments[1].dyes[0]
        assert_true(_same(body, natural_dye(seed)))
        assert_false(_same(body, trim))
        assert_false(_same(body, legs))
        assert_false(_same(trim, legs))
    assert_equal(len(dyed_outfit(4, True).garments), 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
