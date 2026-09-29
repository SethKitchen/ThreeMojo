# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A recorder packet id must be a `RecorderPacketId`, not a bare integer."""

from extensions.carla.recorder_packets import PACKET_EVENT_DEL, write_packet
from extensions.carla.sensor_data import ByteWriter


def main() raises:
    var w = ByteWriter()
    write_packet(w, 3, List[UInt8]())
