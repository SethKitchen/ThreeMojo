# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a compressed format."""

from render.compressed_texture import compressed_texture


def main() raises:
    var data = List[UInt8](length=8, fill=0)
    var image = compressed_texture(4, 4, data, 0)
    print(image.width)
