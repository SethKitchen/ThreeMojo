# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for an eye separation."""

from cameras.stereo_camera import StereoCamera


def main() raises:
    var stereo = StereoCamera(eye_separation=0.064)
    print(stereo.aspect)
