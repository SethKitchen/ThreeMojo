# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two receding checkerboard floors, one mipmapped and one not.

The left half has no mip chain and the right half does, and they are the same
image on the same shape under the same camera. Near the bottom of the frame,
where a pixel covers about one texel, the two are indistinguishable. Towards
the horizon they are not: the left dissolves into a crawling moire, and the
right fades smoothly to the average of the pattern.

That is the whole argument for mipmaps. A pixel there covers dozens of texels,
and reading only one of them — whichever the coordinate happens to land on —
is a point sample of a signal far finer than the pixel grid can carry. Which
texel it lands on changes wildly for a coordinate that barely moved, so the
answer is noise, and the noise crawls as the camera slides forward. Averaging
all the texels under the pixel is the right answer, and the chain is those
averages taken in advance: each level is the one above it halved, so the level
whose texels are pixel-sized is a lookup rather than a sum.

Which level that is comes from the footprint: `render.rasterizer.mip_level`
measures how far the coordinates move over one pixel and takes the log. This
renderer evaluates the neighboring coordinates analytically rather than
differencing a 2x2 quad of fragments — the expression is known, so there is
nothing to approximate and nothing to borrow at a silhouette.

The camera slides forward rather than the floor turning, because the artifact
this is about is one of *motion*. A still frame shows a busy left half and a
smooth right half; the animation shows the left half boiling.

Each half is a `plane` laid flat and positioned, with its texture coordinates
rescaled so one copy of the image covers one meter of floor and the two halves
tile in step across the seam. three.js would express that as `texture.repeat`;
here it is a pass over the `uv` attribute, which `BufferGeometry` exists to
allow.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, UV
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import DOUBLE_SIDE, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.texture import BILINEAR, REPEAT, checkerboard
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/floor.png"
comptime WIDTH = 320
comptime HEIGHT = 200
comptime FRAMES = 30
comptime DELAY_MS = 70
# Where the floor starts and ends along z. It begins behind the camera, so the
# bottom of the frame is ground rather than sky, and runs far enough away that
# the far end is well past one texel per pixel -- which is where the two halves
# part company.
comptime NEAR_Z = Float32(10)
comptime FAR_Z = Float32(-70)
# How wide the floor is either side of the seam. Wide enough that its side
# edges are outside the frame all the way to the horizon, so what the top of
# the image shows is distance rather than the end of the quad.
comptime HALF_WIDTH = Float32(60)
# How many meters one copy of the image covers. Square tiles, which a
# checkerboard needs -- stretch them and the two directions are minified by
# different amounts and the picture stops being about the chain.
comptime TILE_METERS = Float32(1)


def half_floor(
    left_edge: Float32, right_edge: Float32
) raises -> BufferGeometry:
    """Return one half of the floor, tiled with texture coordinates.

    A `plane` the width of the half and the length of the floor, with its
    `uv` rewritten so `u` counts meters from the world's x = 0 -- not from
    the half's own left edge -- and `v` counts meters from the near end. Both
    halves therefore tile in step and the seam between them is invisible.

    Args:
        left_edge: The half's left edge, in world x.
        right_edge: Its right edge.

    Returns:
        The geometry, in the xy plane; the caller lays it flat.

    Raises:
        Error: If the attributes are malformed, which they are not.
    """
    var width = right_edge - left_edge
    var length = NEAR_Z - FAR_Z
    var sheet = plane(Length(width, METER), Length(length, METER))
    var tiled = List[Float32]()
    ref uvs = sheet.attribute_view(String(UV))
    for vertex in range(uvs.count()):
        var u = uvs.component(vertex, 0)
        var v = uvs.component(vertex, 1)
        tiled.append((left_edge + u * width) / TILE_METERS)
        tiled.append(v * length / TILE_METERS)
    sheet.set_attribute(String(UV), BufferAttribute(tiled^, 2))
    return sheet^


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    halves: List[NodeId],
    traveled: Float32,
) raises -> Framebuffer:
    """Render one frame with the floor slid `traveled` meters towards us.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        halves: The two floor nodes, which move together.
        traveled: How far the floor has moved along z.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var center_z = (NEAR_Z + FAR_Z) / 2 + traveled
    scene.node(halves[0]).set_position(-HALF_WIDTH / 2, 0, center_z)
    scene.node(halves[1]).set_position(HALF_WIDTH / 2, 0, center_z)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 20, 28))

    var assets = Assets()
    # Two halves of one floor, meeting at x = 0 so the seam runs up the middle
    # of the frame and the comparison is edge to edge.
    var near_side = assets.geometries.add(half_floor(-HALF_WIDTH, 0))
    var far_side = assets.geometries.add(half_floor(0, HALF_WIDTH))

    # The same checkerboard twice, differing only in whether the chain was
    # built. Bilinear on both: filtering *within* a level is not what is being
    # compared, and leaving it off would blame the chain for hard edges.
    var aliased = assets.textures.add(
        checkerboard(
            64, 8, Color(245, 245, 250), Color(35, 70, 150), REPEAT, BILINEAR
        )
    )
    var filtered = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(245, 245, 250),
            Color(35, 70, 150),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )

    # `DOUBLE_SIDE`: a floor is an open surface, and which way its one triangle
    # happens to wind should not decide whether it exists.
    var plain = assets.materials.add(
        Material(Color(255, 255, 255), aliased, DOUBLE_SIDE)
    )
    var chained = assets.materials.add(
        Material(Color(255, 255, 255), filtered, DOUBLE_SIDE)
    )

    # Each half is laid flat with a quarter turn about x, so the plane's +z
    # becomes +y and its top edge, where v is one, becomes the far end.
    var scene = Scene()
    var halves = List[NodeId]()
    for _ in range(2):
        var half = Object3D()
        half.set_euler(
            Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
        )
        halves.append(scene.add(half^))
    scene.add_mesh(Mesh(near_side, plain, halves[0]))
    scene.add_mesh(Mesh(far_side, chained, halves[1]))

    # The lamp is a node like any other, so it could be parented to something
    # that moves.
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(200.0, METER),
    )
    # Low and looking slightly down: the horizon sits inside the frame, and
    # everything approaching it is minified without limit.
    camera.place(Vector3(0, 1.4, 6.0), Vector3(0, 0.9, -6.0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        # Exactly one tile of travel over the loop, so the animation repeats
        # seamlessly and the moire is the only thing that appears to move.
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                halves,
                TILE_METERS * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
