# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a texture format: three.js's
number is `TextureFormat.RGBA`, not 1023."""

from render.texture_utils import TextureDataType, byte_length


def main() raises:
    print(byte_length(4, 4, 1023, TextureDataType.UNSIGNED_BYTE))
