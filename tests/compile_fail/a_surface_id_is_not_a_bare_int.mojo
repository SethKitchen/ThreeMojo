# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface id must be a `SurfaceId`, not a bare integer."""

from extensions.energy.ids import SurfaceId


def main():
    var id: SurfaceId = 0
    _ = id.is_valid()
