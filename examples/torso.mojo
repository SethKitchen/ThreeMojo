# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A whole body, with skin and without it, in a lit studio.

    mojo run -I . examples/torso.mojo [path.png] [quality]

The page is Torso. A six-foot male stands twice on a floor. The left
copy shows the bones, the joint tissues and the muscles of the torso
and its shoulder girdle, the pelvis, both legs and feet, both arms and
hands, and the neck and the head. The right copy shows one skin from
the head down to the wrists, and each hand's own, with the eyes and
the hair. The program also prints the mass of several torso parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `high`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.quality import (
    anatomy_detail,
    hand_skin_detail,
    quality_named,
    skin_detail,
    triangle_budget,
)
from extensions.humanoid.skeleton.simplify import (
    fit_triangle_budget,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_physical
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.look import (
    add_complexion,
    cartilage_physical,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
    tendon_physical,
)
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.torso.body import add_body
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    L3,
    RIB_7,
    SCAPULA,
    STERNUM,
)
from extensions.humanoid.skeleton.torso.bones.mass import torso_bone_mass
from extensions.humanoid.skeleton.torso.contents import BOTH, SKIN
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    DIAPHRAGM,
    ERECTOR_SPINAE,
    PECTORALIS_MAJOR,
)
from extensions.humanoid.skeleton.torso.muscles.mass import torso_muscle_mass
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import add_groom
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
from std.math import cos, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/torso.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "high"
comptime SPACING = Float32(0.44)


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


def _turned(v: Vector3, angle: Float32) -> Vector3:
    """Return `v` turned by `angle` radians about the vertical.

    Args:
        v: The vector.
        angle: The turn, counterclockwise seen from above.

    Returns:
        The turned vector.
    """
    var c = cos(angle)
    var s = sin(angle)
    return Vector3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)


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
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))
    var budget = triangle_budget(level)
    var detail = anatomy_detail(level)
    var covering = skin_detail(level)
    var hand_covering = hand_skin_detail(level)

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var S = person.stature.value
    print("Torso tissue for a six-foot male:")
    print("  L3", torso_bone_mass(person, L3).mass.to(GRAM), "g")
    print("  seventh rib", torso_bone_mass(person, RIB_7).mass.to(GRAM), "g")
    print("  sternum", torso_bone_mass(person, STERNUM).mass.to(GRAM), "g")
    print("  scapula", torso_bone_mass(person, SCAPULA).mass.to(GRAM), "g")
    print(
        "  erector spinae",
        torso_muscle_mass(person, ERECTOR_SPINAE).mass.to(GRAM),
        "g",
    )
    print(
        "  pectoralis major",
        torso_muscle_mass(person, PECTORALIS_MAJOR).mass.to(GRAM),
        "g",
    )
    print(
        "  diaphragm", torso_muscle_mass(person, DIAPHRAGM).mass.to(GRAM), "g"
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
    var looks = add_complexion(assets, person.genome, whole_body=True)

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
    var first = len(scene.meshes)
    var anatomy = _stand(scene, pivot, -SPACING, ground)
    _ = add_body(
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
        detail,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    var covered = _stand(scene, pivot, SPACING, ground)
    _ = add_body(
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
        detail,
        covering,
        hand_covering,
        skin_paint=looks.skin,
        hair_paint=looks.hair,
        eye_paint=looks.eyes,
        workers=available_workers(),
    )
    # The scalp's hair as strands, over the mass of it in shade.
    var hair = add_groom(scene, assets, covered, person, 1200, 5)
    # The skin is meshed smooth and lean already, and carries the face's
    # colors, which decimation would drop: only the anatomy is fitted to
    # the budget.
    for index in range(len(scene.meshes)):
        scene.meshes[index].cast_shadow = True
        scene.meshes[index].receive_shadow = True

    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    var ground_shape = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER))
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
    sun.shadow.set_extent(Length(1.8, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 1.05, 5.3), Vector3(0.0, 0.88, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    # The lamp as the hair sees it, and the camera.
    var toward = Vector3(1.4, 2.6, 2.2)
    toward.normalize()
    var eye = Vector3(0.0, 1.05, 5.3)
    var turned = Float32(0)
    for _ in range(FRAMES):
        # The frame turns the bodies by `step`: carry the camera and the
        # lamp into the covered body's own frame, as it will stand.
        turned += step.value
        var lights = List[HairLight]()
        lights.append(
            HairLight(_turned(toward, -turned), Vector3(2.2, 1.97, 1.72))
        )
        var camera_at = _turned(eye, -turned) - Vector3(SPACING, ground, 0)
        hair.shade(assets, lights, camera_at, Vector3(0.11, 0.11, 0.12))
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
