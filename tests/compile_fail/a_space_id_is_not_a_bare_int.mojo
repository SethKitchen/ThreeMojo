# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A space id must be a `SpaceId`, not a bare integer."""

from extensions.building.ids import SpaceId


def main():
    var id: SpaceId = 0
    _ = id.is_valid()
