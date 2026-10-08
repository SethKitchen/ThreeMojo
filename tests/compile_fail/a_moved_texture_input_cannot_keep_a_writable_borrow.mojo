# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Moving a List into texture storage invalidates a lifetime-tracked alias."""

from render.texture import Texture


def main() raises:
    var values = List[UInt8](length=4, fill=128)
    var writable = values.unsafe_ptr()
    var texture = Texture(1, 1, values^)
    writable[unsafe_offset=0] = 9
    print(texture.pixels[0])
