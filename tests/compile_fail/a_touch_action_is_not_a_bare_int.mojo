# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a touch action."""

from controls.orbit_controls import OrbitControls


def main() raises:
    var controls = OrbitControls()
    controls.touch_one = 1
    print(controls.enabled)
