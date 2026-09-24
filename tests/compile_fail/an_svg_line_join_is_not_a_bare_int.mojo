# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an SVG line join."""

from loaders.svg_shapes import SVG_CAP_BUTT, SvgStrokeStyle


def main() raises:
    var style = SvgStrokeStyle(1, 2, SVG_CAP_BUTT)
    print(style.width)
