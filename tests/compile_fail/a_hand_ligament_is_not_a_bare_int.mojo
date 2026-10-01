# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hand ligament must be a `HandLigament`, not a bare integer."""

from extensions.humanoid.skeleton.hand.ligaments.dimensions import (
    hand_ligament_label,
)


def main() raises:
    print(hand_ligament_label(0))
