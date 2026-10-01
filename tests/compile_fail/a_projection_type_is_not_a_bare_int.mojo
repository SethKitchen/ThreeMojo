# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A projection type must be a `ProjectionType`, not a bare integer."""

from extensions.carla.geo import GeoProjection


def main() raises:
    var projection = GeoProjection()
    projection.projection_type = 2
    print(projection.proj_string)
