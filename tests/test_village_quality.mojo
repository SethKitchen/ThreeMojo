# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village game's quality: the four presets, the checks on each
setting, and the meadow each plant detail grows."""

from extensions.village.quality import (
    ALL_PLANTS,
    FEWER_PLANTS,
    FEWEST_PLANTS,
    GameQuality,
    HIGH,
    LOW,
    MANY_PLANTS,
    MEDIUM,
    PlantDetail,
    QualityPreset,
    ULTRA,
    game_quality,
    planted,
)
from extensions.village.village import VillageParameters
from renderers.game_renderer import CACHED_SHADOWS, FULL_SHADOWS, ShadowMode
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_the_presets_rise_from_low_to_ultra() raises:
    var presets: List[QualityPreset] = [LOW, MEDIUM, HIGH, ULTRA]
    var last = Float32(0)
    for preset in presets:
        assert_true(preset.is_valid())
        var quality = game_quality(preset)
        quality.check()
        assert_true(quality.render_scale > last)
        last = quality.render_scale
    assert_false(QualityPreset(4).is_valid())
    assert_false(QualityPreset(-1).is_valid())
    with assert_raises(contains="one of the four"):
        _ = game_quality(QualityPreset(4))
    assert_true(game_quality(LOW).shadows == CACHED_SHADOWS)
    assert_true(game_quality(ULTRA).shadows == FULL_SHADOWS)
    var size = game_quality(LOW).frame_size(1920, 1080)
    assert_equal(size[0], 640)
    assert_equal(size[1], 360)
    var whole = game_quality(ULTRA).frame_size(3, 2)
    assert_equal(whole[0], 3)
    assert_equal(whole[1], 2)
    with assert_raises(contains="positive"):
        _ = game_quality(LOW).frame_size(0, 10)
    with assert_raises(contains="positive"):
        _ = game_quality(LOW).frame_size(10, 0)


def _refused(quality: GameQuality, words: String) raises:
    """Assert that `check` refuses a quality, with `words` in the error."""
    with assert_raises(contains=words):
        quality.check()


def test_each_setting_is_checked() raises:
    var q = game_quality(MEDIUM)
    q.render_scale = 0.2
    _refused(q, "render scale")
    q = game_quality(MEDIUM)
    q.plants = PlantDetail(9)
    _refused(q, "plant detail")
    q = game_quality(MEDIUM)
    q.grass_wind_every = 65
    _refused(q, "wind")
    q = game_quality(MEDIUM)
    q.sky_step = 0
    _refused(q, "sky")
    q = game_quality(MEDIUM)
    q.water_step = 65
    _refused(q, "water's step")
    q = game_quality(MEDIUM)
    q.animal_coarseness = 9
    _refused(q, "coarseness")
    q = game_quality(MEDIUM)
    q.shadows = ShadowMode(4)
    _refused(q, "shadow mode")
    q = game_quality(MEDIUM)
    q.shadow_size = 32
    _refused(q, "shadow map")
    q = game_quality(MEDIUM)
    q.water_refresh_every = 0
    _refused(q, "surface")
    # The size of a frame is found only for a quality `check` passes.
    var big = GameQuality(2, ALL_PLANTS, 1, 1, 1, 1, 1, FULL_SHADOWS, 4096)
    with assert_raises(contains="render scale"):
        _ = big.frame_size(10, 10)


def test_each_plant_detail_grows_its_meadow() raises:
    var details: List[PlantDetail] = [
        FEWEST_PLANTS,
        FEWER_PLANTS,
        MANY_PLANTS,
        ALL_PLANTS,
    ]
    var litter = 0
    for detail in details:
        assert_true(detail.is_valid())
        var village = planted(VillageParameters(), detail)
        village.check()
        assert_true(village.meadow.litter > litter)
        litter = village.meadow.litter
    assert_false(PlantDetail(4).is_valid())
    with assert_raises(contains="one of the four"):
        _ = planted(VillageParameters(), PlantDetail(4))
    var fewest = planted(VillageParameters(), FEWEST_PLANTS)
    assert_true(fewest.meadow.crown_levels[0].cards)
    assert_almost_equal(fewest.meadow.crown_levels[0].detail, 0.08, atol=1e-6)
    assert_equal(fewest.caustic_resolution, 128)
    var all = planted(VillageParameters(), ALL_PLANTS)
    assert_equal(all.caustic_resolution, VillageParameters().caustic_resolution)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
