# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an anchor kind: say `CAST_IN` or
`POST_INSTALLED`."""

from extensions.design.anchors import breakout_tension_strength
from units.si import INCH64, Length64, Pressure64


def main() raises:
    var c = Length64(10, INCH64)
    print(breakout_tension_strength(0, c, c, c, c, c, Pressure64(2e7)))
