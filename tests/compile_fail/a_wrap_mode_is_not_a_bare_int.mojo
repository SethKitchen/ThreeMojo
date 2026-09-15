# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a wrap mode."""

from render.texture import Texture


def main() raises:
    var pixels = List[UInt8](length=4, fill=255)
    var bad = Texture(1, 1, pixels^, 0)
    print(bad.width)
