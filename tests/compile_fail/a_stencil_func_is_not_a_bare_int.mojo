# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a stencil function."""

from render.raster_state import RasterState


def main():
    var bad = RasterState(stencil_func=2)
    print(bad.stencil_func.value)
