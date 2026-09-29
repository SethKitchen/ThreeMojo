# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene light's group must be a `SceneLightGroup`, not a bare integer."""

from extensions.carla.recorder_packets import (
    LIGHT_GROUP_STREET,
    RecordedLightScene,
    SceneLightId,
)
from math.vector4 import Vector4


def main():
    _ = RecordedLightScene(SceneLightId(5), 1, Vector4(1, 1, 1, 1), True, 2)
