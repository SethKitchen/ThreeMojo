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
"""

from cameras.camera import Camera
from core.buffer_geometry import NORMAL, POSITION, UV
from core.assets import Assets
from lights.lighting import Lighting
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from materials.material import BACK_SIDE, DOUBLE_SIDE, FRONT_SIDE, Blending
from render.texture import IGNORED
from render.texture_store import NO_TEXTURE, TextureId
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from math.vector2 import Vector2
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    ShadeMode,
    edge,
    rasterize_all,
)
from renderers.clip import ClipVertex, clip_depth
from std.math import max
from std.sys import num_logical_cores


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


def _draw_order(
    scene: Scene,
    assets: Assets,
    view: Matrix4,
) raises -> List[Int]:
    """Return the order to draw meshes in: opaque nearest first, then the
    translucent ones furthest first.

    Blending is not commutative, so a translucent surface only looks right if
    what is behind it is already there. Two rules follow, and they are the
    same two every renderer has:

    Opaque first, because a translucent surface has to mix with the solid
    thing behind it, and because opaque surfaces write depth — which is what
    stops a translucent surface behind a wall from showing through it. Among
    themselves the opaque meshes go nearest first. The image does not depend
    on it, since the depth test settles every pixel whatever the order, but
    the cost does: a fragment that fails the depth test is skipped *before*
    it is lit and sampled, so drawing the near things first means the far
    things' hidden fragments are never shaded at all. three.js sorts its
    opaque list front to back for the same reason.

    Then translucent, furthest first, because each one mixes into the result
    of the ones beyond it. Sorted by the camera-space depth of the mesh's
    origin, which is what three.js sorts by: per object, not per triangle.
    Within one mesh the triangles keep their own order, so a translucent mesh
    that overlaps itself is still approximate. That is the usual bargain, and
    the alternative is sorting every triangle every frame.

    Args:
        scene: The transform hierarchy, and the meshes to draw.
        assets: Where the materials live.
        view: The world-to-camera transform, for measuring depth.

    Returns:
        Indices into `scene.meshes`, in the order they should be drawn.

    Raises:
        Error: If a mesh names a node or material that is not there.
    """
    ref meshes = scene.meshes
    var solid = List[Int]()
    var solid_depths = List[Float32]()
    var clear = List[Int]()
    var clear_depths = List[Float32]()
    for index in range(len(meshes)):
        # The camera looks down -z, so a smaller z is further away.
        var depth = view.transform_point(
            scene.world_position(meshes[index].node)
        ).z
        if assets.materials.get(meshes[index].material).is_transparent():
            clear.append(index)
            clear_depths.append(depth)
        else:
            solid.append(index)
            # Negated, so one ascending sort serves both lists: the nearest
            # opaque mesh has the largest z and must come first.
            solid_depths.append(-depth)

    _sort_by(solid, solid_depths)
    _sort_by(clear, clear_depths)
    var order = List[Int]()
    for position in range(len(solid)):
        order.append(solid[position])
    for position in range(len(clear)):
        order.append(clear[position])
    return order^


def _sort_by(mut items: List[Int], mut keys: List[Float32]):
    """Sort `items` by `keys`, ascending, in place and stably.

    Insertion sort: the lists are one entry per mesh, which is small, and a
    stable order keeps meshes at equal depth in the order the caller gave
    them.
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
    `RasterVertex` has fourteen fields and rebuilding one by hand at three
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
        corner.lit,
        corner.emissive,
        corner.emissive_map,
    )


def _to_raster(
    vertex: ClipVertex,
    to_screen: Matrix4,
    texture: TextureId,
    blend: Blending,
    lit: Bool,
    emissive_map: TextureId,
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
        lit,
        vertex.emissive,
        emissive_map,
    )


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
            whose node shares no layer with the camera contributes none.

        Raises:
            Error: If a mesh names a node, a geometry or a material that is
                not there, if a material names a texture or an emissive map
                that is not there, if its emissive map does not ignore its
                alpha, or if its geometry has no positions.
        """
        var corners = List[RasterVertex]()
        # Asked of the scene as well as the camera: a camera riding a node
        # looks from wherever the scene put that node.
        var view = camera.view_matrix_in(scene)
        var to_screen = camera.view_to_screen_matrix(self.width, self.height)
        var near = camera.near_distance()
        var far = camera.far_distance()

        ref meshes = scene.meshes
        # Worked out once, not once per mesh.
        var order = _draw_order(scene, assets, view)
        for ordered in range(len(meshes)):
            var index = order[ordered]
            # A camera draws only the meshes on its layers, three.js's
            # `layers.test`, asked before anything is done for the mesh.
            var layers = scene.get(meshes[index].node).layers
            if not layers.test(camera.visible_layers()):
                continue
            var world = scene.world_matrix(meshes[index].node)
            # An odd number of reflections in the world transform reverses
            # winding, which turns both the culling convention and the
            # geometric-normal fallback upside down. Asked once per mesh, of
            # the world matrix rather than the node's own scale, because the
            # reflection can be inherited from any parent.
            var mirrored = world.determinant() < 0
            # Borrowed, not copied: two meshes naming the same id read the
            # same arrays rather than each holding their own.
            ref geometry = assets.geometries.get(meshes[index].geometry)
            var material = assets.materials.get(meshes[index].material)
            # Carried on every vertex of this mesh, so one flat triangle list
            # can hold a scene whose meshes use different images.
            var blending = material.blending
            var map = material.map
            # Whether the lights reach this surface at all; a `BASIC`
            # material shows its own color. Per triangle, like the blend.
            var lit = material.is_lit()
            # Checked here because here is the first place that can: a
            # material is built without the store in reach, so a positive id
            # naming nothing is only detectable once both are together. It is
            # checked before rasterization rather than during, so the answer
            # does not depend on whether the mesh happened to cover a pixel.
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
            # Light the surface gives off, decoded to linear once and carried
            # on every corner like the base color below.
            var glow = material.emissive_light()
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
            for vertex in range(vertex_count):
                var point = world.transform_point(positions.vector3(vertex))
                world_points.append(point)
                view_points.append(view.transform_point(point))

            # Texture coordinates travel untransformed: they name a place in
            # an image, not a place in the world. A geometry without them
            # gets zeroes, which map everything to one corner -- harmless
            # until something is actually sampled with them.
            var vertex_u = List[Float32]()
            var vertex_v = List[Float32]()
            if mapped:
                ref uvs = geometry.attribute_view(String(UV))
                for vertex in range(vertex_count):
                    vertex_u.append(uvs.component(vertex, 0))
                    vertex_v.append(uvs.component(vertex, 1))
            else:
                for _ in range(vertex_count):
                    vertex_u.append(0)
                    vertex_v.append(0)

            # World-space normals are their own pass so the normal array can
            # be borrowed only when there is one, and the normal matrix built
            # once per mesh rather than once per vertex. What used to happen
            # here was the *lighting*; now only the normal is worked out, and
            # the light is applied per fragment.
            var vertex_normals = List[Vector3]()
            if smooth:
                ref normals = geometry.attribute_view(String(NORMAL))
                var to_normal = world.normal_matrix()
                for vertex in range(vertex_count):
                    # transform_direction ignores translation, which is what a
                    # normal wants: it points somewhere, it is not somewhere.
                    var direction = to_normal.transform_direction(
                        normals.vector3(vertex)
                    )
                    direction.normalize()
                    vertex_normals.append(direction)

            # One color for the whole mesh now: the material's, decoded to
            # linear once with its opacity folded into alpha. Every corner
            # carries this same value and the fragment lights it.
            var base = _with_opacity(
                FloatColor(srgb=material.color), material.opacity
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
                    normal_a = geometric
                    normal_b = geometric
                    normal_c = geometric

                var pieces = clip_depth(
                    ClipVertex(
                        view_points[first],
                        base,
                        normal_a,
                        vertex_u[first],
                        vertex_v[first],
                        world_points[first],
                        glow,
                    ),
                    ClipVertex(
                        view_points[second],
                        base,
                        normal_b,
                        vertex_u[second],
                        vertex_v[second],
                        world_points[second],
                        glow,
                    ),
                    ClipVertex(
                        view_points[third],
                        base,
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
                        lit,
                        glow_map,
                    )
                    var two = _to_raster(
                        pieces[piece * 3 + 1],
                        to_screen,
                        map,
                        blending,
                        lit,
                        glow_map,
                    )
                    var three = _to_raster(
                        pieces[piece * 3 + 2],
                        to_screen,
                        map,
                        blending,
                        lit,
                        glow_map,
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
            Error: If a mesh names a node or a geometry that is not there, or
                its geometry has no positions.
        """
        var corners = self.prepare(scene, assets, camera)
        # Resolved here as well as in `prepare`, because the fragments need
        # it: lighting is no longer baked into the corners on the way past.
        var lighting = Lighting(scene)
        var target = RenderTarget(self.width, self.height, self.background)
        rasterize_all(
            corners,
            target,
            self.shading,
            assets.textures,
            lighting,
            self.workers,
        )
        # Linear light becomes an image exactly once, here, on as many
        # threads as drew it.
        return target.resolve(self.workers)
