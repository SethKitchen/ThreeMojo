# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for an angular acceleration."""

from controls.arcball_controls import ArcballControls
from math.vector3 import Vector3


def main() raises:
    var controls = ArcballControls(Vector3(0, 0, 0))
    controls.damping_factor = 25.0
    print(controls.enabled)
