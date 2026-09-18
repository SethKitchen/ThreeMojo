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

from cameras.camera import Camera
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
from lights.lighting import PERSPECTIVE_VIEW, Lighting
from core.layers import Layers
from core.object3d import NodeId
from core.scene import Scene
from math.bounds import Sphere
from math.frustum import Frustum
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.instanced_mesh import check_placing
from objects.skeleton import blend_bones
from objects.skinned_mesh import BONES_PER_VERTEX, SKIN_INDEX, SKIN_WEIGHT
from materials.material import (
    BACK_SIDE,
    DOUBLE_SIDE,
    FRONT_SIDE,
    NORMALS,
    Blending,
    Material,
    MaterialId,
    MaterialKind,
)
from units.si import Length, METER
from render.texture import IGNORED
from render.texture_store import NO_TEXTURE, TextureId
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from render.tonemap import NO_TONE_MAPPING, ToneMapping, check_tone_mapping
from math.vector2 import Vector2
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    ShadeMode,
    check_alpha_map,
    check_gradient_map,
    check_output_kinds,
    edge,
    rasterize_all,
)
from renderers.clip import ClipVertex, clip_depth
from std.math import max
from std.sys import num_logical_cores


def _carriers(
    geometry: BufferGeometry,
    skins: List[_Skin],
    skin: Int,
    vertex_count: Int,
) raises -> List[Matrix4]:
    """Return one matrix per vertex, carrying it from its own space to
    where the bones have taken it.

    three.js's `skinning_vertex` and `skinnormal_vertex` share a blend and
    so do these: the sandwich `bind_inverse * blend * bind` is a linear
    map, so the same matrix moves the position and turns the normal.

    Args:
        geometry: The geometry being drawn; it must carry `skinIndex` and
            `skinWeight`.
        skins: The frame's posed skeletons.
        skin: Which of them carries this draw, or minus one for none.
        vertex_count: How many vertices the geometry has.

    Returns:
        One matrix per vertex, or an empty list when the draw is not
        skinned.

    Raises:
        Error: If the geometry has no skin attributes, if either is not
            four numbers a vertex or does not cover every vertex, or if a
            vertex names a bone the skeleton does not have or carries
            weights that do not sum to one.
    """
    var out = List[Matrix4]()
    if skin < 0:
        return out^
    if not geometry.has_attribute(String(SKIN_INDEX)) or not (
        geometry.has_attribute(String(SKIN_WEIGHT))
    ):
        raise Error("A skinned mesh needs skinIndex and skinWeight")
    ref bones = geometry.attribute_view(String(SKIN_INDEX))
    ref weights = geometry.attribute_view(String(SKIN_WEIGHT))
    if (
        bones.item_size != BONES_PER_VERTEX
        or weights.item_size != BONES_PER_VERTEX
    ):
        raise Error("A skin attribute holds four numbers a vertex")
    if bones.count() != vertex_count or weights.count() != vertex_count:
        raise Error("A skin attribute must cover every vertex")
    for vertex in range(vertex_count):  # pragma: no branch
        var named = List[Int]()
        var shares = List[Float32]()
        for slot in range(BONES_PER_VERTEX):  # pragma: no branch
            named.append(Int(bones.component(vertex, slot)))
            shares.append(weights.component(vertex, slot))
        var blended = blend_bones(skins[skin].palette, named, shares)
        # Into the bones' space, through them, and back out: three.js's
        # `bindMatrixInverse * skinMatrix * bindMatrix`.
        var carry = Matrix4(copy=skins[skin].bind_inverse)
        carry.multiply(blended)
        carry.multiply(skins[skin].bind)
        out.append(carry^)
    return out^


def _morph_offset(
    base: Vector3, target: Vector3, weight: Float32, relative: Bool
) -> Vector3:
    """Return how far one morph target moves a vertex at `weight`.

    three.js's two lines of `morphtarget_vertex`, and the same pair for a
    normal. A target that holds finished positions contributes the run from
    the base to itself; one that holds offsets contributes itself.

    It returns the offset rather than the moved point so that the caller
    can add every target's offset to the *unmorphed* value. Moving the
    point once per target instead measures each target from where the last
    one left it, and two half-worn targets then land somewhere neither of
    them names: half of a target that carries a vertex to two, followed by
    half of one that carries it to two the other way, gave a half rather
    than a one.
    """
    if relative:
        return target * weight
    return (target - base) * weight


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
    ]
    var chosen = Matrix3()
    var settled = False
    # Three maps, always, so the loop never runs zero times.
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


struct _Skin(Movable):
    """One skinned mesh's bones, as the vertex loop needs them.

    The palette is `Skeleton.pose`: one matrix per bone saying how far it
    has moved since the bind. The two bind matrices carry a vertex into the
    space the bones work in and back out again; see
    `objects.skinned_mesh`.

    It is a per-frame thing and not part of a `_Draw`, because a draw is
    copied into a sorted list and a palette is a list of its own. Draws
    name theirs by index instead, which keeps a draw four small values.
    """

    var palette: List[Matrix4]
    var bind: Matrix4
    var bind_inverse: Matrix4

    def __init__(
        out self,
        var palette: List[Matrix4],
        bind: Matrix4,
        bind_inverse: Matrix4,
    ):
        """Hold one mesh's posed bones and its bind matrices.

        Args:
            palette: One matrix per bone, from `Skeleton.pose`.
            bind: Where the mesh stood when it was bound.
            bind_inverse: The inverse of that.
        """
        self.palette = palette^
        self.bind = bind
        self.bind_inverse = bind_inverse


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

    Raises:
        Error: If the node, a geometry or the material is not there, a
            geometry has no positions, the scene is stale, or an instance
            matrix projects or holds a value that is not finite.
    """
    if not scene.get(node).layers.test(visible):
        return
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
        depths.append(
            view.transform_point(
                Vector3(
                    world.elements[12], world.elements[13], world.elements[14]
                )
            ).z
        )
        clear.append(blends)
        draws.append(
            _Draw(geometries[index], material, world^, morph_influences, skin)
        )


def _draws(
    scene: Scene,
    assets: Assets,
    view: Matrix4,
    eye: Vector3,
    visible: Layers,
    frustum: Frustum,
    slack: Float32,
    mut skins: List[_Skin],
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
        )
    for index in range(len(scene.skinned_meshes)):
        ref skinned = scene.skinned_meshes[index]
        # The bones' world matrices, then how far each has moved since the
        # bind. Once per mesh per frame, whatever the vertex count.
        var placed = List[Matrix4]()
        for bone in range(skinned.bone_count()):  # pragma: no branch
            placed.append(scene.world_matrix(skinned.skeleton.node(bone)))
        skins.append(
            _Skin(
                skinned.skeleton.pose(placed),
                skinned.bind_matrix,
                skinned.bind_inverse,
            )
        )
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
        )
    for index in range(len(scene.batched_meshes)):
        ref batch = scene.batched_meshes[index]
        var geometries = List[GeometryId]()
        var matrices = List[Matrix4]()
        for slot in range(batch.count()):
            geometries.append(batch.instances[slot].geometry)
            matrices.append(batch.instances[slot].matrix)
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
        )
    for index in range(len(scene.lods)):
        ref lod = scene.lods[index]
        var level = lod.level_for(
            Length((eye - scene.world_position(lod.node)).length(), METER)
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

    var solid = List[Int]()
    var solid_depths = List[Float32]()
    var see_through = List[Int]()
    var see_through_depths = List[Float32]()
    for index in range(len(draws)):
        if clear[index]:
            see_through.append(index)
            see_through_depths.append(depths[index])
        else:
            solid.append(index)
            # Negated, so one ascending sort serves both lists: the nearest
            # opaque draw has the largest z and must come first.
            solid_depths.append(-depths[index])
    _sort_by(solid, solid_depths)
    _sort_by(see_through, see_through_depths)
    var ordered = List[_Draw]()
    for position in range(len(solid)):
        ordered.append(draws[solid[position]])
    for position in range(len(see_through)):
        ordered.append(draws[see_through[position]])
    return ordered^


def _sort_by(mut items: List[Int], mut keys: List[Float32]):
    """Sort `items` by `keys`, ascending, in place and stably.

    Insertion sort: the lists are one entry per draw, hundreds in a busy
    scene rather than millions, and a stable order keeps draws at equal
    depth in the order the caller gave them.
    """
    for position in range(len(items)):
        var item = items[position]
        var key = keys[position]
        var slot = position
        while slot > 0 and keys[slot - 1] > key:
            items[slot] = items[slot - 1]
            keys[slot] = keys[slot - 1]
            slot -= 1
        items[slot] = item
        keys[slot] = key


def _turned_around(corner: RasterVertex) -> RasterVertex:
    """Return `corner` with its normal reversed.

    For a surface being seen from its far side. Every other field is carried
    across unchanged, which is why this exists rather than a mutation: a
    `RasterVertex` has fifteen fields and rebuilding one by hand at three
    call sites is three chances to drop one.
    """
    return RasterVertex(
        corner.x,
        corner.y,
        corner.z,
        corner.inv_w,
        corner.color,
        corner.u,
        corner.v,
        corner.texture,
        corner.blend,
        -corner.normal,
        corner.world,
        corner.kind,
        corner.emissive,
        corner.emissive_map,
        corner.view_depth,
        corner.alpha_map,
        corner.alpha_test,
        corner.specular,
        corner.shininess,
        corner.gradient_map,
        corner.matcap,
    )


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


def available_workers() -> Int:
    """Return how many rasterizer workers this machine can run at once.

    One per logical core. The bands are independent and memory-light, so
    hyperthreads help rather than hurt.
    """
    return num_logical_cores()


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

        Returns:
            Raster vertices, three per triangle, in submission order. A mesh
            whose node shares no layer with the camera contributes none,
            and nor does one whose bounding sphere lies wholly outside the
            camera's frustum, unless it opted out of that test. An
            instanced or batched mesh contributes each of its instances the
            same way, and an LOD the one level its distance from the camera
            picks.

        Raises:
            Error: If a mesh names a node, a geometry or a material that is
                not there, if a material names a texture, an emissive map
                or an alpha map that is not there, if its emissive map does
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
        var to_screen = camera.view_to_screen_matrix(self.width, self.height)
        var near = camera.near_distance()
        var far = camera.far_distance()
        # What the camera can see, in world space, where the meshes' bounds
        # are: three.js's `_projScreenMatrix` read as four side planes, and
        # the near and far distances the clipper below is given, as the
        # two depth planes.
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var frustum = Frustum.from_camera(clip, view, near, far)

        # Where the camera is, in the world: what an LOD measures its
        # distance from, and what a highlight is measured toward.
        var to_world = Matrix4(copy=view)
        to_world.invert()
        var eye = to_world.transform_point(Vector3(0, 0, 0))
        # Worked out once, not once per draw, and already without what
        # the camera does not draw: every mesh, every instance and every
        # LOD's shown level, as one list.
        var skins = List[_Skin]()
        var draws = _draws(
            scene,
            assets,
            view,
            eye,
            camera.visible_layers(),
            frustum,
            far * CULL_SLACK,
            skins,
        )
        for slot in range(len(draws)):
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
            # Where the maps are moved, tiled and turned on this surface,
            # asked of the material's own maps whatever the shading mode:
            # the uv view shows the coordinates the texture would be
            # sampled with, and a pair of maps that disagree is a wrong
            # asset under any mode.
            var to_uv = _uv_transform(assets, material)
            # Light the surface gives off, decoded to linear once and carried
            # on every corner like the base color below.
            var glow = material.emissive_light()
            # How much the surface sends toward the camera, decoded once and
            # carried the same way. Black unless the material is `PHONG`,
            # which is the only kind the constructor lets carry one.
            var sheen = material.specular_light()
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
            var targets = geometry.morph_count()
            # A skinned draw works out one matrix per vertex before the
            # loops below, because the position and the normal both want
            # it and three.js blends it once for the same reason.
            var carriers = _carriers(
                geometry, skins, draws[slot].skin, vertex_count
            )
            var carried = len(carriers) > 0
            for vertex in range(vertex_count):
                var base = positions.vector3(vertex)
                var local = base
                for target in range(targets):
                    local = local + _morph_offset(
                        base,
                        geometry.morph_position(target, vertex),
                        draws[slot].morph_influences[target],
                        geometry.morph_relative,
                    )
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
                ref normals = geometry.attribute_view(String(NORMAL))
                var to_normal = world.normal_matrix()
                # Morphed only when the targets carry normals of their own.
                # A geometry whose targets carry none keeps the base
                # normal however far the positions move, which is what
                # three.js's shader does without `morphAttributes.normal`.
                var turned = targets
                if not geometry.has_morph_normals():
                    turned = 0
                for vertex in range(vertex_count):
                    var rest = normals.vector3(vertex)
                    var facing = rest
                    for target in range(turned):
                        facing = facing + _morph_offset(
                            rest,
                            geometry.morph_normal(target, vertex),
                            draws[slot].morph_influences[target],
                            geometry.morph_relative,
                        )
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
            var base = _with_opacity(
                FloatColor(srgb=material.color), material.opacity
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

                var pieces = clip_depth(
                    ClipVertex(
                        view_points[first],
                        vertex_colors[first],
                        normal_a,
                        vertex_u[first],
                        vertex_v[first],
                        world_points[first],
                        glow,
                    ),
                    ClipVertex(
                        view_points[second],
                        vertex_colors[second],
                        normal_b,
                        vertex_u[second],
                        vertex_v[second],
                        world_points[second],
                        glow,
                    ),
                    ClipVertex(
                        view_points[third],
                        vertex_colors[third],
                        normal_c,
                        vertex_u[third],
                        vertex_v[third],
                        world_points[third],
                        glow,
                    ),
                    near,
                    far,
                )
                for piece in range(len(pieces) // 3):
                    var one = _to_raster(
                        pieces[piece * 3],
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
                    )
                    var two = _to_raster(
                        pieces[piece * 3 + 1],
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
                    )
                    var three = _to_raster(
                        pieces[piece * 3 + 2],
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
                    )
                    # Which way this piece ends up facing decides two things
                    # at once: whether it survives, and which side of it is
                    # being lit. Read from the screen winding, so it is known
                    # only now -- which is why the normal traveled this far
                    # unflipped.
                    var away = _faces_away(one, two, three, mirrored)
                    if material.side == FRONT_SIDE and away:
                        continue
                    if material.side == BACK_SIDE and not away:
                        continue
                    if away:
                        # Seen from behind, so light the side being looked at.
                        # Without this a BackSide surface with the light in
                        # front of it renders black: the Lambert term is taken
                        # against the normal pointing away from the camera.
                        #
                        # One flip replaces the two colors this used to carry
                        # from the vertex stage, because the far side's normal
                        # is just this one negated -- which the lighting was
                        # not, once it had been applied.
                        one = _turned_around(one)
                        two = _turned_around(two)
                        three = _turned_around(three)
                    corners.append(one)
                    corners.append(two)
                    corners.append(three)

        return corners^

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
            Error: If a mesh names a node or a geometry that is not there,
                its geometry has no positions, the scene's fog holds a
                kind that is none of the three or a range that is inside
                out -- see `core.fog.FogView` -- or a tone mapping curve is
                set and the scene holds both a data material and a blended
                one, which no pixel could resolve; see
                `render.rasterizer.check_output_kinds`.
        """
        var corners = self.prepare(scene, assets, camera)
        # Two output representations cannot share a tone-mapped frame. Asked
        # here, before anything is drawn, exactly where `GpuRenderer.draw`
        # asks it before a launch. The uv view is data throughout and is
        # never tone mapped, so it is never refused; see below.
        check_output_kinds(
            corners,
            self.shading != SHADE_UV and self.tone_mapping != NO_TONE_MAPPING,
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
        )
        # The scene's fog as the rasterizer takes it. Each corner already
        # carries the depth `prepare` measured for it along this view.
        var fog = FogView(scene.fog)
        var target = RenderTarget(self.width, self.height, self.background)
        rasterize_all(
            corners,
            target,
            self.shading,
            assets.textures,
            lighting,
            self.workers,
            fog,
        )
        # Linear light becomes an image exactly once, here, on as many
        # threads as drew it, through the tone mapping curve on the way --
        # except in the uv view, which is coordinates rather than light and
        # is never tone mapped, background included, on either backend. A
        # normal or depth material's pixels are data too, and the target
        # keeps the curve off them by itself.
        var curve = self.tone_mapping
        if self.shading == SHADE_UV:
            curve = NO_TONE_MAPPING
        return target.resolve(self.workers, curve, self.tone_mapping_exposure)
