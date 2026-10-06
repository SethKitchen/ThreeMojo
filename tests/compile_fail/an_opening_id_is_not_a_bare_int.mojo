# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An opening id must be a `OpeningId`, not a bare integer."""

from extensions.building.ids import OpeningId


def main():
    var id: OpeningId = 0
    _ = id.is_valid()
