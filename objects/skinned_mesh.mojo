# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh carried by bones, from three.js `src/objects/SkinnedMesh.js`.

A skinned mesh is a mesh whose vertices are attached to a skeleton. Every
vertex names up to four bones and says how much of each one carries it, and
the vertex drawn is the weighted average of where those bones have taken
it. That is how an elbow bends without tearing: the vertices near the joint
are shared between the two bones and follow both.

The two attributes are three.js's, and glTF's, under the same names:

    skinIndex    four bone numbers per vertex
    skinWeight   four weights per vertex, summing to one

Four because that is what every skinning pipeline settled on, from glTF to
every game engine. It is enough for a joint, and a fifth bone on one vertex
is the sign of a rig that needs cleaning rather than a format that needs
widening.

## The two bind matrices

`bind_matrix` is where the mesh stood when it was attached, and
`bind_inverse` undoes it. They exist because a bone's matrix carries a
vertex in *world* space -- `Skeleton.pose` multiplies by the bone's world
matrix -- while a geometry's vertices are in the mesh's own space. three.js
has the same pair for the same reason, and the arithmetic here is its
`skinning_vertex` line for line:

    skinned = sum over the four bones of
              weight * bone_matrix * (bind_matrix * vertex)
    vertex  = bind_inverse * skinned

A mesh bound where it stands, with every bone posed where it was bound,
comes out exactly where it went in. That is the test worth writing first.

## Why it owns its skeleton

`InstancedMesh` owns its matrices and is added to a scene by being moved
in. This is the same: a skeleton is a list, a list makes the mesh
non-copyable, and `Scene.add_skinned_mesh` consumes it.

three.js lets several meshes share one skeleton, which matters for a
character wearing separate clothes. Here each mesh carries its own, and two
meshes on one rig carry two skeletons naming the same nodes. The nodes are
shared, so the pose is shared; only the small per-bone bind matrices are
duplicated.

## Morph targets as well

A skinned mesh wears morph targets the way a plain `Mesh` does, and for the
same reason three.js's `SkinnedMesh` extends `Mesh`: a face is morphed for
its expression and skinned for its jaw, and both at once is the ordinary
case rather than an exotic one.

The order is three.js's, and its vertex shader's: a vertex is moved by its
morph targets first, and the bones then carry wherever it has got to. Doing
it the other way round would carry the base shape and add the expression in
world space, which is a different and wrong picture.

## What is refused

A skeleton with no bones, or a bind matrix that cannot be inverted. The
skin attributes are checked where they are read, by the renderer, because
that is where the geometry is known: a mesh names a geometry by id and
cannot see it.
"""

from core.buffer_geometry import MAX_MORPH_TARGETS
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from math.matrix4 import Matrix4
from objects.skeleton import Skeleton
from std.math import isfinite

# Four numbers per vertex in each of the two skin attributes: three.js's
# and glTF's. See the module docstring.
comptime BONES_PER_VERTEX = 4

# The geometry attribute naming which bones carry each vertex, four per
# vertex, each a whole number identifying a bone of the skeleton.
comptime SKIN_INDEX = "skinIndex"
# The geometry attribute saying how much of each named bone carries the
# vertex, four per vertex.
comptime SKIN_WEIGHT = "skinWeight"


struct SkinnedMesh(Copyable, Movable):
    """A geometry carried by a skeleton, drawn with one material."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    var skeleton: Skeleton
    # Where the mesh stood when it was bound, and its inverse. See the
    # module docstring.
    var bind_matrix: Matrix4
    var bind_inverse: Matrix4
    # Whether the renderer may skip this mesh when its bounding sphere lies
    # outside the camera's frustum. Off by default, and that is not the
    # same default a `Mesh` has: a posed skeleton carries vertices wherever
    # the bones go, and the geometry's bound describes the rest pose only.
    var frustum_culled: Bool
    # How much of each of the geometry's morph targets this mesh wears,
    # exactly as a `Mesh` carries them. See `objects.mesh`.
    var morph_influences: SIMD[DType.float32, MAX_MORPH_TARGETS]

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        var skeleton: Skeleton,
        var bind_matrix: Matrix4 = Matrix4(),
        *,
        frustum_culled: Bool = False,
    ) raises:
        """Bind a stored geometry and material to a scene node and a
        skeleton.

        Args:
            geometry: Id of the geometry to draw. It must carry
                `skinIndex` and `skinWeight`, which the renderer checks.
            material: Id of the material to draw it with.
            node: Index of the scene node giving its world transform.
            skeleton: The bones that carry it, consumed.
            bind_matrix: Where the mesh stood when it was bound. The
                identity by default, which is right for a mesh modelled
                and bound at the origin.
            frustum_culled: Whether the renderer may skip this mesh when
                its bounds are out of view. Off by default, because a
                posed skeleton moves the vertices out of the bound the
                geometry describes.

        Raises:
            Error: If any id is negative, or the bind matrix is not a
                finite affine transform that can be inverted.
        """
        if node.value < 0:
            raise Error("A skinned mesh must name a scene node")
        if geometry.value < 0:
            raise Error("A skinned mesh must name a geometry")
        if material.value < 0:
            raise Error("A skinned mesh must name a material")
        if not bind_matrix.is_finite():
            raise Error("A bind matrix must be a real transform")
        if not bind_matrix.is_affine():
            raise Error("A bind matrix must be affine")
        if bind_matrix.determinant() == 0:
            raise Error("A bind matrix must be invertible")
        var undo = Matrix4(copy=bind_matrix)
        undo.invert()
        self.geometry = geometry
        self.material = material
        self.node = node
        self.skeleton = skeleton^
        self.bind_matrix = bind_matrix^
        self.bind_inverse = undo^
        self.frustum_culled = frustum_culled
        self.morph_influences = SIMD[DType.float32, MAX_MORPH_TARGETS](0)

    def bone_count(self) -> Int:
        """Return how many bones carry this mesh."""
        return self.skeleton.bone_count()

    def set_morph_influence(mut self, target: Int, weight: Float32) raises:
        """Set how much of one morph target this mesh wears.

        Args:
            target: Which of the geometry's targets, from zero.
            weight: How much of it; see `objects.mesh.Mesh`.

        Raises:
            Error: If there is no such target, or the weight is not a
                number.
        """
        if target < 0 or target >= MAX_MORPH_TARGETS:
            raise Error("A mesh has eight morph target influences")
        if not isfinite(weight):
            raise Error("A morph influence must be a number")
        self.morph_influences[target] = weight

    def morph_influence(self, target: Int) raises -> Float32:
        """Return how much of one morph target this mesh wears.

        Args:
            target: Which of the geometry's targets, from zero.

        Returns:
            Its weight.

        Raises:
            Error: If there is no such target.
        """
        if target < 0 or target >= MAX_MORPH_TARGETS:
            raise Error("A mesh has eight morph target influences")
        return self.morph_influences[target]
