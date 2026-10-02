# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clipping unions assign coplanar geometry to only one piece."""

from core.assets import Assets
from core.scene import Scene
from materials.material import BASIC, Material
from math.bounds import Plane
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.target import FLOAT_TARGET, RenderTarget
from renderers.clip import ClipVertex, clip_depth, clip_segment, flipped
from renderers.renderer import Renderer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from tests.test_clipping import _area, _camera, _quad_scene


def _vertex(x: Float32, y: Float32) -> ClipVertex:
    return ClipVertex(
        Vector3(x, y, -1), FloatColor(1, 0, 0, 0.5), Vector3(0, 0, 1), 0, 0
    )


def test_coplanar_triangles_belong_to_the_first_union_piece() raises:
    var boundary = Plane(Vector3(0, 0, 1), 1)
    var planes: List[Plane] = [boundary, boundary, flipped(boundary)]
    var clipped = clip_depth(
        _vertex(-1, -1), _vertex(1, -1), _vertex(0, 1), 0.1, 10, any_of=planes
    )
    assert_equal(len(clipped), 3)
    assert_almost_equal(_area(clipped), Float32(2), atol=1e-6)


def test_coplanar_segments_belong_to_the_first_union_piece() raises:
    var boundary = Plane(Vector3(0, 0, 1), 1)
    var planes: List[Plane] = [boundary, boundary, flipped(boundary)]
    var clipped = clip_segment(
        _vertex(-1, 0), _vertex(1, 0), 0.1, 10, any_of=planes
    )
    assert_equal(len(clipped), 2)
    assert_equal(clipped[0].position.x, Float32(-1))
    assert_equal(clipped[1].position.x, Float32(1))


def test_opposing_half_spaces_preserve_crossing_triangle_area() raises:
    var boundary = Plane(Vector3(1, 0, 0), 0)
    var clipped = clip_depth(
        _vertex(-1, -1),
        _vertex(1, -1),
        _vertex(0, 1),
        0.1,
        10,
        any_of=[boundary, flipped(boundary)],
    )
    assert_almost_equal(_area(clipped), Float32(2), atol=1e-6)
    var line = clip_segment(
        _vertex(-1, 0),
        _vertex(1, 0),
        0.1,
        10,
        any_of=[boundary, flipped(boundary)],
    )
    var length = Float32(0)
    for at in range(0, len(line), 2):
        length += (line[at + 1].position - line[at].position).length()
    assert_almost_equal(length, Float32(2), atol=1e-6)


def test_public_depth_clipping_refuses_nonfinite_planes() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            _ = clip_depth(
                _vertex(-1, -1), _vertex(1, -1), _vertex(0, 1), bad, 10
            )
        with assert_raises(contains="finite"):
            _ = clip_depth(
                _vertex(-1, -1), _vertex(1, -1), _vertex(0, 1), 0.1, bad
            )
        with assert_raises(contains="finite"):
            _ = clip_segment(_vertex(-1, 0), _vertex(1, 0), bad, 10)
        with assert_raises(contains="finite"):
            _ = clip_segment(_vertex(-1, 0), _vertex(1, 0), 0.1, bad)
    assert_equal(
        len(clip_depth(_vertex(-1, -1), _vertex(1, -1), _vertex(0, 1), -3, 10)),
        3,
    )


def _translucent(duplicates: Bool) raises -> RenderTarget:
    var assets = Assets()
    var scene = Scene()
    var material = Material(
        Color(255, 0, 0), kind=BASIC, transparent=True, opacity=0.5
    )
    material.depth_write = False
    var boundary = Plane(Vector3(0, 0, 1), 0)
    var planes: List[Plane] = [boundary]
    if duplicates:
        planes.append(boundary)
    material.set_clipping_planes(planes, intersection=True)
    _quad_scene(assets, scene, material)
    var renderer = Renderer(16, 16)
    renderer.background = Color(0, 0, 0)
    renderer.local_clipping_enabled = True
    var target = RenderTarget(16, 16, Color(0, 0, 0), FLOAT_TARGET)
    renderer.render_into(target, scene, assets, _camera())
    return target^


def test_repeated_planes_do_not_blend_a_translucent_surface_twice() raises:
    var once = _translucent(False)
    var repeated = _translucent(True)
    assert_almost_equal(once.color_at(6, 6).r, Float32(0.5), atol=1e-6)
    for at in range(16 * 16):
        assert_almost_equal(repeated.colors[at].r, once.colors[at].r, atol=1e-6)
        assert_almost_equal(repeated.colors[at].a, once.colors[at].a, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
