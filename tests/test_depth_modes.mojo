# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the logarithmic and the reversed depth buffers: three.js's
`logarithmicDepthBuffer` and `reversedDepthBuffer`, from the arithmetic in
`render.raster_state` through the rasterizer, the renderer and every
reader of a depth."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import BASIC, Material, points_material
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from objects.points import Points
from postprocessing.composer import supersample
from postprocessing.effects import clear_light
from postprocessing.screen_space import DepthView, outline_mask
from render.antialias import downsample
from render.framebuffer import Color, FloatColor, Framebuffer
from render.raster_state import (
    EQUAL_DEPTH,
    GREATER_DEPTH,
    LESS_DEPTH,
    LESS_EQUAL_DEPTH,
    LOGARITHMIC_DEPTH,
    REVERSED_DEPTH,
    STANDARD_DEPTH,
    DepthMode,
    RasterState,
    cleared_depth,
    fragment_depth,
    is_nearer,
    log_depth_factor,
    test_fragment,
    window_depth,
)
from render.rasterizer import (
    RasterVertex,
    rasterize_line,
    rasterize_point,
    rasterize_shaded,
)
from render.rect import Rect
from render.target import RenderTarget
from render.texture import depth_texture_of_buffer
from renderers.renderer import Renderer
from std.math import inf, log2, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16
comptime RED = FloatColor(1.0, 0.0, 0.0, 1.0)
comptime BLUE = FloatColor(0.0, 0.0, 1.0, 1.0)


def _meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def _state(mode: DepthMode, far: Float32 = 100) -> RasterState:
    """Return the default state under a depth mode, with the log factor of
    `far` when the mode is logarithmic."""
    var scale = Float32(0)
    if mode == LOGARITHMIC_DEPTH:
        scale = log_depth_factor(far)
    return RasterState(depth_mode=mode, log_depth_scale=scale)


def _cover(
    z: Float32, inv_w: Float32, color: FloatColor, state: RasterState
) -> List[RasterVertex]:
    """Return one triangle covering an 8x8 target at one depth and one w."""
    var corners = List[RasterVertex]()
    var xs: List[Float32] = [-1, 20, -1]
    var ys: List[Float32] = [-1, -1, 20]
    for index in range(3):
        corners.append(
            RasterVertex(
                xs[index],
                ys[index],
                z,
                inv_w,
                color,
                kind=BASIC,
                state=state,
            )
        )
    return corners^


def _fill(mut target: RenderTarget, corners: List[RasterVertex]) raises:
    """Rasterize one triangle into `target`."""
    rasterize_shaded(corners[0], corners[1], corners[2], target)


# --- the arithmetic ---------------------------------------------------------


def test_the_depth_modes_know_their_values() raises:
    assert_true(STANDARD_DEPTH.is_valid())
    assert_true(LOGARITHMIC_DEPTH.is_valid())
    assert_true(REVERSED_DEPTH.is_valid())
    assert_false(DepthMode(-1).is_valid())
    assert_false(DepthMode(3).is_valid())


def test_the_log_factor_is_three_js_log_depth_buf_fc() raises:
    # `2.0 / ( Math.log( camera.far + 1.0 ) / Math.LN2 )`.
    assert_almost_equal(
        log_depth_factor(100), 2 / log2(Float32(101)), atol=Float64(1e-7)
    )
    assert_almost_equal(log_depth_factor(1), Float32(2), atol=Float64(1e-7))


def test_each_mode_stores_the_depth_three_js_writes() raises:
    # The standard depth is the interpolated NDC depth.
    assert_equal(fragment_depth(_state(STANDARD_DEPTH), 0.25, 0.5), 0.25)
    # The reversed depth is 1 at the near plane and 0 at the far one.
    assert_equal(fragment_depth(_state(REVERSED_DEPTH), -1, 1), 1)
    assert_equal(fragment_depth(_state(REVERSED_DEPTH), 1, 1), 0)
    assert_equal(fragment_depth(_state(REVERSED_DEPTH), 0.5, 1), 0.25)
    # The logarithmic depth reads only w: `log2(1 + w) * fc - 1`, which
    # is 1 at the far plane whatever the NDC depth says.
    var log = _state(LOGARITHMIC_DEPTH, 100)
    assert_almost_equal(
        fragment_depth(log, 0.9, 1.0 / 100.0), 1, atol=Float64(1e-6)
    )
    assert_almost_equal(
        fragment_depth(log, -0.3, 1.0 / 100.0), 1, atol=Float64(1e-6)
    )
    assert_almost_equal(
        fragment_depth(log, 0, 1),
        log_depth_factor(100) - 1,
        atol=Float64(1e-6),
    )
    # And it grows with distance, as a depth must.
    assert_true(fragment_depth(log, 0, 0.5) < fragment_depth(log, 0, 0.25))


def test_each_mode_clears_and_compares_its_own_way() raises:
    assert_equal(cleared_depth(STANDARD_DEPTH), inf[DType.float32]())
    assert_equal(cleared_depth(LOGARITHMIC_DEPTH), inf[DType.float32]())
    assert_equal(cleared_depth(REVERSED_DEPTH), -inf[DType.float32]())
    assert_true(is_nearer(STANDARD_DEPTH, 0.25, 0.5))
    assert_false(is_nearer(STANDARD_DEPTH, 0.5, 0.25))
    assert_true(is_nearer(LOGARITHMIC_DEPTH, 0.25, 0.5))
    assert_true(is_nearer(REVERSED_DEPTH, 0.5, 0.25))
    assert_false(is_nearer(REVERSED_DEPTH, 0.25, 0.5))
    # Every fragment is nearer than the clear.
    for mode in [STANDARD_DEPTH, LOGARITHMIC_DEPTH, REVERSED_DEPTH]:
        assert_true(is_nearer(mode, 0, cleared_depth(mode)))


def test_a_depth_texture_holds_each_mode_from_zero_to_one() raises:
    assert_equal(window_depth(STANDARD_DEPTH, 0), 0.5)
    assert_equal(window_depth(LOGARITHMIC_DEPTH, -1), 0)
    assert_equal(window_depth(REVERSED_DEPTH, 0.75), 0.75)
    # A clear is the far end, and nothing leaves zero to one.
    assert_equal(window_depth(STANDARD_DEPTH, inf[DType.float32]()), 1)
    assert_equal(window_depth(REVERSED_DEPTH, -inf[DType.float32]()), 0)
    assert_equal(window_depth(STANDARD_DEPTH, -3), 0)
    assert_equal(window_depth(REVERSED_DEPTH, 2), 1)


def test_the_reversed_mode_turns_every_comparison_round() raises:
    var reversed = _state(REVERSED_DEPTH)
    # Nearer is larger: `LESS_EQUAL_DEPTH` passes a larger depth.
    assert_true(test_fragment(reversed, 0.8, 0.5, 0).passes)
    assert_false(test_fragment(reversed, 0.2, 0.5, 0).passes)
    assert_true(test_fragment(reversed, 0.5, 0.5, 0).passes)
    var less = RasterState(depth_func=LESS_DEPTH, depth_mode=REVERSED_DEPTH)
    assert_false(test_fragment(less, 0.5, 0.5, 0).passes)
    var greater = RasterState(
        depth_func=GREATER_DEPTH, depth_mode=REVERSED_DEPTH
    )
    assert_true(test_fragment(greater, 0.2, 0.5, 0).passes)
    # Equal stays equal.
    var equal = RasterState(depth_func=EQUAL_DEPTH, depth_mode=REVERSED_DEPTH)
    assert_true(test_fragment(equal, 0.5, 0.5, 0).passes)
    assert_false(test_fragment(equal, 0.4, 0.5, 0).passes)
    # Everything passes against the clear.
    assert_true(
        test_fragment(reversed, 0, cleared_depth(REVERSED_DEPTH), 0).passes
    )
    # And the logarithmic mode compares as the standard one does.
    assert_true(test_fragment(_state(LOGARITHMIC_DEPTH), 0.2, 0.5, 0).passes)


def test_a_state_carries_its_mode_through_the_packed_word() raises:
    var states: List[RasterState] = [
        RasterState(depth_mode=REVERSED_DEPTH),
        RasterState(depth_func=GREATER_DEPTH, depth_mode=LOGARITHMIC_DEPTH),
    ]
    for index in range(len(states)):
        var state = states[index]
        var back = RasterState.unpacked(state.ops_word(), state.stencil_word())
        assert_true(back == state)
        assert_true(state.ops_word() < (1 << 31))


def test_a_state_refuses_a_mode_or_a_factor_no_backend_can_draw() raises:
    var wrong: List[RasterState] = [
        RasterState(depth_mode=DepthMode(3)),
        RasterState(depth_mode=LOGARITHMIC_DEPTH),
        RasterState(depth_mode=LOGARITHMIC_DEPTH, log_depth_scale=-1),
        RasterState(
            depth_mode=LOGARITHMIC_DEPTH, log_depth_scale=nan[DType.float32]()
        ),
        RasterState(
            depth_mode=LOGARITHMIC_DEPTH, log_depth_scale=inf[DType.float32]()
        ),
    ]
    for index in range(len(wrong)):
        assert_false(wrong[index].is_valid())
        with assert_raises(contains="depth mode"):
            wrong[index].check()
    # A factor is read only under the logarithmic mode.
    assert_true(RasterState(depth_mode=REVERSED_DEPTH).is_valid())
    assert_true(_state(LOGARITHMIC_DEPTH).is_valid())


# --- the target and the textures --------------------------------------------


def test_a_target_clears_in_its_mode_and_records_it() raises:
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    assert_true(target.depth_mode == STANDARD_DEPTH)
    target.clear_inside(Rect.whole(4, 4), Color(0, 0, 0), REVERSED_DEPTH)
    assert_true(target.depth_mode == REVERSED_DEPTH)
    assert_equal(target.depth_at(2, 2), -inf[DType.float32]())
    target.clear_inside(Rect.whole(4, 4), Color(0, 0, 0))
    assert_true(target.depth_mode == STANDARD_DEPTH)
    assert_equal(target.depth_at(2, 2), inf[DType.float32]())
    with assert_raises(contains="depth mode"):
        target.clear_inside(Rect.whole(4, 4), Color(0, 0, 0), DepthMode(5))


def test_a_reversed_target_keeps_the_largest_depth_of_a_block() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    target.clear_inside(Rect.whole(2, 2), Color(0, 0, 0), REVERSED_DEPTH)
    target.depth[0] = 0.25
    target.depth[3] = 0.75
    var small = target.downsampled(2)
    assert_true(small.depth_mode == REVERSED_DEPTH)
    assert_equal(small.depth_at(0, 0), 0.75)
    # A block nothing covered stays cleared.
    var empty = RenderTarget(2, 2, Color(0, 0, 0))
    empty.clear_inside(Rect.whole(2, 2), Color(0, 0, 0), REVERSED_DEPTH)
    assert_equal(empty.downsampled(2).depth_at(0, 0), -inf[DType.float32]())
    # And a framebuffer is downsampled by the mode it is given.
    var depths: List[Float32] = [0.25, 0.5, 0.75, -inf[DType.float32]()]
    var image = Framebuffer(2, 2, List[UInt8](length=16, fill=0), depths^)
    assert_equal(downsample(image, 2, REVERSED_DEPTH).depth_at(0, 0), 0.75)
    assert_equal(downsample(image, 2).depth_at(0, 0), -inf[DType.float32]())


def test_a_reversed_depth_texture_is_white_near_and_black_far() raises:
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    target.clear_inside(Rect.whole(2, 1), Color(0, 0, 0), REVERSED_DEPTH)
    target.depth[0] = 1
    var shown = target.depth_texture()
    assert_equal(shown.texel(0, 0).r, 255)
    assert_equal(shown.texel(1, 0).r, 0)
    # The standard one is black near and white where nothing was drawn.
    var plain = RenderTarget(2, 1, Color(0, 0, 0))
    plain.depth[0] = -1
    var seen = plain.depth_texture()
    assert_equal(seen.texel(0, 0).r, 0)
    assert_equal(seen.texel(1, 0).r, 255)
    var depths: List[Float32] = [0]
    with assert_raises(contains="depth mode"):
        _ = depth_texture_of_buffer(1, 1, depths, mode=DepthMode(9))


# --- the rasterizer -----------------------------------------------------------


def test_a_reversed_triangle_stores_one_minus_its_window_depth() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    target.clear_inside(Rect.whole(8, 8), Color(0, 0, 0), REVERSED_DEPTH)
    var state = _state(REVERSED_DEPTH)
    # The far one first and the near one after, then the far one again:
    # the near one wins whichever way round.
    _fill(target, _cover(0.5, 1, BLUE, state))
    assert_equal(target.depth_at(3, 3), 0.25)
    _fill(target, _cover(-0.5, 1, RED, state))
    assert_equal(target.depth_at(3, 3), 0.75)
    _fill(target, _cover(0.5, 1, BLUE, state))
    assert_equal(target.color_at(3, 3).r, 1)
    assert_equal(target.depth_at(3, 3), 0.75)


def test_a_logarithmic_triangle_stores_the_log_of_its_w() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var state = _state(LOGARITHMIC_DEPTH, 100)
    # Two meters away and four: the NDC depths are told to disagree, and
    # the log depth follows w and not them.
    _fill(target, _cover(-0.9, 0.25, BLUE, state))
    _fill(target, _cover(0.9, 0.5, RED, state))
    assert_equal(target.color_at(3, 3).r, 1)
    assert_almost_equal(
        target.depth_at(3, 3),
        log2(Float32(3)) * log_depth_factor(100) - 1,
        atol=Float64(1e-6),
    )


def test_a_line_and_a_point_store_their_mode_as_a_triangle_does() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    target.clear_inside(Rect.whole(8, 8), Color(0, 0, 0), REVERSED_DEPTH)
    var reversed = _state(REVERSED_DEPTH)
    rasterize_line(
        RasterVertex(0, 3.5, 0.5, 1, RED, kind=BASIC, state=reversed),
        RasterVertex(8, 3.5, 0.5, 1, RED, kind=BASIC, state=reversed),
        target,
    )
    assert_equal(target.depth_at(1, 3), 0.25)
    # A farther line is hidden by the nearer one.
    rasterize_line(
        RasterVertex(0, 3.5, 0.75, 1, BLUE, kind=BASIC, state=reversed),
        RasterVertex(8, 3.5, 0.75, 1, BLUE, kind=BASIC, state=reversed),
        target,
    )
    assert_equal(target.color_at(1, 3).r, 1)
    var log = _state(LOGARITHMIC_DEPTH, 100)
    var logged = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(
        RasterVertex(0, 3.5, 0.5, 0.5, RED, kind=BASIC, state=log),
        RasterVertex(8, 3.5, 0.5, 0.5, RED, kind=BASIC, state=log),
        logged,
    )
    var at_two = log2(Float32(3)) * log_depth_factor(100) - 1
    assert_almost_equal(logged.depth_at(1, 3), at_two, atol=Float64(1e-6))
    rasterize_point(
        RasterVertex(
            4, 4, -0.5, 1, BLUE, kind=BASIC, point_size=2, state=reversed
        ),
        target,
    )
    assert_equal(target.depth_at(4, 4), 0.75)
    rasterize_point(
        RasterVertex(4, 4, 0.5, 0.5, BLUE, kind=BASIC, point_size=2, state=log),
        logged,
    )
    assert_almost_equal(logged.depth_at(4, 4), at_two, atol=Float64(1e-6))


# --- the renderer -------------------------------------------------------------


def _camera() raises -> PerspectiveCamera:
    """Return a camera four meters up the z axis, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, _meters(0.1), _meters(100.0)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _flat_camera() raises -> OrthographicCamera:
    """Return an orthographic camera four meters up the z axis."""
    var camera = OrthographicCamera(
        _meters(-2),
        _meters(2),
        _meters(2),
        _meters(-2),
        _meters(0.1),
        _meters(100),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _node(mut scene: Scene, z: Float32, order: Int = 0) raises -> NodeId:
    """Return a new node at depth `z`, drawn in render order `order`."""
    var node = scene.add(Object3D())
    scene.node(node).set_position(0, 0, z)
    scene.node(node).render_order = order
    return node


def _two_quads(mut assets: Assets) raises -> Scene:
    """Return a green square half a meter toward the camera and a larger
    blue one half a meter behind, the blue one drawn last."""
    var scene = Scene()
    var small = assets.geometries.add(plane(_meters(1.0), _meters(1.0)))
    var large = assets.geometries.add(plane(_meters(2.0), _meters(2.0)))
    scene.add_mesh(
        Mesh(
            small,
            assets.materials.add(Material(Color(0, 255, 0), kind=BASIC)),
            _node(scene, 0.5),
        )
    )
    scene.add_mesh(
        Mesh(
            large,
            assets.materials.add(Material(Color(0, 0, 255), kind=BASIC)),
            _node(scene, -0.5, 1),
        )
    )
    scene.update()
    return scene^


def test_a_renderer_refuses_a_mode_that_is_none_of_the_three() raises:
    var renderer = Renderer(SIZE, SIZE)
    assert_true(renderer.depth_mode == STANDARD_DEPTH)
    with assert_raises(contains="depth mode"):
        renderer.set_depth_mode(DepthMode(3))
    renderer.set_depth_mode(REVERSED_DEPTH)
    assert_true(renderer.depth_mode == REVERSED_DEPTH)


def test_a_logarithmic_depth_needs_a_perspective_camera() raises:
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_depth_mode(LOGARITHMIC_DEPTH)
    assert_true(renderer.depth_mode_for(_camera()) == LOGARITHMIC_DEPTH)
    # three.js's `vIsPerspective == 0.0` keeps `gl_FragCoord.z`.
    assert_true(renderer.depth_mode_for(_flat_camera()) == STANDARD_DEPTH)
    renderer.set_depth_mode(REVERSED_DEPTH)
    assert_true(renderer.depth_mode_for(_flat_camera()) == REVERSED_DEPTH)


def test_every_primitive_of_a_frame_carries_the_mode() raises:
    var assets = Assets()
    var scene = _two_quads(assets)
    var segment = BufferGeometry()
    segment.set_attribute(
        POSITION, BufferAttribute([Float32(-2), 0, 0, 2, 0, 0], 3)
    )
    var far = _node(scene, -0.5)
    scene.add_line(
        Line(
            assets.geometries.add(segment^),
            assets.materials.add(Material(Color(255, 0, 0), kind=BASIC)),
            far,
            mode=SEGMENTS,
        )
    )
    var dot = BufferGeometry()
    dot.set_attribute(POSITION, BufferAttribute([Float32(0.5), 0.5, 0], 3))
    scene.add_points(
        Points(
            assets.geometries.add(dot^),
            assets.materials.add(points_material(Color(255, 0, 0))),
            far,
        )
    )
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_depth_mode(LOGARITHMIC_DEPTH)
    var frame = renderer.prepare_frame(scene, assets, _camera())
    assert_true(len(frame.corners) > 0)
    assert_true(len(frame.segments) > 0)
    assert_true(len(frame.points) > 0)
    var factor = log_depth_factor(100)
    for index in range(len(frame.corners)):
        assert_true(frame.corners[index].state.depth_mode == LOGARITHMIC_DEPTH)
        assert_equal(frame.corners[index].state.log_depth_scale, factor)
    assert_true(frame.segments[0].state.depth_mode == LOGARITHMIC_DEPTH)
    assert_true(frame.points[0].state.depth_mode == LOGARITHMIC_DEPTH)
    # Reversed, with no factor to carry.
    renderer.set_depth_mode(REVERSED_DEPTH)
    var turned = renderer.prepare_frame(scene, assets, _camera())
    assert_true(turned.corners[0].state.depth_mode == REVERSED_DEPTH)
    assert_equal(turned.corners[0].state.log_depth_scale, 0)
    assert_true(turned.segments[0].state.depth_mode == REVERSED_DEPTH)


def _drawn(mode: DepthMode, antialias: Bool = False) raises -> RenderTarget:
    """Return `_two_quads` drawn under a depth mode, not resolved."""
    var assets = Assets()
    var scene = _two_quads(assets)
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    renderer.set_depth_mode(mode)
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    if antialias:
        var big = renderer.supersampled()
        var drawn = RenderTarget(big.width, big.height, Color(0, 0, 0))
        big.render_into(drawn, scene, assets, _camera())
        return drawn.downsampled(2)
    renderer.render_into(target, scene, assets, _camera())
    return target^


def test_every_mode_draws_the_nearer_surface() raises:
    for mode in [STANDARD_DEPTH, LOGARITHMIC_DEPTH, REVERSED_DEPTH]:
        for antialias in [False, True]:
            var target = _drawn(mode, antialias)
            assert_true(target.depth_mode == mode)
            var middle = target.color_at(8, 8)
            assert_true(middle.g > 0.9 and middle.b < 0.1)
            # Off the green square the blue one shows, and nothing is
            # drawn off both.
            assert_true(target.color_at(4, 4).b > 0.9)
    # The reversed depth is 1 near and 0 far, the clear beyond both.
    var reversed = _drawn(REVERSED_DEPTH)
    var near = reversed.depth_at(8, 8)
    var far = reversed.depth_at(4, 4)
    assert_true(near > far and far > 0 and near < 1)
    assert_equal(reversed.depth_at(0, 0), -inf[DType.float32]())
    var standard = _drawn(STANDARD_DEPTH)
    assert_almost_equal(
        near, (1 - standard.depth_at(8, 8)) * 0.5, atol=Float64(1e-6)
    )
    # The logarithmic depth is `log2(1 + w)` scaled: 3.5 meters away.
    var log = _drawn(LOGARITHMIC_DEPTH)
    assert_almost_equal(
        log.depth_at(8, 8),
        log2(Float32(4.5)) * log_depth_factor(100) - 1,
        atol=Float64(1e-4),
    )


def test_the_shadow_maps_keep_the_standard_depth() raises:
    var assets = Assets()
    var scene = _two_quads(assets)
    var lamp = _node(scene, 5)
    var sun = directional_light(Color(255, 255, 255), lamp, 1.0)
    sun.cast_shadow = True
    scene.add_light(sun)
    for index in range(len(scene.meshes)):
        scene.meshes[index].cast_shadow = True
    scene.update()
    var plain = Renderer(SIZE, SIZE).shadow_maps(scene, assets)[0].depths.copy()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_depth_mode(REVERSED_DEPTH)
    var turned = renderer.shadow_maps(scene, assets)[0].depths.copy()
    assert_equal(len(plain), len(turned))
    for index in range(len(plain)):
        assert_equal(plain[index], turned[index])


# --- the readers --------------------------------------------------------------


def _view(target: RenderTarget) raises -> DepthView:
    """Return a target's depth through `_camera`, in its own mode."""
    var camera = _camera()
    return DepthView(
        target.depth,
        target.width,
        target.height,
        camera.projection_matrix(),
        _meters(0.1),
        _meters(100),
        target.depth_mode,
    )


def test_a_depth_view_reads_every_mode_as_the_same_window_depth() raises:
    var plain = _view(_drawn(STANDARD_DEPTH))
    for mode in [LOGARITHMIC_DEPTH, REVERSED_DEPTH]:
        var other = _view(_drawn(mode))
        for slot in range(len(plain.depth)):
            assert_almost_equal(
                other.depth[slot], plain.depth[slot], atol=Float64(1e-4)
            )
    # A pixel nothing covered is the far plane in every mode.
    assert_equal(_view(_drawn(REVERSED_DEPTH)).depth[0], 1)
    with assert_raises(contains="depth mode"):
        var depths: List[Float32] = [0]
        _ = DepthView(
            depths,
            1,
            1,
            _camera().projection_matrix(),
            _meters(0.1),
            _meters(100),
            DepthMode(4),
        )


def test_a_depth_view_reads_a_flat_logarithmic_depth_as_standard() raises:
    # The renderer stores the standard depth under an orthographic camera,
    # and the view reads it that way.
    var depths: List[Float32] = [0.5]
    var flat = _flat_camera().projection_matrix()
    var view = DepthView(
        depths, 1, 1, flat, _meters(0.1), _meters(100), LOGARITHMIC_DEPTH
    )
    assert_equal(view.depth[0], 0.75)


def test_an_outline_reads_a_reversed_depth() raises:
    var clear = cleared_depth(REVERSED_DEPTH)
    var all_depth: List[Float32] = [0.5, 0.75, 0.5]
    var selected: List[Float32] = [clear, 0.5, 0.5]
    var mask = outline_mask(all_depth, selected, REVERSED_DEPTH)
    # Nothing selected, selected and hidden, selected and seen.
    assert_equal(mask[0].r, 1)
    assert_equal(mask[1].g, 1)
    assert_equal(mask[2].g, 0)
    assert_equal(mask[2].r, 0)
    with assert_raises(contains="depth mode"):
        _ = outline_mask(all_depth, selected, DepthMode(3))


def test_a_supersampled_frame_and_a_clear_pass_keep_the_mode() raises:
    var assets = Assets()
    var scene = _two_quads(assets)
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_depth_mode(REVERSED_DEPTH)
    var frame = supersample(renderer, scene, assets, _camera(), 1, False)
    assert_true(frame.depth_mode == REVERSED_DEPTH)
    var reference = _drawn(REVERSED_DEPTH)
    assert_true(frame.depth_at(8, 8) > frame.depth_at(4, 4))
    assert_almost_equal(
        frame.depth_at(8, 8), reference.depth_at(8, 8), atol=Float64(1e-3)
    )
    assert_equal(frame.depth_at(0, 0), -inf[DType.float32]())
    clear_light(frame, Color(0, 0, 0))
    assert_equal(frame.depth_at(8, 8), -inf[DType.float32]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
