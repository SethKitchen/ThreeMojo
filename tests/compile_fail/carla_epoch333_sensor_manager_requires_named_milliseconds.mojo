# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Require an explicit source-unit adapter for an arbitrary integer epoch."""

from extensions.carla.sensor_manager import SensorManager


def main() raises:
    _ = SensorManager(1234)
