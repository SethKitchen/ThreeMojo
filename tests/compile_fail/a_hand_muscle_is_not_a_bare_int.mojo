# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hand muscle must be a `HandMuscle`, not a bare integer."""

from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    hand_muscle_label,
)


def main() raises:
    print(hand_muscle_label(3))
