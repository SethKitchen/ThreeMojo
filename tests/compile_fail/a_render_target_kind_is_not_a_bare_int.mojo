# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare int must not stand in for a layered render target's kind: name
it with `TARGET_2D`, `TARGET_3D`, `TARGET_ARRAY` or `TARGET_CUBE`."""

from render.layered_target import LayeredRenderTarget


def main() raises:
    var target = LayeredRenderTarget(1, 2, 2, 3)
    print(target.depth)
