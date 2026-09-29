# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A signal orientation must be a `SignalOrientation`, not a bare integer."""

from extensions.carla.map_builder import default_validities
from extensions.carla.road_info import LaneId


def main() raises:
    print(len(default_validities(0, List[LaneId]())))
