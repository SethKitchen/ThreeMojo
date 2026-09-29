# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera's exposure mode must be an `ExposureMode`, not a bare
integer."""

from extensions.carla.camera_render import RgbCameraSettings


def main():
    var settings = RgbCameraSettings()
    settings.exposure_mode = 1
    print(settings.exposure_mode.is_valid())
