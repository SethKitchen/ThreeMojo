# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A failure mode must be a `FailureMode`, not a bare integer."""

from extensions.geotech.failure import failure_motion
from extensions.geotech.wall import CantileverWall
from units.si import Length64


def main() raises:
    var w = CantileverWall(
        Length64(4),
        Length64(0.5),
        Length64(0.4),
        Length64(3),
        Length64(0.6),
        Length64(0),
        Length64(0.3),
        Length64(0),
        Length64(0),
    )
    _ = failure_motion(1, w, 0.5, Length64(1))
