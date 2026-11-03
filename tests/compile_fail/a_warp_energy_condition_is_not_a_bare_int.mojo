# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An energy condition must be an `EnergyCondition`, not a bare integer."""

from extensions.warp.conditions import energy_condition
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.metrics import minkowski
from extensions.warp.solver import stress_energy
from units.si import Duration64, Length64


def main() raises:
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1), Length64(1))
    var metric = minkowski(grid)
    _ = energy_condition(stress_energy(metric), metric, 0)
