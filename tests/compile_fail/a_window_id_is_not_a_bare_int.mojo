# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A window id must be a `WindowId`, not a bare integer."""

from extensions.energy.ids import WindowId


def main():
    var id: WindowId = 0
    _ = id.is_valid()
