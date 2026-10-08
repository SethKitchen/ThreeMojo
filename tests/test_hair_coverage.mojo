# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Image and depth controls for the opt-in hashed strand raster contract."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light, point_light, spot_light
from materials.material import (
    BASIC,
    BLEND,
    DOUBLE_SIDE,
    LineWidth,
    Material,
    MaterialId,
    OPAQUE,
    line_material,
)
from math.vector3 import Vector3
from objects.line_segments2 import (
    LineCoverage,
    LineSegments2,
    SOLID_LINE_COVERAGE,
    STRAND_LINE_COVERAGE,
    line_segments_geometry,
)
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import isfinite, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime SIZE = 64
comptime RED = Color(255, 0, 0)
comptime BLUE = Color(0, 0, 255)
comptime GREEN = Color(0, 255, 0)
comptime BLACK = Color(0, 0, 0)


def _camera() raises -> OrthographicCamera:
    """View a two-meter square from four meters on +z."""
    var camera = centered(
        Length(2, METER), 1, Length(0.1, METER), Length(10, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _line(
    mut scene: Scene,
    mut assets: Assets,
    points: List[Vector3],
    color: Color,
    opacity: Float32 = 0.65,
    width: Float32 = 9,
    coverage: LineCoverage = STRAND_LINE_COVERAGE,
    cast: Bool = True,
) raises -> NodeId:
    """Attach one test strand with independent node and owned resources."""
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(line_segments_geometry(points))
    var material = assets.materials.add(
        line_material(
            color, LineWidth(pixels=width), opacity=opacity, blending=OPAQUE
        )
    )
    scene.add_wide_line(
        LineSegments2(
            geometry, material, node, coverage=coverage, cast_shadow=cast
        )
    )
    return node


def _crossing(
    reverse: Bool, foreground: Bool = False, workers: Int = 1
) raises -> Framebuffer:
    """Draw fixed crossing strands in either object order, with optional occluder.
    """
    var scene = Scene()
    var assets = Assets()
    for order in range(2):
        var strand = 1 - order if reverse else order
        if strand == 0:
            _ = _line(
                scene,
                assets,
                [Vector3(-0.8, -0.7, 0), Vector3(0.8, 0.7, 0)],
                RED,
            )
        else:
            _ = _line(
                scene,
                assets,
                [Vector3(-0.8, 0.7, -0.2), Vector3(0.8, -0.7, -0.2)],
                BLUE,
            )
    if foreground:
        var node = Object3D()
        node.set_position(0, 0, 0.2)
        var id = scene.add(node^)
        var geometry = assets.geometries.add(
            plane(Length(2, METER), Length(2, METER))
        )
        var material = assets.materials.add(
            Material(GREEN, kind=BASIC, side=DOUBLE_SIDE)
        )
        scene.add_mesh(Mesh(geometry, material, id))
    scene.update()
    var renderer = Renderer(SIZE, SIZE, workers=workers)
    renderer.set_background(BLACK)
    return renderer.render(scene, assets, _camera())


def _same(a: Framebuffer, b: Framebuffer) raises:
    """Require exact sample equality, including every silhouette hole."""
    for y in range(SIZE):
        for x in range(SIZE):
            var first = a.get_pixel(x, y)
            var second = b.get_pixel(x, y)
            assert_equal(first.r, second.r)
            assert_equal(first.g, second.g)
            assert_equal(first.b, second.b)
            assert_equal(first.a, second.a)


def test_crossing_strands_are_order_independent_and_repeatable() raises:
    var first = _crossing(False)
    var reversed = _crossing(True)
    var repeated = _crossing(False)
    var workers = _crossing(False, workers=3)
    _same(first, reversed)
    _same(first, repeated)
    _same(first, workers)
    var red = 0
    var blue = 0
    var holes = 0
    for y in range(SIZE):
        for x in range(SIZE):
            var p = first.get_pixel(x, y)
            red += Int(p.r > 128)
            blue += Int(p.b > 128)
            holes += Int(p.r == 0 and p.g == 0 and p.b == 0)
    assert_true(red > 40)
    assert_true(blue > 40)
    assert_true(holes > SIZE * SIZE // 2)


def test_opaque_foreground_occludes_all_strand_samples() raises:
    var image = _crossing(False, foreground=True)
    for y in range(2, SIZE - 2):
        for x in range(2, SIZE - 2):
            var pixel = image.get_pixel(x, y)
            assert_equal(pixel.r, UInt8(0))
            assert_equal(pixel.g, UInt8(255))
            assert_equal(pixel.b, UInt8(0))


def _covered(opacity: Float32, width: Float32) raises -> Int:
    """Count samples from one fixed horizontal strand."""
    var scene = Scene()
    var assets = Assets()
    _ = _line(
        scene,
        assets,
        [Vector3(-0.8, 0.013, 0), Vector3(0.8, 0.013, 0)],
        RED,
        opacity,
        width,
    )
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var image = renderer.render(scene, assets, _camera())
    var count = 0
    for y in range(SIZE):
        for x in range(SIZE):
            count += Int(image.get_pixel(x, y).r > 128)
    return count


def test_opacity_and_subpixel_width_control_coverage() raises:
    assert_equal(_covered(0, 9), 0)
    assert_true(_covered(0.5, 9) < _covered(1, 9))
    assert_true(_covered(1, 0.5) > 0)
    assert_true(_covered(1, 0.5) < _covered(1, 2))


def _shadow_samples(
    opacity: Float32, cast: Bool, hidden: Bool, layers: Bool, light_kind: Int
) raises -> Int:
    """Count actual light-map depth samples for directional, spot and point light.
    """
    var scene = Scene()
    var assets = Assets()
    var strand = _line(
        scene,
        assets,
        [Vector3(-0.8, 0, 0), Vector3(0.8, 0, 0)],
        RED,
        opacity,
        cast=cast,
    )
    if hidden or layers:
        var object = scene.get(strand)
        object.visible = not hidden
        if layers:
            object.layers.set(1)
        scene.set(strand, object^)
    var lamp = Object3D()
    lamp.set_position(0, 0, 4)
    var node = scene.add(lamp^)
    var light = directional_light(Color(255, 255, 255), node)
    if light_kind == 1:
        light = spot_light(Color(255, 255, 255), node)
    elif light_kind == 2:
        light = point_light(Color(255, 255, 255), node)
    light.cast_shadow = True
    light.shadow.map_size = SIZE
    light.shadow.set_extent(Length(1, METER))
    light.shadow.near = Length(0.1, METER)
    light.shadow.far = Length(10, METER)
    scene.add_light(light)
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    var maps = renderer.shadow_maps(scene, assets, Layers())
    assert_equal(len(maps), 1)
    var samples = 0
    for index in range(len(maps[0].depths)):
        if light_kind == 2:
            samples += Int(maps[0].depths[index] < 1)
        else:
            samples += Int(isfinite(maps[0].depths[index]))
    return samples


def test_actual_strand_shadows_honor_opacity_cast_visibility_and_layers() raises:
    for kind in range(3):
        var solid = _shadow_samples(1, True, False, False, kind)
        var translucent = _shadow_samples(0.5, True, False, False, kind)
        assert_true(solid > 0)
        assert_true(translucent > 0)
        assert_true(translucent < solid)
        assert_equal(_shadow_samples(0, True, False, False, kind), 0)
        assert_equal(_shadow_samples(1, False, False, False, kind), 0)
        assert_equal(_shadow_samples(1, True, True, False, kind), 0)
        assert_equal(_shadow_samples(1, True, False, True, kind), 0)


def test_coverage_is_typed_and_invalid_mutated_modes_are_refused() raises:
    assert_true(SOLID_LINE_COVERAGE.is_valid())
    assert_true(STRAND_LINE_COVERAGE.is_valid())
    assert_false(LineCoverage(2).is_valid())
    with assert_raises(contains="coverage"):
        _ = LineSegments2(
            GeometryId(0), MaterialId(0), NodeId(0), coverage=LineCoverage(-1)
        )
    var scene = Scene()
    var assets = Assets()
    _ = _line(scene, assets, [Vector3(-0.8, 0, 0), Vector3(0.8, 0, 0)], RED)
    scene.wide_lines[0].coverage = LineCoverage(4)
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    with assert_raises(contains="coverage"):
        _ = renderer.render(scene, assets, _camera())


def _short_strand_energy(width: Float32, length: Float32) raises -> Int:
    """Count red sample energy over a fixed grid of tiny strands.

    Subpixel caps use a radial heuristic, so the reference is bounded,
    repeatable visibility and a width response, not a physical disc area.
    The centers are separated by 3.84 pixels and span multiple pixel phases.
    """
    var scene = Scene()
    var assets = Assets()
    var points = List[Vector3]()
    for row in range(16):
        for column in range(16):
            var x = Float32(-0.9) + Float32(column) * 0.12
            var y = Float32(-0.9) + Float32(row) * 0.12
            points.append(Vector3(x, y, 0))
            points.append(Vector3(x + length, y, 0))
    _ = _line(scene, assets, points, RED, 1, width)
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var image = renderer.render(scene, assets, _camera())
    var energy = 0
    for y in range(SIZE):
        for x in range(SIZE):
            energy += Int(image.get_pixel(x, y).r > 128)
    return energy


def test_short_subpixel_caps_have_bounded_repeatable_sample_energy() raises:
    # A point-like strand and a 0.032-pixel segment exercise both caps
    # without allowing the long ribbon to hide their behavior.
    for length in [Float32(0), 0.001]:
        var thin = _short_strand_energy(0.25, length)
        var wide = _short_strand_energy(1, length)
        assert_true(thin > 0)
        assert_true(wide > thin)
        # Each isolated support fits in at most four pixel samples.
        assert_true(wide <= 256 * 4)
        assert_equal(_short_strand_energy(0.25, length), thin)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
