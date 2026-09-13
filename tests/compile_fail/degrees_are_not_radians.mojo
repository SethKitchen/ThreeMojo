# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A raw float must not stand in for an angle."""

from units.si import Angle, DEGREE


def rotate(angle: Angle):
    print(angle.value)


def main() raises:
    rotate(90.0)
