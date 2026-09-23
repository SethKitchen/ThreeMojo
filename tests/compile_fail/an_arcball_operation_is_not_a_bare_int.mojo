# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an arcball operation."""

from controls.arcball_controls import ArcballControls, MOUSE_PRIMARY
from math.vector3 import Vector3


def main() raises:
    var controls = ArcballControls(Vector3(0, 0, 0))
    print(controls.set_mouse_action(1, MOUSE_PRIMARY))
