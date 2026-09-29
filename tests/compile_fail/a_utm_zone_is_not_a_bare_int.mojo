# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A UTM zone must be a `UtmZone`, not a bare integer."""

from extensions.carla.geo import Ellipsoid, UniversalTransverseMercatorParams


def main() raises:
    var p = UniversalTransverseMercatorParams(32, True, Ellipsoid(), None)
    print(p.north)
