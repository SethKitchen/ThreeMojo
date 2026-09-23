# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a key."""

from controls.input import InputEvent, KEY_DOWN


def main() raises:
    var bad = InputEvent(KEY_DOWN, key=113)
    print(bad.x)
