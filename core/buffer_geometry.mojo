# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh's vertex data, from three.js `src/core/BufferGeometry.js`.

A geometry is a bag of named attributes — `position` at minimum, later
`normal` and `uv` — plus an optional index buffer saying which vertices make
up each triangle. Indexing exists so a vertex shared by several triangles is
stored once; a cube's eight corners serve thirty-six triangle slots.

Without an index, vertices are taken three at a time in order. three.js allows
both and so does this.

Reading an attribute borrows it; copying one is a separate call with copy in
its name. That distinction is the whole reason `attribute_view` exists next to
`clone_attribute`: a single accessor that returned an owning copy made every
read allocate, and reads are what a renderer does constantly.

The attributes are held as two parallel lists rather than a `Dict`, which is
the concession that makes the borrowing accessor usable. Mojo gives every value
in a `Dict` the same symbolic origin, so taking a view of `normal` invalidates
an outstanding view of `position` — the compiler cannot tell the two apart, and
a renderer that wants both at once is refused. List elements share an origin
too, but one the compiler does not invalidate on a second borrow. Two lists
also keep insertion order, which a `Dict` does not promise and a GPU upload
will eventually want.

The examples grew these arrays by hand before this module existed, and two of
them had drifted into near-identical copies. That duplication is what a
geometry type is for.

## Morph targets

A geometry can also carry *morph targets*: three.js's `morphAttributes`, a
second, third and further set of positions for the same vertices. A mesh
gives each one a weight, and the vertex it draws is the base vertex moved
toward those targets by their weights. That is how a face smiles: one
geometry, one target per expression, and a number per expression that says
how much of it to use.

The targets live here because they are vertex data, and the weights live on
the `Mesh` because they are what changes. Two meshes can share one head and
wear different expressions, which is the whole point and is the same
argument that put `position` here and the transform on the node.

`morph_relative` is three.js's `morphTargetsRelative`. False, the default,
means a target holds the *finished* positions and the mesh moves from the
base toward them. True means it holds the offsets to add. Exporters write
both, so both are read.

Normals may be morphed alongside positions, and either every target carries
them or none does. three.js allows the same, and a geometry whose targets
have no normals keeps the base normal -- which is what three.js's shader
does when `morphAttributes.normal` is absent.
"""

from core.buffer_attribute import BufferAttribute
from core.interleaved_buffer import InterleavedBuffer
from math.bounds import Box3, Sphere
from math.vector3 import Vector3
from std.math import isfinite

# How many morph targets one geometry may carry. This port's limit, and
# not three.js's: older three.js had a `MAX_MORPH_TARGETS` of eight because
# of how many attribute slots a WebGL program has, and current three.js
# passes the targets in a texture instead and is bounded by memory rather
# than by eight.
#
# Eight is here because a mesh holds its weights in a fixed row rather than
# a list, which is what keeps a `Mesh` implicitly copyable, and a row has
# to have a size. Widening it is changing one number and the tests that
# name it.
comptime MAX_MORPH_TARGETS = 8

# The attributes this port knows about, named as three.js names them.
# `position` is the only one a geometry must have.
comptime POSITION = "position"
comptime NORMAL = "normal"
# Texture coordinates, two per vertex. three.js's convention and OpenGL's: the
# origin is the bottom-left of the image and v grows upwards, which is the
# opposite of how a framebuffer's rows are numbered. Sampling is where that
# gets reconciled, not here.
comptime UV = "uv"
# A second set of texture coordinates, two per vertex, three.js's `uv1`.
# Read by an ambient occlusion map or a light map whose texture names
# `UV_CHANNEL_1`: a baked map is usually laid out apart from the color map.
comptime UV1 = "uv1"
# A color per vertex, three or four floats, in linear light as three.js's
# are since its color management: what a material's `vertex_colors`
# multiplies the material's color by. Decode an authored sRGB color with
# `FloatColor(srgb=...)` before storing it here.
comptime COLOR = "color"
# A tangent per vertex, four floats: the direction texture u grows along the
# surface, and in `w` which way v grows from it, one or minus one. What
# `compute_tangents` writes, and what a normal map needs to turn its texels
# into directions.
comptime TANGENT = "tangent"


def _shift(mut attribute: BufferAttribute, offset: Vector3) raises:
    """Move every item of a position attribute by one offset.

    An interleaved attribute moves in its shared buffer, and the other
    attributes on the buffer keep their numbers.

    Args:
        attribute: Positions, three or more numbers an item.
        offset: How far to move them.

    Raises:
        Error: If the attribute holds fewer than three numbers an item.
    """
    for vertex in range(attribute.count()):
        var moved = attribute.vector3(vertex) + offset
        attribute.set_component(vertex, 0, moved.x)
        attribute.set_component(vertex, 1, moved.y)
        attribute.set_component(vertex, 2, moved.z)


def _cloned(
    attributes: List[BufferAttribute],
    mut originals: List[InterleavedBuffer],
    mut clones: List[InterleavedBuffer],
) -> List[BufferAttribute]:
    """Return a copy of every attribute, with each interleaved buffer
    copied once.

    Args:
        attributes: The attributes to copy.
        originals: The buffers copied so far, appended to.
        clones: The copy of each of `originals`, appended to.

    Returns:
        The copies. An interleaved one reads the copy of its buffer.
    """
    var out = List[BufferAttribute](capacity=len(attributes))
    for slot in range(len(attributes)):
        ref attribute = attributes[slot]
        if not attribute.is_interleaved():
            out.append(attribute.copy())
            continue
        # Interleaved, so the handle is there.
        var buffer = attribute._buffer.value().copy()
        var found = -1
        for seen in range(len(originals)):
            if originals[seen].shares_with(buffer):
                found = seen
        if found < 0:
            found = len(originals)
            originals.append(buffer.copy())
            clones.append(buffer.clone())
        out.append(attribute.on_buffer(clones[found]))
    return out^


@fieldwise_init
struct MaterialIndex(Equatable, ImplicitlyCopyable, Writable):
    """Which of a mesh's materials a group of triangles wears, as a type
    rather than a bare int: three.js's `materialIndex`.

    A position in a list of materials, and not a `MaterialId`, which names a
    material in a store. The two are both small integers and mean different
    things, which is the reason for the type. `add_group` stops a negative
    one with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a position in a list: zero or more."""
        return self.value >= 0


@fieldwise_init
struct GeometryGroup(ImplicitlyCopyable):
    """A run of triangles that wears one material, three.js's geometry
    group.

    `start` and `count` are counted in index entries for an indexed
    geometry and in vertices for one without an index, as in three.js.
    """

    var start: Int
    var count: Int
    var material_index: MaterialIndex


struct BufferGeometry(Movable):
    """Named vertex attributes, with optional indexed triangles."""

    # Parallel arrays: `names[i]` is the name of `values[i]`. See the module
    # docstring for why this is not a Dict.
    var names: List[String]
    var values: List[BufferAttribute]
    var index: List[Int]
    # One further set of positions per morph target, each as long as
    # `position`. See the module docstring.
    var morph_positions: List[BufferAttribute]
    # The matching normals, either one per target or none at all.
    var morph_normals: List[BufferAttribute]
    # Whether a target holds finished positions or offsets to add:
    # three.js's `morphTargetsRelative`. Read only when there are targets,
    # and either answer is a legitimate one, so nothing checks it.
    var morph_relative: Bool
    # Each morph target's name, three.js's morph attribute `name`, which
    # its `morphTargetDictionary` is made from: empty, or one per target.
    var morph_names: List[String]
    # Runs of triangles that wear one material each: three.js's `groups`.
    # Empty means the whole geometry is one run. See `add_group`.
    var groups: List[GeometryGroup]
    # Whether the geometry is drawn once per instance, three.js's
    # `InstancedBufferGeometry`. See `BufferGeometry(instanced=True)`.
    var instanced: Bool
    # How many instances to draw, three.js's `instanceCount`, or none for
    # as many as the per-instance attributes hold: three.js's default of
    # `Infinity`. Read only when `instanced` is set.
    var instance_count: Optional[Int]

    def __init__(out self):
        """Create an empty geometry with no attributes and no index."""
        self = BufferGeometry(instanced=False)

    def __init__(out self, *, instanced: Bool):
        """Create an empty geometry, instanced or not.

        `BufferGeometry(instanced=True)` is three.js's
        `InstancedBufferGeometry`. A mesh draws it once per instance, and
        every attribute built with `mesh_per_attribute` advances once per
        instance rather than once per vertex. The renderer reads two of
        them: `offset`, which moves an instance, and `color`, which colors
        one when the material asks for vertex colors. See
        `drawn_instances`.

        Args:
            instanced: Whether the geometry is drawn once per instance.
        """
        self.names = List[String]()
        self.values = List[BufferAttribute]()
        self.index = List[Int]()
        self.morph_positions = List[BufferAttribute]()
        self.morph_normals = List[BufferAttribute]()
        self.morph_relative = False
        self.morph_names = List[String]()
        self.groups = List[GeometryGroup]()
        self.instanced = instanced
        self.instance_count = None

    def clone(self) -> BufferGeometry:
        """Return a copy of this geometry, three.js's `clone`.

        Copies every attribute, the index, the morph targets, the groups
        and the instancing. A geometry is not `Copyable`, so that a copy is
        always asked for by name and never made by an assignment.

        Each interleaved buffer is copied once, and the copied attributes
        that read it read the one copy, as three.js's `copy` does. So two
        attributes that shared a buffer still share one.

        Returns:
            The copy, which shares nothing with this geometry.
        """
        var copied = BufferGeometry(instanced=self.instanced)
        var originals = List[InterleavedBuffer]()
        var clones = List[InterleavedBuffer]()
        copied.names = self.names.copy()
        copied.values = _cloned(self.values, originals, clones)
        copied.index = self.index.copy()
        copied.morph_positions = _cloned(
            self.morph_positions, originals, clones
        )
        copied.morph_normals = _cloned(self.morph_normals, originals, clones)
        copied.morph_relative = self.morph_relative
        copied.morph_names = self.morph_names.copy()
        copied.groups = self.groups.copy()
        copied.instance_count = self.instance_count
        return copied^

    def set_instance_count(mut self, count: Int) raises:
        """Set how many instances to draw, three.js's `instanceCount`.

        Args:
            count: How many. Zero draws nothing.

        Raises:
            Error: If the geometry is not instanced, or `count` is negative.
        """
        if not self.instanced:
            raise Error("Only an instanced geometry has an instance count")
        if count < 0:
            raise Error("An instance count cannot be negative")
        self.instance_count = count

    def drawn_instances(self) raises -> Int:
        """Return how many instances a mesh draws of this geometry.

        three.js draws `instanceCount` instances, capped by the instances
        the per-instance attributes hold. The cap here is the smallest over
        every per-instance attribute: `count() * mesh_per_attribute()`.
        three.js takes it from the first attribute the shader reads, which
        a port without shaders cannot ask.

        Returns:
            The number of instances. One for a geometry that is not
            instanced.

        Raises:
            Error: If the instance count is negative, or it is left
                unbounded and no attribute is per instance.
        """
        if not self.instanced:
            return 1
        var cap = -1
        for slot in range(len(self.values)):
            ref attribute = self.values[slot]
            if attribute.is_instanced():
                var holds = attribute.count() * attribute.mesh_per_attribute()
                if cap < 0 or holds < cap:
                    cap = holds
        if Bool(self.instance_count):
            var count = self.instance_count.value()
            if count < 0:
                raise Error("An instance count cannot be negative")
            if cap < 0:
                return count
            return min(count, cap)
        if cap < 0:
            raise Error(
                "An instanced geometry with no per-instance attribute needs"
                " an instance count"
            )
        return cap

    def add_group(
        mut self,
        start: Int,
        count: Int,
        material_index: MaterialIndex = MaterialIndex(0),
    ) raises:
        """Add a run of triangles that wears one material, three.js's
        `addGroup`.

        A mesh that wears a list of materials draws each group in the
        material its index names; a mesh with one material draws every
        triangle and ignores the groups, as in three.js. See
        `objects.mesh`. `merge_geometries` writes groups and
        `compute_tangents` visits what they hold, as three.js's does.

        Args:
            start: The first index entry of the run, or the first vertex
                for a geometry without an index.
            count: How many entries or vertices the run holds.
            material_index: Which of the mesh's materials the run wears.

        Raises:
            Error: If `start` or `count` is negative, or the material index
                is not valid.
        """
        if start < 0 or count < 0:
            raise Error("A group cannot start or run a negative distance")
        if not material_index.is_valid():
            raise Error("A group's material index cannot be negative")
        self.groups.append(GeometryGroup(start, count, material_index))

    def clear_groups(mut self):
        """Remove every group, three.js's `clearGroups`."""
        self.groups.clear()

    def morph_count(self) -> Int:
        """Return how many morph targets the geometry carries."""
        return len(self.morph_positions)

    def has_morph_normals(self) -> Bool:
        """Return True if the morph targets carry normals as well as
        positions."""
        return len(self.morph_normals) > 0

    def _check_morph(self, attribute: BufferAttribute) raises:
        """Raise unless `attribute` can be a morph target of this geometry.

        Raises:
            Error: If the geometry has no positions, if the attribute is
                not three numbers a vertex, if it does not describe the
                same vertices the positions do, or if the geometry already
                holds `MAX_MORPH_TARGETS` of them.
        """
        if not self.has_attribute(String(POSITION)):
            raise Error("A morph target needs a geometry with positions")
        if attribute.item_size != 3:
            raise Error("A morph target holds three numbers a vertex")
        if attribute.count() != self.attribute_view(String(POSITION)).count():
            raise Error("A morph target must cover every vertex")
        if len(self.morph_positions) >= MAX_MORPH_TARGETS:
            raise Error("A geometry holds at most eight morph targets")

    def add_morph_target(mut self, var positions: BufferAttribute) raises:
        """Add one morph target's positions, with no normals.

        The base normal is then used whatever the weights are, which is
        what three.js's shader does when a target has no normals of its
        own.

        Args:
            positions: Where every vertex goes at full weight, or how far
                it moves when `morph_relative` is set.

        Raises:
            Error: If the target does not fit the geometry -- see
                `_check_morph` -- or if the targets already added carry
                normals, since either all of them do or none does.
        """
        self._check_morph(positions)
        if len(self.morph_normals) > 0:
            raise Error("Every morph target must carry normals, or none")
        self.morph_positions.append(positions^)

    def add_morph_target(
        mut self, var positions: BufferAttribute, var normals: BufferAttribute
    ) raises:
        """Add one morph target's positions and normals.

        Args:
            positions: Where every vertex goes at full weight.
            normals: Which way every vertex faces at full weight.

        Raises:
            Error: If either does not fit the geometry -- see
                `_check_morph` -- or if the targets already added carry no
                normals, since either all of them do or none does.
        """
        self._check_morph(positions)
        self._check_morph(normals)
        if len(self.morph_positions) != len(self.morph_normals):
            raise Error("Every morph target must carry normals, or none")
        self.morph_positions.append(positions^)
        self.morph_normals.append(normals^)

    def morph_position(self, target: Int, vertex: Int) raises -> Vector3:
        """Return where one vertex goes in one morph target.

        Args:
            target: Which target, from zero.
            vertex: Which vertex.

        Returns:
            The target's position for that vertex.

        Raises:
            Error: If there is no such target, or no such vertex.
        """
        if target < 0 or target >= len(self.morph_positions):
            raise Error("No morph target has that index")
        return self.morph_positions[target].vector3(vertex)

    def morph_normal(self, target: Int, vertex: Int) raises -> Vector3:
        """Return which way one vertex faces in one morph target.

        Args:
            target: Which target, from zero.
            vertex: Which vertex.

        Returns:
            The target's normal for that vertex.

        Raises:
            Error: If the targets carry no normals, if there is no such
                target, or no such vertex.
        """
        if target < 0 or target >= len(self.morph_normals):
            raise Error("No morph target has that normal")
        return self.morph_normals[target].vector3(vertex)

    def _slot(self, name: String) -> Int:
        """Return where `name` is stored, or -1 if it is not present."""
        for position in range(len(self.names)):
            if self.names[position] == name:
                return position
        return -1

    def set_attribute(mut self, name: String, var attribute: BufferAttribute):
        """Store `attribute` under `name`, replacing any previous one."""
        var slot = self._slot(name)
        if slot < 0:
            self.names.append(name)
            self.values.append(attribute^)
        else:
            self.values[slot] = attribute^

    def has_attribute(self, name: String) -> Bool:
        """Return True if an attribute of that name is present."""
        return self._slot(name) >= 0

    def attribute_count(self) -> Int:
        """Return how many named attributes this geometry holds."""
        return len(self.names)

    def attribute_view(
        self, name: String
    ) raises -> ref[origin_of(self.values[0])] BufferAttribute:
        """Return a borrowed view of the named attribute.

        This is the ordinary way to read vertex data, and it copies nothing.
        The reference borrows from the geometry, so the geometry must outlive
        it; the compiler enforces that rather than trusting the caller.

        Binding the result with `var` is a compile error rather than a silent
        copy, because `BufferAttribute` is `Copyable` but not
        `ImplicitlyCopyable`. Bind it with `ref`, or say `clone_attribute` if
        a copy is genuinely what was meant.

        The borrow is immutable, which is what lets a caller hold views of
        `position` and `normal` at the same time.

        Args:
            name: Which attribute to read.

        Returns:
            A reference to it, valid as long as this geometry is.

        Raises:
            Error: If the geometry has no such attribute.
        """
        var slot = self._slot(name)
        if slot < 0:
            raise Error("This geometry has no attribute named " + name)
        return self.values[slot]

    def clone_attribute(self, name: String) raises -> BufferAttribute:
        """Return an owning copy of the named attribute.

        Allocates and copies the whole array, so this is for deliberately
        duplicating vertex data — not for reading it. Use `attribute_view`
        to read. An interleaved attribute comes back with an array of its
        own, as three.js's `clone` gives it.

        Args:
            name: Which attribute to copy.

        Returns:
            A copy of it, owned by the caller.

        Raises:
            Error: If the geometry has no such attribute.
        """
        var slot = self._slot(name)
        if slot < 0:
            raise Error("This geometry has no attribute named " + name)
        return self.values[slot].clone()

    def vertex_count(self) raises -> Int:
        """Return how many vertices the position attribute holds.

        Reads the stored attribute through a view. This used to go through a
        copying accessor, which mattered more than it looks: `corner_index`
        calls it, the renderer calls `corner_index` three times per triangle,
        and so drawing a mesh copied its entire position array nine times per
        triangle.

        Returns:
            The vertex count.

        Raises:
            Error: If the geometry has no positions.
        """
        return self.attribute_view(POSITION).count()

    def set_index(mut self, var index: List[Int]) raises:
        """Set the triangle index buffer.

        Args:
            index: Vertex indices, three per triangle.

        Raises:
            Error: If the count is not a multiple of three, or any entry is
                negative. Entries are checked against the vertex count when
                read, since positions may be set after the index.
        """
        if len(index) % 3 != 0:
            raise Error("An index buffer must hold whole triangles")
        for position in range(len(index)):
            if index[position] < 0:
                raise Error("An index entry cannot be negative")
        self.index = index^

    def is_indexed(self) -> Bool:
        """Return True if triangles are looked up through an index buffer."""
        return len(self.index) > 0

    def triangle_count(self) raises -> Int:
        """Return how many triangles this geometry describes.

        Returns:
            The triangle count, from the index if there is one.

        Raises:
            Error: If the geometry has no positions.
        """
        if self.is_indexed():
            return len(self.index) // 3
        return self.vertex_count() // 3

    def corner_index(self, triangle: Int, corner: Int) raises -> Int:
        """Return which vertex a triangle corner refers to.

        For non-indexed geometry that is just the running position; with an
        index it is the entry stored there. Callers that want to transform
        each vertex once and reuse it need this rather than `corner`.

        Args:
            triangle: Which triangle, from zero.
            corner: Which of its three corners, from zero.

        Returns:
            The vertex index.

        Raises:
            Error: If either index is out of range, or an index entry points
                past the end of the position attribute.
        """
        if triangle < 0 or triangle >= self.triangle_count():
            raise Error("Triangle index out of range")
        if corner < 0 or corner > 2:
            raise Error("A triangle has three corners")

        var slot = triangle * 3 + corner
        if not self.is_indexed():
            return slot

        var vertex = self.index[slot]
        if vertex >= self.vertex_count():
            raise Error("An index entry points past the last vertex")
        return vertex

    def corner(self, triangle: Int, corner: Int) raises -> Vector3:
        """Return one corner of one triangle, in the geometry's own space.

        Args:
            triangle: Which triangle, from zero.
            corner: Which of its three corners, from zero.

        Returns:
            That corner's position.

        Raises:
            Error: If either index is out of range, or an index entry points
                past the end of the position attribute.
        """
        var vertex = self.corner_index(triangle, corner)
        return self.attribute_view(POSITION).vector3(vertex)

    def compute_vertex_normals(mut self) raises:
        """Set the `normal` attribute from the triangles, three.js's
        `computeVertexNormals`.

        Each triangle's normal -- the cross product of two of its edges,
        and so twice its area long -- is added to each of its three corners,
        and every corner's sum is made unit length at the end. A vertex
        shared by several triangles gets the average of their normals,
        weighted by their areas, which is what makes a sphere shade
        smoothly. A vertex used once, as every vertex of a box or a
        polyhedron is, gets its one face's normal and shades flat. A vertex
        no triangle uses keeps a zero normal, as in three.js.

        Faces are joined by index, not by position. The two vertices either
        side of a texture seam sit in the same place and keep separate
        sums, so recomputing a seamed sphere's normals shows the seam, as it
        does in three.js. A builder's own normals know better; replace them
        only on purpose.

        Raises:
            Error: If the geometry has no positions, or an index entry
                points past the last vertex.
        """
        var count = self.vertex_count()
        var sums = List[Float32](length=count * 3, fill=0.0)
        for triangle in range(self.triangle_count()):
            var a = self.corner_index(triangle, 0)
            var b = self.corner_index(triangle, 1)
            var c = self.corner_index(triangle, 2)
            var origin = self.corner(triangle, 0)
            var normal = self.corner(triangle, 1) - origin
            normal.cross(self.corner(triangle, 2) - origin)
            for vertex in [a, b, c]:  # pragma: no branch
                sums[vertex * 3] += normal.x
                sums[vertex * 3 + 1] += normal.y
                sums[vertex * 3 + 2] += normal.z
        for vertex in range(count):
            var unit = Vector3(
                sums[vertex * 3], sums[vertex * 3 + 1], sums[vertex * 3 + 2]
            )
            unit.normalize()
            sums[vertex * 3] = unit.x
            sums[vertex * 3 + 1] = unit.y
            sums[vertex * 3 + 2] = unit.z
        self.set_attribute(NORMAL, BufferAttribute(sums^, 3))

    def bounding_box(self) raises -> Box3:
        """Return the smallest box around every vertex, three.js's
        `computeBoundingBox`.

        Computed each time it is asked for rather than cached: a geometry's
        attributes are open, so a cached answer could not know when it had
        gone stale. Empty for a geometry with no vertices.

        Returns:
            The box.

        Raises:
            Error: If the geometry has no positions.
        """
        ref positions = self.attribute_view(POSITION)
        var box = Box3.empty()
        for vertex in range(positions.count()):
            box.expand_by_point(positions.vector3(vertex))
        return box

    def bounding_sphere(self) raises -> Sphere:
        """Return a sphere around every vertex, three.js's
        `computeBoundingSphere`: centered on the bounding box, reaching the
        farthest vertex.

        Not the smallest sphere possible, but a bound, as three.js's is; see
        `Sphere.from_points`. Computed each time, for the reason
        `bounding_box` is. Empty for a geometry with no vertices.

        Returns:
            The sphere.

        Raises:
            Error: If the geometry has no positions.
        """
        var box = self.bounding_box()
        if box.is_empty():
            return Sphere.empty()
        # Two passes over the borrowed positions rather than a copy of them:
        # the box's center, then the farthest vertex from it.
        ref positions = self.attribute_view(POSITION)
        var center = box.center()
        var farthest = Float32(0)
        for vertex in range(positions.count()):  # pragma: no branch
            var reach = (positions.vector3(vertex) - center).length()
            if reach > farthest:
                farthest = reach
        return Sphere(center, farthest)

    def to_non_indexed(self) raises -> BufferGeometry:
        """Return this geometry with every triangle owning its corners,
        three.js's `toNonIndexed`.

        Every attribute and every morph target is read through the index,
        so a vertex shared by four triangles becomes four vertices. The
        groups are kept as they are: an index entry and a vertex of the
        result are counted the same way.

        three.js warns and returns the geometry itself when it has no index.
        This returns a copy, because a geometry here is owned and not shared.

        An instanced geometry stays instanced, and its per-instance
        attributes are copied as they are: they are read per instance, not
        through the index. three.js reads them through the index too.

        Returns:
            A geometry without an index.

        Raises:
            Error: If an index entry points past the last item of an
                attribute or a morph target.
        """
        if not self.is_indexed():
            return self.clone()
        var result = BufferGeometry(instanced=self.instanced)
        result.instance_count = self.instance_count
        for slot in range(len(self.names)):
            if self.values[slot].is_instanced():
                result.set_attribute(
                    self.names[slot], self.values[slot].clone()
                )
            else:
                result.set_attribute(
                    self.names[slot], self.values[slot].gather(self.index)
                )
        for target in range(len(self.morph_positions)):
            result.morph_positions.append(
                self.morph_positions[target].gather(self.index)
            )
        for target in range(len(self.morph_normals)):
            result.morph_normals.append(
                self.morph_normals[target].gather(self.index)
            )
        result.morph_relative = self.morph_relative
        result.morph_names = self.morph_names.copy()
        result.groups = self.groups.copy()
        return result^

    def center(mut self) raises:
        """Move the vertices so that their bounding box is centered on the
        origin, three.js's `center`.

        Only positions move. A normal and a tangent are directions, and a
        translation does not turn them. A geometry with no vertices does not
        move.

        Morph targets that hold finished positions move with the base, so a
        worn target lands where it did relative to the shape. three.js moves
        the base alone and leaves them behind. Targets that hold offsets do
        not move: an offset is the same wherever the shape is.

        Raises:
            Error: If the geometry has no positions, or they hold fewer
                than three numbers a vertex.
        """
        var offset = -self.bounding_box().center()
        _shift(self.values[self._slot(String(POSITION))], offset)
        if not self.morph_relative:
            for target in range(len(self.morph_positions)):
                _shift(self.morph_positions[target], offset)

    def stream_length(self) raises -> Int:
        """Return how many slots the triangle stream holds: the index
        entries, or the vertices of a geometry without an index.

        Returns:
            The count a group's `start` and `count` are measured against.

        Raises:
            Error: If the geometry has no index and no positions.
        """
        if self.is_indexed():
            return len(self.index)
        return self.vertex_count()

    def group_part(self, group: GeometryGroup) raises -> BufferGeometry:
        """Return the slots of one group as a geometry of their own, with
        no index and no group.

        Every attribute and every morph target is read for the group's
        slots, as `to_non_indexed` reads them for all. What a loader uses
        to give each group of a skinned mesh, which wears one material,
        a mesh of its own. The group's `start` and `count` are read as
        they are, so a group must lie within the stream.

        Args:
            group: The group.

        Returns:
            The group's corners.

        Raises:
            Error: If the group reaches past the end of the stream, or an
                index entry points past the last vertex.
        """
        var slots = List[Int]()
        for slot in range(group.start, group.start + group.count):
            slots.append(self.vertex_at(slot))
        var part = BufferGeometry()
        for at in range(len(self.names)):
            part.set_attribute(self.names[at], self.values[at].gather(slots))
        for target in range(len(self.morph_positions)):
            part.morph_positions.append(
                self.morph_positions[target].gather(slots)
            )
        for target in range(len(self.morph_normals)):
            part.morph_normals.append(self.morph_normals[target].gather(slots))
        part.morph_relative = self.morph_relative
        part.morph_names = self.morph_names.copy()
        return part^

    def triangle_run(self, start: Int, count: Int) raises -> Tuple[Int, Int]:
        """Return where a run of the triangle stream begins and how many
        whole triangles it holds, clamped to the stream.

        three.js's `drawStart` and `drawEnd` in `renderBufferDirect`: a
        group that runs past the end of the stream stops at it, and slots
        left over after the last whole triangle are not drawn. The
        renderer, the raycaster and the wireframe all read a group this
        way, so they draw and pick the same triangles.

        Args:
            start: The first slot, a group's `start`.
            count: How many slots, a group's `count`, or minus one for
                every slot from `start` on.

        Returns:
            The first slot, and how many triangles follow it. Triangle
            `t` reads slots `start + 3t` to `start + 3t + 2`.

        Raises:
            Error: If `start` is negative, or the geometry has no index and
                no positions.
        """
        if start < 0:
            raise Error("A run cannot start before the stream")
        var total = self.stream_length()
        var first = min(start, total)
        var end = total
        if count >= 0:
            end = min(start + count, total)
        return (first, max(0, end - first) // 3)

    def vertex_at(self, slot: Int) raises -> Int:
        """Return the vertex one slot of the triangle stream reads.

        The stream is the index for an indexed geometry, and the vertices
        in order for one without. `corner_index` asks the same by triangle;
        this asks by slot, which is how a group counts.

        Args:
            slot: An index entry, or a vertex for a geometry without an
                index.

        Returns:
            The vertex.

        Raises:
            Error: If the slot is outside the stream, if the geometry has
                no positions, or if an index entry points past the last
                vertex.
        """
        if slot < 0 or slot >= self.stream_length():
            raise Error("The triangle stream has no slot of that number")
        if not self.is_indexed():
            return slot
        var vertex = self.index[slot]
        if vertex >= self.vertex_count():
            raise Error("An index entry points past the last vertex")
        return vertex

    def _runs(self) raises -> List[GeometryGroup]:
        """Return the groups, or one group over every triangle if there are
        none, as three.js's `computeTangents` does.

        Returns:
            The runs of the triangle stream to visit.

        Raises:
            Error: If the geometry has no positions.
        """
        if len(self.groups) > 0:
            return self.groups.copy()
        return [GeometryGroup(0, self.stream_length(), MaterialIndex(0))]

    def compute_tangents(mut self) raises:
        """Set the `tangent` attribute from positions, normals and texture
        coordinates, three.js's `computeTangents`.

        A tangent is the direction u grows in along the surface. Each
        triangle gives the directions u and v grow in across it, and they
        are summed at its three corners. At each vertex the u sum is made
        square to the normal and unit length. The fourth number is minus one
        where the v sum points against the normal crossed with the u sum,
        and one otherwise: the handedness a mirrored texture needs.

        A triangle whose texture coordinates have no area gives no
        direction, and is skipped. A vertex no triangle uses gets a tangent
        of four zeros. With groups, only the triangles in them are visited,
        as in three.js.

        three.js refuses a geometry without an index. This reads one
        without an index three corners at a time, as the renderer does.

        Raises:
            Error: If the geometry has no `position`, `normal` or `uv`, if
                those hold too few numbers a vertex, or if an index entry
                points past the last vertex.
        """
        var count = self.vertex_count()
        var runs = self._runs()
        var total = self.stream_length()
        var along_u = List[Vector3](length=count, fill=Vector3(0, 0, 0))
        var along_v = List[Vector3](length=count, fill=Vector3(0, 0, 0))
        ref positions = self.attribute_view(String(POSITION))
        ref normals = self.attribute_view(String(NORMAL))
        ref uvs = self.attribute_view(String(UV))
        # `_runs` gives one run at least, so neither loop over the runs can
        # run zero times.
        for run in runs:  # pragma: no branch
            var end = min(run.start + run.count, total)
            for slot in range(run.start, end - 2, 3):
                var a = self.vertex_at(slot)
                var b = self.vertex_at(slot + 1)
                var c = self.vertex_at(slot + 2)
                var origin = positions.vector3(a)
                var edge_b = positions.vector3(b) - origin
                var edge_c = positions.vector3(c) - origin
                var u_a = uvs.component(a, 0)
                var v_a = uvs.component(a, 1)
                var u_b = uvs.component(b, 0) - u_a
                var v_b = uvs.component(b, 1) - v_a
                var u_c = uvs.component(c, 0) - u_a
                var v_c = uvs.component(c, 1) - v_a
                var scale = 1 / (u_b * v_c - u_c * v_b)
                if not isfinite(scale):
                    continue
                var u_way = (edge_b * v_c - edge_c * v_b) * scale
                var v_way = (edge_c * u_b - edge_b * u_c) * scale
                for vertex in [a, b, c]:  # pragma: no branch
                    along_u[vertex].add(u_way)
                    along_v[vertex].add(v_way)
        var tangents = List[Float32](length=count * 4, fill=0.0)
        for run in runs:  # pragma: no branch
            var end = min(run.start + run.count, total)
            for slot in range(run.start, end):
                var vertex = self.vertex_at(slot)
                var normal = normals.vector3(vertex)
                var u_way = along_u[vertex]
                var tangent = u_way - normal * normal.dot(u_way)
                tangent.normalize()
                var turned = normal
                turned.cross(u_way)
                var handedness = Float32(1)
                if turned.dot(along_v[vertex]) < 0:
                    handedness = -1
                tangents[vertex * 4] = tangent.x
                tangents[vertex * 4 + 1] = tangent.y
                tangents[vertex * 4 + 2] = tangent.z
                tangents[vertex * 4 + 3] = handedness
        self.set_attribute(String(TANGENT), BufferAttribute(tangents^, 4))
