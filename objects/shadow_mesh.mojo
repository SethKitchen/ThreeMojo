# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flat shadow cast onto a plane, from three.js
`examples/jsm/objects/ShadowMesh.js`.

A shadow mesh draws another mesh's geometry flattened onto a plane, away
from a light, in a translucent black. The flattening is one matrix: the
planar projection from the light, after the mesh's own world matrix. The
matrix is projective, and the renderer's divide by w puts every vertex on
the plane. It is the old stencil-shadow trick: no shadow map, and a
shadow that falls only on the one plane.

The material draws each pixel once, as three.js's does: the stencil test
passes where the stencil is zero, and a pass increments it. So two
triangles that overlap in the shadow do not darken it twice.

**The shadow draws a copy of the caster's geometry, without its normals.**
three.js draws the caster's own geometry. The renderer here turns each
normal by the inverse of the world matrix, and a shadow matrix has no
inverse when the light is a direction or the plane holds the origin. The
basic material reads no normal, so the copy draws the same pixels. Build a
new shadow mesh when the caster's geometry changes.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import BASIC, Material
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector4 import Vector4
from objects.mesh import Mesh
from render.framebuffer import Color
from render.raster_state import EQUAL_STENCIL_FUNC, INCREMENT_STENCIL_OP

# three.js's shadow opacity.
comptime SHADOW_OPACITY = Float32(0.6)


def shadow_matrix(plane: Plane, light: Vector4) -> Matrix4:
    """Return the matrix that flattens a point onto a plane, away from a
    light, three.js's `_shadowMatrix`.

    The shadow lands where the normal times the point equals the plane's
    constant. three.js's arithmetic negates the constant, so the shadow of
    `Plane((0, 1, 0), 0.01)` lies at y = 0.01, a little above a ground at
    y = 0, as three.js's example places it.

    Args:
        plane: The plane the shadow falls on, with its constant negated.
        light: Where the light is, with a `w` of one for a point, or which
            way it shines from, with a `w` of zero for a direction.

    Returns:
        The projective matrix.
    """
    # In doubles, as three.js computes it, rounded once into the matrix.
    var nx = Float64(plane.normal.x)
    var ny = Float64(plane.normal.y)
    var nz = Float64(plane.normal.z)
    var c = Float64(plane.constant)
    var lx = Float64(light.x)
    var ly = Float64(light.y)
    var lz = Float64(light.z)
    var lw = Float64(light.w)
    var dot = nx * lx + ny * ly + nz * lz + -c * lw
    var matrix = Matrix4()
    matrix.set(
        Float32(dot - lx * nx),
        Float32(-lx * ny),
        Float32(-lx * nz),
        Float32(-lx * -c),
        Float32(-ly * nx),
        Float32(dot - ly * ny),
        Float32(-ly * nz),
        Float32(-ly * -c),
        Float32(-lz * nx),
        Float32(-lz * ny),
        Float32(dot - lz * nz),
        Float32(-lz * -c),
        Float32(-lw * nx),
        Float32(-lw * ny),
        Float32(-lw * nz),
        Float32(dot - lw * -c),
    )
    return matrix^


def shadow_material() raises -> Material:
    """Return three.js's shadow material: black, translucent, drawn once a
    pixel by the stencil, and writing no depth.

    Returns:
        The material.

    Raises:
        Error: Never in practice: the settings are fixed.
    """
    var material = Material(
        Color(0, 0, 0),
        kind=BASIC,
        opacity=SHADOW_OPACITY,
        transparent=True,
    )
    material.depth_write = False
    material.stencil_write = True
    material.stencil_func = EQUAL_STENCIL_FUNC
    material.stencil_ref = 0
    material.stencil_z_pass = INCREMENT_STENCIL_OP
    return material^


def without_normals(geometry: BufferGeometry) -> BufferGeometry:
    """Return a copy of a geometry with no normals, and no morphed normals.

    Args:
        geometry: The geometry to copy.

    Returns:
        The copy.
    """
    var copy = geometry.clone()
    for index in range(len(copy.names)):
        if copy.names[index] == NORMAL:
            _ = copy.names.pop(index)
            _ = copy.values.pop(index)
            break
    copy.morph_normals = List[BufferAttribute]()
    return copy^


struct ShadowMesh(ImplicitlyCopyable):
    """Another mesh's shadow on a plane, three.js's `ShadowMesh`.

    Put `mesh` in the scene, and call `update` after the caster moves.
    """

    # A copy of the caster's geometry without its normals, the shadow
    # material, and a node of the shadow mesh's own at the root, whose
    # matrix `update` sets.
    var mesh: Mesh
    # The node of the mesh that casts, three.js's `meshMatrix`.
    var caster: NodeId

    def __init__(
        out self, mut assets: Assets, mut scene: Scene, caster: Mesh
    ) raises:
        """Create a shadow mesh for `caster` and add its geometry, its
        material and its node.

        The node sets its matrix by hand, three.js's `matrixAutoUpdate`
        off, and the mesh is never culled, three.js's `frustumCulled` off.

        Args:
            assets: The stores. The copy of the caster's geometry and the
                material are added.
            scene: The scene. A node at the root is added.
            caster: The mesh whose geometry the shadow draws.

        Raises:
            Error: If the caster's geometry is not in the stores, or the
                scene refuses the node.
        """
        var shape = without_normals(assets.geometries.get(caster.geometry))
        var held = Object3D()
        held.matrix_auto_update = False
        var node = scene.add(held^)
        self.mesh = Mesh(
            assets.geometries.add(shape^),
            assets.materials.add(shadow_material()),
            node,
            frustum_culled=False,
        )
        self.caster = caster.node

    def update(self, mut scene: Scene, plane: Plane, light: Vector4) raises:
        """Flatten the caster onto `plane` away from `light`, three.js's
        `update`.

        The shadow's node takes the shadow matrix times the caster's world
        matrix. Update the scene first, so the caster's world matrix is
        current, and again before the render.

        Args:
            scene: The scene, updated.
            plane: The plane the shadow falls on.
            light: The light's position with a `w` of one, or its direction
                with a `w` of zero.

        Raises:
            Error: If a node is not in the scene, or the scene is stale.
        """
        var matrix = shadow_matrix(plane, light)
        matrix.multiply(scene.world_matrix(self.caster))
        var held = scene.get(self.mesh.node)
        held.matrix = matrix
        scene.set(self.mesh.node, held^)
