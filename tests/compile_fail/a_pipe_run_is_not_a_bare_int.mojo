# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pipe run must be a `PipeRun`, not a bare integer."""

from extensions.geotech.pipes import BuriedPipe
from extensions.geotech.quantities import UnitWeight64
from units.si import Length64


def main():
    _ = BuriedPipe(
        1,
        Length64(1),
        Length64(0),
        Length64(1),
        1,
        Length64(1),
        True,
        UnitWeight64(1),
    )
