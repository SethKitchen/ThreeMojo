# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An instance id must be an `InstanceId`, not a bare integer."""

from extensions.carla.image_convert import encode_instance
from extensions.carla.sensor import ROAD


def main() raises:
    var color = encode_instance(ROAD, 5)
    print(color.g)
