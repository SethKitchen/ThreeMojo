# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare int must not stand in for a render target's type: name it with
`UNSIGNED_BYTE_TARGET`, `HALF_FLOAT_TARGET` or `FLOAT_TARGET`."""

from render.framebuffer import Color
from render.target import RenderTarget


def main() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0), 2)
    print(target.count())
