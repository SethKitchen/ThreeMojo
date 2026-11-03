# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A warp speed must be a `Velocity64`, not a bare fraction of c."""

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.metrics import alcubierre_comoving
from units.si import Duration64, InverseLength64, Length64


def main() raises:
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1), Length64(1))
    _ = alcubierre_comoving(
        grid, grid.center(), 0.5, Length64(2), InverseLength64(1)
    )
