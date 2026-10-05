# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an ASTC profile."""

from render.uastc_hdr import astc_image


def main() raises:
    var pixels = astc_image(1, 1, List[UInt8](length=16, fill=0), 4, 0)
    print(len(pixels))
