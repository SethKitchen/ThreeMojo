# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tensor frame must be a `Frame`, not a bare integer."""

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import COVARIANT
from extensions.warp.tensor import TensorField
from units.si import Duration64, Length64


def main() raises:
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1), Length64(1))
    _ = TensorField(grid, COVARIANT, 1)
