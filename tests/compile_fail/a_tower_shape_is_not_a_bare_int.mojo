# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tower shape must be a `TowerShape`, not a bare integer."""

from extensions.castle.kinds import TowerShape


def main():
    var id: TowerShape = 0
    _ = id.is_valid()
