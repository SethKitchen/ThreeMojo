# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a PLY format."""

from loaders.ply import PLY_UINT8, decode_ply_scalar


def main() raises:
    var bytes: List[UInt8] = [1, 2, 3, 4]
    print(decode_ply_scalar(bytes, 0, PLY_UINT8, 1))
