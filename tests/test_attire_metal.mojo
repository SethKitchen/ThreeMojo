# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the metals of mail and plate."""

from extensions.attire.garment import bascinet, forged, hauberk, tunic
from extensions.attire.kinds import (
    ACCENT_DYE,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
)
from extensions.attire.metal import (
    BLACKENED,
    BLUED,
    GOLD,
    IRON,
    METAL_COUNT,
    SILVER,
    STEEL,
    Metal,
    metal_color,
    metal_label,
    metal_metalness,
    metal_named,
    metal_roughness,
    require_metal,
)
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_metals_are_named() raises:
    for k in range(METAL_COUNT):
        var metal = Metal(k)
        assert_true(metal.is_valid())
        assert_equal(metal_named(metal_label(metal)), metal)
    assert_equal(metal_label(BLUED), "blued")
    assert_equal(metal_label(Metal(40)), "metal")
    assert_false(Metal(-1).is_valid())
    assert_false(Metal(METAL_COUNT).is_valid())
    require_metal(GOLD)
    with assert_raises(contains="named one"):
        require_metal(Metal(40))
    with assert_raises(contains="No metal"):
        _ = metal_named("orichalcum")


def test_each_metal_has_its_look() raises:
    var seen = List[Color]()
    for k in range(METAL_COUNT):
        var color = metal_color(Metal(k))
        for other in seen:
            assert_false(other == color)
        seen.append(color)
        var rough = metal_roughness(Metal(k))
        assert_true(rough > 0 and rough < 1)
        assert_true(metal_metalness(Metal(k)) >= 0.7)
    # Silver is the brightest and the most polished; blackened steel the
    # darkest and the least metal.
    assert_true(metal_roughness(SILVER) < metal_roughness(STEEL))
    assert_true(metal_roughness(IRON) > metal_roughness(STEEL))
    assert_equal(metal_metalness(BLACKENED), 0.7)
    assert_equal(metal_metalness(GOLD), 0.95)
    assert_equal(metal_metalness(STEEL), 0.9)
    assert_true(metal_color(BLACKENED).r < metal_color(IRON).r)
    with assert_raises(contains="named one"):
        _ = metal_color(Metal(-2))
    with assert_raises(contains="named one"):
        _ = metal_roughness(Metal(-2))
    with assert_raises(contains="named one"):
        _ = metal_metalness(Metal(-2))


def test_mail_and_plate_are_forged() raises:
    var helm = bascinet()
    helm.dyes[ACCENT_DYE.value] = Color(200, 20, 20)
    var blued = forged(helm^, BLUED, GOLD)
    assert_equal(blued.metal, BLUED)
    assert_true(blued.dyes[PRIMARY_DYE.value] == metal_color(BLUED))
    assert_true(blued.dyes[SECONDARY_DYE.value] == metal_color(BLUED))
    assert_true(blued.dyes[TRIM_DYE.value] == metal_color(GOLD))
    # The accent is left for stones and horns.
    assert_true(blued.dyes[ACCENT_DYE.value] == Color(200, 20, 20))
    var iron = forged(hauberk(), IRON)
    assert_true(iron.dyes[TRIM_DYE.value] == metal_color(IRON))
    with assert_raises(contains="Only mail and plate"):
        _ = forged(tunic(), GOLD)
    with assert_raises(contains="named one"):
        _ = forged(hauberk(), Metal(12))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
