# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A finger must be a `Finger`, not a bare integer."""

from extensions.humanoid.skeleton.hand.bones.dimensions import finger_label


def main() raises:
    print(finger_label(2))
