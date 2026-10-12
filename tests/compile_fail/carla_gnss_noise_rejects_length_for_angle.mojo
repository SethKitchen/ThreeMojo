# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A GNSS latitude deviation is an Angle, not a Length."""

from extensions.carla.gnss import GnssDescription
from units.si import DEGREE, METER, Angle, Length


def settings() raises:
    _ = GnssDescription(
        0,
        Length(1, METER),
        Angle(0, DEGREE),
        Angle(0, DEGREE),
        Angle(0, DEGREE),
        Length(0, METER),
        Length(0, METER),
    )


def main() raises:
    pass
