# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pelvis on two legs, with skin and without it, in a lit studio.

    mojo run -I . examples/pelvis.mojo [path.png]

The page is Pelvis. A six-foot male lower body stands twice on a floor.
The left copy shows the pelvis's bones, ligaments and muscles, and the
same layers of both legs and feet. The right copy shows one skin over
all of it. The program also prints the mass of several pelvic parts.
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
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.look import (
    cartilage_physical,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
    skin_albedo,
    skin_physical,
    tendon_physical,
)
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    RIGHT_HIP_BONE,
    SACRUM,
)
from extensions.humanoid.skeleton.pelvis.bones.mass import pelvis_bone_mass
from extensions.humanoid.skeleton.pelvis.contents import BOTH, SKIN
from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    SACROTUBEROUS,
)
from extensions.humanoid.skeleton.pelvis.ligaments.mass import (
    pelvis_ligament_mass,
)
from extensions.humanoid.skeleton.pelvis.lower_body import add_lower_body
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    ILIACUS,
    PIRIFORMIS,
    PSOAS_MAJOR,
)
from extensions.humanoid.skeleton.pelvis.muscles.mass import (
    pelvis_muscle_mass,
)
from geometries.plane import plane
from lights.light import directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/pelvis.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime ANATOMY_DETAIL = 16
comptime SKIN_DETAIL = 56
comptime SPACING = Float32(0.30)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn both bodies by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The parent of both bodies.
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
    """Return a node that stands a body at `x` with its soles on the floor.

    Args:
        scene: The scene that receives the node.
        parent: Shared parent that turns both bodies.
        x: Position along the row, in meters.
        ground: Height of the hip joint centers above the soles.

    Returns:
        The body's node.

    Raises:
        Error: If the scene refuses the node.
    """
    var holder = Object3D()
    holder.set_position(x, ground, 0)
    return scene.attach(holder^, parent)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var S = person.stature.value
    print("Pelvic tissue for a six-foot male:")
    print(
        "  right hip bone",
        pelvis_bone_mass(person, RIGHT_HIP_BONE).mass.to(GRAM),
        "g",
    )
    print("  sacrum", pelvis_bone_mass(person, SACRUM).mass.to(GRAM), "g")
    print("  iliacus", pelvis_muscle_mass(person, ILIACUS).mass.to(GRAM), "g")
    print(
        "  psoas major",
        pelvis_muscle_mass(person, PSOAS_MAJOR).mass.to(GRAM),
        "g",
    )
    print(
        "  piriformis",
        pelvis_muscle_mass(person, PIRIFORMIS).mass.to(GRAM),
        "g",
    )
    print(
        "  sacrotuberous ligament",
        pelvis_ligament_mass(person, SACROTUBEROUS).mass.to(GRAM),
        "g",
    )

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

    # The soles' height below the hip joint centers: the leg's origin,
    # its plafond, and the foot's ankle height.
    var pose = assemble_pelvis(person)
    var leg = assemble_leg(person, RIGHT)
    var ground = -(
        pose.leg_origin(RIGHT).y + leg.ankle_center().y - Float32(0.048) * S
    )
    var pivot = scene.add(Object3D())
    var anatomy = _stand(scene, pivot, -SPACING, ground)
    _ = add_lower_body(
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
        BOTH,
        ANATOMY_DETAIL,
    )
    var covered = _stand(scene, pivot, SPACING, ground)
    _ = add_lower_body(
        scene,
        assets,
        covered,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        SKIN,
        ANATOMY_DETAIL,
        SKIN_DETAIL,
        skin_paint=skin,
    )
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
    camera.place(Vector3(0.0, 0.70, 3.2), Vector3(0.0, 0.58, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
