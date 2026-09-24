# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One leg and its foot, with skin and without it.

    mojo run -I . examples/limb.mojo [path.png]

The pages are Leg and Foot. A six-foot male right limb stands twice.
The left copy shows bones, knee tissues, muscles and foot ligaments.
The right copy shows the skin envelope. The foot meets the leg at the
tibial plafond.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.foot.assembly import add_foot
from extensions.humanoid.skeleton.foot.contents import BOTH as FOOT_BOTH
from extensions.humanoid.skeleton.foot.contents import SKIN as FOOT_SKIN
from extensions.humanoid.skeleton.foot.contents import FootContents
from extensions.humanoid.skeleton.leg.assembly import add_leg, assemble_leg
from extensions.humanoid.skeleton.leg.contents import BOTH as LEG_BOTH
from extensions.humanoid.skeleton.leg.contents import SKIN as LEG_SKIN
from extensions.humanoid.skeleton.leg.contents import LegContents
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_albedo,
    muscle_phong,
    skin_albedo,
    skin_phong,
    tendon_phong,
)
from lights.light import ambient_light, directional_light
from materials.material import MaterialId
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/limb.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime LEG_DETAIL = 12
comptime FOOT_DETAIL = 8
comptime SPACING = Float32(0.42)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn both limbs by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The parent of both limbs.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def _add_limb(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    person: HumanoidSpec,
    x: Float32,
    leg_layers: LegContents,
    foot_layers: FootContents,
    bone_paint: MaterialId,
    cartilage_paint: MaterialId,
    meniscus_paint: MaterialId,
    ligament_paint: MaterialId,
    muscle_paint: MaterialId,
    tendon_paint: MaterialId,
    skin_paint: MaterialId,
) raises:
    """Place one leg and the foot that meets it.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Shared parent that turns both limbs.
        person: Stature, sex and athleticism.
        x: Position along the row, in meters.
        leg_layers: Layers for the leg.
        foot_layers: Layers for the foot.
        bone_paint: Cortical look.
        cartilage_paint: Cartilage look.
        meniscus_paint: Meniscus look.
        ligament_paint: Ligament look.
        muscle_paint: Muscle look.
        tendon_paint: Tendon look.
        skin_paint: Skin look.

    Raises:
        Error: If the spec, a mesh or the scene is invalid.
    """
    var pose = assemble_leg(person, RIGHT)
    var holder = Object3D()
    holder.set_position(x, 0, 0)
    # Side view, so the heel, arch and toes read as a foot.
    holder.rotate_y(Angle(90.0, DEGREE))
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
        leg_layers,
        LEG_DETAIL,
        skin_paint=skin_paint,
    )
    _ = add_foot(
        scene,
        assets,
        nid,
        person,
        bone_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        RIGHT,
        foot_layers,
        FOOT_DETAIL,
        pose.ankle_center(),
        skin_paint=skin_paint,
    )


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var muscle_map = assets.textures.add(muscle_albedo(64))
    var skin_map = assets.textures.add(skin_albedo(64))
    var bone_paint = assets.materials.add(bone_phong(map))
    var cartilage_paint = assets.materials.add(cartilage_phong())
    var meniscus_paint = assets.materials.add(meniscus_phong())
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong(muscle_map))
    var tendon_paint = assets.materials.add(tendon_phong())
    var skin_paint = assets.materials.add(skin_phong(skin_map))

    var scene = Scene()
    var pivot = scene.add(Object3D())
    _add_limb(
        scene,
        assets,
        pivot,
        person,
        -SPACING,
        LEG_BOTH,
        FOOT_BOTH,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        skin_paint,
    )
    _add_limb(
        scene,
        assets,
        pivot,
        person,
        SPACING,
        LEG_SKIN,
        FOOT_SKIN,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        skin_paint,
    )

    var lamp = Object3D()
    lamp.set_position(0.7, 0.85, 1.6)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 248, 235), 0.52))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.55))

    var camera = PerspectiveCamera(
        Angle(26.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.06, 0.20, 3.40), Vector3(0.0, -0.02, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
