# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject implicit or wrong-dimensional timestamp input."""

from extensions.carla.world_snapshot import Timestamp
from units.si import Duration, Duration64


def main() raises:
    _ = Timestamp(0, Duration(0), Duration64(0), Duration64(0))
