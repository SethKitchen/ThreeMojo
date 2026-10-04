# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A space use must be a `SpaceUse`, not a bare integer."""

from extensions.building.kinds import SpaceUse


def main():
    var id: SpaceUse = 0
    _ = id.is_valid()
