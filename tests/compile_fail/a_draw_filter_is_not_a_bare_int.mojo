# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a draw filter."""

from renderers.draw_filter import kept_draws


def main() raises:
    var capable: List[Bool] = [True, False]
    var kept = kept_draws(capable, 1, 0)
    print(len(kept))
