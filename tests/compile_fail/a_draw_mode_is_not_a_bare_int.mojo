# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a draw mode."""

from core.buffer_geometry import BufferGeometry
from geometries.attribute_utils import to_triangles_draw_mode


def main() raises:
    var bad = to_triangles_draw_mode(BufferGeometry(), 1)
    print(bad.is_indexed())
