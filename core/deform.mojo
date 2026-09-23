# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a geometry's vertices actually are once its morph targets are
worn, from three.js's `morphtarget_vertex` and `morphnormal_vertex`.

A geometry says where its vertices were modelled. A mesh says how much of
each morph target it wears. Neither alone says where a vertex *is*, and
two things need that answer: the renderer, which draws it, and the
raycaster, which has to agree about what the pointer is over.

They did not agree. Rendering applied the targets and picking did not, so
a morphed mesh was drawn in one place and clicked in another -- and worse,
still clickable where it no longer was. That is what this module is for:
one evaluator, two callers, no second copy of the arithmetic to drift.

## What is here and what is not

Skinning moves a vertex too, and the same two callers need it: the posed
bones come from the scene, `skin_pose` reads them once per mesh, and
`skin_carriers` turns them into one matrix per vertex. The renderer draws
a skinned mesh where they put it, and the raycaster picks it there.

A displacement map moves a vertex last, along its normal, and the same
two callers need that too: `displaced_positions` morphs, carries and
displaces in the order three.js's vertex shader does, and the shadow
pass draws through the renderer's code and so gets it as well.

## Why a list and not a callback

Both callers want every vertex, and both want to ask about bounds before
they ask about triangles. Handing back the whole array once is cheaper
than a call per vertex and simpler than an iterator, and it is what the
renderer already does with world and view positions.

A mesh wearing nothing gets the base positions copied. The callers avoid
paying for that by asking `Mesh.is_morphed` first, which is why this does
not try to be clever about it.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
    UV,
)
from core.scene import Scene
from materials.material import Material
from math.bounds import Box3, Sphere
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.skeleton import blend_bones
from objects.skinned_mesh import (
    ATTACHED,
    BONES_PER_VERTEX,
    SKIN_INDEX,
    SKIN_WEIGHT,
)
from render.rasterizer import check_data_map
from render.texture_store import NO_TEXTURE, TextureStore
from std.math import floor, isfinite
from units.si import METER


def morph_offset(
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
    them names.

    Args:
        base: The vertex as the geometry modelled it.
        target: What this target says about it.
        weight: How much of this target the mesh wears.
        relative: Whether the target holds offsets rather than positions.

    Returns:
        The offset to add to the base.
    """
    if relative:
        return target * weight
    return (target - base) * weight


def morphed_positions(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
) raises -> List[Vector3]:
    """Return where every vertex is once the morph targets are worn.

    Args:
        geometry: The geometry, which must have positions.
        influences: How much of each of its targets the mesh wears.

    Returns:
        One point per vertex, in the geometry's own space.

    Raises:
        Error: If the geometry has no positions, or a target does not
            cover a vertex.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var targets = geometry.morph_count()
    var out = List[Vector3]()
    for vertex in range(positions.count()):  # pragma: no branch
        var base = positions.vector3(vertex)
        var moved = base
        for target in range(targets):
            moved = moved + morph_offset(
                base,
                geometry.morph_position(target, vertex),
                influences[target],
                geometry.morph_relative,
            )
        out.append(moved)
    return out^


def morphed_normals(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
) raises -> List[Vector3]:
    """Return which way every vertex faces once the morph targets are worn.

    A geometry whose targets carry no normals keeps its base normals
    however far the positions move, which is what three.js's shader does
    without `morphAttributes.normal`.

    Args:
        geometry: The geometry, which must have normals.
        influences: How much of each of its targets the mesh wears.

    Returns:
        One direction per vertex, not made unit length: the caller turns
        them by its own matrix and normalizes after.

    Raises:
        Error: If the geometry has no normals, or a target does not cover
            a vertex.
    """
    ref normals = geometry.attribute_view(String(NORMAL))
    var targets = geometry.morph_count()
    if not geometry.has_morph_normals():
        targets = 0
    var out = List[Vector3]()
    for vertex in range(normals.count()):  # pragma: no branch
        var rest = normals.vector3(vertex)
        var facing = rest
        for target in range(targets):
            facing = facing + morph_offset(
                rest,
                geometry.morph_normal(target, vertex),
                influences[target],
                geometry.morph_relative,
            )
        out.append(facing)
    return out^


def box_of(points: List[Vector3]) -> Box3:
    """Return the box around a list of points, empty for no points.

    Args:
        points: The points to bound.

    Returns:
        The box.
    """
    var box = Box3.empty()
    for index in range(len(points)):
        box.expand_by_point(points[index])
    return box^


def sphere_of(points: List[Vector3]) raises -> Sphere:
    """Return a sphere around a list of points.

    The same construction `BufferGeometry.bounding_sphere` uses: the center
    of the box around them, and the distance to the furthest one. It is not
    the smallest sphere that holds them, and it does not need to be -- it
    only has to hold them, which is what a rejection test needs.

    Args:
        points: The points to bound.

    Returns:
        The sphere.

    Raises:
        Error: If there are no points to bound.
    """
    if len(points) == 0:
        raise Error("A bound needs a point to be around")
    var box = box_of(points)
    var center = box.center()
    var reach = Float32(0)
    for index in range(len(points)):  # pragma: no branch
        var out = (points[index] - center).length()
        if out > reach:
            reach = out
    return Sphere(center, reach)


def whole_bone(named: Float32, count: Int) raises -> Int:
    """Return which bone a `skinIndex` component names.

    The attribute holds floats because every vertex attribute does, but a
    bone number is a whole number and nothing else. Converting first and
    asking afterward loses the distinction: `Int(0.75)` is bone zero, so a
    rig exported with fractional indices quietly drew the wrong bone
    carrying the wrong vertex, and `Int(-0.5)` is bone zero as well, so a
    negative index lost its sign on the way to the range check.

    Args:
        named: The component as the attribute stores it.
        count: How many bones the skeleton has.

    Returns:
        The bone number.

    Raises:
        Error: If the component is not a number, is not whole, or is not a
            bone the skeleton has.
    """
    if not isfinite(named):
        raise Error("A bone index must be a number")
    if named != floor(named):
        raise Error("A bone index must be a whole number")
    var bone = Int(named)
    if bone < 0 or bone >= count:
        raise Error("A vertex names a bone the skeleton does not have")
    return bone


struct SkinPose(Movable):
    """One skinned mesh's bones, as the vertex loop needs them.

    The palette is `Skeleton.pose`: one matrix per bone saying how far it
    has moved since the bind. The two bind matrices carry a vertex into the
    space the bones work in and back out again; see
    `objects.skinned_mesh`.

    `bind_inverse` is worked out by `skin_pose` rather than taken from the
    mesh, because an `ATTACHED` mesh undoes wherever its node is *now*.
    Taking the mesh's fixed inverse instead moved a character twice when
    its mesh and its bones hung from one root that walked: the bones
    carried the root's transform, and the mesh's node carried it again.
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


def skin_pose(scene: Scene, index: Int) raises -> SkinPose:
    """Return where one skinned mesh's bones stand now.

    Args:
        scene: The scene, updated.
        index: Which mesh, as its position in `scene.skinned_meshes`.

    Returns:
        The palette and the two bind matrices.

    Raises:
        Error: If no skinned mesh has that index, a bone's node is not
            there, the scene is stale, or the matrix the bones' result is
            carried back out of has no inverse.
    """
    if index < 0 or index >= len(scene.skinned_meshes):
        raise Error("No skinned mesh has that index")
    ref skinned = scene.skinned_meshes[index]
    # The bones' world matrices, then how far each has moved since the
    # bind. Once per mesh, whatever the vertex count.
    var placed = List[Matrix4]()
    for bone in range(skinned.bone_count()):  # pragma: no branch
        placed.append(scene.world_matrix(skinned.skeleton.node(bone)))
    # What the bones' world-space result is carried back out of. An
    # attached mesh undoes its node as it stands now, so that the node
    # carrying it and the bones carrying it do not both count; a detached
    # one undoes the bind it was given and stays where its own node puts
    # it.
    var undo = Matrix4(copy=skinned.bind_matrix)
    if skinned.bind_mode == ATTACHED:
        undo = scene.world_matrix(skinned.node)
    if undo.determinant() == 0:
        raise Error("A skinned mesh has no inverse to undo its bind")
    undo.invert()
    return SkinPose(skinned.skeleton.pose(placed), skinned.bind_matrix, undo^)


def skin_carriers(
    geometry: BufferGeometry, pose: SkinPose, vertex_count: Int
) raises -> List[Matrix4]:
    """Return one matrix per vertex, carrying it from its own space to
    where the bones have taken it.

    three.js's `skinning_vertex` and `skinnormal_vertex` share a blend and
    so do these: the sandwich `bind_inverse * blend * bind` is a linear
    map, so the same matrix moves the position and turns the normal.

    Args:
        geometry: The geometry; it must carry `skinIndex` and
            `skinWeight`.
        pose: The mesh's posed skeleton, from `skin_pose`.
        vertex_count: How many vertices the geometry has.

    Returns:
        One matrix per vertex.

    Raises:
        Error: If the geometry has no skin attributes, if either is not
            four numbers a vertex or does not cover every vertex, or if a
            vertex names a bone that is not a whole number in range or
            carries weights that are not numbers or are negative.
    """
    var out = List[Matrix4]()
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
    var count = len(pose.palette)
    # One pair of lists for the whole mesh. They were built per vertex,
    # which is two allocations per vertex per frame to hold four numbers
    # each, and the four are overwritten every time round anyway.
    var named = List[Int](length=BONES_PER_VERTEX, fill=0)
    var shares = List[Float32](length=BONES_PER_VERTEX, fill=0)
    for vertex in range(vertex_count):  # pragma: no branch
        for slot in range(BONES_PER_VERTEX):  # pragma: no branch
            named[slot] = whole_bone(bones.component(vertex, slot), count)
            shares[slot] = weights.component(vertex, slot)
        var blended = blend_bones(pose.palette, named, shares)
        # Into the bones' space, through them, and back out: three.js's
        # `bindMatrixInverse * skinMatrix * bindMatrix`.
        var carry = Matrix4(copy=pose.bind_inverse)
        carry.multiply(blended)
        carry.multiply(pose.bind)
        # three.js keeps the `xyz` of that product and drops its `w`, which
        # is the weights' sum. A bottom row of (0, 0, 0, 1) makes
        # `transform_point` do the same, so weights that do not sum to one
        # scale the vertex as they do there, and are not divided back out.
        carry.elements[3] = 0
        carry.elements[7] = 0
        carry.elements[11] = 0
        carry.elements[15] = 1
        out.append(carry^)
    return out^


def displaced_positions(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
    carriers: List[Matrix4],
    material: Material,
    textures: TextureStore,
) raises -> List[Vector3]:
    """Return where every vertex is once its morph targets are worn, its
    bones have carried it and its material's displacement map has moved
    it: three.js's `morphtarget_vertex`, `skinning_vertex` and
    `displacementmap_vertex`, in that order.

    Each vertex moves along its own normal, morphed and carried the same
    way and made unit length, by the map's red channel times the scale,
    plus the bias. The map is sampled at the vertex's texture coordinate
    through the map's own `uv_transform`, as three.js's
    `vDisplacementMapUv` is, from the full-size image by the map's own
    filter. A geometry with no `uv` samples at the origin, as a vertex
    shader reads a missing attribute as zero.

    Args:
        geometry: The geometry, which must have positions and normals.
        influences: How much of each of its targets the mesh wears.
        carriers: One matrix per vertex that the bones carry it by, or
            none for a mesh no skeleton moves; see `skin_carriers`.
        material: The material, which must name a displacement map.
        textures: Where the map lives.

    Returns:
        One point per vertex, in the geometry's own space, carried already:
        the caller must not carry them again.

    Raises:
        Error: For anything `Material.check_displacement` raises for, if
            the material names no displacement map or one that is not in
            the store, if the map is not stored as data, if the geometry
            has no normals or fewer normals or coordinates than vertices,
            or for anything `morphed_positions` raises for.
    """
    material.check_displacement()
    var map = material.displacement_map
    if map == NO_TEXTURE or map.value >= textures.count():
        raise Error("A material names a displacement map that is not there")
    ref heights = textures.get(map)
    check_data_map(heights, "A displacement map")
    if not geometry.has_attribute(String(NORMAL)):
        raise Error(
            "A displacement map moves each vertex along its normal: the"
            " geometry has no normals"
        )
    var points = morphed_positions(geometry, influences)
    var normals = morphed_normals(geometry, influences)
    if len(normals) < len(points):
        raise Error("A displaced geometry needs a normal for every vertex")
    var to_uv = heights.uv_transform()
    var at = List[Vector2](
        length=len(points), fill=to_uv.transform_point(Vector2(0, 0))
    )
    if geometry.has_attribute(String(UV)):
        ref uvs = geometry.attribute_view(String(UV))
        for vertex in range(len(points)):
            at[vertex] = to_uv.transform_point(
                Vector2(uvs.component(vertex, 0), uvs.component(vertex, 1))
            )
    var carried = len(carriers) > 0
    var scale = material.displacement_scale.to(METER)
    var bias = material.displacement_bias.to(METER)
    var out = List[Vector3]()
    for vertex in range(len(points)):
        var point = points[vertex]
        var facing = normals[vertex]
        if carried:
            point = carriers[vertex].transform_point(point)
            facing = carriers[vertex].transform_direction(facing)
        facing.normalize()
        # `texture2D( displacementMap, uv ).x * scale + bias`, then along
        # the normal, as three.js's shader writes it.
        var height = heights.sample(at[vertex].x, at[vertex].y).r * scale + bias
        out.append(point + facing * height)
    return out^
