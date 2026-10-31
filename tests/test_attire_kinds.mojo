# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the named kinds of `extensions.attire`."""

from extensions.attire.kinds import (
    CROWN,
    CIRCLET,
    GREAT_HELM,
    HALF_HELM,
    HATTED,
    HEADWEAR_COUNT,
    NO_HEADWEAR,
    STRAW,
    Headwear,
    headwear_label,
    headwear_named,
    require_headwear,
    ACCENT_DYE,
    BUMP_COUNT,
    MAIL_RINGS,
    NO_BUMP,
    TWILL,
    Bump,
    require_bump,
    ARMOR_LAYER,
    ARTICULATION_COUNT,
    BACK_SLOT,
    DAMAGE,
    DIRT,
    DYE_CHANNEL_COUNT,
    DYE_PATTERN_COUNT,
    FABRIC_KIND_COUNT,
    FITTED,
    FLEXIBLE,
    FORM_COUNT,
    HEAD_SLOT,
    LAMED,
    LAYER_COUNT,
    LINEN,
    MAIL,
    OVER_LAYER,
    PARTY,
    PLATE,
    PRIMARY_DYE,
    QUARTERLY,
    RIGID,
    SHOD,
    SKIRTED,
    SLOT_COUNT,
    SOLID,
    STRIPES,
    TORSO_SLOT,
    UNDER_LAYER,
    WEAR_KIND_COUNT,
    WOOL,
    Articulation,
    DyeChannel,
    DyePattern,
    FabricKind,
    Form,
    Layer,
    Slot,
    WearKind,
    articulation_label,
    articulation_named,
    fabric_label,
    fabric_named,
    form_label,
    form_named,
    layer_label,
    layer_named,
    pattern_label,
    pattern_named,
    require_articulation,
    require_dye_channel,
    require_dye_pattern,
    require_fabric_kind,
    require_form,
    require_layer,
    require_slot,
    require_wear_kind,
    slot_label,
    slot_named,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_slots_are_named_and_round_trip() raises:
    assert_true(HEAD_SLOT.is_valid())
    assert_true(BACK_SLOT.is_valid())
    assert_false(Slot(-1).is_valid())
    assert_false(Slot(SLOT_COUNT).is_valid())
    for k in range(SLOT_COUNT):
        assert_equal(slot_named(slot_label(Slot(k))).value, k)
    assert_equal(slot_label(Slot(99)), "slot")
    assert_equal(slot_label(TORSO_SLOT), "torso")
    require_slot(TORSO_SLOT)
    with assert_raises(contains="named slot"):
        require_slot(Slot(99))
    with assert_raises(contains="No slot is named"):
        _ = slot_named("hat")


def test_layers_are_ordered_from_the_skin_out() raises:
    assert_true(UNDER_LAYER < ARMOR_LAYER)
    assert_false(OVER_LAYER < ARMOR_LAYER)
    assert_true(UNDER_LAYER.is_valid())
    assert_false(Layer(LAYER_COUNT).is_valid())
    assert_false(Layer(-1).is_valid())
    for k in range(LAYER_COUNT):
        assert_equal(layer_named(layer_label(Layer(k))).value, k)
    assert_equal(layer_label(Layer(7)), "layer")
    require_layer(OVER_LAYER)
    with assert_raises(contains="named layer"):
        require_layer(Layer(7))
    with assert_raises(contains="must be under"):
        _ = layer_named("inner")


def test_fabric_kinds_know_their_metal() raises:
    assert_true(MAIL.is_metal())
    assert_true(PLATE.is_metal())
    assert_false(WOOL.is_metal())
    assert_false(FabricKind(FABRIC_KIND_COUNT).is_valid())
    assert_false(FabricKind(-1).is_valid())
    for k in range(FABRIC_KIND_COUNT):
        assert_equal(fabric_named(fabric_label(FabricKind(k))).value, k)
    assert_equal(fabric_label(FabricKind(-3)), "fabric")
    assert_equal(fabric_label(LINEN), "linen")
    require_fabric_kind(LINEN)
    with assert_raises(contains="named kind"):
        require_fabric_kind(FabricKind(-3))
    with assert_raises(contains="No fabric kind"):
        _ = fabric_named("denim")


def test_dye_channels_and_patterns_are_named() raises:
    assert_true(PRIMARY_DYE.is_valid())
    assert_true(ACCENT_DYE.is_valid())
    assert_false(DyeChannel(DYE_CHANNEL_COUNT).is_valid())
    assert_false(DyeChannel(-1).is_valid())
    require_dye_channel(ACCENT_DYE)
    with assert_raises(contains="named channel"):
        require_dye_channel(DyeChannel(4))
    for k in range(DYE_PATTERN_COUNT):
        var pattern = DyePattern(k)
        assert_true(pattern.is_valid())
        assert_equal(pattern_named(pattern_label(pattern)), pattern)
    assert_equal(pattern_label(DyePattern(9)), "checky")
    assert_false(DyePattern(DYE_PATTERN_COUNT).is_valid())
    assert_false(DyePattern(-1).is_valid())
    assert_equal(pattern_label(DyePattern(40)), "pattern")
    require_dye_pattern(PARTY)
    with assert_raises(contains="named pattern"):
        require_dye_pattern(DyePattern(40))
    with assert_raises(contains="No dye pattern"):
        _ = pattern_named("lozengy")


def test_wear_kinds_are_named() raises:
    assert_true(DIRT.is_valid())
    assert_true(DAMAGE.is_valid())
    assert_false(WearKind(WEAR_KIND_COUNT).is_valid())
    assert_false(WearKind(-1).is_valid())
    require_wear_kind(DIRT)
    with assert_raises(contains="named channel"):
        require_wear_kind(WearKind(4))


def test_forms_are_named() raises:
    for k in range(FORM_COUNT):
        var form = Form(k)
        assert_true(form.is_valid())
        assert_equal(form_named(form_label(form)), form)
    assert_equal(form_label(SKIRTED), "skirted")
    assert_equal(form_label(Form(9)), "form")
    assert_equal(form_label(HATTED), "hatted")
    assert_false(Form(-1).is_valid())
    assert_false(Form(FORM_COUNT).is_valid())
    require_form(FITTED)
    require_form(SHOD)
    with assert_raises(contains="named one"):
        require_form(Form(9))
    with assert_raises(contains="No form"):
        _ = form_named("baggy")


def test_headwear_is_named() raises:
    for k in range(HEADWEAR_COUNT):
        var headwear = Headwear(k)
        assert_true(headwear.is_valid())
        assert_equal(headwear_named(headwear_label(headwear)), headwear)
    assert_equal(headwear_label(GREAT_HELM), "great helm")
    assert_equal(headwear_label(Headwear(40)), "headwear")
    assert_false(Headwear(-1).is_valid())
    assert_false(Headwear(HEADWEAR_COUNT).is_valid())
    # A great helm closes the head; the rest leave the hair below them.
    assert_false(GREAT_HELM.keeps_hair())
    assert_true(HALF_HELM.keeps_hair())
    assert_true(CIRCLET.keeps_hair())
    # A crown and a circlet are open over the hair; a hat is not.
    assert_true(CIRCLET.is_open())
    assert_true(CROWN.is_open())
    assert_false(HALF_HELM.is_open())
    require_headwear(NO_HEADWEAR)
    with assert_raises(contains="named one"):
        require_headwear(Headwear(40))
    with assert_raises(contains="No headwear"):
        _ = headwear_named("turban")
    assert_equal(fabric_label(STRAW), "straw")


def test_articulations_are_named() raises:
    for k in range(ARTICULATION_COUNT):
        var articulation = Articulation(k)
        assert_true(articulation.is_valid())
        assert_equal(
            articulation_named(articulation_label(articulation)), articulation
        )
    assert_equal(articulation_label(RIGID), "rigid")
    assert_equal(articulation_label(Articulation(5)), "articulation")
    assert_false(Articulation(-1).is_valid())
    assert_false(Articulation(ARTICULATION_COUNT).is_valid())
    require_articulation(LAMED)
    require_articulation(FLEXIBLE)
    with assert_raises(contains="named one"):
        require_articulation(Articulation(5))
    with assert_raises(contains="No articulation"):
        _ = articulation_named("loose")


def test_bump_maps_are_named() raises:
    for k in range(BUMP_COUNT):
        assert_true(Bump(k).is_valid())
    assert_false(Bump(BUMP_COUNT).is_valid())
    assert_false(Bump(-1).is_valid())
    assert_true(MAIL_RINGS != TWILL)
    require_bump(NO_BUMP)
    with assert_raises(contains="bump map"):
        require_bump(Bump(BUMP_COUNT))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
