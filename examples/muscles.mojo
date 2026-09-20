# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Leg layers and athleticism, turning under a lamp.

    mojo run -I . examples/muscles.mojo [path.png]

The page is Muscles. A six-foot male right leg is drawn three times:
bones only, untoned muscles, and toned muscles.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import (
    BONES,
    MUSCLES,
    LegContents,
)
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    tendon_phong,
)
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from materials.material import MaterialId
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/muscles.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 10
comptime SPACING = Float32(0.32)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the row by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The parent of every leg.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def _add(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    person: HumanoidSpec,
    x: Float32,
    contents: LegContents,
    bone_paint: MaterialId,
    cartilage_paint: MaterialId,
    meniscus_paint: MaterialId,
    ligament_paint: MaterialId,
    muscle_paint: MaterialId,
    tendon_paint: MaterialId,
) raises:
    """Place one layered leg on the gallery row.

    Args:
        scene: The scene that receives the node and the meshes.
        assets: Geometry store for the new meshes.
        parent: Shared parent that turns every leg together.
        person: Stature, sex and athleticism.
        x: Position along the row, in meters.
        contents: Bones, muscles or both.
        bone_paint: Cortical look.
        cartilage_paint: Cartilage look.
        meniscus_paint: Meniscus look.
        ligament_paint: Ligament look.
        muscle_paint: Muscle look.
        tendon_paint: Tendon look.

    Raises:
        Error: If the spec, the mesh or the scene is invalid.
    """
    var holder = Object3D()
    holder.set_position(x, 0, 0)
    var nid = scene.attach(holder^, parent)
    _ = add_leg(
        scene,
        assets,
        nid,
        person,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        RIGHT,
        contents,
        DETAIL,
    )


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var bones = HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED)
    var untoned = HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED)
    var toned = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var bone_paint = assets.materials.add(bone_phong(map))
    var cartilage_paint = assets.materials.add(cartilage_phong())
    var meniscus_paint = assets.materials.add(meniscus_phong())
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong())
    var tendon_paint = assets.materials.add(tendon_phong())

    var scene = Scene()
    var pivot = scene.add(Object3D())
    _add(
        scene,
        assets,
        pivot,
        bones,
        -SPACING,
        BONES,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
    )
    _add(
        scene,
        assets,
        pivot,
        untoned,
        Float32(0),
        MUSCLES,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
    )
    _add(
        scene,
        assets,
        pivot,
        toned,
        SPACING,
        MUSCLES,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
    )

    var lamp = Object3D()
    lamp.set_position(0.55, 0.65, 1.1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 248, 235), 0.52))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.55))

    var camera = PerspectiveCamera(
        Angle(28.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.28, 0.10, 2.05), Vector3(0.0, 0.04, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
