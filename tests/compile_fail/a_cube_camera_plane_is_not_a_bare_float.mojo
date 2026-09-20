# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a cube camera's clipping plane."""

from cameras.cube_camera import CubeCamera


def main() raises:
    var camera = CubeCamera(0.1, 100.0, 64)
    print(camera.size)
