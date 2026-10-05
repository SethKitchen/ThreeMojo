# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two absolute temperatures do not add: only a difference adds."""

from units.temperature import CELSIUS, Temperature64


def main():
    var inside = Temperature64(20.0, CELSIUS)
    var outside = Temperature64(-5.0, CELSIUS)
    _ = inside + outside
