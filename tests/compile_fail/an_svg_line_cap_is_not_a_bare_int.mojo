# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an SVG line cap."""

from loaders.svg_shapes import SVG_JOIN_MITER, SvgStrokeStyle


def main() raises:
    var style = SvgStrokeStyle(1, SVG_JOIN_MITER, 1)
    print(style.width)
