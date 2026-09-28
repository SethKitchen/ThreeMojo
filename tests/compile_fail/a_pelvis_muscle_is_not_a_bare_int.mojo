# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pelvic muscle must be a `PelvisMuscle`, not a bare integer."""

from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    pelvis_muscle_label,
)


def main() raises:
    print(pelvis_muscle_label(2))
