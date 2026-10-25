# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A game renderer's shadow mode must be a `ShadowMode`, not a bare integer."""

from renderers.game_renderer import GameRenderer


def main() raises:
    var renderer = GameRenderer(64, 64, 1.0)
    renderer.shadows = 2
    print(renderer.width)
