# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane invasion event time must not be a length."""

from extensions.carla.lane_invasion import LaneInvasionEvent
from extensions.carla.road_info import LaneMarking
from extensions.carla.transform import CarlaTransform
from units.si import Length64


def event(pose: CarlaTransform) raises:
    _ = LaneInvasionEvent(1, Length64(1.0), pose, List[LaneMarking]())


def main() raises:
    pass
