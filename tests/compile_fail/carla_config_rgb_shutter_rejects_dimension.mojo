# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a dimension mismatch at the rgb_shutter configuration boundary."""

from extensions.carla.camera_render import RgbCameraSettings
from units.si import Duration


def main() raises:
    var settings = RgbCameraSettings()
    settings.set_shutter_speed(Duration(1))
