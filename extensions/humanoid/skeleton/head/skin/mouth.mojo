# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The inside of the mouth: the scanned head's teeth, gums and tongue.

The face model holds them with the skin, and its expressions move them:
the jaw opening drops the lower teeth and the tongue with the chin. So a
face that speaks or smiles shows teeth that follow it. They are placed
on the person as the scanned skin is, and rigged with the same shapes.

This is not a three.js port. See Extensions.

    var teeth = mouth_mesh(dims, TEETH, face_rig_shapes())
    var both = mouth_meshes(dims, face_rig_shapes())
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.humanoid.skeleton.head.face_model import (
    GUMS_AND_TONGUE,
    TEETH,
    FaceModel,
    FacePart,
)
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.head.skin.scan import (
    place_each,
    rest_expression,
    scan_model,
)
from math.vector3 import Vector3


def mouth_mesh(
    dimensions: HeadMuscleDimensions,
    part: FacePart,
    shapes: List[String] = List[String](),
) raises -> BufferGeometry:
    """Return the teeth, or the gums and the tongue, of one person.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: `TEETH` or `GUMS_AND_TONGUE`.
        shapes: The expression shapes to rig, by the model's names. Each
            becomes a relative morph target, with its normals. None by
            default.

    Returns:
        A geometry with `position`, `normal` and `uv`, in the pelvis
        frame, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, `part` is not
            the inside of the mouth, the face model cannot be read, or a
            shape is not the model's.
    """
    if part.first != TEETH.first and part.first != GUMS_AND_TONGUE.first:
        raise Error("The inside of the mouth is the teeth or the gums")
    var model = scan_model()
    return _rigged(model, _placed(dimensions, model, shapes), part, shapes)


def mouth_meshes(
    dimensions: HeadMuscleDimensions,
    shapes: List[String] = List[String](),
) raises -> List[BufferGeometry]:
    """Return the teeth, and the gums and the tongue, of one person, as
    `mouth_mesh` returns each.

    The model is placed on the person once for each shape, and both parts
    are cut from the same placements: half the work of two calls to
    `mouth_mesh`.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        shapes: The expression shapes to rig, by the model's names.

    Returns:
        The teeth, then the gums and the tongue.

    Raises:
        Error: If `dimensions.validate` refuses the copy, the face model
            cannot be read, or a shape is not the model's.
    """
    var model = scan_model()
    var placed = _placed(dimensions, model, shapes)
    var out = List[BufferGeometry](capacity=2)
    out.append(_rigged(model, placed, TEETH, shapes))
    out.append(_rigged(model, placed, GUMS_AND_TONGUE, shapes))
    return out^


def _placed(
    dimensions: HeadMuscleDimensions,
    model: FaceModel,
    shapes: List[String],
) raises -> List[List[Vector3]]:
    """Return the model placed on the person at rest, then worn in each
    shape in full."""
    dimensions.validate()
    var weights = List[List[Float32]](capacity=len(shapes) + 1)
    weights.append(rest_expression(model))
    for name in shapes:  # pragma: no branch
        var worn = rest_expression(model)
        worn[model.expression(name)] = 1
        weights.append(worn^)
    # Only the inside of the mouth is placed: the gums, the tongue and the
    # teeth, a quarter of the model. A part reads one point per vertex of
    # the model, so the rest stay at the origin.
    var placed = place_each(
        dimensions.head,
        model,
        TEETH.end,
        weights,
        GUMS_AND_TONGUE.first,
    )
    var total = model.vertex_count()
    for k in range(len(placed)):  # pragma: no branch
        for _ in range(TEETH.end, total):  # pragma: no branch
            placed[k].append(Vector3(0, 0, 0))
    return placed^


def _rigged(
    model: FaceModel,
    placed: List[List[Vector3]],
    part: FacePart,
    shapes: List[String],
) raises -> BufferGeometry:
    """Return one part of the mouth at rest, with a relative morph target
    for each shape: `placed` holds the rest, then each shape."""
    var rest = model.part(placed[0], part)
    if len(shapes) == 0:
        return rest^
    ref still = rest.attribute_view(String(POSITION))
    ref facing = rest.attribute_view(String(NORMAL))
    var total = still.count()
    var targets = List[BufferAttribute]()
    var turns = List[BufferAttribute]()
    for k in range(len(shapes)):  # pragma: no branch
        var worn = model.part(placed[k + 1], part)
        ref moved = worn.attribute_view(String(POSITION))
        ref turned = worn.attribute_view(String(NORMAL))
        var positions = List[Float32](capacity=3 * total)
        var normals = List[Float32](capacity=3 * total)
        # Both meshes come from FaceModel.part: their attributes are
        # packed Float32 triples with identical vertex correspondence.
        for c in range(3 * total):  # pragma: no branch
            positions.append(moved.data[c] - still.data[c])
            normals.append(turned.data[c] - facing.data[c])
        targets.append(BufferAttribute(positions^, 3))
        turns.append(BufferAttribute(normals^, 3))
    rest.morph_relative = True
    for k in range(len(shapes)):  # pragma: no branch
        rest.add_morph_target(
            targets[k].copy(), turns[k].copy(), name=shapes[k]
        )
    return rest^
