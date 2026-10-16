# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a light's target sits in world space.

The shading pass and the light helpers both read this point.
"""

from core.object3d import NO_PARENT
from core.scene import Scene
from lights.light import Light
from math.vector3 import Vector3


def light_target_position(scene: Scene, light: Light) raises -> Vector3:
    """Return where a light's target is in world space.

    Args:
        scene: The scene the target node is in.
        light: The light.

    Returns:
        The target node's world position, or the origin when the light
        names no target.

    Raises:
        Error: If the target is a node the scene does not have.
    """
    if light.target == NO_PARENT:
        return Vector3(0, 0, 0)
    return scene.world_position(light.target)
