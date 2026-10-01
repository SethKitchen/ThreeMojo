# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for facial expressions and the mouth's shapes in speech."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.object3d import NodeId
from extensions.humanoid.skeleton.head.expression import (
    AA,
    FEAR,
    NEUTRAL,
    OU,
    PP,
    SILENT,
    SMILE,
    SURPRISE,
    FaceWeights,
    FacialExpression,
    Viseme,
    expression_recipe,
    face_rig_shapes,
    facial_expression_label,
    named_facial_expressions,
    named_visemes,
    viseme_label,
    viseme_recipe,
)
from materials.material import MaterialId
from objects.mesh import Mesh, morph_target_index
from core.geometry_store import GeometryId
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _rigged(shapes: List[String]) raises -> Mesh:
    """Return a mesh of one triangle with an empty target per shape."""
    var geometry = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    var facing: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    geometry.set_attribute(String(NORMAL), BufferAttribute(facing^, 3))
    geometry.morph_relative = True
    for name in shapes:  # pragma: no branch
        geometry.add_morph_target(
            BufferAttribute(List[Float32](length=9, fill=0), 3), name=name
        )
    var mesh = Mesh(GeometryId(0), MaterialId(0), NodeId(0))
    mesh.update_morph_targets(geometry)
    return mesh^


def test_expressions_and_visemes_are_named() raises:
    assert_equal(len(named_facial_expressions()), 8)
    assert_equal(len(named_visemes()), 15)
    assert_equal(facial_expression_label(SMILE), "smile")
    assert_equal(
        facial_expression_label(FacialExpression(8)), "facial expression"
    )
    assert_equal(viseme_label(AA), "aa")
    assert_equal(viseme_label(Viseme(-1)), "viseme")
    assert_false(FacialExpression(-1).is_valid())
    assert_false(Viseme(15).is_valid())
    with assert_raises(contains="named expression"):
        _ = expression_recipe(FacialExpression(9))
    with assert_raises(contains="named viseme"):
        _ = viseme_recipe(Viseme(20))


def test_each_recipe_is_made_of_the_rigs_shapes() raises:
    var shapes = face_rig_shapes()
    assert_true("eyeBlink_L" in shapes and "jawOpen" in shapes)
    # Each shape is named once.
    for k in range(len(shapes)):  # pragma: no branch
        for j in range(k + 1, len(shapes)):  # pragma: no branch
            assert_true(shapes[k] != shapes[j])
    assert_equal(len(expression_recipe(NEUTRAL)), 0)
    assert_equal(len(viseme_recipe(SILENT)), 0)
    for expression in named_facial_expressions():  # pragma: no branch
        for item in expression_recipe(expression):  # pragma: no branch
            assert_true(item.shape in shapes)
            assert_true(item.weight > 0 and item.weight <= 1)
    for viseme in named_visemes():  # pragma: no branch
        for item in viseme_recipe(viseme):  # pragma: no branch
            assert_true(item.shape in shapes)
    # Every expression but neutral and every viseme but silence moves
    # the face.
    for expression in named_facial_expressions()[1:]:  # pragma: no branch
        assert_true(len(expression_recipe(expression)) > 0)
    for viseme in named_visemes()[1:]:  # pragma: no branch
        assert_true(len(viseme_recipe(viseme)) > 0)


def test_a_face_mixes_and_wears_its_weights() raises:
    var face = FaceWeights()
    face.add_expression(SMILE, 0.5)
    assert_true(abs(face.get("mouthSmile_L") - 0.425) < 1e-6)
    face.add_viseme(AA)
    assert_true(face.get("jawOpen") > 0.5)
    # A surprise and an open vowel add past one; the mesh wears one.
    face.add_expression(SURPRISE, 2)
    face.blink(0.5)
    assert_equal(face.get("eyeBlink_R"), 0.5)
    assert_equal(face.get("noSuchShape"), 0)
    with assert_raises(contains="noSuchShape"):
        face.add("noSuchShape", 1)
    var mesh = _rigged(face_rig_shapes())
    face.apply(mesh)
    var jaw = morph_target_index(mesh.morph_target_dictionary, "jawOpen")
    assert_equal(mesh.morph_influence(jaw), 1)
    var pucker = morph_target_index(mesh.morph_target_dictionary, "mouthPucker")
    assert_equal(mesh.morph_influence(pucker), 0)
    face.clear()
    face.add_viseme(OU)
    face.add_viseme(PP)
    face.add_expression(FEAR)
    face.apply(mesh)
    assert_equal(mesh.morph_influence(jaw), face.get("jawOpen"))
    assert_true(mesh.morph_influence(pucker) > 0.7)
    # A mesh rigged with fewer shapes cannot wear them all.
    var bare = _rigged(["jawOpen"])
    with assert_raises():
        face.apply(bare)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
