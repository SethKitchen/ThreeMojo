# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scene traversal, frustum culling, clipping, ribbons and vertex preparation.

`renderers.renderer` drives `Renderer` over these preparation stages and
re-exports every symbol.
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


def _carriers(
    geometry: BufferGeometry,
    skins: List[SkinPose],
    skin: Int,
    vertex_count: Int,
) raises -> List[Matrix4]:
    """Return one matrix per vertex, carrying it from its own space to
    where the bones have taken it; see `core.deform.skin_carriers`.

    Args:
        geometry: The geometry being drawn.
        skins: The frame's posed skeletons.
        skin: Which of them carries this draw, or minus one for none.
        vertex_count: How many vertices the geometry has.

    Returns:
        One matrix per vertex, or an empty list when the draw is not
        skinned.

    Raises:
        Error: For anything `skin_carriers` raises for.
    """
    if skin < 0:
        return List[Matrix4]()
    return skin_carriers(geometry, skins[skin], vertex_count)


def _displaces(assets: Assets, material: MaterialId) raises -> Bool:
    """Return True if a draw's material moves its vertices by a map, and
    so leaves the bound its geometry has.

    Asked only of a draw its bound would cull. Such a draw is kept, as a
    morphed mesh is: the bound describes the surface before the map moved
    it. An id that names nothing answers False, so a draw culled before
    keeps being culled without a read, and one that is kept raises when it
    is drawn.

    Args:
        assets: Where the materials live.
        material: The draw's material.

    Returns:
        Whether the material names a displacement map, or a node program
        with a position node, which moves the vertices too.

    Raises:
        Error: Never for an id in range; the store raises for nothing else.
    """
    if material.value < 0 or material.value >= assets.materials.count():
        return False
    ref named = assets.materials.get(material)
    # A program id that names nothing answers False too, for the same
    # reason: the draw raises when it is drawn.
    return named.has_displacement_map() or (
        named.nodes.value >= 0
        and named.nodes.value < assets.programs.count()
        and assets.programs.get(named.nodes).has(POSITION_NODE)
    )


def face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return the unit normal of the triangle, or zero if it is degenerate.

    Wound counter-clockwise seen from the front, so the normal points at the
    viewer for a front-facing triangle.
    """
    return normal_or_zero(a, b, c)


def _faces_away(
    a: RasterVertex, b: RasterVertex, c: RasterVertex, mirrored: Bool
) -> Bool:
    """Return True if these screen-space corners wind the wrong way round.

    Geometry is wound counter-clockwise seen from outside, but the viewport
    transform flips y — an image counts its rows downwards — and a flip
    reverses winding. So a triangle facing the camera comes out with a
    *negative* signed area here, and a positive one is facing away.

    Unless the mesh is mirrored. A transform with a negative determinant —
    `set_scale(-1, 1, 1)`, or any odd number of reflections inherited from
    parents — reverses winding a second time, and the whole convention is
    upside down. Without this a mirrored single-sided triangle is culled
    exactly when it should be drawn; the first version of this made one
    disappear completely. three.js asks the same question of the same
    quantity, the sign of the world matrix's determinant.

    Exactly zero is a degenerate triangle seen edge-on. It is left in either
    way, because the rasterizer already discards it and calling it "facing
    away" would be a second, differently-worded answer to the same question.

    Args:
        a: First screen-space corner.
        b: Second corner.
        c: Third corner.
        mirrored: True if the mesh's world transform reflects it.

    Returns:
        True if the triangle faces away from the camera.
    """
    var area = edge(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
    if mirrored:
        return area < 0
    return area > 0


def _with_opacity(color: FloatColor, opacity: Float32) -> FloatColor:
    """Return `color` with the material's opacity folded into its alpha.

    Alpha reaching the rasterizer is how much of the surface shows, so the
    material's opacity multiplies whatever the base color already carried.
    """
    return FloatColor(color.r, color.g, color.b, color.a * opacity)


def _vertex_colors(
    geometry: BufferGeometry,
    tinted: Bool,
    base: FloatColor,
    count: Int,
    instance: Int = -1,
    influences: MorphInfluences = MorphInfluences(),
) raises -> List[FloatColor]:
    """Return the color each vertex carries: `base` for every one, or
    `base` times the geometry's `color` attribute when the material asks,
    three.js's `vertexColors`.

    A `color` attribute that is per instance gives every vertex of an
    instance that instance's color, as three.js's attribute divisor does.
    A draw that is not an instance reads the first color, as WebGL does
    for a divided attribute outside an instanced draw.

    The attribute holds three or four floats per vertex in linear light,
    as three.js's does since its color management, and a fourth float
    multiplies the alpha. It is checked here, once per mesh, rather than
    left to read garbage: a material that asks for colors from a geometry
    without them is a wrong asset, not a wrong frame, and so is an
    attribute with the wrong shape or too few colors.

    A geometry whose morph targets carry colors has its colors morphed
    first, three.js's `morphcolor_vertex`, by `core.deform.morphed_colors`.
    A morphed alpha is read only from a color attribute of four floats, as
    three.js morphs it only under `USE_COLOR_ALPHA`.

    Args:
        geometry: The geometry, for its `color` attribute.
        tinted: Whether the material asks for vertex colors.
        base: The material's color, linear, with its opacity in alpha.
        count: How many vertices the geometry has.
        instance: Which instance the draw is, or minus one for a draw that
            is not one.
        influences: How much of each morph target the draw wears.

    Returns:
        One color per vertex.

    Raises:
        Error: If `tinted` and the geometry has no `color` attribute, or
            the attribute holds neither three nor four floats per vertex,
            or holds a color count that is not the vertex count, or is per
            instance and holds no color for the instance.
    """
    var colors = List[FloatColor](length=count, fill=base)
    if not tinted:
        return colors^
    if not geometry.has_attribute(String(COLOR)):
        raise Error(
            "A material asks for vertex colors from a geometry that has none"
        )
    ref tints = geometry.attribute_view(String(COLOR))
    var channels = tints.item_size
    if channels != 3 and channels != 4:
        raise Error("A color attribute holds three or four floats per vertex")
    var per_instance = tints.is_instanced()
    if not per_instance and tints.count() != count:
        raise Error("A color attribute must hold one color per vertex")
    var item = 0
    if per_instance:
        item = max(instance, 0) // tints.mesh_per_attribute()
    var read = List[SIMD[DType.float32, 4]](capacity=count)
    for vertex in range(count):
        if not per_instance:
            item = vertex
        var alpha = Float32(1)
        if channels == 4:
            alpha = tints.component(item, 3)
        read.append(
            SIMD[DType.float32, 4](
                tints.component(item, 0),
                tints.component(item, 1),
                tints.component(item, 2),
                alpha,
            )
        )
    # A per-instance color is one color for many vertices, and three.js
    # morphs the vertex color attribute only.
    if geometry.has_morph_colors() and not per_instance:
        read = morphed_colors(geometry, read, influences)
    for vertex in range(count):
        var alpha = Float32(1)
        if channels == 4:
            alpha = read[vertex][3]
        colors[vertex] = FloatColor(
            base.r * read[vertex][0],
            base.g * read[vertex][1],
            base.b * read[vertex][2],
            base.a * alpha,
        )
    return colors^


def _instancing(
    geometry: BufferGeometry,
) raises -> Tuple[List[Matrix4], List[Int]]:
    """Return where a mesh draws each instance of its geometry, and which
    instance each draw is.

    A geometry that is not instanced is drawn once, where the mesh is. An
    instanced one, three.js's `InstancedBufferGeometry`, is drawn
    `drawn_instances` times. Each instance moves by its item of a
    per-instance `offset` attribute, if there is one. three.js has no
    built-in `offset`: its instancing examples add one in their own vertex
    shader, which is what this stands in for. The move comes before the
    mesh's own transform, as the examples add the offset to `position`.

    Args:
        geometry: The geometry the mesh draws.

    Returns:
        One matrix per draw, relative to the mesh's node, and the instance
        each draw is: minus one for a geometry that is not instanced.

    Raises:
        Error: If the instance count cannot be worked out, if `position`,
            `normal`, `uv` or `tangent` is per instance, which the
            renderer does not draw, or if a per-instance `offset` holds
            fewer than three numbers an item.
    """
    var matrices = List[Matrix4]()
    var instances = List[Int]()
    if not geometry.instanced:
        matrices.append(Matrix4())
        instances.append(-1)
        return (matrices^, instances^)
    var per_vertex: List[String] = [
        String(POSITION),
        String(NORMAL),
        String(UV),
        String(TANGENT),
    ]
    # Four names, always, so the loop never runs zero times.
    for slot in range(len(per_vertex)):  # pragma: no branch
        ref name = per_vertex[slot]
        if (
            geometry.has_attribute(name)
            and geometry.attribute_view(name).is_instanced()
        ):
            raise Error("The renderer does not draw a per-instance " + name)
    var count = geometry.drawn_instances()
    var moved = geometry.has_attribute(String("offset")) and (
        geometry.attribute_view(String("offset")).is_instanced()
    )
    for instance in range(count):
        var matrix = Matrix4()
        if moved:
            ref offsets = geometry.attribute_view(String("offset"))
            var by = offsets.vector3(instance // offsets.mesh_per_attribute())
            matrix = translation(by.x, by.y, by.z)
        matrices.append(matrix^)
        instances.append(instance)
    return (matrices^, instances^)


def _named_maps(material: Material) -> List[TextureId]:
    """Return every map a material names that is sampled at a surface
    coordinate, the ones three.js gives a varying of its own: `vMapUv`,
    `vNormalMapUv` and the rest. `NO_TEXTURE` where it names none."""
    return [
        material.map,
        material.emissive_map,
        material.alpha_map,
        material.roughness_map,
        material.metalness_map,
        material.normal_map,
        material.bump_map,
        material.specular_map,
        material.transmission_map,
        material.thickness_map,
        material.sheen_color_map,
        material.sheen_roughness_map,
        material.iridescence_map,
        material.iridescence_thickness_map,
        material.anisotropy_map,
        material.specular_intensity_map,
        material.specular_color_map,
        material.clearcoat_map,
        material.clearcoat_roughness_map,
        material.clearcoat_normal_map,
        material.ao_map,
        material.light_map,
    ]


def _check_map_channels(assets: Assets, material: Material) raises:
    """Refuse a material that names a map whose channel is neither set.

    Each map is sampled at its own coordinate: its texture's channel picks
    the geometry's `uv` or `uv1`, and its texture's transform moves it, at
    the fragment, as three.js's `WebGLProgram` gives each map its own
    `*_UV` define and its own transform. Nothing else is asked of the maps
    here, so two maps of one material can be moved, tiled and turned apart.
    Asked whatever the shading mode: a wrong asset, not a wrong frame.

    Args:
        assets: Where the textures live. The ids are already checked.
        material: The material, for which maps it names.

    Raises:
        Error: If a map's texture names a channel that is not
            `UV_CHANNEL_0` or `UV_CHANNEL_1`.
    """
    var named = _named_maps(material)
    # Twenty-two maps, always, so the loop never runs zero times.
    for index in range(len(named)):  # pragma: no branch
        if named[index] == NO_TEXTURE:
            continue
        check_channel(assets.textures.get(named[index]))


def _moves_a_map(assets: Assets, material: Material) raises -> Bool:
    """Return True if any map the material names has a transform that is
    not the identity.

    Args:
        assets: Where the textures live. The ids are already checked.
        material: The material, for which maps it names.

    Returns:
        Whether a named map is moved, tiled or turned.

    Raises:
        Error: If a named texture is not in the store.
    """
    var named = _named_maps(material)
    # Twenty-two maps, always, so the loop never runs zero times.
    for index in range(len(named)):  # pragma: no branch
        if named[index] == NO_TEXTURE:
            continue
        if assets.textures.get(named[index]).uv_transform() != Matrix3():
            return True
    return False


def _light_at_corner(
    mut corner: ClipVertex,
    lighting: Lighting,
    normal: Vector3,
    position: Vector3,
):
    """Light a `GOURAUD` corner on both sides, as three.js's
    `GouraudShader` vertex does: the direct and the indirect light for its
    normal, and for the normal turned round."""
    var direct = lighting.direct_at(normal, position)
    var indirect = lighting.indirect_at(normal, position)
    var back_direct = lighting.direct_at(-normal, position)
    var back_indirect = lighting.indirect_at(-normal, position)
    corner.gouraud_direct = Vector3(direct.r, direct.g, direct.b)
    corner.gouraud_indirect = Vector3(indirect.r, indirect.g, indirect.b)
    corner.gouraud_back_direct = Vector3(
        back_direct.r, back_direct.g, back_direct.b
    )
    corner.gouraud_back_indirect = Vector3(
        back_indirect.r, back_indirect.g, back_indirect.b
    )


def _march_volume(
    mut corners: _Slim,
    begin: Int,
    steps: Int,
    geometry: BufferGeometry,
    world: Matrix4,
    scene_depth: Bool = False,
) raises:
    """Give a `VOLUME` draw's corners their ray: the material's steps, and
    the mesh's bounding radius carried to world space, three.js's
    `modelRadius`.

    Args:
        corners: The frame's raster vertices.
        begin: Where the draw's corners start.
        steps: The material's `steps`.
        geometry: The draw's geometry.
        world: The draw's world matrix.
        scene_depth: Whether the volume uses captured opaque-scene depth.

    Raises:
        Error: If `steps` is below one, or the geometry has no positions.
    """
    check_steps(steps)
    var bound = geometry.bounding_sphere()
    bound.apply_matrix4(world)
    # On the surfaces of the corners the draw added: the draw's own.
    if begin < len(corners):
        for surface in range(  # pragma: no branch
            corners.corners[begin].surface, len(corners.surfaces)
        ):
            corners.surfaces[surface].steps = steps
            corners.surfaces[surface].volume_scene_depth = scene_depth
            corners.surfaces[surface].model_radius = bound.radius


def _customs(
    assets: Assets,
    material: Material,
    geometry: BufferGeometry,
    count: Int,
) raises -> List[SIMD[DType.float32, 8]]:
    """Return every vertex's custom attributes, as the material's node
    program lays them out: each attribute the geometry has, its missing
    components from zeros and one, and one the geometry lacks all zeros and
    one, as WebGL fills an attribute.

    Args:
        assets: Where the program is.
        material: The mesh's material.
        geometry: The geometry, for the attributes.
        count: How many vertices the geometry has.

    Returns:
        One set of `MAX_ATTRIBUTE_FLOATS` floats per vertex.

    Raises:
        Error: If an attribute holds fewer than `count` vertices.
    """
    var customs = List[SIMD[DType.float32, 8]](
        length=count, fill=SIMD[DType.float32, 8](0)
    )
    if material.nodes == NO_NODES:
        return customs^
    ref program = assets.programs.get(material.nodes)
    for index in range(len(program.attribute_names)):
        var name = program.attribute_names[index]
        var first = program.attribute_offsets[index]
        var width = program.attribute_widths[index]
        var size = 0
        if geometry.has_attribute(name):
            size = geometry.attribute_view(name).item_size
        # A drawn geometry has vertices.
        for vertex in range(count):  # pragma: no branch
            for lane in range(width):  # pragma: no branch
                var value = Float32(1) if lane == 3 else Float32(0)
                if lane < size:
                    value = geometry.attribute_view(name).component(
                        vertex, lane
                    )
                customs[vertex][first + lane] = value
    return customs^


def _coordinates(
    geometry: BufferGeometry, name: String, count: Int
) raises -> Tuple[List[Float32], List[Float32]]:
    """Return every vertex's texture coordinates from one attribute, raw.

    Texture coordinates do not go through the world transform: they name
    a place in an image, not a place in the world. Nor do they go through
    a texture's transform here: each map moves them at the fragment by its
    own, as three.js's `uv_vertex` makes a varying per map. A geometry
    without the attribute gets zeroes, so a geometry without coordinates
    and one whose coordinates are all zero name the same place.

    Args:
        geometry: The geometry, for the attribute.
        name: Which attribute: `UV` or `UV1`.
        count: How many vertices the geometry has.

    Returns:
        The u of every vertex, then the v.

    Raises:
        Error: If the attribute holds fewer than `count` pairs.
    """
    var us = List[Float32]()
    var vs = List[Float32]()
    if geometry.has_attribute(name):
        ref uvs = geometry.attribute_view(name)
        for vertex in range(count):
            us.append(uvs.component(vertex, 0))
            vs.append(uvs.component(vertex, 1))
    else:
        for _ in range(count):
            us.append(0)
            vs.append(0)
    return (us^, vs^)


# How far past a frustum plane a bound may lie and still be drawn, as a
# fraction of the far distance: a sphere that misses a plane by less than
# this is left for the clipper to settle. Float32 keeps about seven
# figures, and the culler and the clipper reach a depth by different
# roundings of the same view; a millionth of the range they measure over
# is several times the rounding and no distance an image can show.
comptime CULL_SLACK = Float32(1e-6)


def _in_view(
    assets: Assets,
    geometry: GeometryId,
    world: Matrix4,
    frustum: Frustum,
    slack: Float32,
    mut bounds: List[Sphere],
    mut known: List[Bool],
) raises -> Bool:
    """Return True if any of a geometry's bounding sphere, carried by
    `world`, is inside `frustum`.

    three.js's `Frustum.intersectsObject`: the geometry's own bounding
    sphere, carried to world space by the draw's world matrix, tested
    against the six planes. The sphere is worked out afresh each frame,
    as `BufferGeometry.bounding_sphere` says it must be, at two passes
    over the positions, but once per geometry and not once per draw: the
    first draw of a geometry this frame records its bound in `bounds`,
    and every later one reads it back. A forest of one tree drawn two
    hundred times, as two hundred meshes or two hundred instances, scans
    the tree once. A geometry with no vertices has an empty sphere, which
    is in view nowhere, and a draw of it draws nothing either way.

    Args:
        assets: Where the geometry lives.
        geometry: Which geometry.
        world: The transform that places it, instance matrix included.
        frustum: The camera's frustum, in world space.
        slack: How far past a plane the bound may lie and still count as
            in view; see `CULL_SLACK`.
        bounds: One local bound per geometry in the store, filled in as
            geometries are met this frame.
        known: Which entries of `bounds` have been filled in.

    Returns:
        Whether the placed bound reaches into the view.

    Raises:
        Error: If the geometry is not there, or has no positions.
    """
    ref shape = assets.geometries.get(geometry)
    var slot = geometry.value
    if not known[slot]:
        bounds[slot] = shape.bounding_sphere()
        known[slot] = True
    var bound = bounds[slot]
    bound.apply_matrix4(world)
    # Grown, not shrunk: the empty sphere is left empty rather than made a
    # point by the slack.
    if not bound.is_empty():
        bound.radius += slack
    return frustum.intersects_sphere(bound)


def _object_place[
    C: Camera
](
    scene: Scene,
    assets: Assets,
    node: NodeId,
    material: MaterialId,
    geometry: GeometryId,
    frustum_culled: Bool,
    cast_shadow: Bool,
    receive_shadow: Bool,
    casters_only: Bool,
    receivers_cast: Bool,
    camera: C,
    view: Matrix4,
    frustum: Frustum,
    slack: Float32,
    mut bounds: List[Sphere],
    mut known: List[Bool],
) raises -> Tuple[Bool, Matrix4, Float32]:
    """Return whether the camera keeps one line or one points object, and
    where it sits.

    A light's view keeps only what casts. A hidden node is left out. A
    position node moves the object past the bound of its geometry, so
    that object is not culled by the bound. The depth is the node's
    origin in view space.

    Args:
        scene: The transform hierarchy.
        assets: The geometries and materials.
        node: The object's node.
        material: The object's own material, before any override.
        geometry: The object's geometry.
        frustum_culled: Whether the bound may leave the object out.
        cast_shadow: Whether the object casts.
        receive_shadow: Whether the object receives.
        casters_only: Whether this is a light's view.
        receivers_cast: Whether that view also holds receivers.
        camera: The camera, queried only after the caster filter.
        view: The world-to-camera transform.
        frustum: The camera's frustum, in world space.
        slack: How far past a plane the bound may lie and still count.
        bounds: One local bound per geometry, filled in as met.
        known: Which entries of `bounds` have been filled in.

    Returns:
        Whether the object is kept, its world matrix, and its view depth.
        The matrix and the depth are unused when it is not kept.

    Raises:
        Error: If the material or the geometry is not there, or the
            geometry has no positions.
    """
    if casters_only and not _casts(cast_shadow, receive_shadow, receivers_cast):
        return (False, Matrix4(), 0)
    if not scene.shows(node, camera.visible_layers()):
        return (False, Matrix4(), 0)
    var world = scene.world_matrix(node)
    var nodes = assets.materials.get(material).nodes
    var moved = (
        nodes != NO_NODES
        and _checked_nodes(assets, nodes) != NO_NODES
        and assets.programs.get(nodes).has(POSITION_NODE)
    )
    if (
        frustum_culled
        and not moved
        and not _in_view(assets, geometry, world, frustum, slack, bounds, known)
    ):
        return (False, Matrix4(), 0)
    var depth = view.transform_point(
        Vector3(world.elements[12], world.elements[13], world.elements[14])
    ).z
    return (True, world^, depth)


@fieldwise_init
struct _Draw(ImplicitlyCopyable):
    """One geometry drawn with one material at one world transform.

    What a mesh is, and what each instance of an instanced or batched
    mesh is, with the instance's matrix folded into the node's. An
    LOD's level is a node, drawn by its meshes. `prepare` reads the scene as a list of these,
    so that everything after the draw order is written once.
    """

    var geometry: GeometryId
    var material: MaterialId
    var world: Matrix4
    # How much of each of the geometry's morph targets this draw wears.
    # A mesh's own; all zero for an instance or a batch member,
    # neither of which three.js morphs either.
    var morph_influences: MorphInfluences
    # Which of the frame's skins carries this draw, or minus one when
    # nothing does. Only a skinned mesh has one.
    var skin: Int
    # The camera-space depth of the draw's own placed origin, which is what
    # it was sorted by, and whether its material blends. Carried past the
    # sort so that `prepare_frame` can put the draw's primitives in order
    # with the segments', which are sorted by the same two.
    var depth: Float32
    var blends: Bool
    # Which of the scene's sprites this draw is, or minus one when it is
    # not one. A sprite names no geometry: `_prepared` builds its two
    # triangles from its node's world matrix instead; see
    # `objects.sprite`.
    var sprite: Int
    # Whether the lights' shadows fall on this draw: its mesh's
    # `receive_shadow`, and false for everything that is not a mesh.
    var receives_shadow: Bool
    # The render order of the draw's node, three.js's `renderOrder`,
    # which sorts before the depth.
    var order: Int
    # What the material's color is multiplied by, linear: an instance's
    # own color, three.js's `instanceColor`, and white for the rest.
    var tint: FloatColor
    # Which of the scene's wide lines this draw is, or minus one when it
    # is not one. `_prepared` builds its triangles from its geometry's
    # pairs of points; see `objects.line_segments2`.
    var wide_line: Int
    # Which instance of an instanced geometry this draw is, or minus one
    # when the geometry is not instanced. What a per-instance attribute is
    # read at; see `_instancing`.
    var instance: Int
    # The run of the geometry's triangle stream this draw fills: one
    # group of a mesh that wears a material list, three.js's `group` in
    # `renderBufferDirect`. `group_count` is minus one for the whole
    # stream, which is what every other draw fills.
    var group_start: Int
    var group_count: Int
    # The node the draw belongs to, what a render hook is told.
    var node: NodeId
    # Which faces a light's view of the casters draws: the object's own
    # material's `shadow_face`, whatever material draws it there.
    var cast_side: Side

    def source(self) -> _Source:
        """Return what drew this draw, for its run's `RenderItem`."""
        return _Source(self.node, self.geometry, self.material)


@fieldwise_init
struct RenderInfo(ImplicitlyCopyable):
    """What the renderer drew, three.js's `renderer.info.render`.

    `frame` counts the frames drawn. The rest count what the last frame
    drew, or every frame since `Renderer.reset_info` when
    `Renderer.info_auto_reset` is off.
    """

    var frame: Int
    # The runs drawn, three.js's draw calls: one per object and list.
    var calls: Int
    var triangles: Int
    var points: Int
    var lines: Int


struct _RendererState(Movable):
    """What a renderer counts while it draws: its `RenderInfo`, and the
    casters its last shadow pass drew. Held behind an `ArcPointer`, so a
    renderer counts through a read-only reference, as every caller holds
    one, and a supersampled twin counts into its parent's."""

    var info: RenderInfo
    var shadow_items: List[RenderItem]
    var shadow_lights: List[Int]
    # What a velocity attachment reads, three.js's `VelocityNode`: whether
    # the frame being drawn keeps velocities, the camera's view and
    # projection the frame before and this frame, and each object's world
    # matrix when a frame last drew it, by its node. `drawn_worlds` holds
    # this frame's until the frame is done.
    var tracks_velocity: Bool
    var knows_camera: Bool
    # The projection velocities are measured with in the place of the
    # camera's, or `None`: three.js's `VelocityNode.setProjectionMatrix`,
    # which TRAA sets to the camera's projection before its jitter.
    var velocity_projection: Optional[Matrix4]
    var previous_view: Matrix4
    var previous_projection: Matrix4
    var current_view: Matrix4
    var current_projection: Matrix4
    var previous_worlds: Dict[Int, Matrix4]
    var drawn_worlds: Dict[Int, Matrix4]

    def __init__(out self):
        """Count nothing yet."""
        self.info = RenderInfo(0, 0, 0, 0, 0)
        self.shadow_items = List[RenderItem]()
        self.shadow_lights = List[Int]()
        self.tracks_velocity = False
        self.knows_camera = False
        self.velocity_projection = None
        self.previous_view = Matrix4()
        self.previous_projection = Matrix4()
        self.current_view = Matrix4()
        self.current_projection = Matrix4()
        self.previous_worlds = Dict[Int, Matrix4]()
        self.drawn_worlds = Dict[Int, Matrix4]()

    def advance_camera(mut self, view: Matrix4, projection: Matrix4):
        """Begin a frame that keeps velocities: the camera's matrices of the
        last such frame become the previous ones, and these the current.
        The first frame's previous matrices are its own, so nothing has
        moved yet, as three.js's first frame.

        Args:
            view: The camera's view matrix this frame.
            projection: Its projection matrix this frame, which
                `velocity_projection` takes the place of when it is set.
        """
        var measured = projection
        if Bool(self.velocity_projection):
            measured = self.velocity_projection.value()
        if self.knows_camera:
            self.previous_view = self.current_view
            self.previous_projection = self.current_projection
        else:
            self.previous_view = view
            self.previous_projection = measured
            self.knows_camera = True
        self.current_view = view
        self.current_projection = measured

    def current_clip(self, world: Matrix4) -> Matrix4:
        """Return the matrix that puts a draw's vertex where this frame has
        it, in clip space, for a velocity: three.js's
        `clipPositionCurrent`.

        Args:
            world: The draw's world matrix this frame.

        Returns:
            The projection, view and model, in one.
        """
        return self.current_projection * self.current_view * world

    def previous_clip(
        mut self, node: NodeId, node_world: Matrix4, world: Matrix4
    ) raises -> Matrix4:
        """Return the matrix that puts a draw's vertex where the last frame
        had it, in clip space, and note the object's world matrix for the
        next frame: three.js's `previousProjectionMatrix`,
        `previousCameraViewMatrix` and `previousModelWorldMatrix`.

        An object first drawn now has not moved. One that moved carries
        what its node's matrix does not, an instance's own matrix, from
        this frame.

        Args:
            node: The draw's node.
            node_world: The node's world matrix this frame.
            world: The draw's world matrix this frame.

        Returns:
            The last frame's projection, view and model, in one.

        Raises:
            Error: Never: the node is looked up after it is known.
        """
        self.drawn_worlds[node.value] = node_world
        var model = world
        if node.value in self.previous_worlds:
            var then = self.previous_worlds[node.value]
            if then != node_world:
                var undo = node_world
                undo.invert()
                model = then * undo * world
        return self.previous_projection * self.previous_view * model

    def commit_worlds(mut self):
        """End a frame that keeps velocities: each object it drew keeps its
        world matrix for the next, three.js's `updateAfter`."""
        for entry in self.drawn_worlds.items():
            self.previous_worlds[entry.key] = entry.value
        self.drawn_worlds = Dict[Int, Matrix4]()
        self.tracks_velocity = False

    def begin_frame(mut self, auto_reset: Bool):
        """Count one more frame, and forget the last one's draws unless
        the caller keeps them."""
        self.info.frame += 1
        if auto_reset:
            self.reset()

    def reset(mut self):
        """Forget the draws counted so far, three.js's `info.reset`."""
        self.info.calls = 0
        self.info.triangles = 0
        self.info.points = 0
        self.info.lines = 0

    def count(mut self, items: List[RenderItem]):
        """Count one frame's runs by their kind."""
        for index in range(len(items)):
            ref item = items[index]
            self.info.calls += 1
            if item.kind == DRAW_TRIANGLES:
                self.info.triangles += item.count
            elif item.kind == DRAW_SPLATS:
                self.info.triangles += item.count * 2
            elif item.kind == DRAW_SEGMENTS:
                self.info.lines += item.count
            else:
                self.info.points += item.count


trait RenderHooks:
    """What a caller runs around a frame: three.js's `onBeforeRender`,
    `onAfterRender` and `onBeforeShadow`, of the scene and of each object.

    A trait rather than a function on each object, because a hook keeps
    state and a plain function cannot: a counter, a log, a list of what
    was drawn. Pass one to `Renderer.render_with` or
    `Renderer.render_into_with`. Every method does nothing unless a hook
    replaces it. A hook reads the scene and the item and cannot change
    them: the frame is prepared before the object hooks are called.
    """

    def on_before_scene(mut self, scene: Scene) raises:
        """Run before anything of the frame is prepared, three.js's
        `scene.onBeforeRender`.

        Args:
            scene: The scene about to be drawn.

        Raises:
            Error: Whatever the hook raises, which stops the frame.
        """
        pass

    def on_after_scene(mut self, scene: Scene) raises:
        """Run after the frame is drawn, three.js's `scene.onAfterRender`.

        Args:
            scene: The scene just drawn.

        Raises:
            Error: Whatever the hook raises.
        """
        pass

    def on_before_render(mut self, scene: Scene, item: RenderItem) raises:
        """Run before an object's run is drawn, three.js's
        `object.onBeforeRender`, in the frame's draw order.

        Args:
            scene: The scene.
            item: The run about to be drawn.

        Raises:
            Error: Whatever the hook raises, which stops the frame.
        """
        pass

    def on_after_render(mut self, scene: Scene, item: RenderItem) raises:
        """Run after an object's run is drawn, three.js's
        `object.onAfterRender`, in the frame's draw order.

        Args:
            scene: The scene.
            item: The run just drawn.

        Raises:
            Error: Whatever the hook raises.
        """
        pass

    def on_before_shadow(
        mut self, scene: Scene, item: RenderItem, light: Int
    ) raises:
        """Run for each run a light's shadow map drew, three.js's
        `object.onBeforeShadow`, once per face of a point light's cube.

        Args:
            scene: The scene.
            item: The caster's run, with the material the map drew it
                with.
            light: The light's index in `scene.lights`.

        Raises:
            Error: Whatever the hook raises, which stops the frame.
        """
        pass


struct NoHooks(RenderHooks):
    """The hooks `Renderer.render` runs: none."""

    def __init__(out self):
        """Make the empty set of hooks."""
        pass


def _note_span(
    mut spans: List[_Span],
    kind: DrawKind,
    begin: Int,
    end: Int,
    depth: Float32,
    blends: Bool,
    order: Int,
    source: _Source,
    transmits: Bool = False,
):
    """Record the primitives one draw emitted between two corner counts.

    Nothing is recorded for a draw that emitted none -- every triangle
    culled, or a wireframe with no edges -- so a `Draw` never names an
    empty run.

    Args:
        spans: The list to record into.
        kind: `DRAW_TRIANGLES`, `DRAW_SEGMENTS` or `DRAW_POINTS`, which
            says the stride.
        begin: How many corners the list held before the draw.
        end: How many it holds after.
        depth: The draw's camera-space depth.
        blends: Whether its material blends.
        order: Its node's render order.
        source: What drew it.
        transmits: Whether its material transmits.
    """
    var stride = kind.stride()
    var count = (end - begin) // stride
    if count > 0:
        spans.append(
            _Span(
                kind,
                begin // stride,
                count,
                depth,
                blends,
                order,
                source,
                transmits,
            )
        )


def _gather(
    mut draws: List[_Draw],
    mut depths: List[Float32],
    mut clear: List[Bool],
    scene: Scene,
    assets: Assets,
    node: NodeId,
    material: MaterialId,
    geometries: List[GeometryId],
    matrices: List[Matrix4],
    culled: Bool,
    view: Matrix4,
    visible: Layers,
    frustum: Frustum,
    slack: Float32,
    mut bounds: List[Sphere],
    mut known: List[Bool],
    morph_influences: MorphInfluences = MorphInfluences(),
    skin: Int = -1,
    receive_shadow: Bool = False,
    morphs: List[MorphInfluences] = List[MorphInfluences](),
    colors: List[Color] = List[Color](),
    instances: List[Int] = List[Int](),
    group_start: Int = 0,
    group_count: Int = -1,
    one_depth: Bool = False,
) raises:
    """Add the draws of one scene object to `draws`, each with its sort
    key alongside, unless the camera leaves it out.

    An object is a mesh, or every instance of an instanced or batched
    mesh: one node, one material, and a geometry and a matrix per
    draw. It is left out whole when its node shares no layer
    with the camera, three.js's `layers.test` in `projectObject`, before
    anything is measured for it. Each draw is left out on its own when
    its bound lies wholly outside the frustum, three.js's `frustumCulled`
    test in the same function, unless the object opted out; three.js
    tests an instanced mesh by one bound around every instance, and a
    test per instance is what lets the instances behind the camera cost
    nothing. Of a draw left out here only the positions are read, for the
    bound, and whether its material names a displacement map, which moves
    the surface off that bound and so keeps the draw: its material's
    textures and its index buffer are checked when it is drawn, as
    three.js reads nothing of an object it culls, and the material itself
    is looked up once the first draw survives.

    Each draw's depth is its own placed origin's, not its node's, so that
    an instance sorts where it is. And each instance matrix is asked
    again whether it places -- affine, and finite -- whether or not it is
    culled: the lists that hold them are open, and a check at
    `set_matrix_at` alone is a check a caller can walk past.

    Args:
        draws: Every draw so far; the object's are appended.
        depths: Each draw's camera-space depth, appended alongside.
        clear: Whether each draw's material blends, appended alongside.
        scene: The transform hierarchy, updated.
        assets: Where the geometries and materials live.
        node: The object's node.
        material: The object's material.
        geometries: One geometry per draw.
        matrices: One transform per draw, relative to the node; as many
            as `geometries`.
        culled: Whether a draw may be left out for its bound.
        view: The world-to-camera transform, for the depth.
        visible: The camera's layers.
        frustum: The camera's frustum, in world space.
        slack: How far past a plane a bound may lie and still be drawn;
            see `CULL_SLACK`.
        bounds: Each geometry's local bound, filled in as met.
        known: Which entries of `bounds` have been filled in.
        morph_influences: How much of each morph target the object wears.
            A mesh's own, and all zero for everything else.
        skin: Which of the frame's skins carries the object, or minus one.
            Only a skinned mesh has one.
        receive_shadow: Whether the lights' shadows fall on the object,
            a mesh's `receive_shadow`. Off for everything else.
        morphs: The morph weights of each draw, in place of
            `morph_influences`, as an instanced mesh's `morphs` holds
            them. A draw past its end wears `morph_influences`.
        colors: An sRGB color per draw, which multiplies the material's
            color. A draw past the end of the list is white, as three.js
            reads an instance with no `instanceColor`, and a color past
            the last draw is not read.
        instances: Which instance of an instanced geometry each draw is,
            or none when the geometry is not instanced.
        group_start: The first slot of the triangle stream each draw
            fills: a group's `start`, or zero for the whole stream.
        group_count: How many slots each draw fills: a group's `count`,
            or minus one for the whole stream.
        one_depth: Whether every draw takes the node's depth, so that
            the stable sort keeps them in the order given: a batch with a
            custom sort.

    Raises:
        Error: If the node, a geometry or the material is not there, a
            geometry has no positions, the scene is stale, or an instance
            matrix projects or holds a value that is not finite.
    """
    if not scene.shows(node, visible):
        return
    var placed = scene.world_matrix(node)
    var blends = False
    var asked = False
    var cast_side = FRONT_SIDE
    for index in range(len(matrices)):
        check_placing(matrices[index])
        var world = Matrix4(copy=placed)
        world.multiply(matrices[index])
        if (
            culled
            and not _in_view(
                assets, geometries[index], world, frustum, slack, bounds, known
            )
            and not _displaces(assets, material)
        ):
            continue
        if not asked:
            # A material that is not `visible` leaves the object out of
            # every list, three.js's `material.visible` in
            # `projectObject` and in the shadow map's `renderObject`.
            var own = assets.materials.get(material)
            if not own.visible:
                return
            blends = own.is_transparent()
            cast_side = own.shadow_face()
            asked = True
        # The camera looks down -z, so a smaller z is further away. The
        # draw's own origin: the translation column of where it is placed.
        ref origin = placed if one_depth else world
        var depth = view.transform_point(
            Vector3(
                origin.elements[12], origin.elements[13], origin.elements[14]
            )
        ).z
        depths.append(depth)
        clear.append(blends)
        var tint = FloatColor(1, 1, 1, 1)
        if index < len(colors):
            tint = FloatColor(srgb=colors[index])
        var instance = -1
        if len(instances) > 0:
            instance = instances[index]
        var worn = morph_influences
        if index < len(morphs):
            worn = morphs[index]
        draws.append(
            _Draw(
                geometries[index],
                material,
                world^,
                worn,
                skin,
                depth,
                blends,
                -1,
                receive_shadow,
                scene.render_order(node),
                tint,
                -1,
                instance,
                group_start,
                group_count,
                node,
                cast_side,
            )
        )


def _gather_batch(
    mut draws: List[_Draw],
    mut depths: List[Float32],
    mut clear: List[Bool],
    scene: Scene,
    assets: Assets,
    batch: BatchedMesh,
    view: Matrix4,
    visible: Layers,
    frustum: Frustum,
    slack: Float32,
    mut bounds: List[Sphere],
    mut known: List[Bool],
) raises:
    """Add the draws of one batched mesh, as `_gather` adds an object's.

    A deleted or hidden instance is left out, as three.js's
    `onBeforeRender` leaves it out. With `per_object_frustum_culled` each
    instance out of view is left out; without it, the batch is left out
    only when every instance is out of view. A batch with a custom sort
    hands the instances in view to it, each with its depth in front of
    the camera, three.js's `z`, and draws them in the order it leaves them,
    all at the node's depth.

    Args:
        draws: Every draw so far; the batch's are appended.
        depths: Each draw's camera-space depth, appended alongside.
        clear: Whether each draw's material blends, appended alongside.
        scene: The transform hierarchy, updated.
        assets: Where the geometries and materials live.
        batch: The batched mesh.
        view: The world-to-camera transform.
        visible: The camera's layers.
        frustum: The camera's frustum, in world space.
        slack: How far past a plane a bound may lie and still be drawn.
        bounds: Each geometry's local bound, filled in as met.
        known: Which entries of `bounds` have been filled in.

    Raises:
        Error: For anything `_gather` raises for, or if a custom sort
            leaves an instance in the list that is not drawn.
    """
    if not scene.shows(batch.node, visible):
        return
    var placed = scene.world_matrix(batch.node)
    var each = batch.frustum_culled and batch.per_object_frustum_culled
    var items = List[BatchedDrawItem]()
    var any_inside = False
    for slot in range(batch.count()):
        if not batch.is_drawn(slot):
            continue
        ref member = batch.instances[slot]
        check_placing(member.matrix)
        var world = Matrix4(copy=placed)
        world.multiply(member.matrix)
        var inside = True
        if batch.frustum_culled:
            inside = _in_view(
                assets, member.geometry, world, frustum, slack, bounds, known
            ) or _displaces(assets, batch.material)
        if each and not inside:
            continue
        any_inside = any_inside or inside
        var ahead = -view.transform_point(
            Vector3(world.elements[12], world.elements[13], world.elements[14])
        ).z
        items.append(BatchedDrawItem(slot, ahead))
    if not any_inside:
        return
    # A batch with no custom sort holds one that keeps the order.
    batch.custom_sort(items)
    var geometries = List[GeometryId]()
    var matrices = List[Matrix4]()
    var colors = List[Color]()
    # An instance is in view, or the batch returned above: this runs.
    for item in items:  # pragma: no branch
        if not batch.is_drawn(item.index):
            raise Error("A custom sort left an instance that is not drawn")
        ref member = batch.instances[item.index]
        geometries.append(member.geometry)
        matrices.append(member.matrix)
        colors.append(member.color)
    _gather(
        draws,
        depths,
        clear,
        scene,
        assets,
        batch.node,
        batch.material,
        geometries,
        matrices,
        False,
        view,
        visible,
        frustum,
        slack,
        bounds,
        known,
        receive_shadow=batch.receive_shadow,
        colors=colors,
        one_depth=batch.custom_sorted,
    )


def _draws(
    scene: Scene,
    assets: Assets,
    view: Matrix4,
    visible: Layers,
    frustum: Frustum,
    slack: Float32,
    mut skins: List[SkinPose],
    casters_only: Bool = False,
    receivers_cast: Bool = False,
    distance_casters: Bool = False,
    override: Optional[MaterialId] = None,
    uv_meshes: List[Int] = List[Int](),
) raises -> List[_Draw]:
    """Return what the camera draws, in the order to draw it: opaque
    draws nearest first, then the translucent ones furthest first.

    The scene's meshes, instanced meshes and batched meshes are read into
    draws by `_gather`, which also leaves out what the camera's layers and
    frustum leave out. An LOD's levels are nodes: the one
    `Scene.update_lods` shows is drawn by what it carries, and the hidden
    ones are left out as any hidden node is. A mesh that wears a material list
    contributes a draw per group, in the group's material, as three.js's
    `projectObject` pushes a render item per group: each goes into the
    opaque or the translucent list by its own material, at the mesh's
    depth.

    Blending is not commutative, so a translucent surface only looks right if
    what is behind it is already there. Two rules follow, and they are the
    same two every renderer has:

    Opaque first, because a translucent surface has to mix with the solid
    thing behind it, and because opaque surfaces write depth — which is what
    stops a translucent surface behind a wall from showing through it. Among
    themselves the opaque draws go nearest first. The image does not depend
    on it, since the depth test settles every pixel whatever the order, but
    the cost does: a fragment that fails the depth test is skipped *before*
    it is lit and sampled, so drawing the near things first means the far
    things' hidden fragments are never shaded at all. three.js sorts its
    opaque list front to back for the same reason.

    Then translucent, furthest first, because each one mixes into the result
    of the ones beyond it. Sorted by the camera-space depth of each draw's
    own origin: per draw, not per triangle, and per instance rather than per
    object. three.js sorts an InstancedMesh as one object and a
    BatchedMesh's members among themselves, which puts a translucent
    instance in front of one it should be behind whenever the two were
    added the other way round; a software renderer that prepares every
    instance anyway can afford to order them right, and to let a
    translucent mesh between two instances of a group fall between them.
    Within one draw the triangles keep their own order, so a translucent
    mesh that overlaps itself is still approximate. That is the usual
    bargain, and the alternative is sorting every triangle every frame.

    Args:
        scene: The transform hierarchy, and what it draws.
        assets: Where the geometries and materials live.
        view: The world-to-camera transform, for measuring depth.
        visible: The camera's layers. An object on none of them is left
            out.
        frustum: The camera's frustum, in world space. A draw whose bound
            lies wholly outside it is left out, unless its object opted out.
        slack: How far past a plane a bound may lie and still be drawn;
            see `CULL_SLACK`.
        skins: The frame's posed skeletons; one is appended per skinned
            mesh, and the draws name them by index.
        casters_only: Whether this is a light's view for a shadow map,
            which holds the meshes that cast and nothing else: a mesh, a
            skinned, instanced or batched mesh, a line or points whose
            `cast_shadow` is set. An LOD's level is a node, and casts by
            what it carries. A sprite and a wide line cast nothing, as
            three.js's `Sprite` casts nothing.
        receivers_cast: Whether a light's view also holds the meshes that
            receive a shadow, as three.js draws them into a
            `VSM_SHADOW_MAP`.
        distance_casters: Whether a light's view is a point light's, which
            draws a mesh with its `custom_distance_material` rather than
            its `custom_depth_material`.
        override: The material that takes the place of every object's,
            `Renderer.drawn_override`: the renderer's or the scene's, or
            none.
        uv_meshes: `Renderer.uv_space_meshes`: the meshes a light map's
            frame draws, none culled, and nothing else. Empty for a frame
            seen through the camera.

    Returns:
        The draws the camera makes, in the order to make them. A frame's
        draws are drawn with `override` where it applies; a light's view keeps each mesh's own, or its custom one.

    Raises:
        Error: If anything drawn names a node, a geometry or a material
            that is not there, a geometry has no positions, or an instance
            matrix cannot place an instance.
    """
    var draws = List[_Draw]()
    var depths = List[Float32]()
    var clear = List[Bool]()
    # Each geometry's local bound, found the first time a draw needs it
    # this frame and reused by every other draw that does.
    var bounds = List[Sphere](
        length=assets.geometries.count(), fill=Sphere.empty()
    )
    var known = List[Bool](length=assets.geometries.count(), fill=False)
    var one: List[Matrix4] = [Matrix4()]
    # In texture space, only the meshes named, and none culled: the
    # camera does not frame them.
    var uv_space = len(uv_meshes) > 0
    for index in range(len(scene.meshes)):
        ref mesh = scene.meshes[index]
        if uv_space and index not in uv_meshes:
            continue
        if casters_only and not _casts(
            mesh.cast_shadow, mesh.receive_shadow, receivers_cast
        ):
            continue
        # Left out before its geometry is read, as `_gather` would leave
        # it out.
        if not scene.shows(mesh.node, visible):
            continue
        # An instanced geometry is drawn once per instance, each draw
        # placed and culled on its own as an instanced mesh's are.
        var placing = _instancing(assets.geometries.get(mesh.geometry))
        var geometry = List[GeometryId](
            length=len(placing[0]), fill=mesh.geometry
        )
        # A mesh wearing a material list is drawn once per group, each
        # in the material its index names, as three.js's `projectObject`
        # pushes one render item per group. A group past the end of the
        # list is not drawn. A mesh with one material is one run over the
        # whole stream, whatever groups its geometry has.
        var runs = List[GeometryGroup]()
        var wears = List[MaterialId]()
        if mesh.is_multi_material():
            for group in assets.geometries.get(mesh.geometry).groups:
                var worn = mesh.group_material(group.material_index)
                if Bool(worn):
                    runs.append(group)
                    wears.append(worn.value())
        else:
            runs.append(GeometryGroup(0, -1, MaterialIndex(0)))
            wears.append(mesh.material)
        # A mesh wearing a morph target is not where its geometry's bound
        # says it is, so it is not measured against the frustum. The bound
        # describes the face the mesh has stopped wearing. three.js culls
        # it anyway and clips morphed meshes at the edge of the view for
        # exactly this reason.
        var before = len(draws)
        for run in range(len(runs)):
            _gather(
                draws,
                depths,
                clear,
                scene,
                assets,
                mesh.node,
                wears[run],
                geometry,
                placing[0],
                mesh.frustum_culled and not mesh.is_morphed() and not uv_space,
                view,
                visible,
                frustum,
                slack,
                bounds,
                known,
                mesh.morph_influences,
                receive_shadow=mesh.receive_shadow,
                instances=placing[1],
                group_start=runs[run].start,
                group_count=runs[run].count,
            )
        # A light's view draws the mesh with its custom depth or distance
        # material, three.js's `getDepthMaterial`, when it has one.
        var custom = mesh.custom_depth_material
        if distance_casters:
            custom = mesh.custom_distance_material
        var swapped = Bool(custom)
        if casters_only and swapped:
            for slot in range(before, len(draws)):
                draws[slot].material = custom.value()
    # A light's view holds every other kind that casts, as three.js's
    # `renderObject` draws any mesh, line or points object whose
    # `castShadow` is set: a skinned mesh posed, each instance placed.
    for index in range(0 if uv_space else len(scene.skinned_meshes)):
        ref skinned = scene.skinned_meshes[index]
        if casters_only and not _casts(
            skinned.cast_shadow, skinned.receive_shadow, receivers_cast
        ):
            continue
        skins.append(skin_pose(scene, index))
        var skin_geometry: List[GeometryId] = [skinned.geometry]
        _gather(
            draws,
            depths,
            clear,
            scene,
            assets,
            skinned.node,
            skinned.material,
            skin_geometry,
            one,
            skinned.frustum_culled,
            view,
            visible,
            frustum,
            slack,
            bounds,
            known,
            skinned.morph_influences,
            len(skins) - 1,
            receive_shadow=skinned.receive_shadow,
        )
    for index in range(0 if uv_space else len(scene.instanced_meshes)):
        ref group = scene.instanced_meshes[index]
        if casters_only and not _casts(
            group.cast_shadow, group.receive_shadow, receivers_cast
        ):
            continue
        _gather(
            draws,
            depths,
            clear,
            scene,
            assets,
            group.node,
            group.material,
            List[GeometryId](length=group.count(), fill=group.geometry),
            group.matrices,
            group.frustum_culled,
            view,
            visible,
            frustum,
            slack,
            bounds,
            known,
            receive_shadow=group.receive_shadow,
            colors=group.colors,
            morphs=group.morphs,
        )
    for index in range(0 if uv_space else len(scene.batched_meshes)):
        ref batch = scene.batched_meshes[index]
        if casters_only and not _casts(
            batch.cast_shadow, batch.receive_shadow, receivers_cast
        ):
            continue
        _gather_batch(
            draws,
            depths,
            clear,
            scene,
            assets,
            batch,
            view,
            visible,
            frustum,
            slack,
            bounds,
            known,
        )
    # An LOD's levels are nodes, drawn by what they carry: the level
    # `Scene.update_lods` chose is shown and the others hidden, as
    # three.js's `LOD.update` sets their `visible`.
    # The sprites, sorted among the meshes by their own depth so that a
    # translucent sprite falls between the translucent surfaces either
    # side of it. Culled by the sphere around the unit square carried by
    # the world matrix, three.js's `Sprite` geometry bound.
    for index in range(0 if uv_space else len(scene.sprites)):
        if casters_only:
            continue
        ref sprite = scene.sprites[index]
        if not scene.shows(sprite.node, visible):
            continue
        var world = scene.world_matrix(sprite.node)
        if sprite.frustum_culled:
            var bound = Sphere(Vector3(0, 0, 0), SPRITE_RADIUS)
            bound.apply_matrix4(world)
            bound.radius += slack
            if not frustum.intersects_sphere(bound):
                continue
        var depth = view.transform_point(
            Vector3(world.elements[12], world.elements[13], world.elements[14])
        ).z
        var shown = assets.materials.get(sprite.material)
        if not shown.visible:
            continue
        var blends = shown.is_transparent()
        depths.append(depth)
        clear.append(blends)
        draws.append(
            _Draw(
                GeometryId(-1),
                sprite.material,
                world^,
                MorphInfluences(),
                -1,
                depth,
                blends,
                index,
                False,
                scene.render_order(sprite.node),
                FloatColor(1, 1, 1, 1),
                -1,
                -1,
                0,
                -1,
                sprite.node,
                FRONT_SIDE,
            )
        )
    # The wide lines, sorted among the meshes by their own depth, as the
    # sprites are. Culled by the bound of their points, as three.js's
    # `LineSegments2` is: the width is not added to it. Strand coverage
    # opts into shadow casting; ordinary wide lines do not cast by default.
    for index in range(len(scene.wide_lines)):
        ref line = scene.wide_lines[index]
        require_line_coverage(line.coverage)
        if casters_only and not line.cast_shadow:
            continue
        if not scene.shows(line.node, visible):
            continue
        var world = scene.world_matrix(line.node)
        # A feather can cross the image edge while its centerline does
        # not. The ordinary three.js bound excludes width; strands must
        # not use that bound as a proof that coverage is outside.
        if (
            line.frustum_culled
            and line.coverage != STRAND_LINE_COVERAGE
            and not _in_view(
                assets, line.geometry, world, frustum, slack, bounds, known
            )
        ):
            continue
        var depth = view.transform_point(
            Vector3(world.elements[12], world.elements[13], world.elements[14])
        ).z
        var shown = assets.materials.get(line.material)
        if not shown.visible:
            continue
        var blends = shown.is_transparent()
        depths.append(depth)
        clear.append(blends)
        draws.append(
            _Draw(
                line.geometry,
                line.material,
                world^,
                MorphInfluences(),
                -1,
                depth,
                blends,
                -1,
                False,
                scene.render_order(line.node),
                FloatColor(1, 1, 1, 1),
                index,
                -1,
                0,
                -1,
                line.node,
                FRONT_SIDE,
            )
        )

    var orders = List[Int]()
    for index in range(len(draws)):
        orders.append(draws[index].order)
    var ranked = _opaque_then_blended(clear, depths, orders)
    var ordered = List[_Draw]()
    for position in range(len(ranked)):
        ordered.append(draws[ranked[position]])
    # The scene's override draws what the frame draws, each in the list
    # its own material put it in, as three.js's `renderObjects` swaps it
    # in after the lists are made. A light's view keeps the casters' own.
    var overridden = Bool(override)
    if overridden and not casters_only:
        for position in range(len(ordered)):
            ordered[position].material = _drawn_material(
                override,
                assets.materials.get(ordered[position].material),
                ordered[position].material,
            )
    return ordered^


def _casts(cast_shadow: Bool, receive_shadow: Bool, receivers: Bool) -> Bool:
    """Return True if a light's view draws an object: it casts, or it
    receives and the view draws the receivers too.

    three.js's `castShadow || ( receiveShadow && type === VSMShadowMap )`
    in `WebGLShadowMap.renderObject`.

    Args:
        cast_shadow: The object's `cast_shadow`.
        receive_shadow: The object's `receive_shadow`.
        receivers: Whether the view draws the receivers, under
            `VSM_SHADOW_MAP`.

    Returns:
        Whether the object is drawn into the map.
    """
    return cast_shadow or (receivers and receive_shadow)


def _turned_around(corner: RasterVertex) -> RasterVertex:
    """Return `corner` with its normal reversed, and its normal and bump
    map scales with it.

    For a surface being seen from its far side. Every other field is
    carried across unchanged, which is why this exists rather than a
    mutation: rebuilding a `RasterVertex` by hand at three call sites is
    three chances to drop a field. It dropped seven once anyway, when
    fields were added after it: a two-sided reflective mesh lost its env
    map on its back. So it copies the corner and changes what it must.

    The map scales turn with the normal because a map perturbs the normal
    in a frame the surface's own front defines, and the far side's
    perturbed normal is the front's negated: three.js negates the tangent
    and the bitangent under `DOUBLE_SIDED` by `faceDirection`, and a bump
    map's slope by the same sign. Negating the scales does exactly that;
    see `render.rasterizer.mapped_normal`. An anisotropic lobe is
    stretched along the same frame, so its vector turns the same way, and
    a clear coat's normal map perturbs along it, so its scale does too.
    """
    var turned = corner
    turned.normal = -corner.normal
    # A Gouraud corner was lit on both sides; the far side's light is the
    # one drawn now.
    turned.gouraud_direct = corner.gouraud_back_direct
    turned.gouraud_indirect = corner.gouraud_back_indirect
    turned.gouraud_back_direct = corner.gouraud_direct
    turned.gouraud_back_indirect = corner.gouraud_indirect
    turned.normal_scale = Vector2(
        -corner.normal_scale.x, -corner.normal_scale.y
    )
    turned.bump_scale = -corner.bump_scale
    # An object-space normal map's normal is the mesh's, turned by its
    # normal matrix, and three.js multiplies it by `faceDirection` too.
    turned.frames.object_normal = _negated(corner.frames.object_normal)
    turned.layers.anisotropy = Vector2(
        -corner.layers.anisotropy.x, -corner.layers.anisotropy.y
    )
    # Only with a map to scale: a scale of minus one with none would make
    # a corner of any kind look as if it named a clearcoat map.
    if corner.layers.clearcoat_normal_map != NO_TEXTURE:
        turned.layers.clearcoat_normal_scale = Vector2(
            -corner.layers.clearcoat_normal_scale.x,
            -corner.layers.clearcoat_normal_scale.y,
        )
    return turned


def _clip_of(matrix: Matrix4, point: Vector3) -> Vector3:
    """Return a point's clip-space x, y and w under `matrix`, which takes
    it as a position: what a velocity attachment interpolates. See
    `render.rasterizer.fragment_velocity`."""
    ref e = matrix.elements
    return Vector3(
        e[0] * point.x + e[4] * point.y + e[8] * point.z + e[12],
        e[1] * point.x + e[5] * point.y + e[9] * point.z + e[13],
        e[3] * point.x + e[7] * point.y + e[11] * point.z + e[15],
    )


def light_masks(assets: Assets) raises -> List[LightMask]:
    """Return the light masks the materials name, three.js's `lightsNode`,
    each once, in the order of the first material to name it. A material
    lit by every light names none.

    Args:
        assets: The materials.

    Returns:
        The masks. A triangle of the `i`th is lit by the frame's lighting
        `i + 1`; see `RasterVertex.lights`.

    Raises:
        Error: Never: every id asked is in the store.
    """
    var masks = List[LightMask]()
    for index in range(assets.materials.count()):
        var mask = assets.materials.get(MaterialId(index)).lights
        if mask != ALL_LIGHTS and mask not in masks:
            masks.append(mask)
    return masks^


def _mask_place(masks: List[LightMask], mask: LightMask) -> Int:
    """Return which of the frame's lightings a material's mask names: zero
    for every light, and one past its place in `masks` otherwise."""
    var at = first_match(masks, mask)
    if at < 0:
        return 0
    return at + 1


def _to_raster(
    vertex: ClipVertex,
    to_screen: Matrix4,
    texture: TextureId,
    blend: Blending,
    kind: MaterialKind,
    emissive_map: TextureId,
    alpha_map: TextureId,
    alpha_test: Float32,
    specular: FloatColor,
    shininess: Float32,
    gradient_map: TextureId,
    matcap: TextureId,
    dash_size: Float32 = 0,
    gap_size: Float32 = 0,
    point_size: Float32 = 0,
    env_map: CubeTextureId = NO_CUBE_TEXTURE,
    reflectivity: Float32 = 1,
    combine: Combine = MULTIPLY_OPERATION,
    physics: _Physics = _Physics(),
    receives_shadow: Bool = True,
    state: RasterState = RasterState(),
    *,
    shown: _Shown,
) -> RasterVertex:
    """Project a clipped camera-space vertex into the rasterizer's input.

    `transform_point` does the perspective divide and throws the divisor away,
    which is all a position needs. Anything interpolated *alongside* the
    position needs the divisor too, so it is asked for separately and kept as
    its reciprocal — see `RasterVertex`.
    """
    var w = to_screen.transform_w(vertex.position)
    var inv_w = Float32(0)
    # Clipping has already removed everything at or behind the near plane, so
    # w is positive here. The guard costs nothing and keeps a degenerate
    # camera from producing infinities rather than a visible error.
    if w != 0:  # pragma: no branch
        inv_w = Float32(1) / w
    var screen = to_screen.transform_point(vertex.position)
    return RasterVertex(
        screen.x,
        screen.y,
        screen.z,
        inv_w,
        vertex.color,
        vertex.u,
        vertex.v,
        texture,
        blend,
        vertex.normal,
        vertex.world,
        kind,
        vertex.emissive,
        emissive_map,
        # How far in front of the camera this corner is, for the fog: the
        # camera looks down -z, and the position is already in its space.
        -vertex.position.z,
        alpha_map,
        alpha_test,
        specular,
        shininess,
        gradient_map,
        matcap,
        vertex.line_distance,
        dash_size,
        gap_size,
        point_size,
        env_map,
        reflectivity,
        combine,
        physics.roughness,
        physics.metalness,
        physics.env_map_intensity,
        physics.roughness_map,
        physics.metalness_map,
        physics.specular_intensity,
        physics.clearcoat,
        physics.clearcoat_roughness,
        physics.normal_map,
        physics.normal_scale,
        physics.bump_map,
        physics.bump_scale,
        receives_shadow,
        state,
        vertex.u1,
        vertex.v1,
        physics.ao_map,
        physics.ao_map_intensity,
        physics.light_map,
        physics.light_map_intensity,
        physics.specular_map,
        physics.transmission,
        physics.transmission_map,
        physics.thickness,
        physics.thickness_map,
        physics.attenuation_color,
        physics.attenuation_distance,
        physics.dispersion,
        physics.ior,
        shown.fog,
        shown.depth_packing,
        shown.reference,
        shown.near_distance,
        shown.far_distance,
        physics.layers,
        physics.nodes,
    )


@fieldwise_init
struct _Shown(ImplicitlyCopyable):
    """What every corner of one draw carries for the fog switch and the
    data kinds: whether the fog veils it, how a depth is packed, and where
    a distance is measured from and between which two distances.
    """

    var fog: Bool
    var depth_packing: DepthPacking
    var reference: Vector3
    var near_distance: Float32
    var far_distance: Float32


def _shown_of(material: Material) raises -> _Shown:
    """Return what a material says about its fog, its depth packing and
    its distance range, checked.

    Args:
        material: The draw's material.

    Returns:
        The five, as every corner of the draw carries them.

    Raises:
        Error: If `Material.check_data` refuses them.
    """
    material.check_data()
    return _Shown(
        material.fog,
        material.depth_packing,
        material.reference_position,
        material.near_distance.to(METER),
        material.far_distance.to(METER),
    )


@fieldwise_init
struct _Physics(ImplicitlyCopyable):
    """What a physical surface, a normal or bump map, the two baked maps,
    a specular map and a volume add to every corner of one draw: the
    numbers and the maps `RasterVertex` carries for them, gathered so
    `_to_raster` takes one more argument rather than twenty-five.
    """

    var roughness: Float32
    var metalness: Float32
    var env_map_intensity: Float32
    var roughness_map: TextureId
    var metalness_map: TextureId
    var specular_intensity: Float32
    var clearcoat: Float32
    var clearcoat_roughness: Float32
    var normal_map: TextureId
    var normal_scale: Vector2
    var bump_map: TextureId
    var bump_scale: Float32
    var ao_map: TextureId
    var ao_map_intensity: Float32
    var light_map: TextureId
    var light_map_intensity: Float32
    var specular_map: TextureId
    var transmission: Float32
    var transmission_map: TextureId
    # The material's thickness times the length of each axis of the draw's
    # world matrix, three.js's `thickness * modelScale`.
    var thickness: Vector3
    var thickness_map: TextureId
    # Decoded to linear once, as the base color is.
    var attenuation_color: FloatColor
    var attenuation_distance: Float32
    var dispersion: Float32
    var ior: Float32
    var layers: LayerFactors
    # The node material's program, or `NO_NODES`.
    var nodes: NodeProgramId
    # The light through a `PHONG` surface; see `Scattering`.
    var scattering: Scattering

    def __init__(out self):
        """Describe a surface that is not physical and carries no map: the
        `RasterVertex` defaults."""
        self.roughness = 1
        self.metalness = 0
        self.env_map_intensity = 1
        self.roughness_map = NO_TEXTURE
        self.metalness_map = NO_TEXTURE
        self.specular_intensity = 1
        self.clearcoat = 0
        self.clearcoat_roughness = 0
        self.normal_map = NO_TEXTURE
        self.normal_scale = Vector2(1, 1)
        self.bump_map = NO_TEXTURE
        self.bump_scale = 1
        self.ao_map = NO_TEXTURE
        self.ao_map_intensity = 1
        self.light_map = NO_TEXTURE
        self.light_map_intensity = 1
        self.specular_map = NO_TEXTURE
        self.transmission = 0
        self.transmission_map = NO_TEXTURE
        self.thickness = Vector3(0, 0, 0)
        self.thickness_map = NO_TEXTURE
        self.attenuation_color = FloatColor(1.0, 1.0, 1.0)
        self.attenuation_distance = NO_ATTENUATION.to(METER)
        self.dispersion = 0
        self.ior = DEFAULT_IOR
        self.layers = LayerFactors()
        self.nodes = NO_NODES
        self.scattering = NO_SCATTERING


def _plane_in_view(plane: Plane, view: Matrix4) raises -> Plane:
    """Return a world-space plane carried into camera space.

    Its normal goes through the normal matrix, so that a view with a
    scale still keeps it perpendicular to the plane, and a point on it
    goes through the view itself.

    Args:
        plane: The plane, in world space.
        view: The world-to-camera transform.

    Returns:
        The same plane, in camera space.

    Raises:
        Error: If the view cannot be inverted.
    """
    var normal = view.normal_matrix().transform_direction(plane.normal)
    return Plane.from_normal_and_point(
        normal, view.transform_point(plane.coplanar_point())
    )


def _clip_sets(
    material: Material,
    view: Matrix4,
    sides: List[Plane],
    global_planes: List[Plane],
    local: Bool,
    casters_only: Bool,
    mut cut: List[Plane],
    mut any_of: List[Plane],
) raises:
    """Work out which planes cut one draw, in camera space.

    `cut` is every plane a kept point must be in front of: the camera's
    sides, the renderer's clipping planes, and the material's own under
    the union rule. `any_of` is the material's own under
    `clip_intersection`, of which a kept point needs only one. A shadow
    pass is given no renderer planes, and the material's only under
    `clip_shadows`, as three.js's `WebGLClipping` does.

    Args:
        material: The draw's material.
        view: The world-to-camera transform.
        sides: The camera's side planes, in camera space.
        global_planes: The renderer's planes, already in camera space.
        local: Whether the renderer lets a material's planes cut.
        casters_only: Whether this is a light's view for a shadow map.
        cut: Set to the planes that each cut.
        any_of: Set to the planes of which one is enough.

    Raises:
        Error: If the view cannot be inverted, or a material's plane
            count is below zero or above eight.
    """
    cut = sides.copy()
    any_of = List[Plane]()
    if not casters_only:
        cut.extend(Span(global_planes))
    var own = local and material.clip_plane_count > 0
    if not own or (casters_only and not material.clip_shadows):
        return
    var planes = material.clipping_planes()
    # At least one: `own` above asked for a count above zero.
    for index in range(len(planes)):  # pragma: no branch
        var seen = _plane_in_view(planes[index], view)
        if material.clip_intersection:
            any_of.append(seen)
        else:
            cut.append(seen)


def _group_clip_sets(
    scene: Scene,
    node: NodeId,
    view: Matrix4,
    casters_only: Bool,
    mut cut: List[Plane],
    mut any_of: List[Plane],
) raises:
    """Add the planes of the clipping groups at a draw's node and above it,
    in camera space, three.js's `ClippingGroup`.

    A group's union planes each cut, so they join `cut`. Its intersection
    planes join `any_of`, with the material's own. See
    `objects.clipping_group`.

    Args:
        scene: The scene, which holds the groups.
        node: The draw's node.
        view: The world-to-camera transform.
        casters_only: Whether this is a light's view for a shadow map.
        cut: The planes that each cut, added to.
        any_of: The planes of which one is enough, added to.

    Raises:
        Error: If the node is not in the scene, or the view cannot be
            inverted.
    """
    var groups = scene.clipping(node, casters_only)
    cut.extend(Span(_planes_in_view(groups.union_planes, view)))
    any_of.extend(Span(_planes_in_view(groups.intersection_planes, view)))


def _clip_draw(
    material: Material,
    scene: Scene,
    node: NodeId,
    view: Matrix4,
    sides: List[Plane],
    global_planes: List[Plane],
    local: Bool,
    casters_only: Bool,
    mut cut: List[Plane],
    mut any_of: List[Plane],
) raises:
    """Set the planes that cut one draw, then add its clipping groups.

    Args:
        material: The draw's material.
        scene: The scene, which holds the groups.
        node: The draw's node.
        view: The world-to-camera transform.
        sides: The camera's side planes, in camera space.
        global_planes: The renderer's planes, already in camera space.
        local: Whether the renderer lets a material's planes cut.
        casters_only: Whether this is a light's view for a shadow map.
        cut: Set to the planes that each cut, then the groups' union.
        any_of: Set to the planes of which one is enough, then the
            groups' intersection.

    Raises:
        Error: Everything `_clip_sets` and `_group_clip_sets` raise.
    """
    _clip_sets(
        material,
        view,
        sides,
        global_planes,
        local,
        casters_only,
        cut,
        any_of,
    )
    _group_clip_sets(scene, node, view, casters_only, cut, any_of)


def _planes_in_view(planes: List[Plane], view: Matrix4) raises -> List[Plane]:
    """Return world-space planes carried into camera space.

    Args:
        planes: The planes, in world space.
        view: The world-to-camera transform.

    Returns:
        The planes, in camera space, in order.

    Raises:
        Error: If the view cannot be inverted.
    """
    var seen = List[Plane]()
    for index in range(len(planes)):
        seen.append(_plane_in_view(planes[index], view))
    return seen^


def _whole_in_view(
    a: ClipVertex,
    b: ClipVertex,
    c: ClipVertex,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane] = List[Plane](),
) -> Bool:
    """Return True if no corner of the triangle needs cutting.

    Asked corner by corner, so a triangle is refused as soon as one corner
    is outside and the other two are not examined. The depth is asked
    first, because it is the cheaper test and the one a corner behind the
    camera fails.

    Args:
        a: The first corner, in camera space.
        b: The second.
        c: The third.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The camera's four side planes, in camera space, and the
            clipping planes that each cut.
        any_of: The clipping planes of which a kept point needs one. Any
            at all send the triangle through the clipper.

    Returns:
        True if `clip_depth` would return the three corners as they are.
    """
    if len(any_of) > 0:
        return False
    if not within_depth(a.position.z, near, far):
        return False
    if not within_depth(b.position.z, near, far):
        return False
    if not within_depth(c.position.z, near, far):
        return False
    if not within_sides(a.position, sides):
        return False
    if not within_sides(b.position, sides):
        return False
    return within_sides(c.position, sides)


struct _Slim(Movable, Sized):
    """A frame's triangles as they are prepared: each corner slim, and each
    draw's material once per facing, as `Corner` and `Surface`.

    The emitters append whole corners, as they always have; each is split
    here, so the frame's list holds a quarter of what it did. A draw calls
    `new_surface` first. Front and back faces each share one surface, so
    their normal and bump map scales keep the correct sign.
    """

    var corners: List[Corner]
    var surfaces: List[Surface]
    # One surface for each facing in the current draw.
    var front_surface: Int
    var back_surface: Int
    var turned: Bool

    def __init__(out self):
        """Hold nothing yet."""
        self.corners = List[Corner]()
        self.surfaces = List[Surface]()
        self.front_surface = -1
        self.back_surface = -1
        self.turned = False

    def __len__(self) -> Int:
        """Return how many corners there are.

        Returns:
            The count, three a triangle.
        """
        return len(self.corners)

    def reserve(mut self, count: Int):
        """Make room for `count` corners in all.

        Args:
            count: The corners the list should hold without growing.
        """
        self.corners.reserve(count)

    def capacity(self) -> Int:
        """Return how many corners fit before the list grows.

        Returns:
            The capacity of the corner list.
        """
        return self.corners.capacity()

    def new_surface(mut self):
        """Start a draw: its first corner starts a surface of its own."""
        self.front_surface = -1
        self.back_surface = -1
        self.turned = False

    def append(mut self, vertex: RasterVertex):
        """Add a corner, and its surface when it is the facing's first.

        Args:
            vertex: The whole corner.
        """
        var surface = self.back_surface if self.turned else self.front_surface
        if surface < 0:
            surface = len(self.surfaces)
            self.surfaces.append(surface_of(vertex))
            if self.turned:
                self.back_surface = surface
            else:
                self.front_surface = surface
        self.corners.append(corner_of(vertex, surface))

    def take_corners(mut self) -> List[Corner]:
        """Give up the corners, for a `Frame`, and hold none.

        Returns:
            The corners.
        """
        var taken = self.corners^
        self.corners = List[Corner]()
        return taken^

    def take_surfaces(mut self) -> List[Surface]:
        """Give up the surfaces, for a `Frame`, and hold none.

        Returns:
            The surfaces the corners named.
        """
        var taken = self.surfaces^
        self.surfaces = List[Surface]()
        return taken^

    def whole(self) -> List[RasterVertex]:
        """Return every corner whole again, in order.

        Returns:
            The whole corners.
        """
        var out = List[RasterVertex](capacity=len(self.corners))
        for index in range(len(self.corners)):
            ref corner = self.corners[index]
            out.append(joined(corner, self.surfaces[corner.surface]))
        return out^


@fieldwise_init
struct _Paint(ImplicitlyCopyable):
    """What every corner of one filled draw carries besides its own
    varyings, and the two rules that decide whether a piece of it is drawn.

    One of these per draw, so that a piece is emitted by one method
    whether it came straight from the mesh or out of the clipper: the
    same projection, the same material metadata and the same facing test,
    written once rather than once per path.
    """

    var to_screen: Matrix4
    var map: TextureId
    var blending: Blending
    var kind: MaterialKind
    var glow_map: TextureId
    var mask: TextureId
    var alpha_test: Float32
    var sheen: FloatColor
    var shininess: Float32
    var tones: TextureId
    var ball: TextureId
    # Whether the draw's world transform reflects it; see `_faces_away`.
    var mirrored: Bool
    var side: Side
    # The environment the draw reflects, already resolved from
    # `SCENE_ENVIRONMENT`, and how; see `_resolved_env`.
    var env: CubeTextureId
    var reflectivity: Float32
    var combine: Combine
    # The physical terms and the normal or bump map, with the maps the
    # shading mode would not open already erased.
    var physics: _Physics
    # Whether the lights' shadows fall on the draw.
    var receives_shadow: Bool
    # The draw's depth, color and stencil state, and how far its
    # triangles are pushed back; see `_draw_state` and `emit`.
    var state: RasterState
    var offset: PolygonOffset
    # The fog switch, the depth packing and the distance range.
    var shown: _Shown
    # The frames the environment and the normal map are read in; see
    # `_frames_of`.
    var frames: TextureFrames
    # Which of the frame's lightings lights the draw; see
    # `RasterVertex.lights`.
    var lights: Int

    def raster(self, vertex: ClipVertex) -> RasterVertex:
        """Project one clipped corner into the rasterizer's input."""
        var corner = _to_raster(
            vertex,
            self.to_screen,
            self.map,
            self.blending,
            self.kind,
            self.glow_map,
            self.mask,
            self.alpha_test,
            self.sheen,
            self.shininess,
            self.tones,
            self.ball,
            env_map=self.env,
            reflectivity=self.reflectivity,
            combine=self.combine,
            physics=self.physics,
            receives_shadow=self.receives_shadow,
            state=self.state,
            shown=self.shown,
        )
        corner.frames = self.frames
        corner.lights = self.lights
        corner.custom = vertex.custom
        corner.gouraud_direct = vertex.gouraud_direct
        corner.gouraud_indirect = vertex.gouraud_indirect
        corner.gouraud_back_direct = vertex.gouraud_back_direct
        corner.gouraud_back_indirect = vertex.gouraud_back_indirect
        ref scattering = self.physics.scattering
        if scattering.is_on():
            corner.scatter_map = scattering.map
            corner.scatter_color = FloatColor(srgb=scattering.color)
            corner.scatter_distortion = scattering.distortion
            corner.scatter_ambient = scattering.ambient
            corner.scatter_attenuation = scattering.attenuation
            corner.scatter_power = scattering.power
            corner.scatter_scale = scattering.scale
        corner.current = vertex.current
        corner.previous = vertex.previous
        return corner^

    def emit_in_uv_space(
        self,
        mut corners: _Slim,
        a: ClipVertex,
        b: ClipVertex,
        c: ClipVertex,
        viewport: Rect,
        height: Int,
    ):
        """Append one triangle placed by its second texture coordinates
        across the viewport, `u1` from its left edge and `v1` up from its
        bottom one, at the middle depth with no perspective: three.js's
        `gl_Position = vec4((uv1 - 0.5) * 2.0, 1.0, 1.0)`. It is lit as it
        stands in the world, from both sides, unfogged.

        Args:
            corners: The frame's raster vertices, appended to.
            a: The first corner, in camera space.
            b: The second.
            c: The third.
            viewport: Where the texture's square is on the target.
            height: The target's height, which the viewport's rows count
                down from.
        """
        var left = Float32(viewport.x)
        var top = Float32(viewport.top(height))
        var wide = Float32(viewport.width)
        var tall = Float32(viewport.height)
        # Three corners, so the loop runs.
        for vertex in [a, b, c]:  # pragma: no branch
            var corner = self.raster(vertex)
            corner.x = left + vertex.u1 * wide
            corner.y = top + (1 - vertex.v1) * tall
            corner.z = 0
            corner.inv_w = 1
            corner.fog = False
            corners.append(corner)

    def emit(
        self,
        mut corners: _Slim,
        a: ClipVertex,
        b: ClipVertex,
        c: ClipVertex,
    ):
        """Project one triangle and append it, unless its facing rejects it.

        Which way the triangle ends up facing decides two things at once:
        whether it survives, and, for a two-sided material, which side of
        it is being lit. Read from the screen winding, so it is known only
        now -- which is why the normal traveled this far unflipped.

        Args:
            corners: The frame's raster vertices, appended to.
            a: The first corner, in camera space.
            b: The second.
            c: The third.
        """
        self.emit_raster(
            corners, self.raster(a), self.raster(b), self.raster(c)
        )

    def emit_raster(
        self,
        mut corners: _Slim,
        var one: RasterVertex,
        var two: RasterVertex,
        var three: RasterVertex,
    ):
        """Append one projected triangle, unless its facing rejects it.

        `emit` without the projection. A caller that shares a corner
        between triangles, as a strand ribbon and its round caps do, can
        project each corner once with `raster` and pass the result here.
        The result equals `emit` on the unprojected corners.

        Args:
            corners: The frame's raster vertices, appended to.
            one: The first corner, from `raster`.
            two: The second.
            three: The third.
        """
        # The polygon offset, added to the screen depths here, where the
        # triangle is first on the screen, so both backends receive the
        # moved depths and agree without a rule of their own. `NO_OFFSET`
        # adds zero. Measured on the piece the clipper kept, whose depth
        # slope is the whole triangle's.
        var shift = self.offset.shift(
            Vector3(one.x, one.y, one.z),
            Vector3(two.x, two.y, two.z),
            Vector3(three.x, three.y, three.z),
        )
        one.z += shift
        two.z += shift
        three.z += shift
        var away = _faces_away(one, two, three, self.mirrored)
        if self.side == FRONT_SIDE and away:
            return
        if self.side == BACK_SIDE and not away:
            return
        corners.turned = self.side == BACK_SIDE or (
            self.side == DOUBLE_SIDE and away
        )
        if corners.turned:
            # A two-sided surface seen from behind is lit on the side being
            # looked at: three.js's `normal *= faceDirection`, which its
            # shader applies under `DOUBLE_SIDED`. A `BACK_SIDE` surface is
            # lit on its back whichever way it is seen: three.js's
            # `flipSided` is `side === BackSide`, and `defaultnormal_vertex`
            # negates the normal under `FLIP_SIDED`, beside turning the
            # winding round. So the inside of a box lit from a lamp inside
            # it is lit, as three.js draws it. This once kept the authored
            # normal for `BACK_SIDE` on the belief that only the winding
            # turned, which was wrong.
            #
            # One flip replaces the two colors this used to carry from the
            # vertex stage, because the far side's normal is just this one
            # negated -- which the lighting was not, once it had been
            # applied.
            one = _turned_around(one)
            two = _turned_around(two)
            three = _turned_around(three)
        # What a node program's facing reads, from the first corner.
        one.seen_from_behind = away
        one.flip_sided = self.side == BACK_SIDE
        corners.append(one)
        corners.append(two)
        corners.append(three)


def _draw_state(
    material: Material,
    casters_only: Bool,
    dithers: Bool,
    hashes: Bool,
    premultiplies: Bool,
) raises -> RasterState:
    """Return the depth, color and stencil state a draw is made under.

    The material's, checked, for a frame. A light's view of the casters
    draws depth alone, under three.js's own depth material rather than the
    mesh's, so it takes the default state: a mask pass that writes no
    color still casts its shadow.

    A fragment flag stays on only where three.js's shader for the
    primitive reads it: `dithering` in the `dithering_fragment` chunk,
    `alphaHash` in `alphahash_fragment`, `premultipliedAlpha` in
    `premultiplied_alpha_fragment`. `toneMapped` and `alphaToCoverage`
    are kept as the material sets them.

    Args:
        material: The draw's material.
        casters_only: Whether this is a light's view of the casters.
        dithers: Whether the primitive's shader dithers.
        hashes: Whether it has an alpha hash.
        premultiplies: Whether it premultiplies its alpha.

    Returns:
        The state.

    Raises:
        Error: If the material's state is refused by
            `RasterState.check`, whichever view this is.
    """
    var state = material.raster_state()
    if casters_only:
        return RasterState()
    state.dithering = state.dithering and dithers
    state.alpha_hash = state.alpha_hash and hashes
    state.premultiplied_alpha = state.premultiplied_alpha and premultiplies
    return state


def _drawn_material(
    override: Optional[MaterialId], own: Material, id: MaterialId
) -> MaterialId:
    """Return the material an object is drawn with: the scene's
    `override_material` when it has one and the object's own material
    allows it, three.js's `renderObjects`, and the object's own otherwise.

    Args:
        override: The material that takes the place of every object's,
            `Renderer.drawn_override`, or none.
        own: The object's own material.
        id: Its id.

    Returns:
        The id to draw with.
    """
    var overridden = Bool(override)
    if overridden and own.allow_override:
        return override.value()
    return id


def _draw_offset(
    material: Material, casters_only: Bool
) raises -> PolygonOffset:
    """Return how far a draw's filled triangles are pushed back.

    The material's for a frame, and none for a light's view of the
    casters, for the reason `_draw_state` gives.

    Args:
        material: The draw's material.
        casters_only: Whether this is a light's view of the casters.

    Returns:
        The offset.

    Raises:
        Error: If the material's offset is refused by
            `Material.depth_offset`, whichever view this is.
    """
    var offset = material.depth_offset()
    if casters_only:
        return NO_OFFSET
    return offset


def require_named_map(value: Int, count: Int, name: String) raises:
    """Refuse a map id past the textures the store holds.

    Nothing. The call returns when the id is inside the store.

    Args:
        value: The id's integer.
        count: How many textures the store has.
        name: What to call the map in the error.

    Raises:
        Error: If the id is past the store.
    """
    if value >= count:
        raise Error(name + " is named that is not there")


def _checked_data_map(
    assets: Assets, map: TextureId, name: String
) raises -> TextureId:
    """Return `map` once it is known to be in the store and stored as data,
    or `NO_TEXTURE` as it was.

    Args:
        assets: Where the textures live.
        map: The id the material names, or `NO_TEXTURE`.
        name: What to call the map in an error: "A normal map", say.

    Returns:
        `map`, unchanged.

    Raises:
        Error: If the id names nothing in the store, or the texture is not
            `LINEAR` or does not ignore its alpha; see `check_data_map`.
    """
    if map == NO_TEXTURE:
        return map
    require_named_map(map.value, assets.textures.count(), name)
    check_data_map(assets.textures.get(map), name)
    return map


def _stored_map(assets: Assets, map: TextureId, name: String) raises:
    """Refuse a map id that names nothing in the store.

    Args:
        assets: Where the textures live.
        map: The id the material names, not `NO_TEXTURE`.
        name: What to call the map in an error: "A sheen color map", say.

    Raises:
        Error: If the id names nothing in the store.
    """
    require_named_map(map.value, assets.textures.count(), name)


def _layer_factors(
    assets: Assets, material: Material, shading: ShadeMode
) raises -> LayerFactors:
    """Return what a draw's corners carry for its sheen, its thin film and
    its stretched lobe: `LayerFactors` from the material's numbers.

    The sheen color is decoded to linear light and multiplied by the
    sheen, as three.js's `refreshUniformsPhysical` fills `sheenColor`. The
    film's range is read in nanometers. The anisotropy becomes a vector
    of its strength along its rotation, three.js's `anisotropyVector`.
    The specular color is decoded to linear light, for a fragment that
    works its reflectance out again under a specular map, and the
    clearcoat normal scale is carried as it is. Each map is checked the way `check_triangle_maps` checks it, whatever
    the shading mode, and erased unless the mode opens textures. A kind
    that is not `PHYSICAL` carries none of this, and `Material` has
    refused any on one.

    Args:
        assets: Where the textures live.
        material: The draw's material.
        shading: The shading mode, which decides whether maps are opened.

    Returns:
        The factors.

    Raises:
        Error: If a map id names nothing in the store, or a map is not
            stored the way it is read; see `check_color_map`,
            `check_alpha_data_map` and `check_data_map`.
    """
    var factors = LayerFactors()
    if material.kind != PHYSICAL:
        return factors
    var tint = FloatColor(srgb=material.sheen_color)
    factors.sheen_color = Vector3(tint.r, tint.g, tint.b) * material.sheen
    factors.sheen_roughness = material.sheen_roughness
    factors.iridescence = material.iridescence
    factors.iridescence_ior = material.iridescence_ior
    factors.thickness_minimum = material.iridescence_thickness_minimum.to(
        NANOMETER
    )
    factors.thickness_maximum = material.iridescence_thickness_maximum.to(
        NANOMETER
    )
    var turn = material.anisotropy_rotation.to(RADIAN)
    factors.anisotropy = Vector2(
        material.anisotropy * cos(turn), material.anisotropy * sin(turn)
    )
    if material.sheen_color_map != NO_TEXTURE:
        _stored_map(assets, material.sheen_color_map, "A sheen color map")
        check_color_map(
            assets.textures.get(material.sheen_color_map), "A sheen color map"
        )
    if material.sheen_roughness_map != NO_TEXTURE:
        _stored_map(
            assets, material.sheen_roughness_map, "A sheen roughness map"
        )
        check_alpha_data_map(
            assets.textures.get(material.sheen_roughness_map),
            "A sheen roughness map",
        )
    factors.iridescence_map = _checked_data_map(
        assets, material.iridescence_map, "An iridescence map"
    )
    factors.thickness_map = _checked_data_map(
        assets,
        material.iridescence_thickness_map,
        "An iridescence thickness map",
    )
    factors.anisotropy_map = _checked_data_map(
        assets, material.anisotropy_map, "An anisotropy map"
    )
    # The specular and coat maps, checked as `check_triangle_maps` checks
    # them: the intensity is read from the alpha, the color map holds
    # color, and the coat's three hold data.
    var reflected = FloatColor(srgb=material.specular_color)
    factors.specular_color = Vector3(reflected.r, reflected.g, reflected.b)
    factors.clearcoat_normal_scale = material.clearcoat_normal_scale
    if material.specular_intensity_map != NO_TEXTURE:
        _stored_map(
            assets, material.specular_intensity_map, "A specular intensity map"
        )
        check_alpha_data_map(
            assets.textures.get(material.specular_intensity_map),
            "A specular intensity map",
        )
    if material.specular_color_map != NO_TEXTURE:
        _stored_map(assets, material.specular_color_map, "A specular color map")
        check_color_map(
            assets.textures.get(material.specular_color_map),
            "A specular color map",
        )
    factors.clearcoat_map = _checked_data_map(
        assets, material.clearcoat_map, "A clearcoat map"
    )
    factors.clearcoat_roughness_map = _checked_data_map(
        assets, material.clearcoat_roughness_map, "A clearcoat roughness map"
    )
    factors.clearcoat_normal_map = _checked_data_map(
        assets, material.clearcoat_normal_map, "A clearcoat normal map"
    )
    if shading == SHADE_TEXTURE:
        factors.sheen_color_map = material.sheen_color_map
        factors.sheen_roughness_map = material.sheen_roughness_map
        factors.specular_intensity_map = material.specular_intensity_map
        factors.specular_color_map = material.specular_color_map
    else:
        factors.iridescence_map = NO_TEXTURE
        factors.thickness_map = NO_TEXTURE
        factors.anisotropy_map = NO_TEXTURE
        factors.clearcoat_map = NO_TEXTURE
        factors.clearcoat_roughness_map = NO_TEXTURE
        factors.clearcoat_normal_map = NO_TEXTURE
    return factors


def _checked_scattering(
    assets: Assets, material: Material
) raises -> Scattering:
    """Return a material's light through, once its thickness map is known
    to be in the store and stored as data.

    Raises:
        Error: If the thickness map names nothing, or is not data.
    """
    _ = _checked_data_map(assets, material.scattering.map, "A thickness map")
    return material.scattering


def _checked_nodes(
    assets: Assets, nodes: NodeProgramId
) raises -> NodeProgramId:
    """Return a node material's program once it is known to be in the
    store, with every texture it reads, or `NO_NODES` as it was.

    Asked whatever the shading mode, as a map is: a program that names
    nothing is a wrong asset, not a wrong frame.

    Args:
        assets: Where the programs and the textures live.
        nodes: The id the material names, or `NO_NODES`.

    Returns:
        `nodes`, unchanged.

    Raises:
        Error: If the id names nothing in the store, or the program reads
            a texture that is not in the store.
    """
    if nodes == NO_NODES:
        return nodes
    if nodes.value >= assets.programs.count():
        raise Error("A material names a node program that is not there")
    ref program = assets.programs.get(nodes)
    for index in range(len(program.textures)):
        if program.textures[index].value >= assets.textures.count():
            raise Error("A node program reads a texture that is not there")
    for index in range(len(program.cubes)):
        if program.cubes[index].value >= assets.cube_textures.count():
            raise Error("A node program reads a cube that is not there")
    for index in range(len(program.volumes)):
        if program.volumes[index].value >= assets.data_3d_textures.count():
            raise Error("A node program reads a 3D texture that is not there")
    for index in range(len(program.arrays)):
        if program.arrays[index].value >= assets.data_array_textures.count():
            raise Error(
                "A node program reads an array texture that is not there"
            )
    return nodes


def _moves(assets: Assets, material: Material) raises -> Bool:
    """Return True if a material's node program moves its vertices: it has
    a position node. `_checked_nodes` has found the program.

    Raises:
        Error: Never for a program `_checked_nodes` has passed.
    """
    if material.nodes == NO_NODES:
        return False
    return assets.programs.get(material.nodes).has(POSITION_NODE)


def _refuse_nodes(material: Material, what: String) raises:
    """Refuse a node material on a primitive that runs no graph.

    Raises:
        Error: If the material names a node program.
    """
    if material.nodes != NO_NODES:
        raise Error(
            what + " runs no node graph: it has no surface for one to shade"
        )


def _checked_light_map(assets: Assets, map: TextureId) raises -> TextureId:
    """Return a light map once it is known to be in the store and to
    ignore its alpha, or `NO_TEXTURE` as it was.

    Args:
        assets: Where the textures live.
        map: The id the material names, or `NO_TEXTURE`.

    Returns:
        `map`, unchanged.

    Raises:
        Error: If the id names nothing in the store, or the texture reads
            its alpha as coverage; see `check_light_map`.
    """
    if map == NO_TEXTURE:
        return map
    if map.value >= assets.textures.count():
        raise Error("A light map is named that is not there")
    check_light_map(assets.textures.get(map))
    return map


def require_material_texture(map: TextureId, count: Int) raises:
    """Refuse a material texture the store does not have.

    Nothing. The call returns when the id is absent or in the store.

    Args:
        map: The id the material names.
        count: How many textures the store has.

    Raises:
        Error: If the id names a texture that is not there.
    """
    if map != NO_TEXTURE and map.value >= count:
        raise Error("A material names a texture that is not there")


def require_material_alpha(map: TextureId, count: Int) raises:
    """Refuse a material alpha map the store does not have.

    Nothing. The call returns when the id is absent or in the store.

    Args:
        map: The id the material names.
        count: How many textures the store has.

    Raises:
        Error: If the id names an alpha map that is not there.
    """
    if map != NO_TEXTURE and map.value >= count:
        raise Error("A material names an alpha map that is not there")


def require_renderer_workers(workers: Int) raises:
    """Refuse a renderer with no worker.

    Nothing. The call returns when there is one worker or more.

    Args:
        workers: How many threads rasterize a frame.

    Raises:
        Error: If `workers` is below one.
    """
    require_at_least_one(workers, "A renderer needs at least one worker")


def _checked_maps(
    assets: Assets, material: Material, shading: ShadeMode
) raises -> Tuple[TextureId, TextureId]:
    """Return the map and the alpha map a point or a sprite samples, or
    `NO_TEXTURE` for each the shading mode would not open.

    The two checks the mesh loop of `_prepared` makes of the same two
    maps, for the same reasons: an id naming nothing is detectable only
    here, where the store is in reach, and an alpha map must be stored as
    data whatever the mode.

    Args:
        assets: Where the textures live.
        material: The material, for which maps it names.
        shading: The renderer's shading mode. Only `SHADE_TEXTURE` opens
            either map.

    Returns:
        The map, then the alpha map.

    Raises:
        Error: If either id names a texture that is not there, or the
            alpha map is not stored as data -- see `check_alpha_map`.
    """
    var map = material.map
    require_material_texture(map, assets.textures.count())
    if shading != SHADE_TEXTURE:
        map = NO_TEXTURE
    var mask = material.alpha_map
    require_material_alpha(mask, assets.textures.count())
    if mask != NO_TEXTURE:
        check_alpha_map(assets.textures.get(mask))
    if shading != SHADE_TEXTURE:
        mask = NO_TEXTURE
    return (map, mask)


def _resolved_env(
    scene: Scene, assets: Assets, material: Material, shading: ShadeMode
) raises -> CubeTextureId:
    """Return the cube texture a material reflects, or `NO_CUBE_TEXTURE`.

    `SCENE_ENVIRONMENT` becomes whatever the scene's `environment` names,
    which can be nothing: three.js's `material.envMap || scene.environment`.
    The id is then checked against the store, here, where the store is in
    reach, as the material's maps are checked in `_prepared`. Only
    `SHADE_TEXTURE` reflects: a reflection is a texture, and the other two
    modes ignore every texture. The store is asked whatever the mode, as
    the maps are: a wrong asset, not a wrong frame.

    Args:
        scene: The scene, for its environment.
        assets: Where the cube textures live.
        material: The material, for what it names.
        shading: The renderer's shading mode.

    Returns:
        The id, or `NO_CUBE_TEXTURE`.

    Raises:
        Error: If the id names a cube texture that is not there.
    """
    var env = material.env_map
    if env == SCENE_ENVIRONMENT:
        env = scene.environment
    if env != NO_CUBE_TEXTURE and (
        env.value < 0 or env.value >= assets.cube_textures.count()
    ):
        raise Error("A material names a cube texture that is not there")
    if shading != SHADE_TEXTURE:
        env = NO_CUBE_TEXTURE
    return env


def _env_intensity(scene: Scene, material: Material) -> Float32:
    """Return what a physical surface's environment is multiplied by: the
    scene's `environment_intensity` when the surface reflects the scene's
    environment, as three.js's renderer sets `envMapIntensity` from
    `scene.environmentIntensity`, and its own `env_map_intensity`
    otherwise."""
    if material.env_map == SCENE_ENVIRONMENT:
        return scene.environment_intensity
    return material.env_map_intensity


def _negated(basis: Basis3) -> Basis3:
    """Return a 3x3 matrix times minus one."""
    return Basis3(
        -basis.e0,
        -basis.e1,
        -basis.e2,
        -basis.e3,
        -basis.e4,
        -basis.e5,
        -basis.e6,
        -basis.e7,
        -basis.e8,
    )


def _frames_of(
    scene: Scene, material: Material, world: Matrix4
) raises -> TextureFrames:
    """Return the frames a draw's environment and normal map are read in.

    The env map's rotation, or the scene's `environment_rotation` when the
    surface reflects the scene's environment, as three.js's renderer picks
    `envMapRotation`; the material's refraction ratio and normal map type;
    and, for an object-space normal map, the mesh's normal matrix into the
    world, three.js's `normalMatrix` without the view.

    Args:
        scene: The scene, for its environment's rotation.
        material: The draw's material.
        world: The draw's world matrix.

    Returns:
        The frames.

    Raises:
        Error: If `Scene.validate_environment` refuses the scene's
            settings, the rotation is refused by `env_rotation`, or an
            object-space normal map's mesh has a world matrix that
            flattens an axis.
    """
    scene.validate_environment()
    var frames = TextureFrames()
    var rotation = material.env_map_rotation
    if material.env_map == SCENE_ENVIRONMENT:
        rotation = scene.environment_rotation
    frames.env_rotation = env_rotation(rotation)
    frames.refraction_ratio = material.refraction_ratio
    frames.normal_map_type = material.normal_map_type
    if material.normal_map_type == OBJECT_SPACE_NORMAL_MAP:
        ref e = Matrix3.normal_matrix(world).elements
        frames.object_normal = Basis3(
            e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]
        )
    return frames^


def _emit_sprite(
    mut corners: _Slim,
    assets: Assets,
    sprite: Sprite,
    draw: _Draw,
    view: Matrix4,
    to_screen: Matrix4,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    perspective: Bool,
    shading: ShadeMode,
    any_of: List[Plane] = List[Plane](),
    casters_only: Bool = False,
) raises:
    """Build a sprite's two triangles in camera space and append them.

    three.js's `sprite_vert`: the node's world origin is carried into
    camera space, the square is scaled by the lengths of the world
    matrix's x and y columns, turned by the material's rotation, and laid
    flat to the image there, so the node's own turn does nothing to it.
    With the attenuation off the scale is multiplied by the depth the
    perspective divide is about to divide it by, so the square keeps its
    size on the image. See `objects.sprite`.

    The triangles then go where every triangle goes: through the clipper
    and `_Paint.emit`, two-sided, so a sprite is drawn by the triangle
    rule on either backend and needs no rule of its own.

    Args:
        corners: The frame's raster vertices, appended to.
        assets: Where the material and its maps live.
        sprite: The sprite, for its center.
        draw: Its draw, for its material and world matrix.
        view: The world-to-camera transform.
        to_screen: The camera-to-pixels transform.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The camera's four side planes, in camera space, and the
            clipping planes that each cut.
        perspective: Whether the camera's rays converge.
        shading: The renderer's shading mode, for which maps to carry.
        any_of: The clipping planes of which a kept point needs one.
        casters_only: Whether this is a light's view of the casters, which
            takes no depth, color or stencil state; see `_draw_state`.

    Raises:
        Error: If the material is not `BASIC` or is a wireframe, names a
            map or an alpha map that is not there, names an alpha map
            that is not stored as data, reflects an environment, names an
            ao map or a light map, or holds a depth, color, stencil or
            offset state that is refused.
    """
    var material = assets.materials.get(draw.material)
    # Refused for the reason a line refuses a lit kind: a sprite is unlit,
    # as three.js's `SpriteMaterial` is, and there is no light to reach it
    # with in any case -- it has no surface of its own to turn.
    if material.kind != BASIC:
        raise Error(
            "A sprite material must be BASIC: a sprite is a picture facing"
            " the camera, and no light reaches it"
        )
    # A node material shades the square as it shades a mesh, three.js's
    # `SpriteNodeMaterial`; a position node moves a mesh's own vertices,
    # which a sprite has none of.
    if _moves(assets, material):
        raise Error(
            "A sprite's node material has no position node: a sprite has no"
            " vertices of its own to move"
        )
    var physics = _Physics()
    physics.nodes = _checked_nodes(assets, material.nodes)
    if material.wireframe:
        raise Error(
            "A sprite cannot be a wireframe: it is a picture, and its"
            " edges say nothing"
        )
    # A sprite has no surface of its own to turn, so nothing to reflect
    # from: three.js's `SpriteMaterial` has no `envMap`.
    if material.has_env_map():
        raise Error(
            "A sprite cannot reflect an environment: it is a picture facing"
            " the camera, with no surface to reflect from"
        )
    # Nor any indirect light for a baked map to act on: three.js's
    # `SpriteMaterial` has no `aoMap` and no `lightMap`.
    if material.has_baked_map():
        raise Error(
            "A sprite has no ao map or light map: it is a picture, with no"
            " indirect light for either to reach"
        )
    var maps = _checked_maps(assets, material, shading)
    _check_map_channels(assets, material)
    ref world = draw.world
    var origin = Vector3(
        world.elements[12], world.elements[13], world.elements[14]
    )
    var center = view.transform_point(origin)
    var scale_x, scale_y, turned_x, turned_y = sprite_span(
        world,
        center,
        material.size_attenuation,
        perspective,
        material.rotation,
    )
    var base = _with_opacity(FloatColor(srgb=material.color), material.opacity)
    # The unit square's corners and their coordinates, counterclockwise
    # from the bottom left: three.js's sprite geometry.
    var xs: List[Float32] = [-0.5, 0.5, 0.5, -0.5]
    var ys: List[Float32] = [-0.5, -0.5, 0.5, 0.5]
    var quad = List[ClipVertex]()
    for corner in range(4):  # pragma: no branch
        # Raw, on both pairs: each map places them for itself, and a
        # sprite has no `uv1`, so the second pair falls back to the first
        # as a mesh's does.
        var raw = Vector2(xs[corner] + 0.5, ys[corner] + 0.5)
        quad.append(
            ClipVertex(
                sprite_place(
                    center,
                    sprite.center,
                    xs[corner],
                    ys[corner],
                    scale_x,
                    scale_y,
                    turned_x,
                    turned_y,
                ),
                base,
                Vector3(0, 0, 1),
                raw.x,
                raw.y,
                origin,
                u1=raw.x,
                v1=raw.y,
            )
        )
    # Two-sided and unmirrored: a negative scale turns the square inside
    # out, and it is drawn either way, as three.js draws it.
    var paint = _Paint(
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
        False,
        DOUBLE_SIDE,
        NO_CUBE_TEXTURE,
        1,
        MULTIPLY_OPERATION,
        physics,
        False,
        # three.js's `sprite` shader hashes its alpha, and neither dithers
        # nor premultiplies.
        _draw_state(material, casters_only, False, True, False),
        _draw_offset(material, casters_only),
        _shown_of(material),
        TextureFrames(),
        0,
    )
    var thirds: List[Int] = [2, 3]
    for half in range(2):  # pragma: no branch
        _emit_clipped(
            paint,
            corners,
            quad[0],
            quad[thirds[half] - 1],
            quad[thirds[half]],
            near,
            far,
            sides,
            any_of,
        )


def _emit_clipped(
    paint: _Paint,
    mut corners: _Slim,
    a: ClipVertex,
    b: ClipVertex,
    c: ClipVertex,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
) raises:
    """Clip one camera-space triangle and append what is left of it.

    Args:
        paint: What every corner of the draw carries.
        corners: The frame's raster vertices, appended to.
        a: The first corner, in camera space.
        b: The second.
        c: The third.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The planes that each cut.
        any_of: The clipping planes of which a kept point needs one.

    Raises:
        Error: If the clipper does.
    """
    if _whole_in_view(a, b, c, near, far, sides, any_of):
        paint.emit(corners, a, b, c)
        return
    var pieces = clip_depth(a, b, c, near, far, sides, any_of)
    for piece in range(len(pieces) // 3):
        paint.emit(
            corners,
            pieces[piece * 3],
            pieces[piece * 3 + 1],
            pieces[piece * 3 + 2],
        )


struct _Placed(Movable):
    """One corner in camera space and the same corner projected by a
    draw's `_Paint.raster`, so that triangles sharing it project it once.
    """

    var clip: ClipVertex
    var screen: RasterVertex

    def __init__(out self, paint: _Paint, var clip: ClipVertex):
        """Project `clip` with `paint` and keep both.

        Args:
            paint: What every corner of the draw carries.
            clip: The corner, in camera space.
        """
        self.screen = paint.raster(clip)
        self.clip = clip^


def _same_place(a: RasterVertex, b: RasterVertex) -> Bool:
    """Return True if two projected corners are at one place on the image.

    Args:
        a: One corner, from `_Paint.raster`.
        b: Another.

    Returns:
        True if their pixel coordinates are equal.
    """
    return a.x == b.x and a.y == b.y


def _emit_placed(
    paint: _Paint,
    mut corners: _Slim,
    a: _Placed,
    b: _Placed,
    c: _Placed,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
) raises:
    """Clip one triangle of projected corners and append what is left.

    `_emit_clipped` with the projection already done: a triangle that
    needs no cut reuses its corners' projections, and one that does is
    cut and projected as `_emit_clipped` does.

    A triangle that needs no cut and has two corners at the same place on
    the image is left out. Its area is zero, so neither rasterizer
    draws a sample of it: `_Coverage` and the device kernel both skip a
    triangle of zero area. A one-pixel strand makes many of these: its
    inner feather radius is zero, so its middle strip and two of the
    three triangles in each step of its caps collapse onto the center
    line. The image and the depths are the same; the frame holds fewer
    corners.

    Args:
        paint: What every corner of the draw carries.
        corners: The frame's raster vertices, appended to.
        a: The first corner.
        b: The second.
        c: The third.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The planes that each cut.
        any_of: The clipping planes of which a kept point needs one.

    Raises:
        Error: If the clipper does.
    """
    if _whole_in_view(a.clip, b.clip, c.clip, near, far, sides, any_of):
        if (
            _same_place(a.screen, b.screen)
            or _same_place(b.screen, c.screen)
            or _same_place(c.screen, a.screen)
        ):
            return
        # A polygon offset moves the projected depth, which `emit` does
        # in the same arithmetic as the projection. Such a draw projects
        # the triangle again, so its depths stay the same to the last bit.
        if paint.offset.factor == 0 and paint.offset.units == 0:
            paint.emit_raster(corners, a.screen, b.screen, c.screen)
            return
    _emit_clipped(
        paint, corners, a.clip, b.clip, c.clip, near, far, sides, any_of
    )


def _between(a: ClipVertex, b: ClipVertex, t: Float32) -> ClipVertex:
    """Return the point a fraction `t` of the way along a wide segment.

    Its position, its world position, its color and its distance along
    the line, each mixed in camera space, where the segment is straight.
    That is the perspective-correct mix three.js's varyings get.
    """
    return ClipVertex(
        mix_delta3(a.position, b.position, t),
        a.color.mix(b.color, t),
        Vector3(0, 0, 1),
        0,
        0,
        mix_delta3(a.world, b.world, t),
        line_distance=mix_delta(a.line_distance, b.line_distance, t),
    )


struct _Ribbon(ImplicitlyCopyable):
    """Where the corners of one wide segment go, around its two ends.

    three.js's `LineMaterial` vertex shader, per segment. With the width
    in pixels, a corner is its end moved on the image, across and along
    the segment as the image shows it, then carried back into camera space
    at its end's own depth: three.js moves the clip-space corner by an
    offset times `w`, which is the same move. With the width in the world,
    a corner is its end moved in camera space, across the segment and
    square to the direction of its middle, three.js's `worldUp`. The caps
    lie square to that direction too; three.js traces a capsule per
    fragment instead, whose outline this matches.
    """

    var world_units: Bool
    # Half the width: pixels, already times the render scale, or meters.
    var half: Float32
    # Unit directions along and across the segment, on the image and in
    # camera space. Only the pair the width's units ask for is read.
    var along_screen: Vector2
    var across_screen: Vector2
    var along: Vector3
    var across: Vector3
    var to_screen: Matrix4
    var from_screen: Matrix4
    var to_world: Matrix4

    def __init__(
        out self,
        a: ClipVertex,
        b: ClipVertex,
        world_units: Bool,
        half: Float32,
        to_screen: Matrix4,
        from_screen: Matrix4,
        to_world: Matrix4,
    ):
        """Work out the directions for the segment from `a` to `b`.

        A segment that has no length, on the image or in the world, is
        given one along x, so its two caps meet as a round dot. three.js
        normalizes a zero vector there, which GLSL leaves undefined. A
        segment in the world that points at the camera's eye is given a
        direction across it that is square to y, and its caps then make
        one disc facing the camera.

        Args:
            a: The start, in camera space, already cut to the view depth.
            b: The end.
            world_units: Whether `half` is in meters rather than pixels.
            half: Half the width.
            to_screen: The camera-to-pixels transform.
            from_screen: Its inverse.
            to_world: The camera-to-world transform.
        """
        self.world_units = world_units
        self.half = half
        self.to_screen = to_screen
        self.from_screen = from_screen
        self.to_world = to_world
        var start = to_screen.transform_point(a.position)
        var end = to_screen.transform_point(b.position)
        var flat = Vector2(end.x - start.x, end.y - start.y)
        if flat.length() == 0:
            flat = Vector2(1, 0)
        flat.normalize()
        self.along_screen = flat
        self.across_screen = Vector2(-flat.y, flat.x)
        var along = b.position - a.position
        if along.length() == 0:
            along = Vector3(1, 0, 0)
        along.normalize()
        # three.js's `tmpFwd`: toward the segment's middle from the eye.
        var forward = (a.position + b.position) * 0.5
        forward.normalize()
        var across = along
        across.cross(forward)
        if across.length() == 0:
            across = along
            across.cross(Vector3(0, 1, 0))
        across.normalize()
        # The caps bulge along the segment as the camera sees it: its
        # direction with the part toward the eye taken out, so each half
        # disc lies square to the view, as the silhouette of three.js's
        # capsule does. A segment seen end on has no such part, and its
        # two half discs make one disc.
        var ahead = forward
        ahead.cross(across)
        ahead.normalize()
        self.along = ahead
        self.across = across

    def corner(
        self, end: ClipVertex, side: Float32, ahead: Float32
    ) -> ClipVertex:
        """Return `end` moved `side` half widths across the segment and
        `ahead` half widths along it.

        Args:
            end: One end of the segment, or a point along it.
            side: How far across, in half widths.
            ahead: How far along, in half widths.

        Returns:
            The corner, carrying `end`'s color and distance along the line.
        """
        var place: Vector3
        if self.world_units:
            place = (
                end.position
                + (self.across * side + self.along * ahead) * self.half
            )
        else:
            var screen = self.to_screen.transform_point(end.position)
            var move = (
                self.across_screen * side + self.along_screen * ahead
            ) * self.half
            place = self.from_screen.transform_point(
                Vector3(screen.x + move.x, screen.y + move.y, screen.z)
            )
        return ClipVertex(
            place,
            end.color,
            Vector3(0, 0, 1),
            0,
            0,
            self.to_world.transform_point(place),
            line_distance=end.line_distance,
        )

    def radius(self, end: ClipVertex) -> Float32:
        """Return how many pixels across half the line is at `end`.

        Args:
            end: One end of the segment.

        Returns:
            Half the width on the image: `half` itself when it is in
            pixels, and the projected half width when it is in meters.
        """
        if not self.world_units:
            return self.half
        var middle = self.to_screen.transform_point(end.position)
        var edge = self.to_screen.transform_point(
            self.corner(end, 1, 0).position
        )
        return Vector2(edge.x - middle.x, edge.y - middle.y).length()


def _emit_cap(
    ribbon: _Ribbon,
    paint: _Paint,
    mut corners: _Slim,
    end: ClipVertex,
    outward: Float32,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
) raises:
    """Build the round cap at one end of a wide segment and append it.

    three.js's `LineMaterial` cuts a half disc out of the square it puts
    past each end, per fragment. Here the half disc is a fan of triangles
    about the end, `cap_steps` of them, so that it is drawn by the
    triangle rule. Two segments that share an end overlap in their caps,
    which is the round join three.js draws too.

    Args:
        ribbon: The segment's directions.
        paint: What every corner of the draw carries.
        corners: The frame's raster vertices, appended to.
        end: The end the cap is about.
        outward: One at the segment's end, minus one at its start: which
            way along the segment the cap bulges.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The planes that each cut.
        any_of: The clipping planes of which a kept point needs one.

    Raises:
        Error: If the clipper does.
    """
    var steps = cap_steps(ribbon.radius(end))
    var turn = Float32(pi) / Float32(steps)
    var last = ribbon.corner(end, 1, 0)
    for step in range(1, steps + 1):  # pragma: no branch
        var angle = turn * Float32(step)
        var next = ribbon.corner(end, cos(angle), outward * sin(angle))
        _emit_clipped(paint, corners, end, last, next, near, far, sides, any_of)
        last = next


def _ramp_corner(
    ribbon: _Ribbon, end: ClipVertex, side: Float32, ahead: Float32
) -> ClipVertex:
    """Return a ribbon corner that carries where it is about `end`, in
    half widths, as its texture coordinates: three.js's `vUv` on a
    `LineMaterial`, which the edge ramp reads.

    Args:
        ribbon: The segment's directions.
        end: The end the corner is about.
        side: How far across, in half widths.
        ahead: How far along, in half widths.

    Returns:
        The corner, with `side` and `ahead` in `u` and `v`.
    """
    var corner = ribbon.corner(end, side, ahead)
    corner.u = side
    corner.v = ahead
    return corner


def _emit_square_cap(
    ribbon: _Ribbon,
    paint: _Paint,
    mut corners: _Slim,
    end: ClipVertex,
    outward: Float32,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
) raises:
    """Build the square past one end of a wide segment and append it, for
    a line under alpha to coverage.

    three.js's `LineMaterial` puts a square past each end and gives each
    fragment of it an alpha: one inside the half disc, zero outside, and a
    ramp as wide as `fwidth` across the rim. Here the square is two
    triangles whose corners carry their place about the end, and `paint`
    names the edge ramp that reads it; see
    `render.derivatives.edge_ramp_alpha`.

    Args:
        ribbon: The segment's directions.
        paint: What every corner of the draw carries, its edge ramp
            included.
        corners: The frame's raster vertices, appended to.
        end: The end the cap is about.
        outward: One at the segment's end, minus one at its start: which
            way along the segment the cap lies.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The planes that each cut.
        any_of: The clipping planes of which a kept point needs one.

    Raises:
        Error: If the clipper does.
    """
    var a = _ramp_corner(ribbon, end, -1, 0)
    var b = _ramp_corner(ribbon, end, 1, 0)
    var c = _ramp_corner(ribbon, end, 1, outward)
    var d = _ramp_corner(ribbon, end, -1, outward)
    _emit_clipped(paint, corners, a, b, c, near, far, sides, any_of)
    _emit_clipped(paint, corners, a, c, d, near, far, sides, any_of)


def _strand_corner(
    ribbon: _Ribbon,
    paint: _Paint,
    end: ClipVertex,
    side: Float32,
    ahead: Float32,
    alpha: Float32,
) -> _Placed:
    """Return a ribbon corner with the coverage folded into its alpha,
    projected once for every triangle that shares it.

    Args:
        ribbon: The segment's directions.
        paint: What every corner of the draw carries.
        end: The end the corner is about.
        side: How far across, in half widths.
        ahead: How far along, in half widths.
        alpha: The coverage, multiplied into the color's alpha.

    Returns:
        The corner and its projection.
    """
    var corner = ribbon.corner(end, side, ahead)
    corner.color.a *= alpha
    return _Placed(paint, corner^)


def _strand_profile(
    ribbon: _Ribbon, end: ClipVertex, scale: Int
) -> SIMD[DType.float32, 4]:
    """Return inner and outer radius ratios, and peak sample coverage.

    The one-output-pixel box filter of a strip is a trapezoid. A
    subpixel strip has a lower plateau and carries its width in the peak.
    Its integral across the ribbon is the requested projected width.
    """
    var radius = max(ribbon.radius(end), Float32(1e-12))
    var pixel = Float32(scale)
    return SIMD[DType.float32, 4](
        abs(radius - pixel * 0.5) / radius,
        (radius + pixel * 0.5) / radius,
        min(Float32(1), 2 * radius / pixel),
        0,
    )


def _emit_strand_cap(
    ribbon: _Ribbon,
    paint: _Paint,
    mut corners: _Slim,
    end: ClipVertex,
    profile: SIMD[DType.float32, 4],
    outward: Float32,
    scale: Int,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
) raises:
    """Append a round cap with the same feather as the ribbon sides.

    Each corner is placed and projected once, and the fan's triangles
    share them.
    """
    var center = _strand_corner(ribbon, paint, end, 0, 0, profile[2])
    var steps = cap_steps(ribbon.radius(end) + Float32(scale) * 0.5)
    var turn = Float32(pi) / Float32(steps)
    var inner = _strand_corner(ribbon, paint, end, profile[0], 0, profile[2])
    var outer = _strand_corner(ribbon, paint, end, profile[1], 0, 0)
    for step in range(1, steps + 1):  # pragma: no branch
        var angle = turn * Float32(step)
        var side = cos(angle)
        var ahead = outward * sin(angle)
        var next_inner = _strand_corner(
            ribbon,
            paint,
            end,
            side * profile[0],
            ahead * profile[0],
            profile[2],
        )
        var next_outer = _strand_corner(
            ribbon, paint, end, side * profile[1], ahead * profile[1], 0
        )
        _emit_placed(
            paint, corners, center, inner, next_inner, near, far, sides, any_of
        )
        _emit_placed(
            paint, corners, inner, outer, next_outer, near, far, sides, any_of
        )
        _emit_placed(
            paint,
            corners,
            inner,
            next_outer,
            next_inner,
            near,
            far,
            sides,
            any_of,
        )
        inner = next_inner^
        outer = next_outer^


def _emit_strand_segment(
    ribbon: _Ribbon,
    paint: _Paint,
    mut corners: _Slim,
    start: ClipVertex,
    end: ClipVertex,
    scale: Int,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
) raises:
    """Append a filtered ribbon and caps, sampled by the shared alpha hash.

    The ribbon's eight corners are placed and projected once each, and
    its six triangles share them.
    """
    var first = _strand_profile(ribbon, start, scale)
    var second = _strand_profile(ribbon, end, scale)
    var a_side = SIMD[DType.float32, 4](
        -first[1], -first[0], first[0], first[1]
    )
    var b_side = SIMD[DType.float32, 4](
        -second[1], -second[0], second[0], second[1]
    )
    var a_alpha = SIMD[DType.float32, 4](0, first[2], first[2], 0)
    var b_alpha = SIMD[DType.float32, 4](0, second[2], second[2], 0)
    var a = _strand_corner(ribbon, paint, start, a_side[0], 0, a_alpha[0])
    var d = _strand_corner(ribbon, paint, end, b_side[0], 0, b_alpha[0])
    for strip in range(3):
        var b = _strand_corner(
            ribbon,
            paint,
            start,
            a_side[strip + 1],
            0,
            a_alpha[strip + 1],
        )
        var c = _strand_corner(
            ribbon,
            paint,
            end,
            b_side[strip + 1],
            0,
            b_alpha[strip + 1],
        )
        _emit_placed(paint, corners, a, b, c, near, far, sides, any_of)
        _emit_placed(paint, corners, a, c, d, near, far, sides, any_of)
        a = b^
        d = c^
    _emit_strand_cap(
        ribbon,
        paint,
        corners,
        start,
        first,
        -1,
        scale,
        near,
        far,
        sides,
        any_of,
    )
    _emit_strand_cap(
        ribbon,
        paint,
        corners,
        end,
        second,
        1,
        scale,
        near,
        far,
        sides,
        any_of,
    )


def _emit_wide_line(
    mut corners: _Slim,
    assets: Assets,
    draw: _Draw,
    view: Matrix4,
    to_screen: Matrix4,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
    render_scale: Int,
    coverage: LineCoverage,
    casters_only: Bool,
    workers: Int = 1,
) raises:
    """Build a wide line's triangles in camera space and append them.

    three.js's `LineSegments2` drawn with `LineMaterial`: each segment is
    a quad, and each end of it a round cap, unless the line is dashed.
    A dashed segment is cut into a quad per dash, with no caps, as
    three.js throws the caps of a dashed line away. Solid segments keep
    both round caps at every width, including subpixel widths. The segment
    is first cut to the near and the far planes, as three.js trims it to the near
    plane, so that no corner is placed from a point behind the camera. The
    triangles then go where every triangle goes: through the clipper and
    `_Paint.emit`, two-sided. See `objects.line_segments2`.

    Under alpha to coverage a solid line antialiases its edge, as
    three.js's `LineMaterial` does. Each cap is then the square past its
    end and not a fan, and the draw's state names an edge ramp that reads
    each fragment's place from its texture coordinates. See
    `_emit_square_cap` and `render.derivatives.edge_ramp_alpha`.

    Args:
        corners: The frame's raster vertices, appended to.
        assets: Where the geometry and the material live.
        draw: Its draw, for its geometry, material and world matrix.
        view: The world-to-camera transform.
        to_screen: The camera-to-pixels transform.
        near: Distance to the near plane.
        far: Distance to the far plane.
        sides: The camera's side planes and the clipping planes that each
            cut, in camera space.
        any_of: The clipping planes of which a kept point needs one.
        render_scale: How many raster pixels stand for one output pixel,
            which a width in pixels is multiplied by.
        coverage: The solid or feathered hashed coverage rule.
        casters_only: Whether these samples populate a light depth map.
        workers: How many threads may build the triangles. A line of
            fewer than two runs of `WIDE_RUN_SEGMENTS` segments builds on
            one.

    Raises:
        Error: If the material is not `BASIC`, carries a map, an alpha
            map, an env map, an ao map or a light map, or is a wireframe; if the geometry is
            indexed, has no positions or an odd count of them; if the
            material asks for vertex colors the geometry does not have;
            if a dash pattern is too fine for a segment; or if the
            material's depth, color, stencil or offset state is refused.
    """
    var material = assets.materials.get(draw.material)
    require_line_coverage(coverage)
    var strand = coverage == STRAND_LINE_COVERAGE
    if strand:
        require_strand_opacity(material.opacity)
    if strand and (
        material.blending != OPAQUE
        or not material.depth_write
        or not material.depth_test
        or material.is_dashed()
    ):
        raise Error(
            "Strand coverage needs solid depth-tested, depth-writing opaque"
            " lines"
        )
    _refuse_nodes(material, "A wide line")
    if material.kind != BASIC:
        raise Error(
            "A wide line material must be BASIC: a line has no surface, so"
            " it has no normal for a light to reach"
        )
    if material.map != NO_TEXTURE or material.alpha_map != NO_TEXTURE:
        raise Error(
            "A wide line material has no map: three.js's LineMaterial"
            " samples none"
        )
    if material.has_env_map():
        raise Error(
            "A wide line material has no env map: a line has no surface to"
            " reflect from"
        )
    if material.has_baked_map():
        raise Error(
            "A wide line material has no ao map or light map: three.js's"
            " LineMaterial samples none"
        )
    if material.wireframe:
        raise Error(
            "A wide line cannot be a wireframe: it is already its own lines"
        )
    ref geometry = assets.geometries.get(draw.geometry)
    require_unindexed_wide_line(geometry)
    ref positions = geometry.attribute_view(String(POSITION))
    var count = positions.count()
    var visible = drawn_segments(geometry)
    var first_vertex = visible[0]
    var segments = visible[1]
    var base = _with_opacity(FloatColor(srgb=material.color), material.opacity)
    var colors = _vertex_colors(geometry, material.vertex_colors, base, count)
    var dashed = material.is_dashed()
    var dash = material.dash_size.to(METER)
    var gap = material.gap_size.to(METER)
    # How far along the line each point is, scaled and then slid, three.js's
    # `vLineDistance + dashOffset`. A solid line reads none of it.
    var along = List[Float32](length=count, fill=0)
    if dashed:
        along = line_distances(SEGMENTS, positions)
        var slide = material.dash_offset.to(METER)
        for point in range(count):
            along[point] = along[point] * material.dash_scale + slide
    var width = material.line_width
    var half = width.size * 0.5
    if not width.world_units:
        half *= Float32(render_scale)
    var from_screen = Matrix4(copy=to_screen)
    from_screen.invert()
    var to_world = Matrix4(copy=view)
    to_world.invert()
    ref world = draw.world
    var state = _draw_state(material, casters_only, False, False, True)
    if strand:
        state.alpha_hash = True
        state.strand_hash = True
        state.alpha_to_coverage = False
    # The antialiased edge of three.js's `LineMaterial` under alpha to
    # coverage. A line in pixels has it on its round caps. A line in the
    # world has it on its whole outline. A dashed line has none, because
    # three.js throws its caps away and skips the capsule. A draw has one
    # state, so the body of a line in pixels carries the ramp too, with
    # coordinates of zero, where the ramp is one.
    if state.alpha_to_coverage and not dashed:
        state.edge_ramp = (
            CAPSULE_EDGE_RAMP if width.world_units else DISC_EDGE_RAMP
        )
    var blending = material.blending
    if casters_only:
        blending = OPAQUE
    var paint = _Paint(
        to_screen,
        NO_TEXTURE,
        blending,
        BASIC,
        NO_TEXTURE,
        NO_TEXTURE,
        material.alpha_test,
        FloatColor(0.0, 0.0, 0.0),
        0,
        NO_TEXTURE,
        NO_TEXTURE,
        False,
        DOUBLE_SIDE,
        NO_CUBE_TEXTURE,
        1,
        MULTIPLY_OPERATION,
        _Physics(),
        False,
        # Ordinary LineMaterial keeps its three.js flags. Strand coverage
        # hashes the feather and opacity in both the image and shadow map.
        state,
        _draw_offset(material, casters_only),
        _shown_of(material),
        TextureFrames(),
        0,
    )
    var each = 6
    if strand:
        each = 18 + 18 * cap_steps(half + Float32(render_scale) * 0.5)
    elif state.edge_ramp != NO_EDGE_RAMP:
        # Two squares of two triangles each.
        each += 12
    elif not dashed:
        each += 6 * cap_steps(half)
    # Each point in the world once, so every run reads the same values.
    var placed = List[Vector3](capacity=segments * 2)
    for vertex in range(first_vertex, first_vertex + segments * 2):
        placed.append(world.transform_point(positions.vector3(vertex)))
    var setup = _WideRun(
        first_vertex,
        placed^,
        colors^,
        along^,
        view,
        to_screen,
        from_screen,
        to_world,
        near,
        far,
        sides.copy(),
        any_of.copy(),
        render_scale,
        width.world_units,
        half,
        strand,
        dashed,
        dash,
        gap,
        paint,
    )
    var tasks = min(workers, segments // WIDE_RUN_SEGMENTS)
    if tasks <= 1:
        corners.reserve(len(corners) + segments * each)
        _wide_segments(corners, setup, 0, segments)
        return
    # Disjoint runs of segments, each into a list of its own, joined in
    # segment order: the same corners as one run, as `_emit_jobs` keeps.
    var outputs = List[_Slim]()
    var failures = List[String]()
    for _ in range(tasks):  # pragma: no branch
        outputs.append(_Slim())
        failures.append(String())
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _wide_task(
                Pointer(to=setup).unsafe_origin_cast[MutAnyOrigin](),
                outputs.unsafe_ptr()
                .unsafe_offset(task)
                .unsafe_origin_cast[MutAnyOrigin](),
                failures.unsafe_ptr()
                .unsafe_offset(task)
                .unsafe_origin_cast[MutAnyOrigin](),
                task * segments // tasks,
                (task + 1) * segments // tasks,
                each,
            )
        )
    group.wait()
    # The tasks read `setup` through a pointer the compiler cannot see.
    # This read keeps it alive until every task has finished.
    _ = len(setup.placed)
    # The earliest run that failed holds the earliest segment that did.
    for task in range(tasks):  # pragma: no branch
        if failures[task]:
            raise Error(failures[task])
    # A draw shares one surface per facing. Each run made its own, at
    # most one a facing, from its first corner that faced that way. Keep
    # the earliest run's for each facing, in the order one run makes
    # them, and let every corner name the kept one. A run whose every
    # segment was cut away holds none.
    var kept = List[Int](length=2 * tasks, fill=-1)
    for task in range(tasks):  # pragma: no branch
        for own in range(len(outputs[task].surfaces)):
            kept[2 * task + own] = _adopt(corners, outputs[task], own)
    # Place each run's corners in parallel, as `_emit_jobs` does: one
    # copy each, with each corner's surface renamed to the kept one.
    var starts = List[Int](length=tasks, fill=len(corners))
    for task in range(1, tasks):  # pragma: no branch
        starts[task] = starts[task - 1] + len(outputs[task - 1])
    corners.corners.resize(
        unsafe_uninit_length=starts[tasks - 1] + len(outputs[tasks - 1])
    )
    var copies = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        copies.create_task(
            _place_renamed(
                outputs[task]
                .corners.unsafe_ptr()
                .unsafe_origin_cast[MutAnyOrigin](),
                corners.corners.unsafe_ptr()
                .unsafe_offset(starts[task])
                .unsafe_origin_cast[MutAnyOrigin](),
                len(outputs[task]),
                kept[2 * task],
                kept[2 * task + 1],
            )
        )
    copies.wait()
    # The copies read the runs through pointers the compiler cannot see.
    _ = len(outputs)


# A run holds at least this many segments, so a short line stays serial.
comptime WIDE_RUN_SEGMENTS = 1024


struct _WideRun(Movable):
    """What every segment of one wide line reads: its placed points, its
    colors and distances, the camera, the clip planes and the paint."""

    var first_vertex: Int
    var placed: List[Vector3]
    var colors: List[FloatColor]
    var along: List[Float32]
    var view: Matrix4
    var to_screen: Matrix4
    var from_screen: Matrix4
    var to_world: Matrix4
    var near: Float32
    var far: Float32
    var sides: List[Plane]
    var any_of: List[Plane]
    var render_scale: Int
    var world_units: Bool
    var half: Float32
    var strand: Bool
    var dashed: Bool
    var dash: Float32
    var gap: Float32
    var paint: _Paint

    def __init__(
        out self,
        first_vertex: Int,
        var placed: List[Vector3],
        var colors: List[FloatColor],
        var along: List[Float32],
        view: Matrix4,
        to_screen: Matrix4,
        from_screen: Matrix4,
        to_world: Matrix4,
        near: Float32,
        far: Float32,
        var sides: List[Plane],
        var any_of: List[Plane],
        render_scale: Int,
        world_units: Bool,
        half: Float32,
        strand: Bool,
        dashed: Bool,
        dash: Float32,
        gap: Float32,
        paint: _Paint,
    ):
        self.first_vertex = first_vertex
        self.placed = placed^
        self.colors = colors^
        self.along = along^
        self.view = view
        self.to_screen = to_screen
        self.from_screen = from_screen
        self.to_world = to_world
        self.near = near
        self.far = far
        self.sides = sides^
        self.any_of = any_of^
        self.render_scale = render_scale
        self.world_units = world_units
        self.half = half
        self.strand = strand
        self.dashed = dashed
        self.dash = dash
        self.gap = gap
        self.paint = paint


__async def _wide_task(
    setup: Pointer[_WideRun, MutAnyOrigin],
    corners: MutPointer[_Slim, MutAnyOrigin],
    failure: MutPointer[String, MutAnyOrigin],
    first: Int,
    past: Int,
    each: Int,
):
    # A task cannot raise. Its error goes back to `_emit_wide_line`.
    try:
        # Room for every corner of an uncut run, as the serial path
        # reserves, so the run's list does not grow and copy itself.
        corners[].reserve((past - first) * each)
        _wide_segments(corners[], setup[], first, past)
    except error:
        failure[] = String(error)


def _wide_segments(
    mut corners: _Slim, run: _WideRun, first: Int, past: Int
) raises:
    """Append the triangles of segments `first` up to `past`."""
    var no_planes = List[Plane]()
    for segment in range(first, past):
        var ends = List[ClipVertex]()
        for side in range(2):  # pragma: no branch
            var point = segment * 2 + side
            var vertex = run.first_vertex + point
            var placed = run.placed[point]
            ends.append(
                ClipVertex(
                    run.view.transform_point(placed),
                    run.colors[vertex],
                    Vector3(0, 0, 1),
                    0,
                    0,
                    placed,
                    line_distance=run.along[vertex],
                )
            )
        # Cut to the view depth only. The sides and the clipping planes
        # cut the triangles below, so a cap past the edge of the image is
        # cut where the image ends rather than moved inside it.
        var kept = clip_segment(ends[0], ends[1], run.near, run.far, no_planes)
        if len(kept) < 2:
            continue
        var start = kept[0]
        var end = kept[1]
        var ribbon = _Ribbon(
            start,
            end,
            run.world_units,
            run.half,
            run.to_screen,
            run.from_screen,
            run.to_world,
        )
        if run.strand:
            _emit_strand_segment(
                ribbon,
                run.paint,
                corners,
                start,
                end,
                run.render_scale,
                run.near,
                run.far,
                run.sides,
                run.any_of,
            )
            continue
        var spans = dash_spans(
            start.line_distance, end.line_distance, run.dash, run.gap
        )
        for piece in range(len(spans) // 2):
            var a_at = _between(start, end, spans[piece * 2])
            var b_at = _between(start, end, spans[piece * 2 + 1])
            var a = ribbon.corner(a_at, -1, 0)
            var b = ribbon.corner(a_at, 1, 0)
            var c = ribbon.corner(b_at, 1, 0)
            var d = ribbon.corner(b_at, -1, 0)
            # Under the capsule's ramp each corner carries how far across
            # it is. Under the disc's the body keeps coordinates of zero,
            # where that ramp is one.
            if run.paint.state.edge_ramp == CAPSULE_EDGE_RAMP:
                a.u = -1
                b.u = 1
                c.u = 1
                d.u = -1
            _emit_clipped(
                run.paint,
                corners,
                a,
                b,
                c,
                run.near,
                run.far,
                run.sides,
                run.any_of,
            )
            _emit_clipped(
                run.paint,
                corners,
                a,
                c,
                d,
                run.near,
                run.far,
                run.sides,
                run.any_of,
            )
        if run.dashed:
            continue
        if run.paint.state.edge_ramp != NO_EDGE_RAMP:
            _emit_square_cap(
                ribbon,
                run.paint,
                corners,
                start,
                -1,
                run.near,
                run.far,
                run.sides,
                run.any_of,
            )
            _emit_square_cap(
                ribbon,
                run.paint,
                corners,
                end,
                1,
                run.near,
                run.far,
                run.sides,
                run.any_of,
            )
            continue
        _emit_cap(
            ribbon,
            run.paint,
            corners,
            start,
            -1,
            run.near,
            run.far,
            run.sides,
            run.any_of,
        )
        _emit_cap(
            ribbon,
            run.paint,
            corners,
            end,
            1,
            run.near,
            run.far,
            run.sides,
            run.any_of,
        )


def _line_corner(
    view_points: List[Vector3],
    world_points: List[Vector3],
    colors: List[FloatColor],
    vertex: Int,
) -> ClipVertex:
    """Return one end of a wireframe edge, ready for `clip_segment`.

    A line carries a position, a color and a world position and nothing
    else: its kind is unlit, so no normal is read, and it has no surface
    coordinates, so no map is sampled. See `objects.line`.

    Args:
        view_points: Every vertex of this draw, in camera space.
        world_points: The same vertices, in world space.
        colors: The color at each vertex.
        vertex: Which vertex this end is.

    Returns:
        The corner.
    """
    return ClipVertex(
        view_points[vertex],
        colors[vertex],
        Vector3(0, 0, 0),
        0,
        0,
        world_points[vertex],
    )


def camera_position[C: Camera](scene: Scene, camera: C) raises -> Vector3:
    """Return where `camera` stands, in world space.

    three.js's `cameraPosition` uniform. A `PHONG` material measures its
    highlight along the direction from the surface to here, so
    `render` asks it. `Scene.update_lods` takes it for an LOD.
    The view transform is rigid, so its inverse's translation is the eye.

    Args:
        scene: The scene the camera may be riding a node of, updated.
        camera: The camera to ask.

    Returns:
        The camera's world-space position.

    Raises:
        Error: If the camera rides a node the scene does not have, or the
            scene is stale.
    """
    var to_world = camera.view_matrix_in(scene)
    to_world.invert()
    return to_world.transform_point(Vector3(0, 0, 0))


def toward_camera[C: Camera](scene: Scene, camera: C) raises -> Vector3:
    """Return the one direction from any surface toward `camera`, or
    `PERSPECTIVE_VIEW` when its rays converge and there is no single one.

    three.js's `isOrthographic` branch in `lights_fragment_begin`, asked
    once per frame instead of once per fragment. An orthographic camera's
    rays run parallel, so every surface sees it from the same direction,
    and a `PHONG` highlight computed from a *position* would put a bright
    center on a flat plane that should reflect evenly. A perspective
    camera's rays converge, and there the position is the answer.

    Which one a camera is comes from its own projection matrix: a parallel
    projection keeps `w` at one and so is affine, and a converging one does
    not. That is the same fact `cameras.camera` states about the bottom
    row, asked of the matrix rather than of a flag a camera would have to
    carry, so any camera answers it without a method of its own.

    Args:
        scene: The scene the camera may be riding a node of, updated.
        camera: The camera to ask.

    Returns:
        The unit direction toward the camera under a parallel projection,
        or `PERSPECTIVE_VIEW` under a converging one.

    Raises:
        Error: If the camera's volume is degenerate, it rides a node the
            scene does not have, or the scene is stale.
    """
    if not camera.projection_matrix().is_affine():
        return PERSPECTIVE_VIEW
    # The camera looks down its own -z, so +z points back at the viewer;
    # carried into the world by the inverse of the view, which is rigid.
    var to_world = camera.view_matrix_in(scene)
    to_world.invert()
    var toward = to_world.transform_direction(Vector3(0, 0, 1))
    toward.normalize()
    return toward^


def camera_up[C: Camera](scene: Scene, camera: C) raises -> Vector3:
    """Return which way is up for `camera`, in world space.

    three.js measures a matcap's frame against the view space +y axis, and
    this is that axis in world coordinates. A matcap turns with the camera,
    so rolling the camera rolls the image on every surface, and that is
    the frame the roll is measured in.

    Asked once per frame rather than once per fragment, as
    `camera_position` and `toward_camera` are. Every projection answers the
    same way: which way is up does not depend on whether the rays converge.

    Args:
        scene: The scene the camera may be riding a node of, updated.
        camera: The camera to ask.

    Returns:
        The camera's own up axis, a unit vector in world space.

    Raises:
        Error: If the camera rides a node the scene does not have, or the
            scene is stale.
    """
    # The view carries the world into the camera's frame, so its inverse
    # carries the frame's +y back out. The view is rigid, so the result is
    # already unit length; normalized anyway, for the reason
    # `toward_camera` normalizes.
    var to_world = camera.view_matrix_in(scene)
    to_world.invert()
    var up = to_world.transform_direction(Vector3(0, 1, 0))
    up.normalize()
    return up^


def camera_back[C: Camera](scene: Scene, camera: C) raises -> Vector3:
    """Return which way is back for `camera`, in world space: its view
    space +z axis, the way it looks away from.

    With `camera_up` it is the whole view rotation, which a render
    target's normal attachment is written in; see
    `lights.lighting.view_direction`. Asked once per frame, as
    `camera_up` is.

    Args:
        scene: The scene the camera may be riding a node of, updated.
        camera: The camera to ask.

    Returns:
        The camera's own back axis, a unit vector in world space.

    Raises:
        Error: If the camera rides a node the scene does not have, or the
            scene is stale.
    """
    var to_world = camera.view_matrix_in(scene)
    to_world.invert()
    var back = to_world.transform_direction(Vector3(0, 0, 1))
    back.normalize()
    return back^


def _scaled(rect: Rect, factor: Int) -> Rect:
    """Return `rect` with its corner and size multiplied by `factor`: where
    a rectangle of output pixels lands on a supersampled frame."""
    return Rect(
        rect.x * factor,
        rect.y * factor,
        rect.width * factor,
        rect.height * factor,
    )


def _set_backdrop(
    mut image: Framebuffer,
    x: Int,
    y: Int,
    color: FloatColor,
    bytes: SrgbBytes,
) raises:
    """Write one backdrop pixel: the color encoded to sRGB bytes, opaque.

    Opaque whatever the texture's alpha said, as three.js's background
    plane is drawn opaque: a background hides nothing but the clear color.
    `bytes` encodes it, as `encode` would.
    """
    var shown = color.encode_with(bytes)
    image.set_pixel(x, y, Color(shown.r, shown.g, shown.b, 255))


@fieldwise_init
struct _BackdropRays(ImplicitlyCopyable):
    """What every pixel of a backdrop seen by direction needs: its ray,
    where it lands, and how it is shown."""

    var backdrop: Background
    var kept: Rect
    var viewport: Rect
    var top: Int
    var width: Int
    var height: Int
    var unproject: Matrix4
    var to_world: Matrix4
    var spin: Basis3
    var blur: Float32
    var shown: Float32

    def paint(
        self,
        mut image: Framebuffer,
        assets: Assets,
        bytes: SrgbBytes,
        first: Int,
        past: Int,
    ) raises:
        """Paint the rows `first` up to `past` of the backdrop.

        Args:
            image: Where each pixel is written.
            assets: The background's textures.
            bytes: The table each pixel is encoded through.
            first: The first row.
            past: One past the last row.

        Raises:
            Error: If a texture the background names cannot be read.
        """
        for y in range(first, past):  # pragma: no branch
            for x in range(self.width):  # pragma: no branch
                if not self.kept.contains_pixel(
                    x, y, self.height
                ) or not self.viewport.contains_pixel(x, y, self.height):
                    continue
                var ndc_x = texel_ndc(x - self.viewport.x, self.viewport.width)
                var ndc_y = texel_ndc_up(y - self.top, self.viewport.height)
                var near = self.unproject.transform_point(
                    Vector3(ndc_x, ndc_y, -1)
                )
                var far = self.unproject.transform_point(
                    Vector3(ndc_x, ndc_y, 1)
                )
                var looked = self.spin.turn(
                    self.to_world.transform_direction(far - near)
                )
                var seen: FloatColor
                if self.backdrop.kind == TEXTURE_BACKGROUND:
                    seen = _panorama_seen(
                        assets.textures.get(self.backdrop.texture),
                        looked,
                        self.blur,
                    )
                else:
                    seen = _sky_seen(
                        assets.cube_textures.get(self.backdrop.cube),
                        looked,
                        self.blur,
                    )
                _set_backdrop(image, x, y, _brightened(seen, self.shown), bytes)


__async def _backdrop_band(
    rays: Pointer[_BackdropRays, ImmutAnyOrigin],
    image: MutPointer[Framebuffer, MutAnyOrigin],
    assets: Pointer[Assets, ImmutAnyOrigin],
    bytes: Pointer[SrgbBytes, ImmutAnyOrigin],
    errors: MutPointer[String, MutAnyOrigin],
    band: Int,
    first: Int,
    past: Int,
):
    """`_BackdropRays.paint` as a task, one band of rows; a task cannot
    raise, so an error is written into the band's slot."""
    try:
        rays[].paint(image[], assets[], bytes[], first, past)
    except e:
        errors[unsafe_offset=band] = String(e)


def _brightened(color: FloatColor, factor: Float32) -> FloatColor:
    """Return a color's light times a factor, its alpha kept: three.js's
    `texColor.rgb *= backgroundIntensity`."""
    return FloatColor(
        color.r * factor, color.g * factor, color.b * factor, color.a
    )


def _sky_seen(
    sky: CubeTexture, direction: Vector3, blurriness: Float32
) -> FloatColor:
    """Return what a cube background shows in a direction: its faces, or
    above a blurriness of zero the environment read at that roughness,
    from its PMREM when it has one, as three.js's `backgroundCube` shader
    reads `textureCubeUV` at `backgroundBlurriness`."""
    if blurriness > 0:
        return sky.sample_rough(direction, blurriness)
    return sky.sample(direction)


def _panorama_seen(
    picture: Texture, direction: Vector3, blurriness: Float32
) -> FloatColor:
    """Return what a panorama background shows in a direction: the image
    at `equirect_uv`, or above a blurriness of zero read down its chain at
    `reflection_level`, the stand-in a cube with no PMREM takes."""
    var at = equirect_uv(direction)
    if blurriness > 0:
        return picture.sample_level(
            at.x, at.y, reflection_level(blurriness, picture.levels)
        )
    return picture.sample(at.x, at.y)


def _light_aim(scene: Scene, light: Light) raises -> Vector3:
    """Return where a directional or spot light's camera looks, in world
    space: its target's position, or the origin when it names none.

    A node on its target gives the camera no direction. three.js's
    `Matrix4.lookAt` then looks down -z, and so does this: the point one
    meter down -z from the node.

    Raises:
        Error: If the light's node or target is not in the scene.
    """
    var aimed = Vector3(0, 0, 0)
    if light.target != NO_PARENT:
        aimed = scene.world_position(light.target)
    var at = scene.world_position(light.node)
    if (at - aimed).length() == 0:
        return Vector3(at.x, at.y, at.z - 1)
    return aimed


def _spot_camera(
    light: Light, at: Vector3, aimed: Vector3, aspect: Float32
) raises -> PerspectiveCamera:
    """Return a spot light's shadow camera, three.js's `SpotLightShadow`:
    twice the cone's angle times the shadow's `focus` high, `aspect`
    times as wide, from the shadow's near plane to `Light.shadow_far`, at
    `at` looking at `aimed`. The aspect is one but for a projector; see
    `lights.projector_light.projector_aspect`.

    A cone of a quarter turn, or a focus above one, can ask for a half turn
    or more, which no camera sees. three.js builds the degenerate camera
    such a field gives. The widest camera there is stands in for it.

    Raises:
        Error: If `PerspectiveCamera` refuses the planes or the aspect.
    """
    var field = light.shadow.spot_field_of_view(light.angle)
    var widest = nextafter(Float32(pi), Float32(0))
    if not (field.value < widest):
        field = Angle(widest, RADIAN)
    var camera = PerspectiveCamera(
        field,
        aspect,
        light.shadow.near,
        light.shadow_far(),
    )
    camera.place(at, aimed)
    return camera^


def _has_transmissive_back(material: Material) -> Bool:
    """Return True if a material's back faces join the transmission pass:
    three.js redraws a transmissive object as `BackSide` when its side is
    `DoubleSide`."""
    return material.transmits() and material.side == DOUBLE_SIDE


def _reads_scene(assets: Assets, nodes: NodeProgramId) raises -> Bool:
    """Return True if a node program reads the opaque scene behind its
    surface, so it is drawn after that scene is captured, as a
    transmissive surface is. `_checked_nodes` has found the program."""
    return nodes != NO_NODES and assets.programs.get(nodes).reads_scene


def _looks_behind(frame: Frame, triangle: Int) raises -> Bool:
    """Return True if a triangle of a prepared frame transmits, or its
    node program reads the scene behind it."""
    ref first = frame.surfaces[frame.corners[triangle * 3].surface]
    return (
        first.volume_scene_depth
        or first.transmission > 0
        or (
            first.nodes != NO_NODES
            and frame.programs.get(first.nodes).reads_scene
        )
    )


def _needs_volume_depth(frame: Frame) -> Bool:
    """Return whether a prepared surface requests opaque volume depth."""
    for surface in range(len(frame.surfaces)):
        if frame.surfaces[surface].volume_scene_depth:
            return True
    return False


def _transmits(frame: Frame) raises -> Bool:
    """Return True if any triangle of a prepared frame transmits, or reads
    the scene behind it through its node program.

    Every triangle `prepare_frame` returns is one of its draws, so the
    list is asked directly.
    """
    for triangle in range(len(frame.corners) // 3):
        if _looks_behind(frame, triangle):
            return True
    return False


def _is_see_through(
    frame: Frame, draw: Draw, exclude_volumes: Bool
) raises -> Bool:
    """Return True if a draw of a prepared frame transmits or blends:
    three.js leaves both its `transmissive` and its `transparent` lists
    out of the transmission pass. A draw that reads the scene behind is
    left out as a transmissive one is."""
    if draw.kind == DRAW_TRIANGLES:
        return (
            (
                exclude_volumes
                and frame.surfaces[frame.corners[draw.first * 3].surface].kind
                == VOLUME
            )
            or _looks_behind(frame, draw.first)
            or frame.surfaces[
                frame.corners[draw.first * 3].surface
            ].blend.mixes()
        )
    if draw.kind == DRAW_SPLATS:
        return True
    if draw.kind == DRAW_SEGMENTS:
        return frame.segments[draw.first * 2].blend.mixes()
    return frame.points[draw.first].blend.mixes()


def _opaque_draws(frame: Frame) raises -> List[Draw]:
    """Return the draws of a prepared frame the transmission pass draws:
    three.js's `opaqueObjects`, every run that neither transmits nor
    blends, in the frame's order."""
    var kept = List[Draw]()
    var exclude_volumes = _needs_volume_depth(frame)
    # Only a frame with a transmissive run is asked, so it has a draw and
    # the loop never runs zero times.
    for index in range(len(frame.draws)):  # pragma: no branch
        if not _is_see_through(frame, frame.draws[index], exclude_volumes):
            kept.append(frame.draws[index])
    return kept^


def _paint_backdrop(
    mut target: RenderTarget, kept: Rect, image: Framebuffer
) raises:
    """Write a backdrop's opaque pixels into the target as light, decoded
    from the same bytes the kernel decodes; see `Renderer.backdrop`.

    Nothing is claimed in depth: a background is behind everything.
    """
    var top = kept.top(target.height)
    # What `FloatColor(srgb=...)` makes of each byte, worked out once for
    # the 256 of them rather than three times a pixel.
    var decoded = List[Float32](capacity=256)
    for byte in range(256):  # pragma: no branch
        decoded.append(srgb_to_linear(Float32(byte) / 255))
    for y in range(top, top + kept.height):  # pragma: no branch
        for x in range(kept.x, kept.x + kept.width):  # pragma: no branch
            var pixel = image.get_pixel(x, y)
            if pixel.a != 255:
                continue
            target.write(
                x,
                y,
                FloatColor(
                    decoded[Int(pixel.r)],
                    decoded[Int(pixel.g)],
                    decoded[Int(pixel.b)],
                    Float32(pixel.a) / 255,
                ),
                False,
            )


# The most triangles of one draw that one task emits in a row. A large
# draw is cut into pieces this size, so that one skin of a hundred
# thousand triangles is shared between the workers as well.
comptime PIECE_TRIANGLES = 2048
# Bound the vertex arrays held by deferred draws. One larger draw can
# exceed this limit, but no other draw is held beside it. A serial
# renderer releases each draw before it prepares the next one.
comptime PENDING_VERTICES = 65536


struct _TriangleJob(Movable):
    """One draw's filled triangles, with its vertex stage done.

    `_prepared` transforms, lights and colors a draw's vertices on one
    thread, then builds one of these to hold the result. The job owns
    its arrays, so its triangles can be emitted on any thread, and many
    jobs can emit at once. See `_emit_jobs`.
    """

    var run_start: Int
    var triangles: Int
    # The geometry, whose index list is read if `indexed`.
    var geometry: GeometryId
    var indexed: Bool
    var smooth: Bool
    var mirrored: Bool
    var kind: MaterialKind
    var view: Matrix4
    var world_points: List[Vector3]
    var view_points: List[Vector3]
    var vertex_normals: List[Vector3]
    var vertex_colors: List[FloatColor]
    var first_set: Tuple[List[Float32], List[Float32]]
    var second_set: Tuple[List[Float32], List[Float32]]
    var customs: List[SIMD[DType.float32, 8]]
    var glow: FloatColor
    var tracks: Bool
    var current_points: List[Vector3]
    var previous_points: List[Vector3]
    var paint: _Paint
    var in_uv_space: Bool
    var viewport: Rect
    var height: Int
    var near: Float32
    var far: Float32
    var cut: List[Plane]
    var any_of: List[Plane]
    # The draw's sort key, for its span.
    var depth: Float32
    var blends: Bool
    var order: Int
    var source: _Source
    var transmits: Bool

    def __init__(
        out self,
        run_start: Int,
        triangles: Int,
        geometry: GeometryId,
        indexed: Bool,
        smooth: Bool,
        mirrored: Bool,
        kind: MaterialKind,
        view: Matrix4,
        var world_points: List[Vector3],
        var view_points: List[Vector3],
        var vertex_normals: List[Vector3],
        var vertex_colors: List[FloatColor],
        var first_set: Tuple[List[Float32], List[Float32]],
        var second_set: Tuple[List[Float32], List[Float32]],
        var customs: List[SIMD[DType.float32, 8]],
        glow: FloatColor,
        tracks: Bool,
        var current_points: List[Vector3],
        var previous_points: List[Vector3],
        paint: _Paint,
        in_uv_space: Bool,
        viewport: Rect,
        height: Int,
        near: Float32,
        far: Float32,
        var cut: List[Plane],
        var any_of: List[Plane],
        depth: Float32,
        blends: Bool,
        order: Int,
        source: _Source,
        transmits: Bool,
    ):
        """Hold one draw's vertex stage, ready to emit.

        Args:
            run_start: The first index slot of the drawn run.
            triangles: How many triangles the run holds.
            geometry: The geometry drawn.
            indexed: Whether the geometry has an index list.
            smooth: Whether the corners take the vertex normals.
            mirrored: Whether the world transform reflects.
            kind: The material's kind.
            view: The camera's view matrix.
            world_points: Each vertex in world space.
            view_points: Each vertex in camera space.
            vertex_normals: Each vertex's world normal, if `smooth`.
            vertex_colors: Each vertex's base color.
            first_set: Each vertex's first texture coordinates.
            second_set: Each vertex's second texture coordinates.
            customs: Each vertex's custom attributes.
            glow: The material's emitted light.
            tracks: Whether the corners carry velocity.
            current_points: Each vertex in this frame's clip space.
            previous_points: Each vertex in the last frame's clip space.
            paint: What every corner of the draw carries.
            in_uv_space: Whether the frame is a light map's.
            viewport: Where a light map's square is on the target.
            height: The target's height.
            near: Distance to the near plane.
            far: Distance to the far plane.
            cut: The planes that each cut the draw.
            any_of: The planes of which a kept point needs one.
            depth: The draw's camera-space depth.
            blends: Whether its material blends.
            order: Its node's render order.
            source: What drew it.
            transmits: Whether its material transmits.
        """
        self.run_start = run_start
        self.triangles = triangles
        self.geometry = geometry
        self.indexed = indexed
        self.smooth = smooth
        self.mirrored = mirrored
        self.kind = kind
        self.view = view
        self.world_points = world_points^
        self.view_points = view_points^
        self.vertex_normals = vertex_normals^
        self.vertex_colors = vertex_colors^
        self.first_set = first_set^
        self.second_set = second_set^
        self.customs = customs^
        self.glow = glow
        self.tracks = tracks
        self.current_points = current_points^
        self.previous_points = previous_points^
        self.paint = paint
        self.in_uv_space = in_uv_space
        self.viewport = viewport
        self.height = height
        self.near = near
        self.far = far
        self.cut = cut^
        self.any_of = any_of^
        self.depth = depth
        self.blends = blends
        self.order = order
        self.source = source
        self.transmits = transmits

    def note(self, mut spans: List[_Span], begin: Int, end: Int):
        """Record the corners this draw emitted between two counts.

        Args:
            spans: The list to record into.
            begin: Where the draw's corners start.
            end: Where they end.
        """
        _note_span(
            spans,
            DRAW_TRIANGLES,
            begin,
            end,
            self.depth,
            self.blends,
            self.order,
            self.source,
            self.transmits,
        )

    def emit(
        self,
        first: Int,
        past: Int,
        mut corners: _Slim,
        lights: Lighting,
        assets: Assets,
    ):
        """Append the triangles `first` up to `past` of the drawn run.

        It cannot raise, so a worker thread can run it: the camera's
        projection has refused a far plane in front of the near one
        before any job is made, and the index list was checked against
        the vertex count when the draw was.

        Args:
            first: The first triangle to emit, counted from the run's.
            past: One past the last.
            corners: The raster vertices, appended to.
            lights: The camera's lights, which a `GOURAUD` corner is lit
                by.
            assets: The store that holds the geometry.
        """
        # Read directly: the draw has already fetched this id.
        ref indices = assets.geometries.geometries[self.geometry.value].index
        ref vertex_u = self.first_set[0]
        ref vertex_v = self.first_set[1]
        ref vertex_u1 = self.second_set[0]
        ref vertex_v1 = self.second_set[1]
        for triangle in range(first, past):
            var first_corner = self.run_start + triangle * 3
            var second = first_corner + 1
            var third = first_corner + 2
            if self.indexed:
                first_corner = indices[first_corner]
                second = indices[second]
                third = indices[third]

            var normal_a: Vector3
            var normal_b: Vector3
            var normal_c: Vector3
            if self.smooth:
                normal_a = self.vertex_normals[first_corner]
                normal_b = self.vertex_normals[second]
                normal_c = self.vertex_normals[third]
            else:
                # No normals given, so the face supplies its own and the
                # whole triangle takes one.
                var geometric = face_normal(
                    self.world_points[first_corner],
                    self.world_points[second],
                    self.world_points[third],
                )
                if self.mirrored:
                    # The cross product follows the mirrored winding, so
                    # it comes out pointing into the surface. A supplied
                    # normal carried through the inverse transpose does
                    # not flip, and the two paths have to mean the same
                    # side or an object would shade differently purely
                    # for having normals.
                    geometric = -geometric
                if self.kind == NORMALS:
                    # Into view space, as the supplied normals were.
                    geometric = self.view.transform_direction(geometric)
                normal_a = geometric
                normal_b = geometric
                normal_c = geometric

            var corner_a = ClipVertex(
                self.view_points[first_corner],
                self.vertex_colors[first_corner],
                normal_a,
                vertex_u[first_corner],
                vertex_v[first_corner],
                self.world_points[first_corner],
                self.glow,
                u1=vertex_u1[first_corner],
                v1=vertex_v1[first_corner],
            )
            var corner_b = ClipVertex(
                self.view_points[second],
                self.vertex_colors[second],
                normal_b,
                vertex_u[second],
                vertex_v[second],
                self.world_points[second],
                self.glow,
                u1=vertex_u1[second],
                v1=vertex_v1[second],
            )
            var corner_c = ClipVertex(
                self.view_points[third],
                self.vertex_colors[third],
                normal_c,
                vertex_u[third],
                vertex_v[third],
                self.world_points[third],
                self.glow,
                u1=vertex_u1[third],
                v1=vertex_v1[third],
            )
            corner_a.custom = self.customs[first_corner]
            corner_b.custom = self.customs[second]
            corner_c.custom = self.customs[third]
            if self.kind == GOURAUD:
                _light_at_corner(
                    corner_a,
                    lights,
                    normal_a,
                    self.world_points[first_corner],
                )
                _light_at_corner(
                    corner_b, lights, normal_b, self.world_points[second]
                )
                _light_at_corner(
                    corner_c, lights, normal_c, self.world_points[third]
                )
            if self.tracks:
                corner_a.current = self.current_points[first_corner]
                corner_b.current = self.current_points[second]
                corner_c.current = self.current_points[third]
                corner_a.previous = self.previous_points[first_corner]
                corner_b.previous = self.previous_points[second]
                corner_c.previous = self.previous_points[third]
            # In texture space the triangle is placed by its second
            # coordinates, whole: nothing clips it and neither side
            # is culled.
            if self.in_uv_space:
                self.paint.emit_in_uv_space(
                    corners,
                    corner_a,
                    corner_b,
                    corner_c,
                    self.viewport,
                    self.height,
                )
                continue
            # A triangle wholly between the two planes is what the
            # clipper would hand back untouched, so it is not sent
            # through: the clipper builds four lists for every triangle
            # it is given, and a mesh in view gives it thousands that
            # it would return as they came. See `within_depth`.
            if _whole_in_view(
                corner_a,
                corner_b,
                corner_c,
                self.near,
                self.far,
                self.cut,
                self.any_of,
            ):
                self.paint.emit(corners, corner_a, corner_b, corner_c)
                continue
            var pieces = clip_ordered(
                corner_a,
                corner_b,
                corner_c,
                self.near,
                self.far,
                self.cut,
                self.any_of,
            )
            for piece in range(len(pieces) // 3):
                self.paint.emit(
                    corners,
                    pieces[piece * 3],
                    pieces[piece * 3 + 1],
                    pieces[piece * 3 + 2],
                )


@fieldwise_init
struct _Piece(ImplicitlyCopyable):
    """A run of one job's triangles, which one task emits whole."""

    # Which job, in the pending list.
    var job: Int
    # Its first triangle, and one past its last.
    var first: Int
    var past: Int


__async def _emit_pieces(
    jobs: MutPointer[_TriangleJob, MutAnyOrigin],
    pieces: MutPointer[_Piece, MutAnyOrigin],
    first_piece: Int,
    past_piece: Int,
    corners: MutPointer[_Slim, MutAnyOrigin],
    ends: MutPointer[Int, MutAnyOrigin],
    lights: Pointer[Lighting, ImmutAnyOrigin],
    assets: Pointer[Assets, ImmutAnyOrigin],
):
    """Emit a run of pieces into one task's own list.

    One of these runs per worker, as a task on the standard library's
    thread pool, and each writes a list of its own. It takes pointers
    because a coroutine must not borrow from the call that made it;
    `_emit_jobs` keeps everything alive until `TaskGroup.wait` returns.

    A task cannot raise, and nothing it runs does; see
    `_TriangleJob.emit`.

    Args:
        jobs: The pending jobs.
        pieces: Every job's pieces, in draw order.
        first_piece: The first piece this task emits.
        past_piece: One past the last.
        corners: This task's list, appended to.
        ends: Per piece, how long this task's list is once it is done.
        lights: The camera's lights, for a `GOURAUD` corner.
        assets: The store that holds the geometries.
    """
    # A task is only made for a run of one piece or more.
    for index in range(first_piece, past_piece):  # pragma: no branch
        var piece = pieces[unsafe_offset=index]
        # Each piece starts surfaces of its own, which the merge renumbers
        # into the frame's.
        corners[].new_surface()
        jobs[unsafe_offset=piece.job].emit(
            piece.first, piece.past, corners[], lights[], assets[]
        )
        ends[unsafe_offset=index] = len(corners[])


__async def _place_corners(
    source: MutPointer[Corner, MutAnyOrigin],
    destination: MutPointer[Corner, MutAnyOrigin],
    count: Int,
    shift: Int,
):
    """Copy one task's corners into their place in the frame's list.

    Args:
        source: The task's own corners.
        destination: Where its corners go in the frame's list.
        count: How many corners it holds.
        shift: How many of the frame's surfaces come before the task's
            own, which each corner's surface number moves by.
    """
    unsafe_memcpy(dest=destination, src=source, count=count)
    # A task whose every triangle was culled holds none.
    var index = 0
    while index < count:
        destination[unsafe_offset=index].surface += shift
        index += 1


def _adopt(mut corners: _Slim, run: _Slim, own: Int) -> Int:
    """Return the surface that stands for a run's surface `own`.

    The run is a part of the current draw that was built in a list of its
    own. When the draw has no surface yet for that facing, the run's
    surface becomes it, as `_Slim.append` makes one.

    Args:
        corners: The frame's list, which the draw is appended to.
        run: The part of the draw.
        own: A surface of the run, by its index there.

    Returns:
        The surface of `corners` that the run's corners name.
    """
    var turned = own == run.back_surface
    var surface = corners.back_surface if turned else corners.front_surface
    if surface < 0:
        surface = len(corners.surfaces)
        corners.surfaces.append(run.surfaces[own])
        if turned:
            corners.back_surface = surface
        else:
            corners.front_surface = surface
    return surface


__async def _place_renamed(
    source: MutPointer[Corner, MutAnyOrigin],
    destination: MutPointer[Corner, MutAnyOrigin],
    count: Int,
    first: Int,
    second: Int,
):
    """Copy one run's corners into their place, renaming its surfaces.

    Args:
        source: The run's own corners.
        destination: Where its corners go in the frame's list.
        count: How many corners it holds.
        first: The frame's surface that the run's surface 0 becomes.
        second: The frame's surface that the run's surface 1 becomes.
    """
    unsafe_memcpy(dest=destination, src=source, count=count)
    # A run whose every segment was cut away holds none.
    var index = 0
    while index < count:
        var own = destination[unsafe_offset=index].surface
        destination[unsafe_offset=index].surface = first if own == 0 else second
        index += 1


def _emit_jobs(
    mut jobs: List[_TriangleJob],
    mut corners: _Slim,
    mut spans: List[_Span],
    workers: Int,
    lights: Lighting,
    assets: Assets,
):
    """Emit the pending jobs in draw order, and record each one's span.

    With one worker, each job appends straight to `corners`. With more,
    the jobs are cut into pieces of at most `PIECE_TRIANGLES`, the pieces
    are shared out in order between the workers by triangle count, and
    each worker appends to a list of its own. The lists are then copied
    into `corners` one after another, also in parallel. The corners come
    out in the same order either way, so the frame is the same.

    Args:
        jobs: The pending jobs, emptied.
        corners: The frame's raster vertices, appended to.
        spans: The frame's spans, one appended per job that emits.
        workers: How many threads may emit.
        lights: The camera's lights, for a `GOURAUD` corner.
        assets: The store that holds the geometries.
    """
    if len(jobs) == 0:
        return
    var total = 0
    for index in range(len(jobs)):  # pragma: no branch
        total += jobs[index].triangles
    # Room for three corners a triangle, before the clipper adds any or
    # the facing test drops any. Grown to at least double when it runs
    # out: reserving the exact size reallocated on every draw and copied
    # the frame's whole list each time, which a scene of many meshes
    # paid for quadratically.
    var need = len(corners) + total * 3
    if need > corners.capacity():
        corners.reserve(max(need, 2 * corners.capacity()))
    var pieces = List[_Piece]()
    for index in range(len(jobs)):  # pragma: no branch
        var count = jobs[index].triangles
        var first = 0
        while first < count:
            var past = min(first + PIECE_TRIANGLES, count)
            pieces.append(_Piece(index, first, past))
            first = past
    var tasks = min(workers, len(pieces))
    if tasks <= 1:
        for index in range(len(jobs)):  # pragma: no branch
            corners.new_surface()
            var begin = len(corners)
            jobs[index].emit(0, jobs[index].triangles, corners, lights, assets)
            jobs[index].note(spans, begin, len(corners))
        jobs.clear()
        # What is appended next starts a surface of its own.
        corners.new_surface()
        return
    # Each task's first piece. The pieces are shared out evenly by count,
    # so every task has one at least; a piece holds at most
    # `PIECE_TRIANGLES`, so the shares are close in triangles as well.
    var bounds = List[Int](length=tasks + 1, fill=0)
    for index in range(tasks + 1):  # pragma: no branch
        bounds[index] = index * len(pieces) // tasks
    var outputs = List[_Slim]()
    # At least two tasks on this branch, so the loops run.
    for _ in range(tasks):  # pragma: no branch
        outputs.append(_Slim())
    var ends = List[Int](length=len(pieces), fill=0)
    var group = TaskGroup()
    for index in range(tasks):  # pragma: no branch
        group.create_task(
            _emit_pieces(
                jobs.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                pieces.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                bounds[index],
                bounds[index + 1],
                outputs.unsafe_ptr()
                .unsafe_offset(index)
                .unsafe_origin_cast[MutAnyOrigin](),
                ends.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=lights).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=assets).unsafe_origin_cast[ImmutAnyOrigin](),
            )
        )
    group.wait()
    # Where each task's corners and surfaces start in the frame's lists.
    var base = len(corners)
    var starts = List[Int](length=tasks, fill=base)
    var shifts = List[Int](length=tasks, fill=len(corners.surfaces))
    for index in range(1, tasks):  # pragma: no branch
        starts[index] = starts[index - 1] + len(outputs[index - 1])
        shifts[index] = shifts[index - 1] + len(outputs[index - 1].surfaces)
    corners.corners.resize(
        unsafe_uninit_length=starts[tasks - 1] + len(outputs[tasks - 1])
    )
    for index in range(tasks):  # pragma: no branch
        var slot = 0
        while slot < len(outputs[index].surfaces):
            corners.surfaces.append(outputs[index].surfaces[slot])
            slot += 1
    var copies = TaskGroup()
    for index in range(tasks):  # pragma: no branch
        copies.create_task(
            _place_corners(
                outputs[index]
                .corners.unsafe_ptr()
                .unsafe_origin_cast[MutAnyOrigin](),
                corners.corners.unsafe_ptr()
                .unsafe_offset(starts[index])
                .unsafe_origin_cast[MutAnyOrigin](),
                len(outputs[index]),
                shifts[index],
            )
        )
    copies.wait()
    # Each job's corners, from its first piece's start to its last
    # piece's end. The pieces are in draw order, so they are contiguous.
    # A job with no triangles has no piece, and records nothing.
    var job_begin = List[Int](length=len(jobs), fill=0)
    var job_end = List[Int](length=len(jobs), fill=0)
    for index in range(tasks):  # pragma: no branch
        # Every task has one piece at least.
        for slot in range(
            bounds[index], bounds[index + 1]
        ):  # pragma: no branch
            var piece = pieces[slot]
            var start = starts[index]
            if slot > bounds[index]:
                start += ends[slot - 1]
            if piece.first == 0:
                job_begin[piece.job] = start
            job_end[piece.job] = starts[index] + ends[slot]
    for index in range(len(jobs)):  # pragma: no branch
        jobs[index].note(spans, job_begin[index], job_end[index])
    # The tasks read these through pointers the compiler cannot see:
    # these reads keep them alive until every task has finished.
    _ = len(outputs)
    _ = len(ends)
    jobs.clear()
    # What is appended next starts a surface of its own.
    corners.new_surface()


def available_workers() -> Int:
    """Return how many rasterizer workers this machine can run at once.

    One per logical core. The bands are independent and memory-light, so
    hyperthreads help rather than hurt.
    """
    return num_logical_cores()


struct Frame(Movable):
    """A scene as both rasterizers take it: two lists of primitives and
    the one order they are drawn in.

    What `Renderer.prepare_frame` returns and `render.rasterizer.
    rasterize_frame` and `render.gpu.GpuRenderer.draw` consume, so that
    a parity test can hand both backends the identical input and demand
    identical output -- the property `prepare` alone gave the triangles.
    """

    # The triangles' corners, three each, slim: each names its surface.
    # `whole_corners` gives them as `prepare` returns them.
    var corners: List[Corner]
    # What the corners of each draw share, named by index.
    var surfaces: List[Surface]
    # Raster vertices, two per segment, as `prepare_lines` returns them.
    var segments: List[RasterVertex]
    # Raster vertices, one per point, as `prepare_points` returns them.
    var points: List[RasterVertex]
    var splats: List[ProjectedSplat]
    # The order to draw in, as runs of one list or another; see
    # `render.rasterizer.Draw`.
    var draws: List[Draw]
    # The node materials' programs, with this frame's time and view
    # written in; see `materials.nodes`.
    var programs: NodeProgramStore
    # What drew each draw, one item per entry of `draws`: what the render
    # hooks are told and `Renderer.info` counts.
    var items: List[RenderItem]

    def __init__(
        out self,
        var corners: List[Corner],
        var surfaces: List[Surface],
        var segments: List[RasterVertex],
        var draws: List[Draw],
        var points: List[RasterVertex] = List[RasterVertex](),
        var programs: NodeProgramStore = NodeProgramStore(),
        var items: List[RenderItem] = List[RenderItem](),
        var splats: List[ProjectedSplat] = List[ProjectedSplat](),
    ):
        """Hold a prepared frame.

        Args:
            corners: The triangles' corners, three each, slim.
            surfaces: What the corners name.
            segments: The segments' corners, two each.
            draws: The order to draw them in.
            points: The points, one corner each. None by default.
            programs: The node programs the corners name, for this frame.
                None by default.
            items: What drew each draw. None by default.
            splats: The projected Gaussian ellipses. None by default.
        """
        self.corners = corners^
        self.surfaces = surfaces^
        self.segments = segments^
        self.draws = draws^
        self.points = points^
        self.splats = splats^
        self.programs = programs^
        self.items = items^

    def whole_corners(self) -> List[RasterVertex]:
        """Return the triangles' corners whole, three each: what `prepare`
        returns, and what `render.gpu.GpuRenderer.draw` takes.

        Returns:
            Each corner joined to its surface.
        """
        var out = List[RasterVertex](capacity=len(self.corners))
        for index in range(len(self.corners)):
            ref corner = self.corners[index]
            out.append(joined(corner, self.surfaces[corner.surface]))
        return out^


@fieldwise_init
struct _CameraFrame(Movable):
    """The view, the clip and the culling planes for one camera."""

    var view: Matrix4
    var to_screen: Matrix4
    var near: Float32
    var far: Float32
    var clip: Matrix4
    var frustum: Frustum
    var sides: List[Plane]
    var global_planes: List[Plane]
