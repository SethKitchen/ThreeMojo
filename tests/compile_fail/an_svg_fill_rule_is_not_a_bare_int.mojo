# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an SVG fill rule."""

from loaders.svg_path import SvgShapePath
from loaders.svg_shapes import create_shapes_with_rule


def main() raises:
    var shapes = create_shapes_with_rule(SvgShapePath(), 1)
    print(len(shapes))
