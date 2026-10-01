# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One leg and its foot, with skin and without it, in a lit studio.

    mojo run -I . examples/limb.mojo [path.png]

The pages are Leg, Foot and Integument. A six-foot male right limb
stands twice on a floor. The left copy shows bones, knee tissues,
muscles and foot ligaments. The right copy shows one skin over the leg
and the foot. The surfaces are physically based, lit by a room
environment and a lamp that casts soft shadows, and tone mapped.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_physical
from extensions.humanoid.skeleton.foot.assembly import add_foot
from extensions.humanoid.skeleton.foot.contents import BOTH as FOOT_BOTH
from extensions.humanoid.skeleton.leg.assembly import add_leg, assemble_leg
from extensions.humanoid.skeleton.leg.contents import BOTH as LEG_BOTH
from extensions.humanoid.skeleton.limb.skin import add_limb_skin
from extensions.humanoid.skeleton.look import (
    cartilage_physical,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
    skin_albedo,
    skin_physical,
    tendon_physical,
)
from geometries.plane import plane
from lights.light import directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import MaterialId, standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/limb.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime ANATOMY_DETAIL = 24
comptime SKIN_DETAIL = 64
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


def _stand(
    mut scene: Scene, parent: NodeId, x: Float32, ground: Float32
) raises -> NodeId:
    """Return a node that stands a limb at `x` with its sole on the floor.

    Args:
        scene: The scene that receives the node.
        parent: Shared parent that turns both limbs.
        x: Position along the row, in meters.
        ground: Height of the sole below the leg frame's origin.

    Returns:
        The limb's node, turned to show the foot from the side.

    Raises:
        Error: If the scene refuses the node.
    """
    var holder = Object3D()
    holder.set_position(x, ground, 0)
    holder.rotate_y(Angle(90.0, DEGREE))
    return scene.attach(holder^, parent)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(20, 21, 24))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.1
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP

    var assets = Assets()
    var bone = assets.materials.add(
        bone_physical(assets.textures.add(bone_albedo(64)))
    )
    var cartilage = assets.materials.add(cartilage_physical())
    var ligament = assets.materials.add(ligament_physical())
    var muscle = assets.materials.add(
        muscle_physical(assets.textures.add(muscle_albedo(64)))
    )
    var tendon = assets.materials.add(tendon_physical())
    var skin = assets.materials.add(
        skin_physical(assets.textures.add(skin_albedo(64)))
    )

    # Image-based light: three.js's RoomEnvironment through a PMREM.
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)

    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.55

    var pose = assemble_leg(person, RIGHT)
    # The sole's height below the knee's joint line: the plafond, less
    # the foot's ankle height.
    var ground = -(
        pose.ankle_center().y - Float32(0.048) * person.stature.value
    )
    var pivot = scene.add(Object3D())
    var anatomy = _stand(scene, pivot, -SPACING, ground)
    _ = add_leg(
        scene,
        assets,
        anatomy,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        RIGHT,
        LEG_BOTH,
        ANATOMY_DETAIL,
    )
    _ = add_foot(
        scene,
        assets,
        anatomy,
        person,
        bone,
        ligament,
        muscle,
        tendon,
        RIGHT,
        FOOT_BOTH,
        ANATOMY_DETAIL,
        pose.ankle_center(),
    )
    var covered = _stand(scene, pivot, SPACING, ground)
    _ = add_limb_skin(scene, assets, covered, person, skin, RIGHT, SKIN_DETAIL)
    for index in range(len(scene.meshes)):
        scene.meshes[index].cast_shadow = True
        scene.meshes[index].receive_shadow = True

    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    var ground_shape = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    var ground_look = assets.materials.add(
        standard_material(Color(92, 90, 86), roughness=0.85)
    )
    scene.add_mesh(
        Mesh(ground_shape, ground_look, scene.add(floor^), receive_shadow=True)
    )

    var lamp = Object3D()
    lamp.set_position(1.4, 2.6, 2.2)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 244, 228), lamp_node, 2.2)
    sun.cast_shadow = True
    sun.shadow.map_size = 1024
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(Length(1.4, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 0.62, 3.3), Vector3(0.0, 0.50, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
