# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a spot light's angle: degrees and
radians would be indistinguishable."""

from core.object3d import NodeId
from lights.light import spot_light
from render.framebuffer import Color


def main() raises:
    var bad = spot_light(Color(255, 255, 255), NodeId(0), angle=0.5)
    print(bad.intensity)
