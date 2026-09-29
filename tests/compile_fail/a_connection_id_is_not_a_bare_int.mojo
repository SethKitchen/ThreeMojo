# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A connection id must be a `ConId`, not a bare integer."""

from extensions.carla.map import Connection
from extensions.carla.road_info import RoadId


def main() raises:
    var connection = Connection(1, RoadId(1), RoadId(2))
    print(len(connection.lane_links))
