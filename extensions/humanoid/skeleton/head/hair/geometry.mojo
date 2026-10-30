# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Head hair meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var hair = head_hair(person, SCALP_HAIR, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    HairShape,
    HeadHair,
    head_hair_label,
)
from extensions.humanoid.skeleton.head.hair.styles import GROWN, HairStyle
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from extensions.humanoid.spec import HumanoidSpec

comptime INNER_DEPTH = Float32(0.0004)
"""How far under the skin a hair shell's corner must lie to be on its
inner face, in meters. The inner face lies 0.8 mm under it, on the
template, and the outer face stands off it."""


def head_hair(
    spec: HumanoidSpec,
    part: HeadHair,
    side: BodySide,
    detail: Int = 16,
    workers: Int = 1,
) raises -> BufferGeometry:
    """Return one head hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`. The scalp's hair ignores it.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.
        workers: How many threads mesh it. One by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return head_hair_from_dimensions(
        head_muscle_dimensions(spec), part, side, detail, workers
    )


def head_hair_from_dimensions(
    dimensions: HeadMuscleDimensions,
    part: HeadHair,
    side: BodySide,
    detail: Int = 16,
    workers: Int = 1,
    style: HairStyle = GROWN,
    outer_only: Bool = False,
) raises -> BufferGeometry:
    """Return one hair group's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`. The scalp's hair ignores it.
        detail: Cells along the solid.
        workers: How many threads mesh it. One by default.
        style: How the scalp's hair is cut; `GROWN` by default.
        outer_only: Whether to drop the scalp hair's inner face, which
            lies under the skin and never shows. False by default, for
            a closed solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` or `style` is not valid, if `detail` is
            out of range, or if the field produces no surface.
    """
    var field = HairShape(dimensions, part, side, style)
    var label = head_hair_label(part)
    var mesh = mesh_surface(
        field, field.low, field.high, detail, label, workers
    )
    if outer_only and field.scalp:
        drop_inner_face(mesh, field.skin)
    return mesh^


def drop_inner_face(mut mesh: BufferGeometry, skin: HeadSkinField) raises:
    """Drop the triangles of a hair shell that lie under the skin.

    The scalp's hair is a shell over the skin: its inner face lies
    `INNER_DEPTH` or more inside the skin, under the scalp, and its
    outer face stands off it. A triangle whose three corners all lie
    deeper than `INNER_DEPTH` is on the inner face. A game draws the
    shell over the skin, so the inner face never shows, and dropping it
    leaves the shell's whole triangle budget to the face that shows.

    Args:
        mesh: An indexed hair shell.
        skin: The head's skin the shell was made over.

    Raises:
        Error: If the mesh has no positions or no index.
    """
    ref placed = mesh.attribute_view(String(POSITION))
    var under = List[Bool](capacity=placed.count())
    for v in range(placed.count()):
        under.append(skin.distance(placed.vector3(v)) < -INNER_DEPTH)
    var index = List[Int]()
    for t in range(mesh.triangle_count()):
        var a = mesh.corner_index(t, 0)
        var b = mesh.corner_index(t, 1)
        var c = mesh.corner_index(t, 2)
        if under[a] and under[b] and under[c]:
            continue
        index.append(a)
        index.append(b)
        index.append(c)
    mesh.set_index(index^)
