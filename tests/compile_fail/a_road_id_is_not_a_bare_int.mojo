# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A road id must be a `RoadId`, not a bare integer."""

from extensions.carla.map_builder import MapBuilder


def main() raises:
    var builder = MapBuilder()
    print(builder.road_index(1))
