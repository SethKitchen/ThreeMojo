# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent renderer-boundary controls for opt-in strand coverage."""

from cameras.orthographic_camera import centered
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import (
    BLEND,
    FRONT_SIDE,
    LineWidth,
    OPAQUE,
    line_material,
)
from math.matrix4 import Matrix4
from math.bounds import Plane
from math.vector3 import Vector3
from objects.line_segments2 import (
    LineCoverage,
    LineSegments2,
    SOLID_LINE_COVERAGE,
    STRAND_LINE_COVERAGE,
    line_segments_geometry,
)
from core.morph import MorphInfluences
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer, _Draw, _Slim, _emit_wide_line
from std.math import nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER


def test_low_level_emitter_refuses_invalid_coverage_before_emitting() raises:
    var assets = Assets()
    var material = assets.materials.add(line_material())
    var draw = _Draw(
        GeometryId(0),
        material,
        Matrix4(),
        MorphInfluences(),
        -1,
        0,
        False,
        -1,
        False,
        0,
        FloatColor(1, 1, 1, 1),
        0,
        -1,
        0,
        -1,
        NodeId(0),
        FRONT_SIDE,
    )
    var corners = _Slim()
    with assert_raises(contains="named coverage"):
        _emit_wide_line(
            corners,
            assets,
            draw,
            Matrix4(),
            Matrix4(),
            0.1,
            10,
            List[Plane](),
            List[Plane](),
            1,
            LineCoverage(-1),
            False,
        )
    assert_equal(len(corners), 0)
    assert_equal(len(corners.surfaces), 0)


def test_renderer_refuses_each_invalid_strand_material_state() raises:
    # Each case changes just one public material field. The unrelated
    # fields remain valid, so every refusal has an independent cause.
    for change in range(7):
        var scene = Scene()
        var assets = Assets()
        var node = scene.add(Object3D())
        var geometry = assets.geometries.add(
            line_segments_geometry([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)])
        )
        var paint = line_material(
            Color(255, 0, 0), LineWidth(pixels=3), opacity=0.65, blending=OPAQUE
        )
        if change == 0:
            paint.opacity = nan[DType.float32]()
        elif change == 1:
            paint.opacity = -0.1
        elif change == 2:
            paint.opacity = 1.1
        elif change == 3:
            paint.blending = BLEND
        elif change == 4:
            paint.depth_write = False
        elif change == 5:
            paint.depth_test = False
        else:
            paint.dash_size = Length(0.2, METER)
            paint.gap_size = Length(0.1, METER)
        var material = assets.materials.add(paint)
        scene.add_wide_line(
            LineSegments2(
                geometry, material, node, coverage=STRAND_LINE_COVERAGE
            )
        )
        scene.update()
        var camera = centered(
            Length(2, METER), 1, Length(0.1, METER), Length(10, METER)
        )
        camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
        var renderer = Renderer(16, 16, workers=1)
        var reason = String("opacity") if change < 3 else String(
            "solid depth-tested"
        )
        with assert_raises(contains=reason):
            _ = renderer.render(scene, assets, camera)


def test_valid_solid_and_strand_modes_emit_visible_red_samples() raises:
    for coverage in [SOLID_LINE_COVERAGE, STRAND_LINE_COVERAGE]:
        var scene = Scene()
        var assets = Assets()
        var node = scene.add(Object3D())
        var geometry = assets.geometries.add(
            line_segments_geometry([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)])
        )
        var material = assets.materials.add(
            line_material(
                Color(255, 0, 0),
                LineWidth(pixels=3),
                opacity=1,
                blending=OPAQUE,
            )
        )
        scene.add_wide_line(
            LineSegments2(geometry, material, node, coverage=coverage)
        )
        scene.update()
        var camera = centered(
            Length(2, METER), 1, Length(0.1, METER), Length(10, METER)
        )
        camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
        var renderer = Renderer(16, 16, workers=1)
        renderer.set_background(Color(0, 0, 0))
        var image = renderer.render(scene, assets, camera)
        var count = 0
        for y in range(16):
            for x in range(16):
                var pixel = image.get_pixel(x, y)
                assert_equal(pixel.g, 0)
                assert_equal(pixel.b, 0)
                count += Int(pixel.r > 0)
        assert_true(count > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
