# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the options of DLSS Super Resolution and Ray Reconstruction:
Streamline's defaults, the preset of a mode, the DLSS 4.5 models, and every
value the checks refuse."""

from extensions.streamline.kinds import (
    DenoiserPreset,
    MODE_BALANCED,
    MODE_DLAA,
    MODE_MAX_PERFORMANCE,
    MODE_MAX_QUALITY,
    MODE_OFF,
    MODE_ULTRA_PERFORMANCE,
    MODE_ULTRA_QUALITY,
    NormalRoughnessMode,
    ROUGHNESS_PACKED,
    ROUGHNESS_UNPACKED,
    RR_PRESET_D,
    RR_PRESET_DEFAULT,
    RR_PRESET_F,
    SR_PRESET_DEFAULT,
    SR_PRESET_K,
    SR_PRESET_L,
    SR_PRESET_M,
    SuperResolutionPreset,
    UpscaleMode,
)
from extensions.streamline.options import (
    MAX_EXTENT,
    RayReconstructionOptions,
    SuperResolutionOptions,
    check_ray_reconstruction,
    check_super_resolution,
)
from math.matrix4 import Matrix4, translation
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def modes() -> List[UpscaleMode]:
    """Return the six modes that run."""
    return [
        MODE_MAX_PERFORMANCE,
        MODE_BALANCED,
        MODE_MAX_QUALITY,
        MODE_ULTRA_PERFORMANCE,
        MODE_ULTRA_QUALITY,
        MODE_DLAA,
    ]


def test_super_resolution_starts_with_streamline_s_defaults() raises:
    var options = SuperResolutionOptions(MODE_MAX_QUALITY, 3840, 2160)
    assert_equal(options.mode, MODE_MAX_QUALITY)
    assert_equal(options.output_width, 3840)
    assert_equal(options.output_height, 2160)
    assert_equal(options.pre_exposure, 1)
    assert_equal(options.exposure_scale, 1)
    assert_true(options.colors_are_hdr)
    assert_false(options.auto_exposure)
    assert_false(options.alpha_upscaling)
    assert_equal(options.dlaa_preset, SR_PRESET_DEFAULT)
    assert_equal(options.quality_preset, SR_PRESET_DEFAULT)
    assert_equal(options.balanced_preset, SR_PRESET_DEFAULT)
    assert_equal(options.performance_preset, SR_PRESET_DEFAULT)
    assert_equal(options.ultra_performance_preset, SR_PRESET_DEFAULT)
    assert_equal(options.ultra_quality_preset, SR_PRESET_DEFAULT)
    check_super_resolution(options)


def test_super_resolution_reads_the_preset_of_its_mode() raises:
    var options = SuperResolutionOptions(MODE_OFF, 64, 64)
    options.dlaa_preset = SuperResolutionPreset(10)
    options.quality_preset = SuperResolutionPreset(11)
    options.balanced_preset = SuperResolutionPreset(12)
    options.performance_preset = SuperResolutionPreset(13)
    options.ultra_performance_preset = SuperResolutionPreset(14)
    options.ultra_quality_preset = SuperResolutionPreset(15)
    assert_equal(options.preset(), SR_PRESET_DEFAULT)
    options.mode = MODE_DLAA
    assert_equal(options.preset().value, 10)
    options.mode = MODE_MAX_QUALITY
    assert_equal(options.preset().value, 11)
    options.mode = MODE_BALANCED
    assert_equal(options.preset().value, 12)
    options.mode = MODE_MAX_PERFORMANCE
    assert_equal(options.preset().value, 13)
    options.mode = MODE_ULTRA_PERFORMANCE
    assert_equal(options.preset().value, 14)
    options.mode = MODE_ULTRA_QUALITY
    assert_equal(options.preset().value, 15)
    options.mode = UpscaleMode(9)
    assert_equal(options.preset(), SR_PRESET_DEFAULT)


def test_super_resolution_runs_a_dlss_4_5_model_in_every_mode() raises:
    for mode in modes():
        var options = SuperResolutionOptions(mode, 1920, 1080)
        options.use_dlss_4_5(SR_PRESET_M)
        assert_equal(options.preset(), SR_PRESET_M)
        assert_true(options.preset().is_dlss_4_5())
        options.use_dlss_4_5(SR_PRESET_L)
        assert_equal(options.preset(), SR_PRESET_L)
        check_super_resolution(options)
    var options = SuperResolutionOptions(MODE_DLAA, 1920, 1080)
    with assert_raises(contains="L or M"):
        options.use_dlss_4_5(SR_PRESET_K)
    with assert_raises(contains="L or M"):
        options.use_dlss_4_5(SR_PRESET_DEFAULT)
    assert_equal(options.preset(), SR_PRESET_DEFAULT)


def test_the_super_resolution_check_refuses_what_streamline_cannot_use() raises:
    var options = SuperResolutionOptions(MODE_BALANCED, 1280, 720)
    options.mode = UpscaleMode(7)
    with assert_raises(contains="mode"):
        check_super_resolution(options)
    options.mode = UpscaleMode(-1)
    with assert_raises(contains="mode"):
        check_super_resolution(options)
    options.mode = MODE_OFF
    check_super_resolution(options)
    options.output_width = 0
    with assert_raises(contains="width"):
        check_super_resolution(options)
    options.output_width = MAX_EXTENT + 1
    with assert_raises(contains="width"):
        check_super_resolution(options)
    options.output_width = MAX_EXTENT
    check_super_resolution(options)
    options.output_height = 0
    with assert_raises(contains="height"):
        check_super_resolution(options)
    options.output_height = MAX_EXTENT + 1
    with assert_raises(contains="height"):
        check_super_resolution(options)
    options.output_height = 1
    check_super_resolution(options)


def test_the_exposures_must_be_finite_and_positive() raises:
    var options = SuperResolutionOptions(MODE_BALANCED, 1280, 720)
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        Float32(0),
        Float32(-1),
    ]:
        options.pre_exposure = bad
        with assert_raises(contains="pre-exposure"):
            check_super_resolution(options)
    options.pre_exposure = 2
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        Float32(0),
        Float32(-1),
    ]:
        options.exposure_scale = bad
        with assert_raises(contains="exposure scale"):
            check_super_resolution(options)
    options.exposure_scale = 0.5
    check_super_resolution(options)


def test_the_super_resolution_check_refuses_a_removed_preset() raises:
    for value in [1, 2, 3, 4, 16, -1]:
        var options = SuperResolutionOptions(MODE_BALANCED, 1280, 720)
        var bad = SuperResolutionPreset(value)
        options.dlaa_preset = bad
        with assert_raises(contains="preset"):
            check_super_resolution(options)
        options.dlaa_preset = SR_PRESET_DEFAULT
        options.quality_preset = bad
        with assert_raises(contains="preset"):
            check_super_resolution(options)
        options.quality_preset = SR_PRESET_DEFAULT
        options.balanced_preset = bad
        with assert_raises(contains="preset"):
            check_super_resolution(options)
        options.balanced_preset = SR_PRESET_DEFAULT
        options.performance_preset = bad
        with assert_raises(contains="preset"):
            check_super_resolution(options)
        options.performance_preset = SR_PRESET_DEFAULT
        options.ultra_performance_preset = bad
        with assert_raises(contains="preset"):
            check_super_resolution(options)
        options.ultra_performance_preset = SR_PRESET_DEFAULT
        options.ultra_quality_preset = bad
        with assert_raises(contains="preset"):
            check_super_resolution(options)


def test_ray_reconstruction_starts_with_streamline_s_defaults() raises:
    var options = RayReconstructionOptions(MODE_MAX_QUALITY, 3840, 2160)
    assert_equal(options.mode, MODE_MAX_QUALITY)
    assert_equal(options.output_width, 3840)
    assert_equal(options.output_height, 2160)
    assert_equal(options.pre_exposure, 1)
    assert_equal(options.exposure_scale, 1)
    assert_true(options.colors_are_hdr)
    assert_equal(options.normal_roughness_mode, ROUGHNESS_UNPACKED)
    assert_true(options.world_to_camera_view == Matrix4())
    assert_true(options.camera_view_to_world == Matrix4())
    assert_false(options.alpha_upscaling)
    assert_equal(options.dlaa_preset, RR_PRESET_DEFAULT)
    assert_equal(options.quality_preset, RR_PRESET_DEFAULT)
    assert_equal(options.balanced_preset, RR_PRESET_DEFAULT)
    assert_equal(options.performance_preset, RR_PRESET_DEFAULT)
    assert_equal(options.ultra_performance_preset, RR_PRESET_DEFAULT)
    assert_equal(options.ultra_quality_preset, RR_PRESET_DEFAULT)
    check_ray_reconstruction(options)


def test_ray_reconstruction_reads_the_preset_of_its_mode() raises:
    var options = RayReconstructionOptions(MODE_OFF, 64, 64)
    options.dlaa_preset = DenoiserPreset(4)
    options.quality_preset = DenoiserPreset(5)
    options.balanced_preset = DenoiserPreset(6)
    options.performance_preset = DenoiserPreset(7)
    options.ultra_performance_preset = DenoiserPreset(8)
    options.ultra_quality_preset = DenoiserPreset(9)
    assert_equal(options.preset(), RR_PRESET_DEFAULT)
    options.mode = MODE_DLAA
    assert_equal(options.preset().value, 4)
    options.mode = MODE_MAX_QUALITY
    assert_equal(options.preset().value, 5)
    options.mode = MODE_BALANCED
    assert_equal(options.preset().value, 6)
    options.mode = MODE_MAX_PERFORMANCE
    assert_equal(options.preset().value, 7)
    options.mode = MODE_ULTRA_PERFORMANCE
    assert_equal(options.preset().value, 8)
    options.mode = MODE_ULTRA_QUALITY
    assert_equal(options.preset().value, 9)
    options.mode = UpscaleMode(9)
    assert_equal(options.preset(), RR_PRESET_DEFAULT)


def test_ray_reconstruction_runs_the_dlss_4_5_model_in_every_mode() raises:
    for mode in modes():
        var options = RayReconstructionOptions(mode, 1920, 1080)
        options.use_dlss_4_5(RR_PRESET_F)
        assert_equal(options.preset(), RR_PRESET_F)
        assert_true(options.preset().is_dlss_4_5())
        check_ray_reconstruction(options)
    var options = RayReconstructionOptions(MODE_DLAA, 1920, 1080)
    with assert_raises(contains="is F"):
        options.use_dlss_4_5(RR_PRESET_D)
    with assert_raises(contains="is F"):
        options.use_dlss_4_5(RR_PRESET_DEFAULT)
    assert_equal(options.preset(), RR_PRESET_DEFAULT)


def test_the_ray_reconstruction_check_refuses_the_shared_fields() raises:
    var options = RayReconstructionOptions(MODE_BALANCED, 1280, 720)
    options.mode = UpscaleMode(7)
    with assert_raises(contains="mode"):
        check_ray_reconstruction(options)
    options.mode = MODE_BALANCED
    options.output_width = 0
    with assert_raises(contains="width"):
        check_ray_reconstruction(options)
    options.output_width = 1280
    options.output_height = 0
    with assert_raises(contains="height"):
        check_ray_reconstruction(options)
    options.output_height = 720
    options.pre_exposure = 0
    with assert_raises(contains="pre-exposure"):
        check_ray_reconstruction(options)
    options.pre_exposure = 1
    options.exposure_scale = nan[DType.float32]()
    with assert_raises(contains="exposure scale"):
        check_ray_reconstruction(options)


def test_the_ray_reconstruction_check_refuses_a_bad_mode_or_preset() raises:
    var options = RayReconstructionOptions(MODE_BALANCED, 1280, 720)
    options.normal_roughness_mode = NormalRoughnessMode(2)
    with assert_raises(contains="normal and roughness"):
        check_ray_reconstruction(options)
    options.normal_roughness_mode = ROUGHNESS_PACKED
    check_ray_reconstruction(options)
    for value in [1, 2, 3, 16, -1]:
        var bad = DenoiserPreset(value)
        var fresh = RayReconstructionOptions(MODE_BALANCED, 1280, 720)
        fresh.dlaa_preset = bad
        with assert_raises(contains="preset"):
            check_ray_reconstruction(fresh)
        fresh.dlaa_preset = RR_PRESET_DEFAULT
        fresh.quality_preset = bad
        with assert_raises(contains="preset"):
            check_ray_reconstruction(fresh)
        fresh.quality_preset = RR_PRESET_DEFAULT
        fresh.balanced_preset = bad
        with assert_raises(contains="preset"):
            check_ray_reconstruction(fresh)
        fresh.balanced_preset = RR_PRESET_DEFAULT
        fresh.performance_preset = bad
        with assert_raises(contains="preset"):
            check_ray_reconstruction(fresh)
        fresh.performance_preset = RR_PRESET_DEFAULT
        fresh.ultra_performance_preset = bad
        with assert_raises(contains="preset"):
            check_ray_reconstruction(fresh)
        fresh.ultra_performance_preset = RR_PRESET_DEFAULT
        fresh.ultra_quality_preset = bad
        with assert_raises(contains="preset"):
            check_ray_reconstruction(fresh)


def test_the_two_view_matrices_must_be_finite_inverses() raises:
    var options = RayReconstructionOptions(MODE_BALANCED, 1280, 720)
    var view = translation(-3, 4, -5)
    var inverse = translation(3, -4, 5)
    options.world_to_camera_view = view
    options.camera_view_to_world = inverse
    check_ray_reconstruction(options)
    # Not inverses.
    options.camera_view_to_world = translation(3, -4, 6)
    with assert_raises(contains="inverses"):
        check_ray_reconstruction(options)
    # Not finite.
    options.camera_view_to_world = inverse
    options.world_to_camera_view = translation(nan[DType.float32](), 0, 0)
    with assert_raises(contains="world to camera view"):
        check_ray_reconstruction(options)
    options.world_to_camera_view = view
    options.camera_view_to_world = translation(inf[DType.float32](), 0, 0)
    with assert_raises(contains="camera view to world"):
        check_ray_reconstruction(options)


def test_a_far_view_still_inverts_within_rounding() raises:
    var options = RayReconstructionOptions(MODE_BALANCED, 1280, 720)
    var view = translation(-10000, 2500, -7500)
    var inverse = view
    inverse.invert()
    options.world_to_camera_view = view
    options.camera_view_to_world = inverse
    check_ray_reconstruction(options)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
