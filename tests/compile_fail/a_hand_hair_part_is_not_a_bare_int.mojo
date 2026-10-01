# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hand hair group must be a `HandHair`, not a bare integer."""

from extensions.humanoid.skeleton.hand.hair.dimensions import hand_hair_label


def main() raises:
    print(hand_hair_label(1))
