# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a car's body: say `SEDAN`, `SUV`
or `TAXI`."""

from generators.car import CarSpec


def main() raises:
    var spec = CarSpec(1)
    print(spec.wheel_z)
