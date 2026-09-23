# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.raster_state`: the depth, color and stencil state a
material names, and what both rasterizers do with it."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import (
    BASIC,
    BLEND,
    OPAQUE,
    Blending,
    Material,
    points_material,
    sprite_material,
)
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color, FloatColor, Framebuffer
from render.raster_state import (
    ALWAYS_DEPTH,
    ALWAYS_STENCIL_FUNC,
    DECREMENT_STENCIL_OP,
    DECREMENT_WRAP_STENCIL_OP,
    DepthFunc,
    EQUAL_DEPTH,
    EQUAL_STENCIL_FUNC,
    FragmentTest,
    GREATER_DEPTH,
    GREATER_EQUAL_DEPTH,
    GREATER_EQUAL_STENCIL_FUNC,
    GREATER_STENCIL_FUNC,
    INCREMENT_STENCIL_OP,
    INCREMENT_WRAP_STENCIL_OP,
    INVERT_STENCIL_OP,
    KEEP_STENCIL_OP,
    LESS_DEPTH,
    LESS_EQUAL_DEPTH,
    LESS_EQUAL_STENCIL_FUNC,
    LESS_STENCIL_FUNC,
    NEVER_DEPTH,
    NEVER_STENCIL_FUNC,
    NOT_EQUAL_DEPTH,
    NOT_EQUAL_STENCIL_FUNC,
    NO_OFFSET,
    PolygonOffset,
    REPLACE_STENCIL_OP,
    RasterState,
    StencilFunc,
    StencilOp,
    ZERO_STENCIL_OP,
    depth_compare,
    resolvable_depth,
    shades,
    stencil_apply,
    stencil_compare,
    test_fragment,
)
from render.rasterizer import (
    RasterVertex,
    SHADE_UV,
    check_line_state,
    check_point_state,
    check_triangle_state,
    rasterize_line,
    rasterize_point,
    rasterize_shaded,
)
from render.rect import Rect
from render.target import RenderTarget
from renderers.renderer import Renderer
from std.math import inf, nan
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


def _mask(reference: Int = 1) -> RasterState:
    """Return a state that writes `reference` wherever it is drawn, and no
    color and no depth."""
    return RasterState(
        depth_write=False,
        color_write=False,
        stencil_write=True,
        stencil_ref=reference,
        stencil_z_pass=REPLACE_STENCIL_OP,
    )


def _inside(reference: Int = 1) -> RasterState:
    """Return a state that draws only where the stencil holds `reference`."""
    return RasterState(
        stencil_write=True,
        stencil_func=EQUAL_STENCIL_FUNC,
        stencil_ref=reference,
    )


def _cover(
    z: Float32,
    color: FloatColor,
    state: RasterState = RasterState(),
    blend: Blending = OPAQUE,
    alpha_test: Float32 = 0,
    right: Float32 = 20,
) -> List[RasterVertex]:
    """Return one triangle covering every pixel left of `right` on an 8x8
    target, at one depth."""
    var corners = List[RasterVertex]()
    var xs: List[Float32] = [-1, right, -1]
    var ys: List[Float32] = [-1, -1, 20]
    for index in range(3):
        corners.append(
            RasterVertex(
                xs[index],
                ys[index],
                z,
                1,
                color,
                blend=blend,
                kind=BASIC,
                alpha_test=alpha_test,
                state=state,
            )
        )
    return corners^


def _fill(
    mut target: RenderTarget, corners: List[RasterVertex], uv: Bool = False
) raises:
    """Rasterize one triangle into `target`."""
    if uv:
        rasterize_shaded(corners[0], corners[1], corners[2], target, SHADE_UV)
    else:
        rasterize_shaded(corners[0], corners[1], corners[2], target)


def _end(
    x: Float32,
    z: Float32,
    color: FloatColor,
    state: RasterState,
    blend: Blending = OPAQUE,
) -> RasterVertex:
    """Return one end of a horizontal line along row 3."""
    return RasterVertex(
        x, 3.5, z, 1, color, blend=blend, kind=BASIC, state=state
    )


def _dot(
    z: Float32,
    color: FloatColor,
    state: RasterState,
    alpha_test: Float32 = 0,
    blend: Blending = OPAQUE,
) -> RasterVertex:
    """Return a four-pixel point at the middle of an 8x8 target."""
    return RasterVertex(
        4,
        4,
        z,
        1,
        color,
        blend=blend,
        kind=BASIC,
        alpha_test=alpha_test,
        point_size=4,
        state=state,
    )


# --- the types and the arithmetic -------------------------------------------


def test_the_types_know_their_values() raises:
    assert_true(NEVER_DEPTH.is_valid())
    assert_true(NOT_EQUAL_DEPTH.is_valid())
    assert_false(DepthFunc(8).is_valid())
    assert_false(DepthFunc(-1).is_valid())
    assert_true(NEVER_STENCIL_FUNC.is_valid())
    assert_true(ALWAYS_STENCIL_FUNC.is_valid())
    assert_false(StencilFunc(8).is_valid())
    assert_false(StencilFunc(-1).is_valid())
    assert_true(ZERO_STENCIL_OP.is_valid())
    assert_true(INVERT_STENCIL_OP.is_valid())
    assert_false(StencilOp(8).is_valid())
    assert_false(StencilOp(-1).is_valid())
    # three.js numbers its depth functions from zero in this order.
    assert_equal(LESS_EQUAL_DEPTH.value, 3)
    assert_equal(NOT_EQUAL_DEPTH.value, 7)


def test_every_depth_function_compares_as_opengl_does() raises:
    var nearer = Float32(0.25)
    var same = Float32(0.5)
    var farther = Float32(0.75)
    var stored = Float32(0.5)
    assert_false(depth_compare(NEVER_DEPTH, nearer, stored))
    assert_true(depth_compare(ALWAYS_DEPTH, farther, stored))
    assert_true(depth_compare(LESS_DEPTH, nearer, stored))
    assert_false(depth_compare(LESS_DEPTH, same, stored))
    assert_true(depth_compare(LESS_EQUAL_DEPTH, same, stored))
    assert_false(depth_compare(LESS_EQUAL_DEPTH, farther, stored))
    assert_true(depth_compare(EQUAL_DEPTH, same, stored))
    assert_false(depth_compare(EQUAL_DEPTH, nearer, stored))
    assert_true(depth_compare(GREATER_EQUAL_DEPTH, same, stored))
    assert_false(depth_compare(GREATER_EQUAL_DEPTH, nearer, stored))
    assert_true(depth_compare(GREATER_DEPTH, farther, stored))
    assert_false(depth_compare(GREATER_DEPTH, same, stored))
    assert_true(depth_compare(NOT_EQUAL_DEPTH, nearer, stored))
    assert_false(depth_compare(NOT_EQUAL_DEPTH, same, stored))


def test_every_stencil_function_compares_the_reference_on_the_left() raises:
    assert_false(stencil_compare(NEVER_STENCIL_FUNC, 1, 1, 255))
    assert_true(stencil_compare(ALWAYS_STENCIL_FUNC, 9, 1, 255))
    assert_true(stencil_compare(LESS_STENCIL_FUNC, 1, 2, 255))
    assert_false(stencil_compare(LESS_STENCIL_FUNC, 2, 2, 255))
    assert_true(stencil_compare(LESS_EQUAL_STENCIL_FUNC, 2, 2, 255))
    assert_false(stencil_compare(LESS_EQUAL_STENCIL_FUNC, 3, 2, 255))
    assert_true(stencil_compare(EQUAL_STENCIL_FUNC, 2, 2, 255))
    assert_false(stencil_compare(EQUAL_STENCIL_FUNC, 1, 2, 255))
    assert_true(stencil_compare(GREATER_STENCIL_FUNC, 3, 2, 255))
    assert_false(stencil_compare(GREATER_STENCIL_FUNC, 2, 2, 255))
    assert_true(stencil_compare(NOT_EQUAL_STENCIL_FUNC, 1, 2, 255))
    assert_false(stencil_compare(NOT_EQUAL_STENCIL_FUNC, 2, 2, 255))
    assert_true(stencil_compare(GREATER_EQUAL_STENCIL_FUNC, 2, 2, 255))
    assert_false(stencil_compare(GREATER_EQUAL_STENCIL_FUNC, 1, 2, 255))
    # Both sides are masked: only the low four bits are compared here.
    assert_true(stencil_compare(EQUAL_STENCIL_FUNC, 0x13, 0x03, 0x0F))
    assert_false(stencil_compare(EQUAL_STENCIL_FUNC, 0x13, 0x03, 0xFF))


def test_every_stencil_operation_changes_the_value_as_opengl_does() raises:
    assert_equal(stencil_apply(ZERO_STENCIL_OP, 7, 3, 255), 0)
    assert_equal(stencil_apply(KEEP_STENCIL_OP, 7, 3, 255), 7)
    assert_equal(stencil_apply(REPLACE_STENCIL_OP, 7, 3, 255), 3)
    assert_equal(stencil_apply(INCREMENT_STENCIL_OP, 7, 3, 255), 8)
    assert_equal(stencil_apply(INCREMENT_STENCIL_OP, 255, 3, 255), 255)
    assert_equal(stencil_apply(DECREMENT_STENCIL_OP, 7, 3, 255), 6)
    assert_equal(stencil_apply(DECREMENT_STENCIL_OP, 0, 3, 255), 0)
    assert_equal(stencil_apply(INCREMENT_WRAP_STENCIL_OP, 255, 3, 255), 0)
    assert_equal(stencil_apply(INCREMENT_WRAP_STENCIL_OP, 7, 3, 255), 8)
    assert_equal(stencil_apply(DECREMENT_WRAP_STENCIL_OP, 0, 3, 255), 255)
    assert_equal(stencil_apply(DECREMENT_WRAP_STENCIL_OP, 7, 3, 255), 6)
    assert_equal(stencil_apply(INVERT_STENCIL_OP, 0x0F, 3, 255), 0xF0)
    # The write mask keeps the bits it does not set.
    assert_equal(stencil_apply(REPLACE_STENCIL_OP, 0x30, 0xFF, 0x0F), 0x3F)
    assert_equal(stencil_apply(ZERO_STENCIL_OP, 0x3C, 0, 0x0F), 0x30)
    assert_equal(stencil_apply(REPLACE_STENCIL_OP, 0x30, 0xFF, 0), 0x30)


def test_a_state_starts_at_three_js_defaults() raises:
    var state = RasterState()
    assert_true(state.depth_test)
    assert_true(state.depth_write)
    assert_true(state.depth_func == LESS_EQUAL_DEPTH)
    assert_true(state.color_write)
    assert_false(state.stencil_write)
    assert_true(state.stencil_func == ALWAYS_STENCIL_FUNC)
    assert_equal(state.stencil_ref, 0)
    assert_equal(state.stencil_func_mask, 255)
    assert_equal(state.stencil_write_mask, 255)
    assert_true(state.stencil_fail == KEEP_STENCIL_OP)
    assert_true(state.stencil_z_fail == KEEP_STENCIL_OP)
    assert_true(state.stencil_z_pass == KEEP_STENCIL_OP)
    assert_true(state.is_valid())
    state.check()


def test_a_state_crosses_two_words_and_back() raises:
    var states: List[RasterState] = [
        RasterState(),
        RasterState(
            False,
            False,
            NOT_EQUAL_DEPTH,
            False,
            True,
            GREATER_EQUAL_STENCIL_FUNC,
            0xA5,
            0x3C,
            0x0F,
            INVERT_STENCIL_OP,
            DECREMENT_WRAP_STENCIL_OP,
            INCREMENT_WRAP_STENCIL_OP,
        ),
        _mask(255),
    ]
    for index in range(len(states)):
        var state = states[index]
        var back = RasterState.unpacked(state.ops_word(), state.stencil_word())
        assert_true(back == state)
        # Both words fit an Int32 lane of the device's state tables.
        assert_true(state.ops_word() < (1 << 31))
        assert_true(state.stencil_word() < (1 << 31))


def test_a_state_refuses_what_no_backend_can_draw() raises:
    var wrong = List[RasterState]()
    wrong.append(RasterState(depth_func=DepthFunc(8)))
    wrong.append(RasterState(stencil_func=StencilFunc(-1)))
    wrong.append(RasterState(stencil_fail=StencilOp(9)))
    wrong.append(RasterState(stencil_z_fail=StencilOp(9)))
    wrong.append(RasterState(stencil_z_pass=StencilOp(9)))
    wrong.append(RasterState(stencil_ref=256))
    wrong.append(RasterState(stencil_ref=-1))
    wrong.append(RasterState(stencil_func_mask=256))
    wrong.append(RasterState(stencil_write_mask=-1))
    for index in range(len(wrong)):
        assert_false(wrong[index].is_valid())
        with assert_raises(contains="stencil"):
            wrong[index].check()


def test_only_an_opaque_fragment_under_both_switches_writes_depth() raises:
    assert_true(RasterState().writes_depth(False))
    assert_false(RasterState().writes_depth(True))
    assert_false(RasterState(depth_write=False).writes_depth(False))
    assert_false(RasterState(depth_test=False).writes_depth(False))


def test_the_stencil_test_runs_before_the_depth_test() raises:
    # No stencil test: the depth alone decides, and the stencil is kept.
    var plain = test_fragment(RasterState(), 0.25, 0.5, 7)
    assert_true(plain.passes)
    assert_equal(plain.stencil, 7)
    assert_false(plain.changes)
    assert_false(test_fragment(RasterState(), 0.75, 0.5, 7).passes)
    var state = RasterState(
        stencil_write=True,
        stencil_func=EQUAL_STENCIL_FUNC,
        stencil_ref=1,
        stencil_fail=ZERO_STENCIL_OP,
        stencil_z_fail=INCREMENT_STENCIL_OP,
        stencil_z_pass=REPLACE_STENCIL_OP,
    )
    # The stencil fails: the fail operation, whatever the depth says.
    var failed = test_fragment(state, 0.25, 0.5, 5)
    assert_false(failed.passes)
    assert_equal(failed.stencil, 0)
    assert_true(failed.changes)
    # The stencil passes and the depth fails: the depth-fail operation.
    var hidden = test_fragment(state, 0.75, 0.5, 1)
    assert_false(hidden.passes)
    assert_equal(hidden.stencil, 2)
    # Both pass: the pass operation, which here leaves what was there.
    var drawn = test_fragment(state, 0.25, 0.5, 1)
    assert_true(drawn.passes)
    assert_equal(drawn.stencil, 1)
    assert_false(drawn.changes)
    # With the depth test off, the depth never fails.
    var untested = state
    untested.depth_test = False
    assert_true(test_fragment(untested, 0.75, 0.5, 1).passes)


def test_a_failing_fragment_is_shaded_only_when_a_discard_could_save_it() raises:
    var passing = FragmentTest(True, 0, False)
    var quiet = FragmentTest(False, 0, False)
    var loud = FragmentTest(False, 1, True)
    assert_true(shades(passing, False))
    assert_false(shades(quiet, True))
    assert_false(shades(loud, False))
    assert_true(shades(loud, True))


def test_a_polygon_offset_follows_the_slope_and_the_resolution() raises:
    # The depth rises by 0.01 a pixel across x and 0.02 down y.
    var a = Vector3(0, 0, 0.5)
    var b = Vector3(10, 0, 0.6)
    var c = Vector3(0, 10, 0.7)
    var slope_only = PolygonOffset(2, 0)
    assert_almost_equal(slope_only.shift(a, b, c), 0.04, atol=1e-6)
    # One unit is the last place of the deepest corner, 0.7: 2^-24.
    var units_only = PolygonOffset(0, 3)
    assert_equal(units_only.shift(a, b, c), Float32(3) * resolvable_depth(0.7))
    assert_equal(resolvable_depth(0.7), Float32(1.0 / 16777216.0))
    assert_equal(resolvable_depth(1.5), Float32(1.0 / 8388608.0))
    # A depth of zero resolves to the smallest normal float.
    assert_true(resolvable_depth(0) > 0)
    # A triangle with no area has no slope.
    var flat = Vector3(5, 5, 0.5)
    assert_equal(PolygonOffset(4, 0).shift(flat, flat, flat), Float32(0))
    # No offset moves nothing, even a sliver's steep slope.
    var sliver = Vector3(10, 1.0e-30, 0.9)
    assert_equal(NO_OFFSET.shift(a, sliver, b), Float32(0))
    assert_true(PolygonOffset(1, -1).is_valid())
    assert_false(PolygonOffset(nan[DType.float32](), 0).is_valid())
    assert_false(PolygonOffset(0, inf[DType.float32]()).is_valid())


# --- the material ------------------------------------------------------------


def test_a_material_carries_three_js_defaults_and_its_own_state() raises:
    var material = Material(Color(255, 255, 255), kind=BASIC)
    assert_true(material.raster_state() == RasterState())
    assert_true(material.depth_offset() == NO_OFFSET)
    assert_false(material.polygon_offset)
    material.depth_func = GREATER_DEPTH
    material.color_write = False
    material.stencil_write = True
    material.stencil_ref = 3
    material.stencil_func = NOT_EQUAL_STENCIL_FUNC
    material.stencil_func_mask = 0x0F
    material.stencil_write_mask = 0xF0
    material.stencil_fail = ZERO_STENCIL_OP
    material.stencil_z_fail = INVERT_STENCIL_OP
    material.stencil_z_pass = INCREMENT_STENCIL_OP
    material.depth_test = False
    material.depth_write = False
    var state = material.raster_state()
    assert_true(
        state
        == RasterState(
            False,
            False,
            GREATER_DEPTH,
            False,
            True,
            NOT_EQUAL_STENCIL_FUNC,
            3,
            0x0F,
            0xF0,
            ZERO_STENCIL_OP,
            INVERT_STENCIL_OP,
            INCREMENT_STENCIL_OP,
        )
    )
    # The offset is read only under `polygon_offset`, as in three.js.
    material.polygon_offset_factor = 1
    material.polygon_offset_units = 2
    assert_true(material.depth_offset() == NO_OFFSET)
    material.polygon_offset = True
    assert_true(material.depth_offset() == PolygonOffset(1, 2))


def test_a_material_refuses_a_state_no_backend_can_draw() raises:
    var ref_high = Material(Color(255, 255, 255), kind=BASIC)
    ref_high.stencil_ref = 256
    with assert_raises(contains="stencil"):
        _ = ref_high.raster_state()
    var no_func = Material(Color(255, 255, 255), kind=BASIC)
    no_func.depth_func = DepthFunc(12)
    with assert_raises(contains="stencil"):
        _ = no_func.raster_state()
    var no_op = Material(Color(255, 255, 255), kind=BASIC)
    no_op.stencil_z_pass = StencilOp(-3)
    with assert_raises(contains="stencil"):
        _ = no_op.raster_state()
    var no_offset = Material(Color(255, 255, 255), kind=BASIC)
    no_offset.polygon_offset = True
    no_offset.polygon_offset_units = nan[DType.float32]()
    with assert_raises(contains="finite"):
        _ = no_offset.depth_offset()


# --- the target --------------------------------------------------------------


def test_a_target_clears_its_stencil_to_zero() raises:
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    assert_equal(target.stencil_at(1, 1), 0)
    var test = target.test_fragment(1, 1, 0.5, _mask(9))
    assert_true(test.passes)
    target.keep_stencil(1, 1, test)
    assert_equal(target.stencil_at(1, 1), 9)
    # A test that changes nothing writes nothing.
    target.keep_stencil(1, 1, FragmentTest(True, 4, False))
    assert_equal(target.stencil_at(1, 1), 9)
    target.clear_inside(Rect.whole(4, 4), Color(0, 0, 0))
    assert_equal(target.stencil_at(1, 1), 0)
    with assert_raises():
        _ = target.stencil_at(4, 0)


def test_a_fragment_outside_the_scissor_fails_and_changes_nothing() raises:
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    target.set_scissor(Rect(0, 0, 2, 4))
    var outside = target.test_fragment(3, 1, 0.5, _mask(9))
    assert_false(outside.passes)
    assert_false(outside.changes)
    assert_true(target.test_fragment(1, 1, 0.5, _mask(9)).passes)


# --- the host rasterizer: triangles -------------------------------------------


def test_a_mask_pass_writes_the_stencil_and_nothing_else() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.5, RED, _mask(), right=6))
    # No color, no depth, and the reference wherever it covered.
    assert_equal(target.color_at(1, 1).r, 0)
    assert_equal(target.depth_at(1, 1), inf[DType.float32]())
    assert_equal(target.stencil_at(1, 1), 1)
    assert_equal(target.stencil_at(7, 7), 0)
    # A second surface drawn only where the mask was.
    _fill(target, _cover(0.5, BLUE, _inside()))
    assert_equal(target.color_at(1, 1).b, 1)
    assert_equal(target.color_at(7, 7).b, 0)


def test_the_depth_function_decides_which_surface_shows() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.25, RED))
    # A farther surface passes only under a function that wants it.
    _fill(target, _cover(0.75, BLUE))
    assert_equal(target.color_at(3, 3).r, 1)
    _fill(target, _cover(0.75, BLUE, RasterState(depth_func=GREATER_DEPTH)))
    assert_equal(target.color_at(3, 3).b, 1)
    assert_equal(target.depth_at(3, 3), Float32(0.75))
    # The default is three.js's `LessEqualDepth`: an equal depth passes.
    _fill(target, _cover(0.75, RED))
    assert_equal(target.color_at(3, 3).r, 1)
    _fill(target, _cover(0.75, BLUE, RasterState(depth_func=LESS_DEPTH)))
    assert_equal(target.color_at(3, 3).r, 1)


def test_a_surface_with_the_depth_test_off_draws_over_and_claims_nothing() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.25, RED))
    _fill(target, _cover(0.75, BLUE, RasterState(depth_test=False)))
    assert_equal(target.color_at(3, 3).b, 1)
    assert_equal(target.depth_at(3, 3), Float32(0.25))


def test_a_surface_that_writes_no_depth_lets_a_farther_one_show() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.25, RED, RasterState(depth_write=False)))
    assert_equal(target.color_at(3, 3).r, 1)
    _fill(target, _cover(0.75, BLUE))
    assert_equal(target.color_at(3, 3).b, 1)


def test_a_surface_that_writes_no_color_still_hides_what_is_behind() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.25, RED, RasterState(color_write=False)))
    assert_equal(target.color_at(3, 3).r, 0)
    assert_equal(target.depth_at(3, 3), Float32(0.25))
    _fill(target, _cover(0.75, BLUE))
    assert_equal(target.color_at(3, 3).b, 0)
    # A blended surface that writes no color leaves the pixel alone too.
    var clear = RasterState(color_write=False)
    _fill(target, _cover(0.1, FloatColor(0, 1, 0, 0.5), clear, BLEND))
    assert_equal(target.color_at(3, 3).g, 0)


def test_an_alpha_test_decides_whether_a_failing_fragment_counts() raises:
    # The stencil's depth-fail operation reaches only a fragment the alpha
    # test keeps, as a GPU's discard throws the fragment away first.
    var counting = RasterState(
        stencil_write=True, stencil_z_fail=INCREMENT_STENCIL_OP
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.25, RED))
    var faint = FloatColor(0, 0, 1, 0.25)
    _fill(target, _cover(0.75, faint, counting, alpha_test=0.5))
    assert_equal(target.stencil_at(3, 3), 0)
    var solid = FloatColor(0, 0, 1, 0.75)
    _fill(target, _cover(0.75, solid, counting, alpha_test=0.5))
    assert_equal(target.stencil_at(3, 3), 1)
    assert_equal(target.color_at(3, 3).r, 1)
    # A failing fragment whose failure changes nothing is not shaded.
    _fill(target, _cover(0.75, solid, alpha_test=0.5))
    assert_equal(target.color_at(3, 3).r, 1)
    # And one that passes writes its depth once it survives.
    _fill(target, _cover(0.1, solid, counting, alpha_test=0.5))
    assert_equal(target.depth_at(3, 3), Float32(0.1))
    assert_equal(target.stencil_at(3, 3), 1)


def test_the_uv_view_obeys_the_depth_and_color_switches() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    _fill(target, _cover(0.5, RED, RasterState(color_write=False)), uv=True)
    assert_false(target.is_data(3, 3))
    assert_equal(target.depth_at(3, 3), Float32(0.5))
    _fill(target, _cover(0.25, RED, _mask(4)), uv=True)
    assert_false(target.is_data(3, 3))
    assert_equal(target.stencil_at(3, 3), 4)
    assert_equal(target.depth_at(3, 3), Float32(0.5))
    _fill(target, _cover(0.25, RED, _inside(4)), uv=True)
    assert_true(target.is_data(3, 3))


def test_a_triangle_refuses_corners_that_disagree_about_their_state() raises:
    var corners = _cover(0.5, RED)
    corners[2].state = _mask()
    with assert_raises(contains="stencil"):
        check_triangle_state(corners[0], corners[1], corners[2])
    var second = _cover(0.5, RED)
    second[1].state = _mask()
    with assert_raises(contains="stencil"):
        check_triangle_state(second[0], second[1], second[2])
    var wrong = _cover(0.5, RED, RasterState(stencil_ref=300))
    with assert_raises(contains="stencil"):
        check_triangle_state(wrong[0], wrong[1], wrong[2])


# --- the host rasterizer: lines and points ------------------------------------


def test_a_line_obeys_the_stencil_the_depth_and_the_color_switches() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(
        _end(0, 0.5, RED, _mask()), _end(3.5, 0.5, RED, _mask()), target
    )
    assert_equal(target.stencil_at(1, 3), 1)
    assert_equal(target.color_at(1, 3).r, 0)
    # Drawn only where the mask was, and it writes its depth.
    rasterize_line(
        _end(0, 0.5, BLUE, _inside()), _end(8, 0.5, BLUE, _inside()), target
    )
    assert_equal(target.color_at(1, 3).b, 1)
    assert_equal(target.depth_at(1, 3), Float32(0.5))
    assert_equal(target.color_at(6, 3).b, 0)
    # A blended line that writes no color changes nothing.
    var quiet = RasterState(color_write=False)
    var green = FloatColor(0, 1, 0, 0.5)
    rasterize_line(
        _end(0, 0.1, green, quiet, BLEND),
        _end(8, 0.1, green, quiet, BLEND),
        target,
    )
    assert_equal(target.color_at(1, 3).g, 0)
    # A blended line with the default state mixes and claims no depth.
    rasterize_line(
        _end(0, 0.1, green, RasterState(), BLEND),
        _end(8, 0.1, green, RasterState(), BLEND),
        target,
    )
    assert_true(target.color_at(1, 3).g > 0)
    assert_equal(target.depth_at(1, 3), Float32(0.5))


def test_a_line_refuses_ends_that_disagree_about_their_state() raises:
    with assert_raises(contains="stencil"):
        check_line_state(
            _end(0, 0.5, RED, RasterState()), _end(8, 0.5, RED, _mask())
        )
    var wrong = RasterState(stencil_write_mask=999)
    with assert_raises(contains="stencil"):
        check_line_state(_end(0, 0.5, RED, wrong), _end(8, 0.5, RED, wrong))


def test_a_point_obeys_the_stencil_the_depth_and_the_color_switches() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(_dot(0.5, RED, _mask()), target)
    assert_equal(target.stencil_at(4, 4), 1)
    assert_equal(target.color_at(4, 4).r, 0)
    rasterize_point(_dot(0.5, BLUE, _inside(2)), target)
    assert_equal(target.color_at(4, 4).b, 0)
    rasterize_point(_dot(0.5, BLUE, _inside()), target)
    assert_equal(target.color_at(4, 4).b, 1)
    assert_equal(target.depth_at(4, 4), Float32(0.5))
    # An alpha-tested point behind: its depth-fail operation counts only
    # when the alpha test keeps it.
    var counting = RasterState(
        stencil_write=True, stencil_z_fail=INCREMENT_STENCIL_OP
    )
    rasterize_point(
        _dot(0.75, FloatColor(0, 1, 0, 0.25), counting, 0.5), target
    )
    assert_equal(target.stencil_at(4, 4), 1)
    rasterize_point(
        _dot(0.75, FloatColor(0, 1, 0, 0.75), counting, 0.5), target
    )
    assert_equal(target.stencil_at(4, 4), 2)
    assert_equal(target.color_at(4, 4).b, 1)
    # A blended point that writes no color changes nothing.
    rasterize_point(
        _dot(
            0.1,
            FloatColor(0, 1, 0, 0.5),
            RasterState(color_write=False),
            blend=BLEND,
        ),
        target,
    )
    assert_equal(target.color_at(4, 4).g, 0)
    # And the uv view obeys the color and the depth switches.
    rasterize_point(
        _dot(0.25, RED, RasterState(color_write=False, depth_write=False)),
        target,
        SHADE_UV,
    )
    assert_false(target.is_data(4, 4))
    assert_equal(target.depth_at(4, 4), Float32(0.5))
    rasterize_point(_dot(0.25, RED, RasterState()), target, SHADE_UV)
    assert_true(target.is_data(4, 4))
    assert_equal(target.depth_at(4, 4), Float32(0.25))


def test_a_point_refuses_a_state_no_backend_can_draw() raises:
    with assert_raises(contains="stencil"):
        check_point_state(
            _dot(0.5, RED, RasterState(stencil_z_fail=StencilOp(8)))
        )


# --- the renderer -------------------------------------------------------------


def _camera() raises -> PerspectiveCamera:
    """Return a camera four meters up the z axis, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _node(mut scene: Scene, z: Float32, order: Int = 0) raises -> NodeId:
    """Return a new node at depth `z`, drawn in render order `order`."""
    var node = scene.add(Object3D())
    scene.node(node).set_position(0, 0, z)
    scene.node(node).render_order = order
    return node


def _quad(mut assets: Assets, size: Float32) raises -> GeometryId:
    """Return a square of side `size` meters."""
    return assets.geometries.add(
        plane(Length(size, METER), Length(size, METER))
    )


def _basic(color: Color) raises -> Material:
    """Return an unlit opaque material."""
    return Material(color, kind=BASIC)


def test_a_mask_pass_limits_a_later_surface_to_its_shape() raises:
    var assets = Assets()
    var scene = Scene()
    var mask = _basic(Color(255, 255, 255))
    mask.color_write = False
    mask.depth_write = False
    mask.stencil_write = True
    mask.stencil_ref = 1
    mask.stencil_z_pass = REPLACE_STENCIL_OP
    var shown = _basic(Color(255, 0, 0))
    shown.stencil_write = True
    shown.stencil_func = EQUAL_STENCIL_FUNC
    shown.stencil_ref = 1
    var small = _quad(assets, 1.0)
    var large = _quad(assets, 2.0)
    scene.add_mesh(Mesh(small, assets.materials.add(mask), _node(scene, 0)))
    scene.add_mesh(
        Mesh(large, assets.materials.add(shown), _node(scene, -0.5, 1))
    )
    scene.update()
    var image = Renderer(SIZE, SIZE).render(scene, assets, _camera())
    var background = image.get_pixel(0, 0)
    assert_equal(image.get_pixel(8, 8).r, 255)
    # Inside the large square but outside the mask: nothing.
    assert_equal(image.get_pixel(4, 8).r, background.r)


def test_a_polygon_offset_settles_two_coplanar_surfaces() raises:
    var assets = Assets()
    var quad = _quad(assets, 2.0)
    for pushed in [False, True]:
        var red = _basic(Color(255, 0, 0))
        red.polygon_offset = True
        red.polygon_offset_factor = 1 if pushed else -1
        red.polygon_offset_units = 4 if pushed else -4
        var red_id = assets.materials.add(red)
        var blue_id = assets.materials.add(_basic(Color(0, 0, 255)))
        # Both orders, so the offset and not the order decides.
        for first_red in [False, True]:
            var scene = Scene()
            var node = _node(scene, 0)
            if first_red:
                scene.add_mesh(Mesh(quad, red_id, node))
                scene.add_mesh(Mesh(quad, blue_id, node))
            else:
                scene.add_mesh(Mesh(quad, blue_id, node))
                scene.add_mesh(Mesh(quad, red_id, node))
            scene.update()
            var center = (
                Renderer(SIZE, SIZE)
                .render(scene, assets, _camera())
                .get_pixel(8, 8)
            )
            if pushed:
                assert_equal(center.b, 255)
            else:
                assert_equal(center.r, 255)


def test_the_depth_switches_reach_the_renderer() raises:
    var assets = Assets()
    var quad = _quad(assets, 2.0)
    var green = assets.materials.add(_basic(Color(0, 255, 0)))
    # A near surface that writes no depth lets a later farther one show.
    var unclaimed = _basic(Color(0, 255, 0))
    unclaimed.depth_write = False
    # A far surface with the depth test off, or under `GREATER_DEPTH`,
    # draws over the near one.
    var over = _basic(Color(0, 0, 255))
    over.depth_test = False
    var behind = _basic(Color(0, 0, 255))
    behind.depth_func = GREATER_DEPTH
    var cases: List[Tuple[Material, Material]] = [
        (unclaimed, _basic(Color(0, 0, 255))),
        (_basic(Color(0, 255, 0)), over),
        (_basic(Color(0, 255, 0)), behind),
    ]
    for index in range(len(cases)):
        var scene = Scene()
        var near = assets.materials.add(cases[index][0])
        var far = assets.materials.add(cases[index][1])
        scene.add_mesh(Mesh(quad, near, _node(scene, 0.5)))
        scene.add_mesh(Mesh(quad, far, _node(scene, -0.5, 1)))
        scene.update()
        var image = Renderer(SIZE, SIZE).render(scene, assets, _camera())
        assert_equal(image.get_pixel(8, 8).b, 255)
    # And with the defaults, the near surface wins.
    var scene = Scene()
    scene.add_mesh(Mesh(quad, green, _node(scene, 0.5)))
    scene.add_mesh(
        Mesh(
            quad,
            assets.materials.add(_basic(Color(0, 0, 255))),
            _node(scene, -0.5, 1),
        )
    )
    scene.update()
    var image = Renderer(SIZE, SIZE).render(scene, assets, _camera())
    assert_equal(image.get_pixel(8, 8).g, 255)


def _segment() raises -> BufferGeometry:
    """Return a horizontal segment across the view."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([Float32(-2), 0, 0, 2, 0, 0], 3)
    )
    return geometry^


def test_lines_points_sprites_and_wireframes_carry_the_state() raises:
    var assets = Assets()
    var scene = Scene()
    var quad = _quad(assets, 2.0)
    scene.add_mesh(
        Mesh(
            quad,
            assets.materials.add(_basic(Color(0, 255, 0))),
            _node(scene, 0.5),
        )
    )
    var far = _node(scene, -0.5, 1)
    var segment = assets.geometries.add(_segment())
    var line = _basic(Color(255, 0, 0))
    line.depth_test = False
    scene.add_line(
        Line(segment, assets.materials.add(line), far, mode=SEGMENTS)
    )
    var dots = points_material(Color(255, 0, 0))
    dots.depth_test = False
    var dot_geometry = BufferGeometry()
    dot_geometry.set_attribute(
        POSITION, BufferAttribute([Float32(0.5), 0.5, 0], 3)
    )
    scene.add_points(
        Points(
            assets.geometries.add(dot_geometry^),
            assets.materials.add(dots),
            far,
        )
    )
    var card = sprite_material(Color(255, 0, 0))
    card.depth_test = False
    var small = _node(scene, -0.5, 1)
    scene.node(small).set_position(-0.5, -0.5, -0.5)
    scene.node(small).set_scale(0.3, 0.3, 0.3)
    scene.add_sprite(Sprite(assets.materials.add(card), small))
    var edges = _basic(Color(255, 0, 0))
    edges.wireframe = True
    edges.depth_test = False
    var corner = _node(scene, -0.5, 1)
    scene.node(corner).set_position(0.5, -0.5, -0.5)
    scene.node(corner).set_scale(0.5, 0.5, 0.5)
    scene.add_mesh(Mesh(quad, assets.materials.add(edges), corner))
    scene.update()
    var image = Renderer(SIZE, SIZE).render(scene, assets, _camera())
    var reds = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if image.get_pixel(x, y).r > 200:
                reds += 1
    # The line alone crosses the near square's width; the rest add more.
    assert_true(reds > 12, String(reds))
    # A state no backend can draw is refused wherever it is.
    var refused = _basic(Color(255, 0, 0))
    refused.stencil_ref = -1
    scene.meshes[0].material = assets.materials.add(refused)
    with assert_raises(contains="stencil"):
        _ = Renderer(SIZE, SIZE).render(scene, assets, _camera())
    var offset = _basic(Color(255, 0, 0))
    offset.polygon_offset = True
    offset.polygon_offset_factor = inf[DType.float32]()
    scene.meshes[0].material = assets.materials.add(offset)
    with assert_raises(contains="finite"):
        _ = Renderer(SIZE, SIZE).render(scene, assets, _camera())


def test_a_surface_that_writes_no_color_still_casts_its_shadow() raises:
    var assets = Assets()
    var scene = Scene()
    var lamp = _node(scene, 5)
    var sun = directional_light(Color(255, 255, 255), lamp, 1.0)
    sun.cast_shadow = True
    scene.add_light(sun)
    var quad = _quad(assets, 2.0)
    var hidden = _basic(Color(255, 255, 255))
    hidden.color_write = False
    hidden.depth_write = False
    hidden.polygon_offset = True
    hidden.polygon_offset_units = 1000
    var mesh = Mesh(quad, assets.materials.add(hidden), _node(scene, 0))
    mesh.cast_shadow = True
    scene.add_mesh(mesh)
    scene.update()
    var depths = (
        Renderer(SIZE, SIZE).shadow_maps(scene, assets)[0].depths.copy()
    )
    var cast = 0
    for index in range(len(depths)):
        if depths[index] < inf[DType.float32]():
            cast += 1
    assert_true(cast > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
