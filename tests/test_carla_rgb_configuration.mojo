# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""RGB camera attribute conversion must reject invalid physical settings."""

from extensions.carla.blueprint import ATTRIBUTE_FLOAT, ActorAttributeValue
from extensions.carla.camera_render import rgb_camera_settings
from std.testing import TestSuite, assert_equal, assert_raises


def test_rgb_floats_are_finite_after_conversion() raises:
    for field in [
        "gamma",
        "exposure_compensation",
        "shutter_speed",
        "iso",
        "fstop",
        "exposure_min_bright",
        "exposure_max_bright",
        "exposure_speed_up",
        "exposure_speed_down",
        "calibration_constant",
        "bloom_intensity",
        "lens_flare_intensity",
        "motion_blur_intensity",
        "motion_blur_max_distortion",
        "motion_blur_min_object_screen_size",
        "chromatic_aberration_intensity",
        "chromatic_aberration_offset",
        "tint",
        "slope",
        "toe",
        "shoulder",
        "black_clip",
        "white_clip",
        "min_fstop",
        "blur_amount",
        "blur_radius",
        "temp",
        "focal_distance",
        "lens_k",
        "lens_kcube",
        "lens_x_size",
        "lens_y_size",
        "lens_circle_falloff",
        "lens_circle_multiplier",
    ]:
        for text in ["nan", "inf", "-inf", "1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = rgb_camera_settings(
                    [ActorAttributeValue(field, ATTRIBUTE_FLOAT, text)]
                )


def test_rgb_logarithm_and_gamma_domains() raises:
    for field in [
        "gamma",
        "shutter_speed",
        "iso",
        "fstop",
        "calibration_constant",
    ]:
        for text in ["0", "-1"]:
            with assert_raises(contains="positive"):
                _ = rgb_camera_settings(
                    [ActorAttributeValue(field, ATTRIBUTE_FLOAT, text)]
                )
    var s = rgb_camera_settings(
        [ActorAttributeValue("exposure_compensation", ATTRIBUTE_FLOAT, "-2")]
    )
    assert_equal(s.exposure_compensation, -2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
