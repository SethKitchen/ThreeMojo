# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lens model must be a `CameraModel`, not a bare integer."""

from extensions.carla.cameras import compute_angle


def main() raises:
    print(compute_angle(1, 0.5, List[Float32]()).value)
