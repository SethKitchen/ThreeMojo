# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ordering a length against an angle must not compile."""

from units.si import Angle, Length, METER, RADIAN


def main() raises:
    print(Length(1.0, METER) < Angle(1.0, RADIAN))
