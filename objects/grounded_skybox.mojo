# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sky whose lower half is a floor, from three.js
`examples/jsm/objects/GroundedSkybox.js`.

A sphere seen from inside, with a panorama on it. The lower half of the
sphere is pressed flat, `height` below the center, so the floor of the
panorama lies on the ground of the scene: an object that stands on the
ground stands on the photographed floor too. Put the node at the height of
the camera that took the panorama, above the scene's ground.

three.js builds a `SphereGeometry`, mirrors it in z so its faces look
inward, and moves each vertex below the center. A vertex below one and a
half heights down lands on the floor plane; one above that is eased
between the floor and the sphere, so the join has no crease. The
arithmetic is three.js's, in doubles, on the sphere's float positions.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from core.object3d import NodeId
from geometries.sphere import sphere
from materials.material import BASIC, Material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.texture_store import TextureId
from std.math import isfinite
from units.si import Length, METER

# three.js's `resolution` default: the rings from pole to pole.
comptime DEFAULT_SKYBOX_RESOLUTION = 128


def grounded_skybox(
    height: Length,
    radius: Length,
    resolution: Int = DEFAULT_SKYBOX_RESOLUTION,
) raises -> BufferGeometry:
    """Return three.js's `GroundedSkybox` geometry.

    Args:
        height: How far above the floor the panorama was taken.
        radius: The sphere's radius. It must hold the scene.
        resolution: The rings from pole to pole, at least two. There are
            twice as many segments around. three.js takes one, which
            leaves a sphere with no area.

    Returns:
        The sphere, turned inside out and pressed flat below.

    Raises:
        Error: If a size is not positive or not finite, or the
            resolution is below two.
    """
    var h = Float64(height.to(METER))
    var r = radius.to(METER)
    if not _finite_sizes(h, r):
        raise Error("A grounded skybox's height and radius must be finite")
    if not _positive_sizes(h, r):
        raise Error("A grounded skybox's height and radius must be positive")
    if resolution < 2:
        raise Error("A grounded skybox needs at least two rings")
    var geometry = sphere(radius, 2 * resolution, resolution)
    var positions = geometry.clone_attribute(String(POSITION)).packed()
    var normals = geometry.clone_attribute(String(NORMAL)).packed()
    var floor = -h * 3 / 2
    for vertex in range(len(positions) // 3):  # pragma: no branch
        var at = vertex * 3
        # three.js's `geometry.scale(1, 1, -1)`: the faces look inward.
        positions[at + 2] = -positions[at + 2]
        normals[at + 2] = -normals[at + 2]
        var y = Float64(positions[at + 1])
        if y < 0:
            var factor = 1 - y * y / (3 * floor * floor)
            if y < floor:
                factor = -h / y
            positions[at] = Float32(Float64(positions[at]) * factor)
            positions[at + 1] = Float32(y * factor)
            positions[at + 2] = Float32(Float64(positions[at + 2]) * factor)
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    return geometry^


def _finite_sizes(height: Float64, radius: Float32) -> Bool:
    """Return True if both sizes are finite."""
    return isfinite(height) and isfinite(radius)


def _positive_sizes(height: Float64, radius: Float32) -> Bool:
    """Return True if both sizes are positive."""
    return height > 0 and radius > 0


struct GroundedSkybox(ImplicitlyCopyable):
    """A panorama with a floor, three.js's `GroundedSkybox`.

    Put `mesh` in the scene.
    """

    # The pressed sphere, the material and the node.
    var mesh: Mesh

    def __init__(
        out self,
        mut assets: Assets,
        map: TextureId,
        height: Length,
        radius: Length,
        node: NodeId,
        resolution: Int = DEFAULT_SKYBOX_RESOLUTION,
    ) raises:
        """Create a grounded skybox and add its geometry and material to the
        stores.

        The material is three.js's `MeshBasicMaterial` with the map and
        `depthWrite` off.

        Args:
            assets: The stores. The geometry and the material are added.
            map: The panorama, read with the sphere's coordinates.
            height: How far above the floor the panorama was taken.
            radius: The sphere's radius.
            node: The scene node the skybox is drawn at.
            resolution: The rings from pole to pole.

        Raises:
            Error: If `grounded_skybox` refuses the sizes, or the map is not
                in the stores.
        """
        _ = assets.textures.get(map)
        var geometry = grounded_skybox(height, radius, resolution)
        var material = Material(Color(255, 255, 255), map, kind=BASIC)
        material.depth_write = False
        self.mesh = Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(material),
            node,
        )
