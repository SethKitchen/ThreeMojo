# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A road option must be a `RoadOption`, not a bare integer."""

from extensions.carla.traffic_manager_shared import TrafficAction


def main() raises:
    var action = TrafficAction(4, None)
    print(action.road_option.value)
