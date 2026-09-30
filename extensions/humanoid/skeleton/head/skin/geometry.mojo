# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The neck's and the head's skin mesh from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var skin = head_skin_mesh(person)

The solid lives in `dimensions`. Its zero set is extracted with
narrow-band surface nets, and the scanned head's own mesh draws the skin
above the seam on the neck, on the same surface; see `scan_skin_mesh`.
The extracted triangles the scan draws are left out.
"""

from core.buffer_geometry import BufferGeometry, POSITION
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.head.skin.scan import (
    NECK_SEAM,
    ScannedHead,
    scan_model,
    scan_skin_mesh,
)
from extensions.humanoid.skeleton.head.skin.tint import tint_head_skin
from extensions.humanoid.skeleton.isosurface import check_detail
from extensions.humanoid.skeleton.surface_nets import (
    mesh_surface,
    share_height,
)
from geometries.utils import merge_geometries
from math.vector3 import Vector3
from extensions.humanoid.spec import HumanoidSpec


def head_skin_mesh(
    spec: HumanoidSpec, detail: Int = 32, workers: Int = 1
) raises -> BufferGeometry:
    """Return the neck's and the head's skin envelope sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        detail: Cells along the neck's solid, eight through sixty-four,
            32 by default.
        workers: How many threads mesh it. One by default.

    Returns:
        A geometry with `position`, `normal`, `uv` and `color`
        attributes.

    Raises:
        Error: If `spec` is refused, if `detail` is out of range, or if
            the field produces no surface.
    """
    return head_skin_from_dimensions(
        head_muscle_dimensions(spec), detail, workers
    )


# How near the scan a triangle of the modeled solids lies, in template
# cm, when the scan draws the skin there instead.
comptime COVERED = Float32(0.5)


def _leave_covered_out(
    mut geometry: BufferGeometry,
    scan: ScannedHead,
    seam: Float32,
    near: Float32,
) raises:
    """Drop each triangle above `seam` that lies within `near` of the
    scan's skin, where the scan's own mesh draws it."""
    ref positions = geometry.attribute_view(String(POSITION))
    var kept = List[Int]()
    for t in range(0, len(geometry.index), 3):  # pragma: no branch
        var a = geometry.index[t]
        var b = geometry.index[t + 1]
        var c = geometry.index[t + 2]
        var middle = (
            positions.vector3(a) + positions.vector3(b) + positions.vector3(c)
        ) / 3
        if _drawn_by_scan(scan, middle, seam, near):
            continue
        kept.append(a)
        kept.append(b)
        kept.append(c)
    geometry.set_index(kept^)


def _drawn_by_scan(
    scan: ScannedHead, point: Vector3, seam: Float32, near: Float32
) -> Bool:
    """Return True if the scan's mesh draws the skin at `point`."""
    if point.y < seam:
        return False
    return abs(scan.mesh.distance(point)) <= near


def head_skin_from_dimensions(
    dimensions: HeadMuscleDimensions, detail: Int = 32, workers: Int = 1
) raises -> BufferGeometry:
    """Return the neck's and the head's skin mesh for already-computed
    dimensions.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        detail: Cells along the solid.
        workers: How many threads mesh it. One by default.

    Returns:
        A geometry with `position`, `normal`, `uv` and `color`
        attributes. The colors are the face's zones; see
        `tint_head_skin`.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `detail` is
            out of range, or if the field produces no surface.
    """
    check_detail(detail, "head skin")
    var field = HeadSkinField(dimensions)
    var h = dimensions.head.copy()
    var seam = h.at(0, NECK_SEAM, 0).y
    var lap = h.cm(0.6)
    # The modeled solids are meshed whole, and their triangles the scan
    # already draws are left out: all above the seam but the tops of the
    # shoulders' slopes, which stand off the scan.
    var parts = List[BufferGeometry]()
    var solids = mesh_surface(
        field, field.low, field.high, detail, "head skin", workers
    )
    _leave_covered_out(solids, field.scan, seam + lap, h.cm(COVERED))
    parts.append(solids^)
    parts.append(
        scan_skin_mesh(
            field,
            field.scan,
            scan_model(),
            seam - lap,
            field.low,
            field.high,
            field.epsilon,
        )
    )
    var skin = merge_geometries(parts)
    share_height(skin, field.low.y, field.high.y - field.low.y)
    tint_head_skin(skin, dimensions)
    return skin^
