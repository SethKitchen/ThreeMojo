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

Neither has per-instance colors yet. three.js's `instanceColor` is a
separate attribute, and a geometry's own vertex colors already reach every
instance; see `materials.material`.
"""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from math.matrix4 import Matrix4


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

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        count: Int,
        *,
        frustum_culled: Bool = True,
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

    def _check(self, index: Int) raises:
        """Refuse an instance index that names no instance."""
        if index < 0 or index >= len(self.matrices):
            raise Error("No instance has that index")


@fieldwise_init
struct BatchedInstance(ImplicitlyCopyable):
    """One member of a batch: which geometry it draws, and where."""

    var geometry: GeometryId
    var matrix: Matrix4


struct BatchedMesh(Copyable, Movable):
    """Many geometries drawn with one material at many transforms, each
    relative to one scene node: an instanced mesh whose instances each
    name their own geometry."""

    var material: MaterialId
    var node: NodeId
    # As on `InstancedMesh`: per instance.
    var frustum_culled: Bool
    # Each instance's geometry and transform, together.
    var instances: List[BatchedInstance]

    def __init__(
        out self,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
    ) raises:
        """Start an empty batch on a scene node.

        Args:
            material: Id of the material every instance is drawn with.
            node: Index of the scene node the instances are placed
                relative to.
            frustum_culled: Whether the renderer may skip an instance whose
                bounds are out of view.

        Raises:
            Error: If either id is negative.
        """
        if node.value < 0:
            raise Error("A batched mesh must name a scene node")
        if material.value < 0:
            raise Error("A batched mesh must name a material")
        self.material = material
        self.node = node
        self.frustum_culled = frustum_culled
        self.instances = List[BatchedInstance]()

    def count(self) -> Int:
        """Return how many instances there are."""
        return len(self.instances)

    def add_instance(
        mut self, geometry: GeometryId, matrix: Matrix4 = Matrix4()
    ) raises -> Int:
        """Add an instance, three.js's `addInstance`, and return its index.

        Args:
            geometry: Id of the geometry it draws. Whether the store has it
                is checked when the scene renders, as a mesh's is.
            matrix: Its transform relative to the node, affine and finite;
                the identity if not given.

        Returns:
            The new instance's index, for `set_matrix_at` and the rest.

        Raises:
            Error: If the geometry id is negative, or the matrix cannot
                place an instance; see `check_placing`.
        """
        if geometry.value < 0:
            raise Error("A batched instance must name a geometry")
        check_placing(matrix)
        self.instances.append(BatchedInstance(geometry, Matrix4(copy=matrix)))
        return len(self.instances) - 1

    def geometry_at(self, index: Int) raises -> GeometryId:
        """Return which geometry one instance draws.

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
        `setGeometryAt`.

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

    def _check(self, index: Int) raises:
        """Refuse an instance index that names no instance."""
        if index < 0 or index >= len(self.instances):
            raise Error("No instance has that index")
