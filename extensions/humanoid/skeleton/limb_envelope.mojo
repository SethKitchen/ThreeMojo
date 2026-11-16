# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared surface-nets envelope and dermal-shell mass helpers for limbs.

Limb packages (`arm`, `hand` and siblings) construct a `DistanceField` with
bounding corners `low` and `high`. Centralizing surface extraction, dermal
point classification and volumetric mass sampling here removes repeated
per-limb skin wrapper boilerplate while preserving bit-identical geometry and
mass outputs.
"""

from core.buffer_geometry import BufferGeometry
from extensions.anatomy.soft_tissue import SoftMass, SoftTissue
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftOccupancy,
    classify_soft,
    sample_soft_mass,
)
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from math.vector3 import Vector3
from units.si import Length


def mesh_limb_envelope[
    F: DistanceField
](
    field: F,
    low: Vector3,
    high: Vector3,
    detail: Int,
    label: String,
) raises -> BufferGeometry:
    """Extract a surface-nets skin envelope mesh from a bounded distance field.

    Parameters:
        F: The limb skin distance-field type.

    Args:
        field: Signed distance field of the limb envelope.
        low: Lower corner of the sampling bounds, in meters.
        high: Upper corner of the sampling bounds, in meters.
        detail: Coarse cells along the long axis.
        label: Diagnostic label when the field yields no surface.

    Returns:
        A `BufferGeometry` with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `detail` is out of range or no surface is produced.
    """
    return mesh_surface(field, low, high, detail, label)


def classify_limb_dermal[
    F: DistanceField
](field: F, point: Vector3) -> SoftOccupancy:
    """Classify whether `point` lies inside a limb's dermal shell field.

    Parameters:
        F: The dermal shell distance-field type.

    Args:
        field: Signed distance field of the dermal shell.
        point: Point in the pelvis frame, in meters.

    Returns:
        `SOFT_FILL` inside the dermis and `SOFT_EMPTY` elsewhere.
    """
    return classify_soft(field.distance(point))


def sample_limb_dermal_mass[
    F: DistanceField
](
    field: F,
    low: Vector3,
    high: Vector3,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
    label: String = "limb skin",
) raises -> SoftMass:
    """Sample wet-tissue volume and mass of a limb's dermal shell on a grid.

    Parameters:
        F: The dermal shell distance-field type.

    Args:
        field: Signed distance field of the dermal shell.
        low: Lower corner of the sampling bounds, in meters.
        high: Upper corner of the sampling bounds, in meters.
        tissue: Hydrated tissue properties.
        step: Grid cell size.
        label: Diagnostic label for validation errors.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `step` or `tissue` fails validation.
    """
    return sample_soft_mass(field, low, high, tissue, step, label)
