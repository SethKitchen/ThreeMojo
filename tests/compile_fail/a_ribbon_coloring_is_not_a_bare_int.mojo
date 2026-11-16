# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ribbon coloring must be a `RibbonColoring`, not a bare integer."""

from extensions.molecule.ids import require_coloring


def main() raises:
    require_coloring(0)
