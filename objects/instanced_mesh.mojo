# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One geometry drawn many times, from three.js `src/objects/InstancedMesh.js`
and `src/objects/BatchedMesh.js`.

A forest is one tree at two hundred places. A `Mesh` per tree is two
hundred nodes, two hundred draw-order entries and two hundred bounds
tests; an `InstancedMesh` is one node, one material, and two hundred
matrices, each placing one copy of the geometry relative to the node.
three.js's instancing exists to make one GPU draw call of it. Here there
are no draw calls, and what it saves is the scene graph: the copies do not
need nodes. The renderer prepares each instance whose bound is in view,
and orders every instance on its own, nearest first among the opaque and
furthest first among the translucent, where three.js keeps an
InstancedMesh's instances together; a software renderer that prepares
every instance anyway can afford to order them right.

A `BatchedMesh` is the same idea with a geometry per instance: a forest of
three kinds of tree under one material, each instance one geometry id
and one matrix, held together as a `BatchedInstance` so that neither can
be edited without the other. three.js's `BatchedMesh` copies the
geometries into one shared buffer, which is what makes its one draw call
possible; here every geometry already lives in the store, so an instance
simply names one.

Both hold their matrices as three.js holds `instanceMatrix`: relative to
the node, so that moving the node moves the whole forest, and read and
written one at a time with `matrix_at` and `set_matrix_at`. An instance
index is a plain number, as three.js's `instanceId` is: it is an index
into a list this object owns, not an id another store could confuse it
with, and it is checked against the count wherever it is used.

An instance matrix must place: it moves, turns, scales, shears or
mirrors, and keeps `w` at one, with every element a finite number. A
matrix that projects is refused, because everything downstream carries
positions, bounds and normals as an affine transform carries them, and a
homogeneous divide would bend the positions while the normals kept the
affine answer. The lists are open, as every field here is, so the
renderer asks the same question again of each matrix it draws.

Both hold a color per instance, three.js's `instanceColor` and
`BatchedMesh.setColorAt`. It multiplies the material's color, as a vertex
color does, and a geometry's own vertex colors multiply it again. An
instanced mesh has no colors until the first `set_color_at`, which starts
every instance at white, as three.js does; a batch member is white until
set.

An instanced mesh can also give each instance its own morph weights,
three.js's `setMorphAt`. The renderer morphs each instance by them, where
three.js reads them from its `morphTexture`. An instance past the end of
`morphs` wears none.

## Managing a batch

A batch follows three.js's `BatchedMesh` API. `delete_instance` frees an
index, and the next `add_instance` reuses the lowest free one.
`set_visible_at` hides an instance without deleting it. `add_geometry`
gives a geometry a range of the batch's buffers, `delete_geometry`
deletes a geometry's instances and frees its range, and `optimize` closes
the gaps. `set_instance_count` and `set_geometry_size` resize the batch,
and refuse to cut off what is in use.

three.js copies each geometry into buffers the batch shares, so its ranges
are memory. Here each geometry stays in the store, and a range is
bookkeeping: the same starts, counts and refusals, with no copy behind
them. An instance can still draw a geometry that has no range.

`per_object_frustum_culled` tests each instance against the frustum, as
three.js's does. With it off, the batch is left out only when every
instance is out of view. three.js tests one sphere around them all, which
can keep a batch whose instances are all out of view.

`set_custom_sort` orders the instances in view with a function, three.js's
`setCustomSort`. The batch is then drawn as one object at its node's
depth, in that order. Without one, each instance sorts on its own among
the scene's draws; see `renderers.renderer`.
"""

from core.buffer_geometry import BufferGeometry
from core.geometry_store import GeometryId
from core.morph import MorphInfluences
from core.object3d import NodeId
from materials.material import MaterialId
from math.matrix4 import Matrix4
from render.framebuffer import Color
from std.math import isfinite

comptime WHITE = Color(255, 255, 255)


def check_placing(matrix: Matrix4) raises:
    """Refuse a matrix that cannot place an instance.

    Args:
        matrix: The transform an instance is to have, relative to its node.

    Raises:
        Error: If an element is infinite or not a number, or the matrix
            projects rather than keeping `w` at one.
    """
    if not matrix.is_finite():
        raise Error("An instance matrix must hold finite numbers")
    if not matrix.is_affine():
        raise Error(
            "An instance matrix must be affine: it moves, turns, scales or"
            " shears, and keeps w at one"
        )


struct InstancedMesh(Copyable, Movable):
    """One geometry drawn with one material at many transforms, each
    relative to one scene node."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    # Whether the renderer may skip an instance whose bounding sphere,
    # carried to world space, lies outside the camera's frustum. Tested per
    # instance here, where three.js tests the whole group's bound once.
    var frustum_culled: Bool
    # One transform per instance, relative to the node: three.js's
    # `instanceMatrix`. The identity until set, so a fresh instanced mesh
    # draws every copy on top of the node.
    var matrices: List[Matrix4]
    # One color per instance, three.js's `instanceColor`, or none at all:
    # empty until the first `set_color_at`. `color_at` reads an instance
    # past its end as white, and so does the renderer.
    var colors: List[Color]
    # How much of each morph target each instance wears, three.js's
    # `morphTexture`, or none at all: empty until the first
    # `set_morph_at`. An instance with none wears no target.
    var morphs: List[MorphInfluences]
    # Whether the instances are drawn into the lights' shadow maps, and
    # whether their shadows fall on them: three.js's `castShadow` and
    # `receiveShadow`, both off by default as there.
    var cast_shadow: Bool
    var receive_shadow: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        count: Int,
        *,
        frustum_culled: Bool = True,
        cast_shadow: Bool = False,
        receive_shadow: Bool = False,
    ) raises:
        """Bind a stored geometry and material to a scene node, `count`
        times over.

        Args:
            geometry: Id of the geometry every instance draws.
            material: Id of the material every instance is drawn with.
            node: Index of the scene node the instances are placed
                relative to.
            count: How many instances, each starting at the identity.
            frustum_culled: Whether the renderer may skip an instance whose
                bounds are out of view.
            cast_shadow: Whether the instances are drawn into the shadow
                maps, three.js's `castShadow`. Off unless said otherwise.
            receive_shadow: Whether the shadows fall on the instances,
                three.js's `receiveShadow`. Off unless said otherwise.

        Raises:
            Error: If any id is negative, or the count is.
        """
        if node.value < 0:
            raise Error("An instanced mesh must name a scene node")
        if geometry.value < 0:
            raise Error("An instanced mesh must name a geometry")
        if material.value < 0:
            raise Error("An instanced mesh must name a material")
        if count < 0:
            raise Error("An instanced mesh cannot have a negative count")
        self.geometry = geometry
        self.material = material
        self.node = node
        self.frustum_culled = frustum_culled
        self.matrices = List[Matrix4](length=count, fill=Matrix4())
        self.colors = List[Color]()
        self.morphs = List[MorphInfluences]()
        self.cast_shadow = cast_shadow
        self.receive_shadow = receive_shadow

    def count(self) -> Int:
        """Return how many instances there are, three.js's `count`."""
        return len(self.matrices)

    def matrix_at(self, index: Int) raises -> Matrix4:
        """Return one instance's transform, three.js's `getMatrixAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            Its transform relative to the node.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        return Matrix4(copy=self.matrices[index])

    def set_matrix_at(mut self, index: Int, matrix: Matrix4) raises:
        """Place one instance, three.js's `setMatrixAt`.

        Args:
            index: Which instance, from zero.
            matrix: Its transform relative to the node: affine and finite.

        Raises:
            Error: If there is no such instance, or the matrix cannot
                place one; see `check_placing`.
        """
        self._check(index)
        check_placing(matrix)
        self.matrices[index] = Matrix4(copy=matrix)

    def color_at(self, index: Int) raises -> Color:
        """Return one instance's color, three.js's `getColorAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            Its color, sRGB. White when it has no color: none has one yet,
            or it was appended to `matrices` after the colors were made.
            three.js reads a missing `instanceColor` as white too.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        if index >= len(self.colors):
            return WHITE
        return self.colors[index]

    def set_color_at(mut self, index: Int, color: Color) raises:
        """Color one instance, three.js's `setColorAt`.

        The first call gives every instance a color, white for the rest.
        A later call after `matrices` grew gives the new instances white.

        Args:
            index: Which instance, from zero.
            color: Its color, sRGB. It multiplies the material's color.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        while len(self.colors) < len(self.matrices):
            self.colors.append(WHITE)
        self.colors[index] = color

    def morph_at(self, index: Int) raises -> MorphInfluences:
        """Return how much of each morph target one instance wears,
        three.js's `getMorphAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            A copy of its weights. None held, every target at zero, when
            no instance has weights yet or it was appended after they were
            made.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        if index >= len(self.morphs):
            return MorphInfluences()
        return MorphInfluences(copy=self.morphs[index])

    def set_morph_at(mut self, index: Int, influences: MorphInfluences) raises:
        """Set how much of each morph target one instance wears, three.js's
        `setMorphAt`, which copies a mesh's `morphTargetInfluences`.

        The first call gives every instance weights, none held for the
        rest. The renderer morphs each instance by its own weights, as a
        mesh is morphed by its own.

        Args:
            index: Which instance, from zero.
            influences: Its weights, copied.

        Raises:
            Error: If there is no such instance, or a weight is not a
                number.
        """
        self._check(index)
        for target in range(len(influences)):
            if not isfinite(influences[target]):
                raise Error("A morph weight must be a number")
        while len(self.morphs) < len(self.matrices):
            self.morphs.append(MorphInfluences())
        self.morphs[index] = MorphInfluences(copy=influences)

    def _check(self, index: Int) raises:
        """Refuse an instance index that names no instance."""
        if index < 0 or index >= len(self.matrices):
            raise Error("No instance has that index")


struct BatchedInstance(ImplicitlyCopyable):
    """One member of a batch: which geometry it draws, and where."""

    var geometry: GeometryId
    var matrix: Matrix4
    # Its color, sRGB, which multiplies the material's; white until set.
    var color: Color
    # Whether it is drawn and picked: three.js's `visible` in
    # `_instanceInfo`, set by `set_visible_at`.
    var visible: Bool
    # Whether it exists: three.js's `active`, false once deleted. A deleted
    # instance's index is reused by the next `add_instance`.
    var active: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        matrix: Matrix4,
        color: Color,
        *,
        visible: Bool = True,
        active: Bool = True,
    ):
        """Hold one member of a batch.

        Args:
            geometry: The geometry it draws.
            matrix: Its transform relative to the batch's node.
            color: Its color, sRGB.
            visible: Whether it is drawn.
            active: Whether it exists.
        """
        self.geometry = geometry
        self.matrix = Matrix4(copy=matrix)
        self.color = color
        self.visible = visible
        self.active = active

    def __init__(out self, *, copy: Self):
        """Copy a member.

        Args:
            copy: The member to copy.
        """
        self.geometry = copy.geometry
        self.matrix = Matrix4(copy=copy.matrix)
        self.color = copy.color
        self.visible = copy.visible
        self.active = copy.active


@fieldwise_init
struct BatchedGeometry(ImplicitlyCopyable):
    """Where one geometry's vertices and indices lie in a batch's shared
    buffers: three.js's entry in `_geometryInfo`, which
    `get_geometry_range_at` returns.

    A start or a count is -1 where three.js's is: the index fields of a
    geometry with no index."""

    # Which geometry of the store the range holds.
    var geometry: GeometryId
    var vertex_start: Int
    var vertex_count: Int
    var reserved_vertex_count: Int
    var index_start: Int
    var index_count: Int
    var reserved_index_count: Int
    # Whether the range is in use: false once `delete_geometry` frees it.
    var active: Bool

    def start(self) -> Int:
        """Return where the geometry's draw range starts, three.js's
        `start`: its index start, or its vertex start without an index."""
        if self.index_start >= 0:
            return self.index_start
        return self.vertex_start

    def count(self) -> Int:
        """Return how long the draw range is, three.js's `count`."""
        if self.index_start >= 0:
            return self.index_count
        return self.vertex_count


@fieldwise_init
struct BatchedDrawItem(ImplicitlyCopyable):
    """One instance about to be drawn, as a custom sort sees it: three.js's
    entry in the `MultiDrawRenderList`."""

    # Which instance.
    var index: Int
    # How far in front of the camera its origin is, in meters: three.js's
    # `z`, which it measures to the instance's bounding sphere center.
    var z: Float32


# A custom sort, three.js's `customSort(list, camera)`: it reorders the list
# of instances in view in place. The camera is not passed; each item's `z`
# carries what three.js reads from it.
comptime BatchedSort = def(mut List[BatchedDrawItem]) thin -> None


def _keep_order(mut items: List[BatchedDrawItem]):
    """Leave the list as it is: the sort of a batch with no custom sort."""
    pass


# The largest count a batch accepts when none is given. three.js has no
# default: its constructor asks for all three.
comptime NO_LIMIT = Int.MAX


struct BatchedMesh(Copyable, Movable):
    """Many geometries drawn with one material at many transforms, each
    relative to one scene node: an instanced mesh whose instances each
    name their own geometry."""

    var material: MaterialId
    var node: NodeId
    # three.js's `frustumCulled`: whether the renderer may leave the batch
    # out when it lies wholly outside the camera's frustum.
    var frustum_culled: Bool
    # three.js's `perObjectFrustumCulled`: whether each instance is tested
    # on its own. Only read when `frustum_culled` is on.
    var per_object_frustum_culled: Bool
    # Each instance's geometry and transform, together, by index. A
    # deleted one stays, inactive, until its index is reused.
    var instances: List[BatchedInstance]
    # The indices of the deleted instances: three.js's
    # `_availableInstanceIds`.
    var available_instances: List[Int]
    # The geometries given a range with `add_geometry`: three.js's
    # `_geometryInfo`. A freed range stays, inactive, until reused.
    var geometries: List[BatchedGeometry]
    # The slots of the freed ranges: three.js's `_availableGeometryIds`.
    var available_geometries: List[Int]
    # The sizes three.js's constructor and `setInstanceCount` and
    # `setGeometrySize` set.
    var max_instance_count: Int
    var max_vertex_count: Int
    var max_index_count: Int
    # Where the next range starts: three.js's `_nextVertexStart` and
    # `_nextIndexStart`.
    var next_vertex_start: Int
    var next_index_start: Int
    # Whether the ranges hold indices, set by the first `add_geometry`.
    var indexed: Optional[Bool]
    # three.js's `customSort`, used when `custom_sorted` is set.
    var custom_sort: BatchedSort
    var custom_sorted: Bool
    # Whether the instances are drawn into the lights' shadow maps, and
    # whether their shadows fall on them: three.js's `castShadow` and
    # `receiveShadow`, both off by default as there.
    var cast_shadow: Bool
    var receive_shadow: Bool

    def __init__(
        out self,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
        per_object_frustum_culled: Bool = True,
        max_instance_count: Int = NO_LIMIT,
        max_vertex_count: Int = NO_LIMIT,
        max_index_count: Int = NO_LIMIT,
        cast_shadow: Bool = False,
        receive_shadow: Bool = False,
    ) raises:
        """Start an empty batch on a scene node, three.js's
        `new BatchedMesh(maxInstanceCount, maxVertexCount, maxIndexCount,
        material)`.

        Args:
            material: Id of the material every instance is drawn with.
            node: Index of the scene node the instances are placed
                relative to.
            frustum_culled: Whether the renderer may leave the batch out
                when it is out of view.
            per_object_frustum_culled: Whether each instance is tested on
                its own, as three.js's default is.
            max_instance_count: How many instances the batch holds at
                most. No limit by default.
            max_vertex_count: How many vertices the ranges of
                `add_geometry` hold at most. No limit by default.
            max_index_count: How many indices the ranges hold at most. No
                limit by default. three.js's default is twice the vertices.
            cast_shadow: Whether the instances are drawn into the shadow
                maps, three.js's `castShadow`. Off unless said otherwise.
            receive_shadow: Whether the shadows fall on the instances,
                three.js's `receiveShadow`. Off unless said otherwise.

        Raises:
            Error: If either id is negative, or a count is.
        """
        if node.value < 0:
            raise Error("A batched mesh must name a scene node")
        if material.value < 0:
            raise Error("A batched mesh must name a material")
        if (
            max_instance_count < 0
            or max_vertex_count < 0
            or max_index_count < 0
        ):
            raise Error("A batched mesh cannot hold a negative count")
        self.material = material
        self.node = node
        self.frustum_culled = frustum_culled
        self.per_object_frustum_culled = per_object_frustum_culled
        self.instances = List[BatchedInstance]()
        self.available_instances = List[Int]()
        self.geometries = List[BatchedGeometry]()
        self.available_geometries = List[Int]()
        self.max_instance_count = max_instance_count
        self.max_vertex_count = max_vertex_count
        self.max_index_count = max_index_count
        self.next_vertex_start = 0
        self.next_index_start = 0
        self.indexed = None
        self.custom_sort = _keep_order
        self.custom_sorted = False
        self.cast_shadow = cast_shadow
        self.receive_shadow = receive_shadow

    def count(self) -> Int:
        """Return how many instance indices are in use or free: three.js's
        `_instanceInfo.length`. `instance_count` leaves out the deleted."""
        return len(self.instances)

    def instance_count(self) -> Int:
        """Return how many instances exist, three.js's `instanceCount`."""
        return len(self.instances) - len(self.available_instances)

    def unused_vertex_count(self) -> Int:
        """Return how many vertices the ranges have left, three.js's
        `unusedVertexCount`."""
        return self.max_vertex_count - self.next_vertex_start

    def unused_index_count(self) -> Int:
        """Return how many indices the ranges have left, three.js's
        `unusedIndexCount`."""
        return self.max_index_count - self.next_index_start

    def is_drawn(self, index: Int) -> Bool:
        """Return True if an instance exists and is visible: what the
        renderer and the raycaster draw and pick.

        Args:
            index: Which instance, from zero.

        Returns:
            False for an index past the end.
        """
        if index < 0 or index >= len(self.instances):
            return False
        return self.instances[index].active and self.instances[index].visible

    def add_instance(
        mut self, geometry: GeometryId, matrix: Matrix4 = Matrix4()
    ) raises -> Int:
        """Add an instance, three.js's `addInstance`, and return its index.

        The lowest index a deleted instance freed is reused first, as
        three.js reuses it.

        Args:
            geometry: Id of the geometry it draws. Whether the store has it
                is checked when the scene renders, as a mesh's is.
            matrix: Its transform relative to the node, affine and finite;
                the identity if not given.

        Returns:
            The new instance's index, for `set_matrix_at` and the rest.

        Raises:
            Error: If the geometry id is negative, the matrix cannot place
                an instance (see `check_placing`), or the batch holds
                `max_instance_count` instances and none is free.
        """
        if geometry.value < 0:
            raise Error("A batched instance must name a geometry")
        check_placing(matrix)
        var full = len(self.instances) >= self.max_instance_count
        if full and len(self.available_instances) == 0:
            raise Error("A batched mesh holds no more instances")
        var member = BatchedInstance(geometry, Matrix4(copy=matrix), WHITE)
        if len(self.available_instances) > 0:
            var index = _take_lowest(self.available_instances)
            self.instances[index] = member
            return index
        self.instances.append(member)
        return len(self.instances) - 1

    def delete_instance(mut self, index: Int) raises:
        """Delete an instance, three.js's `deleteInstance`. Its index is
        free for the next `add_instance`.

        Args:
            index: Which instance, from zero.

        Raises:
            Error: If there is no such instance, or it is deleted already.
        """
        self._check(index)
        self.instances[index].active = False
        self.available_instances.append(index)

    def set_visible_at(mut self, index: Int, visible: Bool) raises:
        """Show or hide an instance, three.js's `setVisibleAt`.

        Args:
            index: Which instance, from zero.
            visible: Whether it is drawn and picked.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        self.instances[index].visible = visible

    def visible_at(self, index: Int) raises -> Bool:
        """Return whether an instance is shown, three.js's `getVisibleAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            Its visibility.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        return self.instances[index].visible

    def add_geometry(
        mut self,
        id: GeometryId,
        geometry: BufferGeometry,
        reserved_vertex_count: Int = -1,
        reserved_index_count: Int = -1,
    ) raises -> GeometryId:
        """Give a geometry a range of the batch's buffers, three.js's
        `addGeometry`, and return its id.

        three.js copies the geometry into buffers the batch shares. Here
        every geometry stays in the store, so the range is bookkeeping
        only: it is what `max_vertex_count`, `optimize` and
        `set_geometry_size` measure. An instance can draw a geometry
        without a range, as it could before this port had ranges.

        Args:
            id: The geometry's id in the store.
            geometry: The geometry itself, for its counts.
            reserved_vertex_count: How many vertices to reserve, or -1 for
                as many as it has.
            reserved_index_count: How many indices to reserve, or -1 for as
                many as it has.

        Returns:
            `id`, for `add_instance`.

        Raises:
            Error: If the id is negative or already has a range, the
                geometry has no positions, it has an index where the ranges
                before it had none or the other way round, a reservation is
                smaller than the geometry, or the range does not fit in
                `max_vertex_count` and `max_index_count`.
        """
        if id.value < 0:
            raise Error("A batched geometry must name a geometry")
        if self._range_of(id) >= 0:
            raise Error("A batched geometry has a range already")
        var has_index = geometry.is_indexed()
        if Bool(self.indexed) and self.indexed.value() != has_index:
            raise Error(
                "Every geometry of a batch must have an index, or none must"
            )
        var vertices = geometry.vertex_count()
        var indices = len(geometry.index)
        var vertex_room = vertices if reserved_vertex_count == -1 else (
            reserved_vertex_count
        )
        var index_room = indices if reserved_index_count == -1 else (
            reserved_index_count
        )
        if vertex_room < vertices or index_room < indices:
            raise Error("A reserved range is smaller than its geometry")
        var index_start = -1
        if has_index:
            index_start = self.next_index_start
        else:
            index_room = -1
            indices = -1
        var too_many_indices = (
            has_index and index_start + index_room > self.max_index_count
        )
        if (
            self.next_vertex_start + vertex_room > self.max_vertex_count
            or too_many_indices
        ):
            raise Error("A reserved range does not fit in the batch")
        var span = BatchedGeometry(
            id,
            self.next_vertex_start,
            vertices,
            vertex_room,
            index_start,
            indices,
            index_room,
            True,
        )
        if len(self.available_geometries) > 0:
            self.geometries[_take_lowest(self.available_geometries)] = span
        else:
            self.geometries.append(span)
        self.indexed = has_index
        self.next_vertex_start += vertex_room
        if has_index:
            self.next_index_start = index_start + index_room
        return id

    def delete_geometry(mut self, id: GeometryId) raises:
        """Delete every instance that draws a geometry, and free its range,
        three.js's `deleteGeometry`.

        Args:
            id: The geometry's id in the store.

        Raises:
            Error: If the id is negative.
        """
        if id.value < 0:
            raise Error("A batched geometry must name a geometry")
        for index in range(len(self.instances)):
            ref member = self.instances[index]
            if member.active and member.geometry == id:
                self.delete_instance(index)
        var slot = self._range_of(id)
        if slot >= 0:
            self.geometries[slot].active = False
            self.available_geometries.append(slot)

    def get_geometry_range_at(self, id: GeometryId) raises -> BatchedGeometry:
        """Return a geometry's range, three.js's `getGeometryRangeAt`.

        Args:
            id: The geometry's id in the store.

        Returns:
            Its span.

        Raises:
            Error: If the geometry has no span.
        """
        var slot = self._range_of(id)
        if slot < 0:
            raise Error("That geometry has no range in the batch")
        return self.geometries[slot]

    def optimize(mut self):
        """Close the gaps freed ranges left, three.js's `optimize`: every
        range in use moves down to follow the one before it, in the order
        they lie."""
        var order = List[Int]()
        for slot in range(len(self.geometries)):
            var at = len(order)
            while (
                at > 0
                and self.geometries[order[at - 1]].vertex_start
                > self.geometries[slot].vertex_start
            ):
                at -= 1
            order.insert(at, slot)
        var next_vertex = 0
        var next_index = 0
        for slot in order:
            ref span = self.geometries[slot]
            if not span.active:
                continue
            if span.index_start >= 0:
                span.index_start = next_index
                next_index += span.reserved_index_count
                self.next_index_start = next_index
            span.vertex_start = next_vertex
            next_vertex += span.reserved_vertex_count
            self.next_vertex_start = next_vertex

    def set_instance_count(mut self, count: Int) raises:
        """Change how many instances the batch holds at most, three.js's
        `setInstanceCount`.

        The deleted instances at the end are dropped first, so that their
        indices do not count against the new size.

        Args:
            count: The new largest count.

        Raises:
            Error: If an instance at or past `count` is in use.
        """
        _sort_ascending(self.available_instances)
        while (
            len(self.available_instances) > 0
            and self.available_instances[len(self.available_instances) - 1]
            == len(self.instances) - 1
        ):
            _ = self.instances.pop()
            _ = self.available_instances.pop()
        if count < len(self.instances):
            raise Error(
                "A batched mesh cannot shrink below the instances it uses"
            )
        self.max_instance_count = count

    def set_geometry_size(
        mut self, max_vertex_count: Int, max_index_count: Int
    ) raises:
        """Change how many vertices and indices the ranges hold at most,
        three.js's `setGeometrySize`.

        Args:
            max_vertex_count: The new largest vertex count.
            max_index_count: The new largest index count.

        Raises:
            Error: If a range in use reaches past either.
        """
        for span in self.geometries:
            if not span.active:
                continue
            if (
                span.vertex_start + span.reserved_vertex_count
                > max_vertex_count
            ):
                raise Error(
                    "A batched mesh cannot shrink below the vertices it uses"
                )
            var end = span.index_start + span.reserved_index_count
            if span.index_start >= 0 and end > max_index_count:
                raise Error(
                    "A batched mesh cannot shrink below the indices it uses"
                )
        self.max_vertex_count = max_vertex_count
        self.max_index_count = max_index_count

    def set_custom_sort(mut self, sort: BatchedSort):
        """Order the batch's instances with a function of your own,
        three.js's `setCustomSort`.

        The renderer then draws the instances in view in the order the
        function leaves them, together, at the depth of the batch's node,
        as three.js draws a batch as one object. Without a custom sort each
        instance is sorted among the scene's draws by its own depth.

        Args:
            sort: The function. It is given the instances in view.
        """
        self.custom_sort = sort
        self.custom_sorted = True

    def clear_custom_sort(mut self):
        """Go back to the renderer's own order, three.js's
        `setCustomSort(null)`."""
        self.custom_sort = _keep_order
        self.custom_sorted = False

    def geometry_at(self, index: Int) raises -> GeometryId:
        """Return which geometry one instance draws, three.js's
        `getGeometryIdAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            Its geometry id.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        return self.instances[index].geometry

    def set_geometry_at(mut self, index: Int, geometry: GeometryId) raises:
        """Change which geometry one instance draws, three.js's
        `setGeometryIdAt`.

        Args:
            index: Which instance, from zero.
            geometry: Its new geometry id.

        Raises:
            Error: If there is no such instance, or the id is negative.
        """
        self._check(index)
        if geometry.value < 0:
            raise Error("A batched instance must name a geometry")
        self.instances[index].geometry = geometry

    def matrix_at(self, index: Int) raises -> Matrix4:
        """Return one instance's transform, three.js's `getMatrixAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            Its transform relative to the node.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        return Matrix4(copy=self.instances[index].matrix)

    def set_matrix_at(mut self, index: Int, matrix: Matrix4) raises:
        """Place one instance, three.js's `setMatrixAt`.

        Args:
            index: Which instance, from zero.
            matrix: Its transform relative to the node: affine and finite.

        Raises:
            Error: If there is no such instance, or the matrix cannot
                place one; see `check_placing`.
        """
        self._check(index)
        check_placing(matrix)
        self.instances[index].matrix = Matrix4(copy=matrix)

    def color_at(self, index: Int) raises -> Color:
        """Return one instance's color, three.js's `getColorAt`.

        Args:
            index: Which instance, from zero.

        Returns:
            Its color, sRGB.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        return self.instances[index].color

    def set_color_at(mut self, index: Int, color: Color) raises:
        """Color one instance, three.js's `setColorAt`.

        Args:
            index: Which instance, from zero.
            color: Its color, sRGB. It multiplies the material's color.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        self.instances[index].color = color

    def _check(self, index: Int) raises:
        """Refuse an instance index that names no instance, or a deleted
        one: three.js's `validateInstanceId`."""
        if index < 0 or index >= len(self.instances):
            raise Error("No instance has that index")
        if not self.instances[index].active:
            raise Error("That instance has been deleted")

    def _range_of(self, id: GeometryId) -> Int:
        """Return the slot of a geometry's range in use, or -1."""
        var found = -1
        for slot in range(len(self.geometries)):
            ref span = self.geometries[slot]
            if span.active and span.geometry == id:
                found = slot
        return found


def _sort_ascending(mut values: List[Int]):
    """Sort a short list of indices, smallest first, in place."""
    for position in range(1, len(values)):
        var value = values[position]
        var at = position
        while at > 0 and values[at - 1] > value:
            values[at] = values[at - 1]
            at -= 1
        values[at] = value


def _take_lowest(mut values: List[Int]) -> Int:
    """Remove and return the smallest of a list that is not empty, as
    three.js's `sort(ascIdSort)` then `shift()` does."""
    _sort_ascending(values)
    return values.pop(0)
