# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bitwise controls for packed face reads against the original array path."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, NORMAL, UV
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import MALE, FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.expression import face_rig_shapes
from extensions.humanoid.skeleton.head.face_model import (
    FaceModel,
    FacePart,
    FACE_MODEL_PATH,
    FACE_AND_HEAD,
    MOUTH_SOCKET,
    EYE_SOCKETS,
    TEETH,
    GUMS_AND_TONGUE,
    LEFT_EYEBALL,
    RIGHT_EYEBALL,
    TEAR_FILM,
    EYE_BLEND,
    EYE_OCCLUSION,
    EYELASHES,
    _in_parts,
    _floats,
    _NEUTRAL,
)
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.skin.mouth import mouth_mesh
from extensions.humanoid.skeleton.head.skin.scan import (
    place,
    rest_expression,
    scan_model,
)
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Length, FOOT


def _reference_part(
    model: FaceModel, points: List[Vector3], part: FacePart
) raises -> BufferGeometry:
    """Return one part of the head as a mesh.

    Args:
        model: The converted model, with the original array readers.
        points: Every vertex, from `shape`, in any frame.
        part: Which part.

    Returns:
        A geometry with `position`, `normal` and `uv`. The normals
        are the mean of the faces round each vertex, weighted by
        their area; vertices on a seam of the texture share theirs.

    Raises:
        Error: If `points` is not one per vertex of the model, the
            part is not a valid run of its vertices, or the part has
            no triangles.
    """
    model._check(part)
    if len(points) != model.vertex_count():
        raise Error("A face part needs one point per model vertex")
    var triangles = model.triangles()
    var position_of = model.position_of()
    var model_uvs = model.uvs()
    var remap = List[Int](length=len(position_of), fill=-1)
    var positions = List[Float32]()
    var uvs = List[Float32]()
    var owners = List[Int]()
    var indices = List[Int]()
    var parts: List[FacePart] = [part]
    for t in range(0, len(triangles), 3):  # pragma: no branch
        if not _in_parts(
            parts,
            position_of[triangles[t]],
            position_of[triangles[t + 1]],
            position_of[triangles[t + 2]],
        ):
            continue
        for c in range(3):  # pragma: no branch
            var d = triangles[t + c]
            if remap[d] < 0:
                remap[d] = len(owners)
                var p = position_of[d]
                owners.append(p)
                positions.append(points[p].x)
                positions.append(points[p].y)
                positions.append(points[p].z)
                uvs.append(model_uvs[d * 2])
                uvs.append(model_uvs[d * 2 + 1])
            indices.append(remap[d])
    if len(indices) == 0:
        raise Error("That face part has no triangles")
    # Smooth normals, summed per position so a seam does not show.
    var sums = List[Vector3](length=model.vertex_count(), fill=Vector3(0, 0, 0))
    for t in range(0, len(indices), 3):  # pragma: no branch
        var a = points[owners[indices[t]]]
        var b = points[owners[indices[t + 1]]]
        var c = points[owners[indices[t + 2]]]
        var e1 = b - a
        var e2 = c - a
        var n = Vector3(
            e1.y * e2.z - e1.z * e2.y,
            e1.z * e2.x - e1.x * e2.z,
            e1.x * e2.y - e1.y * e2.x,
        )
        for c in range(3):  # pragma: no branch
            var p = owners[indices[t + c]]
            sums[p] = sums[p] + n
    var normals = List[Float32]()
    for i in range(len(owners)):  # pragma: no branch
        var n = sums[owners[i]]
        n.normalize()
        normals.append(n.x)
        normals.append(n.y)
        normals.append(n.z)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(indices^)
    return geometry^


def _reference_mouth_mesh(
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
        for v in range(total):  # pragma: no branch
            var d = moved.vector3(v) - still.vector3(v)
            var n = turned.vector3(v) - facing.vector3(v)
            positions.append(d.x)
            positions.append(d.y)
            positions.append(d.z)
            normals.append(n.x)
            normals.append(n.y)
            normals.append(n.z)
        targets.append(BufferAttribute(positions^, 3))
        turns.append(BufferAttribute(normals^, 3))
    rest.morph_relative = True
    for k in range(len(shapes)):  # pragma: no branch
        rest.add_morph_target(
            targets[k].copy(), turns[k].copy(), name=shapes[k]
        )
    return rest^


def _same_values(a: List[Float32], b: List[Float32]) raises:
    """Compare each stored bit, including signed zero."""
    assert_equal(len(a), len(b))
    for i in range(len(a)):
        assert_equal(bitcast[DType.uint32](a[i]), bitcast[DType.uint32](b[i]))


def _same_geometry(a: BufferGeometry, b: BufferGeometry) raises:
    """Compare the complete base and every named morph in order."""
    assert_equal(len(a.index), len(b.index))
    for i in range(len(a.index)):
        assert_equal(a.index[i], b.index[i])
    for name in [String(POSITION), String(NORMAL), String(UV)]:
        ref x = a.attribute_view(name)
        ref y = b.attribute_view(name)
        assert_equal(x.item_size, y.item_size)
        assert_equal(x.is_interleaved(), False)
        assert_equal(x.is_integer(), False)
        assert_equal(x.is_normalized(), False)
        assert_equal(x.item_size, 2 if name == String(UV) else 3)
        _same_values(x.data, y.data)
    assert_equal(a.morph_relative, b.morph_relative)
    assert_equal(a.morph_count(), b.morph_count())
    for k in range(a.morph_count()):
        assert_equal(a.morph_names[k], b.morph_names[k])
        _same_values(a.morph_positions[k].data, b.morph_positions[k].data)
        _same_values(a.morph_normals[k].data, b.morph_normals[k].data)


def test_neutral_points_keep_every_packed_coordinate_bit() raises:
    var model = FaceModel(FACE_MODEL_PATH, 0, False)
    for count in [-1, 0, 10, model.vertex_count(), model.vertex_count() + 1]:
        var n = model.vertex_count()
        if count >= 0:
            n = min(n, count)
        var values = _floats(model.bytes, model.sections[_NEUTRAL], n * 3)
        var points = model.neutral(count)
        assert_equal(len(points), n)
        for v in range(n):
            assert_equal(
                bitcast[DType.uint32](points[v].x),
                bitcast[DType.uint32](values[v * 3]),
            )
            assert_equal(
                bitcast[DType.uint32](points[v].y),
                bitcast[DType.uint32](values[v * 3 + 1]),
            )
            assert_equal(
                bitcast[DType.uint32](points[v].z),
                bitcast[DType.uint32](values[v * 3 + 2]),
            )


def test_parts_keep_topology_uvs_and_area_normal_order() raises:
    var model = FaceModel(FACE_MODEL_PATH)
    var identity = model.no_identity()
    identity[0] = 0.75
    identity[7] = -0.25
    var expression = model.no_expression()
    expression[model.expression("jawOpen")] = 0.6
    var points = model.shape(identity, expression)
    var parts: List[FacePart] = [
        FACE_AND_HEAD,
        MOUTH_SOCKET,
        EYE_SOCKETS,
        TEETH,
        GUMS_AND_TONGUE,
        LEFT_EYEBALL,
        RIGHT_EYEBALL,
        TEAR_FILM,
        EYE_BLEND,
        EYE_OCCLUSION,
        EYELASHES,
        FacePart(TEETH.first, TEETH.end - 4),
    ]
    for part in parts:
        _same_geometry(
            model.part(points, part), _reference_part(model, points, part)
        )
    var bare = FaceModel(FACE_MODEL_PATH, 0, False)
    _same_geometry(
        bare.part(points, TEETH), _reference_part(bare, points, TEETH)
    )
    with assert_raises(contains="run of the model"):
        _ = model.part(List[Vector3](), FacePart(-1, 1))
    with assert_raises(contains="one point per model"):
        _ = model.part(List[Vector3](), TEETH)
    with assert_raises(contains="no triangles"):
        _ = model.part(points, FacePart(TEETH.first, TEETH.first + 1))


def test_template_mouth_keeps_all_named_targets_bitwise() raises:
    var dims = head_muscle_dimensions(HumanoidSpec(Length(6, FOOT), MALE))
    var shapes = face_rig_shapes()
    for part in [TEETH, GUMS_AND_TONGUE]:
        _same_geometry(
            mouth_mesh(dims, part, shapes),
            _reference_mouth_mesh(dims, part, shapes),
        )


def test_shaped_mouth_keeps_all_named_targets_bitwise() raises:
    var dims = head_muscle_dimensions(
        HumanoidSpec(Length(5.4, FOOT), FEMALE, genome=random_genome(19))
    )
    var shapes = face_rig_shapes()
    for part in [TEETH, GUMS_AND_TONGUE]:
        _same_geometry(
            mouth_mesh(dims, part, shapes),
            _reference_mouth_mesh(dims, part, shapes),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
