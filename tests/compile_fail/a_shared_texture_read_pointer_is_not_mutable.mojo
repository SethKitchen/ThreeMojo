# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A shared texture's direct read pointer cannot write its channels."""

from render.texture import Texture


def main() raises:
    var texture = Texture(1, 1, List[UInt8](length=4, fill=128))
    var pointer = texture.pixels.unsafe_ptr()
    pointer[unsafe_offset=0] = 9
    print(texture.pixels[0])
