# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a movement speed: it is a
`Velocity`, in meters a second."""

from controls.fly_controls import FlyControls


def main() raises:
    var controls = FlyControls()
    controls.movement_speed = Float32(2.0)
    print(controls.enabled)
