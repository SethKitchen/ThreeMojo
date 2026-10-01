# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node of the traffic manager's map must be a `SimpleWaypointIndex`,
not a bare integer."""

from extensions.carla.traffic_manager_map import InMemoryMap


def main() raises:
    var map = InMemoryMap()
    print(map.at(0).location().x)
