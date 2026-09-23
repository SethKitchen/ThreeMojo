# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a PLY scalar type."""

from loaders.ply import PLY_BINARY_LITTLE_ENDIAN, decode_ply_scalar


def main() raises:
    var bytes: List[UInt8] = [1, 2, 3, 4]
    print(decode_ply_scalar(bytes, 0, 1, PLY_BINARY_LITTLE_ENDIAN))
