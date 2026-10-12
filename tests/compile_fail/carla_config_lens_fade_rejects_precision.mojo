# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a precision mismatch at the lens_fade configuration boundary."""

from extensions.carla.cameras import WideAngleLens, EQUIDISTANT
from units.si import Angle, Angle64


def main() raises:
    var lens = WideAngleLens(EQUIDISTANT, List[Float32](), 4, 2, Angle(1))
    lens.set_fov_fade_size(Angle64(0))
