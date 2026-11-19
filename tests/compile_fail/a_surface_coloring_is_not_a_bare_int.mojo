# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface coloring must be a `SurfaceColoring`, not a bare integer."""

from extensions.molecule.ids import require_surface_coloring


def main() raises:
    require_surface_coloring(0)
