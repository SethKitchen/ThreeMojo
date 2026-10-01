# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm and its hand, with skin and without it, in a lit studio.

    mojo run -I . examples/arm.mojo [path.png] [quality]

The page is Arm. A six-foot male right arm and hand hang twice, each
turning about its own length. The left copy shows the bones, the joint
tissues and the muscles, and the clavicle and the scapula the arm hangs
from. The right copy shows the skin and the hair. The program also
prints the mass of several arm parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `xhigh`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.athleticism import TONED
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
from extensions.humanoid.skeleton.arm.assembly import place_mesh
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    HUMERUS,
    RADIUS,
    ULNA,
)
from extensions.humanoid.skeleton.arm.bones.mass import arm_bone_mass
from extensions.humanoid.skeleton.arm.contents import BOTH, HAIR, SKIN
from extensions.humanoid.skeleton.arm.frame import arm_dimensions
from extensions.humanoid.skeleton.arm.limb import add_upper_limb
from extensions.humanoid.skeleton.arm.muscles.dimensions import (
    BICEPS_BRACHII,
    DELTOID,
    TRICEPS_BRACHII,
)
from extensions.humanoid.skeleton.arm.muscles.mass import arm_muscle_mass
from extensions.humanoid.skeleton.bone import bone_albedo, bone_physical
from extensions.humanoid.skeleton.look import (
    cartilage_physical,
    hair_phong,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
    skin_albedo,
    skin_physical,
    tendon_physical,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    CLAVICLE,
    SCAPULA,
    torso_dimensions,
)
from extensions.humanoid.skeleton.torso.bones.geometry import (
    torso_bone_from_dimensions,
)
from extensions.humanoid.spec import HumanoidSpec
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

comptime DEFAULT_OUTPUT = "out/arm.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "xhigh"
comptime SPACING = Float32(0.22)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    left: NodeId,
    right: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn both arms by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        left: The turning node of the anatomy.
        right: The turning node of the skin.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(left).rotate_y(step)
    scene.node(right).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def _hang(
    mut scene: Scene, x: Float32, height: Float32, center: Vector3
) raises -> Tuple[NodeId, NodeId]:
    """Return a turning node at `x` and the node an arm hangs from.

    The arm hangs so that its middle, `center` in the pelvis frame,
    sits on the turning node's axis.

    Args:
        scene: The scene that receives the nodes.
        x: Position along the row, in meters.
        height: Height of the arm's middle above the floor.
        center: The arm's middle in the pelvis frame, in meters.

    Returns:
        The turning node, then the node to hang the arm from.

    Raises:
        Error: If the scene refuses a node.
    """
    var pivot = Object3D()
    pivot.set_position(x, height, 0)
    var pivot_id = scene.add(pivot^)
    var holder = Object3D()
    holder.set_position(-center.x, -center.y, -center.z)
    return (pivot_id, scene.attach(holder^, pivot_id))


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

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    print("Arm tissue for a six-foot toned male:")
    print("  humerus", arm_bone_mass(person, HUMERUS).mass.to(GRAM), "g")
    print("  radius", arm_bone_mass(person, RADIUS).mass.to(GRAM), "g")
    print("  ulna", arm_bone_mass(person, ULNA).mass.to(GRAM), "g")
    print("  deltoid", arm_muscle_mass(person, DELTOID).mass.to(GRAM), "g")
    print(
        "  biceps brachii",
        arm_muscle_mass(person, BICEPS_BRACHII).mass.to(GRAM),
        "g",
    )
    print(
        "  triceps brachii",
        arm_muscle_mass(person, TRICEPS_BRACHII).mass.to(GRAM),
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
    var hair = assets.materials.add(hair_phong())

    # Image-based light: three.js's RoomEnvironment through a PMREM.
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)

    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.55

    # The arm's middle: halfway from the shoulder to the fingertips.
    var f = arm_dimensions(person.stature, person.sex).frame
    var tip = f.hand(0, -20, 0)
    var center = (f.shoulder + tip) * Float32(0.5)
    var height = Float32(0.62)
    var first = len(scene.meshes)
    var anatomy = _hang(scene, -SPACING, height, center)
    _ = add_upper_limb(
        scene,
        assets,
        anatomy[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        RIGHT,
        BOTH,
        detail,
        tendon_paint=tendon,
    )
    # The clavicle and the scapula the arm hangs from.
    var torso = torso_dimensions(person.stature, person.sex)
    place_mesh(
        scene,
        assets,
        anatomy[1],
        torso_bone_from_dimensions(torso, CLAVICLE, RIGHT, detail),
        bone,
    )
    place_mesh(
        scene,
        assets,
        anatomy[1],
        torso_bone_from_dimensions(torso, SCAPULA, RIGHT, detail),
        bone,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    first = len(scene.meshes)
    var covered = _hang(scene, SPACING, height, center)
    _ = add_upper_limb(
        scene,
        assets,
        covered[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        RIGHT,
        SKIN.plus(HAIR),
        detail,
        covering,
        hand_covering,
        skin_paint=skin,
        hair_paint=hair,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
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
    lamp.set_position(1.2, 2.2, 2.0)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 244, 228), lamp_node, 2.2)
    sun.cast_shadow = True
    sun.shadow.map_size = 1024
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(Length(1.2, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 0.66, 2.1), Vector3(0.0, 0.6, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(
                renderer, camera, assets, scene, anatomy[0], covered[0], step
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
