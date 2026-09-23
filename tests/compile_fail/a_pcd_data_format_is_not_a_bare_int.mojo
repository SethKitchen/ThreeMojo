# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a PCD data format."""

from loaders.pcd import PcdHeader


def main() raises:
    var header = PcdHeader()
    header.data = 1
    print("unreachable")
