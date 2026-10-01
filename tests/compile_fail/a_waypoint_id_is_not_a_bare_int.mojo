# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A place's id must be a `WaypointId`, not a bare integer."""

from extensions.carla.traffic_manager_state import TrackTraffic


def main() raises:
    var track = TrackTraffic()
    print(len(track.get_passing_vehicles(1)))
