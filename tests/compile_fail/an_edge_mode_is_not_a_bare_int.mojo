# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An edge mode of a filter must be an `EdgeMode`, not a bare integer."""

from extensions.imaging.ids import require_edge_mode


def main() raises:
    require_edge_mode(1)
