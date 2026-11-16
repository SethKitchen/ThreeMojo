# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draws a scene through a camera, the counterpart to three.js's renderers.

The loop here is the one both cube examples had grown by hand: take each
mesh's world transform, project its vertices, and rasterize its triangles with
depth. Having it in one place is what lets an example say `render(scene,
assets, camera)` instead of spelling all that out.

Lighting is evaluated per *fragment*: what a corner carries is a world-space
normal, which is interpolated across the triangle and made unit length again
at every pixel before the lights are summed. A geometry's `normal` attribute
decides how it looks: a
box gives each of a face's four corners that face's own normal, so the four
agree and the face comes out flat with a crisp edge; a sphere gives each
vertex the direction it points from the center, so neighboring triangles
agree along their shared edge and the facets disappear.

A geometry with no normals falls back to the triangle's *geometric* normal,
computed from its own world-space corners with a cross product. That is always
faceted, which is the honest result for geometry that never said which way it
faces.

Normals are carried by the world matrix's *normal matrix* — the inverse
transpose of its rotation and scale part — rather than by the world matrix
itself. Under a uniform scale the two agree up to a length that normalizing
removes, which is why the simpler version worked for as long as it did. Under
a non-uniform scale they do not: `Object3D.set_scale` takes three separate
factors, so the transform API could always reach a state the naive version
shaded wrongly. It is computed once per mesh, not once per vertex.

Vertices are taken into camera space and cut against the near and far planes
*before* being projected. Projecting first would divide by a depth of zero or a
negative one for anything level with or behind the camera, which does not
produce a slightly wrong triangle but a wildly wrong one. The far plane is cut
too, because the depth buffer cannot enforce it on its own: it clears to
infinity and accepts anything smaller, so geometry past `camera.far` would
otherwise still be drawn. See `renderers.clip`.

A mesh whose world transform reflects it — a negative scale on one axis, or
any odd number of them inherited down the hierarchy — has its winding reversed,
and both the culling convention and the geometric-normal fallback are turned
upside down with it. The sign of the world matrix's determinant is what says
so, and it is asked once per mesh. three.js asks the same question of the same
quantity.

Triangles facing away from the camera are discarded before rasterization,
which is an optimization rather than a correctness fix — the depth buffer
already hides them, and did so alone for several versions. It is switchable
because a camera inside a closed mesh sees nothing but back faces, and that is
a legitimate thing to want; three.js expresses the same choice as a material's
`side`, which is where this belongs once `Material` exists.

Whole meshes are discarded earlier still, before a vertex of them is
transformed or clipped. Each geometry's bounding sphere is read off its
positions once per frame, carried to world space for each mesh that draws
it, and tested against the camera's frustum, three.js's `frustumCulled`; a
mesh wholly outside is left out of the draw order. It too is an
optimization and not a correctness fix: every triangle of such a mesh is
clipped away or lands off the image, so the frame is the same with the test
and without. What the test saves is the transform, the clip and the
projection of every one of those triangles, for the price of two passes
over the positions and six dot products. A mesh can opt out with
`Mesh.frustum_culled`, and the renderer's own tests do, to show the image
does not change.

Two things keep that promise at the edges. The frustum's near and far
planes are built from the camera's own distances, the numbers the clipper
is given, rather than read back off the projection, where rounding can
leave the far plane meters short; see `Frustum.from_camera`. And a sphere
is kept when it comes within a millionth of the far distance of any plane,
so that a mesh the culler and the clipper measure by different roundings
of the same view is left for the clipper to decide. Keeping a mesh costs
work; dropping one changes the image.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.
"""

from math.triangle_normal import normal_or_zero

from renderers.render_list import (
    RenderItem,
    RenderSort,
    _Source,
    _Span,
    _opaque_then_blended,
    _sort_by,
    _span_draw_order,
    _sort_with,
    _furthest_first,
    _add_run,
)

from render.color_spaces import (
    ColorSpaceId,
    OutputEncoding,
    SRGB_COLOR_SPACE,
    output_encoding,
)
from cameras.array_camera import ArrayCamera
from cameras.camera import Camera
from cameras.cube_camera import CubeCamera
from core.background import COLOR_BACKGROUND, TEXTURE_BACKGROUND, Background
from core.deform import (
    SkinPose,
    displaced_positions,
    morphed_colors,
    morphed_normals,
    morphed_positions,
    skin_carriers,
    skin_pose,
)
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
    UV1,
    BufferGeometry,
    GeometryGroup,
    require_vertex_index,
    MaterialIndex,
)
from core.assets import Assets
from core.extent import require_positive_extent
from core.geometry_store import GeometryId
from core.fog import FogView
from lights.light import (
    ALL_LIGHTS,
    DIRECTIONAL,
    IES_SPOT,
    POINT,
    PROJECTOR_SPOT,
    Light,
    LightMask,
)
from lights.light_slot import index_of_light
from lights.lighting import PERSPECTIVE_VIEW, Lighting
from lights.shadow import (
    CUBE_FACES,
    PCF_SHADOW_MAP,
    VSM_SHADOW_MAP,
    ShadowMap,
    ShadowMapType,
    require_shadow_type,
    SpotLightMap,
    cube_direction,
    cube_stored,
    cube_up,
    vsm_moments,
)
from lights.ltc import LtcTables
from lights.light_probe_grid import LightProbeGrid
from lights.projector_light import projector_aspect
from lights.spot_profile import SpotProfile, needs_profile
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.layers import Layers
from core.morph import MorphInfluences
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from core.search import first_match
from math.bounds import Plane, Sphere
from math.frustum import Frustum
from math.matrix3 import Matrix3
from render.rect import Rect
from render.splatrule import ProjectedSplat
from render.splat_raster import prepare_gaussian_splat
from render.rasterizer import (
    DRAW_SPLATS,
    Corner,
    _raise_band_errors,
    Surface,
    corner_of,
    joined,
    surface_of,
    DRAW_POINTS,
    DRAW_SEGMENTS,
    SHADE_LIT,
    SHADE_SHADOW,
    SHADE_TEXTURE,
    SHADE_UV,
    DRAW_TRIANGLES,
    Draw,
    DrawKind,
    LayerFactors,
    RasterVertex,
    ShadeMode,
    require_shade_mode,
    TextureFrames,
    check_alpha_data_map,
    check_alpha_map,
    check_channel,
    check_color_map,
    check_data_map,
    check_gradient_map,
    check_light_map,
    check_output_kinds,
    edge,
    rasterize_frame,
)
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3, mix_delta3
from math.utils import (
    mix_delta,
    texel_center,
    texel_center_from_end,
    texel_ndc,
    texel_ndc_up,
)
from objects.instanced_mesh import BatchedDrawItem, BatchedMesh, check_placing
from geometries.edges import triangle_edges
from objects.line import (
    CONDITIONAL_DASH,
    CONDITIONAL_GAP,
    CONTROL0,
    CONTROL1,
    DIRECTION,
    SEGMENTS,
    conditional_discard,
    line_distances,
    segment_count,
    segment_ends,
)
from objects.line_segments2 import (
    LineCoverage,
    require_line_coverage,
    require_unindexed_wide_line,
    STRAND_LINE_COVERAGE,
    cap_steps,
    dash_spans,
    drawn_segments,
)
from objects.sprite import SPRITE_RADIUS, Sprite, sprite_place, sprite_span
from materials.material import (
    BACK_SIDE,
    BASIC,
    DEFAULT_LINE_WIDTH,
    DOUBLE_SIDE,
    FRONT_SIDE,
    GOURAUD,
    VOLUME,
    check_steps,
    require_strand_opacity,
    DEFAULT_IOR,
    MULTIPLY_OPERATION,
    NO_ATTENUATION,
    NO_DASH,
    NORMALS,
    OBJECT_SPACE_NORMAL_MAP,
    OPAQUE,
    PHYSICAL,
    SHADOW,
    Blending,
    Combine,
    Material,
    NO_SCATTERING,
    Scattering,
    MaterialId,
    MaterialKind,
    Side,
)
from render.antialias import SUPERSAMPLE
from render.cube_texture import (
    FACE_COUNT,
    Basis3,
    CubeTexture,
    cube_texture_of,
    env_rotation,
    equirect_uv,
    reflection_level,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from units.si import (
    Angle,
    DEGREE,
    Duration,
    Length,
    METER,
    NANOMETER,
    RADIAN,
    SECOND,
)
from materials.nodes import (
    NO_NODES,
    POSITION_NODE,
    SIZE_NODE,
    NodeInputs,
    NodeProgram,
    NodeProgramId,
    NodeProgramStore,
    moved_position,
    point_size_of,
)
from render.pointrule import attenuated_size
from render.texture import Texture
from render.texture_store import NO_TEXTURE, TextureId
from render.framebuffer import (
    Color,
    FloatColor,
    Framebuffer,
    SrgbBytes,
    append_float_color,
)
from render.layered_target import TARGET_CUBE, LayeredRenderTarget
from render.srgb import srgb_to_linear
from render.target import (
    RenderTarget,
    check_samples,
    require_rect,
    sample_grid,
)
from render.derivatives import (
    CAPSULE_EDGE_RAMP,
    DISC_EDGE_RAMP,
    NO_EDGE_RAMP,
)
from render.raster_state import (
    LOGARITHMIC_DEPTH,
    NO_OFFSET,
    STANDARD_DEPTH,
    DepthMode,
    PolygonOffset,
    require_depth_mode,
    RasterState,
    log_depth_factor,
)
from render.transmission import TransmissionTarget
from render.packing import DepthPacking
from render.tonemap import (
    CUSTOM_TONE_MAPPING,
    NO_TONE_MAPPING,
    ToneMapping,
    check_tone_mapping,
)
from math.vector2 import Vector2
from renderers.draw_filter import (
    ALL_DRAWS,
    DrawFilter,
    ONE_OIT_DRAW,
    check_draw_filter,
    kept_draws,
    oit_capable,
    snap_to_pixels,
)
from renderers.clip import (
    ClipVertex,
    clip_depth,
    clip_ordered,
    clip_segment,
    within_any,
    within_depth,
    within_sides,
)
from render.tasks import TaskGroup
from math.curve_checks import require_at_least_one
from math.finite import require_positive_finite
from std.math import cos, max, min, nextafter, pi, sin
from std.memory import ArcPointer, unsafe_memcpy
from std.sys import num_logical_cores
from core.ordinal import require_valid, require_positive


from renderers.renderer_prepare import (
    CULL_SLACK,
    Frame,
    NoHooks,
    PENDING_VERTICES,
    PIECE_TRIANGLES,
    RenderHooks,
    RenderInfo,
    WIDE_RUN_SEGMENTS,
    _BackdropRays,
    _CameraFrame,
    _Draw,
    _Paint,
    _Physics,
    _Piece,
    _Placed,
    _RendererState,
    _Ribbon,
    _Shown,
    _Slim,
    _TriangleJob,
    _WideRun,
    _adopt,
    _backdrop_band,
    _between,
    _brightened,
    _carriers,
    _casts,
    _check_map_channels,
    _checked_data_map,
    _checked_light_map,
    _checked_maps,
    _checked_nodes,
    _checked_scattering,
    _clip_draw,
    _clip_of,
    _clip_sets,
    _coordinates,
    _customs,
    _displaces,
    _draw_offset,
    _draw_state,
    _drawn_material,
    _draws,
    _emit_cap,
    _emit_clipped,
    _emit_jobs,
    _emit_pieces,
    _emit_placed,
    _emit_sprite,
    _emit_square_cap,
    _emit_strand_cap,
    _emit_strand_segment,
    _emit_wide_line,
    _env_intensity,
    _faces_away,
    _frames_of,
    _gather,
    _gather_batch,
    _group_clip_sets,
    _has_transmissive_back,
    _in_view,
    _instancing,
    _is_see_through,
    _layer_factors,
    _light_aim,
    _light_at_corner,
    _line_corner,
    _looks_behind,
    _march_volume,
    _mask_place,
    _moves,
    _moves_a_map,
    _named_maps,
    _needs_volume_depth,
    _negated,
    _note_span,
    _object_place,
    _opaque_draws,
    _paint_backdrop,
    _panorama_seen,
    _place_corners,
    _place_renamed,
    _plane_in_view,
    _planes_in_view,
    _ramp_corner,
    _reads_scene,
    _refuse_nodes,
    _resolved_env,
    _same_place,
    _scaled,
    _set_backdrop,
    _shown_of,
    _sky_seen,
    _spot_camera,
    _stored_map,
    _strand_corner,
    _strand_profile,
    _to_raster,
    _transmits,
    _turned_around,
    _vertex_colors,
    _whole_in_view,
    _wide_segments,
    _wide_task,
    _with_opacity,
    available_workers,
    camera_back,
    camera_position,
    camera_up,
    face_normal,
    light_masks,
    require_material_alpha,
    require_material_texture,
    require_named_map,
    require_renderer_workers,
    toward_camera,
)


struct Renderer(Movable):
    """Renders a scene to a framebuffer of a fixed size."""

    var width: Int
    var height: Int
    var background: Color
    # What a fragment's color comes from. `SHADE_TEXTURE` is the default and
    # means "follow the material": a material with a map is sampled, one
    # without is not, which is what three.js does by having a map at all.
    # `SHADE_LIT` and `SHADE_UV` are overrides for looking at something —
    # ignore every texture, or draw texture coordinates instead of color.
    var shading: ShadeMode
    # How many threads rasterize a frame. One by default, deliberately: the
    # coverage tool reconstructs MC/DC vectors from the *order* probe
    # records arrive in, and two threads reporting the same decision at once
    # would interleave them. Everything that wants speed rather than
    # measurement -- the examples, the benchmark -- asks for
    # `available_workers()`.
    var workers: Int
    # The curve that compresses each finished pixel's light into what a
    # display can show, and what the light is scaled by first: three.js's
    # `toneMapping` and `toneMappingExposure`, at three.js's defaults of
    # none and one. Applied by `RenderTarget.resolve`, once, to the
    # composited image -- see `render.tonemap`.
    var tone_mapping: ToneMapping
    var tone_mapping_exposure: Float32
    # A material that takes the place of every object's while it is set,
    # before the scene's own `override_material`: what three.js's
    # `RenderPass` puts on the scene for its draw. None by default.
    var override_material: Optional[MaterialId]
    # The space the finished image is written in, three.js's
    # `outputColorSpace`: sRGB unless `set_output_color_space` says
    # otherwise. See `render.color_spaces.output_encoding`.
    var output_color_space: ColorSpaceId
    # Where on the target the camera's image lands: three.js's
    # `setViewport`. The whole target by default. Folded into the screen
    # matrix by `prepare` and `prepare_lines`, so both backends draw the
    # same pixels. The corner counts up from the bottom; see `render.rect`.
    var viewport: Rect
    # Which pixels a draw may touch, and whether that is enforced:
    # three.js's `setScissor` and `setScissorTest`. Off by default, as
    # there. With the test on, `render_into` clears and draws inside the
    # scissor alone, which is what lets several viewports share one
    # target.
    var scissor: Rect
    var scissor_test: Bool
    # Whether `render`, `render_array` and `render_cube` draw at twice the size
    # each way and average every four pixels into one: three.js's
    # `antialias`, by supersampling. Off by default, as there. See
    # `render.antialias` and `set_antialias`.
    var antialias: Bool
    # How many raster pixels of this renderer stand for one pixel of the
    # image the caller asked for. One in every renderer a caller builds,
    # and `SUPERSAMPLE` in the one `supersampled` returns.
    #
    # **It is the boundary between two kinds of pixel, and everything
    # measured in pixels has to cross it exactly once.** A world-space
    # length does not: a triangle is projected onto whatever grid it is
    # drawn on and comes out the right size either way. A length given in
    # pixels does: a `PointsMaterial` size, and the one-pixel thickness of
    # a line. Those used to cross it zero times, so turning `antialias`
    # on halved a line and quartered a point's area -- the setting changed
    # what the objects *were*, not just how cleanly their edges were
    # drawn. `attenuated_size` takes it for the points and
    # `rasterize_frame` for the lines, and both take it once.
    #
    # Not a public setting: a caller asks for anti-aliasing and this
    # follows from it. `render_into` draws into a target the caller holds,
    # at that target's size, so a renderer a caller built has a scale of
    # one whatever its `antialias` says.
    var render_scale: Int
    # The tables a rect area light is evaluated with, or none until
    # `set_ltc_tables`.
    var ltc: LtcTables
    # The box of light probes every lit surface adds, three.js's
    # `LightProbeGrid`, or an empty grid until `set_light_probe_grid`.
    var probe_grid: LightProbeGrid
    # Planes in world space that cut away what lies behind any of them,
    # from every mesh, line, point and sprite, three.js's
    # `clippingPlanes`. None by default. They do not cut shadows, as
    # three.js's do not.
    var clipping_planes: List[Plane]
    # True to let each material's own planes cut it, three.js's
    # `localClippingEnabled`. False by default, as there.
    var local_clipping_enabled: Bool
    # Which filter the shadow maps are read with, three.js's
    # `shadowMap.type`. `PCF_SHADOW_MAP` by default, as there. See
    # `lights.shadow`.
    var shadow_map_type: ShadowMapType
    # Whether the shadow pass keeps the color a light sees through each
    # caster, three.js's `shadowMap.transmitted`: opaque black, or the
    # material's `CAST_SHADOW_NODE`, thinned by its maps' alpha. False by
    # default, as there. See `lights.shadow.transmitted_shadow`.
    var shadow_map_transmitted: Bool
    # How a frame's depth is stored and compared: three.js's
    # `logarithmicDepthBuffer` and `reversedDepthBuffer`, as one value.
    # `STANDARD_DEPTH` by default, as there. See `set_depth_mode`.
    var depth_mode: DepthMode
    # How long the animation has run, what a node graph's `time` node reads
    # and a position node's offset can follow: three.js's `NodeFrame.time`.
    # Zero by default. The caller moves it on between frames.
    var time: Duration
    # Whether `render_into` clears the target before it draws, and which
    # of its buffers: three.js's `autoClear`, `autoClearColor`,
    # `autoClearDepth` and `autoClearStencil`, all on by default as there.
    # Off, the frame draws over what the target holds; `clear` clears it
    # by hand.
    var auto_clear: Bool
    # The scene's meshes, by their place in `scene.meshes`, to draw in the
    # space of their second texture coordinates and nothing else: what
    # `ProgressiveLightMap` draws its light map with, three.js's
    # `gl_Position = vec4((uv1 - 0.5) * 2.0, 1.0, 1.0)`. No background,
    # line or point is drawn. Empty, the default, draws the scene through
    # the camera.
    var uv_space_meshes: List[Int]
    var auto_clear_color: Bool
    var auto_clear_depth: Bool
    var auto_clear_stencil: Bool
    # The program `CUSTOM_TONE_MAPPING` maps each pixel through, or
    # `NO_NODES` for three.js's default custom curve, which leaves the
    # light as it is. See `render.tonemap.custom_tone_map`.
    var custom_tone_mapping: NodeProgramId
    # Whether each frame forgets the last one's counts, three.js's
    # `info.autoReset`. On by default, as there. See `info`.
    var info_auto_reset: Bool
    # The caller's sorts, three.js's `setOpaqueSort` and
    # `setTransparentSort`, or none for this renderer's own order.
    var _opaque_sort: Optional[RenderSort]
    var _transparent_sort: Optional[RenderSort]
    # Which of a frame's draws `render_into` draws, and which
    # order-independent draw `ONE_OIT_DRAW` keeps: what three.js's
    # `OITPassNode` sets with `setRenderObjectFunction`. Every draw by
    # default. See `renderers.draw_filter`.
    var draw_filter: DrawFilter
    var oit_draw: Int
    # Whether each corner is rounded to a whole pixel from the center
    # before it is drawn, three.js's `RetroPassNode` vertex node. Off by
    # default.
    var snap_vertices: Bool
    # What the renderer counts while it draws, shared with a supersampled
    # twin; see `_RendererState`.
    var _state: ArcPointer[_RendererState]

    def __init__(out self, width: Int, height: Int, workers: Int = 1) raises:
        """Create a renderer with a dark background.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            workers: How many threads rasterize a frame; see `set_workers`.

        Raises:
            Error: If either dimension is not positive, or `workers` is.
        """
        require_positive_extent(
            width, height, "Renderer dimensions must be positive"
        )
        require_renderer_workers(workers)
        self.width = width
        self.height = height
        self.background = Color(16, 18, 26)
        self.shading = SHADE_TEXTURE
        self.workers = workers
        self.tone_mapping = NO_TONE_MAPPING
        self.tone_mapping_exposure = 1.0
        self.output_color_space = SRGB_COLOR_SPACE
        self.override_material = None
        self.viewport = Rect.whole(width, height)
        self.scissor = Rect.whole(width, height)
        self.scissor_test = False
        self.antialias = False
        self.render_scale = 1
        self.ltc = LtcTables()
        self.probe_grid = LightProbeGrid.none()
        self.clipping_planes = List[Plane]()
        self.local_clipping_enabled = False
        self.shadow_map_type = PCF_SHADOW_MAP
        self.shadow_map_transmitted = False
        self.depth_mode = STANDARD_DEPTH
        self.time = Duration(0.0, SECOND)
        self.auto_clear = True
        self.uv_space_meshes = List[Int]()
        self.auto_clear_color = True
        self.auto_clear_depth = True
        self.auto_clear_stencil = True
        self.custom_tone_mapping = NO_NODES
        self.info_auto_reset = True
        self._opaque_sort = None
        self._transparent_sort = None
        self.draw_filter = ALL_DRAWS
        self.oit_draw = 0
        self.snap_vertices = False
        self._state = ArcPointer(_RendererState())

    def set_opaque_sort(mut self, method: Optional[RenderSort]):
        """Order the opaque runs by `method`, three.js's `setOpaqueSort`.

        The function is asked of two runs and answers True when the first
        is drawn first. It orders every opaque run of every kind together,
        stably. `None` puts back this renderer's own order: the triangles,
        then the segments, then the points, each nearest first.

        Args:
            method: The function, or `None`.
        """
        self._opaque_sort = method

    def set_transparent_sort(mut self, method: Optional[RenderSort]):
        """Order the transmissive runs and the blended runs by `method`,
        three.js's `setTransparentSort`.

        Each of the two lists is sorted on its own, stably, as three.js
        sorts its `transmissive` and `transparent` lists. `None` puts back
        this renderer's own order: render order, then furthest first.

        Args:
            method: The function, or `None`.
        """
        self._transparent_sort = method

    def info(self) -> RenderInfo:
        """Return what the renderer drew, three.js's `renderer.info.render`.

        Counted by `render_into` and everything that calls it. A run is a
        call. Its triangles, segments or points are the ones the
        rasterizer receives: after the faces turned away are culled and
        the clipper has cut, where three.js counts what it submits. The
        transmission pass, the shadow maps and the background are not
        counted.

        Returns:
            The counts.
        """
        return self._state[].info

    def reset_info(self):
        """Forget the draws counted so far, three.js's `info.reset`. The
        frame count is kept."""
        self._state[].reset()

    def set_antialias(mut self, enabled: Bool):
        """Turn supersampling on or off, three.js's `antialias`.

        On, `render`, `render_array` and `render_cube` draw the frame at
        `SUPERSAMPLE` times the size each way and average every block into
        one output pixel. The average is taken on the linear render target,
        before the tone mapping and the sRGB encode, so what is averaged is
        the scene's light rather than a picture of it; see
        `render.antialias` and `RenderTarget.downsampled`.

        The viewport and the scissor are given in output pixels and scaled
        with the frame, and so are the two sizes a caller gives in pixels:
        a point's size and a line's thickness come out as asked, not
        smaller. See `render_scale`.

        `render_into`, `render_array_into`, `render_into_layer` and
        `render_cube_into` use the target's sample count instead. This
        setting does not add samples to those draws.

        Args:
            enabled: Whether to supersample.
        """
        self.antialias = enabled

    def supersampled(self) raises -> Renderer:
        """Return a renderer `SUPERSAMPLE` times this one's size each way,
        with the same settings, its viewport and scissor scaled to match,
        and no supersampling of its own.

        What `render` draws with when `antialias` is on, and what a caller
        drawing on the GPU uses to prepare a frame it will `downsample`
        itself. It is `scaled(SUPERSAMPLE)`; see `scaled` for why a
        point's size and a line's thickness come out the size they were
        asked for.

        Returns:
            The larger renderer.

        Raises:
            Error: If the larger renderer cannot be built.
        """
        return self.scaled(SUPERSAMPLE)

    def multisampled(self, samples: Int) raises -> Renderer:
        """Return the renderer a draw into a target with `samples` takes
        its samples with: `scaled(sample_grid(samples))`.

        What `render_into` draws with when its target has samples, and
        what a caller drawing on the GPU prepares a frame with before
        `GpuRenderer.read_back_target` resolves it. Pass its
        `render_scale` as the draw's `line_width`.

        Args:
            samples: The target's sample count; see
                `render.target.check_samples`.

        Returns:
            The larger renderer, or a copy of this one's settings at this
            size for zero or one sample.

        Raises:
            Error: If `check_samples` refuses the count, or the larger
                renderer cannot be built.
        """
        check_samples(samples)
        return self.scaled(sample_grid(samples))

    def _copy_draw_settings(self, mut other: Self):
        """Copy the draw settings that do not follow the frame size.

        The viewport, the scissor, the scissor test, antialias, and
        `render_scale` stay with the caller. A supersampled frame scales
        the rectangles and the scale. A resized frame keeps the whole
        target and copies antialias.
        """
        other.background = self.background
        other.shading = self.shading
        other.tone_mapping = self.tone_mapping
        other.tone_mapping_exposure = self.tone_mapping_exposure
        other.output_color_space = self.output_color_space
        other.override_material = self.override_material
        # The planes cut in camera space, and the shadow filter reads the
        # light's own map, so neither changes with the frame's size.
        other.clipping_planes = self.clipping_planes.copy()
        other.local_clipping_enabled = self.local_clipping_enabled
        other.shadow_map_type = self.shadow_map_type
        other.shadow_map_transmitted = self.shadow_map_transmitted
        other.depth_mode = self.depth_mode
        other.time = self.time
        other.auto_clear = self.auto_clear
        other.auto_clear_color = self.auto_clear_color
        other.auto_clear_depth = self.auto_clear_depth
        other.auto_clear_stencil = self.auto_clear_stencil
        other.custom_tone_mapping = self.custom_tone_mapping
        other.info_auto_reset = self.info_auto_reset
        other._opaque_sort = self._opaque_sort
        other._transparent_sort = self._transparent_sort
        other.draw_filter = self.draw_filter
        other.oit_draw = self.oit_draw
        other.snap_vertices = self.snap_vertices
        other.uv_space_meshes = self.uv_space_meshes.copy()
        # Counted into this renderer's info, not a copy of it.
        other._state = self._state
        other.ltc = self.ltc.copy()
        other.probe_grid = self.probe_grid.copy()

    def scaled(self, factor: Int) raises -> Renderer:
        """Return a renderer `factor` times this one's size each way, with
        the same settings, its viewport and scissor scaled to match, and
        no supersampling of its own.

        Its `render_scale` is this one's times `factor`, so a point's size
        and a line's thickness -- the two things a caller gives in pixels
        -- come out the size they were asked for once the frame is
        averaged down. A caller driving `GpuRenderer.draw` by hand has to
        pass that `render_scale` as the draw's `line_width` for the same
        reason.

        Args:
            factor: How many raster pixels across and down stand for one
                pixel of this renderer.

        Returns:
            The larger renderer.

        Raises:
            Error: If the factor is below one, or the larger renderer
                cannot be built.
        """
        require_positive(factor, "A renderer is scaled by at least one")
        var big = Renderer(
            self.width * factor, self.height * factor, self.workers
        )
        self._copy_draw_settings(big)
        big.viewport = _scaled(self.viewport, factor)
        big.scissor = _scaled(self.scissor, factor)
        big.scissor_test = self.scissor_test
        # A point's size and a line's thickness are given in this
        # renderer's output pixels. The larger renderer converts them
        # once, so the averaged frame keeps the size the caller asked for.
        big.render_scale = self.render_scale * factor
        return big^

    def resized(self, width: Int, height: Int) raises -> Renderer:
        """Return a renderer of another size with the same settings, drawing
        over its whole target, that shares this one's velocity history: what
        a pass that draws the scene at its own resolution scale draws with,
        as three.js's `PassNode.setResolutionScale` draws into a smaller
        target with the same renderer.

        Args:
            width: The new width in pixels.
            height: The new height in pixels.

        Returns:
            The renderer.

        Raises:
            Error: If a size is not positive.
        """
        var sized = Renderer(width, height, self.workers)
        self._copy_draw_settings(sized)
        sized.antialias = self.antialias
        sized.render_scale = self.render_scale
        return sized^

    def set_viewport(mut self, rect: Rect) raises:
        """Put the camera's image in `rect`, three.js's `setViewport`.

        The projection is mapped onto the rectangle rather than onto the
        whole target, so the image is squeezed or stretched to its size,
        as three.js's is. A rectangle hanging off the target is allowed:
        the pixels it puts outside are not drawn. Pass
        `Rect.whole(width, height)` to fill the target again.

        Args:
            rect: Where the image lands. The corner counts up from the
                bottom left, as three.js's does; see `render.rect`.

        Raises:
            Error: If the rectangle holds no pixel.
        """
        require_valid(
            rect.is_valid(), "A viewport needs a positive width and height"
        )
        self.viewport = rect

    def set_scissor(mut self, rect: Rect) raises:
        """Draw only inside `rect` once the scissor test is on, three.js's
        `setScissor`.

        The rectangle is kept whether or not the test is on, as three.js
        keeps it, and read only while it is. See `set_scissor_test`.

        Args:
            rect: The pixels a draw may touch. It must lie wholly inside
                the target. The corner counts up from the bottom left.

        Raises:
            Error: If the rectangle is empty or reaches outside the target.
        """
        require_rect(rect, self.width, self.height, "scissor")
        self.scissor = rect

    def set_scissor_test(mut self, enabled: Bool):
        """Turn the scissor on or off, three.js's `setScissorTest`.

        On, `render` and `render_into` clear and draw inside the scissor
        alone. Off, the default, they touch the whole target and the
        scissor is ignored.

        Args:
            enabled: Whether the scissor is enforced.
        """
        self.scissor_test = enabled

    def set_velocity_projection(self, projection: Optional[Matrix4]):
        """Measure velocities with a projection in the place of the
        camera's, or with the camera's again: three.js's
        `VelocityNode.setProjectionMatrix`. TRAA sets the camera's
        projection before its jitter, so the jitter is not motion.

        Kept with the renderer's history, which every copy that shares it
        sees; see `_RendererState`.

        Args:
            projection: The projection, or `None` for the camera's own.
        """
        self._state[].velocity_projection = projection

    def _to_screen[C: Camera](self, camera: C) raises -> Matrix4:
        """Return the transform from camera space to the viewport's pixels.

        The camera maps its projection onto a rectangle of the viewport's
        size, and that rectangle is then moved to where the viewport is.
        The viewport's corner counts up from the bottom and the rows count
        down from the top, so the move along y is to `Rect.top`.
        """
        var to_screen = translation(
            Float32(self.viewport.x),
            Float32(self.viewport.top(self.height)),
            0,
        )
        to_screen.multiply(
            camera.view_to_screen_matrix(
                self.viewport.width, self.viewport.height
            )
        )
        return to_screen^

    def _camera_frame[
        C: Camera
    ](self, scene: Scene, camera: C) raises -> _CameraFrame:
        """Return the view, the clip and the culling planes for one camera.

        A camera riding a node looks from wherever the scene put that
        node. The frustum is in world space, where the bounds are:
        three.js's `_projScreenMatrix`, with the near and far distances
        the clipper is given. The side planes are in camera space, where
        the clipper cuts. With a viewport smaller than the target, off
        the image is still on the target, and only a cut keeps it off.
        The renderer's clipping planes are carried into camera space once.

        Args:
            scene: The transform hierarchy.
            camera: The camera.

        Returns:
            The world-to-camera transform, the pixel transform, the near
            and far distances, the clip matrix, the world-space frustum,
            the camera-space side planes and the renderer's clipping
            planes in camera space.

        Raises:
            Error: If a clipping plane cannot be carried into camera space.
        """
        var view = camera.view_matrix_in(scene)
        var screen = self._to_screen(camera)
        var near = camera.near_distance()
        var far = camera.far_distance()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        return _CameraFrame(
            view,
            screen,
            near,
            far,
            clip,
            Frustum.from_camera(clip, view, near, far),
            Frustum.side_planes(camera.projection_matrix()),
            _planes_in_view(self.clipping_planes, view),
        )

    def set_workers(mut self, workers: Int) raises:
        """Choose how many threads rasterize a frame.

        The image is cut into that many horizontal bands and every triangle
        is rasterized once per band, each on its own thread. The result is
        byte for byte what one thread produces, because a band owns its rows
        and draws in the same order; only the wall clock changes. More
        bands than rows collapse to one band per row.

        Args:
            workers: At least one. `available_workers()` is one per core.

        Raises:
            Error: If `workers` is less than one.
        """
        require_renderer_workers(workers)
        self.workers = workers

    def set_background(mut self, color: Color):
        """Set the color the image is cleared to."""
        self.background = color

    def set_tone_mapping(
        mut self, mode: ToneMapping, exposure: Float32 = 1.0
    ) raises:
        """Choose how each pixel's light is compressed for a display.

        Args:
            mode: One of the seven curves in `render.tonemap`, or
                `NO_TONE_MAPPING` to clamp and nothing else.
            exposure: What the light is scaled by before the curve,
                three.js's `toneMappingExposure`. One leaves it alone.

        Raises:
            Error: If the mode is none of the seven, or the exposure is
                negative or not finite; see `check_tone_mapping`. The type
                stops a bare integer; it does not stop `ToneMapping(9)`.
        """
        check_tone_mapping(mode, exposure)
        self.tone_mapping = mode
        self.tone_mapping_exposure = exposure

    def set_output_color_space(mut self, space: ColorSpaceId) raises:
        """Choose the color space the finished image is written in,
        three.js's `outputColorSpace`.

        The light is carried into the space's primaries by three.js's
        matrix, then through its transfer function: sRGB's curve for
        `SRGB_COLOR_SPACE` and `DISPLAY_P3_COLOR_SPACE`, none for a linear
        space. See `render.color_spaces.output_encoding`.

        Args:
            space: The output color space; sRGB by default.

        Raises:
            Error: If the value names no color space, or it is
                `NO_COLOR_SPACE`.
        """
        _ = output_encoding(space)
        self.output_color_space = space

    def drawn_override(self, scene: Scene) -> Optional[MaterialId]:
        """Return the material that takes the place of every object's in a
        frame: the renderer's `override_material` when it is set, and the
        scene's otherwise.

        Args:
            scene: The scene, for its own override.

        Returns:
            The material, or none.
        """
        var own = Bool(self.override_material)
        if own:
            return self.override_material
        return scene.override_material

    def output_encoding(self) raises -> OutputEncoding:
        """Return how the finished image is written out, for a caller
        that resolves a target of its own the way `render` does.

        Returns:
            The encoding of `output_color_space`.

        Raises:
            Error: If `output_color_space` was set by hand to a value that
                names no color space, or to `NO_COLOR_SPACE`.
        """
        return output_encoding(self.output_color_space)

    def set_depth_mode(mut self, mode: DepthMode) raises:
        """Choose how a frame's depth is stored and compared: three.js's
        `logarithmicDepthBuffer` and `reversedDepthBuffer` options.

        `LOGARITHMIC_DEPTH` stores `log2(1 + w)` scaled by the camera's
        far distance, per fragment, for a perspective camera. An
        orthographic camera keeps the standard depth, as three.js does.
        `REVERSED_DEPTH` stores 1 at the near plane and 0 at the far
        plane, clears to minus infinity and turns every depth comparison
        round. Both backends follow the mode. The shadow maps do not:
        they keep the standard depth that their comparison reads. See
        `render.raster_state.fragment_depth`.

        Args:
            mode: `STANDARD_DEPTH`, `LOGARITHMIC_DEPTH` or
                `REVERSED_DEPTH`.

        Raises:
            Error: If the mode is none of those three. The type stops a
                bare integer; it does not stop `DepthMode(7)`.
        """
        require_depth_mode(mode)
        self.depth_mode = mode

    def depth_mode_for[C: Camera](self, camera: C) raises -> DepthMode:
        """Return the depth mode a frame through `camera` is drawn in.

        The renderer's mode, but `LOGARITHMIC_DEPTH` falls back to
        `STANDARD_DEPTH` for a camera whose projection does not divide by
        distance: three.js's `vIsPerspective == 0.0` keeps
        `gl_FragCoord.z`.

        Args:
            camera: The camera the frame is drawn through.

        Returns:
            The mode every primitive of the frame carries.

        Raises:
            Error: If the camera's projection cannot be built.
        """
        if (
            self.depth_mode == LOGARITHMIC_DEPTH
            and camera.projection_matrix().is_affine()
        ):
            return STANDARD_DEPTH
        return self.depth_mode

    def _encode_depth[C: Camera](self, mut vertices: _Slim, camera: C) raises:
        """`_encode_depth` on the surfaces of slim corners, which hold the
        depth mode the camera writes.

        Args:
            vertices: The frame's triangles.
            camera: The camera the frame is drawn through.

        Raises:
            Error: As the other overload.
        """
        var mode = self.depth_mode_for(camera)
        var scale = Float32(0)
        if mode == LOGARITHMIC_DEPTH:
            scale = log_depth_factor(camera.far_distance())
        for index in range(len(vertices.surfaces)):
            vertices.surfaces[index].state.depth_mode = mode
            vertices.surfaces[index].state.log_depth_scale = scale

    def _encode_depth[
        C: Camera
    ](self, mut vertices: List[RasterVertex], camera: C) raises:
        """Put the frame's depth mode on every primitive's state.

        Args:
            vertices: The prepared corners, ends or points, changed in
                place.
            camera: The camera the frame is drawn through.

        Raises:
            Error: If the camera's projection cannot be built.
        """
        var mode = self.depth_mode_for(camera)
        var scale = Float32(0)
        if mode == LOGARITHMIC_DEPTH:
            scale = log_depth_factor(camera.far_distance())
        for index in range(len(vertices)):
            vertices[index].state.depth_mode = mode
            vertices[index].state.log_depth_scale = scale

    def set_shading(mut self, mode: ShadeMode) raises:
        """Choose what a fragment's color is taken from.

        Args:
            mode: `SHADE_TEXTURE` to follow each material, `SHADE_LIT` to
                ignore every texture, or `SHADE_UV` to write texture
                coordinates as red and green instead.

        Raises:
            Error: If the mode is none of those three: `SHADE_SHADOW` is the
                shadow pass's. The type stops a bare integer; it does not
                stop `ShadeMode(99)`.
        """
        require_shade_mode(mode)
        if mode == SHADE_SHADOW:
            raise Error(
                "SHADE_SHADOW draws a shadow map's colors, which the"
                " renderer draws for itself"
            )
        self.shading = mode

    def prepare[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
    ) raises -> List[
        RasterVertex
    ]:
        """Turn a scene into the triangles a rasterizer can fill.

        The filled surfaces only. A mesh whose material is a wireframe is
        drawn as lines by `prepare_lines`, and contributes no triangle
        here; see `_prepared`.

        Args:
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

        Returns:
            Raster vertices, three per triangle, in submission order.

        Raises:
            Error: Everything `_prepared` raises.
        """
        var spans = List[_Span]()
        return self._prepared(scene, assets, camera, False, spans)

    def _prepared[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        wireframe: Bool,
        mut spans: List[_Span],
        casters_only: Bool = False,
        receivers_cast: Bool = False,
        transmissive_backs: Bool = False,
        distance_casters: Bool = False,
    ) raises -> List[RasterVertex]:
        """`_prepared_slim`, each corner whole: what `prepare` returns and
        what a pass that reads whole corners takes."""
        return self._prepared_slim(
            scene,
            assets,
            camera,
            wireframe,
            spans,
            casters_only,
            receivers_cast,
            transmissive_backs,
            distance_casters,
        ).whole()

    def _prepared_slim[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        wireframe: Bool,
        mut spans: List[_Span],
        casters_only: Bool = False,
        receivers_cast: Bool = False,
        transmissive_backs: Bool = False,
        distance_casters: Bool = False,
    ) raises -> _Slim:
        """Turn a scene into the triangles a rasterizer can fill.

        Everything that is not filling pixels happens here: world transforms,
        lighting, clipping and projection. What comes out is the boundary
        between the two halves of the renderer — screen-space triangles with
        their varyings already worked out — and it is the *same* boundary
        whichever rasterizer consumes it. The CPU one is `render` below; the
        GPU one is `render.gpu`, which takes exactly this list.

        Keeping it a separate step is what makes the two backends comparable
        rather than merely similar: a parity test can hand both the identical
        input and demand identical output.

        **Prepared triangles are no longer the whole of a frame.** Lighting
        used to be evaluated here and baked into each corner; it is now
        evaluated per fragment, so a rasterizer needs the scene's resolved
        `Lighting` alongside this list. Handing one backend the lights and
        letting the other fall back to `Lighting.uniform` is not a parity
        test, it is two different questions.

        `scene.update()` must have been called since the last transform
        change; this reads world matrices rather than recomputing them, so a
        stale scene renders stale positions.

        Args:
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
                Two meshes naming the same id share one copy of it.
            camera: The camera to project through — anything satisfying
                `cameras.camera.Camera`, perspective or orthographic, placed
                or riding one of the scene's nodes.
            wireframe: Which half of the scene to prepare, and what to
                make of it. False gives the filled surfaces as triangles,
                three corners each, which is what `prepare` asks for. True
                gives the wireframe meshes as segments, two corners each,
                assembled from the edges of their own triangles. The split
                is here, after the vertex stage, so that a wireframe is
                morphed, skinned, instanced and culled by the same code as
                the surface it replaces, and only the primitive it is
                assembled into differs. It is not a filled mesh cut up
                afterwards: clipping a triangle leaves a polygon that has
                to be fanned, and the fan's diagonal and the cut along the
                near plane are edges of the clipper rather than of the
                mesh. See below.
            spans: Where each draw's run of primitives is recorded, with
                its depth and whether it blends, for `prepare_frame` to
                order against the other kind's. Appended to.
            casters_only: Whether this is a light's view for a shadow
                map, holding only the meshes that cast; see `_draws`.
            receivers_cast: Whether that view also holds the meshes that
                receive; see `_draws`.
            transmissive_backs: Whether this is the second half of the
                transmission pass: the back faces of every two-sided
                transmissive mesh and nothing else, three.js's
                `material.side = BackSide` over its `transmissiveObjects`.
            distance_casters: Whether a light's view of the casters is a
                point light's; see `_draws`.

        Returns:
            Raster vertices, three per triangle, in submission order, or
            two per segment when `wireframe`. A mesh
            whose node shares no layer with the camera contributes none,
            and nor does one whose bounding sphere lies wholly outside the
            camera's frustum, unless it opted out of that test. An
            instanced or batched mesh contributes each of its instances the
            same way. An LOD's hidden levels contribute nothing, as any
            hidden node does.

        Raises:
            Error: If a mesh names a node, a geometry or a material that is
                not there, if a material names a texture, an emissive map,
                an alpha map or a cube texture that is not there, if its
                emissive map does
                not ignore its alpha, if its alpha map is not stored as
                data, if its geometry has no positions, or if its material
                asks for vertex colors and the geometry has no `color`
                attribute of three or four floats per vertex. The asset
                checks are made on the draws that are made: a mesh the
                camera's layers or frustum leave out is not read.
        """
        var corners = _Slim()
        var frame = self._camera_frame(scene, camera)
        var view = frame.view
        var to_screen = frame.to_screen
        var near = frame.near
        var far = frame.far
        var frustum = frame.frustum.copy()
        var sides = frame.sides.copy()
        var global_planes = frame.global_planes.copy()

        # Worked out once, not once per draw, and already without what
        # the camera does not draw: every mesh and every instance, as one
        # list.
        var skins = List[SkinPose]()
        var draws = _draws(
            scene,
            assets,
            view,
            camera.visible_layers(),
            frustum,
            far * CULL_SLACK,
            skins,
            casters_only,
            receivers_cast,
            distance_casters,
            self.drawn_override(scene),
            self.uv_space_meshes.copy(),
        )
        # Whether the camera's rays converge, for a sprite that keeps its
        # size on the image; see `_emit_sprite`.
        var perspective = not camera.projection_matrix().is_affine()
        # The camera's lights, with no shadow, for a `GOURAUD` surface's
        # corners: resolved once, when the first one is met.
        var gouraud_lights = Lighting.uniform()
        var gouraud_ready = False
        # A light map's frame: the meshes named, in their own texture
        # space; see `uv_space_meshes`. A light's view is drawn by a
        # renderer of its own, which draws the casters as they stand.
        var in_uv_space = len(self.uv_space_meshes) > 0
        # The light masks the materials name, each a lighting of its own;
        # see `light_masks`.
        var masks = light_masks(assets)
        # The filled draws whose vertex stage is done, waiting to emit
        # their triangles on the workers. Emitted before anything else
        # is appended, so the corners stay in draw order.
        var jobs = List[_TriangleJob]()
        var pending_vertices = 0
        for slot in range(len(draws)):
            # Each draw shares one surface per facing.
            corners.new_surface()
            if draws[slot].wide_line >= 0:
                # A wide line is drawn as triangles, so it is a filled
                # surface and is left out of the wireframe half. Its
                # triangles are built from its pairs of points; see
                # `_emit_wide_line`. It never transmits.
                if wireframe or transmissive_backs:
                    continue
                _emit_jobs(
                    jobs, corners, spans, self.workers, gouraud_lights, assets
                )
                pending_vertices = 0
                var wide_begin = len(corners)
                var wide_cut = List[Plane]()
                var wide_any = List[Plane]()
                _clip_draw(
                    assets.materials.get(draws[slot].material),
                    scene,
                    draws[slot].node,
                    view,
                    sides,
                    global_planes,
                    self.local_clipping_enabled,
                    casters_only,
                    wide_cut,
                    wide_any,
                )
                _emit_wide_line(
                    corners,
                    assets,
                    draws[slot],
                    view,
                    to_screen,
                    near,
                    far,
                    wide_cut,
                    wide_any,
                    self.render_scale,
                    scene.wide_lines[draws[slot].wide_line].coverage,
                    casters_only,
                    self.workers,
                )
                _note_span(
                    spans,
                    DRAW_TRIANGLES,
                    wide_begin,
                    len(corners),
                    draws[slot].depth,
                    draws[slot].blends,
                    draws[slot].order,
                    draws[slot].source(),
                )
                continue
            if draws[slot].sprite >= 0:
                # A sprite names no geometry, so nothing below applies to
                # it: its two triangles are built from its node instead.
                # It is a filled surface only, and refuses a wireframe. It
                # is basic, and never transmits.
                if wireframe or transmissive_backs:
                    continue
                _emit_jobs(
                    jobs, corners, spans, self.workers, gouraud_lights, assets
                )
                pending_vertices = 0
                var begin = len(corners)
                var sprite_cut = List[Plane]()
                var sprite_any = List[Plane]()
                _clip_draw(
                    assets.materials.get(draws[slot].material),
                    scene,
                    draws[slot].node,
                    view,
                    sides,
                    global_planes,
                    self.local_clipping_enabled,
                    casters_only,
                    sprite_cut,
                    sprite_any,
                )
                _emit_sprite(
                    corners,
                    assets,
                    scene.sprites[draws[slot].sprite],
                    draws[slot],
                    view,
                    to_screen,
                    near,
                    far,
                    sprite_cut,
                    perspective,
                    self.shading,
                    sprite_any,
                    casters_only,
                )
                _note_span(
                    spans,
                    DRAW_TRIANGLES,
                    begin,
                    len(corners),
                    draws[slot].depth,
                    draws[slot].blends,
                    draws[slot].order,
                    draws[slot].source(),
                )
                continue
            var world = draws[slot].world
            # For a frame that keeps velocities, the matrix that puts a
            # vertex where the last frame had it. A light map's frame is
            # not seen through the camera, and keeps none.
            var tracks = self._state[].tracks_velocity and not in_uv_space
            var front = Matrix4()
            var back = Matrix4()
            if tracks:
                front = self._state[].current_clip(world)
                back = self._state[].previous_clip(
                    draws[slot].node,
                    scene.world_matrix(draws[slot].node),
                    world,
                )
            var current_points = List[Vector3]()
            var previous_points = List[Vector3]()
            # An odd number of reflections in the world transform reverses
            # winding, which turns both the culling convention and the
            # geometric-normal fallback upside down. Asked once per draw, of
            # the world matrix rather than the node's own scale, because the
            # reflection can be inherited from any parent, or from an
            # instance's own matrix.
            var mirrored = world.determinant() < 0
            # Borrowed, not copied: two draws naming the same id read the
            # same arrays rather than each holding their own.
            ref geometry = assets.geometries.get(draws[slot].geometry)
            var material = assets.materials.get(draws[slot].material)
            # The one line that splits the scene in two. Everything above
            # is shared, so a wireframe is culled, sorted, morphed and
            # skinned by the same code as a filled surface.
            if material.wireframe != wireframe:
                continue
            # The transmission pass's back faces: only a two-sided mesh
            # that transmits, drawn from behind whatever its side says.
            var side = material.side
            if casters_only:
                side = draws[slot].cast_side
            if transmissive_backs:
                if not _has_transmissive_back(material):
                    continue
                side = BACK_SIDE
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_draw(
                material,
                scene,
                draws[slot].node,
                view,
                sides,
                global_planes,
                self.local_clipping_enabled,
                casters_only,
                cut,
                any_of,
            )
            # Carried on every vertex of this mesh, so one flat triangle list
            # can hold a scene whose meshes use different images.
            var blending = material.blending
            var map = material.map
            # What kind of surface this is: whether the lights reach it, or
            # whether it shows its normal or its depth instead of a color.
            # Per triangle, like the blend.
            var kind = material.kind
            if material.volume_scene_depth and kind != VOLUME:
                raise Error("Only a VOLUME material reads volume scene depth")
            # Checked here because here is the first place that can: a
            # material is built without the store in reach, so a positive id
            # naming nothing is only detectable once both are together. It is
            # checked before rasterization rather than during, so the answer
            # does not depend on which pixels the mesh happened to cover.
            require_material_texture(map, assets.textures.count())
            if self.shading != SHADE_TEXTURE:
                map = NO_TEXTURE
            # The emissive map, checked the same way. It multiplies the
            # emissive color, so a material that gives off no light has no
            # use for it, and a fragment is spared the sample.
            var glow_map = material.emissive_map
            if (
                glow_map != NO_TEXTURE
                and glow_map.value >= assets.textures.count()
            ):
                raise Error(
                    "A material names an emissive map that is not there"
                )
            # Its alpha means nothing, and only a texture built to ignore it
            # filters accordingly; one that reads alpha as coverage would
            # darken wherever its alpha is low -- see `render.texture.Alpha`.
            # Refused whatever the shading mode: it is a wrong asset, not a
            # wrong frame.
            if glow_map != NO_TEXTURE:
                check_color_map(
                    assets.textures.get(glow_map), "A material's emissive map"
                )
            if self.shading != SHADE_TEXTURE or not material.is_emissive():
                glow_map = NO_TEXTURE
            # The alpha map, checked the same way, and refused unless it is
            # stored as data: its green channel is a coverage, and the sRGB
            # curve and a coverage-weighted filter each change what it
            # means. Refused whatever the shading mode, as the emissive
            # map's alpha mode is: a wrong asset, not a wrong frame.
            var mask = material.alpha_map
            require_material_alpha(mask, assets.textures.count())
            if mask != NO_TEXTURE:
                check_alpha_map(assets.textures.get(mask))
            if self.shading != SHADE_TEXTURE:
                mask = NO_TEXTURE
            # The ramp a `TOON` surface steps through, checked the same way
            # and refused unless it is stored as data. Carried under every
            # shading mode that lights the surface, unlike the alpha map:
            # `SHADE_LIT` shades a toon surface and reads the ramp, and
            # only the uv view does not.
            var tones = material.gradient_map
            if tones != NO_TEXTURE and tones.value >= assets.textures.count():
                raise Error("A material names a gradient map that is not there")
            if tones != NO_TEXTURE:
                check_gradient_map(assets.textures.get(tones))
            if self.shading == SHADE_UV:
                tones = NO_TEXTURE
            # The image a `MATCAP` surface is looked up in. Its own alpha
            # means nothing, so it is refused unless it ignores it -- the
            # rule the emissive map follows. Carried under every mode that
            # shades, as the ramp is.
            var ball = material.matcap
            if ball != NO_TEXTURE and ball.value >= assets.textures.count():
                raise Error("A material names a matcap that is not there")
            if ball != NO_TEXTURE:
                check_color_map(assets.textures.get(ball), "A matcap")
            if self.shading == SHADE_UV:
                ball = NO_TEXTURE
            # The environment the surface reflects, the scene's if the
            # material asked for it, checked against the store here.
            var env = _resolved_env(scene, assets, material, self.shading)
            # The five maps that hold numbers, each checked the way the
            # alpha map is -- there, and stored as data, whatever the
            # shading mode -- and each erased unless textures are opened.
            var physics = _Physics(
                material.roughness,
                material.metalness,
                _env_intensity(scene, material),
                _checked_data_map(
                    assets, material.roughness_map, "A roughness map"
                ),
                _checked_data_map(
                    assets, material.metalness_map, "A metalness map"
                ),
                material.specular_intensity,
                material.clearcoat,
                material.clearcoat_roughness,
                _checked_data_map(assets, material.normal_map, "A normal map"),
                material.normal_scale,
                _checked_data_map(assets, material.bump_map, "A bump map"),
                material.bump_scale,
                _checked_data_map(assets, material.ao_map, "An ao map"),
                material.ao_map_intensity,
                _checked_light_map(assets, material.light_map),
                material.light_map_intensity,
                _checked_data_map(
                    assets, material.specular_map, "A specular map"
                ),
                material.transmission,
                _checked_data_map(
                    assets, material.transmission_map, "A transmission map"
                ),
                # three.js's `thickness * modelScale`: the thickness is in
                # the geometry's own units, and the slab is as deep along
                # each world axis as that axis is stretched.
                Vector3(
                    material.thickness.to(METER) * world.column_length(0),
                    material.thickness.to(METER) * world.column_length(1),
                    material.thickness.to(METER) * world.column_length(2),
                ),
                _checked_data_map(
                    assets, material.thickness_map, "A thickness map"
                ),
                FloatColor(srgb=material.attenuation_color),
                material.attenuation_distance.to(METER),
                material.dispersion,
                material.ior,
                _layer_factors(assets, material, self.shading),
                _checked_nodes(assets, material.nodes),
                _checked_scattering(assets, material),
            )
            if self.shading != SHADE_TEXTURE:
                physics.roughness_map = NO_TEXTURE
                physics.metalness_map = NO_TEXTURE
                physics.normal_map = NO_TEXTURE
                physics.bump_map = NO_TEXTURE
                physics.ao_map = NO_TEXTURE
                physics.light_map = NO_TEXTURE
                physics.specular_map = NO_TEXTURE
                physics.transmission_map = NO_TEXTURE
                physics.thickness_map = NO_TEXTURE
            # Which set of coordinates each map reads, asked of the
            # material's own maps whatever the shading mode: a channel that
            # is neither set is a wrong asset under any mode. Where each
            # map is moved, tiled and turned is its own texture's business,
            # applied at the fragment.
            _check_map_channels(assets, material)
            # Light the surface gives off, decoded to linear once and carried
            # on every corner like the base color below.
            var glow = material.emissive_light()
            # How much the surface reflects head on, decoded once and
            # carried the same way: a `PHONG` material's specular, a
            # physical material's reflectance, and black for every other
            # kind. See `Material.base_reflectance`.
            var sheen = material.base_reflectance()
            # A flat-shaded draw takes the face's own normal, as a geometry
            # with no normals does: three.js's `flatShading`, whose normal
            # is the cross product of the view position's derivatives.
            # Put on all three corners here, so both rasterizers light
            # every fragment of the face with one normal and need no rule
            # of their own. `emit` turns it with the face, and a normal
            # or bump map perturbs it as it would any other.
            var smooth = (
                geometry.has_attribute(String(NORMAL))
                and not material.flat_shading
            )

            # World positions are kept as well as camera-space ones: a
            # geometric normal needs the triangle's real shape, and the view
            # transform is where clipping has to happen.
            var world_points = List[Vector3]()
            var view_points = List[Vector3]()
            # `ref` and not `var`: this borrows the geometry's array rather
            # than copying it. Writing `var` here is a compile error, which is
            # the point of the two accessors.
            ref positions = geometry.attribute_view(String(POSITION))
            var vertex_count = positions.count()
            if pending_vertices + vertex_count > PENDING_VERTICES:
                _emit_jobs(
                    jobs, corners, spans, self.workers, gouraud_lights, assets
                )
                pending_vertices = 0
            world_points.reserve(vertex_count)
            view_points.reserve(vertex_count)
            # How many of the geometry's morph targets this draw actually
            # wears. Worked out once here rather than per vertex, and zero
            # for everything that is not a morphed mesh, which is the only
            # cost an unmorphed scene pays for any of this.
            # A skinned draw works out one matrix per vertex before the
            # loops below, because the position and the normal both want
            # it and three.js blends it once for the same reason.
            var carriers = _carriers(
                geometry, skins, draws[slot].skin, vertex_count
            )
            var carried = len(carriers) > 0
            # Where the targets put the vertices. The same call the
            # raycaster makes, so what is drawn and what is picked cannot
            # answer differently.
            var worn: List[Vector3]
            # A displacement map moves them last, along their normals,
            # and the call that does it carries them first: three.js's
            # `displacementmap_vertex` follows `skinning_vertex`. Checked
            # for every draw, so a scale set with no map is refused here
            # and not only by the raycaster. A light's view draws this
            # same code, so the shadow moves with the surface.
            material.check_displacement()
            var carry_here = carried
            if material.has_displacement_map():
                worn = displaced_positions(
                    geometry,
                    draws[slot].morph_influences,
                    carriers,
                    material,
                    assets.textures,
                )
                carry_here = False
            else:
                worn = morphed_positions(geometry, draws[slot].morph_influences)
            # A node material's position node moves them after that, in the
            # model's own space: three.js's `positionNode` follows the
            # skinning and the displacement map. Each vertex reads the
            # geometry's own normal, or zero where it has none.
            var moves = _moves(assets, material)
            var has_normals = geometry.has_attribute(String(NORMAL))
            for vertex in range(vertex_count):
                var local = worn[vertex]
                if carry_here:
                    local = carriers[vertex].transform_point(local)
                if moves:
                    var normal = Vector3(0, 0, 0)
                    if has_normals:
                        normal = geometry.attribute_view(
                            String(NORMAL)
                        ).vector3(vertex)
                    local = moved_position(
                        assets.programs.get(material.nodes), local, normal
                    )
                var point = world.transform_point(local)
                world_points.append(point)
                view_points.append(view.transform_point(point))
                if tracks:
                    current_points.append(_clip_of(front, local))
                    previous_points.append(_clip_of(back, local))

            # Texture coordinates do not go through the world transform:
            # they name a place in an image, not a place in the world. Nor
            # through any texture's transform: each map moves them at the
            # fragment by its own, as three.js's `uv_vertex` makes a
            # varying per map. A geometry without them gets zeroes, which
            # map everything to one place -- harmless until something is
            # actually sampled with them.
            var first_set = _coordinates(geometry, String(UV), vertex_count)
            # The second pair, which a map on `UV_CHANNEL_1` reads: the
            # geometry's `uv1` when it has one, and its `uv` otherwise.
            var second_name = String(UV)
            if geometry.has_attribute(String(UV1)):
                second_name = String(UV1)
            var second_set = _coordinates(geometry, second_name, vertex_count)
            # The custom attributes a node material reads, raw.
            var customs = _customs(assets, material, geometry, vertex_count)
            if kind == GOURAUD and not gouraud_ready:
                gouraud_lights = Lighting(
                    scene,
                    visible=camera.visible_layers(),
                    profiles=self.spot_profiles(
                        scene, assets, camera.visible_layers()
                    ),
                    probe_grid=self.probe_grid,
                )
                gouraud_ready = True

            # World-space normals are their own pass so the normal array can
            # be borrowed only when there is one, and the normal matrix built
            # once per mesh rather than once per vertex. What used to happen
            # here was the *lighting*; now only the normal is worked out, and
            # the light is applied per fragment.
            #
            # A normal material shows the normal as the camera sees it,
            # three.js's `vNormal` in view space, so its normals are turned
            # once more, by the view. The view is rigid, so the turn keeps
            # them unit length, and the fragment normalizes what it gets in
            # any case. The lights never see these: the kind is unlit.
            var vertex_normals = List[Vector3]()
            if smooth:
                var to_normal = world.normal_matrix()
                # Morphed by the same evaluator the positions went through,
                # which keeps the two in step and keeps the rule about a
                # geometry whose targets carry no normals in one place.
                var faces = morphed_normals(
                    geometry, draws[slot].morph_influences
                )
                for vertex in range(vertex_count):
                    var facing = faces[vertex]
                    if carried:
                        facing = carriers[vertex].transform_direction(facing)
                    # transform_direction ignores translation, which is what a
                    # normal wants: it points somewhere, it is not somewhere.
                    var direction = to_normal.transform_direction(facing)
                    direction.normalize()
                    if kind == NORMALS:
                        direction = view.transform_direction(direction)
                    vertex_normals.append(direction)

            # The material's color, decoded to linear once with its opacity
            # folded into alpha, is what every corner carries -- times the
            # vertex's own color when the material asks for vertex colors.
            # The fragment lights whatever arrives.
            # An instance's color multiplies the material's, three.js's
            # `instanceColor`; white for everything else.
            var own = FloatColor(srgb=material.color)
            ref tint = draws[slot].tint
            var base = _with_opacity(
                FloatColor(
                    own.r * tint.r, own.g * tint.g, own.b * tint.b, own.a
                ),
                material.opacity,
            )
            var vertex_colors = _vertex_colors(
                geometry,
                material.vertex_colors,
                base,
                vertex_count,
                draws[slot].instance,
                draws[slot].morph_influences,
            )

            # The index buffer is read directly, checked once up front.
            # `corner_index` does the same checks per corner, but reaches
            # the vertex count through a string lookup of the position
            # attribute, and three of those per triangle was measurable.
            var indexed = geometry.is_indexed()
            ref indices = geometry.index
            for slot in range(len(indices)):
                require_vertex_index(indices[slot], vertex_count)
            # The run this draw fills: a group of a mesh that wears a
            # material list, or the whole stream, inside the geometry's
            # draw range. See `drawn_run`.
            var run = geometry.drawn_run(
                draws[slot].group_start, draws[slot].group_count
            )
            var run_start = run[0]
            var triangles = run[1]
            var lights_up = not kind.is_data() and kind != SHADOW
            # A light's view approximates alpha to coverage by an alpha
            # test at one half, as three.js's shadow map does.
            var alpha_cut = material.alpha_test
            if casters_only and material.alpha_to_coverage:
                alpha_cut = 0.5
            var paint = _Paint(
                to_screen,
                map,
                blending,
                kind,
                glow_map,
                mask,
                alpha_cut,
                sheen,
                material.shininess,
                tones,
                ball,
                mirrored,
                side,
                env,
                material.reflectivity,
                material.combine,
                physics,
                draws[slot].receives_shadow,
                # Every surface shader three.js has but the normal, the
                # depth, the distance and the shadow one dithers and
                # premultiplies; all but the normal and the shadow one
                # hash their alpha.
                _draw_state(
                    material,
                    casters_only,
                    lights_up,
                    kind != NORMALS and kind != SHADOW,
                    lights_up,
                ),
                _draw_offset(material, casters_only),
                _shown_of(material),
                _frames_of(scene, material, world),
                _mask_place(masks, material.lights),
            )
            if wireframe:
                # The mesh's own edges, each once, clipped as segments.
                # `clip_segment` shares its arithmetic with the triangle
                # clipper, so a wireframe edge and the filled edge under
                # it are cut at the same place.
                #
                # No backface test and no `side`: this is submitted as
                # lines, as three.js submits it, and a line has no facing
                # to reject. A front-sided wireframe box shows the far
                # side of itself, which is what a wireframe is for.
                # The edges of the triangles drawn: the run above, which
                # the draw range has cut, as three.js cuts its wireframe
                # index by the same range.
                _emit_jobs(
                    jobs, corners, spans, self.workers, gouraud_lights, assets
                )
                pending_vertices = 0
                var begin = len(corners)
                var ends = triangle_edges(geometry, run_start, triangles * 3)
                for edge in range(len(ends[0])):
                    var from_end = ends[0][edge]
                    var to_end = ends[1][edge]
                    var kept = clip_segment(
                        _line_corner(
                            view_points,
                            world_points,
                            vertex_colors,
                            from_end,
                        ),
                        _line_corner(
                            view_points, world_points, vertex_colors, to_end
                        ),
                        near,
                        far,
                        cut,
                        any_of,
                    )
                    for end in range(len(kept)):
                        corners.append(
                            _to_raster(
                                kept[end],
                                to_screen,
                                NO_TEXTURE,
                                blending,
                                BASIC,
                                NO_TEXTURE,
                                NO_TEXTURE,
                                0,
                                FloatColor(0.0, 0.0, 0.0),
                                0,
                                NO_TEXTURE,
                                NO_TEXTURE,
                                state=paint.state,
                                shown=paint.shown,
                            )
                        )
                _note_span(
                    spans,
                    DRAW_SEGMENTS,
                    begin,
                    len(corners),
                    draws[slot].depth,
                    draws[slot].blends,
                    draws[slot].order,
                    draws[slot].source(),
                )
                continue
            # The triangles themselves are emitted later, on the workers,
            # by a job that owns everything the vertex stage worked out.
            var job = _TriangleJob(
                run_start,
                triangles,
                draws[slot].geometry,
                indexed,
                smooth,
                mirrored,
                kind,
                view,
                world_points^,
                view_points^,
                vertex_normals^,
                vertex_colors^,
                first_set^,
                second_set^,
                customs^,
                glow,
                tracks,
                current_points^,
                previous_points^,
                paint,
                in_uv_space,
                self.viewport,
                self.height,
                near,
                far,
                cut^,
                any_of^,
                draws[slot].depth,
                draws[slot].blends,
                draws[slot].order,
                draws[slot].source(),
                material.transmits()
                or material.volume_scene_depth
                or _reads_scene(assets, material.nodes),
            )
            if kind == VOLUME:
                # A volume marches its own corners once they are all
                # there, so it emits at once, after what came before it.
                _emit_jobs(
                    jobs, corners, spans, self.workers, gouraud_lights, assets
                )
                pending_vertices = 0
                var begin = len(corners)
                job.emit(0, triangles, corners, gouraud_lights, assets)
                _march_volume(
                    corners,
                    begin,
                    material.steps,
                    geometry,
                    world,
                    material.volume_scene_depth and not casters_only,
                )
                job.note(spans, begin, len(corners))
                continue
            jobs.append(job^)
            pending_vertices += vertex_count
            if self.workers == 1 or pending_vertices >= PENDING_VERTICES:
                _emit_jobs(
                    jobs, corners, spans, self.workers, gouraud_lights, assets
                )
                pending_vertices = 0

        _emit_jobs(jobs, corners, spans, self.workers, gouraud_lights, assets)
        # A light's view of the casters keeps the standard depth, which
        # is what the shadow comparison reads; see `set_depth_mode`.
        if not casters_only:
            self._encode_depth(corners, camera)
        return corners^

    def prepare_lines[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
    ) raises -> List[
        RasterVertex
    ]:
        """Turn the lines in a scene into the segments a rasterizer draws.

        `prepare` for lines. It is the same boundary and the same promise:
        screen-space primitives with their varyings worked out, handed to
        the CPU rasterizer by `render` and to the GPU by
        `render.gpu.GpuRenderer.draw`, so a parity test can give both the
        identical input.

        It is a second pass rather than more work inside the first,
        because almost nothing a triangle carries applies to a line. A
        line has no surface, so no normal, no texture coordinates and no
        winding. What is left is a position, a color and a depth, and a
        pass that carries only those is shorter than a pass that carries
        everything and then throws most of it away.

        `scene.update()` must have been called since the last transform
        change, as `prepare` needs.

        Args:
            scene: The transform hierarchy, and the lines in it.
            assets: The geometries and materials the lines name.
            camera: The camera to project through.

        Returns:
            Raster vertices, two per segment. Opaque lines come first,
            nearest first, then the blended ones furthest first, which is
            the order `_draws` puts the triangles in and for the same
            reasons. A line whose node shares no layer with the camera
            contributes none, and nor does one whose bounding sphere lies
            wholly outside the camera frustum, unless it opted out.

        Raises:
            Error: If a line names a node, a geometry or a material that
                is not there, if its geometry has no positions or carries
                an index buffer, if its point count does not suit its
                mode, if its material is not `BASIC` or carries a map, or
                if its material asks for vertex colors and the geometry
                has no `color` attribute of three or four floats per
                vertex.
        """
        var spans = List[_Span]()
        return self._prepared_lines(scene, assets, camera, spans)

    def _prepared_lines[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        mut spans: List[_Span],
        casters_only: Bool = False,
        receivers_cast: Bool = False,
        distance_casters: Bool = False,
    ) raises -> List[RasterVertex]:
        """Turn the lines and the wireframes in a scene into segments, in
        draw order, recording each one's run.

        The body of `prepare_lines`. The standalone lines are read in
        scene order and the wireframes after them, and the whole list is
        then put in draw order at once: opaque runs nearest first, blended
        runs furthest first, a wireframe sorted among the lines by its
        own depth rather than appended after them, which once let an
        opaque wireframe follow a blended line.

        Args:
            scene: The transform hierarchy, and the lines in it.
            assets: The geometries and materials the lines name.
            camera: The camera to project through.
            spans: Where each line's and each wireframe's run is recorded,
                with its depth and whether it blends, in the order the
                returned list holds them. Appended to.
            casters_only: Whether this is a light's view for a shadow map,
                which holds the lines and the wireframes that cast. A line
                there is drawn in its own material under the default
                state, and solid, as three.js draws it with its depth
                material, which has no dashes.
            receivers_cast: Whether that view also holds the lines and
                the wireframes that receive; see `_draws`.
            distance_casters: Whether that view is a point light's; see
                `_draws`.

        Returns:
            Raster vertices, two per segment, in draw order.

        Raises:
            Error: Everything `prepare_lines` raises.
        """
        if len(self.uv_space_meshes) > 0:
            return List[RasterVertex]()
        var frame = self._camera_frame(scene, camera)
        var view = frame.view
        var to_screen = frame.to_screen
        var near = frame.near
        var far = frame.far
        var clip = frame.clip
        var frustum = frame.frustum.copy()
        var sides = frame.sides.copy()
        var global_planes = frame.global_planes.copy()
        # One local bound per geometry, found the first time a line needs
        # it this frame, exactly as `_draws` keeps them for the meshes.
        var bounds = List[Sphere](
            length=assets.geometries.count(), fill=Sphere.empty()
        )
        var known = List[Bool](length=assets.geometries.count(), fill=False)
        var slack = far * CULL_SLACK

        # Every line the camera keeps, read in scene order and sorted
        # below with the wireframes. Per line and not per segment: one sort
        # key per object is what `_draws` uses, and a line is one object.
        var unsorted = List[_Span]()
        var corners = List[RasterVertex]()
        for index in range(len(scene.lines)):
            ref line = scene.lines[index]
            var kept, world, depth = _object_place(
                scene,
                assets,
                line.node,
                line.material,
                line.geometry,
                line.frustum_culled,
                line.cast_shadow,
                line.receive_shadow,
                casters_only,
                receivers_cast,
                camera,
                view,
                frustum,
                slack,
                bounds,
                known,
            )
            if not kept:
                continue
            var begin = len(corners)
            ref geometry = assets.geometries.get(line.geometry)
            # The line's own material says whether it is drawn and which
            # list it sorts in; the scene's override, when it takes it,
            # draws it. See `_drawn_material`.
            var own = assets.materials.get(line.material)
            if not own.visible:
                continue
            var blends = own.is_transparent()
            # A light's view keeps the line's own material, as it keeps a
            # mesh's; the scene's override is the frame's alone.
            var drawn = line.material if casters_only else _drawn_material(
                self.drawn_override(scene), own, line.material
            )
            var material = assets.materials.get(drawn)
            # A node material shades each segment as it shades a
            # triangle: a `ShaderMaterial` on a `Line`. A light's view
            # runs it too, for its mask and its cast shadow node.
            var program = _checked_nodes(assets, material.nodes)
            var physics = _Physics()
            physics.nodes = program
            # A dashed line is three.js's `dashed` shader, which does not
            # dither; a plain one is its `basic` shader, which does. A
            # light's view takes the default state; see `_draw_state`.
            var state = _draw_state(
                material, casters_only, not material.is_dashed(), False, True
            )
            var shown = _shown_of(material)
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_draw(
                material,
                scene,
                line.node,
                view,
                sides,
                global_planes,
                self.local_clipping_enabled,
                casters_only,
                cut,
                any_of,
            )
            # A line is unlit and untextured, and these refuse the
            # alternatives rather than carrying them and drawing neither.
            # See the module docstring of `objects.line`.
            if material.kind != BASIC:
                raise Error(
                    "A line material must be BASIC: a line has no surface,"
                    " so it has no normal for a light to reach"
                )
            if material.map != NO_TEXTURE or material.alpha_map != NO_TEXTURE:
                raise Error(
                    "A line material has no map: a line has no surface"
                    " coordinates to sample one with"
                )
            if material.has_env_map():
                raise Error(
                    "A line material has no env map: a line has no surface"
                    " to reflect from"
                )
            # A `Line` is drawn by the line pass, one pixel wide, and a
            # wide line by `prepare`, so a width here would be ignored.
            if (
                material.line_width != DEFAULT_LINE_WIDTH
                or material.dash_offset != NO_DASH
            ):
                raise Error(
                    "A Line is one pixel wide and has no dash offset: draw"
                    " a wider one as a LineSegments2"
                )
            if material.has_baked_map():
                raise Error(
                    "A line material has no ao map or light map: a line has"
                    " no surface coordinates to sample one with"
                )
            # An index buffer here is a triangle index -- `set_index`
            # demands whole triangles -- so it cannot say which points a
            # segment joins. A line geometry carries its points in order,
            # which is what three.js `EdgesGeometry` produces.
            if geometry.is_indexed():
                raise Error(
                    "A line geometry cannot be indexed: its points are"
                    " joined in the order they are given"
                )
            ref positions = geometry.attribute_view(String(POSITION))
            var vertex_count = positions.count()
            var base = _with_opacity(
                FloatColor(srgb=material.color), material.opacity
            )
            var colors = _vertex_colors(
                geometry, material.vertex_colors, base, vertex_count
            )
            # What a node program reads of each vertex: its coordinates
            # and its custom attributes, raw, as a mesh's corner has them.
            var coordinates = _coordinates(geometry, String(UV), vertex_count)
            var vertex_u = coordinates[0].copy()
            var vertex_v = coordinates[1].copy()
            var customs = _customs(assets, material, geometry, vertex_count)
            var moves = program != NO_NODES and assets.programs.get(
                program
            ).has(POSITION_NODE)
            var world_points = List[Vector3]()
            var view_points = List[Vector3]()
            for vertex in range(vertex_count):
                var local = Vector3(
                    positions.component(vertex, 0),
                    positions.component(vertex, 1),
                    positions.component(vertex, 2),
                )
                # A position node moves it in the model's own space; a
                # line has no normal, so the node reads zero.
                if moves:
                    local = moved_position(
                        assets.programs.get(program),
                        local,
                        Vector3(0, 0, 0),
                    )
                var point = world.transform_point(local)
                world_points.append(point)
                view_points.append(view.transform_point(point))
            # How far along the line each point is, in the geometry's own
            # space and scaled by the material, three.js's `vLineDistance`.
            # Worked out here rather than kept as an attribute, so a dashed
            # line cannot forget to have it worked out; see `objects.line`.
            # A solid line carries zeros, which no gap ever falls on.
            var dash = Float32(0)
            var gap = Float32(0)
            var along = List[Float32](length=vertex_count, fill=0)
            if material.is_dashed() and not casters_only:
                dash = material.dash_size.to(METER)
                gap = material.gap_size.to(METER)
                along = line_distances(line.mode, positions)
                for vertex in range(vertex_count):
                    along[vertex] *= material.dash_scale
            # A conditional line's flag, worked out here for each vertex
            # and blended along its segment, is drawn as a dash of one half,
            # so both backends leave out what three.js's shader discards. A
            # light's view draws it with its depth material, which does not.
            if line.conditional and not casters_only:
                if material.is_dashed():
                    raise Error(
                        "A conditional line is not dashed: its dash draws"
                        " its condition"
                    )
                for name in [
                    CONTROL0,
                    CONTROL1,
                    DIRECTION,
                ]:  # pragma: no branch
                    if not geometry.has_attribute(String(name)):
                        raise Error(
                            "A conditional line's geometry carries control0,"
                            " control1 and direction"
                        )
                ref first = geometry.attribute_view(String(CONTROL0))
                ref second = geometry.attribute_view(String(CONTROL1))
                ref toward = geometry.attribute_view(String(DIRECTION))
                var mvp = clip * view * world
                for vertex in range(vertex_count):  # pragma: no branch
                    along[vertex] = conditional_discard(
                        mvp,
                        Vector3(
                            positions.component(vertex, 0),
                            positions.component(vertex, 1),
                            positions.component(vertex, 2),
                        ),
                        Vector3(
                            toward.component(vertex, 0),
                            toward.component(vertex, 1),
                            toward.component(vertex, 2),
                        ),
                        Vector3(
                            first.component(vertex, 0),
                            first.component(vertex, 1),
                            first.component(vertex, 2),
                        ),
                        Vector3(
                            second.component(vertex, 0),
                            second.component(vertex, 1),
                            second.component(vertex, 2),
                        ),
                    )
                dash = CONDITIONAL_DASH
                gap = CONDITIONAL_GAP

            # The whole line must suit its mode, and then only the points
            # the draw range lets through are joined, as `drawArrays` joins
            # them: a loop closes on the first of them, and a list of
            # sticks leaves out a last point that has no partner.
            _ = segment_count(line.mode, vertex_count)
            var ranged = geometry.drawn_vertices()
            var joined = ranged[1]
            if line.mode == SEGMENTS:
                joined -= joined % 2
            for segment in range(segment_count(line.mode, joined)):
                var ends = segment_ends(line.mode, joined, segment)
                var first = ranged[0] + ends[0]
                var second = ranged[0] + ends[1]
                # The normal is zero because nothing reads it: the kind is
                # unlit. The color, the world position, the distance along
                # the line, and the coordinates and custom floats a node
                # program reads are what a segment varies.
                var from_end = ClipVertex(
                    view_points[first],
                    colors[first],
                    Vector3(0, 0, 0),
                    vertex_u[first],
                    vertex_v[first],
                    world_points[first],
                    line_distance=along[first],
                )
                from_end.custom = customs[first]
                var to_end = ClipVertex(
                    view_points[second],
                    colors[second],
                    Vector3(0, 0, 0),
                    vertex_u[second],
                    vertex_v[second],
                    world_points[second],
                    line_distance=along[second],
                )
                to_end.custom = customs[second]
                var kept = clip_segment(
                    from_end, to_end, near, far, cut, any_of
                )
                for end in range(len(kept)):
                    corners.append(
                        _to_raster(
                            kept[end],
                            to_screen,
                            NO_TEXTURE,
                            material.blending,
                            BASIC,
                            NO_TEXTURE,
                            NO_TEXTURE,
                            # No map, so there is no coverage to test.
                            0,
                            FloatColor(0.0, 0.0, 0.0),
                            0,
                            NO_TEXTURE,
                            NO_TEXTURE,
                            dash,
                            gap,
                            physics=physics,
                            state=state,
                            shown=shown,
                        )
                    )
                    corners[len(corners) - 1].custom = kept[end].custom
            _note_span(
                unsorted,
                DRAW_SEGMENTS,
                begin,
                len(corners),
                depth,
                blends,
                scene.render_order(line.node),
                _Source(line.node, line.geometry, drawn),
            )

        # And the meshes drawn as the lines of their own triangles.
        # `_prepared` shares everything up to primitive assembly with the
        # filled pass -- morph, skin, instance, cull, transform -- and
        # then assembles edges rather than triangles, so a wireframe of a
        # morphed or skinned mesh needs no second word about either.
        #
        # An edge shared by two triangles is drawn once: `triangle_edges`
        # pairs them, as three.js's `getWireframeAttribute` does. Drawing
        # it twice is not free even though it is the same pixels, because
        # a blended segment drawn over itself is twice as opaque.
        for index in range(assets.materials.count()):
            if assets.materials.get(MaterialId(index)).wireframe:
                # Asked before the work rather than after, so a scene with
                # no wireframe in it pays one pass over the materials
                # rather than a second pass over its geometry.
                var wire_spans = List[_Span]()
                var wired = self._prepared(
                    scene,
                    assets,
                    camera,
                    True,
                    wire_spans,
                    casters_only,
                    receivers_cast,
                    distance_casters=distance_casters,
                )
                var offset = len(corners) // 2
                corners.extend(Span(wired))
                for span in range(len(wire_spans)):
                    ref run = wire_spans[span]
                    unsorted.append(
                        _Span(
                            DRAW_SEGMENTS,
                            offset + run.first,
                            run.count,
                            run.depth,
                            run.blends,
                            run.order,
                            run.source,
                        )
                    )
                break

        # Into draw order: opaque runs nearest first, then blended runs
        # furthest first, lines and wireframes together. The same two
        # rules `_draws` applies to the meshes, for the same reasons.
        var order = _span_draw_order(unsorted)
        var ordered = List[RasterVertex]()
        ordered.reserve(len(corners))
        for position in range(len(order)):
            ref run = unsorted[order[position]]
            spans.append(
                _Span(
                    DRAW_SEGMENTS,
                    len(ordered) // 2,
                    run.count,
                    run.depth,
                    run.blends,
                    run.order,
                    run.source,
                )
            )
            ordered.extend(
                Span(corners)[run.first * 2 : (run.first + run.count) * 2]
            )
        self._encode_depth(ordered, camera)
        return ordered^

    def prepare_points[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
    ) raises -> List[
        RasterVertex
    ]:
        """Turn the points in a scene into the squares a rasterizer draws.

        `prepare_lines` for points: the same boundary and the same
        promise, and a third pass for the reason the lines have a second.
        A point has no surface, so it has no normal and no winding, and
        no second corner to interpolate anything toward. What it has is a
        position, a color, a depth and a size on the image, and a pass
        that carries only those is shorter than one that carries
        everything.

        `scene.update()` must have been called since the last transform
        change, as `prepare` needs.

        Args:
            scene: The transform hierarchy, and the points in it.
            assets: The geometries, materials and textures the points name.
            camera: The camera to project through.

        Returns:
            Raster vertices, one per point, each carrying its size on the
            image with the attenuation applied. Opaque points come first,
            nearest first, then the blended ones furthest first, as the
            lines are ordered and for the same reasons. A point whose node
            shares no layer with the camera contributes none, nor does one
            whose bounding sphere lies wholly outside the camera frustum
            unless it opted out, nor does a point outside the view volume:
            a point is kept or thrown away whole, as three.js's is.

        Raises:
            Error: If the points name a node, a geometry or a material
                that is not there, if their geometry has no positions or
                carries an index buffer, if their material is not `BASIC`
                or is a wireframe, if it names a map or an alpha map that
                is not there or whose transform is not the identity, if
                its alpha map is not stored as data, or if it asks for
                vertex colors and the geometry has no `color` attribute
                of three or four floats per vertex.
        """
        var spans = List[_Span]()
        return self._prepared_points(scene, assets, camera, spans)

    def _prepared_points[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        mut spans: List[_Span],
        casters_only: Bool = False,
        receivers_cast: Bool = False,
    ) raises -> List[RasterVertex]:
        """Turn the points in a scene into raster vertices, in draw order,
        recording each object's run.

        The body of `prepare_points`, shaped as `_prepared_lines` is: every
        object read in scene order, then the whole list put in draw order
        at once.

        Args:
            scene: The transform hierarchy, and the points in it.
            assets: The geometries, materials and textures the points name.
            camera: The camera to project through.
            spans: Where each object's run is recorded, with its depth and
                whether it blends, in the order the returned list holds
                them. Appended to.
            casters_only: Whether this is a light's view for a shadow map,
                which holds the points that cast. A point there is drawn
                in its own material under the default state, one texel
                wide: three.js draws it with its depth material, whose
                shader sets no `gl_PointSize`, and WebGL draws one pixel.
            receivers_cast: Whether that view also holds the points that
                receive; see `_draws`.

        Returns:
            Raster vertices, one per point, in draw order.

        Raises:
            Error: Everything `prepare_points` raises.
        """
        if len(self.uv_space_meshes) > 0:
            return List[RasterVertex]()
        var frame = self._camera_frame(scene, camera)
        var view = frame.view
        var to_screen = frame.to_screen
        var near = frame.near
        var far = frame.far
        var frustum = frame.frustum.copy()
        var sides = frame.sides.copy()
        var global_planes = frame.global_planes.copy()
        var perspective = not camera.projection_matrix().is_affine()
        # Half the height of the image the caller asked for: three.js's
        # `scale` uniform, which a point's size is measured against at a
        # depth of one meter. The whole target and not the viewport, as
        # three.js reads the drawing buffer's height whatever the
        # viewport -- and the *output* height rather than this renderer's,
        # so that a supersampled frame measures the size against the image
        # it will become. `attenuated_size` takes the render scale
        # separately and applies it to both kinds of point; see
        # `render_scale`.
        var scale = Float32(self.height // self.render_scale) / 2
        var bounds = List[Sphere](
            length=assets.geometries.count(), fill=Sphere.empty()
        )
        var known = List[Bool](length=assets.geometries.count(), fill=False)
        var slack = far * CULL_SLACK

        var unsorted = List[_Span]()
        var corners = List[RasterVertex]()
        for index in range(len(scene.points)):
            ref points = scene.points[index]
            var kept, world, depth = _object_place(
                scene,
                assets,
                points.node,
                points.material,
                points.geometry,
                points.frustum_culled,
                points.cast_shadow,
                points.receive_shadow,
                casters_only,
                receivers_cast,
                camera,
                view,
                frustum,
                slack,
                bounds,
                known,
            )
            if not kept:
                continue
            var begin = len(corners)
            ref geometry = assets.geometries.get(points.geometry)
            var own = assets.materials.get(points.material)
            if not own.visible:
                continue
            var blends = own.is_transparent()
            var drawn = points.material if casters_only else _drawn_material(
                self.drawn_override(scene), own, points.material
            )
            var material = assets.materials.get(drawn)
            # A node material shades each point's square as it shades a
            # triangle, three.js's `PointsNodeMaterial` and a
            # `ShaderMaterial` on `Points`. A light's view runs it too, as
            # it does for a line.
            var program = _checked_nodes(assets, material.nodes)
            var physics = _Physics()
            physics.nodes = program
            # three.js's `points` shader premultiplies and does not dither.
            # A light's view takes the default state; see `_draw_state`.
            var state = _draw_state(material, casters_only, False, False, True)
            var shown = _shown_of(material)
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_draw(
                material,
                scene,
                points.node,
                view,
                sides,
                global_planes,
                self.local_clipping_enabled,
                casters_only,
                cut,
                any_of,
            )
            # A point is unlit, and refuses a lit kind rather than being
            # shaded by a normal it does not have. See `objects.points`.
            if material.kind != BASIC:
                raise Error(
                    "A points material must be BASIC: a point has no"
                    " surface, so it has no normal for a light to reach"
                )
            if material.wireframe:
                raise Error(
                    "A points material cannot be a wireframe: a point has"
                    " no edges to draw"
                )
            if material.has_env_map():
                raise Error(
                    "A points material has no env map: a point has no"
                    " surface to reflect from"
                )
            if material.has_baked_map():
                raise Error(
                    "A points material has no ao map or light map: a point"
                    " has no surface for either to reach"
                )
            var maps = _checked_maps(assets, material, self.shading)
            # A point samples its maps at its own coordinate, as stored;
            # see `render.pointrule.coord`. A map moved, tiled or turned
            # would be sampled somewhere its author did not say, so it is
            # refused rather than sampled untransformed, whatever the
            # shading mode: it is a wrong asset, not a wrong frame.
            _check_map_channels(assets, material)
            if _moves_a_map(assets, material):
                raise Error(
                    "A point samples its map at its own coordinate, as"
                    " stored: a map whose transform is not the identity is"
                    " refused"
                )
            if geometry.is_indexed():
                raise Error(
                    "A points geometry cannot be indexed: each vertex is"
                    " one point"
                )
            ref positions = geometry.attribute_view(String(POSITION))
            var vertex_count = positions.count()
            var base = _with_opacity(
                FloatColor(srgb=material.color), material.opacity
            )
            var colors = _vertex_colors(
                geometry, material.vertex_colors, base, vertex_count
            )
            # What a node program reads of each point: its coordinates
            # and its custom attributes, raw, as a mesh's corner has them.
            var noded = program != NO_NODES
            var coordinates = _coordinates(geometry, String(UV), vertex_count)
            var vertex_u = coordinates[0].copy()
            var vertex_v = coordinates[1].copy()
            var customs = _customs(assets, material, geometry, vertex_count)
            var moves = noded and assets.programs.get(program).has(
                POSITION_NODE
            )
            var sized = (
                noded
                and not casters_only
                and assets.programs.get(program).has(SIZE_NODE)
            )
            # The size node reads the frame's time and view, as the
            # frame's copy of the program has them.
            var sizer = NodeProgram()
            if sized:
                sizer = assets.programs.get(program).copy()
                sizer.set_frame(self.time, view)
            # Only the points the draw range lets through.
            var ranged = geometry.drawn_vertices()
            for vertex in range(ranged[0], ranged[0] + ranged[1]):
                var local = Vector3(
                    positions.component(vertex, 0),
                    positions.component(vertex, 1),
                    positions.component(vertex, 2),
                )
                # A position node moves it in the model's own space; a
                # point has no normal, so the node reads zero.
                if moves:
                    local = moved_position(
                        assets.programs.get(program),
                        local,
                        Vector3(0, 0, 0),
                    )
                var point = world.transform_point(local)
                var seen = view.transform_point(point)
                # Kept or thrown away whole: a point has no extent in the
                # scene to cut, so one whose center is outside the volume
                # is left out, as OpenGL leaves it out.
                if not within_depth(seen.z, near, far):
                    continue
                if not within_sides(seen, cut):
                    continue
                if not within_any(seen, any_of):
                    continue
                var u = vertex_u[vertex]
                var v = vertex_v[vertex]
                # The size node, once per point, in pixels, in place of
                # the material's size and its attenuation. A light's view
                # draws every point one pixel across, as it does without.
                var size = attenuated_size(
                    material.point_size.pixels,
                    seen.z,
                    scale,
                    perspective and material.size_attenuation,
                    self.render_scale,
                )
                if sized:
                    size = point_size_of(
                        sizer,
                        NodeInputs(
                            u,
                            v,
                            point,
                            Vector3(0, 0, 0),
                            Vector3(
                                colors[vertex].r,
                                colors[vertex].g,
                                colors[vertex].b,
                            ),
                            Vector3(0, 0, 0),
                            False,
                            customs[vertex],
                        ),
                    ) * Float32(self.render_scale)
                    require_positive_finite(
                        Float64(size),
                        (
                            "A point's size node gave a size that is not above"
                            " zero"
                        ),
                    )
                corners.append(
                    _to_raster(
                        ClipVertex(
                            seen,
                            colors[vertex],
                            Vector3(0, 0, 0),
                            u,
                            v,
                            point,
                        ),
                        to_screen,
                        maps[0],
                        material.blending,
                        BASIC,
                        NO_TEXTURE,
                        maps[1],
                        material.alpha_test,
                        FloatColor(0.0, 0.0, 0.0),
                        0,
                        NO_TEXTURE,
                        NO_TEXTURE,
                        point_size=Float32(1) if casters_only else size,
                        physics=physics,
                        state=state,
                        shown=shown,
                    )
                )
                corners[len(corners) - 1].custom = customs[vertex]
            _note_span(
                unsorted,
                DRAW_POINTS,
                begin,
                len(corners),
                depth,
                blends,
                scene.render_order(points.node),
                _Source(points.node, points.geometry, drawn),
            )

        # Into draw order, as `_prepared_lines` puts the lines.
        var order = _span_draw_order(unsorted)
        var ordered = List[RasterVertex]()
        ordered.reserve(len(corners))
        for position in range(len(order)):
            ref run = unsorted[order[position]]
            spans.append(
                _Span(
                    DRAW_POINTS,
                    len(ordered),
                    run.count,
                    run.depth,
                    run.blends,
                    run.order,
                    run.source,
                )
            )
            ordered.extend(Span(corners)[run.first : run.first + run.count])
        self._encode_depth(ordered, camera)
        return ordered^

    def prepare_frame[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        keeps_velocity: Bool = False,
    ) raises -> Frame:
        """Turn a scene into a frame: its triangles, its segments, its
        points, and the one order all three are drawn in.

        `prepare`, `prepare_lines` and `prepare_points` together, with
        what no list can say on its own: where a run of one kind goes
        among the runs of the others. Opaque runs come first, the
        triangles nearest first, then the segments and then the points,
        each nearest first, which is safe in any order because an opaque
        fragment settles a pixel by depth alone. Blended runs follow, all
        three kinds together, furthest first by the depth of each draw's
        own placed origin, so that a translucent line is drawn after the
        translucent surface behind it and before the one in front of it.
        Drawing every line after every triangle, as the two lists were
        once drawn, put an opaque line behind a translucent pane on top of
        it, or, once the pane claimed its depth, left the line out of the
        mix.

        Args:
            scene: The transform hierarchy, and the meshes, lines, points
                and lights in it.
            assets: The geometry, materials and textures they name.
            camera: The camera to project through.
            keeps_velocity: Whether the frame is drawn into a target with
                a velocity attachment. The camera's matrices move on, as
                three.js's `VelocityNode` moves them once a frame, and
                each mesh's corners carry where the last such frame had
                them. See `render.rasterizer.fragment_velocity`.

        Returns:
            The frame. `Renderer.render` fills it with `rasterize_frame`
            and `GpuRenderer.draw` takes its four lists as they are.

        Raises:
            Error: Everything `prepare`, `prepare_lines` and
                `prepare_points` raise, and anything `camera` raises for
                its view.
        """
        var corner_spans = List[_Span]()
        self._state[].tracks_velocity = keeps_velocity
        if keeps_velocity:
            self._state[].advance_camera(
                camera.view_matrix_in(scene), camera.projection_matrix()
            )
        var corners: _Slim
        try:
            corners = self._prepared_slim(
                scene, assets, camera, False, corner_spans
            )
        finally:
            # Each object drawn keeps its matrix for the next frame, even
            # when this one is refused, and no later frame keeps
            # velocities it did not ask for.
            self._state[].commit_worlds()
        var segment_spans = List[_Span]()
        var segments = self._prepared_lines(
            scene, assets, camera, segment_spans
        )
        var point_spans = List[_Span]()
        var points = self._prepared_points(scene, assets, camera, point_spans)
        var opaque = List[_Span]()
        for span in range(len(corner_spans)):
            ref run = corner_spans[span]
            if not run.blends and not run.transmits:
                opaque.append(run)
        for span in range(len(segment_spans)):
            if not segment_spans[span].blends:
                opaque.append(segment_spans[span])
        for span in range(len(point_spans)):
            if not point_spans[span].blends:
                opaque.append(point_spans[span])
        # A caller's opaque sort, three.js's `setOpaqueSort`, orders every
        # opaque run of every kind at once. Without one, the triangles go
        # first, then the segments and then the points, each nearest first.
        var sorted_opaque = Bool(self._opaque_sort)
        if sorted_opaque:
            _sort_with(opaque, self._opaque_sort.value())
        var draws = List[Draw]()
        var items = List[RenderItem]()
        for position in range(len(opaque)):
            _add_run(draws, items, opaque[position])
        # The transmissive runs, after every opaque run and before every
        # blended one, furthest first, as three.js draws its
        # `transmissive` list between its `opaque` and `transparent`
        # lists and sorts it as it sorts the transparent one. A
        # transmissive run that also blends is drawn here, as three.js
        # puts an object with any transmission on that list first.
        var clear = List[_Span]()
        for span in range(len(corner_spans)):
            if corner_spans[span].transmits:
                clear.append(corner_spans[span])
        _furthest_first(clear, self._transparent_sort)
        for position in range(len(clear)):
            _add_run(draws, items, clear[position])
        # Every kind's blended runs, furthest first. Each list is already
        # in that order on its own; the sort is stable, so at one depth a
        # surface still goes before a line, and a line before a point.
        var mixed = List[_Span]()
        for span in range(len(corner_spans)):
            if corner_spans[span].blends and not corner_spans[span].transmits:
                mixed.append(corner_spans[span])
        for span in range(len(segment_spans)):
            if segment_spans[span].blends:
                mixed.append(segment_spans[span])
        for span in range(len(point_spans)):
            if point_spans[span].blends:
                mixed.append(point_spans[span])
        var splats = List[ProjectedSplat]()
        var view = camera.view_matrix_in(scene)
        for index in range(len(scene.gaussian_splats)):
            ref object = scene.gaussian_splats[index][]
            var prepared = prepare_gaussian_splat(
                scene,
                object,
                camera,
                self.width,
                self.height,
                self.depth_mode_for(camera),
                self.viewport,
                self.workers,
            )
            if len(prepared) == 0:
                continue
            var first = len(splats)
            splats.extend(Span(prepared))
            var origin = view.transform_point(
                scene.world_matrix(object.node).transform_point(
                    Vector3(0, 0, 0)
                )
            )
            mixed.append(
                _Span(
                    DRAW_SPLATS,
                    first,
                    len(prepared),
                    origin.z,
                    True,
                    scene.render_order(object.node),
                    _Source(object.node, GeometryId(-1), MaterialId(-1)),
                )
            )
        _furthest_first(mixed, self._transparent_sort)
        for position in range(len(mixed)):
            _add_run(draws, items, mixed[position])
        # The node programs, with this frame's time and view written in, as
        # three.js updates its `time` and camera nodes before a frame.
        var programs = assets.programs.copy()
        programs.set_frame(self.time, camera.view_matrix_in(scene))
        return Frame(
            corners.take_corners(),
            corners.take_surfaces(),
            segments^,
            draws^,
            points^,
            programs^,
            items^,
            splats^,
        )

    def render[
        C: Camera
    ](self, scene: Scene, assets: Assets, camera: C,) raises -> Framebuffer:
        """Draw every mesh in the scene on the CPU and return the image.

        `prepare` does the work; this fills the triangles it produces. The
        shape is three.js's `renderer.render(scene, camera)` plus the one
        argument Mojo needs and JavaScript does not: who owns the geometry.

        Args:
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

        Returns:
            The rendered image.

        Raises:
            Error: Everything `render_into` raises.
        """
        var hooks = NoHooks()
        return self.render_with(hooks, scene, assets, camera)

    def render_with[
        C: Camera, H: RenderHooks
    ](
        self, mut hooks: H, scene: Scene, assets: Assets, camera: C
    ) raises -> Framebuffer:
        """Draw the scene as `render` does, running `hooks` around it.

        Args:
            hooks: What runs before and after the scene, each run and each
                shadow caster; see `RenderHooks`.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

        Returns:
            The rendered image.

        Raises:
            Error: Everything `render_into` raises, and whatever a hook
                raises.
        """
        if self.antialias:
            # Drawn at `SUPERSAMPLE` times the size by a renderer that
            # does not supersample, and averaged down *before* the one
            # conversion below rather than after it: the samples are scene
            # radiance and the average of radiance is what an output pixel
            # holds. See `RenderTarget.downsampled` and `render.antialias`.
            var big = self.supersampled()
            var drawn = RenderTarget(big.width, big.height, self.background)
            big.render_into_with(hooks, drawn, scene, assets, camera)
            return drawn.downsampled(SUPERSAMPLE).resolve(
                self.workers,
                self.tone_curve(),
                self.tone_mapping_exposure,
                self.curve_program(assets),
                self.output_encoding(),
            )
        var target = RenderTarget(self.width, self.height, self.background)
        self.render_into_with(hooks, target, scene, assets, camera)
        # Linear light becomes an image exactly once, here, on as many
        # threads as drew it, through the tone mapping curve on the way --
        # except in the uv view, which is coordinates rather than light and
        # is never tone mapped, background included, on either backend. A
        # normal or depth material's pixels are data too, and the target
        # keeps the curve off them by itself.
        return target.resolve(
            self.workers,
            self.tone_curve(),
            self.tone_mapping_exposure,
            self.curve_program(assets),
            self.output_encoding(),
        )

    def render_array(
        mut self, scene: Scene, assets: Assets, array: ArrayCamera
    ) raises -> Framebuffer:
        """Draw the scene once per camera of `array`, each into its own
        rectangle of one image, and return the image.

        three.js's `WebGLRenderer.render` given an `ArrayCamera`: the
        viewport and the scissor are set to each sub camera's rectangle
        in turn, that rectangle is cleared to the background and drawn
        through the camera, and the target is resolved once at the end.
        The renderer's own viewport, scissor and scissor test are put
        back afterward.

        Args:
            scene: The transform hierarchy, and what it draws.
            assets: The geometry, materials and textures they name.
            array: The cameras and their rectangles.

        Returns:
            The rendered image. An array of no cameras gives the
            background alone.

        Raises:
            Error: If a rectangle reaches outside the target, or anything
                `render_into` raises for one of the cameras.
        """
        if self.antialias:
            # As `render` does it, and resolved in linear light for the
            # same reason: every rectangle is drawn at the larger size and
            # the whole target is averaged down once, before the light
            # becomes an image.
            var big = self.supersampled()
            var scaled = ArrayCamera()
            for index in range(array.count()):
                scaled.add(
                    array.cameras[index],
                    _scaled(array.viewports[index], SUPERSAMPLE),
                )
            var drawn = RenderTarget(big.width, big.height, self.background)
            big.render_array_into(drawn, scene, assets, scaled)
            return drawn.downsampled(SUPERSAMPLE).resolve(
                self.workers,
                self.tone_curve(),
                self.tone_mapping_exposure,
                self.curve_program(assets),
                self.output_encoding(),
            )
        var target = RenderTarget(self.width, self.height, self.background)
        self.render_array_into(target, scene, assets, array)
        return target.resolve(
            self.workers,
            self.tone_curve(),
            self.tone_mapping_exposure,
            self.curve_program(assets),
            self.output_encoding(),
        )

    def _require_target_size(self, target: RenderTarget) raises:
        """Refuse a target that is not this renderer's size.

        Nothing. The call returns when the target matches.

        Args:
            target: The target to draw or clear.

        Raises:
            Error: If the width or the height differs.
        """
        if target.width != self.width or target.height != self.height:
            raise Error("A target must be the renderer's size")

    def render_array_into(
        mut self,
        mut target: RenderTarget,
        scene: Scene,
        assets: Assets,
        array: ArrayCamera,
    ) raises:
        """Draw the scene once per camera of `array` into `target`, each
        into its own rectangle, and resolve nothing.

        `render_array` without the target's creation and its resolution,
        as `render_into` is to `render`. Pixels outside every rectangle
        are left as they were.

        Args:
            target: The target to draw into. It must be the renderer's
                size.
            scene: The transform hierarchy, and what it draws.
            assets: The geometry, materials and textures they name.
            array: The cameras and their rectangles.

        Raises:
            Error: If the target is not the renderer's size, the array's
                cameras and rectangles do not pair up, a rectangle
                reaches outside the target, or anything `render_into`
                raises for one of the cameras. The first three are
                refused before anything is drawn. A camera refused after
                an earlier one drew leaves that one's rectangle drawn:
                the renderer's settings are put back, the target is not.
        """
        # Asked here as well as by `render_into`, which an array of no
        # cameras never calls.
        self._require_target_size(target)
        var viewport = self.viewport
        var scissor = self.scissor
        var scissor_test = self.scissor_test
        # Every rectangle is checked before any is drawn, so a bad one
        # leaves the target untouched rather than half drawn. `count`
        # refuses lists that do not pair up.
        for index in range(array.count()):
            if not array.viewports[index].fits(self.width, self.height):
                raise Error(
                    "A sub camera's viewport must lie inside the target"
                )
        self.scissor_test = True
        var hooks = NoHooks()
        try:
            for index in range(array.count()):
                self.viewport = array.viewports[index]
                self.scissor = array.viewports[index]
                # One frame, however many cameras, as three.js counts an
                # array camera's `render`.
                _ = self._draw_into(
                    hooks,
                    target,
                    scene,
                    assets,
                    array.cameras[index],
                    index == 0,
                )
        except failure:
            # Put back whatever a refused camera left set, then say why.
            self.viewport = viewport
            self.scissor = scissor
            self.scissor_test = scissor_test
            raise failure
        self.viewport = viewport
        self.scissor = scissor
        self.scissor_test = scissor_test

    def tone_curve(self) -> ToneMapping:
        """Return the curve `render` resolves a target through: the tone
        mapping set, or none in the uv view, which is coordinates rather
        than light and is never tone mapped.

        For a caller that fills a target with `render_into` and resolves it
        itself, so it resolves it as `render` would.
        """
        if self.shading == SHADE_UV:
            return NO_TONE_MAPPING
        return self.tone_mapping

    def curve_program(self, assets: Assets) raises -> List[Float32]:
        """Return the custom curve's program as `RenderTarget.resolve`
        takes it, for a caller that resolves a target itself.

        Args:
            assets: Where `custom_tone_mapping` names its program.

        Returns:
            The program's floats under `CUSTOM_TONE_MAPPING` with a
            program set, and none otherwise.

        Raises:
            Error: If `custom_tone_mapping` names a program that is not in
                `assets.programs`.
        """
        var none = List[Float32]()
        if self.custom_tone_mapping == NO_NODES:
            return none^
        var code = assets.programs.get(self.custom_tone_mapping).code.copy()
        if self.tone_curve() != CUSTOM_TONE_MAPPING:
            return none^
        return code^

    def clear(
        self,
        mut target: RenderTarget,
        color: Bool = True,
        depth: Bool = True,
        stencil: Bool = True,
    ) raises:
        """Clear the target's color, depth or stencil, three.js's `clear`.

        The color is this renderer's `background`, three.js's clear color.
        With the scissor test on, the scissor alone is cleared.

        Args:
            target: The target to clear.
            color: Whether the color is cleared.
            depth: Whether the depth is cleared.
            stencil: Whether the stencil is cleared.

        Raises:
            Error: If the target is not the renderer's size, or the
                renderer's depth mode is none of the three.
        """
        self._require_target_size(target)
        var kept = Rect.whole(self.width, self.height)
        if self.scissor_test:
            kept = self.scissor
        target.clear_inside(
            kept, self.background, self.depth_mode, color, depth, stencil
        )

    def render_into[
        C: Camera
    ](
        self, mut target: RenderTarget, scene: Scene, assets: Assets, camera: C
    ) raises:
        """Draw every mesh in the scene on the CPU into `target`, clearing
        first, and resolve nothing.

        What `_draw_into` does with no hooks, as one frame.

        Args:
            target: The target to draw into. It must be the renderer's size.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

        Raises:
            Error: Everything `_draw_into` raises.
        """
        var hooks = NoHooks()
        _ = self._draw_into(hooks, target, scene, assets, camera, True)

    def render_into_keeping_shadows[
        C: Camera
    ](
        self, mut target: RenderTarget, scene: Scene, assets: Assets, camera: C
    ) raises -> List[ShadowMap]:
        """Draw the scene into `target` as `render_into` does, and return
        the shadow maps the frame drew.

        A caller that reads the shadows again after the frame -- a
        screen-space effect that asks which pixels the sun reaches --
        takes them here rather than drawing every caster into every map a
        second time with `shadow_maps`.

        Args:
            target: The target to draw into. It must be the renderer's size.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

        Returns:
            The maps, as `shadow_maps` returns them for the camera's layers.

        Raises:
            Error: Everything `_draw_into` raises.
        """
        var hooks = NoHooks()
        return self._draw_into(hooks, target, scene, assets, camera, True)

    def render_into_with_shadows[
        C: Camera
    ](
        self,
        mut target: RenderTarget,
        scene: Scene,
        assets: Assets,
        camera: C,
        shadows: List[ShadowMap],
    ) raises:
        """Draw with an independent copy of the caller's shadow maps.

        Views can share maps when their lights, casters and visible layers
        are the same. Use `render_into_reusing_shadows` to transfer the maps
        between views without copying their texels.

        Args:
            target: The target to draw into. It must be the renderer's size.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.
            shadows: The maps, from `shadow_maps` for the camera's layers.

        Raises:
            Error: Everything `_draw_into` raises.
        """
        _ = self.render_into_reusing_shadows(
            target, scene, assets, camera, shadows.copy()
        )

    def render_into_reusing_shadows[
        C: Camera
    ](
        self,
        mut target: RenderTarget,
        scene: Scene,
        assets: Assets,
        camera: C,
        var shadows: List[ShadowMap],
    ) raises -> List[ShadowMap]:
        """Draw the scene into `target` as `render_into` does, with shadow
        maps the caller drew rather than drawing them.

        Views of one scene with the same visible layers can share their
        maps. Transfer `shadows` with `^` and keep the return value to
        reuse their storage without copying it between views. A caller
        that must keep its maps can use `render_into_with_shadows`.

        Args:
            target: The target to draw into. It must be the renderer's size.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.
            shadows: The maps, from `shadow_maps` for the camera's layers.

        Returns:
            The maps used by this frame, moved without copying their texels.

        Raises:
            Error: Everything `_draw_into` raises.
        """
        var hooks = NoHooks()
        return self._draw_into(
            hooks, target, scene, assets, camera, True, shadows^
        )

    def render_into_with[
        C: Camera, H: RenderHooks
    ](
        self,
        mut hooks: H,
        mut target: RenderTarget,
        scene: Scene,
        assets: Assets,
        camera: C,
    ) raises:
        """Draw the scene into `target` as `render_into` does, running
        `hooks` around it.

        Args:
            hooks: What runs before and after the scene, each run and each
                shadow caster; see `RenderHooks`.
            target: The target to draw into. It must be the renderer's size.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

        Raises:
            Error: Everything `_draw_into` raises, and whatever a hook
                raises.
        """
        _ = self._draw_into(hooks, target, scene, assets, camera, True)

    def _draw_into[
        C: Camera, H: RenderHooks
    ](
        self,
        mut hooks: H,
        mut target: RenderTarget,
        scene: Scene,
        assets: Assets,
        camera: C,
        first: Bool,
        var shadows: Optional[List[ShadowMap]] = None,
    ) raises -> List[ShadowMap]:
        """Draw every mesh in the scene on the CPU into `target`, clearing
        first, and resolve nothing, and return the shadow maps it drew.

        `render` without the target's creation and its resolution, for a
        caller that draws more than one view into one image: a split
        screen is two cameras, two viewports and two scissors drawing into
        one target, each clearing its own rectangle and leaving the
        other's alone, as three.js draws one with `setScissorTest`. The
        caller resolves the target once, through `tone_curve`.

        With the scissor test on, the scissor is cleared to the background
        and drawn into, and no other pixel is touched. Off, the whole
        target is.

        The hooks run in three.js's order: the scene's before anything
        is prepared, each shadow caster's once the shadow maps are drawn,
        each run's before and after the frame is rasterized, in the
        frame's draw order, and the scene's after. `Renderer.info` counts
        the frame. With `auto_clear` off, nothing is cleared.

        Args:
            hooks: What runs around the frame.
            target: The target to draw into. It must be the renderer's
                size. Its type and outputs are its own: a target with an
                `OUTPUT_NORMAL` attachment receives every opaque
                triangle's view-space normal in the same pass, three.js's
                multiple render targets. A target with `samples` is drawn
                by `multisampled(samples)` into its `multisample_buffer`
                and resolved into the pixels the draw may touch, three.js's
                multisampled render target. See `render.target`.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.
            first: Whether this starts a frame of `info`, rather than
                adding a camera of an array to the one before it.
            shadows: The shadow maps to light the frame with, or None to
                draw them.

        Raises:
            Error: If the target is not the renderer's size, if a mesh
                names a node or a geometry that is not there, its geometry
                has no positions, the scene's fog holds a kind that is
                none of the three or a range that is inside out -- see
                `core.fog.FogView` -- or a tone mapping curve is set and
                the scene holds both a data material and a blended one,
                which no pixel could resolve; see
                `render.rasterizer.check_output_kinds`.
        """
        self._require_target_size(target)
        if target.samples > 1:
            # three.js's multisampled render target: the samples are drawn
            # by a renderer `sample_grid` times the size, which refuses a
            # scene before its buffer is touched, and resolved into the
            # target once the draw is done. Only the pixels the draw may
            # touch are resolved, so a scissor keeps the rest.
            var buffer = target.multisample_buffer()
            var maps = self.multisampled(target.samples)._draw_into(
                hooks, buffer, scene, assets, camera, first, shadows^
            )
            var drawn = Rect.whole(self.width, self.height)
            if self.scissor_test:
                drawn = self.scissor
            target.resolve_samples(buffer, drawn)
            target.set_scissor(drawn)
            return maps^
        hooks.on_before_scene(scene)
        # Prepared and checked before a pixel is touched, so a scene that
        # is refused leaves a target another view was drawn into as it was.
        # A target with a velocity attachment makes a frame that keeps
        # velocities.
        var frame = self.prepare_frame(
            scene, assets, camera, target.has_velocities()
        )
        # A filtered beauty draw still reads the whole opaque scene. Save
        # its draw order before ONE_OIT_DRAW removes the opaque objects;
        # the corners and surfaces remain the same prepared frame below.
        # Frames without requested volume depth keep the existing path.
        var volume_opaque: Optional[List[Draw]] = None
        if (
            self.draw_filter != ALL_DRAWS
            and self.shading != SHADE_UV
            and _needs_volume_depth(frame)
        ):
            volume_opaque = _opaque_draws(frame)
        # The draws a filter leaves out, and the snap; see
        # `renderers.draw_filter`.
        check_draw_filter(self.draw_filter, self.oit_draw)
        var alone = self.draw_filter == ONE_OIT_DRAW
        if self.draw_filter != ALL_DRAWS:
            var capable = List[Bool]()
            for index in range(len(frame.items)):
                capable.append(
                    frame.items[index].kind != DRAW_SPLATS
                    and oit_capable(
                        assets.materials.get(frame.items[index].material)
                    )
                )
            var kept = kept_draws(capable, self.draw_filter, self.oit_draw)
            var draws = List[Draw]()
            var items = List[RenderItem]()
            for index in range(len(kept)):
                if kept[index]:
                    draws.append(frame.draws[index])
                    items.append(frame.items[index])
            frame.draws = draws^
            frame.items = items^
        if self.snap_vertices:
            snap_to_pixels(frame.corners, self.width, self.height)
        # Two output representations cannot share a tone-mapped frame. Asked
        # here, before anything is drawn, exactly where `GpuRenderer.draw`
        # asks it before a launch. The uv view is data throughout and is
        # never tone mapped, so it is never refused; see below.
        check_output_kinds(
            frame.surfaces,
            self.shading != SHADE_UV and self.tone_mapping != NO_TONE_MAPPING,
            frame.segments,
            frame.points,
            len(frame.splats) > 0,
        )
        # Resolved here as well as in `prepare`, because the fragments need
        # it: lighting is no longer baked into the corners on the way past.
        # Only the lights on the camera's layers, as only its meshes were
        # prepared: a light the camera does not see lights nothing it draws.
        # The camera's own position goes with them, because a `PHONG`
        # surface's highlight is measured from wherever the camera stands
        # -- or from one fixed direction, if the camera's rays are parallel
        # rather than converging. See `toward_camera`. Which way is up for
        # the camera goes with them too, for the frame a `MATCAP` surface
        # is looked up in, and which way is back, for a target that keeps
        # view-space normals. See `camera_up`.
        var lighting = self._lighting(scene, assets, camera, shadows^)
        # And the lights of each material that names its own, three.js's
        # `lightsNode`.
        var lightings = self._lightings(scene, assets, camera, lighting)
        # The shadow maps are drawn, so their casters are known.
        ref state = self._state[]
        for index in range(len(state.shadow_items)):
            hooks.on_before_shadow(
                scene, state.shadow_items[index], state.shadow_lights[index]
            )
        # The scene's fog as the rasterizer takes it. Each corner already
        # carries the depth `prepare` measured for it along this view.
        var fog = FogView(scene.fog)
        fog.validate()
        var kept = Rect.whole(self.width, self.height)
        if self.scissor_test:
            kept = self.scissor
        target.set_scissor(kept)
        # The scene's background, then the renderer's own: three.js clears
        # to `scene.background` when it is a color and to the clear color
        # otherwise, and then draws a texture or a cube background over
        # the clear before the scene. See `core.background`.
        #
        # The backdrop is built *before* the clear, though it is painted
        # after it. It is the last thing in this function that can refuse
        # the frame -- a background naming a texture that is not there --
        # and a target is a buffer the caller keeps and draws several
        # views into. Clearing first meant a refused background erased a
        # view that had already been drawn and then raised, so the caller
        # lost an image to an error that touched nothing. Everything that
        # can be refused is now asked before anything is written.
        var backdrop = self.backdrop(scene, assets, camera)
        # The opaque scene a transmissive surface looks through, drawn
        # before the frame as three.js draws its transmission pass, and
        # before the clear, since it too can be refused.
        var seen = self._transmission_pass(
            frame, scene, assets, camera, lighting, fog, backdrop, volume_opaque
        )
        _ = self.curve_program(assets)
        if first:
            state.begin_frame(self.info_auto_reset)
        state.count(frame.items)
        for index in range(len(frame.items)):
            hooks.on_before_render(scene, frame.items[index])
        # One order-independent draw alone is weighed over nothing, as
        # three.js clears its accumulation target to transparent black.
        var cleared = self.clear_color(scene)
        if alone:
            cleared = Color(0, 0, 0, 0)
        if self.auto_clear:
            target.clear_inside(
                kept,
                cleared,
                self.depth_mode_for(camera),
                self.auto_clear_color,
                self.auto_clear_depth,
                self.auto_clear_stencil,
            )
        # Spelled as a Bool rather than testing the Optional directly,
        # because the coverage instrumenter wraps every condition in a
        # probe that takes a Bool; see `materials.material`. A frame in
        # texture space has no background: it is not seen through a camera.
        var painted = (
            Bool(backdrop) and len(self.uv_space_meshes) == 0 and not alone
        )
        if painted:
            _paint_backdrop(target, kept, backdrop.value())
        # Triangles, segments and points in the frame's one order, which
        # is the order the kernel walks too. See
        # `render.rasterizer.rasterize_frame` and `prepare_frame`.
        rasterize_frame(
            frame.corners,
            frame.surfaces,
            frame.segments,
            frame.draws,
            target,
            self.shading,
            assets.textures,
            lighting,
            self.workers,
            fog,
            frame.points,
            assets.cube_textures,
            self.render_scale,
            seen,
            frame.programs,
            assets.data_3d_textures,
            assets.data_array_textures,
            lightings,
            frame.splats,
        )
        for index in range(len(frame.items)):
            hooks.on_after_render(scene, frame.items[index])
        hooks.on_after_scene(scene)
        var maps = lighting.shadows^
        lighting.shadows = List[ShadowMap]()
        return maps^

    def _lightings[
        C: Camera
    ](
        self, scene: Scene, assets: Assets, camera: C, lighting: Lighting
    ) raises -> List[Lighting]:
        """Return the lights each light mask the materials name resolves
        to, in `light_masks` order: `lighting` narrowed to the mask's
        lights, with the same shadow maps and spot light maps.

        Args:
            scene: The scene.
            assets: The materials, whose masks are read.
            camera: The camera the frame is drawn through.
            lighting: The frame's own lighting, every light the camera
                sees.

        Returns:
            One lighting a mask.

        Raises:
            Error: Everything `Lighting` raises.
        """
        var masks = light_masks(assets)
        var lightings = List[Lighting]()
        for index in range(len(masks)):
            lightings.append(
                Lighting(
                    scene,
                    visible=camera.visible_layers(),
                    eye=camera_position(scene, camera),
                    toward_eye=toward_camera(scene, camera),
                    up=camera_up(scene, camera),
                    shadows=lighting.shadows.copy(),
                    ltc=self.ltc_tables(),
                    spot_maps=lighting.spot_maps.copy(),
                    back=camera_back(scene, camera),
                    chosen=masks[index],
                    profiles=lighting.spot_profiles.copy(),
                    probe_grid=self.probe_grid,
                )
            )
        return lightings^

    def _lighting[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        var shadows: Optional[List[ShadowMap]] = None,
    ) raises -> Lighting:
        """Return the scene's lights as `render_into` resolves them for
        this camera: the ones on its layers, its shadows, and where it
        stands. Shadow maps the caller drew are used as they are."""
        var maps: List[ShadowMap]
        if Bool(shadows):
            maps = shadows.take()
        else:
            maps = self.shadow_maps(scene, assets, camera.visible_layers())
        return Lighting(
            scene,
            visible=camera.visible_layers(),
            eye=camera_position(scene, camera),
            toward_eye=toward_camera(scene, camera),
            up=camera_up(scene, camera),
            shadows=maps^,
            ltc=self.ltc_tables(),
            spot_maps=self._projected(scene, assets, camera.visible_layers()),
            back=camera_back(scene, camera),
            profiles=self.spot_profiles(scene, assets, camera.visible_layers()),
            probe_grid=self.probe_grid,
        )

    def to_target[C: Camera](self, scene: Scene, camera: C) raises -> Matrix4:
        """Return the transform from a world position to a coordinate on
        the transmission target: the camera's view, its projection and
        the viewport, then pixels scaled to `u` across and `v` up.

        three.js's `projectionMatrix * viewMatrix` followed by its
        `* 0.5 + 0.5`, onto a target the renderer's size; see
        `render.transmission`.

        Args:
            scene: The scene, for where the camera is.
            camera: The camera.

        Returns:
            The matrix, divided by its fourth row as a projection is.

        Raises:
            Error: If the camera's matrices are refused.
        """
        var onto = Matrix4()
        onto.elements[0] = 1 / Float32(self.width)
        onto.elements[5] = -1 / Float32(self.height)
        onto.elements[13] = 1
        onto.multiply(self._to_screen(camera))
        onto.multiply(camera.view_matrix_in(scene))
        return onto^

    def transmission_target[
        C: Camera
    ](
        self, scene: Scene, assets: Assets, camera: C
    ) raises -> TransmissionTarget:
        """Return the opaque scene a transmissive surface looks through,
        as `render_into` draws it first: three.js's
        `renderTransmissionPass`.

        For a caller that draws the frame elsewhere, such as
        `render.gpu.GpuRenderer.draw`, which takes the target as it is.
        Also holds immutable opaque depth when a volume requests it, in
        every shading mode except `SHADE_UV`. Otherwise empty when no
        surface reads the scene under `SHADE_TEXTURE`.

        Args:
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera.

        Returns:
            The target.

        Raises:
            Error: Everything `render_into` raises.
        """
        var frame = self.prepare_frame(scene, assets, camera)
        var fog = FogView(scene.fog)
        fog.validate()
        return self._transmission_pass(
            frame,
            scene,
            assets,
            camera,
            self._lighting(scene, assets, camera),
            fog,
            self.backdrop(scene, assets, camera),
        )

    def _transmission_pass[
        C: Camera
    ](
        self,
        frame: Frame,
        scene: Scene,
        assets: Assets,
        camera: C,
        lighting: Lighting,
        fog: FogView,
        backdrop: Optional[Framebuffer],
        volume_opaque: Optional[List[Draw]] = None,
    ) raises -> TransmissionTarget:
        """Draw the opaque part of a prepared frame into a target of its
        own and return it with its chain: three.js's
        `renderTransmissionPass`.

        The clear color, or white at half alpha when the clear color is
        not opaque, as three.js clears the pass. Then the background, the
        runs that neither transmit nor blend with no tone mapping, as
        three.js turns it off for the pass, and the chain. Then the back
        faces of every two-sided transmissive mesh, each looking through
        what was drawn so far, and the chain again. A requested volume
        depth snapshot is copied before those back faces and preserved
        afterward. A frame that needs neither scene colors nor volume
        depth returns an empty target.

        Args:
            frame: The frame, prepared.
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera.
            lighting: The scene's lights, as `_lighting` resolves them.
            fog: The scene's fog, checked.
            backdrop: The scene's image background, or none.
            volume_opaque: The unfiltered opaque draw order, when a
                filtered frame contains a volume that reads scene depth.
                None keeps the prepared frame's own draw selection.

        Returns:
            The target, empty when nothing needs it.

        Raises:
            Error: Everything `rasterize_frame` raises.
        """
        var volume_depth = self.shading != SHADE_UV and _needs_volume_depth(
            frame
        )
        if not volume_depth and (
            self.shading != SHADE_TEXTURE or not _transmits(frame)
        ):
            return TransmissionTarget()
        var lightings = self._lightings(scene, assets, camera, lighting)
        var kept = Rect.whole(self.width, self.height)
        if self.scissor_test:
            kept = self.scissor
        var clear = self.clear_color(scene)
        if clear.a < 255:
            clear = Color(255, 255, 255, 128)
        var drawn = RenderTarget(self.width, self.height, clear)
        drawn.clear_inside(
            Rect.whole(self.width, self.height),
            clear,
            self.depth_mode_for(camera),
        )
        drawn.set_scissor(kept)
        var painted = Bool(backdrop)
        if painted:
            _paint_backdrop(drawn, kept, backdrop.value())
        var opaque_draws: List[Draw]
        if Bool(volume_opaque):
            opaque_draws = volume_opaque.value().copy()
        else:
            opaque_draws = _opaque_draws(frame)
        rasterize_frame(
            frame.corners,
            frame.surfaces,
            frame.segments,
            opaque_draws,
            drawn,
            self.shading,
            assets.textures,
            lighting,
            self.workers,
            fog,
            frame.points,
            assets.cube_textures,
            self.render_scale,
            programs=frame.programs,
            volumes=assets.data_3d_textures,
            arrays=assets.data_array_textures,
            lightings=lightings,
        )
        var view = self.to_target(scene, camera)
        var seen = TransmissionTarget(drawn, view)
        if volume_depth:
            seen.capture_volume_depth(
                drawn,
                self._to_screen(camera),
                Length(camera.far_distance(), METER),
            )
        var backs = List[_Span]()
        var turned = self._prepared(
            scene, assets, camera, False, backs, transmissive_backs=True
        )
        if len(backs) == 0:
            return seen^
        var order = List[Draw]()
        # Not empty, as asked just above.
        for span in range(len(backs)):  # pragma: no branch
            order.append(
                Draw(DRAW_TRIANGLES, backs[span].first, backs[span].count)
            )
        rasterize_frame(
            turned,
            List[RasterVertex](),
            order,
            drawn,
            self.shading,
            assets.textures,
            lighting,
            self.workers,
            fog,
            List[RasterVertex](),
            assets.cube_textures,
            self.render_scale,
            seen,
            frame.programs,
            assets.data_3d_textures,
            assets.data_array_textures,
            lightings,
        )
        var finished = TransmissionTarget(drawn, view)
        finished.volume_depth = seen.volume_depth^
        seen.volume_depth = List[Float32]()
        return finished^

    def set_ltc_tables(mut self, var tables: LtcTables):
        """Hold the tables a rect area light is evaluated with.

        `lights.ltc.load_ltc_tables` reads them from `assets/ltc.f32`.
        A scene with a rect area light and no tables is refused when its
        lighting is resolved; a scene without one never needs them.

        Args:
            tables: The two tables, loaded.
        """
        self.ltc = tables^

    def ltc_tables(self) -> LtcTables:
        """Return a copy of the tables this renderer holds, or none."""
        if not self.ltc.is_loaded():
            return LtcTables()
        return LtcTables(copy=self.ltc)

    def shadow_maps(
        self,
        scene: Scene,
        assets: Assets,
        visible: Layers = Layers.all(),
        var kept: List[ShadowMap] = List[ShadowMap](),
    ) raises -> List[ShadowMap]:
        """Draw the scene's depth from every light that casts a shadow,
        and return the maps for `Lighting` to compare against.

        One map per directional, point or spot light on the camera's
        layers whose `cast_shadow` is set, drawn through the camera the
        light's `shadow` describes: an orthographic one between its
        `left`, `right`, `top` and `bottom` edges for a directional light,
        three.js's `DirectionalLightShadow`, and a perspective one twice
        the cone's angle wide for a spot light, three.js's `SpotLightShadow`, each at
        the light's node looking at its target, between the shadow's near
        and far planes. A point light draws six square ninety-degree
        views from its node, one along each of `cube_direction`'s six
        directions with `cube_up` up, three.js's `PointLightShadow`, and
        keeps the distance from the bulb in each texel; see
        `lights.shadow.cube_stored`. A point or spot light with a distance
        puts its far plane there; see `Light.shadow_far`. Only what casts
        is drawn, under lit shading with no lights: every mesh, skinned,
        instanced or batched mesh, LOD level, line and points object
        whose `cast_shadow` is set, as three.js's `renderObject` draws
        any mesh, line or points object. So a cut-out map cuts nothing
        out of a shadow. A translucent surface writes its depth, as
        three.js's depth material does, and casts a whole shadow; see
        `_casters`. What is kept is the target's depth, and the
        transform that put it there.

        Each map carries the renderer's `shadow_map_type`, three.js's
        `shadowMap.type`. Under `VSM_SHADOW_MAP` a directional or spot
        light also draws the meshes that receive, as three.js does, and
        keeps the blurred mean and spread of the depth that
        `lights.shadow.vsm_moments` makes, across the shadow's `radius`
        in its `blur_samples` steps. A point light's cube draws the
        receiving meshes too but is not blurred, as three.js blurs none.

        Each map carries its light's `shadow.intensity`, which weakens
        what the map takes away; see `lights.shadow.shadow_strength`.

        A light whose shadow is frozen, three.js's `autoUpdate` and
        `needsUpdate` both false, takes its map from `kept` rather than
        drawing it again, as three.js keeps the map it drew last. One
        with no map in `kept` is drawn: this renderer keeps nothing
        between frames, so `render_into` draws every map every frame.
        Hand last frame's maps back as `kept` to freeze one, and clear
        each drawn light's `needs_update` with
        `lights.light.shadows_drawn`, as three.js clears it.

        `render_into` draws these itself. Call this to hand the same maps
        to `GpuRenderer.draw`, through `Lighting`.

        Args:
            scene: The transform hierarchy, updated, with its lights.
            assets: The geometry and materials the casters name.
            visible: The camera's layers. A light or caster on none of
                them is left out, as in three.js's shadow pass.
            kept: Maps drawn before, each naming its light. Only a frozen
                light's is used; the rest are dropped.

        Returns:
            The maps, each naming its light by index.

        Raises:
            Error: If the renderer's `shadow_map_type` is none of the four,
                a light is refused by `Light.validate`, a casting light
                names a node or a target the scene lacks, or anything
                `prepare` raises for the casters.
        """
        require_shadow_type(self.shadow_map_type)
        self._state[].shadow_items.clear()
        self._state[].shadow_lights.clear()
        var variance = self.shadow_map_type == VSM_SHADOW_MAP
        var maps = List[ShadowMap]()
        for index in range(len(scene.lights)):
            ref light = scene.lights[index]
            light.validate()
            if not light.cast_shadow or not light.layers.test(visible):
                continue
            if not scene.light_shown(light):
                continue
            ref shadow = light.shadow
            var reused = index_of_light(kept, index)
            if shadow.is_frozen() and reused >= 0:
                maps.append(kept.pop(reused))
                continue
            if light.kind == POINT:
                maps.append(
                    self._cube_shadow(scene, assets, light, index, visible)
                )
                continue
            var at = scene.world_position(light.node)
            var aimed = _light_aim(scene, light)
            var target: RenderTarget
            var frame: Matrix4
            if light.kind == DIRECTIONAL:
                var camera = OrthographicCamera(
                    shadow.left,
                    shadow.right,
                    shadow.top,
                    shadow.bottom,
                    shadow.near,
                    shadow.far,
                )
                camera.place(at, aimed)
                camera.layers = visible
                target = self._casters(
                    scene,
                    assets,
                    camera,
                    shadow.map_size,
                    variance,
                    index,
                )
                frame = camera.projection_matrix()
                frame.multiply(camera.view_matrix_in(scene))
            else:
                var camera = _spot_camera(
                    light, at, aimed, projector_aspect(light, assets.textures)
                )
                camera.layers = visible
                target = self._casters(
                    scene,
                    assets,
                    camera,
                    shadow.map_size,
                    variance,
                    index,
                )
                frame = camera.projection_matrix()
                frame.multiply(camera.view_matrix_in(scene))
            var held = SIMD[DType.float32, 16](0)
            for element in range(16):  # pragma: no branch
                held[element] = frame.elements[element]
            var depths = target.depth.copy()
            if variance:
                depths = vsm_moments(
                    target.depth,
                    shadow.map_size,
                    shadow.radius,
                    shadow.blur_samples,
                )
            maps.append(
                ShadowMap(
                    index,
                    shadow.map_size,
                    held,
                    depths^,
                    shadow.bias,
                    shadow.normal_bias,
                    shadow.radius,
                    self.shadow_map_type,
                    shadow.intensity,
                    self._kept_colors(target),
                )
            )
        return maps^

    def _cube_shadow(
        self,
        scene: Scene,
        assets: Assets,
        light: Light,
        index: Int,
        visible: Layers,
    ) raises -> ShadowMap:
        """Draw a point light's six faces and return them as its cube."""
        ref shadow = light.shadow
        var size = shadow.map_size
        var at = scene.world_position(light.node)
        var near = shadow.near.to(METER)
        var far = light.shadow_far().to(METER)
        var depths = List[Float32](capacity=CUBE_FACES * size * size)
        var colors = List[Float32]()
        for face in range(CUBE_FACES):  # pragma: no branch
            var camera = PerspectiveCamera(
                Angle(90.0, DEGREE), 1.0, shadow.near, light.shadow_far()
            )
            camera.up = cube_up(face)
            camera.place(at, at + cube_direction(face))
            camera.layers = visible
            var target = self._casters(
                scene,
                assets,
                camera,
                size,
                self.shadow_map_type == VSM_SHADOW_MAP,
                index,
                True,
            )
            for row in range(size):  # pragma: no branch
                for column in range(size):  # pragma: no branch
                    depths.append(
                        cube_stored(
                            target.depth[row * size + column],
                            column,
                            row,
                            size,
                            near,
                            far,
                        )
                    )
            colors.extend(self._kept_colors(target))
        return ShadowMap(
            cube_of=index,
            size=size,
            origin=at,
            near=near,
            far=far,
            depths=depths^,
            bias=shadow.bias,
            normal_bias=shadow.normal_bias,
            radius=shadow.radius,
            shadow_type=self.shadow_map_type,
            intensity=shadow.intensity,
            colors=colors^,
        )

    def _kept_colors(self, target: RenderTarget) -> List[Float32]:
        """Return what the light saw through each texel of a shadow pass,
        four floats a texel from the top, or nothing when the renderer
        keeps no colors; see `shadow_map_transmitted`."""
        var colors = List[Float32]()
        if not self.shadow_map_transmitted:
            return colors^
        for texel in range(len(target.colors)):  # pragma: no branch
            ref seen = target.colors[texel]
            append_float_color(colors, seen)
        return colors^

    def _projected(
        self, scene: Scene, assets: Assets, visible: Layers
    ) raises -> List[SpotLightMap]:
        """Return the spot light maps a frame draws with: every one under
        `SHADE_TEXTURE`, and none under the other two modes, which ignore
        every texture, as they ignore an image background."""
        if self.shading != SHADE_TEXTURE:
            return List[SpotLightMap]()
        return self.spot_light_maps(scene, assets, visible)

    def spot_light_maps(
        self, scene: Scene, assets: Assets, visible: Layers = Layers.all()
    ) raises -> List[SpotLightMap]:
        """Return the picture every spot light projects, with the
        transform onto it, for `Lighting` to tint the lights with.

        One per spot light on the camera's layers whose `map` names a
        texture, three.js's `SpotLight.map`, seen through the camera its
        shadow would be drawn through: a perspective one at the light's
        node looking at its target, twice the cone's angle wide, between
        the shadow's near plane and `Light.shadow_far`. The surface is
        moved along its normal by the shadow's normal bias first when the
        light casts, as three.js moves it only under a shadow.

        `render_into` builds these itself under `SHADE_TEXTURE`; the other
        two modes ignore every texture, and a map is one. Call this to
        hand the same maps to `GpuRenderer.draw`, through `Lighting`.

        Args:
            scene: The transform hierarchy, updated, with its lights.
            assets: The textures the maps name.
            visible: The camera's layers; a light on none of them projects
                nothing, as `Lighting` leaves it out.

        Returns:
            The maps, each naming its light by index.

        Raises:
            Error: If a light is refused by `Light.validate`; a spot light
                with a map names a node or a target the scene lacks, or
                names a texture that is not there or is blank.
        """
        var maps = List[SpotLightMap]()
        for index in range(len(scene.lights)):
            ref light = scene.lights[index]
            light.validate()
            if light.map == NO_TEXTURE or not light.layers.test(visible):
                continue
            if not scene.light_shown(light):
                continue
            var at = scene.world_position(light.node)
            var camera = _spot_camera(
                light,
                at,
                _light_aim(scene, light),
                projector_aspect(light, assets.textures),
            )
            var frame = camera.projection_matrix()
            frame.multiply(camera.view_matrix_in(scene))
            var held = SIMD[DType.float32, 16](0)
            for element in range(16):  # pragma: no branch
                held[element] = frame.elements[element]
            var bias = Float32(0)
            if light.cast_shadow:
                bias = light.shadow.normal_bias
            maps.append(
                SpotLightMap(
                    index,
                    light.map,
                    Texture(copy=assets.textures.get(light.map)),
                    held,
                    bias,
                )
            )
        return maps^

    def spot_profiles(
        self, scene: Scene, assets: Assets, visible: Layers = Layers.all()
    ) raises -> List[SpotProfile]:
        """Return the beam of every IES spot light and every projector,
        for `Lighting` to shape the lights with.

        One per spot light on the camera's layers that `needs_profile`:
        an `IES_SPOT` with its profile's texture, three.js's `iesMap`, and
        a `PROJECTOR_SPOT` with the frame of the camera its shadow would
        be drawn through, at its aspect. `render_into` builds these itself
        in every shading mode, as the beam is not a surface's texture.
        Call this to hand the same profiles to `GpuRenderer.draw`,
        through `Lighting`.

        Args:
            scene: The transform hierarchy, updated, with its lights.
            assets: The textures the profiles and the maps name.
            visible: The camera's layers; a light on none of them is
                left out, as `Lighting` leaves it out.

        Returns:
            The profiles, each naming its light by index.

        Raises:
            Error: If a light is refused by `Light.validate`; such a light
                names a node or a target the scene lacks; or it names a
                profile or a map that is not in the store, or a blank
                profile.
        """
        var profiles = List[SpotProfile]()
        for index in range(len(scene.lights)):
            ref light = scene.lights[index]
            light.validate()
            if not needs_profile(light) or not light.layers.test(visible):
                continue
            if not scene.light_shown(light):
                continue
            var held = SIMD[DType.float32, 16](0)
            if light.spot_shape == IES_SPOT:
                profiles.append(
                    SpotProfile(
                        index,
                        IES_SPOT,
                        light.ies_map,
                        Texture(copy=assets.textures.get(light.ies_map)),
                        held,
                    )
                )
                continue
            var camera = _spot_camera(
                light,
                scene.world_position(light.node),
                _light_aim(scene, light),
                projector_aspect(light, assets.textures),
            )
            var frame = camera.projection_matrix()
            frame.multiply(camera.view_matrix_in(scene))
            for element in range(16):  # pragma: no branch
                held[element] = frame.elements[element]
            profiles.append(
                SpotProfile(index, PROJECTOR_SPOT, NO_TEXTURE, Texture(), held)
            )
        return profiles^

    def set_light_probe_grid(mut self, var grid: LightProbeGrid) raises:
        """Hold a box of light probes that every lit surface adds, as
        three.js adds a `LightProbeGrid` to a scene.

        Bake it first, with
        `renderers.light_probe_grid_utils.bake_light_probe_grid`. An empty
        grid, `LightProbeGrid.none()`, takes it away.

        Args:
            grid: The grid.

        Raises:
            Error: If the grid is not empty and is refused by
                `LightProbeGrid.validate`.
        """
        if not grid.is_empty():
            grid.validate()
        self.probe_grid = grid^

    def _casters[
        C: Camera
    ](
        self,
        scene: Scene,
        assets: Assets,
        camera: C,
        size: Int,
        receivers_cast: Bool,
        light: Int,
        distance: Bool = False,
    ) raises -> RenderTarget:
        """Draw what casts a shadow, and what receives when
        `receivers_cast`, as a light's camera sees it, onto a square of
        `size` pixels a side, and remember each caster's run for the
        `on_before_shadow` hook of light `light`.

        Every kind three.js's shadow map draws is drawn: the triangles of
        every mesh, skinned, instanced or batched mesh and LOD level, the
        segments of every line and wireframe, and every point, under lit
        shading with no lights, or under `SHADE_SHADOW` when the renderer
        keeps the colors, `shadow_map_transmitted`. A mesh whose material
        names a node program runs that program, so the program and the
        textures it reads are the scene's. A point light's view,
        `distance`, draws a mesh's custom distance material.

        Args:
            scene: The transform hierarchy, updated.
            assets: The geometry and materials the casters name.
            camera: The light's camera.
            size: How many texels a side the map is.
            receivers_cast: Whether the receivers are drawn too.
            light: The light's index, for the hook.
            distance: Whether this is a point light's view.

        Returns:
            The target, whose depth is the map.

        Raises:
            Error: Anything `prepare`, `prepare_lines`, `prepare_points`
                or `rasterize_frame` raises for the casters.
        """
        var spans = List[_Span]()
        var square = Renderer(size, size, workers=self.workers)
        # A material's planes cut its shadow under `clip_shadows`, which
        # this renderer's switch decides as it does for the frame.
        square.local_clipping_enabled = self.local_clipping_enabled
        # The slim corners, as the frame's pass takes them: a whole corner
        # is four times the size, and the map is only depth.
        var frame = square._prepared_slim(
            scene,
            assets,
            camera,
            False,
            spans,
            True,
            receivers_cast,
            distance_casters=distance,
        )
        var segments = square._prepared_lines(
            scene,
            assets,
            camera,
            spans,
            True,
            receivers_cast,
            distance,
        )
        var points = square._prepared_points(
            scene, assets, camera, spans, True, receivers_cast
        )
        ref state = self._state[]
        for index in range(len(spans)):
            state.shadow_items.append(spans[index].item())
            state.shadow_lights.append(light)
        # Every fragment writes its depth under the default state, so the
        # nearest wins whatever the order: the three kinds go one after
        # the other. Lit shading reads no material map. A node program
        # still runs, and it reads the scene's textures.
        var draws: List[Draw] = [
            Draw(DRAW_TRIANGLES, 0, len(frame) // 3),
            Draw(DRAW_SEGMENTS, 0, len(segments) // 2),
            Draw(DRAW_POINTS, 0, len(points)),
        ]
        # With the colors kept, a texel nothing is drawn in is clear, alpha
        # zero, as three.js clears the map to `0x000000, 0`, and each
        # caster writes what the light sees through it; see `SHADE_SHADOW`.
        var transmitted = self.shadow_map_transmitted
        var target = RenderTarget(
            size, size, Color(0, 0, 0, 0) if transmitted else Color(0, 0, 0)
        )
        rasterize_frame(
            frame.corners,
            frame.surfaces,
            segments,
            draws,
            target,
            SHADE_SHADOW if transmitted else SHADE_LIT,
            assets.textures,
            Lighting.uniform(),
            self.workers,
            points=points,
            cubes=assets.cube_textures,
            # A node material's mask and depth hold in the light's view
            # as in the camera's.
            programs=assets.programs,
            volumes=assets.data_3d_textures,
            arrays=assets.data_array_textures,
        )
        return target^

    def clear_color(self, scene: Scene) raises -> Color:
        """Return what a frame of `scene` is cleared to: the scene's color
        background if it has one, else this renderer's `background`.

        three.js's rule: `scene.background` as a color replaces the clear
        color, and any other background is drawn over the clear color.

        Args:
            scene: The scene, for its background.

        Returns:
            The clear color, as authored in sRGB.

        Raises:
            Error: If the background is refused by `Background.validate`.
        """
        scene.background.validate()
        if scene.background.kind == COLOR_BACKGROUND:
            return scene.background.color
        return self.background

    def backdrop[
        C: Camera
    ](self, scene: Scene, assets: Assets, camera: C) raises -> Optional[
        Framebuffer
    ]:
        """Return the scene's image background as this camera sees it, or
        none when the scene has no image background.

        What `render_into` paints under the scene and `GpuRenderer.draw`
        takes as its `backdrop`, so both backends start a frame from the
        same bytes. A pixel inside the viewport holds the background's
        color there with full alpha; every other pixel is transparent,
        and holds the clear color on either backend. The image is sRGB
        bytes, as a background image is, and both backends decode the
        same bytes into linear light through the same ramp.

        A texture background is stretched over the viewport, as three.js
        draws one, and read at its full size through its own filter; its
        transform is not applied. A texture with an equirectangular
        mapping is not stretched: it is read at `equirect_uv` of each
        pixel's direction, as a cube is. A cube background is read in the
        direction each pixel's ray leaves the camera along: the near and
        the far point of the ray are unprojected into *view* space through
        the inverse projection, and their difference is turned into the
        world by the camera's rotation alone. So any camera serves, a
        parallel one sees one direction everywhere, and moving a camera
        without turning it changes no pixel of the sky.

        The direction is turned by `Scene.background_rotation` before it
        is read. Above a `background_blurriness` of zero a cube is read at
        that roughness, from its PMREM when it has one, and a panorama
        down its chain; see `CubeTexture.sample_rough`. Every background
        image is multiplied by `background_intensity` before it is
        encoded, as three.js's shaders multiply it.

        Only `SHADE_TEXTURE` draws an image background: the other two
        modes ignore every texture, and a background is one. Under either
        of them this returns none and the frame is cleared to the color.

        Args:
            scene: The scene, for its background.
            assets: Where the texture or the cube texture lives.
            camera: The camera the frame is drawn through.

        Returns:
            The backdrop, the renderer's size, or none.

        Raises:
            Error: If the background is refused by `Background.validate`,
                the scene by `Scene.validate_environment`, the background
                names a texture or a cube texture that is not there, or
                the camera's matrices cannot be built.
        """
        scene.background.validate()
        scene.validate_environment()
        var backdrop = scene.background
        if not backdrop.is_image() or self.shading != SHADE_TEXTURE:
            return None
        # three.js's `backgroundIntensity`, on every background image.
        var shown = scene.background_intensity
        var image = Framebuffer(self.width, self.height, Color(0, 0, 0, 0))
        # Every pixel is encoded through one table; see `SrgbBytes`.
        var bytes = SrgbBytes()
        var kept = Rect.whole(self.width, self.height)
        if self.scissor_test:
            kept = self.scissor
        var viewport = self.viewport
        var top = viewport.top(self.height)
        if backdrop.kind == TEXTURE_BACKGROUND:
            if backdrop.texture.value >= assets.textures.count():
                raise Error("A background names a texture that is not there")
            ref picture = assets.textures.get(backdrop.texture)
            # A panorama is read by direction, as a cube is: three.js
            # turns an equirectangular background into a cube first.
            if not picture.mapping.is_equirectangular():
                for y in range(self.height):  # pragma: no branch
                    for x in range(self.width):  # pragma: no branch
                        if not kept.contains_pixel(
                            x, y, self.height
                        ) or not viewport.contains_pixel(x, y, self.height):
                            continue
                        # Stretched over the viewport: the pixel's center
                        # as a fraction of the rectangle, `v` counting up.
                        var u = texel_center(x - viewport.x, viewport.width)
                        var v = texel_center_from_end(y - top, viewport.height)
                        _set_backdrop(
                            image,
                            x,
                            y,
                            _brightened(picture.sample(u, v), shown),
                            bytes,
                        )
                return image^
        elif backdrop.cube.value >= assets.cube_textures.count():
            raise Error("A background names a cube texture that is not there")
        # three.js's `backgroundRotation` and `backgroundBlurriness`.
        var spin = env_rotation(scene.background_rotation)
        var blur = scene.background_blurriness
        # From pixels back to the camera's own space, and only then out
        # into the world as a *direction*. Unprojecting through the
        # projection and the view together puts the near and the far point
        # in world coordinates, where both carry the camera's translation:
        # a scene a million meters from the origin spends its Float32
        # significand on that offset and rounds the difference of the two
        # points -- the ray -- into steps. The camera's position cannot
        # change which way a ray leaves it, so it is kept out of the
        # arithmetic. The inverse projection alone gives both points in
        # view space, where the camera is at the origin, and
        # `transform_direction` turns their difference by the camera's
        # rotation and drops the translation.
        var unproject = camera.projection_matrix()
        unproject.invert()
        var to_world = camera.view_matrix_in(scene)
        to_world.invert()
        var rays = _BackdropRays(
            backdrop,
            kept,
            viewport,
            top,
            self.width,
            self.height,
            unproject,
            to_world,
            spin,
            blur,
            shown,
        )
        # Each pixel is its own, so the rows are split over the workers.
        var bands = min(self.workers, self.height)
        if bands == 1:
            rays.paint(image, assets, bytes, 0, self.height)
            return image^
        var errors = List[String](length=bands, fill=String(""))
        var group = TaskGroup()
        for band in range(bands):  # pragma: no branch
            group.create_task(
                _backdrop_band(
                    Pointer(to=rays)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=image)
                    .unsafe_mut_cast[True]()
                    .unsafe_origin_cast[MutAnyOrigin](),
                    Pointer(to=assets).unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=bytes)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    band,
                    band * self.height // bands,
                    (band + 1) * self.height // bands,
                )
            )
        group.wait()
        # The tasks read these through pointers the compiler cannot see.
        _ = len(bytes.thresholds)
        _ = rays.width
        _raise_band_errors(errors)
        return image^

    def _cube_renderer(
        self, size: Int, copy_probe_grid: Bool = True
    ) raises -> Renderer:
        """Return a fresh cube-face renderer with this scene's light and clip settings.

        The face owns its viewport and history, uses unit exposure with no
        tone mapping, and writes the usual sRGB image when resolved.
        Sampling belongs to the caller: `render_cube` copies `antialias`,
        while `render_cube_into` uses each target face's `samples`.
        Probe baking supplies its own grid and skips copying this one's.
        """
        var side = Renderer(size, size, self.workers)
        side.background = self.background
        side.shading = self.shading
        side.depth_mode = self.depth_mode
        side.clipping_planes = self.clipping_planes.copy()
        side.local_clipping_enabled = self.local_clipping_enabled
        side.shadow_map_type = self.shadow_map_type
        side.shadow_map_transmitted = self.shadow_map_transmitted
        side.ltc = self.ltc.copy()
        if copy_probe_grid:
            side.probe_grid = self.probe_grid.copy()
        side.time = self.time
        side.override_material = self.override_material
        return side^

    def render_cube(
        self, scene: Scene, assets: Assets, camera: CubeCamera
    ) raises -> CubeTexture:
        """Draw the scene six times from one point, once along each axis,
        and return the six views as a cube texture: three.js's
        `CubeCamera.update(renderer, scene)`.

        Each face is drawn by a renderer of the face's size with this
        one's background, shading, workers, lighting resources and clipping,
        through `render`, so the scene's background and materials reach the
        faces. Shadow settings, material override and node time carry over.
        This renderer's `antialias` applies to each face. The samples are
        averaged in linear light before the sRGB byte image is made.
        The tone mapping is left off, as three.js turns it off around its
        update: the faces are light the main frame will map once, when a
        surface reflects them or the sky shows them.

        Args:
            scene: The transform hierarchy, and what it draws.
            assets: The geometry, materials and textures it names.
            camera: Where to stand, how far to see, and how big a face is.

        Returns:
            The cube texture, stored `SRGB`; see `cube_texture_of`.

        Raises:
            Error: Everything `render` raises for one of the six faces, or
                `CubeCamera.face_camera` for the camera's node.
        """
        var side = self._cube_renderer(camera.size)
        side.antialias = self.antialias
        var faces = List[Framebuffer]()
        for face in range(FACE_COUNT):  # pragma: no branch
            faces.append(
                side.render(scene, assets, camera.face_camera(face, scene))
            )
        return cube_texture_of(faces)

    def render_into_layer[
        C: Camera
    ](
        self,
        mut target: LayeredRenderTarget,
        layer: Int,
        level: Int,
        scene: Scene,
        assets: Assets,
        camera: C,
    ) raises:
        """Draw the scene into one layer and one level of a layered
        target: three.js's `setRenderTarget(target, activeCubeFace,
        activeMipmapLevel)` followed by `render`.

        `render_into` on `target.image(layer, level)`, so the image's own
        samples, type and outputs apply. The renderer must be the level's
        size. three.js asks the same of the viewport, which a caller sets
        to the level's size by hand.

        Args:
            target: The layered target.
            layer: The layer of a 3D or array target, the face of a cube,
                or zero for a 2D target.
            level: The mip level, zero for the largest.
            scene: The transform hierarchy, and what it draws.
            assets: The geometry, materials and textures it names.
            camera: The camera to project through.

        Raises:
            Error: If the target has no such layer or level, fails
                `LayeredRenderTarget.validate`, or anything `render_into`
                raises, a level of another size included.
        """
        self.render_into(target.image(layer, level), scene, assets, camera)

    def render_cube_into(
        self,
        mut target: LayeredRenderTarget,
        scene: Scene,
        assets: Assets,
        camera: CubeCamera,
    ) raises:
        """Draw the scene six times from one point into the first level of
        a cube target's faces: three.js's `CubeCamera.update(renderer,
        scene)` with a `WebGLCubeRenderTarget`.

        Each face is drawn by a renderer of the face's size with this
        one's scene settings, as `render_cube` draws them, into
        `target.image(face, 0)`. Each face's `samples` controls sampling,
        as in `render_into`; this renderer's `antialias` does not apply.
        Zero or one takes one sample; 4, 9 or 16 takes that many per pixel.
        Samples are averaged once in linear light. The faces keep the light
        as the target's type stores it. Use `FLOAT_TARGET` to keep HDR light.
        Call `target.generate_mipmaps` to fill the levels below.

        Args:
            target: A cube target.
            scene: The transform hierarchy, and what it draws.
            assets: The geometry, materials and textures it names.
            camera: Where to stand and how far to see. Its size is not
                read: the target's faces say how big a face is.

        Raises:
            Error: If the target is not a cube or fails `validate`, or
                anything `render_into` raises for one of the six faces.
        """
        target.validate()
        if target.kind != TARGET_CUBE:
            raise Error("A cube camera draws into a cube target")
        var side = self._cube_renderer(target.width)
        for face in range(FACE_COUNT):  # pragma: no branch
            side.render_into(
                target.image(face, 0),
                scene,
                assets,
                camera.face_camera(face, scene),
            )
