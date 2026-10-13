# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the recorder time-packet boundary."""

from extensions.carla.recorder_packets import time_packet, PACKET_VISUAL_TIME
from extensions.carla.sensor_data import ByteWriter
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Velocity,
    Velocity64,
)


def main() raises:
    var writer = ByteWriter()
    time_packet(writer, PACKET_VISUAL_TIME, Float64(1))
