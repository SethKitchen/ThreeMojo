# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the fabric table, its looks and the areal density units."""

from extensions.anatomy.evidence import DESIGN, FROM_TEXT
from extensions.attire.fabric import (
    dye_sheen,
    fabric,
    fabric_material,
    fold_depth,
)
from extensions.attire.kinds import (
    FABRIC_KIND_COUNT,
    FELT,
    FUR,
    STRAW,
    LEATHER,
    LINEN,
    MAIL,
    PADDING,
    PLATE,
    SCALE,
    SILK,
    VELVET,
    WOOL,
    FabricKind,
)
from extensions.attire.metal import BLACKENED, BRONZE, GOLD, IRON, Metal
from extensions.attire.quantities import (
    ArealDensity,
    GRAM_PER_SQUARE_METER,
    KILOGRAM_PER_SQUARE_METER,
    OUNCE_PER_SQUARE_YARD,
)
from materials.material import PHYSICAL, SCENE_ENVIRONMENT
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Area, MILLIMETER, SQUARE_METER


def test_areal_density_units_convert() raises:
    var linen = ArealDensity(200, GRAM_PER_SQUARE_METER)
    assert_almost_equal(linen.to(KILOGRAM_PER_SQUARE_METER), 0.2, atol=1e-6)
    # One ounce per square yard is about 33.906 g/m^2.
    var ounce = ArealDensity(1, OUNCE_PER_SQUARE_YARD)
    assert_almost_equal(ounce.to(GRAM_PER_SQUARE_METER), 33.906, atol=1e-3)
    # Times an area, an areal density is a mass.
    var mass = linen * Area(1.5, SQUARE_METER)
    assert_almost_equal(mass.value, 0.3, atol=1e-6)


def test_each_fabric_has_its_constants() raises:
    for k in range(FABRIC_KIND_COUNT):
        var cloth = fabric(FabricKind(k))
        assert_equal(cloth.kind, FabricKind(k))
        assert_true(cloth.areal_density.value > 0)
        assert_true(cloth.thickness.value > 0)
        assert_true(cloth.clearance.value > 0)
        assert_true(cloth.drape >= 1)
    # Plate: 2 mm of steel at 7,850 kg/m^3 is 15.7 kg/m^2.
    var plate = fabric(PLATE)
    assert_almost_equal(
        plate.areal_density.to(KILOGRAM_PER_SQUARE_METER), 15.7, atol=1e-4
    )
    assert_almost_equal(plate.thickness.to(MILLIMETER), 2, atol=1e-5)
    assert_equal(plate.source.evidence, DESIGN)
    assert_equal(fabric(PADDING).source.evidence, FROM_TEXT)
    assert_equal(fabric(MAIL).source.source, "ClevelandHauberk")
    # Stiffer fabrics span more of the body's hollows.
    assert_true(fabric(PLATE).drape > fabric(PADDING).drape)
    assert_true(fabric(PADDING).drape > fabric(LINEN).drape)
    with assert_raises(contains="named kind"):
        _ = fabric(FabricKind(42))


def test_each_fabric_has_a_physical_look() raises:
    var white = Color(255, 255, 255)
    for k in range(FABRIC_KIND_COUNT):
        var look = fabric_material(FabricKind(k), white)
        assert_equal(look.kind, PHYSICAL)
        assert_true(look.vertex_colors)
        assert_equal(look.env_map, SCENE_ENVIRONMENT)
    # Metal is metal; cloth has a sheen.
    assert_true(fabric_material(PLATE, white).metalness > 0.5)
    assert_true(fabric_material(MAIL, white).metalness > 0.5)
    assert_true(fabric_material(MAIL, white).roughness > 0.4)
    assert_true(fabric_material(WOOL, white).sheen > 0)
    assert_true(fabric_material(SILK, white).sheen > 0)
    assert_true(fabric_material(VELVET, white).sheen > 0)
    assert_true(fabric_material(LEATHER, white).clearcoat > 0)
    assert_true(fabric_material(FUR, white).sheen > 0.9)
    assert_true(fabric_material(FELT, white).sheen > 0)
    assert_true(fabric_material(STRAW, white).clearcoat > 0)
    # Mail and plate take their metal's finish.
    var gold = fabric_material(PLATE, white, GOLD)
    var iron = fabric_material(PLATE, white, IRON)
    assert_true(gold.roughness < iron.roughness)
    assert_true(gold.metalness > fabric_material(PLATE, white).metalness)
    assert_true(
        fabric_material(MAIL, white, BLACKENED).metalness
        < fabric_material(MAIL, white).metalness
    )
    assert_true(
        fabric_material(MAIL, white, IRON).roughness
        > fabric_material(PLATE, white, IRON).roughness
    )
    with assert_raises(contains="metal must"):
        _ = fabric_material(PLATE, white, Metal(77))
    with assert_raises(contains="named kind"):
        _ = fabric_material(FabricKind(-1), white)


def test_soft_cloth_folds_and_plate_does_not() raises:
    assert_true(fold_depth(WOOL).value > fold_depth(LINEN).value)
    assert_equal(fold_depth(SILK).value, fold_depth(LINEN).value)
    assert_equal(fold_depth(VELVET).value, fold_depth(WOOL).value)
    assert_true(fold_depth(LEATHER).value > fold_depth(PADDING).value)
    assert_equal(fold_depth(MAIL).value, fold_depth(LEATHER).value)
    assert_equal(fold_depth(PLATE).value, 0)
    assert_equal(fold_depth(STRAW).value, fold_depth(PADDING).value)
    assert_true(fold_depth(FUR).value > fold_depth(LEATHER).value)
    assert_equal(fold_depth(FELT).value, fold_depth(FUR).value)
    with assert_raises(contains="named kind"):
        _ = fold_depth(FabricKind(99))


def test_a_cloth_s_sheen_takes_its_dye() raises:
    var wool = fabric_material(WOOL, Color(255, 255, 255))
    dye_sheen(wool, Color(20, 30, 40))
    # A dark dye shines a little paler, and never gray-white.
    assert_true(wool.sheen_color.r > 20 and wool.sheen_color.r < 130)
    assert_true(wool.sheen_color.b > wool.sheen_color.r)
    var plate = fabric_material(PLATE, Color(255, 255, 255))
    var before = plate.sheen_color
    dye_sheen(plate, Color(20, 30, 40))
    assert_true(plate.sheen_color == before)


def test_scale_is_a_metal_on_a_backing() raises:
    var scale = fabric(SCALE)
    assert_almost_equal(Float32(scale.areal_density.value), 10.5)
    assert_almost_equal(Float32(scale.thickness.to(MILLIMETER)), 4)
    assert_true(SCALE.is_metal())
    assert_equal(fold_depth(SCALE).value, fold_depth(MAIL).value)
    var bronze = fabric_material(SCALE, Color(255, 255, 255), BRONZE)
    var plate = fabric_material(PLATE, Color(255, 255, 255), BRONZE)
    assert_true(bronze.kind == PHYSICAL)
    assert_true(bronze.metalness > 0.5)
    # A little rougher than plate of the same metal.
    assert_true(bronze.roughness > plate.roughness)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
