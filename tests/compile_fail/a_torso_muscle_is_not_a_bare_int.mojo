# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torso muscle must be a `TorsoMuscle`, not a bare integer."""

from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    torso_muscle_label,
)


def main() raises:
    print(torso_muscle_label(2))
