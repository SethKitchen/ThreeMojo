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
"""

from render.color_spaces import (
    ColorSpaceId,
    OutputEncoding,
    SRGB_COLOR_SPACE,
    output_encoding,
)
from cameras.array_camera import ArrayCamera
from cameras.camera import Camera
from cameras.cube_camera import CubeCamera
from core.background import (
    COLOR_BACKGROUND,
    CUBE_BACKGROUND,
    TEXTURE_BACKGROUND,
    Background,
)
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
    MaterialIndex,
)
from core.assets import Assets
from core.geometry_store import GeometryId
from core.fog import FogView
from lights.light import DIRECTIONAL, POINT, SPOT, Light
from lights.lighting import PERSPECTIVE_VIEW, Lighting
from lights.shadow import (
    CUBE_FACES,
    PCF_SHADOW_MAP,
    VSM_SHADOW_MAP,
    ShadowMap,
    ShadowMapType,
    SpotLightMap,
    cube_direction,
    cube_stored,
    cube_up,
    vsm_moments,
)
from lights.ltc import LtcTables
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.layers import Layers
from core.morph import MorphInfluences
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.bounds import Plane, Sphere
from math.frustum import Frustum
from math.matrix3 import Matrix3
from render.rect import Rect
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
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
from objects.line_segments2 import cap_steps, dash_spans
from objects.lod import Lod
from objects.sprite import SPRITE_RADIUS, Sprite
from objects.skinned_mesh import (
    ATTACHED,
    BONES_PER_VERTEX,
    SKIN_INDEX,
    SKIN_WEIGHT,
)
from materials.material import (
    BACK_SIDE,
    BASIC,
    DEFAULT_LINE_WIDTH,
    DOUBLE_SIDE,
    FRONT_SIDE,
    DEFAULT_IOR,
    MULTIPLY_OPERATION,
    NO_ATTENUATION,
    NO_DASH,
    NORMALS,
    OBJECT_SPACE_NORMAL_MAP,
    PHYSICAL,
    SHADOW,
    Blending,
    Combine,
    Material,
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
    NodeProgramId,
    NodeProgramStore,
    moved_position,
)
from render.pointrule import attenuated_size
from render.texture import IGNORED, Texture
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.framebuffer import Color, FloatColor, Framebuffer
from render.layered_target import TARGET_CUBE, LayeredRenderTarget
from render.target import RenderTarget, check_samples, sample_grid
from render.raster_state import (
    LOGARITHMIC_DEPTH,
    NO_OFFSET,
    STANDARD_DEPTH,
    DepthMode,
    PolygonOffset,
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
from render.rasterizer import (
    DRAW_POINTS,
    DRAW_SEGMENTS,
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    DRAW_TRIANGLES,
    Draw,
    DrawKind,
    LayerFactors,
    RasterVertex,
    ShadeMode,
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
from renderers.clip import (
    ClipVertex,
    clip_depth,
    clip_segment,
    within_any,
    within_depth,
    within_sides,
)
from std.math import cos, floor, isfinite, max, pi, sin
from std.memory import ArcPointer
from std.sys import num_logical_cores


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
    var first = b - a
    first.cross(c - a)
    # normalize leaves a zero vector alone, so a degenerate triangle gives a
    # zero normal rather than a division by zero.
    first.normalize()
    return first^


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
struct _Source(ImplicitlyCopyable):
    """The object a run of primitives came from: its node, its geometry
    and the material it was drawn with."""

    var node: NodeId
    var geometry: GeometryId
    var material: MaterialId


@fieldwise_init
struct RenderItem(ImplicitlyCopyable):
    """One run of a prepared frame, what three.js's render list holds for
    one object: what a render hook is told, and what a custom sort
    compares.

    The node, the geometry and the material drawn with, the scene's
    `override_material` when it replaced the object's own. A sprite names
    no geometry, and its `geometry` is -1.
    """

    var node: NodeId
    var geometry: GeometryId
    var material: MaterialId
    # Which primitives the run holds, and how many: `DRAW_TRIANGLES`,
    # `DRAW_SEGMENTS` or `DRAW_POINTS`.
    var kind: DrawKind
    var count: Int
    # The node's render order, three.js's `renderOrder`.
    var order: Int
    # How far ahead of the camera the object's origin is, in meters: the
    # larger, the further. It orders as three.js's `z` does.
    var z: Float32


# How a caller orders a frame's runs, three.js's `setOpaqueSort` and
# `setTransparentSort`: True when the first is drawn before the second. A
# plain function, as three.js's is, and the sort is stable.
comptime RenderSort = def(RenderItem, RenderItem) thin -> Bool


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

    def __init__(out self):
        """Count nothing yet."""
        self.info = RenderInfo(0, 0, 0, 0, 0)
        self.shadow_items = List[RenderItem]()
        self.shadow_lights = List[Int]()

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


struct _Span(ImplicitlyCopyable):
    """One draw's run of primitives in a prepared list, with its sort key.

    What `_prepared` and `_prepared_lines` record beside the corners they
    emit, and what `prepare_frame` turns into `Draw` records: the run,
    which list it is in, how deep the draw was, whether it blends, and
    whether it transmits.
    """

    var kind: DrawKind
    # The first primitive of the run, a triangle or a segment.
    var first: Int
    var count: Int
    var depth: Float32
    var blends: Bool
    # The draw's node's render order, which sorts before the depth.
    var order: Int
    # Whether the draw's material transmits, three.js's `transmissive`
    # list: drawn after every opaque run and before every blended one.
    var transmits: Bool
    # What drew the run.
    var source: _Source

    def __init__(
        out self,
        kind: DrawKind,
        first: Int,
        count: Int,
        depth: Float32,
        blends: Bool,
        order: Int,
        source: _Source,
        transmits: Bool = False,
    ):
        """Record one run.

        Args:
            kind: Which list the run is in.
            first: Its first primitive.
            count: How many primitives it holds.
            depth: The draw's camera-space depth.
            blends: Whether its material blends.
            order: Its node's render order.
            source: What drew it.
            transmits: Whether its material transmits. Only a filled
                surface can.
        """
        self.kind = kind
        self.first = first
        self.count = count
        self.depth = depth
        self.blends = blends
        self.order = order
        self.source = source
        self.transmits = transmits

    def item(self) -> RenderItem:
        """Return the run as a hook and a sort see it."""
        return RenderItem(
            self.source.node,
            self.source.geometry,
            self.source.material,
            self.kind,
            self.count,
            self.order,
            -self.depth,
        )


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
    for index in range(len(scene.meshes)):
        ref mesh = scene.meshes[index]
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
                mesh.frustum_culled and not mesh.is_morphed(),
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
    for index in range(len(scene.skinned_meshes)):
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
    for index in range(len(scene.instanced_meshes)):
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
    for index in range(len(scene.batched_meshes)):
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
    for index in range(len(scene.sprites)):
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
    # `LineSegments2` is: the width is not added to it. A light's view of
    # the casters holds none, as it holds no sprite.
    var wide_count = 0 if casters_only else len(scene.wide_lines)
    for index in range(wide_count):
        ref line = scene.wide_lines[index]
        if not scene.shows(line.node, visible):
            continue
        var world = scene.world_matrix(line.node)
        if line.frustum_culled and not _in_view(
            assets, line.geometry, world, frustum, slack, bounds, known
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

    var solid = List[Int]()
    var solid_depths = List[Float32]()
    var solid_orders = List[Int]()
    var see_through = List[Int]()
    var see_through_depths = List[Float32]()
    var see_through_orders = List[Int]()
    for index in range(len(draws)):
        if clear[index]:
            see_through.append(index)
            see_through_depths.append(depths[index])
            see_through_orders.append(draws[index].order)
        else:
            solid.append(index)
            # Negated, so one ascending sort serves both lists: the nearest
            # opaque draw has the largest z and must come first.
            solid_depths.append(-depths[index])
            solid_orders.append(draws[index].order)
    _sort_by(solid, solid_depths, solid_orders)
    _sort_by(see_through, see_through_depths, see_through_orders)
    var ordered = List[_Draw]()
    for position in range(len(solid)):
        ordered.append(draws[solid[position]])
    for position in range(len(see_through)):
        ordered.append(draws[see_through[position]])
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


def _sort_by(
    mut items: List[Int], mut keys: List[Float32], mut orders: List[Int]
):
    """Sort `items` by render order, then by `keys`, ascending, in place
    and stably.

    Insertion sort: the lists are one entry per draw, hundreds in a busy
    scene rather than millions, and a stable order keeps draws at equal
    order and depth in the order the caller gave them.
    """
    for position in range(len(items)):
        var item = items[position]
        var key = keys[position]
        var order = orders[position]
        var slot = position
        while slot > 0 and _after(orders[slot - 1], keys[slot - 1], order, key):
            items[slot] = items[slot - 1]
            keys[slot] = keys[slot - 1]
            orders[slot] = orders[slot - 1]
            slot -= 1
        items[slot] = item
        keys[slot] = key
        orders[slot] = order


def _after(
    order: Int, key: Float32, other_order: Int, other_key: Float32
) -> Bool:
    """Return True if an entry sorts after another: a higher render order,
    or the same order and a larger key."""
    return order > other_order or (order == other_order and key > other_key)


def _sort_with(mut runs: List[_Span], before: RenderSort):
    """Sort runs in place, stably, by a caller's function, three.js's
    custom sort: a run moves in front of the one before it while the
    function says it is drawn first."""
    for position in range(1, len(runs)):
        var held = runs[position]
        var slot = position
        while slot > 0 and before(held.item(), runs[slot - 1].item()):
            runs[slot] = runs[slot - 1]
            slot -= 1
        runs[slot] = held


def _furthest_first(mut runs: List[_Span], custom: Optional[RenderSort]):
    """Sort blended or transmissive runs in place: by the caller's
    transparent sort when there is one, and otherwise by render order
    and then furthest first, as `_draws` sorts its translucent draws."""
    var sorted = Bool(custom)
    if sorted:
        _sort_with(runs, custom.value())
        return
    var order = List[Int]()
    var depths = List[Float32]()
    var orders = List[Int]()
    for position in range(len(runs)):
        order.append(position)
        depths.append(runs[position].depth)
        orders.append(runs[position].order)
    _sort_by(order, depths, orders)
    var kept = runs.copy()
    for position in range(len(order)):
        runs[position] = kept[order[position]]


def _add_run(mut draws: List[Draw], mut items: List[RenderItem], run: _Span):
    """Append one run to a frame's draw order, and its item beside it."""
    draws.append(Draw(run.kind, run.first, run.count))
    items.append(run.item())


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
        Error: If the view cannot be inverted.
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
        return corner^

    def emit(
        self,
        mut corners: List[RasterVertex],
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
        var one = self.raster(a)
        var two = self.raster(b)
        var three = self.raster(c)
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
        if self.side == BACK_SIDE or (self.side == DOUBLE_SIDE and away):
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


def _column_length(matrix: Matrix4, axis: Int) -> Float32:
    """Return the length of one of a matrix's three axis columns: how much
    it scales along that axis, three.js's `length(modelMatrix[axis].xyz)`.

    Args:
        matrix: The transform.
        axis: Which column, zero for x through two for z.

    Returns:
        The length.
    """
    ref e = matrix.elements
    var start = axis * 4
    var x = e[start]
    var y = e[start + 1]
    var z = e[start + 2]
    return Vector3(x, y, z).length()


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
    if map.value >= assets.textures.count():
        raise Error(name + " is named that is not there")
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
    if map.value >= assets.textures.count():
        raise Error(name + " is named that is not there")


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
    if map != NO_TEXTURE and map.value >= assets.textures.count():
        raise Error("A material names a texture that is not there")
    if shading != SHADE_TEXTURE:
        map = NO_TEXTURE
    var mask = material.alpha_map
    if mask != NO_TEXTURE and mask.value >= assets.textures.count():
        raise Error("A material names an alpha map that is not there")
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
    mut corners: List[RasterVertex],
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
    _refuse_nodes(material, "A sprite")
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
    var scale_x = _column_length(world, 0)
    var scale_y = _column_length(world, 1)
    if not material.size_attenuation and perspective:
        scale_x *= -center.z
        scale_y *= -center.z
    var turn = material.rotation.to(RADIAN)
    var turned_x = cos(turn)
    var turned_y = sin(turn)
    var base = _with_opacity(FloatColor(srgb=material.color), material.opacity)
    # The unit square's corners and their coordinates, counterclockwise
    # from the bottom left: three.js's sprite geometry.
    var xs: List[Float32] = [-0.5, 0.5, 0.5, -0.5]
    var ys: List[Float32] = [-0.5, -0.5, 0.5, 0.5]
    var quad = List[ClipVertex]()
    for corner in range(4):  # pragma: no branch
        var aligned_x = (xs[corner] - (sprite.center.x - 0.5)) * scale_x
        var aligned_y = (ys[corner] - (sprite.center.y - 0.5)) * scale_y
        # Raw, on both pairs: each map places them for itself, and a
        # sprite has no `uv1`, so the second pair falls back to the first
        # as a mesh's does.
        var raw = Vector2(xs[corner] + 0.5, ys[corner] + 0.5)
        quad.append(
            ClipVertex(
                Vector3(
                    center.x + turned_x * aligned_x - turned_y * aligned_y,
                    center.y + turned_y * aligned_x + turned_x * aligned_y,
                    center.z,
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
        _Physics(),
        False,
        # three.js's `sprite` shader hashes its alpha, and neither dithers
        # nor premultiplies.
        _draw_state(material, casters_only, False, True, False),
        _draw_offset(material, casters_only),
        _shown_of(material),
        TextureFrames(),
    )
    var thirds: List[Int] = [2, 3]
    for half in range(2):  # pragma: no branch
        var a = quad[0]
        var b = quad[thirds[half] - 1]
        var c = quad[thirds[half]]
        if _whole_in_view(a, b, c, near, far, sides, any_of):
            paint.emit(corners, a, b, c)
            continue
        var pieces = clip_depth(a, b, c, near, far, sides, any_of)
        for piece in range(len(pieces) // 3):
            paint.emit(
                corners,
                pieces[piece * 3],
                pieces[piece * 3 + 1],
                pieces[piece * 3 + 2],
            )


def _emit_clipped(
    paint: _Paint,
    mut corners: List[RasterVertex],
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


def _between(a: ClipVertex, b: ClipVertex, t: Float32) -> ClipVertex:
    """Return the point a fraction `t` of the way along a wide segment.

    Its position, its world position, its color and its distance along
    the line, each mixed in camera space, where the segment is straight.
    That is the perspective-correct mix three.js's varyings get.
    """
    return ClipVertex(
        a.position + (b.position - a.position) * t,
        FloatColor(
            a.color.r + (b.color.r - a.color.r) * t,
            a.color.g + (b.color.g - a.color.g) * t,
            a.color.b + (b.color.b - a.color.b) * t,
            a.color.a + (b.color.a - a.color.a) * t,
        ),
        Vector3(0, 0, 1),
        0,
        0,
        a.world + (b.world - a.world) * t,
        line_distance=a.line_distance + (b.line_distance - a.line_distance) * t,
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
    mut corners: List[RasterVertex],
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


def _emit_wide_line(
    mut corners: List[RasterVertex],
    assets: Assets,
    draw: _Draw,
    view: Matrix4,
    to_screen: Matrix4,
    near: Float32,
    far: Float32,
    sides: List[Plane],
    any_of: List[Plane],
    render_scale: Int,
) raises:
    """Build a wide line's triangles in camera space and append them.

    three.js's `LineSegments2` drawn with `LineMaterial`: each segment is
    a quad, and each end of it a round cap, unless the line is dashed.
    A dashed segment is cut into a quad per dash, with no caps, as
    three.js throws the caps of a dashed line away. The segment is first
    cut to the near and the far planes, as three.js trims it to the near
    plane, so that no corner is placed from a point behind the camera. The
    triangles then go where every triangle goes: through the clipper and
    `_Paint.emit`, two-sided. See `objects.line_segments2`.

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

    Raises:
        Error: If the material is not `BASIC`, carries a map, an alpha
            map, an env map, an ao map or a light map, or is a wireframe; if the geometry is
            indexed, has no positions or an odd count of them; if the
            material asks for vertex colors the geometry does not have;
            if a dash pattern is too fine for a segment; or if the
            material's depth, color, stencil or offset state is refused.
    """
    var material = assets.materials.get(draw.material)
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
    if geometry.is_indexed():
        raise Error(
            "A wide line geometry cannot be indexed: its points are paired"
            " in the order they are given"
        )
    ref positions = geometry.attribute_view(String(POSITION))
    var count = positions.count()
    var segments = segment_count(SEGMENTS, count)
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
    var paint = _Paint(
        to_screen,
        NO_TEXTURE,
        material.blending,
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
        # three.js's `LineMaterial` premultiplies, and neither dithers nor
        # hashes its alpha.
        _draw_state(material, False, False, False, True),
        _draw_offset(material, False),
        _shown_of(material),
        TextureFrames(),
    )
    var no_planes = List[Plane]()
    for segment in range(segments):
        var ends = List[ClipVertex]()
        for side in range(2):  # pragma: no branch
            var vertex = segment * 2 + side
            var placed = world.transform_point(positions.vector3(vertex))
            ends.append(
                ClipVertex(
                    view.transform_point(placed),
                    colors[vertex],
                    Vector3(0, 0, 1),
                    0,
                    0,
                    placed,
                    line_distance=along[vertex],
                )
            )
        # Cut to the view depth only. The sides and the clipping planes
        # cut the triangles below, so a cap past the edge of the image is
        # cut where the image ends rather than moved inside it.
        var kept = clip_segment(ends[0], ends[1], near, far, no_planes)
        if len(kept) < 2:
            continue
        var start = kept[0]
        var end = kept[1]
        var ribbon = _Ribbon(
            start,
            end,
            width.world_units,
            half,
            to_screen,
            from_screen,
            to_world,
        )
        var spans = dash_spans(
            start.line_distance, end.line_distance, dash, gap
        )
        for piece in range(len(spans) // 2):
            var first = _between(start, end, spans[piece * 2])
            var second = _between(start, end, spans[piece * 2 + 1])
            var a = ribbon.corner(first, -1, 0)
            var b = ribbon.corner(first, 1, 0)
            var c = ribbon.corner(second, 1, 0)
            var d = ribbon.corner(second, -1, 0)
            _emit_clipped(paint, corners, a, b, c, near, far, sides, any_of)
            _emit_clipped(paint, corners, a, c, d, near, far, sides, any_of)
        if dashed:
            continue
        _emit_cap(ribbon, paint, corners, start, -1, near, far, sides, any_of)
        _emit_cap(ribbon, paint, corners, end, 1, near, far, sides, any_of)


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
    mut image: Framebuffer, x: Int, y: Int, color: FloatColor
) raises:
    """Write one backdrop pixel: the color encoded to sRGB bytes, opaque.

    Opaque whatever the texture's alpha said, as three.js's background
    plane is drawn opaque: a background hides nothing but the clear color.
    """
    var shown = color.encode()
    image.set_pixel(x, y, Color(shown.r, shown.g, shown.b, 255))


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


def _kept_for(kept: List[ShadowMap], light: Int) -> Int:
    """Return which of `kept` a light drew, or -1 for none."""
    for slot in range(len(kept)):
        if kept[slot].light == light:
            return slot
    return -1


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
    light: Light, at: Vector3, aimed: Vector3
) raises -> PerspectiveCamera:
    """Return a spot light's shadow camera, three.js's `SpotLightShadow`:
    twice the cone's angle times the shadow's `focus` wide, square, from
    the shadow's near plane to `Light.shadow_far`, at `at` looking at
    `aimed`.

    Raises:
        Error: If `PerspectiveCamera` refuses the planes or the angle.
    """
    var camera = PerspectiveCamera(
        light.shadow.spot_field_of_view(light.angle),
        1.0,
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


def _transmits(frame: Frame) -> Bool:
    """Return True if any triangle of a prepared frame transmits.

    Every triangle `prepare_frame` returns is one of its draws, so the
    list is asked directly.
    """
    for triangle in range(len(frame.corners) // 3):
        if frame.corners[triangle * 3].transmission > 0:
            return True
    return False


def _is_see_through(frame: Frame, draw: Draw) -> Bool:
    """Return True if a draw of a prepared frame transmits or blends:
    three.js leaves both its `transmissive` and its `transparent` lists
    out of the transmission pass."""
    if draw.kind == DRAW_TRIANGLES:
        ref first = frame.corners[draw.first * 3]
        return first.transmission > 0 or first.blend.mixes()
    if draw.kind == DRAW_SEGMENTS:
        return frame.segments[draw.first * 2].blend.mixes()
    return frame.points[draw.first].blend.mixes()


def _opaque_draws(frame: Frame) -> List[Draw]:
    """Return the draws of a prepared frame the transmission pass draws:
    three.js's `opaqueObjects`, every run that neither transmits nor
    blends, in the frame's order."""
    var kept = List[Draw]()
    # Only a frame with a transmissive run is asked, so it has a draw and
    # the loop never runs zero times.
    for index in range(len(frame.draws)):  # pragma: no branch
        if not _is_see_through(frame, frame.draws[index]):
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
    for y in range(top, top + kept.height):  # pragma: no branch
        for x in range(kept.x, kept.x + kept.width):  # pragma: no branch
            var pixel = image.get_pixel(x, y)
            if pixel.a != 255:
                continue
            target.write(x, y, FloatColor(srgb=pixel), False)


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

    # Raster vertices, three per triangle, as `prepare` returns them.
    var corners: List[RasterVertex]
    # Raster vertices, two per segment, as `prepare_lines` returns them.
    var segments: List[RasterVertex]
    # Raster vertices, one per point, as `prepare_points` returns them.
    var points: List[RasterVertex]
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
        var corners: List[RasterVertex],
        var segments: List[RasterVertex],
        var draws: List[Draw],
        var points: List[RasterVertex] = List[RasterVertex](),
        var programs: NodeProgramStore = NodeProgramStore(),
        var items: List[RenderItem] = List[RenderItem](),
    ):
        """Hold a prepared frame.

        Args:
            corners: The triangles' corners, three each.
            segments: The segments' corners, two each.
            draws: The order to draw them in.
            points: The points, one corner each. None by default.
            programs: The node programs the corners name, for this frame.
                None by default.
            items: What drew each draw. None by default.
        """
        self.corners = corners^
        self.segments = segments^
        self.draws = draws^
        self.points = points^
        self.programs = programs^
        self.items = items^


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
    # Whether `render` and `render_array` draw the frame at twice the size
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
        if width <= 0 or height <= 0:
            raise Error("Renderer dimensions must be positive")
        if workers < 1:
            raise Error("A renderer needs at least one worker")
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
        self.clipping_planes = List[Plane]()
        self.local_clipping_enabled = False
        self.shadow_map_type = PCF_SHADOW_MAP
        self.depth_mode = STANDARD_DEPTH
        self.time = Duration(0.0, SECOND)
        self.auto_clear = True
        self.auto_clear_color = True
        self.auto_clear_depth = True
        self.auto_clear_stencil = True
        self.custom_tone_mapping = NO_NODES
        self.info_auto_reset = True
        self._opaque_sort = None
        self._transparent_sort = None
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

        `render_into` and `render_array_into` draw into a target the caller
        holds, at its size, and are not changed by this.

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
        if factor < 1:
            raise Error("A renderer is scaled by at least one")
        var big = Renderer(
            self.width * factor, self.height * factor, self.workers
        )
        big.background = self.background
        big.shading = self.shading
        big.tone_mapping = self.tone_mapping
        big.tone_mapping_exposure = self.tone_mapping_exposure
        big.output_color_space = self.output_color_space
        big.override_material = self.override_material
        big.viewport = _scaled(self.viewport, factor)
        big.scissor = _scaled(self.scissor, factor)
        big.scissor_test = self.scissor_test
        # The planes cut in camera space, and the shadow filter reads the
        # light's own map, so neither changes with the frame's size.
        big.clipping_planes = self.clipping_planes.copy()
        big.local_clipping_enabled = self.local_clipping_enabled
        big.shadow_map_type = self.shadow_map_type
        big.depth_mode = self.depth_mode
        big.time = self.time
        big.auto_clear = self.auto_clear
        big.auto_clear_color = self.auto_clear_color
        big.auto_clear_depth = self.auto_clear_depth
        big.auto_clear_stencil = self.auto_clear_stencil
        big.custom_tone_mapping = self.custom_tone_mapping
        big.info_auto_reset = self.info_auto_reset
        big._opaque_sort = self._opaque_sort
        big._transparent_sort = self._transparent_sort
        # Counted into this renderer's info, not a copy of it.
        big._state = self._state
        big.ltc = self.ltc.copy()
        # What makes the larger renderer draw a frame that *averages down*
        # to this one rather than merely one that is bigger: a point's
        # size and a line's thickness are given in the output pixels this
        # renderer has, and the larger one converts them once. See
        # `render_scale`.
        big.render_scale = self.render_scale * factor
        return big^

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
        if not rect.is_valid():
            raise Error("A viewport needs a positive width and height")
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
        if not rect.fits(self.width, self.height):
            raise Error("A scissor must lie inside the target")
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
        if workers < 1:
            raise Error("A renderer needs at least one worker")
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
        if not mode.is_valid():
            raise Error("A depth mode that is none of the three")
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
            Error: If the mode is none of those three. The type stops a bare
                integer; it does not stop `ShadeMode(99)`.
        """
        if not mode.is_valid():
            raise Error("A shading mode that is none of the three")
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
        var corners = List[RasterVertex]()
        # Asked of the scene as well as the camera: a camera riding a node
        # looks from wherever the scene put that node.
        var view = camera.view_matrix_in(scene)
        var to_screen = self._to_screen(camera)
        var near = camera.near_distance()
        var far = camera.far_distance()
        # What the camera can see, in world space, where the meshes' bounds
        # are: three.js's `_projScreenMatrix` read as four side planes, and
        # the near and far distances the clipper below is given, as the
        # two depth planes.
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var frustum = Frustum.from_camera(clip, view, near, far)
        # The same four sides in camera space, where the clipper cuts.
        # With a viewport smaller than the target, "off the image" is
        # still on the target, and only a cut keeps it off; see
        # `renderers.clip`.
        var sides = Frustum.side_planes(camera.projection_matrix())
        # The renderer's clipping planes, carried into camera space once.
        var global_planes = _planes_in_view(self.clipping_planes, view)

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
        )
        # Whether the camera's rays converge, for a sprite that keeps its
        # size on the image; see `_emit_sprite`.
        var perspective = not camera.projection_matrix().is_affine()
        for slot in range(len(draws)):
            if draws[slot].wide_line >= 0:
                # A wide line is drawn as triangles, so it is a filled
                # surface and is left out of the wireframe half. Its
                # triangles are built from its pairs of points; see
                # `_emit_wide_line`. It never transmits.
                if wireframe or transmissive_backs:
                    continue
                var wide_begin = len(corners)
                var wide_cut = List[Plane]()
                var wide_any = List[Plane]()
                _clip_sets(
                    assets.materials.get(draws[slot].material),
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
                var begin = len(corners)
                var sprite_cut = List[Plane]()
                var sprite_any = List[Plane]()
                _clip_sets(
                    assets.materials.get(draws[slot].material),
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
            _clip_sets(
                material,
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
            # Checked here because here is the first place that can: a
            # material is built without the store in reach, so a positive id
            # naming nothing is only detectable once both are together. It is
            # checked before rasterization rather than during, so the answer
            # does not depend on which pixels the mesh happened to cover.
            if map != NO_TEXTURE and map.value >= assets.textures.count():
                raise Error("A material names a texture that is not there")
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
            if (
                glow_map != NO_TEXTURE
                and assets.textures.get(glow_map).alpha != IGNORED
            ):
                raise Error(
                    "A material's emissive map must ignore its alpha; build"
                    " the texture with alpha=IGNORED"
                )
            if self.shading != SHADE_TEXTURE or not material.is_emissive():
                glow_map = NO_TEXTURE
            # The alpha map, checked the same way, and refused unless it is
            # stored as data: its green channel is a coverage, and the sRGB
            # curve and a coverage-weighted filter each change what it
            # means. Refused whatever the shading mode, as the emissive
            # map's alpha mode is: a wrong asset, not a wrong frame.
            var mask = material.alpha_map
            if mask != NO_TEXTURE and mask.value >= assets.textures.count():
                raise Error("A material names an alpha map that is not there")
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
            if (
                ball != NO_TEXTURE
                and assets.textures.get(ball).alpha != IGNORED
            ):
                raise Error(
                    "A matcap must ignore its alpha; build the texture with"
                    " alpha=IGNORED"
                )
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
                    material.thickness.to(METER) * _column_length(world, 0),
                    material.thickness.to(METER) * _column_length(world, 1),
                    material.thickness.to(METER) * _column_length(world, 2),
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

            # Texture coordinates do not go through the world transform:
            # they name a place in an image, not a place in the world. Nor
            # through any texture's transform: each map moves them at the
            # fragment by its own, as three.js's `uv_vertex` makes a
            # varying per map. A geometry without them gets zeroes, which
            # map everything to one place -- harmless until something is
            # actually sampled with them.
            var first_set = _coordinates(geometry, String(UV), vertex_count)
            ref vertex_u = first_set[0]
            ref vertex_v = first_set[1]
            # The second pair, which a map on `UV_CHANNEL_1` reads: the
            # geometry's `uv1` when it has one, and its `uv` otherwise.
            var second_name = String(UV)
            if geometry.has_attribute(String(UV1)):
                second_name = String(UV1)
            var second_set = _coordinates(geometry, second_name, vertex_count)
            ref vertex_u1 = second_set[0]
            ref vertex_v1 = second_set[1]

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
                if indices[slot] >= vertex_count:
                    raise Error("An index entry points past the last vertex")
            # The run this draw fills: a group of a mesh that wears a
            # material list, or the whole stream, inside the geometry's
            # draw range. See `drawn_run`.
            var run = geometry.drawn_run(
                draws[slot].group_start, draws[slot].group_count
            )
            var run_start = run[0]
            var triangles = run[1]
            # Grown once per draw rather than by doubling as corners arrive,
            # which copied the frame's whole list several times over: three
            # corners a triangle, before the clipper adds any or the facing
            # test drops any.
            corners.reserve(len(corners) + triangles * 3)
            var begin = len(corners)
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
            for triangle in range(triangles):
                var first = run_start + triangle * 3
                var second = first + 1
                var third = first + 2
                if indexed:
                    first = indices[first]
                    second = indices[second]
                    third = indices[third]

                var normal_a: Vector3
                var normal_b: Vector3
                var normal_c: Vector3
                if smooth:
                    normal_a = vertex_normals[first]
                    normal_b = vertex_normals[second]
                    normal_c = vertex_normals[third]
                else:
                    # No normals given, so the face supplies its own and the
                    # whole triangle takes one.
                    var geometric = face_normal(
                        world_points[first],
                        world_points[second],
                        world_points[third],
                    )
                    if mirrored:
                        # The cross product follows the mirrored winding, so
                        # it comes out pointing into the surface. A supplied
                        # normal carried through the inverse transpose does
                        # not flip, and the two paths have to mean the same
                        # side or an object would shade differently purely
                        # for having normals.
                        geometric = -geometric
                    if kind == NORMALS:
                        # Into view space, as the supplied normals were.
                        geometric = view.transform_direction(geometric)
                    normal_a = geometric
                    normal_b = geometric
                    normal_c = geometric

                var corner_a = ClipVertex(
                    view_points[first],
                    vertex_colors[first],
                    normal_a,
                    vertex_u[first],
                    vertex_v[first],
                    world_points[first],
                    glow,
                    u1=vertex_u1[first],
                    v1=vertex_v1[first],
                )
                var corner_b = ClipVertex(
                    view_points[second],
                    vertex_colors[second],
                    normal_b,
                    vertex_u[second],
                    vertex_v[second],
                    world_points[second],
                    glow,
                    u1=vertex_u1[second],
                    v1=vertex_v1[second],
                )
                var corner_c = ClipVertex(
                    view_points[third],
                    vertex_colors[third],
                    normal_c,
                    vertex_u[third],
                    vertex_v[third],
                    world_points[third],
                    glow,
                    u1=vertex_u1[third],
                    v1=vertex_v1[third],
                )
                # A triangle wholly between the two planes is what the
                # clipper would hand back untouched, so it is not sent
                # through: the clipper builds four lists for every triangle
                # it is given, and a mesh in view gives it thousands that
                # it would return as they came. See `within_depth`.
                if _whole_in_view(
                    corner_a, corner_b, corner_c, near, far, cut, any_of
                ):
                    paint.emit(corners, corner_a, corner_b, corner_c)
                    continue
                var pieces = clip_depth(
                    corner_a, corner_b, corner_c, near, far, cut, any_of
                )
                for piece in range(len(pieces) // 3):
                    paint.emit(
                        corners,
                        pieces[piece * 3],
                        pieces[piece * 3 + 1],
                        pieces[piece * 3 + 2],
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
                material.transmits(),
            )

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
        var view = camera.view_matrix_in(scene)
        var to_screen = self._to_screen(camera)
        var near = camera.near_distance()
        var far = camera.far_distance()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var frustum = Frustum.from_camera(clip, view, near, far)
        # The same four sides in camera space, where the clipper cuts.
        # With a viewport smaller than the target, "off the image" is
        # still on the target, and only a cut keeps it off; see
        # `renderers.clip`.
        var sides = Frustum.side_planes(camera.projection_matrix())
        var global_planes = _planes_in_view(self.clipping_planes, view)
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
            if casters_only and not _casts(
                line.cast_shadow, line.receive_shadow, receivers_cast
            ):
                continue
            if not scene.shows(line.node, camera.visible_layers()):
                continue
            var world = scene.world_matrix(line.node)
            if line.frustum_culled and not _in_view(
                assets, line.geometry, world, frustum, slack, bounds, known
            ):
                continue
            var depth = view.transform_point(
                Vector3(
                    world.elements[12], world.elements[13], world.elements[14]
                )
            ).z
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
            _refuse_nodes(material, "A line")
            # A dashed line is three.js's `dashed` shader, which does not
            # dither; a plain one is its `basic` shader, which does. A
            # light's view takes the default state; see `_draw_state`.
            var state = _draw_state(
                material, casters_only, not material.is_dashed(), False, True
            )
            var shown = _shown_of(material)
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_sets(
                material,
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
            var world_points = List[Vector3]()
            var view_points = List[Vector3]()
            for vertex in range(vertex_count):
                var point = world.transform_point(
                    Vector3(
                        positions.component(vertex, 0),
                        positions.component(vertex, 1),
                        positions.component(vertex, 2),
                    )
                )
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
                # The normal is zero and the texture coordinates are zero
                # because nothing reads either: the kind is unlit and there
                # is no map. Carrying the material color, the world
                # position and the distance along the line is the whole of
                # what a segment varies.
                var kept = clip_segment(
                    ClipVertex(
                        view_points[first],
                        colors[first],
                        Vector3(0, 0, 0),
                        0,
                        0,
                        world_points[first],
                        line_distance=along[first],
                    ),
                    ClipVertex(
                        view_points[second],
                        colors[second],
                        Vector3(0, 0, 0),
                        0,
                        0,
                        world_points[second],
                        line_distance=along[second],
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
                            state=state,
                            shown=shown,
                        )
                    )
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
        var solid = List[Int]()
        var solid_depths = List[Float32]()
        var solid_orders = List[Int]()
        var see_through = List[Int]()
        var see_through_depths = List[Float32]()
        var see_through_orders = List[Int]()
        for position in range(len(unsorted)):
            if unsorted[position].blends:
                see_through.append(position)
                see_through_depths.append(unsorted[position].depth)
                see_through_orders.append(unsorted[position].order)
            else:
                solid.append(position)
                solid_orders.append(unsorted[position].order)
                # Negated so one ascending sort serves both lists, as in
                # `_draws`: the nearest opaque line has the largest z.
                solid_depths.append(-unsorted[position].depth)
        _sort_by(solid, solid_depths, solid_orders)
        _sort_by(see_through, see_through_depths, see_through_orders)
        var order = List[Int]()
        for position in range(len(solid)):
            order.append(solid[position])
        for position in range(len(see_through)):
            order.append(see_through[position])
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
        var view = camera.view_matrix_in(scene)
        var to_screen = self._to_screen(camera)
        var near = camera.near_distance()
        var far = camera.far_distance()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var frustum = Frustum.from_camera(clip, view, near, far)
        var sides = Frustum.side_planes(camera.projection_matrix())
        var global_planes = _planes_in_view(self.clipping_planes, view)
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
            if casters_only and not _casts(
                points.cast_shadow, points.receive_shadow, receivers_cast
            ):
                continue
            if not scene.shows(points.node, camera.visible_layers()):
                continue
            var world = scene.world_matrix(points.node)
            if points.frustum_culled and not _in_view(
                assets, points.geometry, world, frustum, slack, bounds, known
            ):
                continue
            var depth = view.transform_point(
                Vector3(
                    world.elements[12], world.elements[13], world.elements[14]
                )
            ).z
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
            _refuse_nodes(material, "A point")
            # three.js's `points` shader premultiplies and does not dither.
            # A light's view takes the default state; see `_draw_state`.
            var state = _draw_state(material, casters_only, False, False, True)
            var shown = _shown_of(material)
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_sets(
                material,
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
            # Only the points the draw range lets through.
            var ranged = geometry.drawn_vertices()
            for vertex in range(ranged[0], ranged[0] + ranged[1]):
                var point = world.transform_point(
                    Vector3(
                        positions.component(vertex, 0),
                        positions.component(vertex, 1),
                        positions.component(vertex, 2),
                    )
                )
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
                corners.append(
                    _to_raster(
                        ClipVertex(
                            seen,
                            colors[vertex],
                            Vector3(0, 0, 0),
                            0,
                            0,
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
                        point_size=Float32(1) if casters_only else (
                            attenuated_size(
                                material.point_size.pixels,
                                seen.z,
                                scale,
                                perspective and material.size_attenuation,
                                self.render_scale,
                            )
                        ),
                        state=state,
                        shown=shown,
                    )
                )
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
        var solid = List[Int]()
        var solid_depths = List[Float32]()
        var solid_orders = List[Int]()
        var see_through = List[Int]()
        var see_through_depths = List[Float32]()
        var see_through_orders = List[Int]()
        for position in range(len(unsorted)):
            if unsorted[position].blends:
                see_through.append(position)
                see_through_depths.append(unsorted[position].depth)
                see_through_orders.append(unsorted[position].order)
            else:
                solid.append(position)
                solid_orders.append(unsorted[position].order)
                solid_depths.append(-unsorted[position].depth)
        _sort_by(solid, solid_depths, solid_orders)
        _sort_by(see_through, see_through_depths, see_through_orders)
        var order = List[Int]()
        for position in range(len(solid)):
            order.append(solid[position])
        for position in range(len(see_through)):
            order.append(see_through[position])
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
    ](self, scene: Scene, assets: Assets, camera: C,) raises -> Frame:
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

        Returns:
            The frame. `Renderer.render` fills it with `rasterize_frame`
            and `GpuRenderer.draw` takes its four lists as they are.

        Raises:
            Error: Everything `prepare`, `prepare_lines` and
                `prepare_points` raise, and anything `camera` raises for
                its view.
        """
        var corner_spans = List[_Span]()
        var corners = self._prepared(scene, assets, camera, False, corner_spans)
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
        _furthest_first(mixed, self._transparent_sort)
        for position in range(len(mixed)):
            _add_run(draws, items, mixed[position])
        # The node programs, with this frame's time and view written in, as
        # three.js updates its `time` and camera nodes before a frame.
        var programs = assets.programs.copy()
        programs.set_frame(self.time, camera.view_matrix_in(scene))
        return Frame(corners^, segments^, draws^, points^, programs^, items^)

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
        if target.width != self.width or target.height != self.height:
            raise Error("A target must be the renderer's size")
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
                self._draw_into(
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
        if target.width != self.width or target.height != self.height:
            raise Error("A target must be the renderer's size")
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
        self._draw_into(hooks, target, scene, assets, camera, True)

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
        self._draw_into(hooks, target, scene, assets, camera, True)

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
    ) raises:
        """Draw every mesh in the scene on the CPU into `target`, clearing
        first, and resolve nothing.

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
        if target.width != self.width or target.height != self.height:
            raise Error("A target must be the renderer's size")
        if target.samples > 1:
            # three.js's multisampled render target: the samples are drawn
            # by a renderer `sample_grid` times the size, which refuses a
            # scene before its buffer is touched, and resolved into the
            # target once the draw is done. Only the pixels the draw may
            # touch are resolved, so a scissor keeps the rest.
            var buffer = target.multisample_buffer()
            self.multisampled(target.samples)._draw_into(
                hooks, buffer, scene, assets, camera, first
            )
            var drawn = Rect.whole(self.width, self.height)
            if self.scissor_test:
                drawn = self.scissor
            target.resolve_samples(buffer, drawn)
            target.set_scissor(drawn)
            return
        hooks.on_before_scene(scene)
        # Prepared and checked before a pixel is touched, so a scene that
        # is refused leaves a target another view was drawn into as it was.
        var frame = self.prepare_frame(scene, assets, camera)
        # Two output representations cannot share a tone-mapped frame. Asked
        # here, before anything is drawn, exactly where `GpuRenderer.draw`
        # asks it before a launch. The uv view is data throughout and is
        # never tone mapped, so it is never refused; see below.
        check_output_kinds(
            frame.corners,
            self.shading != SHADE_UV and self.tone_mapping != NO_TONE_MAPPING,
            frame.segments,
            frame.points,
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
        var lighting = self._lighting(scene, assets, camera)
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
            frame, scene, assets, camera, lighting, fog, backdrop
        )
        _ = self.curve_program(assets)
        if first:
            state.begin_frame(self.info_auto_reset)
        state.count(frame.items)
        for index in range(len(frame.items)):
            hooks.on_before_render(scene, frame.items[index])
        if self.auto_clear:
            target.clear_inside(
                kept,
                self.clear_color(scene),
                self.depth_mode_for(camera),
                self.auto_clear_color,
                self.auto_clear_depth,
                self.auto_clear_stencil,
            )
        # Spelled as a Bool rather than testing the Optional directly,
        # because the coverage instrumenter wraps every condition in a
        # probe that takes a Bool; see `materials.material`.
        var painted = Bool(backdrop)
        if painted:
            _paint_backdrop(target, kept, backdrop.value())
        # Triangles, segments and points in the frame's one order, which
        # is the order the kernel walks too. See
        # `render.rasterizer.rasterize_frame` and `prepare_frame`.
        rasterize_frame(
            frame.corners,
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
        )
        for index in range(len(frame.items)):
            hooks.on_after_render(scene, frame.items[index])
        hooks.on_after_scene(scene)

    def _lighting[
        C: Camera
    ](self, scene: Scene, assets: Assets, camera: C) raises -> Lighting:
        """Return the scene's lights as `render_into` resolves them for
        this camera: the ones on its layers, its shadows, and where it
        stands."""
        return Lighting(
            scene,
            visible=camera.visible_layers(),
            eye=camera_position(scene, camera),
            toward_eye=toward_camera(scene, camera),
            up=camera_up(scene, camera),
            shadows=self.shadow_maps(scene, assets, camera.visible_layers()),
            ltc=self.ltc_tables(),
            spot_maps=self._projected(scene, assets, camera.visible_layers()),
            back=camera_back(scene, camera),
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
        Empty when nothing in the frame transmits or the shading mode is
        not `SHADE_TEXTURE`.

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
    ) raises -> TransmissionTarget:
        """Draw the opaque part of a prepared frame into a target of its
        own and return it with its chain: three.js's
        `renderTransmissionPass`.

        The clear color, or white at half alpha when the clear color is
        not opaque, as three.js clears the pass. Then the background, the
        runs that neither transmit nor blend with no tone mapping, as
        three.js turns it off for the pass, and the chain. Then the back
        faces of every two-sided transmissive mesh, each looking through
        what was drawn so far, and the chain again. A frame that does not
        transmit, or a mode that opens no texture, draws nothing and
        returns an empty target.

        Args:
            frame: The frame, prepared.
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera.
            lighting: The scene's lights, as `_lighting` resolves them.
            fog: The scene's fog, checked.
            backdrop: The scene's image background, or none.

        Returns:
            The target, empty when nothing needs it.

        Raises:
            Error: Everything `rasterize_frame` raises.
        """
        if self.shading != SHADE_TEXTURE or not _transmits(frame):
            return TransmissionTarget()
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
        rasterize_frame(
            frame.corners,
            frame.segments,
            _opaque_draws(frame),
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
        )
        var view = self.to_target(scene, camera)
        var seen = TransmissionTarget(drawn, view)
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
        )
        return TransmissionTarget(drawn, view)

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
            visible: The camera's layers; a light on none of them draws
                nothing, as `Lighting` leaves it out.
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
        if not self.shadow_map_type.is_valid():
            raise Error("A shadow map type that is none of the four")
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
            var reused = _kept_for(kept, index)
            if shadow.is_frozen() and reused >= 0:
                maps.append(kept.pop(reused))
                continue
            if light.kind == POINT:
                maps.append(self._cube_shadow(scene, assets, light, index))
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
                var camera = _spot_camera(light, at, aimed)
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
                )
            )
        return maps^

    def _cube_shadow(
        self,
        scene: Scene,
        assets: Assets,
        light: Light,
        index: Int,
    ) raises -> ShadowMap:
        """Draw a point light's six faces and return them as its cube."""
        ref shadow = light.shadow
        var size = shadow.map_size
        var at = scene.world_position(light.node)
        var near = shadow.near.to(METER)
        var far = light.shadow_far().to(METER)
        var depths = List[Float32](capacity=CUBE_FACES * size * size)
        for face in range(CUBE_FACES):  # pragma: no branch
            var camera = PerspectiveCamera(
                Angle(90.0, DEGREE), 1.0, shadow.near, light.shadow_far()
            )
            camera.up = cube_up(face)
            camera.place(at, at + cube_direction(face))
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
        )

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
            var camera = _spot_camera(light, at, _light_aim(scene, light))
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
        shading with no lights. A point light's view, `distance`, draws a
        mesh's custom distance material.

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
        var corners = square._prepared(
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
        # the other.
        var draws: List[Draw] = [
            Draw(DRAW_TRIANGLES, 0, len(corners) // 3),
            Draw(DRAW_SEGMENTS, 0, len(segments) // 2),
            Draw(DRAW_POINTS, 0, len(points)),
        ]
        var target = RenderTarget(size, size, Color(0, 0, 0))
        rasterize_frame(
            corners,
            segments,
            draws,
            target,
            SHADE_LIT,
            TextureStore(),
            Lighting.uniform(),
            self.workers,
            points=points,
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
                        var u = (Float32(x - viewport.x) + 0.5) / Float32(
                            viewport.width
                        )
                        var v = 1 - (Float32(y - top) + 0.5) / Float32(
                            viewport.height
                        )
                        _set_backdrop(
                            image,
                            x,
                            y,
                            _brightened(picture.sample(u, v), shown),
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
        for y in range(self.height):  # pragma: no branch
            for x in range(self.width):  # pragma: no branch
                if not kept.contains_pixel(
                    x, y, self.height
                ) or not viewport.contains_pixel(x, y, self.height):
                    continue
                var ndc_x = (Float32(x - viewport.x) + 0.5) / Float32(
                    viewport.width
                ) * 2 - 1
                var ndc_y = (
                    1 - (Float32(y - top) + 0.5) / Float32(viewport.height) * 2
                )
                var near = unproject.transform_point(Vector3(ndc_x, ndc_y, -1))
                var far = unproject.transform_point(Vector3(ndc_x, ndc_y, 1))
                var looked = spin.turn(to_world.transform_direction(far - near))
                var seen: FloatColor
                if backdrop.kind == TEXTURE_BACKGROUND:
                    seen = _panorama_seen(
                        assets.textures.get(backdrop.texture), looked, blur
                    )
                else:
                    seen = _sky_seen(
                        assets.cube_textures.get(backdrop.cube), looked, blur
                    )
                _set_backdrop(image, x, y, _brightened(seen, shown))
        return image^

    def render_cube(
        self, scene: Scene, assets: Assets, camera: CubeCamera
    ) raises -> CubeTexture:
        """Draw the scene six times from one point, once along each axis,
        and return the six views as a cube texture: three.js's
        `CubeCamera.update(renderer, scene)`.

        Each face is drawn by a renderer of the face's size with this
        one's background, shading and workers, through `render`, so the
        scene's own background and every material are in the faces.
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
        var side = Renderer(camera.size, camera.size, self.workers)
        side.background = self.background
        side.shading = self.shading
        side.antialias = self.antialias
        side.depth_mode = self.depth_mode
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
        one's background, shading, workers and depth mode, as
        `render_cube` draws them, into `target.image(face, 0)`. The faces
        keep the light as the target's type stores it. Call
        `target.generate_mipmaps` to fill the levels below.

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
        var side = Renderer(target.width, target.width, self.workers)
        side.background = self.background
        side.shading = self.shading
        side.depth_mode = self.depth_mode
        for face in range(FACE_COUNT):  # pragma: no branch
            side.render_into(
                target.image(face, 0),
                scene,
                assets,
                camera.face_camera(face, scene),
            )
