# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A furniture kind must be a `FurnitureKind`, not a bare integer."""

from extensions.building.kinds import FurnitureKind


def main():
    var id: FurnitureKind = 0
    _ = id.is_valid()
