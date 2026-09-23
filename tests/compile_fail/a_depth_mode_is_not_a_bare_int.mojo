# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a depth mode."""

from renderers.renderer import Renderer


def main() raises:
    var renderer = Renderer(4, 4)
    renderer.set_depth_mode(2)
    print(renderer.depth_mode.value)
