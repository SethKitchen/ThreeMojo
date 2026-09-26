# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an SVG quality."""

from renderers.svg_renderer import SVGRenderer


def main() raises:
    var renderer = SVGRenderer(4, 2)
    renderer.set_quality(0)
