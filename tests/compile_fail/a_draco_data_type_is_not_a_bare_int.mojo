# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco data type."""

from loaders.draco import decode_draco


def main() raises:
    var geometry = decode_draco(List[UInt8]())
    print(len(geometry.integer_values(0, 2)))
