# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a PCD field type."""

from loaders.pcd import decode_pcd_value


def main() raises:
    var bytes: List[UInt8] = [0, 0, 0, 0]
    print(decode_pcd_value(bytes, 0, 2, 4))
