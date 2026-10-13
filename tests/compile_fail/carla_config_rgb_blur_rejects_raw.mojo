# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a raw mismatch at the rgb_blur configuration boundary."""

from extensions.carla.camera_render import RgbCameraSettings


def main() raises:
    var settings = RgbCameraSettings()
    settings.set_depth_blur_distance(Float32(1))
