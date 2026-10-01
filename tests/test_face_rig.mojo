# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a head rigged to move its face and its mouth."""

from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import (
    ALL,
    MOUTH,
    SKIN,
)
from extensions.humanoid.skeleton.head.face_model import (
    FACE_AND_HEAD,
    GUMS_AND_TONGUE,
    TEETH,
)
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.skin.geometry import (
    head_skin_from_dimensions,
)
from extensions.humanoid.skeleton.head.skin.mouth import mouth_mesh
from extensions.humanoid.skeleton.head.skin.scan import NECK_SEAM
from extensions.humanoid.spec import HumanoidSpec
from materials.material import MaterialId
from renderers.renderer import available_workers
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def _dims() raises -> HeadMuscleDimensions:
    """Return the six-foot male template's head."""
    return head_muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))


def test_the_skin_moves_with_the_face_and_not_below_it() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var shapes: List[String] = ["jawOpen", "eyeBlink_L"]
    var skin = head_skin_from_dimensions(dims, 16, available_workers(), shapes)
    assert_equal(skin.morph_count(), 2)
    assert_true(skin.morph_relative and skin.has_morph_normals())
    ref positions = skin.attribute_view(String(POSITION))
    # The scan's skin starts a little below the seam, under its lap.
    var seam = h.at(0, NECK_SEAM - 0.6, 0).y
    var drop = Float32(0)
    var low = Float32(0)
    for v in range(positions.count()):  # pragma: no branch
        var d = skin.morph_position(0, v)
        drop = max(drop, -d.y)
        if positions.vector3(v).y < seam:
            low = max(low, d.length())
    # The jaw opening drops the chin by centimeters; the neck below the
    # scan does not move.
    assert_true(drop > h.cm(2.0))
    assert_equal(low, 0)


def test_the_teeth_follow_the_jaw() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var shapes: List[String] = ["jawOpen", "mouthSmile_L"]
    var teeth = mouth_mesh(dims, TEETH, shapes)
    assert_equal(teeth.morph_count(), 2)
    var drop = Float32(0)
    var smile = Float32(0)
    for v in range(teeth.attribute_view(String(POSITION)).count()):
        drop = max(drop, -teeth.morph_position(0, v).y)
        smile = max(smile, teeth.morph_position(1, v).length())
    assert_true(drop > h.cm(2.0))
    # A smile moves the lips, not the teeth.
    assert_equal(smile, 0)
    var gums = mouth_mesh(dims, GUMS_AND_TONGUE)
    assert_equal(gums.morph_count(), 0)
    assert_true(gums.triangle_count() > 0)
    with assert_raises(contains="teeth or the gums"):
        _ = mouth_mesh(dims, FACE_AND_HEAD)
    var unknown: List[String] = ["noSuchShape"]
    with assert_raises():
        _ = mouth_mesh(dims, TEETH, unknown)


def test_a_head_is_drawn_rigged() raises:
    assert_true(ALL.includes_mouth())
    assert_true(not SKIN.includes_mouth())
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var shapes: List[String] = ["jawOpen"]
    _ = add_head(
        scene,
        assets,
        root,
        HumanoidSpec(Length(6.0, FOOT), MALE),
        MaterialId(0),
        MaterialId(0),
        MaterialId(0),
        MaterialId(0),
        SKIN.plus(MOUTH),
        8,
        16,
        workers=available_workers(),
        face_shapes=shapes,
    )
    # The skin, the teeth and the gums, each with a weight per shape.
    assert_equal(len(scene.meshes), 3)
    for m in range(3):  # pragma: no branch
        assert_equal(len(scene.meshes[m].morph_target_dictionary), 1)
        scene.meshes[m].set_morph_influence("jawOpen", 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
