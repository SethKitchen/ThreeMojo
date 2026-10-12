# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a precision mismatch at the gnss_length configuration boundary."""

from extensions.carla.gnss import GnssDescription
from units.si import Length, Length64


def main() raises:
    var settings = GnssDescription()
    settings.set_altitude_noise(Length64(0), Length(0))
