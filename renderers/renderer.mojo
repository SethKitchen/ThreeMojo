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
    morphed_normals,
    morphed_positions,
    skin_carriers,
    skin_pose,
)
from core.buffer_geometry import (
    COLOR,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
)
from core.assets import Assets
from core.geometry_store import GeometryId
from core.fog import FogView
from lights.light import DIRECTIONAL, SPOT
from lights.lighting import PERSPECTIVE_VIEW, Lighting
from lights.shadow import ShadowMap
from lights.ltc import LtcTables
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.bounds import Plane, Sphere
from math.frustum import Frustum
from math.matrix3 import Matrix3
from render.rect import Rect
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
from objects.instanced_mesh import check_placing
from geometries.edges import triangle_edges
from objects.line import SEGMENTS, line_distances, segment_count, segment_ends
from objects.line_segments2 import cap_steps, dash_spans
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
    MULTIPLY_OPERATION,
    NO_DASH,
    NORMALS,
    Blending,
    Combine,
    Material,
    MaterialId,
    MaterialKind,
    Side,
)
from render.antialias import SUPERSAMPLE
from render.cube_texture import FACE_COUNT, CubeTexture, cube_texture_of
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from units.si import Angle, Length, METER, RADIAN
from render.pointrule import attenuated_size
from render.texture import IGNORED
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from render.raster_state import NO_OFFSET, PolygonOffset, RasterState
from render.tonemap import NO_TONE_MAPPING, ToneMapping, check_tone_mapping
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
    RasterVertex,
    ShadeMode,
    check_alpha_map,
    check_data_map,
    check_gradient_map,
    check_output_kinds,
    edge,
    rasterize_all,
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
    geometry: BufferGeometry, tinted: Bool, base: FloatColor, count: Int
) raises -> List[FloatColor]:
    """Return the color each vertex carries: `base` for every one, or
    `base` times the geometry's `color` attribute when the material asks,
    three.js's `vertexColors`.

    The attribute holds three or four floats per vertex in linear light,
    as three.js's does since its color management, and a fourth float
    multiplies the alpha. It is checked here, once per mesh, rather than
    left to read garbage: a material that asks for colors from a geometry
    without them is a wrong asset, not a wrong frame, and so is an
    attribute with the wrong shape or too few colors.

    Args:
        geometry: The geometry, for its `color` attribute.
        tinted: Whether the material asks for vertex colors.
        base: The material's color, linear, with its opacity in alpha.
        count: How many vertices the geometry has.

    Returns:
        One color per vertex.

    Raises:
        Error: If `tinted` and the geometry has no `color` attribute, or
            the attribute holds neither three nor four floats per vertex,
            or holds a color count that is not the vertex count.
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
    if tints.count() != count:
        raise Error("A color attribute must hold one color per vertex")
    for vertex in range(count):
        var alpha = Float32(1)
        if channels == 4:
            alpha = tints.component(vertex, 3)
        colors[vertex] = FloatColor(
            base.r * tints.component(vertex, 0),
            base.g * tints.component(vertex, 1),
            base.b * tints.component(vertex, 2),
            base.a * alpha,
        )
    return colors^


def _uv_transform(assets: Assets, material: Material) raises -> Matrix3:
    """Return the transform a mesh's texture coordinates go through before
    its maps are sampled with them: its map's `uv_transform`, three.js's
    `mapTransform`.

    A fragment carries one coordinate pair and samples every map with it,
    where three.js carries a pair per map. So the first map the material
    names decides the transform, and the others must agree with it, which
    is asked here rather than left to sample a map somewhere the author did
    not say. Two maps from one image agree by construction:
    `Texture.ignoring_alpha` copies the transform.

    Args:
        assets: Where the textures live. The ids are already checked.
        material: The material, for which maps it names.

    Returns:
        The matrix. The identity for a material with no map at all.

    Raises:
        Error: If the material names two maps whose transforms differ.
    """
    var named: List[TextureId] = [
        material.map,
        material.emissive_map,
        material.alpha_map,
        material.roughness_map,
        material.metalness_map,
        material.normal_map,
        material.bump_map,
    ]
    var chosen = Matrix3()
    var settled = False
    # Seven maps, always, so the loop never runs zero times.
    for index in range(len(named)):  # pragma: no branch
        if named[index] == NO_TEXTURE:
            continue
        var to_uv = assets.textures.get(named[index]).uv_transform()
        if not settled:
            chosen = to_uv^
            settled = True
        elif to_uv != chosen:
            raise Error(
                "A material's maps must share one transform: a fragment"
                " samples them all at one coordinate"
            )
    return chosen^


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

    What a mesh is; what each instance of an instanced or batched mesh
    is, with the instance's matrix folded into the node's; and what the
    level an LOD picks is. `prepare` reads the scene as a list of these,
    so that everything after the draw order is written once.
    """

    var geometry: GeometryId
    var material: MaterialId
    var world: Matrix4
    # How much of each of the geometry's morph targets this draw wears.
    # A mesh's own; all zero for an instance, a batch member or an LOD
    # level, none of which three.js morphs either.
    var morph_influences: SIMD[DType.float32, MAX_MORPH_TARGETS]
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


@fieldwise_init
struct _Span(ImplicitlyCopyable):
    """One draw's run of primitives in a prepared list, with its sort key.

    What `_prepared` and `_prepared_lines` record beside the corners they
    emit, and what `prepare_frame` turns into `Draw` records: the run,
    which list it is in, how deep the draw was, and whether it blends.
    """

    var kind: DrawKind
    # The first primitive of the run, a triangle or a segment.
    var first: Int
    var count: Int
    var depth: Float32
    var blends: Bool
    # The draw's node's render order, which sorts before the depth.
    var order: Int


def _note_span(
    mut spans: List[_Span],
    kind: DrawKind,
    begin: Int,
    end: Int,
    depth: Float32,
    blends: Bool,
    order: Int,
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
    """
    var stride = kind.stride()
    var count = (end - begin) // stride
    if count > 0:
        spans.append(_Span(kind, begin // stride, count, depth, blends, order))


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
    morph_influences: SIMD[DType.float32, MAX_MORPH_TARGETS] = SIMD[
        DType.float32, MAX_MORPH_TARGETS
    ](0),
    skin: Int = -1,
    receive_shadow: Bool = False,
    colors: List[Color] = List[Color](),
) raises:
    """Add the draws of one scene object to `draws`, each with its sort
    key alongside, unless the camera leaves it out.

    An object is a mesh, every instance of an instanced or batched mesh,
    or the level an LOD shows: one node, one material, and a geometry and
    a matrix per draw. It is left out whole when its node shares no layer
    with the camera, three.js's `layers.test` in `projectObject`, before
    anything is measured for it. Each draw is left out on its own when
    its bound lies wholly outside the frustum, three.js's `frustumCulled`
    test in the same function, unless the object opted out; three.js
    tests an instanced mesh by one bound around every instance, and a
    test per instance is what lets the instances behind the camera cost
    nothing. Of a draw left out here only the positions are read, for the
    bound: its material's textures and its index buffer are checked when
    it is drawn, as three.js reads nothing of an object it culls, and the
    material itself is looked up once the first draw survives.

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
        colors: One sRGB color per draw, which multiplies the material's
            color, or none for white.

    Raises:
        Error: If the node, a geometry or the material is not there, a
            geometry has no positions, the scene is stale, an instance
            matrix projects or holds a value that is not finite, or there
            are colors but not one per draw.
    """
    if not scene.shows(node, visible):
        return
    var tinted = len(colors) > 0
    if tinted and len(colors) != len(matrices):
        raise Error("An instanced mesh must have one color per instance")
    var placed = scene.world_matrix(node)
    var blends = False
    var asked = False
    for index in range(len(matrices)):
        check_placing(matrices[index])
        var world = Matrix4(copy=placed)
        world.multiply(matrices[index])
        if culled and not _in_view(
            assets, geometries[index], world, frustum, slack, bounds, known
        ):
            continue
        if not asked:
            blends = assets.materials.get(material).is_transparent()
            asked = True
        # The camera looks down -z, so a smaller z is further away. The
        # draw's own origin: the translation column of where it is placed.
        var depth = view.transform_point(
            Vector3(world.elements[12], world.elements[13], world.elements[14])
        ).z
        depths.append(depth)
        clear.append(blends)
        var tint = FloatColor(1, 1, 1, 1)
        if tinted:
            tint = FloatColor(srgb=colors[index])
        draws.append(
            _Draw(
                geometries[index],
                material,
                world^,
                morph_influences,
                skin,
                depth,
                blends,
                -1,
                receive_shadow,
                scene.render_order(node),
                tint,
                -1,
            )
        )


def _draws(
    scene: Scene,
    assets: Assets,
    view: Matrix4,
    eye: Vector3,
    visible: Layers,
    frustum: Frustum,
    slack: Float32,
    mut skins: List[SkinPose],
    casters_only: Bool = False,
) raises -> List[_Draw]:
    """Return what the camera draws, in the order to draw it: opaque
    draws nearest first, then the translucent ones furthest first.

    The scene's meshes, instanced meshes, batched meshes and LODs are
    read into draws by `_gather`, which also leaves out what the camera's
    layers and frustum leave out; an LOD contributes the one level its
    node's distance from the camera picks, three.js's `LOD.update`, or
    nothing when it has no levels.

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
        eye: Where the camera is, in world space, for an LOD's distance.
        visible: The camera's layers. An object on none of them is left
            out.
        frustum: The camera's frustum, in world space. A draw whose bound
            lies wholly outside it is left out, unless its object opted out.
        slack: How far past a plane a bound may lie and still be drawn;
            see `CULL_SLACK`.
        skins: The frame's posed skeletons; one is appended per skinned
            mesh, and the draws name them by index.
        casters_only: Whether this is a light's view for a shadow map,
            which holds the meshes that cast and nothing else: not a
            mesh that does not cast, and not a skinned, instanced or
            batched mesh, an LOD, a sprite or a wide line, none of which
            casts yet.

    Returns:
        The draws the camera makes, in the order to make them.

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
        if casters_only and not mesh.cast_shadow:
            continue
        var geometry: List[GeometryId] = [mesh.geometry]
        # A mesh wearing a morph target is not where its geometry's bound
        # says it is, so it is not measured against the frustum. The bound
        # describes the face the mesh has stopped wearing. three.js culls
        # it anyway and clips morphed meshes at the edge of the view for
        # exactly this reason.
        _gather(
            draws,
            depths,
            clear,
            scene,
            assets,
            mesh.node,
            mesh.material,
            geometry,
            one,
            mesh.frustum_culled and not mesh.is_morphed(),
            view,
            visible,
            frustum,
            slack,
            bounds,
            known,
            mesh.morph_influences,
            receive_shadow=mesh.receive_shadow,
        )
    for index in range(len(scene.skinned_meshes)):
        if casters_only:
            continue
        ref skinned = scene.skinned_meshes[index]
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
        )
    for index in range(len(scene.instanced_meshes)):
        if casters_only:
            continue
        ref group = scene.instanced_meshes[index]
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
            colors=group.colors,
        )
    for index in range(len(scene.batched_meshes)):
        if casters_only:
            continue
        ref batch = scene.batched_meshes[index]
        var geometries = List[GeometryId]()
        var matrices = List[Matrix4]()
        var colors = List[Color]()
        for slot in range(batch.count()):
            geometries.append(batch.instances[slot].geometry)
            matrices.append(batch.instances[slot].matrix)
            colors.append(batch.instances[slot].color)
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
            batch.frustum_culled,
            view,
            visible,
            frustum,
            slack,
            bounds,
            known,
            colors=colors,
        )
    for index in range(len(scene.lods)):
        if casters_only:
            continue
        ref lod = scene.lods[index]
        # The level `Scene.update_lods` last chose sets the hysteresis; a
        # scene never updated gets the stateless choice.
        var level = lod.level_from(
            Length((eye - scene.world_position(lod.node)).length(), METER),
            lod.shown,
        )
        if level < 0:
            continue
        var shown = lod.levels[level]
        var geometry: List[GeometryId] = [shown.geometry]
        _gather(
            draws,
            depths,
            clear,
            scene,
            assets,
            lod.node,
            shown.material,
            geometry,
            one,
            lod.frustum_culled,
            view,
            visible,
            frustum,
            slack,
            bounds,
            known,
        )
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
        var blends = assets.materials.get(sprite.material).is_transparent()
        depths.append(depth)
        clear.append(blends)
        draws.append(
            _Draw(
                GeometryId(-1),
                sprite.material,
                world^,
                SIMD[DType.float32, MAX_MORPH_TARGETS](0),
                -1,
                depth,
                blends,
                index,
                False,
                scene.render_order(sprite.node),
                FloatColor(1, 1, 1, 1),
                -1,
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
        var blends = assets.materials.get(line.material).is_transparent()
        depths.append(depth)
        clear.append(blends)
        draws.append(
            _Draw(
                line.geometry,
                line.material,
                world^,
                SIMD[DType.float32, MAX_MORPH_TARGETS](0),
                -1,
                depth,
                blends,
                -1,
                False,
                scene.render_order(line.node),
                FloatColor(1, 1, 1, 1),
                index,
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
    return ordered^


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
    see `render.rasterizer.mapped_normal`.
    """
    var turned = corner
    turned.normal = -corner.normal
    turned.normal_scale = Vector2(
        -corner.normal_scale.x, -corner.normal_scale.y
    )
    turned.bump_scale = -corner.bump_scale
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
    )


@fieldwise_init
struct _Physics(ImplicitlyCopyable):
    """What a physical surface and a normal or bump map add to every corner
    of one draw: the numbers and the maps `RasterVertex` carries for them,
    gathered so `_to_raster` takes one more argument rather than twelve.
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

    def raster(self, vertex: ClipVertex) -> RasterVertex:
        """Project one clipped corner into the rasterizer's input."""
        return _to_raster(
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
        )

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


def _draw_state(material: Material, casters_only: Bool) raises -> RasterState:
    """Return the depth, color and stencil state a draw is made under.

    The material's, checked, for a frame. A light's view of the casters
    draws depth alone, under three.js's own depth material rather than the
    mesh's, so it takes the default state: a mask pass that writes no
    color still casts its shadow.

    Args:
        material: The draw's material.
        casters_only: Whether this is a light's view of the casters.

    Returns:
        The state.

    Raises:
        Error: If the material's state is refused by
            `RasterState.check`, whichever view this is.
    """
    var state = material.raster_state()
    if casters_only:
        return RasterState()
    return state


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
            that is not stored as data, or holds a depth, color, stencil
            or offset state that is refused.
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
    var maps = _checked_maps(assets, material, shading)
    var to_uv = _uv_transform(assets, material)
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
        var placed = to_uv.transform_point(
            Vector2(xs[corner] + 0.5, ys[corner] + 0.5)
        )
        quad.append(
            ClipVertex(
                Vector3(
                    center.x + turned_x * aligned_x - turned_y * aligned_y,
                    center.y + turned_y * aligned_x + turned_x * aligned_y,
                    center.z,
                ),
                base,
                Vector3(0, 0, 1),
                placed.x,
                placed.y,
                origin,
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
        _draw_state(material, casters_only),
        _draw_offset(material, casters_only),
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
            map or an env map, or is a wireframe; if the geometry is
            indexed, has no positions or an odd count of them; if the
            material asks for vertex colors the geometry does not have;
            if a dash pattern is too fine for a segment; or if the
            material's depth, color, stencil or offset state is refused.
    """
    var material = assets.materials.get(draw.material)
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
        _draw_state(material, False),
        _draw_offset(material, False),
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
    highlight along the direction from the surface to here, and an `Lod`
    measures its distance from here, so both `prepare` and `render` ask it.
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

    def __init__(
        out self,
        var corners: List[RasterVertex],
        var segments: List[RasterVertex],
        var draws: List[Draw],
        var points: List[RasterVertex] = List[RasterVertex](),
    ):
        """Hold a prepared frame.

        Args:
            corners: The triangles' corners, three each.
            segments: The segments' corners, two each.
            draws: The order to draw them in.
            points: The points, one corner each. None by default.
        """
        self.corners = corners^
        self.segments = segments^
        self.draws = draws^
        self.points = points^


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
        self.viewport = Rect.whole(width, height)
        self.scissor = Rect.whole(width, height)
        self.scissor_test = False
        self.antialias = False
        self.render_scale = 1
        self.ltc = LtcTables()
        self.clipping_planes = List[Plane]()
        self.local_clipping_enabled = False

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
        itself. Its `render_scale` is this one's times `SUPERSAMPLE`, so a
        point's size and a line's thickness -- the two things a caller
        gives in pixels -- come out the size they were asked for once the
        frame is averaged down. A caller driving `GpuRenderer.draw` by
        hand has to pass that `render_scale` as the draw's `line_width`
        for the same reason.

        Returns:
            The larger renderer.

        Raises:
            Error: If the larger renderer cannot be built.
        """
        var big = Renderer(
            self.width * SUPERSAMPLE, self.height * SUPERSAMPLE, self.workers
        )
        big.background = self.background
        big.shading = self.shading
        big.tone_mapping = self.tone_mapping
        big.tone_mapping_exposure = self.tone_mapping_exposure
        big.viewport = _scaled(self.viewport, SUPERSAMPLE)
        big.scissor = _scaled(self.scissor, SUPERSAMPLE)
        big.scissor_test = self.scissor_test
        # What makes the larger renderer draw a frame that *averages down*
        # to this one rather than merely one that is bigger: a point's
        # size and a line's thickness are given in the output pixels this
        # renderer has, and the larger one converts them once. See
        # `render_scale`.
        big.render_scale = self.render_scale * SUPERSAMPLE
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

        Returns:
            Raster vertices, three per triangle, in submission order, or
            two per segment when `wireframe`. A mesh
            whose node shares no layer with the camera contributes none,
            and nor does one whose bounding sphere lies wholly outside the
            camera's frustum, unless it opted out of that test. An
            instanced or batched mesh contributes each of its instances the
            same way, and an LOD the one level its distance from the camera
            picks.

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

        # Where the camera is, in the world: what an LOD measures its
        # distance from, and what a highlight is measured toward.
        var to_world = Matrix4(copy=view)
        to_world.invert()
        var eye = to_world.transform_point(Vector3(0, 0, 0))
        # Worked out once, not once per draw, and already without what
        # the camera does not draw: every mesh, every instance and every
        # LOD's shown level, as one list.
        var skins = List[SkinPose]()
        var draws = _draws(
            scene,
            assets,
            view,
            eye,
            camera.visible_layers(),
            frustum,
            far * CULL_SLACK,
            skins,
            casters_only,
        )
        # Whether the camera's rays converge, for a sprite that keeps its
        # size on the image; see `_emit_sprite`.
        var perspective = not camera.projection_matrix().is_affine()
        for slot in range(len(draws)):
            if draws[slot].wide_line >= 0:
                # A wide line is drawn as triangles, so it is a filled
                # surface and is left out of the wireframe half. Its
                # triangles are built from its pairs of points; see
                # `_emit_wide_line`.
                if wireframe:
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
                )
                continue
            if draws[slot].sprite >= 0:
                # A sprite names no geometry, so nothing below applies to
                # it: its two triangles are built from its node instead.
                # It is a filled surface only, and refuses a wireframe.
                if wireframe:
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
            # The four maps that hold numbers, each checked the way the
            # alpha map is -- there, and stored as data, whatever the
            # shading mode -- and each erased unless textures are opened.
            var physics = _Physics(
                material.roughness,
                material.metalness,
                material.env_map_intensity,
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
            )
            if self.shading != SHADE_TEXTURE:
                physics.roughness_map = NO_TEXTURE
                physics.metalness_map = NO_TEXTURE
                physics.normal_map = NO_TEXTURE
                physics.bump_map = NO_TEXTURE
            # Where the maps are moved, tiled and turned on this surface,
            # asked of the material's own maps whatever the shading mode:
            # the uv view shows the coordinates the texture would be
            # sampled with, and a pair of maps that disagree is a wrong
            # asset under any mode.
            var to_uv = _uv_transform(assets, material)
            # Light the surface gives off, decoded to linear once and carried
            # on every corner like the base color below.
            var glow = material.emissive_light()
            # How much the surface reflects head on, decoded once and
            # carried the same way: a `PHONG` material's specular, a
            # physical material's reflectance, and black for every other
            # kind. See `Material.base_reflectance`.
            var sheen = material.base_reflectance()
            var smooth = geometry.has_attribute(String(NORMAL))
            var mapped = geometry.has_attribute(String(UV))

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
            var worn = morphed_positions(geometry, draws[slot].morph_influences)
            for vertex in range(vertex_count):
                var local = worn[vertex]
                if carried:
                    local = carriers[vertex].transform_point(local)
                var point = world.transform_point(local)
                world_points.append(point)
                view_points.append(view.transform_point(point))

            # Texture coordinates do not go through the world transform:
            # they name a place in an image, not a place in the world. They
            # go through the texture's own transform instead, once per
            # vertex as three.js's vertex shader does it, so a repeat tiles
            # the image and an offset slides it. A geometry without them
            # gets zeroes, which map everything to one corner -- harmless
            # until something is actually sampled with them.
            var vertex_u = List[Float32]()
            var vertex_v = List[Float32]()
            if mapped:
                ref uvs = geometry.attribute_view(String(UV))
                for vertex in range(vertex_count):
                    var placed = to_uv.transform_point(
                        Vector2(
                            uvs.component(vertex, 0), uvs.component(vertex, 1)
                        )
                    )
                    vertex_u.append(placed.x)
                    vertex_v.append(placed.y)
            else:
                # Through the transform too, so a geometry without
                # coordinates and one whose coordinates are all zero name
                # the same place in the image.
                var fallback = to_uv.transform_point(Vector2(0, 0))
                for _ in range(vertex_count):
                    vertex_u.append(fallback.x)
                    vertex_v.append(fallback.y)

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
                geometry, material.vertex_colors, base, vertex_count
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
            var triangles = geometry.triangle_count()
            # Grown once per draw rather than by doubling as corners arrive,
            # which copied the frame's whole list several times over: three
            # corners a triangle, before the clipper adds any or the facing
            # test drops any.
            corners.reserve(len(corners) + triangles * 3)
            var begin = len(corners)
            var paint = _Paint(
                to_screen,
                map,
                blending,
                kind,
                glow_map,
                mask,
                material.alpha_test,
                sheen,
                material.shininess,
                tones,
                ball,
                mirrored,
                material.side,
                env,
                material.reflectivity,
                material.combine,
                physics,
                draws[slot].receives_shadow,
                _draw_state(material, casters_only),
                _draw_offset(material, casters_only),
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
                var ends = triangle_edges(geometry)
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
                )
                continue
            for triangle in range(triangles):
                var first = triangle * 3
                var second = first + 1
                var third = first + 2
                if indexed:
                    first = indices[triangle * 3]
                    second = indices[triangle * 3 + 1]
                    third = indices[triangle * 3 + 2]

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
                )
                var corner_b = ClipVertex(
                    view_points[second],
                    vertex_colors[second],
                    normal_b,
                    vertex_u[second],
                    vertex_v[second],
                    world_points[second],
                    glow,
                )
                var corner_c = ClipVertex(
                    view_points[third],
                    vertex_colors[third],
                    normal_c,
                    vertex_u[third],
                    vertex_v[third],
                    world_points[third],
                    glow,
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
            )

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
            var material = assets.materials.get(line.material)
            # A line is never a caster, so its state is always its own.
            var state = _draw_state(material, False)
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_sets(
                material,
                view,
                sides,
                global_planes,
                self.local_clipping_enabled,
                False,
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
            if material.is_dashed():
                dash = material.dash_size.to(METER)
                gap = material.gap_size.to(METER)
                along = line_distances(line.mode, positions)
                for vertex in range(vertex_count):
                    along[vertex] *= material.dash_scale

            for segment in range(segment_count(line.mode, vertex_count)):
                var ends = segment_ends(line.mode, vertex_count, segment)
                var first = ends[0]
                var second = ends[1]
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
                        )
                    )
            _note_span(
                unsorted,
                DRAW_SEGMENTS,
                begin,
                len(corners),
                depth,
                material.is_transparent(),
                scene.render_order(line.node),
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
                    scene, assets, camera, True, wire_spans
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
                )
            )
            ordered.extend(
                Span(corners)[run.first * 2 : (run.first + run.count) * 2]
            )
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
            var material = assets.materials.get(points.material)
            # A point is never a caster, so its state is always its own.
            var state = _draw_state(material, False)
            var cut = List[Plane]()
            var any_of = List[Plane]()
            _clip_sets(
                material,
                view,
                sides,
                global_planes,
                self.local_clipping_enabled,
                False,
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
            var maps = _checked_maps(assets, material, self.shading)
            # A point samples its maps at its own coordinate, as stored;
            # see `render.pointrule.coord`. A map moved, tiled or turned
            # would be sampled somewhere its author did not say, so it is
            # refused rather than sampled untransformed, whatever the
            # shading mode: it is a wrong asset, not a wrong frame.
            if _uv_transform(assets, material) != Matrix3():
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
            for vertex in range(vertex_count):
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
                        point_size=attenuated_size(
                            material.point_size.pixels,
                            seen.z,
                            scale,
                            perspective and material.size_attenuation,
                            self.render_scale,
                        ),
                        state=state,
                    )
                )
            _note_span(
                unsorted,
                DRAW_POINTS,
                begin,
                len(corners),
                depth,
                material.is_transparent(),
                scene.render_order(points.node),
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
                )
            )
            ordered.extend(Span(corners)[run.first : run.first + run.count])
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
        it: the pane had blended without claiming the depth, and the line
        passed the test.

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
                `prepare_points` raise.
        """
        var corner_spans = List[_Span]()
        var corners = self._prepared(scene, assets, camera, False, corner_spans)
        var segment_spans = List[_Span]()
        var segments = self._prepared_lines(
            scene, assets, camera, segment_spans
        )
        var point_spans = List[_Span]()
        var points = self._prepared_points(scene, assets, camera, point_spans)
        var draws = List[Draw]()
        for span in range(len(corner_spans)):
            ref run = corner_spans[span]
            if not run.blends:
                draws.append(Draw(DRAW_TRIANGLES, run.first, run.count))
        for span in range(len(segment_spans)):
            ref run = segment_spans[span]
            if not run.blends:
                draws.append(Draw(DRAW_SEGMENTS, run.first, run.count))
        for span in range(len(point_spans)):
            ref run = point_spans[span]
            if not run.blends:
                draws.append(Draw(DRAW_POINTS, run.first, run.count))
        # Every kind's blended runs, furthest first. Each list is already
        # in that order on its own; the sort is stable, so at one depth a
        # surface still goes before a line, and a line before a point.
        var mixed = List[_Span]()
        var order = List[Int]()
        var depths = List[Float32]()
        var orders = List[Int]()
        for span in range(len(corner_spans)):
            if corner_spans[span].blends:
                order.append(len(mixed))
                depths.append(corner_spans[span].depth)
                orders.append(corner_spans[span].order)
                mixed.append(corner_spans[span])
        for span in range(len(segment_spans)):
            if segment_spans[span].blends:
                order.append(len(mixed))
                depths.append(segment_spans[span].depth)
                orders.append(segment_spans[span].order)
                mixed.append(segment_spans[span])
        for span in range(len(point_spans)):
            if point_spans[span].blends:
                order.append(len(mixed))
                depths.append(point_spans[span].depth)
                orders.append(point_spans[span].order)
                mixed.append(point_spans[span])
        _sort_by(order, depths, orders)
        for position in range(len(order)):
            ref run = mixed[order[position]]
            draws.append(Draw(run.kind, run.first, run.count))
        return Frame(corners^, segments^, draws^, points^)

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
        if self.antialias:
            # Drawn at `SUPERSAMPLE` times the size by a renderer that
            # does not supersample, and averaged down *before* the one
            # conversion below rather than after it: the samples are scene
            # radiance and the average of radiance is what an output pixel
            # holds. See `RenderTarget.downsampled` and `render.antialias`.
            var big = self.supersampled()
            var drawn = RenderTarget(big.width, big.height, self.background)
            big.render_into(drawn, scene, assets, camera)
            return drawn.downsampled(SUPERSAMPLE).resolve(
                self.workers, self.tone_curve(), self.tone_mapping_exposure
            )
        var target = RenderTarget(self.width, self.height, self.background)
        self.render_into(target, scene, assets, camera)
        # Linear light becomes an image exactly once, here, on as many
        # threads as drew it, through the tone mapping curve on the way --
        # except in the uv view, which is coordinates rather than light and
        # is never tone mapped, background included, on either backend. A
        # normal or depth material's pixels are data too, and the target
        # keeps the curve off them by itself.
        return target.resolve(
            self.workers, self.tone_curve(), self.tone_mapping_exposure
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
                self.workers, self.tone_curve(), self.tone_mapping_exposure
            )
        var target = RenderTarget(self.width, self.height, self.background)
        self.render_array_into(target, scene, assets, array)
        return target.resolve(
            self.workers, self.tone_curve(), self.tone_mapping_exposure
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
        try:
            for index in range(array.count()):
                self.viewport = array.viewports[index]
                self.scissor = array.viewports[index]
                self.render_into(target, scene, assets, array.cameras[index])
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

    def render_into[
        C: Camera
    ](
        self, mut target: RenderTarget, scene: Scene, assets: Assets, camera: C
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

        Args:
            target: The target to draw into. It must be the renderer's
                size.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera to project through.

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
        # is looked up in. See `camera_up`.
        var lighting = Lighting(
            scene,
            visible=camera.visible_layers(),
            eye=camera_position(scene, camera),
            toward_eye=toward_camera(scene, camera),
            up=camera_up(scene, camera),
            shadows=self.shadow_maps(scene, assets, camera.visible_layers()),
            ltc=self.ltc_tables(),
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
        target.clear_inside(kept, self.clear_color(scene))
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
        )

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
        self, scene: Scene, assets: Assets, visible: Layers = Layers.all()
    ) raises -> List[ShadowMap]:
        """Draw the scene's depth from every light that casts a shadow,
        and return the maps for `Lighting` to compare against.

        One map per directional or spot light on the camera's layers
        whose `cast_shadow` is set, drawn through the camera the light's
        `shadow` describes: an orthographic one `extent` meters to each
        side for a directional light, three.js's `DirectionalLightShadow`,
        and a perspective one twice the cone's angle wide for a spot
        light, three.js's `SpotLightShadow`, each at the light's node
        looking at its target, between the shadow's near and far planes.
        Only the meshes that cast are drawn, under lit shading with no
        lights, so a cut-out map cuts nothing out of a shadow and a
        translucent surface, which claims no depth, casts none; see
        `_draws`. What is kept is the target's depth, and the transform
        that put it there.

        `render_into` draws these itself. Call this to hand the same maps
        to `GpuRenderer.draw`, through `Lighting`.

        Args:
            scene: The transform hierarchy, updated, with its lights.
            assets: The geometry and materials the casters name.
            visible: The camera's layers; a light on none of them draws
                nothing, as `Lighting` leaves it out.

        Returns:
            The maps, each naming its light by index.

        Raises:
            Error: If a light is refused by `Light.validate`, a casting
                light names a node or a target the scene lacks or sits on
                its target, or anything `prepare` raises for the casters.
        """
        var maps = List[ShadowMap]()
        for index in range(len(scene.lights)):
            ref light = scene.lights[index]
            light.validate()
            if not light.cast_shadow or not light.layers.test(visible):
                continue
            if not scene.light_shown(light):
                continue
            var at = scene.world_position(light.node)
            var aimed = Vector3(0, 0, 0)
            if light.target != NO_PARENT:
                aimed = scene.world_position(light.target)
            if (at - aimed).length() == 0:
                raise Error(
                    "A light that casts a shadow needs a direction: its node"
                    " sits on its target"
                )
            ref shadow = light.shadow
            var corners: List[RasterVertex]
            var frame: Matrix4
            if light.kind == DIRECTIONAL:
                var camera = OrthographicCamera(
                    Length(-shadow.extent.to(METER), METER),
                    shadow.extent,
                    shadow.extent,
                    Length(-shadow.extent.to(METER), METER),
                    shadow.near,
                    shadow.far,
                )
                camera.place(at, aimed)
                corners = self._casters(scene, assets, camera, shadow.map_size)
                frame = camera.projection_matrix()
                frame.multiply(camera.view_matrix_in(scene))
            else:
                var camera = PerspectiveCamera(
                    Angle(light.angle.value * 2, RADIAN),
                    1.0,
                    shadow.near,
                    shadow.far,
                )
                camera.place(at, aimed)
                corners = self._casters(scene, assets, camera, shadow.map_size)
                frame = camera.projection_matrix()
                frame.multiply(camera.view_matrix_in(scene))
            var target = RenderTarget(
                shadow.map_size, shadow.map_size, Color(0, 0, 0)
            )
            rasterize_all(
                corners,
                target,
                SHADE_LIT,
                TextureStore(),
                Lighting.uniform(),
                self.workers,
            )
            var held = SIMD[DType.float32, 16](0)
            for element in range(16):  # pragma: no branch
                held[element] = frame.elements[element]
            maps.append(
                ShadowMap(
                    index,
                    shadow.map_size,
                    held,
                    target.depth.copy(),
                    shadow.bias,
                    shadow.normal_bias,
                    shadow.radius,
                )
            )
        return maps^

    def _casters[
        C: Camera
    ](self, scene: Scene, assets: Assets, camera: C, size: Int) raises -> List[
        RasterVertex
    ]:
        """Return the triangles of the meshes that cast a shadow, as a
        light's camera sees them, on a square of `size` pixels a side."""
        var spans = List[_Span]()
        var square = Renderer(size, size, workers=self.workers)
        # A material's planes cut its shadow under `clip_shadows`, which
        # this renderer's switch decides as it does for the frame.
        square.local_clipping_enabled = self.local_clipping_enabled
        return square._prepared(scene, assets, camera, False, spans, True)

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
        transform is not applied. A cube background is read in the
        direction each pixel's ray leaves the camera along: the near and
        the far point of the ray are unprojected into *view* space through
        the inverse projection, and their difference is turned into the
        world by the camera's rotation alone. So any camera serves, a
        parallel one sees one direction everywhere, and moving a camera
        without turning it changes no pixel of the sky.

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
                names a texture or a cube texture that is not there, or
                the camera's matrices cannot be built.
        """
        scene.background.validate()
        var backdrop = scene.background
        if not backdrop.is_image() or self.shading != SHADE_TEXTURE:
            return None
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
            for y in range(self.height):  # pragma: no branch
                for x in range(self.width):  # pragma: no branch
                    if not kept.contains_pixel(
                        x, y, self.height
                    ) or not viewport.contains_pixel(x, y, self.height):
                        continue
                    # Stretched over the viewport: the pixel's center as a
                    # fraction of the rectangle, `v` counting up.
                    var u = (Float32(x - viewport.x) + 0.5) / Float32(
                        viewport.width
                    )
                    var v = 1 - (Float32(y - top) + 0.5) / Float32(
                        viewport.height
                    )
                    _set_backdrop(image, x, y, picture.sample(u, v))
            return image^
        if backdrop.cube.value >= assets.cube_textures.count():
            raise Error("A background names a cube texture that is not there")
        ref sky = assets.cube_textures.get(backdrop.cube)
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
                _set_backdrop(
                    image,
                    x,
                    y,
                    sky.sample(to_world.transform_direction(far - near)),
                )
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
        var faces = List[Framebuffer]()
        for face in range(FACE_COUNT):  # pragma: no branch
            faces.append(
                side.render(scene, assets, camera.face_camera(face, scene))
            )
        return cube_texture_of(faces)
