# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A zone shape must be a `ZoneShape`, not a bare integer."""

from extensions.village.boss import Zone, inside
from math.vector3 import Vector3


def main() raises:
    print(
        inside(
            Zone(1, Vector3(0, 0, 0), Vector3(0, 0, 1), 1, 0), Vector3(0, 0, 0)
        )
    )
