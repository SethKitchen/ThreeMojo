# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A head muscle must be a `HeadMuscle`, not a bare integer."""

from extensions.humanoid.skeleton.head.muscles.dimensions import (
    head_muscle_label,
)


def main() raises:
    print(head_muscle_label(1))
