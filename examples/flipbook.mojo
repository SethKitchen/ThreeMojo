# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A morph target sphere pulses beside a gyroscope.

    mojo run -I . examples/flipbook.mojo [path.png]

The page is Animated objects. `MorphBlendMesh` plays three named targets
on the sphere, tall then wide then flat, as one flip-book. The bar turns.
The red box turns with it. The blue box rides a `Gyroscope`, so it follows
the bar and keeps its own turn.
"""

from animation.keyframe_track import MeshIndex
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import box, cube
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.gyroscope import gyroscope
from objects.mesh import Mesh
from objects.morph_blend_mesh import MorphBlendMesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import sqrt
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/animated.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _scaled(
    base: BufferAttribute, sx: Float32, sy: Float32, sz: Float32
) raises -> BufferAttribute:
    """Return every vertex moved by a scale on each axis.

    Args:
        base: The sphere's positions.
        sx: The scale on x.
        sy: The scale on y.
        sz: The scale on z.

    Returns:
        Positions at that scale.

    Raises:
        Error: If a vertex of `base` cannot be read.
    """
    var data = List[Float32]()
    for vertex in range(base.count()):
        data.append(base.component(vertex, 0) * sx)
        data.append(base.component(vertex, 1) * sy)
        data.append(base.component(vertex, 2) * sz)
    return BufferAttribute(data^, 3)


def _facing(
    base: BufferAttribute, sx: Float32, sy: Float32, sz: Float32
) raises -> BufferAttribute:
    """Return normals carried through the inverse of a scale.

    Args:
        base: The sphere's normals.
        sx: The scale on x. It must not be zero.
        sy: The scale on y. It must not be zero.
        sz: The scale on z. It must not be zero.

    Returns:
        Unit normals for the scaled shape.

    Raises:
        Error: If a vertex of `base` cannot be read.
    """
    var data = List[Float32]()
    for vertex in range(base.count()):
        var x = base.component(vertex, 0) / sx
        var y = base.component(vertex, 1) / sy
        var z = base.component(vertex, 2) / sz
        var length = sqrt(x * x + y * y + z * z)
        if length > 0:
            x /= length
            y /= length
            z /= length
        data.append(x)
        data.append(y)
        data.append(z)
    return BufferAttribute(data^, 3)


def _target(
    mut shape: BufferGeometry,
    positions: BufferAttribute,
    normals: BufferAttribute,
    sx: Float32,
    sy: Float32,
    sz: Float32,
    name: String,
) raises:
    """Add one absolute morph target of a scaled sphere.

    Args:
        shape: The sphere the target belongs to.
        positions: The sphere's positions.
        normals: The sphere's normals.
        sx: The scale on x.
        sy: The scale on y.
        sz: The scale on z.
        name: The target's name, a word and a number.

    Raises:
        Error: If the target does not fit the sphere.
    """
    shape.add_morph_target(
        _scaled(positions, sx, sy, sz),
        _facing(normals, sx, sy, sz),
        name=name,
    )


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    mut blend: MorphBlendMesh,
    arm: NodeId,
    ball: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Advance the flip-book, turn the bar, and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the pair.
        assets: The geometries and materials.
        scene: The persistent scene, edited in place.
        blend: The flip-book playing on the sphere.
        arm: The bar the two boxes ride.
        ball: The sphere's node.
        step: How much further the bar and the sphere turn.

    Returns:
        The rendered frame.

    Raises:
        Error: If the blend, the scene or the render is invalid.
    """
    # Two passes of the three-target clip across the whole animation.
    blend.update(scene, 0.5 / 18.0)
    scene.node(arm).rotate_y(step)
    scene.node(ball).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var shape = sphere(Length(0.62, METER), 16, 12)
    var positions = shape.clone_attribute(POSITION)
    var normals = shape.clone_attribute(NORMAL)
    _target(shape, positions, normals, 0.72, 1.55, 0.72, "pulse1")
    _target(shape, positions, normals, 1.35, 0.55, 1.35, "pulse2")
    _target(shape, positions, normals, 1.15, 0.9, 0.42, "pulse3")

    var assets = Assets()
    var ball_shape = assets.geometries.add(shape^)
    var block = assets.geometries.add(cube(Length(0.36, METER)))
    var bar_shape = assets.geometries.add(
        box(Length(1.55, METER), Length(0.08, METER), Length(0.08, METER))
    )
    var coral = assets.materials.add(Material(Color(232, 112, 64)))
    var red = assets.materials.add(Material(Color(196, 64, 58)))
    var blue = assets.materials.add(Material(Color(70, 130, 210)))
    var metal = assets.materials.add(Material(Color(150, 156, 168)))

    var scene = Scene()
    var ball = Object3D()
    ball.set_position(0.95, 0.05, 0)
    var ball_id = scene.add(ball^)
    scene.add_mesh(Mesh(ball_shape, coral, ball_id))
    var slot = len(scene.meshes) - 1
    scene.meshes[slot].update_morph_targets(
        assets.geometries.geometries[ball_shape.value]
    )
    var blend = MorphBlendMesh(MeshIndex(slot), scene)
    blend.auto_create_animations(scene, 4)
    if not blend.play_animation("pulse"):
        raise Error("The pulse animation was not created")

    var arm = Object3D()
    arm.set_position(-0.95, 0, 0)
    var arm_id = scene.add(arm^)
    scene.add_mesh(Mesh(bar_shape, metal, arm_id))
    var spin = Object3D()
    spin.set_position(0.72, 0, 0)
    scene.add_mesh(Mesh(block, red, scene.attach(spin^, arm_id)))
    var steady = gyroscope()
    steady.set_position(-0.72, 0, 0)
    scene.add_mesh(Mesh(block, blue, scene.attach(steady^, arm_id)))

    var lamp = Object3D()
    lamp.set_position(1.2, 1.8, 1.6)
    var lamp_id = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.45))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_id, 2.2))

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.05, 0.55, 3.35), Vector3(0, 0.05, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(
                renderer, camera, assets, scene, blend, arm_id, ball_id, step
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
