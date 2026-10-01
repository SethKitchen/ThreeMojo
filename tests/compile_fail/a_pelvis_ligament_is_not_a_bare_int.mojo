# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pelvic ligament must be a `PelvisLigament`, not a bare integer."""

from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    pelvis_ligament_label,
)


def main() raises:
    print(pelvis_ligament_label(2))
