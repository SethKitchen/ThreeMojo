# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a raw mismatch at the gnss_angle configuration boundary."""

from extensions.carla.gnss import GnssDescription
from units.si import Angle


def main() raises:
    var settings = GnssDescription()
    settings.set_latitude_noise(Float32(0), Angle(0))
