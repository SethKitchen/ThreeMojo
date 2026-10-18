# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One pelvic bone mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = pelvis_bone(person, SACRUM)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import mesh_checked
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    PelvisBone,
    require_pelvis_bone,
    PelvisBoneField,
    PelvisDimensions,
    pelvis_bone_label,
    pelvis_dimensions,
)


def pelvis_bone(
    spec: HumanoidSpec, part: PelvisBone, detail: Int = 16
) raises -> BufferGeometry:
    """Return one pelvic bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to mesh.
        detail: Cells along the bone, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `part` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return pelvis_bone_from_dimensions(
        pelvis_dimensions(spec.stature, spec.sex), part, detail
    )


def pelvis_bone_from_dimensions(
    dimensions: PelvisDimensions, part: PelvisBone, detail: Int = 16
) raises -> BufferGeometry:
    """Return one bone mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `pelvis_dimensions`.
        part: Which bone to mesh.
        detail: Cells along the bone.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `detail` is out of range, or if the field
            produces no surface.
    """
    dimensions.validate()
    require_pelvis_bone(part)
    var label = pelvis_bone_label(part)
    var field = PelvisBoneField(dimensions, part)
    return mesh_checked(field, field.low, field.high, detail, label)
