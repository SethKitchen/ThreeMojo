# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Navigation flags must be `NavFlags`, not a bare integer."""

from extensions.carla.navigation_mesh import NavFlags, NavQueryFilter


def main() raises:
    var filter = NavQueryFilter(2, NavFlags(0))
    print(filter.include.value)
