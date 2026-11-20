# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A foe state must be a `FoeState`, not a bare integer."""

from extensions.village.foes import FoeState


def main():
    var value: FoeState = 0
    _ = value.is_valid()
