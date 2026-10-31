# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for fur's shells of strands."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.attire.fur import (
    FUR_COMB,
    FUR_PILE,
    FUR_ROOT,
    FUR_SHELLS,
    FUR_TEXELS,
    FUR_TILE,
    LEAST_FUR_SHELLS,
    fur_shell_count,
    fur_shells,
    outer_face,
    fur_test,
    fur_texture,
    strand_heights,
)
from extensions.humanoid.rig.joints import HIPS, RIGHT_FOREARM
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from render.srgb import LINEAR
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import standing_rig, tube


def test_fewer_shells_stand_over_a_coarse_garment() raises:
    assert_equal(fur_shell_count(1), FUR_SHELLS)
    assert_equal(fur_shell_count(0.5), 2)
    assert_equal(fur_shell_count(0.01), LEAST_FUR_SHELLS)
    # Each shell tests a higher share of the pile, never all or none.
    for k in range(FUR_SHELLS):
        var test = fur_test(k, FUR_SHELLS)
        assert_true(test > 0 and test < 1)
        if k > 0:
            assert_true(test > fur_test(k - 1, FUR_SHELLS))


def test_strands_are_cones_that_thin_as_they_rise() raises:
    var heights = strand_heights()
    assert_equal(len(heights), FUR_TEXELS * FUR_TEXELS)
    # The higher a shell, the fewer texels its strands reach.
    var last = FUR_TEXELS * FUR_TEXELS + 1
    for k in range(FUR_SHELLS):
        var reached = 0
        for h in heights:
            if h >= fur_test(k, FUR_SHELLS):
                reached += 1
        assert_true(reached > 0 and reached < last)
        last = reached
    # Bare skin shows between the strands at the root.
    var bare = 0
    for h in heights:
        if h == 0:
            bare += 1
    assert_true(bare > 0)
    var texture = fur_texture()
    assert_true(texture.color_space == LINEAR)
    assert_almost_equal(texture.repeat.x, 1 / FUR_TILE, atol=1e-3)


def _painted() raises -> BufferGeometry:
    """Return a tube, painted mid gray."""
    var mesh = tube(0, 0, 0.2, 0.2, -0.2, HIPS, 2, 8)
    mesh.set_attribute(
        String(COLOR),
        BufferAttribute(
            List[Float32](length=3 * mesh.vertex_count(), fill=0.5), 3
        ),
    )
    return mesh^


def test_each_shell_stands_out_and_falls_combed() raises:
    var mesh = _painted()
    var shells = fur_shells(mesh, 4)
    assert_equal(len(shells), 4)
    ref base = mesh.attribute_view(String(POSITION))
    ref normals = mesh.attribute_view(String(NORMAL))
    for k in range(4):
        var height = Float32(k + 1) / 4
        ref placed = shells[k].attribute_view(String(POSITION))
        ref colors = shells[k].attribute_view(String(COLOR))
        assert_equal(placed.count(), base.count())
        assert_equal(shells[k].triangle_count(), mesh.triangle_count())
        for v in range(placed.count()):
            var moved = placed.vector3(v) - base.vector3(v)
            # Out along the normal, by its share of the pile.
            assert_almost_equal(
                moved.dot(normals.vector3(v)), FUR_PILE * height, atol=1e-5
            )
            # And down, more the higher it stands.
            assert_almost_equal(
                moved.y, -FUR_COMB * FUR_PILE * height * height, atol=1e-5
            )
        # Darker at the root.
        var shade = FUR_ROOT + (1 - FUR_ROOT) * height
        assert_almost_equal(colors.component(0, 0), 0.5 * shade, atol=1e-6)
    with assert_raises(contains="one shell"):
        _ = fur_shells(mesh, 0)
    with assert_raises():
        _ = fur_shells(tube(0, 0, 0.2, 0.2, -0.2, HIPS, 2, 8), 2)


def test_strands_stand_on_the_outer_face_alone() raises:
    var rig = standing_rig()
    var mesh = _painted()
    # A tube round the hips faces out from them: all of it is kept.
    assert_equal(outer_face(mesh, rig).triangle_count(), mesh.triangle_count())
    # The bone that weighs most is read, though it is the second.
    var second = mesh.clone()
    var bones = List[Float32]()
    var weights = List[Float32]()
    for _ in range(second.vertex_count()):
        bones.append(Float32(RIGHT_FOREARM.value))
        bones.append(Float32(HIPS.value))
        bones.append(0)
        bones.append(0)
        weights.append(0.1)
        weights.append(0.9)
        weights.append(0)
        weights.append(0)
    second.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    second.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    assert_equal(
        outer_face(second, rig).triangle_count(), mesh.triangle_count()
    )
    # Its lining, turned to face in, is dropped.
    var lining = mesh.clone()
    ref normals = mesh.attribute_view(String(NORMAL))
    var turned = List[Float32]()
    for v in range(normals.count()):
        for c in range(3):
            turned.append(-normals.component(v, c))
    lining.set_attribute(String(NORMAL), BufferAttribute(turned^, 3))
    assert_equal(outer_face(lining, rig).triangle_count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
