# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a precision mismatch at the gnss_angle configuration boundary."""

from extensions.carla.gnss import GnssDescription
from units.si import Angle, Angle64


def main() raises:
    var settings = GnssDescription()
    settings.set_latitude_noise(Angle64(0), Angle(0))
