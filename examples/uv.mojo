# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What perspective-correct interpolation is actually for.

Two frames of the same floor plane, drawn as two large triangles seen at a
grazing angle, with its texture coordinates written straight out as red and
green. The first frame interpolates them correctly; the second interpolates
them across the screen as though there were no perspective at all. Flipping
between the two shows the diagonal seam of the quad swing back and forth —
the artifact anyone who played a PlayStation 1 game has seen, where textures
slide and warp as the camera moves.

The two frames come from *one* call to `Renderer.prepare`. That is the point
of it being a public seam rather than a private step: the affine frame is the
same prepared triangles with every `inv_w` set to one, which is precisely what
"ignore perspective when interpolating" means. Nothing else about the scene,
the clipping or the coverage differs, so the difference in the image is the
correction and nothing else.

A floor plane is the worst case on purpose. The error grows with how much
perspective a single triangle spans, so it is invisible on a finely subdivided
sphere and unmissable on two triangles stretching to the horizon.
"""

from core.object3d import NodeId
from cameras.perspective_camera import PerspectiveCamera
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, UV
from core.assets import Assets
from materials.material import Material
from core.object3d import Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.target import RenderTarget
from render.rasterizer import SHADE_UV, RasterVertex, rasterize_shaded
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_OUTPUT = "out/uv.png"
comptime WIDTH = 320
comptime HEIGHT = 200
# Slow enough to read which frame is which.
comptime DELAY_MS = 900
comptime EXTENT = Float32(6.0)


def floor_plane() raises -> BufferGeometry:
    """Return a flat square in the xz plane, two triangles, fully mapped.

    Wound counter-clockwise seen from above, so it survives backface culling
    when the camera is above it.

    Returns:
        The geometry.

    Raises:
        Error: If the attributes are malformed, which they are not.
    """
    var half = EXTENT / 2
    var positions = List[Float32]()
    var uvs = List[Float32]()

    # Corners: far-left, far-right, near-right, near-left.
    var xs = [-half, half, half, -half]
    var zs = [-half, -half, half, half]
    var us = [Float32(0), Float32(1), Float32(1), Float32(0)]
    var vs = [Float32(1), Float32(1), Float32(0), Float32(0)]
    for corner in range(4):
        positions.append(xs[corner])
        positions.append(0)
        positions.append(zs[corner])
        uvs.append(us[corner])
        uvs.append(vs[corner])

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    var index = List[Int]()
    for entry in [0, 2, 1, 0, 3, 2]:
        index.append(entry)
    geometry.set_index(index^)
    return geometry^


def fill(corners: List[RasterVertex], background: Color) raises -> Framebuffer:
    """Rasterize prepared triangles in UV mode.

    Args:
        corners: Raster vertices, three per triangle.
        background: The colour to clear to.

    Returns:
        The finished frame.

    Raises:
        Error: If the framebuffer cannot be made.
    """
    var target = RenderTarget(WIDTH, HEIGHT, background)
    for triangle in range(len(corners) // 3):
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_UV,
        )
    return target.resolve()


def flattened(corners: List[RasterVertex]) -> List[RasterVertex]:
    """Return the same corners with every `inv_w` set to one.

    Which is exactly "pretend there is no perspective": the correction weights
    by `inv_w` and divides by the interpolated `inv_w`, so making them all
    equal cancels it completely and leaves plain screen-space interpolation.
    """
    var affine = List[RasterVertex]()
    for index in range(len(corners)):
        var corner = corners[index]
        affine.append(
            RasterVertex(
                corner.x,
                corner.y,
                corner.z,
                1.0,
                corner.color,
                corner.u,
                corner.v,
                corner.texture,
                corner.blend,
            )
        )
    return affine^


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var background = Color(12, 12, 16)
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(background)

    var assets = Assets()
    var plane = assets.geometries.add(floor_plane())

    var scene = Scene()
    _ = scene.add(Object3D())
    # The lamp is a node like any other, so it could be parented to something
    # that moves. Added last, leaving the node ids the meshes name untouched.
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))

    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            plane,
            assets.materials.add(Material(Color(255, 255, 255))),
            NodeId(0),
        )
    )

    # Low and close, so the far edge of the plane runs away to a vanishing
    # point and one triangle spans a great deal of perspective.
    var camera = PerspectiveCamera(
        Angle(55.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0.8, 3.4), Vector3(0, 0, -1.5))

    var corners = renderer.prepare(scene, assets, meshes, camera)

    var frames = List[Framebuffer]()
    frames.append(fill(corners, background))
    frames.append(fill(flattened(corners), background))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "- frame 1 perspective correct, frame 2 affine")
