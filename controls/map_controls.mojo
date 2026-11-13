# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera over a map, from three.js `examples/jsm/controls/MapControls.js`.

three.js's `MapControls` is `OrbitControls` with its settings changed:
the primary button pans, the secondary button rotates, and a pan moves
over the ground rather than up the view. One finger pans, and two fingers
dolly and rotate. So here it is a function that makes `OrbitControls`
with those settings, and every member and method is `OrbitControls`'s.
"""

from controls.orbit_controls import (
    DOLLY,
    OrbitControls,
    PAN,
    ROTATE,
    TOUCH_DOLLY_ROTATE,
    TOUCH_PAN,
)
from math.vector3 import Vector3


def MapControls(target: Vector3 = Vector3(0, 0, 0)) -> OrbitControls:
    """Return orbit controls set up as three.js's `MapControls`.

    The primary button pans, the middle button dollies, and the secondary
    button rotates. One finger pans, and two fingers dolly and rotate.
    `screen_space_panning` is False, so a drag up the view moves the target
    forward over the plane at right angles to the camera's up.

    Args:
        target: The point to orbit.

    Returns:
        The controls.
    """
    var controls = OrbitControls(target)
    controls.screen_space_panning = False
    controls.primary_action = PAN
    controls.middle_action = DOLLY
    controls.secondary_action = ROTATE
    controls.touch_one = TOUCH_PAN
    controls.touch_two = TOUCH_DOLLY_ROTATE
    return controls^
