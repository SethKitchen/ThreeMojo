# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A turning box rendered every frame, then shown on two screens.

    mojo run -I . examples/television.mojo [path.png]

The page is Textures. Each frame the box scene is drawn into a small
target of its own. The target's color becomes a texture on the left
screen and its depth a texture on the right one, and a second render
shows both screens on a stand. The ramp the box is shaded through is a
data texture: three numbers, never an image file.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import BASIC, Material, toon_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.target import RenderTarget
from render.texture import IGNORED, data_texture

from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/television.png"
comptime WIDTH = 240
comptime HEIGHT = 180
# The size of the picture the screens show.
comptime SCREEN_WIDTH = 96
comptime SCREEN_HEIGHT = 72
comptime FRAMES = 36
comptime DELAY_MS = 55


def a_camera(
    width: Int, height: Int, back: Float32, near: Length, far: Length
) raises -> PerspectiveCamera:
    """Return a camera `back` meters from the origin, looking at it.

    Args:
        width: The image's width, for the aspect.
        height: Its height.
        back: How far along +z the camera stands.
        near: Its near plane.
        far: Its far plane. The studio camera's two planes hug the box,
            because a perspective depth spends most of its range near the
            near plane: with the usual tenth of a meter to a hundred the
            depth screen would show the box as near white.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(width) / Float32(height),
        near,
        far,
    )
    camera.place(Vector3(0, 0.6, back), Vector3(0, 0, 0))
    return camera^


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    # The box scene: a toon box under a lamp, shaded through a ramp built
    # from three numbers.
    var studio = Renderer(
        SCREEN_WIDTH, SCREEN_HEIGHT, workers=available_workers()
    )
    studio.set_background(Color(30, 60, 90))
    var props = Assets()
    var box = props.geometries.add(cube(Length(1.2, METER)))
    var ramp = props.textures.add(
        data_texture(3, 1, [0.35, 0.7, 1.0], channels=1, alpha=IGNORED)
    )
    var cel = props.materials.add(
        toon_material(Color(255, 170, 60), gradient_map=ramp)
    )
    var stage = Scene()
    var turning = stage.add(Object3D())
    stage.add_mesh(Mesh(box, cel, turning))
    var lamp = Object3D()
    lamp.set_position(1.0, 1.2, 0.8)
    var lamp_node = stage.add(lamp^)
    stage.add_light(ambient_light(Color(255, 255, 255), 0.4))
    stage.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.5))
    var studio_camera = a_camera(
        SCREEN_WIDTH, SCREEN_HEIGHT, 3.2, Length(2.0, METER), Length(4.5, METER)
    )

    # The room: two screens on a stand, each showing one texture of the
    # box scene. The textures are replaced every frame.
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var room = Assets()
    var screen = room.geometries.add(
        plane(Length(1.6, METER), Length(1.2, METER))
    )
    var shelf = room.geometries.add(cube(Length(0.5, METER)))
    var wood = room.materials.add(Material(Color(120, 80, 50)))
    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.95, 0.3, 0)
    left.rotate_y(Angle(20.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.95, 0.3, 0)
    right.rotate_y(Angle(-20.0, DEGREE))
    var right_node = scene.add(right^)
    var stand = Object3D()
    stand.set_position(0, -0.55, 0)
    stand.set_scale(4.0, 0.3, 1.0)
    var stand_node = scene.add(stand^)
    scene.add_mesh(Mesh(shelf, wood, stand_node))
    var room_lamp = Object3D()
    room_lamp.set_position(0.5, 1.5, 1.0)
    var room_lamp_node = scene.add(room_lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.6))
    scene.add_light(
        directional_light(Color(255, 255, 255), room_lamp_node, 2.0)
    )
    scene.update()
    var camera = a_camera(
        WIDTH, HEIGHT, 3.6, Length(0.1, METER), Length(100.0, METER)
    )

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        stage.node(turning).rotate_y(step)
        stage.update()
        # Draw the box into its own target, then read the target back as
        # two textures: its picture and its depth.
        var target = RenderTarget(
            SCREEN_WIDTH, SCREEN_HEIGHT, studio.background
        )
        studio.render_into(target, stage, props, studio_camera)
        var picture = room.textures.add(
            target.texture(workers=renderer.workers)
        )
        var depth = room.textures.add(target.depth_texture())
        var color_screen = room.materials.add(
            Material(Color(255, 255, 255), picture, kind=BASIC)
        )
        var depth_screen = room.materials.add(
            Material(Color(255, 255, 255), depth, kind=BASIC)
        )
        scene.meshes = List[Mesh]()
        scene.add_mesh(Mesh(shelf, wood, stand_node))
        scene.add_mesh(Mesh(screen, color_screen, left_node))
        scene.add_mesh(Mesh(screen, depth_screen, right_node))
        frames.append(renderer.render(scene, room, camera))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
