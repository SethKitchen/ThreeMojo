# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A contact mode must be a `ContactMode`, not a bare integer."""

from extensions.geotech.stability import BasePressure
from units.si import Length64, Pressure64


def main():
    _ = BasePressure(0, Length64(0), Length64(1), Pressure64(1), Pressure64(1))
