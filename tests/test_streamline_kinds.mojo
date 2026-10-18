# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the modes, presets and buffer kinds of Streamline's DLSS
features: the numbers they carry, what is valid, and the names."""

from extensions.streamline.kinds import (
    BUFFER_ALBEDO,
    BUFFER_DEPTH,
    BUFFER_DEPTH_OF_FIELD_GUIDE,
    BUFFER_SUBSURFACE_GUIDE,
    BufferKind,
    DenoiserPreset,
    Feature,
    MODE_BALANCED,
    MODE_DLAA,
    MODE_MAX_PERFORMANCE,
    MODE_MAX_QUALITY,
    MODE_OFF,
    MODE_ULTRA_PERFORMANCE,
    MODE_ULTRA_QUALITY,
    MOTION_NORMALIZED,
    MOTION_PIXELS,
    MotionVectorSpace,
    NormalRoughnessMode,
    RAY_RECONSTRUCTION,
    ROUGHNESS_PACKED,
    ROUGHNESS_UNPACKED,
    RR_PRESET_D,
    RR_PRESET_DEFAULT,
    RR_PRESET_E,
    RR_PRESET_F,
    SR_PRESET_DEFAULT,
    SR_PRESET_J,
    SR_PRESET_K,
    SR_PRESET_L,
    SR_PRESET_M,
    SUPER_RESOLUTION,
    SuperResolutionPreset,
    UpscaleMode,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_the_features_are_two() raises:
    assert_true(SUPER_RESOLUTION.is_valid())
    assert_true(RAY_RECONSTRUCTION.is_valid())
    assert_false(Feature(-1).is_valid())
    assert_false(Feature(2).is_valid())
    assert_equal(SUPER_RESOLUTION.name(), "super resolution")
    assert_equal(RAY_RECONSTRUCTION.name(), "ray reconstruction")
    assert_equal(Feature(2).name(), "unknown")


def test_the_modes_carry_streamline_s_numbers() raises:
    # sl::DLSSMode, sl_dlss.h of Streamline 2.14.16.
    assert_equal(MODE_OFF.value, 0)
    assert_equal(MODE_MAX_PERFORMANCE.value, 1)
    assert_equal(MODE_BALANCED.value, 2)
    assert_equal(MODE_MAX_QUALITY.value, 3)
    assert_equal(MODE_ULTRA_PERFORMANCE.value, 4)
    assert_equal(MODE_ULTRA_QUALITY.value, 5)
    assert_equal(MODE_DLAA.value, 6)
    for value in range(7):
        assert_true(UpscaleMode(value).is_valid())
        assert_true(UpscaleMode(value).name() != "unknown")
    assert_false(UpscaleMode(-1).is_valid())
    assert_false(UpscaleMode(7).is_valid())
    assert_equal(MODE_DLAA.name(), "dlaa")
    assert_equal(MODE_MAX_QUALITY.name(), "max quality")
    assert_equal(UpscaleMode(7).name(), "unknown")


def test_super_resolution_presets_carry_streamline_s_numbers() raises:
    # sl::DLSSPreset: A to D are removed, so 1 to 4 are not valid.
    assert_equal(SR_PRESET_DEFAULT.value, 0)
    assert_equal(SR_PRESET_J.value, 10)
    assert_equal(SR_PRESET_K.value, 11)
    assert_equal(SR_PRESET_L.value, 12)
    assert_equal(SR_PRESET_M.value, 13)
    for value in range(1, 5):
        assert_false(SuperResolutionPreset(value).is_valid())
    assert_false(SuperResolutionPreset(-1).is_valid())
    assert_false(SuperResolutionPreset(16).is_valid())
    assert_true(SuperResolutionPreset(0).is_valid())
    assert_true(SuperResolutionPreset(5).is_valid())
    assert_true(SuperResolutionPreset(15).is_valid())


def test_super_resolution_presets_say_what_streamline_says() raises:
    for value in range(5, 16):
        var preset = SuperResolutionPreset(value)
        assert_equal(preset.is_deprecated(), value == 5 or value == 6)
        assert_equal(
            preset.reverts_to_default(),
            value == 7
            or value == 8
            or value == 9
            or value == 14
            or value == 15,
        )
        assert_equal(preset.is_dlss_4_5(), value == 12 or value == 13)
    assert_false(SR_PRESET_DEFAULT.is_deprecated())
    assert_false(SR_PRESET_DEFAULT.reverts_to_default())
    assert_false(SR_PRESET_DEFAULT.is_dlss_4_5())
    assert_equal(SR_PRESET_DEFAULT.name(), "default")
    assert_equal(SuperResolutionPreset(5).name(), "E")
    assert_equal(SR_PRESET_M.name(), "M")
    assert_equal(SuperResolutionPreset(15).name(), "O")
    assert_equal(SuperResolutionPreset(3).name(), "unknown")


def test_denoiser_presets_carry_streamline_s_numbers() raises:
    # sl::DLSSDPreset: A to C are removed, so 1 to 3 are not valid.
    assert_equal(RR_PRESET_DEFAULT.value, 0)
    assert_equal(RR_PRESET_D.value, 4)
    assert_equal(RR_PRESET_E.value, 5)
    assert_equal(RR_PRESET_F.value, 6)
    for value in range(1, 4):
        assert_false(DenoiserPreset(value).is_valid())
    assert_false(DenoiserPreset(-1).is_valid())
    assert_false(DenoiserPreset(16).is_valid())
    assert_true(DenoiserPreset(0).is_valid())
    assert_true(DenoiserPreset(4).is_valid())
    assert_true(DenoiserPreset(15).is_valid())


def test_denoiser_presets_say_what_streamline_says() raises:
    for value in range(4, 16):
        var preset = DenoiserPreset(value)
        assert_equal(preset.reverts_to_default(), value >= 7)
        assert_equal(preset.is_dlss_4_5(), value == 6)
    assert_false(RR_PRESET_DEFAULT.reverts_to_default())
    assert_false(DenoiserPreset(16).reverts_to_default())
    assert_false(RR_PRESET_DEFAULT.is_dlss_4_5())
    assert_equal(RR_PRESET_DEFAULT.name(), "default")
    assert_equal(RR_PRESET_D.name(), "D")
    assert_equal(RR_PRESET_F.name(), "F")
    assert_equal(DenoiserPreset(15).name(), "O")
    assert_equal(DenoiserPreset(2).name(), "unknown")


def test_the_normal_and_roughness_modes() raises:
    assert_equal(ROUGHNESS_UNPACKED.value, 0)
    assert_equal(ROUGHNESS_PACKED.value, 1)
    assert_true(ROUGHNESS_UNPACKED.is_valid())
    assert_true(ROUGHNESS_PACKED.is_valid())
    assert_false(NormalRoughnessMode(-1).is_valid())
    assert_false(NormalRoughnessMode(2).is_valid())
    assert_equal(ROUGHNESS_PACKED.name(), "packed")
    assert_equal(ROUGHNESS_UNPACKED.name(), "unpacked")
    assert_equal(NormalRoughnessMode(2).name(), "unknown")


def test_the_motion_vector_spaces() raises:
    assert_true(MOTION_NORMALIZED.is_valid())
    assert_true(MOTION_PIXELS.is_valid())
    assert_false(MotionVectorSpace(-1).is_valid())
    assert_false(MotionVectorSpace(2).is_valid())
    assert_equal(MOTION_NORMALIZED.name(), "normalized")
    assert_equal(MOTION_PIXELS.name(), "pixels")
    assert_equal(MotionVectorSpace(2).name(), "unknown")


def test_the_buffer_kinds_are_eighteen() raises:
    for value in range(18):
        assert_true(BufferKind(value).is_valid())
        assert_true(BufferKind(value).name() != "unknown")
    assert_false(BufferKind(-1).is_valid())
    assert_false(BufferKind(18).is_valid())
    assert_equal(BUFFER_DEPTH.value, 0)
    assert_equal(BUFFER_ALBEDO.value, 8)
    assert_equal(BUFFER_SUBSURFACE_GUIDE.value, 16)
    assert_equal(BUFFER_DEPTH_OF_FIELD_GUIDE.value, 17)
    assert_equal(BUFFER_DEPTH.name(), "depth")
    assert_equal(BUFFER_ALBEDO.name(), "albedo")
    assert_equal(BufferKind(18).name(), "unknown")


def test_the_features_map_to_streamline_s_ids() raises:
    # sl::kFeatureDLSS and sl::kFeatureDLSS_RR, sl_core_types.h.
    assert_equal(SUPER_RESOLUTION.streamline_id(), 0)
    assert_equal(RAY_RECONSTRUCTION.streamline_id(), 1001)
    with assert_raises(contains="feature"):
        _ = Feature(2).streamline_id()


def test_the_buffer_kinds_map_to_streamline_s_buffer_types() raises:
    # sl::BufferType, sl_core_types.h of Streamline 2.14.16. The running
    # sl.dlss and sl.dlss_d require 0, 1, 3 and 4: the depth, the motion
    # vectors, the scaling input color and the scaling output color.
    var types: List[Int] = [
        0,
        49,
        1,
        10,
        42,
        3,
        4,
        13,
        7,
        8,
        5,
        14,
        6,
        51,
        52,
        40,
        58,
        64,
    ]
    for value in range(18):
        assert_equal(BufferKind(value).streamline_type(), types[value])
    with assert_raises(contains="eighteen"):
        _ = BufferKind(18).streamline_type()
    with assert_raises(contains="eighteen"):
        _ = BufferKind(-1).streamline_type()


def test_five_modes_have_optimal_settings() raises:
    assert_false(MODE_OFF.has_optimal_settings())
    assert_true(MODE_MAX_PERFORMANCE.has_optimal_settings())
    assert_true(MODE_BALANCED.has_optimal_settings())
    assert_true(MODE_MAX_QUALITY.has_optimal_settings())
    assert_true(MODE_ULTRA_PERFORMANCE.has_optimal_settings())
    assert_false(MODE_ULTRA_QUALITY.has_optimal_settings())
    assert_true(MODE_DLAA.has_optimal_settings())
    assert_false(UpscaleMode(7).has_optimal_settings())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
