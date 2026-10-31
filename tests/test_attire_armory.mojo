# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the armory's armor and helmets, and the apparel's clothes and
hats."""

from extensions.attire.apparel import (
    apparel,
    circlet,
    crown,
    feathered_cap,
    royal_mantle,
    straw_hat,
    wizard_hat,
    wizard_robe,
)
from extensions.attire.armory import (
    armory,
    great_helm,
    great_pauldrons,
    horned_helm,
    plate_legs,
    plate_skirt,
    platebody,
)
from extensions.attire.garment import greaves, wardrobe
from extensions.attire.kinds import (
    ACCENT_DYE,
    ARMOR_LAYER,
    CROWN,
    DOMED,
    FUR,
    HATTED,
    HEAD_SLOT,
    LAMED,
    NO_HEADWEAR,
    PLATE,
    PRIMARY_DYE,
    RIGID,
    SKIRTED,
    TRIM_DYE,
)
from extensions.attire.metal import GOLD, SILVER, STEEL, metal_color
from extensions.attire.outfit import Outfit
from extensions.humanoid.rig.joints import CHEST, HEAD, HIPS
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_every_new_garment_checks_and_has_its_own_name() raises:
    var names = List[String]()
    for garment in wardrobe():
        names.append(garment.name)
    var added = armory()
    added.extend(apparel())
    assert_equal(len(added), 28)
    for garment in added:
        garment.check()
        assert_false(garment.name in names)
        names.append(garment.name)
        # A hat names its headwear, and rides the head.
        if garment.form == HATTED:
            assert_true(garment.headwear != NO_HEADWEAR)
            assert_equal(garment.slot, HEAD_SLOT)
            assert_equal(garment.articulation, RIGID)
            assert_equal(garment.anchor, HEAD)


def test_plate_rides_its_bones() raises:
    var body = platebody()
    assert_equal(body.articulation, LAMED)
    assert_equal(body.anchor, CHEST)
    assert_equal(body.lames, 5)
    var skirt = plate_skirt()
    assert_equal(skirt.anchor, HIPS)
    assert_equal(skirt.form, SKIRTED)
    assert_true(skirt.flare > 0)
    assert_equal(plate_legs().articulation, RIGID)
    assert_equal(great_pauldrons().form, DOMED)
    # Plate legs take the place of greaves.
    var outfit = Outfit()
    outfit.add(greaves())
    with assert_raises(contains="already has"):
        outfit.add(plate_legs())


def test_helmets_and_hats_are_dyed() raises:
    var helm = great_helm()
    assert_equal(helm.layer, ARMOR_LAYER)
    assert_equal(helm.fabric, PLATE)
    assert_false(helm.dyes[TRIM_DYE.value] == helm.dyes[PRIMARY_DYE.value])
    assert_false(horned_helm().dyes[ACCENT_DYE.value] == Color(198, 200, 206))
    var gold = crown()
    assert_equal(gold.headwear, CROWN)
    assert_equal(gold.metal, GOLD)
    assert_true(gold.dyes[PRIMARY_DYE.value] == metal_color(GOLD))
    assert_equal(circlet().metal, SILVER)
    assert_equal(wizard_hat().metal, STEEL)
    assert_false(
        feathered_cap().dyes[ACCENT_DYE.value]
        == feathered_cap().dyes[PRIMARY_DYE.value]
    )
    assert_false(
        straw_hat().dyes[TRIM_DYE.value] == straw_hat().dyes[PRIMARY_DYE.value]
    )
    # A royal mantle is edged in white fur; a wizard's robe in gold.
    var mantle = royal_mantle()
    assert_true(mantle.dyes[TRIM_DYE.value].r > 220)
    assert_true(wizard_robe().dyes[TRIM_DYE.value].r > 200)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
