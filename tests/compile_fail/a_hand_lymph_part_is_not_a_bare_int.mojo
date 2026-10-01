# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hand lymphatic must be a `HandLymph`, not a bare integer."""

from extensions.humanoid.skeleton.hand.lymph.dimensions import hand_lymph_label


def main() raises:
    print(hand_lymph_label(0))
