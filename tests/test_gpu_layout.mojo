# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for how `render.gpu` lays its buffers out on the host.

Every test here flattens data into the vertex lanes, the state tables, the
texture table or the light buffer, and reads it back. None of them opens a
device. That is why this suite is apart from `tests/test_gpu.mojo`: it needs
MAX installed but no GPU, so CI runs it on every push, where the device
suite would skip every test and prove nothing.

The layout tests were stale for a week before this suite existed. The lanes
and the header grew, and the assertions kept the old counts, because the
only machine that ran them had no GPU and failed every device test as well.

The fixtures are the device suite's own, imported from it, so the two
suites build the same corners.
"""

from cameras.perspective_camera import (
    PerspectiveCamera,
)
from core.assets import (
    Assets,
)
from core.fog import (
    FogView,
    linear_fog,
)
from core.layers import (
    Layers,
)
from core.object3d import (
    Object3D,
)
from core.scene import (
    Scene,
)
from geometries.box import (
    cube,
)
from geometries.plane import (
    plane,
)
from lights.light import (
    ambient_light,
    directional_light,
    hemisphere_light,
    spot_light,
)
from lights.lighting import (
    Lighting,
    PERSPECTIVE_VIEW,
)
from lights.ltc import (
    load_ltc_tables,
    LTC_FLOATS,
)
from lights.shadow import (
    BASIC_SHADOW_MAP,
    PCF_SHADOW_MAP,
    SHADOW_HEADER,
    SHADOW_INTENSITY_AT,
    SHADOW_TYPE_AT,
    ShadowCascade,
    SPOT_MAP_FLOATS,
    VSM_SHADOW_MAP,
)
from materials.material import (
    ADD_OPERATION,
    BASIC,
    BLEND,
    DEPTH,
    DISTANCE,
    LAMBERT,
    MATCAP,
    MULTIPLY_OPERATION,
    NO_TEXTURE,
    NORMALS,
    OPAQUE,
    PHYSICAL,
    TOON,
)
from materials.nodes import (
    COLOR_NODE as NODES_COLOR,
    NodeGraph,
    NodeProgramId,
    NodeProgramStore,
    OPACITY_NODE as NODES_OPACITY,
)
from math.vector2 import (
    Vector2,
)
from math.vector3 import (
    Vector3,
)
from postprocessing.composer import (
    BOKEH,
    COPY,
    CUBE_TEXTURE,
    GOD_RAYS,
    GTAO,
    LUT,
    MASK,
    PassKind,
    RENDER,
    RENDER_PIXELATED,
    RENDER_TRANSITION,
    SAVE,
    SHADER,
    SHADER_EFFECT,
    SMAA,
)
from render.cube_texture import (
    cube_of_panorama,
)
from render.cube_texture_store import (
    CubeTextureId,
    CubeTextureStore,
)
from render.framebuffer import (
    Color,
    FloatColor,
)
from render.gpu import (
    CASCADE_AT,
    CUBE_PANORAMA,
    CUBE_ROWS,
    DIRECTIONAL_FLOATS,
    flatten,
    flatten_fog,
    flatten_lights,
    flatten_programs,
    flatten_textures,
    flatten_transmission,
    FLOATS_PER_VERTEX,
    FOG_FLOATS,
    FOG_OUTPUT,
    LANE_ANISOTROPY_X,
    LANE_ANISOTROPY_Y,
    LANE_AO_INTENSITY,
    LANE_BLEND_CONSTANT,
    LANE_ATTENUATION_B,
    LANE_ATTENUATION_DISTANCE,
    LANE_ATTENUATION_R,
    LANE_BUMP_SCALE,
    LANE_CLEARCOAT,
    LANE_CLEARCOAT_NORMAL_SCALE_X,
    LANE_CLEARCOAT_NORMAL_SCALE_Y,
    LANE_CLEARCOAT_ROUGHNESS,
    LANE_DASH,
    LANE_ENV_ROTATION,
    LANE_DISPERSION,
    LANE_ENV_INTENSITY,
    LANE_FAR_DISTANCE,
    LANE_GAP,
    LANE_IOR,
    LANE_IRIDESCENCE,
    LANE_IRIDESCENCE_IOR,
    LANE_LIGHT_MAP_INTENSITY,
    LANE_LINE_DISTANCE,
    LANE_LOG_DEPTH,
    LANE_METALNESS,
    LANE_NEAR_DISTANCE,
    LANE_NORMAL_SCALE_X,
    LANE_NORMAL_SCALE_Y,
    LANE_POINT_SIZE,
    LANE_REFERENCE_X,
    LANE_REFERENCE_Y,
    LANE_REFERENCE_Z,
    LANE_REFLECTIVITY,
    LANE_ROUGHNESS,
    LANE_SHEEN_B,
    LANE_SHEEN_G,
    LANE_SHEEN_R,
    LANE_SHEEN_ROUGHNESS,
    LANE_SPECULAR_COLOR_B,
    LANE_SPECULAR_COLOR_G,
    LANE_SPECULAR_COLOR_R,
    LANE_SPECULAR_INTENSITY,
    LANE_THICKNESS_MAXIMUM,
    LANE_THICKNESS_MINIMUM,
    LANE_THICKNESS_X,
    LANE_THICKNESS_Z,
    LANE_TRANSMISSION,
    LANE_U1,
    LANE_V1,
    LIGHTS_AMBIENT,
    LIGHTS_BACK,
    LIGHTS_EYE,
    LIGHTS_FIRST,
    LIGHTS_PROBE,
    LIGHTS_RECT_COUNT,
    LIGHTS_TOWARD,
    LIGHTS_UP,
    line_state,
    LINE_STATE_FOG,
    LINE_STATE_OPS,
    LINE_STATE_STENCIL,
    NO_SHADOW,
    pack,
    PLANE_COLOR,
    PLANE_DATA,
    PLANE_FLOATS,
    PLANE_NORMAL,
    POINT_FLOATS,
    point_state,
    POINT_STATE_ALPHA_MAP,
    POINT_STATE_BLEND,
    POINT_STATE_FOG,
    POINT_STATE_OPS,
    POINT_STATE_STENCIL,
    POINT_STATE_TEXTURE,
    program_starts,
    RECT_FLOATS,
    runs_on_device,
    SPOT_FLOATS,
    STATE_ANISOTROPY_MAP,
    STATE_AO_MAP,
    STATE_BUMP_MAP,
    STATE_CLEARCOAT_MAP,
    STATE_CLEARCOAT_NORMAL_MAP,
    STATE_CLEARCOAT_ROUGHNESS_MAP,
    STATE_COMBINE,
    STATE_DEPTH_PACKING,
    STATE_ENV_MAP,
    STATE_FILM_THICKNESS_MAP,
    STATE_FOG,
    STATE_IRIDESCENCE_MAP,
    STATE_LIGHT_MAP,
    STATE_METALNESS_MAP,
    STATE_NODES,
    STATE_NORMAL_MAP,
    STATE_NORMAL_MAP_TYPE,
    STATE_OPS,
    STATE_PER_LINE,
    STATE_PER_POINT,
    STATE_PER_TRIANGLE,
    STATE_RECEIVES_SHADOW,
    STATE_ROUGHNESS_MAP,
    STATE_SHEEN_COLOR_MAP,
    STATE_SHEEN_ROUGHNESS_MAP,
    STATE_SPECULAR_COLOR_MAP,
    STATE_SPECULAR_INTENSITY_MAP,
    STATE_SPECULAR_MAP,
    STATE_STENCIL,
    STATE_THICKNESS_MAP,
    STATE_TRANSMISSION_MAP,
    TABLE_COLUMNS,
    TABLE_FLIP_Y,
    TABLE_MAPPING,
    TABLE_MIN_FILTER,
    TABLE_PLACEMENT,
    TABLE_WRAP_T,
    TRANSMISSION_HEADER,
    TRANSMISSION_LEVELS,
    TRANSMISSION_WIDTH,
    triangle_state,
)
from render.packing import (
    BASIC_DEPTH_PACKING,
    RGB_DEPTH_PACKING,
)
from render.raster_state import (
    GREATER_DEPTH,
    INCREMENT_STENCIL_OP,
    LOGARITHMIC_DEPTH,
    NOT_EQUAL_STENCIL_FUNC,
    RasterState,
    REVERSED_DEPTH,
)
from render.rasterizer import (
    LayerFactors,
    RasterVertex,
)
from render.srgb import (
    ColorSpace,
)
from render.texture import (
    BILINEAR,
    checkerboard,
    CLAMP,
    COVERAGE,
    CUBE_REFLECTION_MAPPING,
    CUBE_REFRACTION_MAPPING,
    CUBE_UV_REFLECTION_MAPPING,
    EQUIRECTANGULAR_REFLECTION_MAPPING,
    EQUIRECTANGULAR_REFRACTION_MAPPING,
    float_from_bytes,
    FLOAT_TYPE,
    IGNORED,
    LINEAR_MIPMAP_NEAREST,
    MIRROR,
    NEAREST,
    REPEAT,
    Texture,
    UNSIGNED_BYTE_TYPE,
    UV_CHANNEL_0,
    UV_CHANNEL_1,
)
from render.texture_store import (
    TextureId,
    TextureStore,
)
from renderers.renderer import (
    Renderer,
)
from std.memory import (
    bitcast,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle,
    DEGREE,
    Length,
    METER,
)
from test_gpu import (
    _stenciled,
    a_bulb_and_slide_scene,
    a_cube_store,
    a_float_ramp,
    a_gpu_cube,
    a_gpu_data_map,
    a_gpu_face,
    a_gpu_panorama,
    a_pmrem_store,
    a_point,
    a_scene_behind,
    a_shadowed_scene,
    a_varying_line,
    baked_pair,
    corner,
    data_pair,
    glass_pair,
    glowing,
    gpu_striped_store,
    matcap_pair,
    mirror_pair,
    overlapping_pair,
    packed_pair,
    phong_lighting,
    phong_pair,
    physical_pair,
    probe_lighting,
    toon_pair,
    with_a_rectangle,
    with_gpu_layers,
    with_nodes,
    with_specular_map,
)


def test_colors_pack_into_a_big_endian_word() raises:
    assert_equal(pack(Color(0xAA, 0xBB, 0xCC, 0xDD)), UInt32(0xAABBCCDD))
    assert_equal(pack(Color(0, 0, 0, 0)), UInt32(0))
    assert_equal(pack(Color(255, 255, 255, 255)), UInt32(0xFFFFFFFF))


def test_alpha_survives_packing() raises:
    assert_equal(pack(Color(1, 2, 3, 128)) & UInt32(0xFF), UInt32(128))


def test_flattening_lays_out_a_lane_per_varying() raises:
    # The host side of the kernel's unpacking. If these disagree the image is
    # garbage, so the layout is asserted rather than assumed. The count is
    # spelled out because changing the stride and missing one of the kernel's
    # offsets is a mistake this project has made twice. A new lane changes
    # it; the other tests read `FLOATS_PER_VERTEX`, so it is spelled once.
    var corners = List[RasterVertex]()
    corners.append(
        glowing(
            corner(1, 2, 3, 4, Color(255, 128, 0, 64)),
            FloatColor(0.25, 0.5, 0.75),
        )
    )
    var flat = flatten(corners)
    assert_equal(len(flat), 97)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[0], Float32(1))
    assert_equal(flat[1], Float32(2))
    assert_equal(flat[2], Float32(3))
    assert_equal(flat[3], Float32(4))
    assert_equal(flat[4], Float32(1.0))
    assert_almost_equal(flat[5], Float32(128) / 255, atol=Float64(1e-6))
    assert_equal(flat[6], Float32(0))
    assert_almost_equal(flat[7], Float32(64) / 255, atol=Float64(1e-6))
    # The emissive rides after the world position, three lanes: it never
    # touches alpha. The camera-space depth rides last, for the fog.
    assert_equal(flat[16], Float32(0.25))
    assert_equal(flat[17], Float32(0.5))
    assert_equal(flat[18], Float32(0.75))
    assert_equal(flat[19], Float32(0))
    var deep = List[RasterVertex]()
    deep.append(RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), view_depth=7.5))
    assert_equal(flatten(deep)[19], Float32(7.5))
    # The distance along a line and its dash and gap ride last, three
    # lanes, and a corner that says nothing about them carries zeros.
    assert_equal(flat[LANE_LINE_DISTANCE], Float32(0))
    assert_equal(flat[LANE_DASH], Float32(0))
    assert_equal(flat[LANE_GAP], Float32(0))
    var dashed = List[RasterVertex]()
    dashed.append(
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            line_distance=6.5,
            dash_size=3,
            gap_size=1,
        )
    )
    var lanes = flatten(dashed)
    assert_equal(lanes[LANE_LINE_DISTANCE], Float32(6.5))
    assert_equal(lanes[LANE_DASH], Float32(3))
    assert_equal(lanes[LANE_GAP], Float32(1))
    # A point's size rides last of all, and a corner that is not a point
    # carries zero.
    assert_equal(flat[LANE_POINT_SIZE], Float32(0))
    var dotted = List[RasterVertex]()
    dotted.append(RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), point_size=5.5))
    assert_equal(flatten(dotted)[LANE_POINT_SIZE], Float32(5.5))
    # The reflectivity rides after the point size, and a corner that
    # says nothing about it carries three.js's one.
    assert_equal(flat[LANE_REFLECTIVITY], Float32(1))
    var dim = List[RasterVertex]()
    dim.append(RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), reflectivity=0.25))
    assert_equal(flatten(dim)[LANE_REFLECTIVITY], Float32(0.25))
    # The log depth factor rides last, zero for a corner under the
    # standard depth.
    assert_equal(flat[LANE_LOG_DEPTH], Float32(0))
    var logged = List[RasterVertex]()
    logged.append(
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            state=RasterState(
                depth_mode=LOGARITHMIC_DEPTH, log_depth_scale=0.25
            ),
        )
    )
    assert_equal(flatten(logged)[LANE_LOG_DEPTH], Float32(0.25))


def test_the_point_state_table_has_an_entry_per_map_and_policy() raises:
    var points: List[RasterVertex] = [
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            texture=TextureId(3),
            blend=BLEND,
            kind=BASIC,
            alpha_map=TextureId(5),
            point_size=2,
        ),
        RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), kind=BASIC, point_size=2),
    ]
    var state = point_state(points)
    assert_equal(len(state), 2 * STATE_PER_POINT)
    assert_equal(state[POINT_STATE_TEXTURE], Int32(3))
    assert_equal(state[POINT_STATE_BLEND], Int32(BLEND.value))
    assert_equal(state[POINT_STATE_ALPHA_MAP], Int32(5))
    assert_equal(state[STATE_PER_POINT + POINT_STATE_TEXTURE], Int32(-1))
    assert_equal(
        state[STATE_PER_POINT + POINT_STATE_BLEND], Int32(OPAQUE.value)
    )
    assert_equal(state[STATE_PER_POINT + POINT_STATE_ALPHA_MAP], Int32(-1))


def test_the_state_table_has_an_entry_per_map_and_policy() raises:
    # Texture, blend, material kind, emissive map, alpha map and gradient
    # map, all from the first corner.
    var corners = List[RasterVertex]()
    for _ in range(3):
        corners.append(
            RasterVertex(
                0,
                0,
                0.5,
                1,
                FloatColor(1, 1, 1),
                0,
                0,
                TextureId(2),
                BLEND,
                Vector3(0, 0, 1),
                Vector3(0, 0, 0),
                BASIC,
                FloatColor(0, 0, 0),
                TextureId(5),
            )
        )
    var state = triangle_state(corners)
    assert_equal(len(state), STATE_PER_TRIANGLE)
    assert_equal(state[0], Int32(2))
    assert_equal(state[1], Int32(BLEND.value))
    assert_equal(state[2], Int32(BASIC.value))
    assert_equal(state[3], Int32(5))
    assert_equal(state[4], Int32(NO_TEXTURE.value))
    assert_equal(state[5], Int32(NO_TEXTURE.value))
    assert_equal(state[6], Int32(NO_TEXTURE.value))
    # No env map crosses as -1, and the combine as its value.
    assert_equal(state[STATE_ENV_MAP], Int32(-1))
    assert_equal(state[STATE_COMBINE], Int32(MULTIPLY_OPERATION.value))
    # An env map crosses as the row of its first face: after the flat
    # textures, `CUBE_ROWS` rows a cube: six faces, the PMREM row and the
    # panorama row.
    var mirrored = mirror_pair(CubeTextureId(2), 0.5, ADD_OPERATION)
    assert_equal(triangle_state(mirrored)[STATE_ENV_MAP], Int32(2 * CUBE_ROWS))
    assert_equal(
        triangle_state(mirrored, 5)[STATE_ENV_MAP], Int32(5 + 2 * CUBE_ROWS)
    )
    assert_equal(
        triangle_state(mirrored)[STATE_COMBINE], Int32(ADD_OPERATION.value)
    )
    # A matcap triangle's image rides the column after the ramp.
    assert_equal(triangle_state(matcap_pair(TextureId(8)))[6], Int32(8))
    assert_equal(triangle_state(matcap_pair())[6], Int32(NO_TEXTURE.value))
    # A toon triangle's ramp rides the last column.
    var stepped = toon_pair(TextureId(6))
    assert_equal(triangle_state(stepped)[5], Int32(6))
    assert_equal(triangle_state(toon_pair())[5], Int32(NO_TEXTURE.value))
    # And each of the other four kinds crosses as its own value.
    for kind in [LAMBERT, NORMALS, DEPTH, TOON, MATCAP]:
        var others = List[RasterVertex]()
        for _ in range(3):
            others.append(
                RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1), kind=kind)
            )
        assert_equal(triangle_state(others)[2], Int32(kind.value))


def test_flattening_lights_lays_out_the_sky_and_the_cone() raises:
    # The camera first, then the ambient term, then nine floats per
    # hemisphere light after the point lights and thirteen per spot light
    # after those, in the order the kernel unpacks them.
    var scene = Scene()
    var up = Object3D()
    up.set_position(0, 4, 0)
    var up_node = scene.add(up^)
    var bulb = Object3D()
    bulb.set_position(0, 2, 0)
    var bulb_node = scene.add(bulb^)
    scene.update()
    scene.add_light(ambient_light(Color(255, 255, 255), 0.5))
    scene.add_light(
        hemisphere_light(Color(255, 255, 255), Color(0, 0, 0), up_node, 0.25)
    )
    scene.add_light(
        spot_light(
            Color(255, 255, 255),
            bulb_node,
            2.0,
            7.0,
            Angle(60.0, DEGREE),
            0.5,
            1.0,
        )
    )
    var lighting = Lighting(scene)
    var flat = flatten_lights(lighting)
    assert_equal(len(flat), LIGHTS_FIRST + 9 + 15)
    assert_almost_equal(flat[LIGHTS_AMBIENT], Float32(0.5), atol=Float64(1e-6))
    # The sky is straight up, white at a quarter, over a black ground.
    var sky = LIGHTS_FIRST
    assert_almost_equal(flat[sky + 1], Float32(1), atol=Float64(1e-6))
    assert_almost_equal(flat[sky + 3], Float32(0.25), atol=Float64(1e-6))
    assert_almost_equal(flat[sky + 6], Float32(0), atol=Float64(1e-6))
    # The bulb two meters up, pointing down at the origin, so its axis from
    # the target toward it is +y; twice white; decay one and a cutoff of
    # seven; and the cosines of sixty and thirty degrees.
    var beam = sky + 9
    assert_almost_equal(flat[beam + 1], Float32(2), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 4], Float32(1), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 6], Float32(2), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 9], Float32(1), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 10], Float32(7), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 11], Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 12], Float32(0.8660254), atol=Float64(1e-6))


def test_flattening_fog_lays_out_six_floats() raises:
    # The two edges, the density, then the color, linear.
    var view = FogView(
        linear_fog(Color(128, 0, 255), Length(2.0, METER), Length(9.0, METER))
    )
    var flat = flatten_fog(view)
    assert_equal(len(flat), 18)
    assert_equal(len(flat), FOG_FLOATS)
    # Then the output encoding: sRGB by default, the matrix skipped.
    assert_equal(flat[FOG_OUTPUT], Float32(1))
    assert_equal(flat[FOG_OUTPUT + 9], Float32(1))
    assert_equal(flat[FOG_OUTPUT + 10], Float32(1))
    # No custom tone mapping curve: its start is -1.
    assert_equal(flat[6], Float32(-1))
    assert_equal(flatten_fog(view, 12)[6], Float32(12))
    assert_equal(flat[0], Float32(2))
    assert_equal(flat[1], Float32(9))
    assert_equal(flat[2], Float32(0))
    assert_almost_equal(flat[3], Float32(0.215861), atol=Float64(1e-5))
    assert_equal(flat[4], Float32(0))
    assert_equal(flat[5], Float32(1))


def test_the_table_carries_the_alpha_mode() raises:
    # Host side: eight columns per texture, the last the alpha mode, and the
    # blank texture crosses as coverage like any opaque image.
    var textures = TextureStore()
    _ = textures.add(checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0)))
    _ = textures.add(
        checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    _ = textures.add(Texture())
    var flattened = flatten_textures(textures)
    ref table = flattened[1]
    assert_equal(len(table), 3 * TABLE_COLUMNS)
    assert_equal(table[7], Int32(COVERAGE.value))
    assert_equal(table[TABLE_COLUMNS + 7], Int32(IGNORED.value))
    assert_equal(table[2 * TABLE_COLUMNS + 7], Int32(COVERAGE.value))


def test_the_table_carries_a_float_texture() raises:
    # Host side: a float texture crosses as four little-endian bytes a
    # number, its chain included, and says so in the table's last column.
    var textures = TextureStore()
    _ = textures.add(checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0)))
    var ramp = a_float_ramp(4)
    var expected = ramp.data.copy()
    _ = textures.add(ramp^)
    var flattened = flatten_textures(textures)
    ref table = flattened[1]
    ref texels = flattened[0]
    assert_equal(table[9], Int32(UNSIGNED_BYTE_TYPE.value))
    assert_equal(table[TABLE_COLUMNS + 9], Int32(FLOAT_TYPE.value))
    var start = Int(table[TABLE_COLUMNS])
    assert_equal(len(texels), start + len(expected) * 4)
    for index in range(len(expected)):
        var at = start + index * 4
        assert_equal(
            float_from_bytes(
                texels[at], texels[at + 1], texels[at + 2], texels[at + 3]
            ),
            expected[index],
        )


def test_flattening_refuses_a_texture_edited_into_nonsense() raises:
    # Host side, so it runs without a GPU: the upload checks every texture
    # again, because the kernel cannot raise on what it finds in the table.
    var textures = TextureStore()
    var board = checkerboard(
        4, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    )
    board.color_space = ColorSpace(99)
    _ = textures.add(board^)
    with assert_raises():
        _ = flatten_textures(textures)


def test_flattening_carries_the_alpha_test_in_its_own_lane() raises:
    # It is the only float among the per-triangle state, so it rides a lane
    # of its own rather than the integer state table.
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), alpha_test=0.375)
    )
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[20], Float32(0.375))
    # And a corner that says nothing about it carries zero, no test.
    var plain = List[RasterVertex]()
    plain.append(RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1)))
    assert_equal(flatten(plain)[20], Float32(0))


def test_the_state_table_carries_the_alpha_map() raises:
    var corners = List[RasterVertex]()
    for _ in range(3):
        corners.append(
            RasterVertex(
                0,
                0,
                0.5,
                1,
                FloatColor(1, 1, 1),
                alpha_map=TextureId(7),
            )
        )
    var state = triangle_state(corners)
    assert_equal(len(state), STATE_PER_TRIANGLE)
    assert_equal(state[4], Int32(7))
    var plain = List[RasterVertex]()
    for _ in range(3):
        plain.append(RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1)))
    assert_equal(triangle_state(plain)[4], Int32(NO_TEXTURE.value))


def test_flattening_carries_the_specular_and_the_shininess() raises:
    # Four more lanes: the specular as three, like the emissive, and the
    # shininess as one per-triangle float, like the alpha test.
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            specular=FloatColor(0.25, 0.5, 0.75),
            shininess=30.0,
        )
    )
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[21], Float32(0.25))
    assert_equal(flat[22], Float32(0.5))
    assert_equal(flat[23], Float32(0.75))
    assert_equal(flat[24], Float32(30.0))


def test_the_light_buffer_begins_with_the_camera_and_its_direction() raises:
    # A highlight is measured from there, and putting the camera at the
    # head leaves every light's offset one named constant away. The
    # direction beside it is what a parallel projection puts there.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    var flat = flatten_lights(Lighting(scene, Layers.all(), Vector3(7, 8, 9)))
    assert_equal(len(flat), LIGHTS_FIRST + DIRECTIONAL_FLOATS)
    assert_equal(flat[LIGHTS_EYE], Float32(7))
    assert_equal(flat[LIGHTS_EYE + 1], Float32(8))
    assert_equal(flat[LIGHTS_EYE + 2], Float32(9))
    # Nothing said which way the camera lies, so the lanes hold the zero
    # vector that means a converging view; see `toward_eye_at`.
    assert_equal(flat[LIGHTS_TOWARD], Float32(0))
    assert_equal(flat[LIGHTS_TOWARD + 1], Float32(0))
    assert_equal(flat[LIGHTS_TOWARD + 2], Float32(0))
    assert_equal(flat[LIGHTS_AMBIENT], Float32(1))
    # The one directional light follows, its unit direction then its light.
    assert_equal(flat[LIGHTS_FIRST + 2], Float32(1))
    assert_equal(flat[LIGHTS_FIRST + 3], Float32(1))
    # A parallel projection puts its one direction there, normalized on the
    # way in so no fragment has to.
    var flat_view = flatten_lights(
        Lighting(scene, Layers.all(), Vector3(7, 8, 9), Vector3(0, 0, 4))
    )
    assert_equal(flat_view[LIGHTS_TOWARD], Float32(0))
    assert_equal(flat_view[LIGHTS_TOWARD + 1], Float32(0))
    assert_equal(flat_view[LIGHTS_TOWARD + 2], Float32(1))
    # The camera's own up axis follows, normalized on the way in. World
    # up is what an upright camera has and what a caller that says
    # nothing gets.
    assert_equal(flat[LIGHTS_UP], Float32(0))
    assert_equal(flat[LIGHTS_UP + 1], Float32(1))
    assert_equal(flat[LIGHTS_UP + 2], Float32(0))
    var rolled = flatten_lights(
        Lighting(
            scene,
            Layers.all(),
            Vector3(7, 8, 9),
            PERSPECTIVE_VIEW,
            Vector3(0, 0, 5),
        )
    )
    assert_equal(rolled[LIGHTS_UP + 2], Float32(1))
    assert_equal(rolled[LIGHTS_UP + 1], Float32(0))


def test_flattening_lays_the_cube_faces_out_after_the_textures() raises:
    var textures = TextureStore()
    _ = textures.add(a_gpu_face(Color(1, 2, 3)))
    var flat = flatten_textures(textures, a_cube_store())
    ref table = flat[1]
    # One flat texture, then two cubes of six faces, a PMREM row and a
    # panorama row each: seventeen rows.
    assert_equal(len(table), 17 * TABLE_COLUMNS)
    # The +x face of the first cube is the second row, red, 2x2, clamped.
    assert_equal(table[TABLE_COLUMNS + 1], Int32(2))
    assert_equal(table[TABLE_COLUMNS + 3], Int32(CLAMP.value))
    var start = Int(table[TABLE_COLUMNS])
    assert_equal(flat[0][start], UInt8(255))
    assert_equal(flat[0][start + 1], UInt8(0))
    # The -x face is the third row, green.
    var next = Int(table[2 * TABLE_COLUMNS])
    assert_equal(flat[0][next + 1], UInt8(255))
    # A cube edited into nonsense is refused, as a texture is.
    var store = a_cube_store()
    store.textures[1].faces[3].set_wrap(REPEAT)
    with assert_raises():
        _ = flatten_textures(textures, store)


def test_the_table_carries_the_anisotropy() raises:
    var store = gpu_striped_store(8)
    var flat = flatten_textures(store)
    assert_equal(len(flat[1]), TABLE_COLUMNS)
    assert_equal(flat[1][8], Int32(8))
    # The blank texture allows one tap.
    var blank = TextureStore()
    _ = blank.add(Texture())
    assert_equal(flatten_textures(blank)[1][8], Int32(1))
    # And an anisotropy edited below one is refused on the way up.
    store.textures[0].anisotropy = 0
    with assert_raises():
        _ = flatten_textures(store)


def test_the_physical_lanes_and_columns_ride_last() raises:
    # Nine more lanes after the reflectivity, and four more columns after
    # the combine, each from the first corner.
    var corners = physical_pair(
        PHYSICAL,
        0.3,
        0.6,
        0.9,
        0.2,
        CubeTextureId(1),
        TextureId(2),
        NO_TEXTURE,
        TextureId(4),
        TextureId(5),
    )
    corners[0].env_map_intensity = 1.5
    corners[0].specular_intensity = 0.75
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX * 6)
    assert_equal(flat[LANE_ROUGHNESS], Float32(0.3))
    assert_equal(flat[LANE_METALNESS], Float32(0.6))
    assert_equal(flat[LANE_ENV_INTENSITY], Float32(1.5))
    assert_equal(flat[LANE_SPECULAR_INTENSITY], Float32(0.75))
    assert_equal(flat[LANE_CLEARCOAT], Float32(0.9))
    assert_equal(flat[LANE_CLEARCOAT_ROUGHNESS], Float32(0.2))
    assert_equal(flat[LANE_NORMAL_SCALE_X], Float32(1.5))
    assert_equal(flat[LANE_NORMAL_SCALE_Y], Float32(0.5))
    assert_equal(flat[LANE_BUMP_SCALE], Float32(0.3))
    assert_equal(LANE_BUMP_SCALE, LANE_U1 - 1)
    assert_equal(LANE_FAR_DISTANCE, LANE_SHEEN_R - 1)
    # A corner that says nothing carries a rough dielectric with no map.
    var plain = flatten([RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1))])
    assert_equal(plain[LANE_ROUGHNESS], Float32(1))
    assert_equal(plain[LANE_METALNESS], Float32(0))
    assert_equal(plain[LANE_ENV_INTENSITY], Float32(1))
    assert_equal(plain[LANE_SPECULAR_INTENSITY], Float32(1))
    assert_equal(plain[LANE_CLEARCOAT], Float32(0))
    assert_equal(plain[LANE_NORMAL_SCALE_X], Float32(1))
    assert_equal(plain[LANE_NORMAL_SCALE_Y], Float32(1))
    assert_equal(plain[LANE_BUMP_SCALE], Float32(1))
    var state = triangle_state(corners, 3)
    assert_equal(len(state), 2 * STATE_PER_TRIANGLE)
    assert_equal(state[STATE_ROUGHNESS_MAP], Int32(4))
    assert_equal(state[STATE_METALNESS_MAP], Int32(5))
    assert_equal(state[STATE_NORMAL_MAP], Int32(2))
    assert_equal(state[STATE_BUMP_MAP], Int32(NO_TEXTURE.value))
    assert_equal(state[STATE_ENV_MAP], Int32(3 + CUBE_ROWS))
    assert_equal(STATE_BUMP_MAP, STATE_RECEIVES_SHADOW - 1)


def test_the_light_buffer_carries_the_shadow_maps_after_the_lights() raises:
    # A directional light's seventh float and a spot light's fourteenth
    # say where their maps begin, and the maps follow with a header of
    # twenty-one floats and then their depths.
    var assets = Assets()
    var scene = a_shadowed_scene(assets)
    var renderer = Renderer(24, 18)
    var maps = renderer.shadow_maps(scene, assets)
    assert_equal(len(maps), 2)
    var lighting = Lighting(scene, shadows=maps^)
    var flat = flatten_lights(lighting)
    var lights_end = LIGHTS_FIRST + DIRECTIONAL_FLOATS + 15
    var first_map = lights_end
    var second_map = first_map + SHADOW_HEADER + 48 * 48
    assert_equal(len(flat), second_map + SHADOW_HEADER + 32 * 32)
    assert_equal(flat[LIGHTS_FIRST + 6], Float32(first_map))
    assert_equal(
        flat[LIGHTS_FIRST + DIRECTIONAL_FLOATS + 13], Float32(second_map)
    )
    assert_equal(flat[first_map], Float32(48))
    assert_equal(flat[first_map + 1], Float32(-0.002))
    assert_equal(flat[first_map + 3], Float32(1.5))
    assert_equal(flat[second_map], Float32(32))
    assert_equal(flat[second_map + 2], Float32(0.02))
    assert_equal(flat[first_map + 4], lighting.shadows[0].frame[0])
    assert_equal(
        flat[first_map + SHADOW_TYPE_AT], Float32(PCF_SHADOW_MAP.value)
    )
    assert_equal(flat[first_map + SHADOW_HEADER], lighting.shadows[0].depths[0])
    # Without maps, the lights carry `NO_SHADOW`.
    var bare = flatten_lights(Lighting(scene))
    assert_equal(len(bare), lights_end)
    assert_equal(bare[LIGHTS_FIRST + 6], NO_SHADOW)
    assert_equal(bare[LIGHTS_FIRST + DIRECTIONAL_FLOATS + 13], NO_SHADOW)
    # And the state table says whether a triangle receives.
    var corners = renderer.prepare(
        scene,
        assets,
        PerspectiveCamera(
            Angle(45.0, DEGREE),
            4.0 / 3.0,
            Length(0.1, METER),
            Length(50.0, METER),
        ),
    )
    var state = triangle_state(corners)
    assert_equal(STATE_RECEIVES_SHADOW, STATE_OPS - 1)
    assert_equal(state[STATE_RECEIVES_SHADOW], Int32(1))
    var plain = data_pair(LAMBERT)
    for index in range(len(plain)):
        plain[index].receives_shadow = False
    assert_equal(triangle_state(plain)[STATE_RECEIVES_SHADOW], Int32(0))


def test_the_light_buffer_carries_a_cube_and_a_spot_lights_map() raises:
    # A point light's ninth float says where its cube begins, and the cube
    # holds the bulb and its planes where a frame would be, then six faces;
    # a spot light's fifteenth says where its map begins, after the shadow
    # maps: the texture's slot, the normal bias and the frame.
    var assets = Assets()
    var scene = a_bulb_and_slide_scene(assets)
    var renderer = Renderer(24, 18)
    var shadows = renderer.shadow_maps(scene, assets)
    var slides = renderer.spot_light_maps(scene, assets)
    assert_equal(len(shadows), 2)
    assert_equal(len(slides), 1)
    var lighting = Lighting(scene, shadows=shadows^, spot_maps=slides^)
    var flat = flatten_lights(lighting)
    assert_equal(POINT_FLOATS, 9)
    assert_equal(SPOT_FLOATS, 15)
    var first_map = LIGHTS_FIRST + POINT_FLOATS + SPOT_FLOATS
    var second_map = first_map + SHADOW_HEADER + 6 * 16 * 16
    var slide_at = second_map + SHADOW_HEADER + 8 * 8
    assert_equal(len(flat), slide_at + SPOT_MAP_FLOATS)
    assert_equal(flat[LIGHTS_FIRST + 8], Float32(first_map))
    assert_equal(flat[LIGHTS_FIRST + POINT_FLOATS + 13], Float32(second_map))
    assert_equal(flat[LIGHTS_FIRST + POINT_FLOATS + 14], Float32(slide_at))
    assert_equal(flat[first_map], Float32(16))
    assert_equal(flat[first_map + 1], Float32(-0.005))
    assert_equal(flat[first_map + 3], Float32(1.5))
    assert_equal(flat[first_map + 4], Float32(-2))
    assert_equal(flat[first_map + 5], Float32(3))
    assert_equal(flat[first_map + 6], Float32(1))
    assert_equal(flat[first_map + 7], Float32(0.5))
    assert_equal(flat[first_map + 8], Float32(500))
    assert_equal(flat[first_map + 9], Float32(0))
    assert_equal(flat[first_map + SHADOW_HEADER], lighting.shadows[0].depths[0])
    assert_equal(flat[slide_at], Float32(0))
    assert_equal(flat[slide_at + 1], Float32(0.02))
    assert_equal(flat[slide_at + 2], lighting.spot_maps[0].frame[0])
    assert_equal(flat[slide_at + 17], lighting.spot_maps[0].frame[15])
    # Without them, the lights carry `NO_SHADOW` in both places.
    var bare = flatten_lights(Lighting(scene))
    assert_equal(len(bare), first_map)
    assert_equal(bare[LIGHTS_FIRST + 8], NO_SHADOW)
    assert_equal(bare[LIGHTS_FIRST + POINT_FLOATS + 14], NO_SHADOW)


def test_the_light_buffer_carries_each_maps_type_and_a_variance_maps_moments() raises:
    # The header's last float is the map's `ShadowMapType`, and a variance
    # map's two squares follow it: the means, then the spreads.
    var assets = Assets()
    var scene = a_shadowed_scene(assets)
    var renderer = Renderer(24, 18)
    renderer.shadow_map_type = VSM_SHADOW_MAP
    var lighting = Lighting(scene, shadows=renderer.shadow_maps(scene, assets))
    var flat = flatten_lights(lighting)
    var first_map = LIGHTS_FIRST + DIRECTIONAL_FLOATS + 15
    var second_map = first_map + SHADOW_HEADER + 2 * 48 * 48
    assert_equal(len(flat), second_map + SHADOW_HEADER + 2 * 32 * 32)
    assert_equal(
        flat[LIGHTS_FIRST + DIRECTIONAL_FLOATS + 13], Float32(second_map)
    )
    assert_equal(
        flat[first_map + SHADOW_TYPE_AT], Float32(VSM_SHADOW_MAP.value)
    )
    assert_equal(
        flat[first_map + SHADOW_HEADER + 48 * 48],
        lighting.shadows[0].depths[48 * 48],
    )
    # A cube carries its type in the same place.
    var bulbs = a_bulb_and_slide_scene(assets)
    renderer.shadow_map_type = BASIC_SHADOW_MAP
    var cube = flatten_lights(
        Lighting(bulbs, shadows=renderer.shadow_maps(bulbs, assets))
    )
    var cube_at = LIGHTS_FIRST + POINT_FLOATS + SPOT_FLOATS
    assert_equal(
        cube[cube_at + SHADOW_TYPE_AT], Float32(BASIC_SHADOW_MAP.value)
    )


def test_the_light_buffer_carries_cascades_and_shadow_intensities() raises:
    # A directional light's last five floats are its cascade, and every
    # shadow map's header ends with its intensity.
    var assets = Assets()
    var scene = a_shadowed_scene(assets)
    scene.lights[0].shadow.intensity = 0.4
    scene.lights[0].cascade = ShadowCascade(
        0.25, 0.75, Length(20.0, METER), True, True
    )
    var renderer = Renderer(24, 18)
    var lighting = Lighting(scene, shadows=renderer.shadow_maps(scene, assets))
    var flat = flatten_lights(lighting)
    assert_equal(DIRECTIONAL_FLOATS, CASCADE_AT + 5)
    assert_equal(flat[LIGHTS_FIRST + CASCADE_AT], Float32(0.25))
    assert_equal(flat[LIGHTS_FIRST + CASCADE_AT + 1], Float32(0.75))
    assert_equal(flat[LIGHTS_FIRST + CASCADE_AT + 2], Float32(20))
    assert_equal(flat[LIGHTS_FIRST + CASCADE_AT + 3], Float32(1))
    assert_equal(flat[LIGHTS_FIRST + CASCADE_AT + 4], Float32(1))
    var first_map = Int(flat[LIGHTS_FIRST + 6])
    assert_equal(flat[first_map + SHADOW_INTENSITY_AT], Float32(0.4))
    var second_map = Int(flat[LIGHTS_FIRST + DIRECTIONAL_FLOATS + 13])
    assert_equal(flat[second_map + SHADOW_INTENSITY_AT], Float32(1))
    # A light that is no cascade carries a span of zero.
    var bare = flatten_lights(Lighting(a_shadowed_scene(assets)))
    assert_equal(bare[LIGHTS_FIRST + CASCADE_AT + 2], Float32(0))
    assert_equal(bare[LIGHTS_FIRST + CASCADE_AT + 3], Float32(0))


def test_the_light_buffer_carries_the_rectangles_and_the_tables() raises:
    # The header counts the rectangles; each is twelve floats after the
    # spot lights; the two tables follow them, and the shadow maps follow
    # the tables. Without a rectangle, no table rides.
    var assets = Assets()
    var scene = a_shadowed_scene(assets)
    with_a_rectangle(scene, 0, 3, 0)
    scene.update()
    var renderer = Renderer(24, 18)
    var maps = renderer.shadow_maps(scene, assets)
    var lighting = Lighting(scene, shadows=maps^, ltc=load_ltc_tables())
    var flat = flatten_lights(lighting)
    assert_equal(flat[LIGHTS_RECT_COUNT], Float32(1))
    assert_equal(LIGHTS_RECT_COUNT, LIGHTS_PROBE - 1)
    assert_equal(RECT_FLOATS, 12)
    var first_rect = LIGHTS_FIRST + DIRECTIONAL_FLOATS + 15
    var first_table = first_rect + RECT_FLOATS
    var first_map = first_table + 2 * LTC_FLOATS
    assert_equal(flat[first_rect + 1], Float32(3))
    assert_equal(flat[first_rect + 3], Float32(1))
    assert_equal(flat[first_rect + 7], Float32(0.5))
    assert_equal(flat[first_rect + 9], Float32(1.5))
    assert_equal(flat[first_rect + 11], lighting.rect_radiances[0].b)
    assert_true(flat[first_rect + 11] < 1, "the radiance was not decoded")
    assert_equal(flat[first_table], lighting.ltc.first[0])
    assert_equal(flat[first_table + 3], lighting.ltc.first[3])
    assert_equal(flat[first_table + LTC_FLOATS], lighting.ltc.second[0])
    assert_equal(flat[LIGHTS_FIRST + 6], Float32(first_map))
    assert_equal(flat[first_map], Float32(48))
    var second_map = first_map + SHADOW_HEADER + 48 * 48
    assert_equal(
        flat[LIGHTS_FIRST + DIRECTIONAL_FLOATS + 13], Float32(second_map)
    )
    assert_equal(len(flat), second_map + SHADOW_HEADER + 32 * 32)
    var bare = flatten_lights(Lighting(a_shadowed_scene(assets)))
    assert_equal(bare[LIGHTS_RECT_COUNT], Float32(0))
    assert_equal(len(bare), first_rect)


def test_the_state_tables_carry_the_depth_color_and_stencil_state() raises:
    var state = RasterState(
        depth_func=GREATER_DEPTH,
        stencil_write=True,
        stencil_func=NOT_EQUAL_STENCIL_FUNC,
        stencil_ref=7,
        stencil_z_pass=INCREMENT_STENCIL_OP,
    )
    var corners = List[RasterVertex]()
    for _ in range(3):
        corners.append(_stenciled(0, 0, 0.5, Color(255, 0, 0), state))
    var table = triangle_state(corners)
    assert_equal(table[STATE_OPS], Int32(state.ops_word()))
    assert_equal(table[STATE_STENCIL], Int32(state.stencil_word()))
    var ends = List[RasterVertex]()
    ends.append(_stenciled(0, 0, 0.5, Color(255, 0, 0), state))
    ends.append(_stenciled(4, 0, 0.5, Color(255, 0, 0), state))
    var lined = line_state(ends)
    assert_equal(lined[LINE_STATE_OPS], Int32(state.ops_word()))
    assert_equal(lined[LINE_STATE_STENCIL], Int32(state.stencil_word()))
    var dots = point_state(
        [_stenciled(0, 0, 0.5, Color(255, 0, 0), state, size=2)]
    )
    assert_equal(dots[POINT_STATE_OPS], Int32(state.ops_word()))
    assert_equal(dots[POINT_STATE_STENCIL], Int32(state.stencil_word()))
    # And each unpacks to the state it came from.
    assert_true(
        RasterState.unpacked(Int(table[STATE_OPS]), Int(table[STATE_STENCIL]))
        == state
    )


def test_the_baked_lanes_and_columns_ride_last() raises:
    var corners = baked_pair(LAMBERT, TextureId(2), TextureId(3))
    corners[0].u1 = 0.25
    corners[0].v1 = 0.75
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX * 6)
    assert_equal(flat[LANE_U1], Float32(0.25))
    assert_equal(flat[LANE_V1], Float32(0.75))
    assert_equal(LANE_V1, LANE_U1 + 1)
    assert_equal(flat[LANE_AO_INTENSITY], Float32(0.8))
    assert_equal(flat[LANE_LIGHT_MAP_INTENSITY], Float32(1.5))
    assert_equal(LANE_LOG_DEPTH, LANE_LIGHT_MAP_INTENSITY + 1)
    assert_equal(LANE_LOG_DEPTH, LANE_TRANSMISSION - 1)
    assert_equal(LANE_REFERENCE_X, LANE_IOR + 1)
    var state = triangle_state(corners)
    assert_equal(len(state), 2 * STATE_PER_TRIANGLE)
    assert_equal(state[STATE_AO_MAP], Int32(2))
    assert_equal(state[STATE_LIGHT_MAP], Int32(3))
    assert_equal(STATE_SPECULAR_MAP, STATE_TRANSMISSION_MAP - 1)
    assert_equal(STATE_THICKNESS_MAP, STATE_DEPTH_PACKING - 1)
    # A corner that says nothing names neither map, at intensities of one.
    var plain = flatten([RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1))])
    assert_equal(plain[LANE_AO_INTENSITY], Float32(1))
    assert_equal(plain[LANE_LIGHT_MAP_INTENSITY], Float32(1))
    var none = triangle_state(
        [
            RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1)),
            RasterVertex(1, 0, 0, 1, FloatColor(1, 1, 1)),
            RasterVertex(0, 1, 0, 1, FloatColor(1, 1, 1)),
        ]
    )
    assert_equal(none[STATE_AO_MAP], Int32(NO_TEXTURE.value))
    assert_equal(none[STATE_LIGHT_MAP], Int32(NO_TEXTURE.value))


def test_the_state_tables_carry_the_depth_mode() raises:
    var state = RasterState(depth_mode=REVERSED_DEPTH)
    var corners = List[RasterVertex]()
    for _ in range(3):
        corners.append(_stenciled(0, 0, 0.5, Color(255, 0, 0), state))
    var table = triangle_state(corners)
    assert_true(
        RasterState.unpacked(Int(table[STATE_OPS]), Int(table[STATE_STENCIL]))
        == state
    )


def test_the_light_buffer_carries_the_camera_s_back_axis() raises:
    var scene = Scene()
    scene.update()
    var lighting = Lighting(scene, back=Vector3(0, 0, -2))
    var flat = flatten_lights(lighting)
    assert_equal(flat[LIGHTS_BACK], Float32(0))
    assert_equal(flat[LIGHTS_BACK + 1], Float32(0))
    assert_equal(flat[LIGHTS_BACK + 2], Float32(-1))
    # The attachments ride after the depth, each in a plane of its own.
    assert_equal(PLANE_COLOR, 1)
    assert_equal(PLANE_NORMAL, PLANE_COLOR + 4)
    assert_equal(PLANE_DATA, PLANE_NORMAL + 3)
    assert_equal(PLANE_FLOATS, PLANE_DATA + 1)


def test_flattening_lays_a_pmrem_row_after_the_faces() raises:
    var flat = flatten_textures(TextureStore(), a_pmrem_store())
    ref table = flat[1]
    # Two cubes of eight rows.
    assert_equal(len(table), 16 * TABLE_COLUMNS)
    # The first cube's seventh row is its PMREM: floats, 336 by 64.
    var layout = 6 * TABLE_COLUMNS
    assert_equal(table[layout + 1], Int32(336))
    assert_equal(table[layout + 2], Int32(64))
    assert_equal(table[layout + 9], Int32(FLOAT_TYPE.value))
    assert_equal(
        table[layout + TABLE_MAPPING], Int32(CUBE_UV_REFLECTION_MAPPING.value)
    )
    # The second cube has none: one white byte texel.
    var none = 14 * TABLE_COLUMNS
    assert_equal(table[none + 1], Int32(1))
    assert_equal(table[none + 9], Int32(UNSIGNED_BYTE_TYPE.value))
    # Nor a panorama: its row is one white texel with the cube's mapping.
    var bare = 15 * TABLE_COLUMNS
    assert_equal(table[bare + 1], Int32(1))
    assert_equal(
        table[bare + TABLE_MAPPING], Int32(CUBE_REFLECTION_MAPPING.value)
    )


def test_flattening_the_lights_carries_the_probes() raises:
    var lighting = probe_lighting()
    var flat = flatten_lights(lighting)
    assert_equal(LIGHTS_BACK, LIGHTS_PROBE + 27)
    assert_equal(LIGHTS_FIRST, LIGHTS_BACK + 3)
    for lane in range(27):
        assert_equal(flat[LIGHTS_PROBE + lane], lighting.probe.lanes[lane])
    # Band zero is the average light, which is not black.
    assert_true(flat[LIGHTS_PROBE] > 0)
    # With no probe, the 27 are zero.
    var plain = flatten_lights(phong_lighting())
    for lane in range(27):
        assert_equal(plain[LIGHTS_PROBE + lane], Float32(0))


def test_the_state_table_carries_the_specular_map() raises:
    var corners = with_specular_map(
        phong_pair(FloatColor(0.3, 0.3, 0.3), 30.0), TextureId(4)
    )
    var state = triangle_state(corners)
    assert_equal(len(state), 2 * STATE_PER_TRIANGLE)
    assert_equal(state[STATE_SPECULAR_MAP], Int32(4))
    assert_equal(state[STATE_PER_TRIANGLE + STATE_SPECULAR_MAP], Int32(4))
    var plain = triangle_state(phong_pair(FloatColor(0.3, 0.3, 0.3), 30.0))
    assert_equal(plain[STATE_SPECULAR_MAP], Int32(NO_TEXTURE.value))


def test_the_volume_lanes_and_columns_ride_last() raises:
    var corners = glass_pair(TextureId(4), TextureId(5), 2)
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX * 6)
    assert_equal(flat[LANE_TRANSMISSION], Float32(0.9))
    assert_equal(flat[LANE_THICKNESS_X], Float32(0.5))
    assert_equal(flat[LANE_THICKNESS_Z], Float32(0.3))
    assert_equal(flat[LANE_ATTENUATION_R], Float32(0.8))
    assert_equal(flat[LANE_ATTENUATION_B], Float32(0.3))
    assert_equal(flat[LANE_ATTENUATION_DISTANCE], Float32(0.7))
    assert_equal(flat[LANE_DISPERSION], Float32(2))
    assert_equal(flat[LANE_IOR], Float32(1.4))
    assert_equal(LANE_TRANSMISSION, LANE_LOG_DEPTH + 1)
    assert_equal(LANE_IOR, LANE_REFERENCE_X - 1)
    var state = triangle_state(corners)
    assert_equal(state[STATE_TRANSMISSION_MAP], Int32(4))
    assert_equal(state[STATE_THICKNESS_MAP], Int32(5))
    assert_equal(STATE_TRANSMISSION_MAP, STATE_SPECULAR_MAP + 1)
    assert_equal(STATE_THICKNESS_MAP, STATE_DEPTH_PACKING - 1)


def test_a_transmission_target_crosses_as_a_header_and_its_chain() raises:
    var scene = a_scene_behind()
    var bytes = flatten_transmission(scene)
    assert_equal(
        len(bytes), TRANSMISSION_HEADER * 4 + len(scene.image.data) * 4
    )
    var at = 12 * 4
    assert_equal(
        float_from_bytes(
            bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]
        ),
        Float32(0.5),
    )
    at = TRANSMISSION_WIDTH * 4
    assert_equal(
        float_from_bytes(
            bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]
        ),
        Float32(36),
    )
    at = TRANSMISSION_LEVELS * 4
    assert_equal(
        float_from_bytes(
            bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]
        ),
        Float32(scene.image.levels),
    )
    at = (TRANSMISSION_HEADER + 5) * 4
    assert_equal(
        float_from_bytes(
            bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]
        ),
        scene.image.data[5],
    )


def test_the_gpu_composer_runs_the_per_pixel_passes_on_the_device() raises:
    assert_true(runs_on_device(COPY))
    assert_true(runs_on_device(LUT))
    assert_true(runs_on_device(BOKEH))
    assert_false(runs_on_device(RENDER))
    assert_false(runs_on_device(SMAA))
    assert_false(runs_on_device(MASK))
    assert_true(runs_on_device(CUBE_TEXTURE))
    assert_true(runs_on_device(SAVE))
    assert_true(runs_on_device(SHADER))
    assert_true(runs_on_device(SHADER_EFFECT))
    assert_true(runs_on_device(GOD_RAYS))
    assert_false(runs_on_device(RENDER_PIXELATED))
    assert_false(runs_on_device(GTAO))
    assert_false(runs_on_device(RENDER_TRANSITION))
    assert_false(runs_on_device(PassKind(60)))


def test_the_depth_packing_the_range_and_the_fog_switch_cross() raises:
    # Five lanes for the range, one column for the packing, and one each in
    # the three state tables for the fog switch.
    assert_equal(LANE_REFERENCE_X, LANE_IOR + 1)
    assert_equal(LANE_REFERENCE_Y, LANE_REFERENCE_X + 1)
    assert_equal(LANE_REFERENCE_Z, LANE_REFERENCE_Y + 1)
    assert_equal(LANE_NEAR_DISTANCE, LANE_REFERENCE_Z + 1)
    assert_equal(LANE_FAR_DISTANCE, LANE_NEAR_DISTANCE + 1)
    var corners = packed_pair(DISTANCE, BASIC_DEPTH_PACKING)
    var flat = flatten(corners)
    assert_equal(flat[LANE_REFERENCE_X], Float32(0.5))
    assert_equal(flat[LANE_REFERENCE_Y], Float32(0.25))
    assert_equal(flat[LANE_REFERENCE_Z], Float32(1))
    assert_equal(flat[LANE_NEAR_DISTANCE], Float32(1))
    assert_equal(flat[LANE_FAR_DISTANCE], Float32(9))
    var depth = packed_pair(DEPTH, RGB_DEPTH_PACKING)
    depth[0].fog = False
    var state = triangle_state(depth)
    assert_equal(STATE_FOG, STATE_SHEEN_COLOR_MAP - 1)
    assert_equal(state[STATE_DEPTH_PACKING], Int32(RGB_DEPTH_PACKING.value))
    assert_equal(state[STATE_FOG], Int32(0))
    assert_equal(state[STATE_PER_TRIANGLE + STATE_FOG], Int32(1))
    var ends = a_varying_line(
        2.5, 13.5, FloatColor(1, 1, 1), FloatColor(1, 1, 1)
    )
    ends[0].fog = False
    ends[1].fog = False
    var lined = line_state(ends)
    assert_equal(LINE_STATE_FOG, STATE_PER_LINE - 1)
    assert_equal(lined[LINE_STATE_FOG], Int32(0))
    var dot = a_point(4.5, 4.5, 3, 0.5, Color(255, 255, 255))
    var dots = point_state([dot])
    assert_equal(POINT_STATE_FOG, STATE_PER_POINT - 1)
    assert_equal(dots[POINT_STATE_FOG], Int32(1))


def test_the_layer_lanes_and_columns_ride_last() raises:
    var layers = LayerFactors()
    layers.sheen_color = Vector3(0.1, 0.2, 0.3)
    layers.sheen_roughness = 0.4
    layers.iridescence = 0.5
    layers.iridescence_ior = 1.6
    layers.thickness_minimum = 50
    layers.thickness_maximum = 700
    layers.anisotropy = Vector2(0.25, -0.5)
    layers.sheen_color_map = TextureId(1)
    layers.sheen_roughness_map = TextureId(2)
    layers.iridescence_map = TextureId(3)
    layers.thickness_map = TextureId(4)
    layers.anisotropy_map = TextureId(5)
    var corners = with_gpu_layers(physical_pair(PHYSICAL, 0.5, 0.5), layers)
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX * 6)
    assert_equal(flat[LANE_SHEEN_R], Float32(0.1))
    assert_equal(flat[LANE_SHEEN_G], Float32(0.2))
    assert_equal(flat[LANE_SHEEN_B], Float32(0.3))
    assert_equal(flat[LANE_SHEEN_ROUGHNESS], Float32(0.4))
    assert_equal(flat[LANE_IRIDESCENCE], Float32(0.5))
    assert_equal(flat[LANE_IRIDESCENCE_IOR], Float32(1.6))
    assert_equal(flat[LANE_THICKNESS_MINIMUM], Float32(50))
    assert_equal(flat[LANE_THICKNESS_MAXIMUM], Float32(700))
    assert_equal(flat[LANE_ANISOTROPY_X], Float32(0.25))
    assert_equal(flat[LANE_ANISOTROPY_Y], Float32(-0.5))
    assert_equal(LANE_SHEEN_R, LANE_FAR_DISTANCE + 1)
    assert_equal(LANE_ANISOTROPY_Y, LANE_SPECULAR_COLOR_R - 1)
    var state = triangle_state(corners)
    assert_equal(len(state), 2 * STATE_PER_TRIANGLE)
    assert_equal(state[STATE_SHEEN_COLOR_MAP], Int32(1))
    assert_equal(state[STATE_SHEEN_ROUGHNESS_MAP], Int32(2))
    assert_equal(state[STATE_IRIDESCENCE_MAP], Int32(3))
    assert_equal(state[STATE_FILM_THICKNESS_MAP], Int32(4))
    assert_equal(state[STATE_ANISOTROPY_MAP], Int32(5))
    assert_equal(STATE_SHEEN_COLOR_MAP, STATE_FOG + 1)
    assert_equal(STATE_ANISOTROPY_MAP, STATE_NODES - 1)
    # A corner that says nothing carries three.js's defaults and no map.
    var plain = flatten([RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1))])
    assert_equal(plain[LANE_SHEEN_ROUGHNESS], Float32(1))
    assert_equal(plain[LANE_IRIDESCENCE_IOR], Float32(1.3))
    assert_equal(plain[LANE_THICKNESS_MAXIMUM], Float32(400))
    assert_equal(plain[LANE_ANISOTROPY_X], Float32(0))
    var none = triangle_state(physical_pair(PHYSICAL, 0.5, 0.5))
    assert_equal(none[STATE_SHEEN_COLOR_MAP], Int32(NO_TEXTURE.value))
    assert_equal(none[STATE_ANISOTROPY_MAP], Int32(NO_TEXTURE.value))


def test_the_node_column_rides_last_and_programs_follow_the_fog() raises:
    var store = NodeProgramStore()
    var first = NodeGraph()
    first.set_output(NODES_COLOR, first.vec3(1, 0, 0))
    _ = store.add(first.compile())
    var second = NodeGraph()
    second.set_output(NODES_OPACITY, second.float(0.5))
    _ = store.add(second.compile())
    var starts = program_starts(store)
    assert_equal(starts[0], FOG_FLOATS)
    assert_equal(starts[1], FOG_FLOATS + len(store.programs[0].code))
    var flat = flatten_programs(store)
    assert_equal(
        len(flat), len(store.programs[0].code) + len(store.programs[1].code)
    )
    assert_equal(flat[starts[1] - FOG_FLOATS], store.programs[1].code[0])
    assert_equal(len(program_starts(NodeProgramStore())), 0)
    var corners = with_nodes(overlapping_pair(), 1)
    corners[0].nodes = NodeProgramId(-1)
    corners[1].nodes = NodeProgramId(-1)
    corners[2].nodes = NodeProgramId(-1)
    var state = triangle_state(corners, 0, starts)
    assert_equal(STATE_NODES, STATE_SPECULAR_INTENSITY_MAP - 1)
    assert_equal(STATE_NODES, STATE_ANISOTROPY_MAP + 1)
    assert_equal(state[STATE_NODES], Int32(-1))
    assert_equal(state[STATE_PER_TRIANGLE + STATE_NODES], Int32(starts[1]))
    # A program past the layout, which a draw refuses first, reads none.
    assert_equal(
        triangle_state(with_nodes(overlapping_pair(), 5), 0, starts)[
            STATE_NODES
        ],
        Int32(-1),
    )


def test_the_specular_and_coat_lanes_and_columns_ride_last() raises:
    var layers = LayerFactors()
    layers.specular_color = Vector3(0.9, 0.5, 0.25)
    layers.clearcoat_normal_scale = Vector2(1.5, -0.75)
    layers.specular_intensity_map = TextureId(1)
    layers.specular_color_map = TextureId(2)
    layers.clearcoat_map = TextureId(3)
    layers.clearcoat_roughness_map = TextureId(4)
    layers.clearcoat_normal_map = TextureId(5)
    var corners = with_gpu_layers(physical_pair(PHYSICAL, 0.5, 0.5), layers)
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX * 6)
    assert_equal(flat[LANE_SPECULAR_COLOR_R], Float32(0.9))
    assert_equal(flat[LANE_SPECULAR_COLOR_G], Float32(0.5))
    assert_equal(flat[LANE_SPECULAR_COLOR_B], Float32(0.25))
    assert_equal(flat[LANE_CLEARCOAT_NORMAL_SCALE_X], Float32(1.5))
    assert_equal(flat[LANE_CLEARCOAT_NORMAL_SCALE_Y], Float32(-0.75))
    assert_equal(LANE_SPECULAR_COLOR_R, LANE_ANISOTROPY_Y + 1)
    assert_equal(LANE_CLEARCOAT_NORMAL_SCALE_Y, LANE_ENV_ROTATION - 1)
    var state = triangle_state(corners)
    assert_equal(len(state), 2 * STATE_PER_TRIANGLE)
    assert_equal(state[STATE_SPECULAR_INTENSITY_MAP], Int32(1))
    assert_equal(state[STATE_SPECULAR_COLOR_MAP], Int32(2))
    assert_equal(state[STATE_CLEARCOAT_MAP], Int32(3))
    assert_equal(state[STATE_CLEARCOAT_ROUGHNESS_MAP], Int32(4))
    assert_equal(state[STATE_CLEARCOAT_NORMAL_MAP], Int32(5))
    assert_equal(
        state[STATE_PER_TRIANGLE + STATE_CLEARCOAT_NORMAL_MAP], Int32(5)
    )
    assert_equal(STATE_SPECULAR_INTENSITY_MAP, STATE_NODES + 1)
    assert_equal(STATE_CLEARCOAT_NORMAL_MAP, STATE_NORMAL_MAP_TYPE - 1)
    # A corner that says nothing carries a white tint, a scale of one and
    # no map.
    var plain = flatten([RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1))])
    assert_equal(plain[LANE_SPECULAR_COLOR_G], Float32(1))
    assert_equal(plain[LANE_CLEARCOAT_NORMAL_SCALE_X], Float32(1))
    var none = triangle_state(physical_pair(PHYSICAL, 0.5, 0.5))
    assert_equal(none[STATE_SPECULAR_COLOR_MAP], Int32(NO_TEXTURE.value))
    assert_equal(none[STATE_CLEARCOAT_NORMAL_MAP], Int32(NO_TEXTURE.value))


def test_the_texture_table_carries_each_placement() raises:
    # The last seven columns of a texture's row are its placement: the six
    # numbers of the matrix, bit for bit, then the channel.
    var textures = TextureStore()
    _ = textures.add(a_gpu_data_map())
    var moved = a_gpu_data_map()
    moved.repeat = Vector2(2, -3)
    moved.offset = Vector2(0.25, 0.5)
    moved.rotation = Angle(30.0, DEGREE)
    moved.center = Vector2(0.5, 0.5)
    moved.channel = UV_CHANNEL_1
    var expected = moved.placement()
    _ = textures.add(moved^)
    var table = flatten_textures(textures)[1].copy()
    assert_equal(len(table), 2 * TABLE_COLUMNS)
    assert_equal(TABLE_COLUMNS, TABLE_PLACEMENT + 7)
    var row = TABLE_COLUMNS + TABLE_PLACEMENT
    assert_equal(bitcast[DType.float32](table[row]), expected.xx)
    assert_equal(bitcast[DType.float32](table[row + 1]), expected.xy)
    assert_equal(bitcast[DType.float32](table[row + 2]), expected.x0)
    assert_equal(bitcast[DType.float32](table[row + 3]), expected.yx)
    assert_equal(bitcast[DType.float32](table[row + 4]), expected.yy)
    assert_equal(bitcast[DType.float32](table[row + 5]), expected.y0)
    assert_equal(table[row + 6], Int32(UV_CHANNEL_1.value))
    # A texture that says nothing is the identity on the first set.
    assert_equal(bitcast[DType.float32](table[TABLE_PLACEMENT]), Float32(1))
    assert_equal(bitcast[DType.float32](table[TABLE_PLACEMENT + 1]), Float32(0))
    assert_equal(bitcast[DType.float32](table[TABLE_PLACEMENT + 4]), Float32(1))
    assert_equal(table[TABLE_PLACEMENT + 6], Int32(UV_CHANNEL_0.value))


def test_the_texture_table_carries_the_sampler_and_the_mapping() raises:
    var textures = TextureStore()
    var image = checkerboard(
        8, 2, Color(240, 60, 20), Color(20, 40, 200), REPEAT, BILINEAR
    )
    image.wrap_t = MIRROR
    image.mag_filter = NEAREST
    image.min_filter = LINEAR_MIPMAP_NEAREST
    image.flip_y = False
    image.mapping = EQUIRECTANGULAR_REFLECTION_MAPPING
    _ = textures.add(image^)
    var cubes = CubeTextureStore()
    _ = cubes.add(
        cube_of_panorama(a_gpu_panorama(EQUIRECTANGULAR_REFRACTION_MAPPING))
    )
    var refracting = a_gpu_cube()
    refracting.mapping = CUBE_REFRACTION_MAPPING
    _ = cubes.add(refracting^)
    var flat = flatten_textures(textures, cubes)
    ref table = flat[1]
    assert_equal(len(table), (1 + 2 * CUBE_ROWS) * TABLE_COLUMNS)
    assert_equal(TABLE_PLACEMENT, TABLE_MAPPING + 1)
    assert_equal(table[3], Int32(REPEAT.value))
    assert_equal(table[4], Int32(NEAREST.value))
    assert_equal(table[TABLE_WRAP_T], Int32(MIRROR.value))
    assert_equal(table[TABLE_MIN_FILTER], Int32(LINEAR_MIPMAP_NEAREST.value))
    assert_equal(table[TABLE_FLIP_Y], Int32(0))
    assert_equal(
        table[TABLE_MAPPING], Int32(EQUIRECTANGULAR_REFLECTION_MAPPING.value)
    )
    # The first cube's panorama row: the panorama, with the cube's mapping.
    var panorama = (1 + CUBE_PANORAMA) * TABLE_COLUMNS
    assert_equal(table[panorama + 1], Int32(6))
    assert_equal(table[panorama + TABLE_FLIP_Y], Int32(1))
    assert_equal(
        table[panorama + TABLE_MAPPING],
        Int32(EQUIRECTANGULAR_REFRACTION_MAPPING.value),
    )
    # The second cube has none: one white texel carrying its mapping.
    var bare = (1 + CUBE_ROWS + CUBE_PANORAMA) * TABLE_COLUMNS
    assert_equal(table[bare + 1], Int32(1))
    assert_equal(
        table[bare + TABLE_MAPPING], Int32(CUBE_REFRACTION_MAPPING.value)
    )


def test_flattening_carries_the_blend_constant() raises:
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            state=RasterState(
                blend_red=0.25, blend_green=0.5, blend_blue=0.75, blend_alpha=1
            ),
        )
    )
    var flat = flatten(corners)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[LANE_BLEND_CONSTANT], Float32(0.25))
    assert_equal(flat[LANE_BLEND_CONSTANT + 1], Float32(0.5))
    assert_equal(flat[LANE_BLEND_CONSTANT + 2], Float32(0.75))
    assert_equal(flat[LANE_BLEND_CONSTANT + 3], Float32(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
