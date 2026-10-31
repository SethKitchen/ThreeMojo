# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fight button must be a `FightButton`, not a bare integer."""

from extensions.village.combat import style_move
from extensions.village.styles import SWORD
from extensions.village.combat import FREE


def main() raises:
    print(style_move(SWORD, 0, True, FREE))
