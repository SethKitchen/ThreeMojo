# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An errand's state must be an `ErrandState`, not a bare integer."""

from extensions.village.talk import ErrandState, OFFERED


def main() raises:
    var state: ErrandState = 1
    print(state == OFFERED)
