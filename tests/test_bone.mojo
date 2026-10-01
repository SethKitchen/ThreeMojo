# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for bone tissue, occupancy and the procedural PBR maps."""

from extensions.humanoid.skeleton.bone import (
    MAX_LOOK,
    MIN_LOOK,
    _byte,
    bone_albedo,
    bone_phong,
    bone_roughness,
)
from extensions.humanoid.skeleton.tissue import (
    CORTICAL,
    TRABECULAR,
    BoneKind,
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from materials.material import PHONG
from render.srgb import LINEAR, SRGB
from render.texture import IGNORED
from render.texture_store import NO_TEXTURE, TextureStore
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Density,
    GRAM_PER_CUBIC_CENTIMETER,
    GIGAPASCAL,
    MEGAPASCAL,
    PASCAL,
    Pressure,
)

comptime TOLERANCE = Float64(1e-4)


def test_cortical_and_trabecular_are_valid() raises:
    assert_true(CORTICAL.is_valid())
    assert_true(TRABECULAR.is_valid())
    assert_false(BoneKind(2).is_valid())
    assert_false(BoneKind(-1).is_valid())


def test_cortical_tissue_matches_morgan_2018() raises:
    var tissue = cortical_tissue()
    assert_true(tissue.kind == CORTICAL)
    assert_almost_equal(
        tissue.tissue_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(2.0),
        atol=TOLERANCE,
    )
    assert_almost_equal(tissue.porosity, Float32(0.10), atol=TOLERANCE)
    assert_almost_equal(
        tissue.elastic_modulus.to(GIGAPASCAL), Float32(17.9), atol=TOLERANCE
    )
    assert_almost_equal(
        tissue.elastic_modulus_secondary.to(GIGAPASCAL),
        Float32(18.16),
        atol=TOLERANCE,
    )
    assert_almost_equal(tissue.poisson_ratio, Float32(0.62), atol=TOLERANCE)
    assert_almost_equal(
        tissue.apparent_density().to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.8),
        atol=TOLERANCE,
    )


def test_trabecular_tissue_uses_the_porous_template() raises:
    var tissue = trabecular_tissue()
    assert_true(tissue.kind == TRABECULAR)
    assert_almost_equal(
        tissue.tissue_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(2.0),
        atol=TOLERANCE,
    )
    assert_almost_equal(tissue.porosity, Float32(0.80), atol=TOLERANCE)
    assert_almost_equal(
        tissue.elastic_modulus.to(MEGAPASCAL), Float32(400.0), atol=TOLERANCE
    )
    assert_almost_equal(
        tissue.apparent_density().to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.40),
        atol=TOLERANCE,
    )


def test_zero_porosity_keeps_tissue_density() raises:
    var dense = BoneTissue(
        CORTICAL,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0),
        Pressure(17.9, GIGAPASCAL),
        Pressure(18.16, GIGAPASCAL),
        Float32(0.3),
    )
    dense.validate()
    assert_equal(dense.apparent_density().value, dense.tissue_density.value)


def test_full_porosity_has_no_apparent_density() raises:
    var empty = BoneTissue(
        TRABECULAR,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        Float32(1),
        Pressure(400.0, MEGAPASCAL),
        Pressure(400.0, MEGAPASCAL),
        Float32(0),
    )
    empty.validate()
    assert_equal(empty.apparent_density().value, Float32(0))


def test_refuses_an_invalid_kind() raises:
    var tissue = cortical_tissue()
    tissue.kind = BoneKind(9)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_finite_density() raises:
    var tissue = cortical_tissue()
    tissue.tissue_density = Density(nan[DType.float32]())
    with assert_raises():
        tissue.validate()
    tissue.tissue_density = Density(inf[DType.float32]())
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_positive_density() raises:
    var tissue = cortical_tissue()
    tissue.tissue_density = Density(0)
    with assert_raises():
        tissue.validate()
    tissue.tissue_density = Density(-1.0)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_finite_porosity() raises:
    var tissue = cortical_tissue()
    tissue.porosity = nan[DType.float32]()
    with assert_raises():
        tissue.validate()


def test_refuses_a_porosity_outside_zero_to_one() raises:
    var tissue = cortical_tissue()
    tissue.porosity = Float32(-0.01)
    with assert_raises():
        tissue.validate()
    tissue.porosity = Float32(1.01)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_finite_modulus() raises:
    var tissue = cortical_tissue()
    tissue.elastic_modulus = Pressure(nan[DType.float32](), PASCAL)
    with assert_raises():
        tissue.validate()
    tissue.elastic_modulus = Pressure(inf[DType.float32](), PASCAL)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_positive_modulus() raises:
    var tissue = cortical_tissue()
    tissue.elastic_modulus = Pressure(0)
    with assert_raises():
        tissue.validate()
    tissue.elastic_modulus = Pressure(-1.0)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_finite_secondary_modulus() raises:
    var tissue = cortical_tissue()
    tissue.elastic_modulus_secondary = Pressure(nan[DType.float32](), PASCAL)
    with assert_raises():
        tissue.validate()
    tissue.elastic_modulus_secondary = Pressure(inf[DType.float32](), PASCAL)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_positive_secondary_modulus() raises:
    var tissue = cortical_tissue()
    tissue.elastic_modulus_secondary = Pressure(0)
    with assert_raises():
        tissue.validate()
    tissue.elastic_modulus_secondary = Pressure(-2.0)
    with assert_raises():
        tissue.validate()


def test_refuses_a_non_finite_poisson_ratio() raises:
    var tissue = cortical_tissue()
    tissue.poisson_ratio = nan[DType.float32]()
    with assert_raises():
        tissue.validate()


def test_refuses_a_poisson_ratio_outside_zero_to_one() raises:
    var tissue = cortical_tissue()
    tissue.poisson_ratio = Float32(-0.01)
    with assert_raises():
        tissue.validate()
    tissue.poisson_ratio = Float32(1.01)
    with assert_raises():
        tissue.validate()


def test_byte_clamps_and_rounds() raises:
    assert_equal(_byte(Float32(-1)), UInt8(0))
    assert_equal(_byte(Float32(0)), UInt8(0))
    assert_equal(_byte(Float32(10.2)), UInt8(10))
    assert_equal(_byte(Float32(10.7)), UInt8(11))
    assert_equal(_byte(Float32(255)), UInt8(255))
    assert_equal(_byte(Float32(300)), UInt8(255))


def test_albedo_is_srgb_ivory() raises:
    var image = bone_albedo(MIN_LOOK)
    assert_equal(image.width, MIN_LOOK)
    assert_equal(image.height, MIN_LOOK)
    assert_true(image.color_space == SRGB)
    var r = Int(image.pixels[0])
    var g = Int(image.pixels[1])
    var b = Int(image.pixels[2])
    assert_true(r > 140)
    assert_true(g > 120)
    assert_true(b > 90)
    assert_true(r >= g)
    assert_true(g >= b)
    # Grain and the aspera strip make the map vary.
    var same = True
    var first = image.pixels[0]
    var index = 0
    while index < len(image.pixels):
        if image.pixels[index] != first:
            same = False
        index = index + 4
    assert_false(same)


def test_roughness_is_linear_data() raises:
    var image = bone_roughness(MIN_LOOK)
    assert_true(image.color_space == LINEAR)
    assert_true(image.alpha == IGNORED)
    var shaft = Int(image.pixels[(MIN_LOOK // 2) * MIN_LOOK * 4])
    var end = Int(image.pixels[0])
    assert_true(end > shaft)


def test_bone_phong_without_a_map_is_ivory() raises:
    var paint = bone_phong()
    assert_true(paint.kind == PHONG)
    assert_true(paint.map == NO_TEXTURE)
    assert_equal(paint.color.r, UInt8(232))


def test_bone_phong_with_a_map_does_not_tint() raises:
    var store = TextureStore()
    var mapped = bone_phong(store.add(bone_albedo(MIN_LOOK)))
    assert_equal(mapped.color.r, UInt8(255))
    assert_equal(mapped.color.g, UInt8(255))
    assert_equal(mapped.color.b, UInt8(255))
    assert_true(mapped.map != NO_TEXTURE)


def test_refuses_a_small_map() raises:
    with assert_raises():
        _ = bone_albedo(MIN_LOOK - 1)
    with assert_raises():
        _ = bone_roughness(MIN_LOOK - 1)


def test_refuses_a_large_map() raises:
    with assert_raises():
        _ = bone_albedo(MAX_LOOK + 1)
    with assert_raises():
        _ = bone_roughness(MAX_LOOK + 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
