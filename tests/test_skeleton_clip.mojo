# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for cutting a mesh level, along one height."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from extensions.humanoid.skeleton.clip import clip_level
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _ladder() raises -> BufferGeometry:
    """Return two quads stacked from y = 0 to y = 2, facing +z, with a uv
    that runs up them and normals that lean."""
    var flat: List[Float32] = [
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        2,
        0,
        1,
        2,
        0,
    ]
    var uvs: List[Float32] = [0, 0, 1, 0, 0, 0.5, 1, 0.5, 0, 1, 1, 1]
    var normals = List[Float32]()
    for v in range(6):
        normals.append(Float32(0.6) if v % 2 == 0 else Float32(-0.6))
        normals.append(0)
        normals.append(0.8)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    mesh.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    mesh.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    mesh.set_index([0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4])
    return mesh^


def test_a_mesh_is_cut_level() raises:
    var below = clip_level(_ladder(), 1.5, keep_above=False)
    ref placed = below.attribute_view(String(POSITION))
    var highest = Float32(-1)
    for v in range(placed.count()):
        highest = max(highest, placed.vector3(v).y)
    assert_almost_equal(highest, 1.5)
    # The lower quad whole, two triangles, and the lower half of the
    # other in three; three new corners, one shared by two triangles.
    assert_equal(below.triangle_count(), 5)
    assert_equal(below.vertex_count(), 7)
    # The new corners take the attributes between: uv three quarters up.
    ref uv = below.attribute_view(String(UV))
    var found = False
    for v in range(placed.count()):
        if placed.vector3(v).y > 1.49:
            assert_almost_equal(uv.component(v, 1), 0.75)
            found = True
    assert_true(found)
    var above = clip_level(_ladder(), 1.5, keep_above=True)
    assert_equal(above.triangle_count(), 3)
    ref up = above.attribute_view(String(POSITION))
    for v in range(up.count()):
        assert_true(up.vector3(v).y >= 1.5 - 1e-6)


def test_a_new_corner_s_normal_is_unit_length() raises:
    var cut = clip_level(_ladder(), 0.5, keep_above=True)
    ref normals = cut.attribute_view(String(NORMAL))
    for v in range(normals.count()):
        assert_almost_equal(normals.vector3(v).length(), 1, atol=1e-5)
    # A normal that mixes to nothing stays nothing.
    var flat = _ladder()
    var opposed = flat.clone_attribute(String(NORMAL))
    for v in range(6):
        opposed.set_component(v, 2, 0)
    flat.set_attribute(String(NORMAL), opposed^)
    var none = clip_level(flat, 0.5, keep_above=True)
    var zero = False
    ref mixed = none.attribute_view(String(NORMAL))
    for v in range(mixed.count()):
        if mixed.vector3(v).length() < 1e-6:
            zero = True
    assert_true(zero)


def test_nothing_or_everything_is_kept() raises:
    assert_equal(clip_level(_ladder(), 5, keep_above=True).triangle_count(), 0)
    assert_equal(clip_level(_ladder(), 5, keep_above=False).triangle_count(), 4)
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    assert_equal(clip_level(empty, 0, True).vertex_count(), 0)
    # A mesh with no attributes but positions is cut as well.
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    assert_equal(clip_level(bare, 0.5, True).triangle_count(), 1)
    var morphing = _ladder()
    morphing.add_morph_target(morphing.clone_attribute(String(POSITION)))
    with assert_raises(contains="morph targets"):
        _ = clip_level(morphing, 1, True)
    var skinned = _ladder()
    skinned.set_attribute(
        String(SKIN_INDEX), BufferAttribute(List[Float32](length=24, fill=0), 4)
    )
    with assert_raises(contains="bone indices"):
        _ = clip_level(skinned, 1, True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
