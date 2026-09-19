# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three colored lamps on one white sphere, and a fourth carried by it.

Everything the lighting rewrite made possible, in one picture. Until lights
became scene objects, a scene had exactly one of them and it had no color: the
renderer held a direction and an ambient fraction, so this image could not be
made at all.

**Three lights, and they add in linear light.** Red from the left, green from
above and blue from the right. Where two of them reach the same part of the
surface their light *sums* — red and green overlap into yellow, all three into
white — which is true of light and is not true of the encoded bytes a display
shows. Summing those instead would make every overlap too dark, in the same
specific way `render.srgb` exists to prevent.

**A lamp parented to a turning node, and it is a point light.** The fourth
is warm and hangs from the same turntable the sphere is on, so it travels
with the surface instead of sweeping across it: the pool of light it leaves
stays put while the other three slide past. A light on the renderer could not
do that, because it had no transform to inherit. It is a bulb rather than a
sun -- its light spreads out from where it is and falls off with the square
of the distance -- so it lights the part of the sphere nearest it and little
else, which is what makes it read as a small warm lamp rather than a fourth
color wash.

**Shading per fragment.** The sphere is deliberately coarse — twelve segments
around, eight from pole to pole — so its triangles are large enough to see.
Lighting is evaluated at every pixel from a normal interpolated across the
face and made unit length again there, so the terminator between lit and unlit
curves smoothly across each triangle. Shading only at the corners and
interpolating the color, which is what this renderer used to do, puts a
visible crease along every edge instead.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light, point_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/lamps.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 60
# Coarse on purpose: large triangles are what make per-fragment shading
# visible rather than merely correct.
comptime AROUND = 12
comptime POLE_TO_POLE = 8


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    table: NodeId,
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the turntable at `turn` degrees.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        table: The turntable node the sphere and the fourth lamp ride on.
        turn: How far the turntable has turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(table).set_euler(
        Angle(0.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE)
    )
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(10, 11, 16))

    var assets = Assets()
    var ball = assets.geometries.add(
        sphere(Length(1.0, METER), AROUND, POLE_TO_POLE)
    )
    # White, so what you see is the light and nothing else.
    var white = assets.materials.add(Material(Color(255, 255, 255)))

    # The turntable, and the sphere riding on it.
    var scene = Scene()
    var table = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, white, table))

    # Three fixed lamps, each its own node so each has a direction.
    var places = [
        Vector3(-1.0, 0.15, 0.5),
        Vector3(0.0, 1.0, 0.35),
        Vector3(1.0, 0.15, 0.5),
    ]
    var tints = [
        Color(255, 40, 40),
        Color(40, 255, 80),
        Color(60, 110, 255),
    ]
    for lamp in range(3):
        var node = Object3D()
        node.set_position(places[lamp].x, places[lamp].y, places[lamp].z)
        var id = scene.add(node^)
        scene.add_light(directional_light(tints[lamp], id, 2.83))

    # The fourth hangs from the turntable, so it turns with the sphere and its
    # pool of light stays in the same place on the surface. A bulb, held just
    # off the surface: close enough that the inverse-square falloff makes it
    # a spot rather than a wash.
    var carried = Object3D()
    carried.set_position(0, -0.6, 1.6)
    var carried_id = scene.attach(carried^, table)
    scene.add_light(point_light(Color(255, 200, 120), carried_id, 1.57))

    # Just enough fill that the unlit side is a shape rather than a hole.
    scene.add_light(ambient_light(Color(30, 34, 48), 3.14))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.35, 3.4), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                table,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
