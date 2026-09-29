# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An agent's road option must be a `RoadOption`, not a bare integer."""

from extensions.carla.agents_misc import OPTION_LANE_FOLLOW


def main() raises:
    var option = OPTION_LANE_FOLLOW
    option = 4
    print(option.value)
