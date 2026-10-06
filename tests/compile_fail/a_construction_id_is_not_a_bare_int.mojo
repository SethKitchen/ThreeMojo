# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A construction id must be a `ConstructionId`, not a bare integer."""

from extensions.building.ids import ConstructionId


def main():
    var id: ConstructionId = 0
    _ = id.is_valid()
