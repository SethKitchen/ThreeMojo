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
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.humanoid.skeleton.head.face_model import (
    GUMS_AND_TONGUE,
    TEETH,
    FacePart,
)
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.head.skin.scan import (
    place,
    rest_expression,
    scan_model,
)


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
    dimensions.validate()
    var h = dimensions.head.copy()
    var model = scan_model()
    var count = model.vertex_count()
    var rest = model.part(place(h, model, count), part)
    if len(shapes) == 0:
        return rest^
    ref still = rest.attribute_view(String(POSITION))
    ref facing = rest.attribute_view(String(NORMAL))
    var total = still.count()
    var targets = List[BufferAttribute]()
    var turns = List[BufferAttribute]()
    for name in shapes:  # pragma: no branch
        var weights = rest_expression(model)
        weights[model.expression(name)] = 1
        var worn = model.part(place(h, model, count, weights), part)
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
