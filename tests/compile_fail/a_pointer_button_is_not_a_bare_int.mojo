# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a pointer button."""

from controls.input import InputEvent, POINTER_DOWN


def main() raises:
    var bad = InputEvent(POINTER_DOWN, button=0)
    print(bad.x)
