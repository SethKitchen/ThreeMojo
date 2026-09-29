# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A head ligament must be a `HeadLigament`, not a bare integer."""

from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    head_ligament_label,
)


def main() raises:
    print(head_ligament_label(1))
