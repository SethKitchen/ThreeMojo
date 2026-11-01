# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a wind exposure: say `EXPOSURE_B`,
`EXPOSURE_C` or `EXPOSURE_D`."""

from extensions.design.wind import exposure_coefficient
from units.si import FOOT64, Length64


def main() raises:
    print(exposure_coefficient(Length64(15, FOOT64), 1))
