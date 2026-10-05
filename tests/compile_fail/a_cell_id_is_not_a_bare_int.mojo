# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cell id must be a `CellId`, not a bare integer."""

from extensions.topology.ids import CellId


def main():
    var id: CellId = 0
    _ = id.is_valid()
