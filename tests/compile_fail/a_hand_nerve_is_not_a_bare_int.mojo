# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hand nerve must be a `HandNerve`, not a bare integer."""

from extensions.humanoid.skeleton.hand.nerves.dimensions import hand_nerve_label


def main() raises:
    print(hand_nerve_label(3))
