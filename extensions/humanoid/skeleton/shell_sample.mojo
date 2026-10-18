# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cortical-shell classification for a sweep that does not store thickness.

Arm, hand, head and torso bones are `SweepField` solids. Their cortical
thickness is a fraction of stature, not a field member. This module
pairs the sweep with that thickness so the shared bone-mass grid can
classify it.
"""

from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    TRABECULAR_FILL,
    BoneOccupancy,
)
from extensions.humanoid.skeleton.torso.sweep import SweepField
from math.vector3 import Vector3


@fieldwise_init
struct ShelledSweep(Copyable, DistanceField, Movable):
    """A sweep plus the cortical thickness used to classify its interior."""

    var field: SweepField
    var shell: Float32

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the sweep, in meters.

        Args:
            point: The sample point, in meters.

        Returns:
            The sweep's signed distance. Negative is inside.
        """
        return self.field.distance(point)


def fill_at(distance: Float32, shell: Float32) -> BoneOccupancy:
    """Return the fill at a signed distance from a bone's surface.

    Args:
        distance: Signed distance, negative inside, in meters.
        shell: Cortical thickness, in meters.

    Returns:
        `EMPTY`, `CORTICAL_FILL` or `TRABECULAR_FILL`.
    """
    if distance >= 0:
        return EMPTY
    if distance > -shell:
        return CORTICAL_FILL
    return TRABECULAR_FILL


def shelled_sweep_occupancy(
    sample: ShelledSweep, point: Vector3
) -> BoneOccupancy:
    """Return what fills `point` in a sweep wrapped with its shell.

    Args:
        sample: The sweep and its cortical thickness.
        point: A sample point, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` inside it.
    """
    return fill_at(sample.distance(point), sample.shell)
