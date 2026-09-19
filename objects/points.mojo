# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Vertices drawn as squares of pixels, from three.js `src/objects/Points.js`.

A `Points` names the same three ids a `Mesh` does -- a node, a geometry
and a material -- for the reasons `objects.mesh` gives, and nothing else.
Its geometry's `position` attribute is the list of points, and each one
is drawn as a square `point_size` pixels across, centered on where the
point projects. It is the third kind of primitive the renderer draws,
beside the triangle and the segment.

## What a point is made of

A point geometry carries its points in the `position` attribute and no
index buffer. An index buffer here is a triangle index -- `set_index`
demands whole triangles -- and drawing a point per index entry would draw
a shared vertex once per triangle it is in. `Renderer.prepare_points`
refuses an indexed geometry rather than reading a triangle list as if it
were a point list, as `prepare_lines` refuses one.

## What a point is drawn with

`PointsMaterial` in three.js, which `points_material` builds, and which is
a `BASIC` material here with a `point_size` and a `size_attenuation`. A
point has no surface, so it has no normal, and every lighting term needs
one; `prepare_points` refuses a lit kind, as it refuses one on a line.

A point does have a coordinate of its own, across its square: OpenGL's
`gl_PointCoord`, which three.js samples a `PointsMaterial` map with. So a
point can carry a map and an alpha map, where a line cannot. The map is
sampled at that coordinate as it is stored: a map whose own transform is
not the identity is refused, rather than sampled somewhere the author did
not say.

The material color, its opacity, its blending, its alpha test and the
geometry's vertex colors all work as they do on a mesh. So does the fog.

## What a point is not

It is a square and not a disc, and it is not anti-aliased: what
`gl_PointSize` draws. A round point is a square point with a round alpha
map. It is not morphed and not skinned, as a line is not.
"""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId


struct Points(ImplicitlyCopyable):
    """Vertices drawn as squares of pixels at a scene node."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    # Whether `Renderer.prepare_points` may leave these points out when
    # their bounding sphere, carried to world space, lies outside the
    # camera frustum. On by default, as the flag of a `Mesh` is and as the
    # three.js `frustumCulled` is. The sphere bounds the points' centers,
    # not their squares: a point just outside the view whose square
    # reaches into it is left out, as three.js leaves it out.
    var frustum_culled: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
    ) raises:
        """Bind a stored geometry and material to a scene node.

        Whether the ids exist is not checkable here, for the reason
        `objects.mesh.Mesh` gives: the points hold none of the stores. The
        renderer has them all and raises if any id is out of range.

        Args:
            geometry: Id of the geometry whose vertices to draw.
            material: Id of the material to draw them with. It must be
                `BASIC`, and `points_material` builds one. The renderer
                checks that, where it can see the store.
            node: Index of the scene node giving their world transform.
            frustum_culled: Whether the renderer can skip these points
                when their bounds are out of view.

        Raises:
            Error: If any id is negative.
        """
        if node.value < 0:
            raise Error("Points must name a scene node")
        if geometry.value < 0:
            raise Error("Points must name a geometry")
        if material.value < 0:
            raise Error("Points must name a material")
        self.geometry = geometry
        self.material = material
        self.node = node
        self.frustum_culled = frustum_culled
