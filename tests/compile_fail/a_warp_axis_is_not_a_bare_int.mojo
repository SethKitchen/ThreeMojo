# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A warp grid axis must be an `Axis`, not a bare integer."""

from extensions.warp.derivatives import derivative
from extensions.warp.grid import SpacetimeGrid
from units.si import Duration64, Length64


def main() raises:
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1), Length64(1))
    var field = List[Float64](length=grid.points(), fill=0.0)
    _ = derivative(field, grid, 1)
