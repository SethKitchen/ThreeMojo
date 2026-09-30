# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A neck and a head, with skin and without it, in a lit studio.

    mojo run -I . examples/head.mojo [path.png] [quality]

The page is Head. A six-foot male neck and head stand twice, each
turning about its own axis. The left copy shows the cervical vertebrae,
the skull, the mandible, the teeth and the hyoid, the joint tissues and
the cartilages of the larynx, and the muscles of the neck, the jaw and
the face. The right copy shows the skin, the hair and the eyes. The program also
prints the mass of several head parts.

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
    quality_named,
    skin_detail,
    triangle_budget,
)
from extensions.humanoid.skeleton.simplify import (
    fit_triangle_budget,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.bones.dimensions import (
    C2,
    MANDIBLE,
    SKULL,
)
from extensions.humanoid.skeleton.head.bones.mass import head_bone_mass
from extensions.humanoid.skeleton.head.contents import BOTH, EYES, HAIR, SKIN
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from extensions.humanoid.skeleton.head.muscles.dimensions import (
    MASSETER,
    STERNOCLEIDOMASTOID,
    TEMPORALIS,
)
from extensions.humanoid.skeleton.head.muscles.mass import head_muscle_mass
from extensions.humanoid.skeleton.bone import bone_albedo, bone_physical
from extensions.humanoid.skeleton.look import (
    add_complexion,
    cartilage_physical,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
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
from std.math import cos, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/head.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "xhigh"
comptime SPACING = Float32(0.16)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    left: NodeId,
    right: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn both heads by `step` and render one frame.

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


def _hang(
    mut scene: Scene, x: Float32, height: Float32, center: Vector3
) raises -> Tuple[NodeId, NodeId]:
    """Return a turning node at `x` and the node a head stands on.

    The head stands so that its middle, `center` in the pelvis frame,
    sits on the turning node's axis.

    Args:
        scene: The scene that receives the nodes.
        x: Position along the row, in meters.
        height: Height of the head's middle above the floor.
        center: The head's middle in the pelvis frame, in meters.

    Returns:
        The turning node, then the node to stand the head on.

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

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    print("Head tissue for a six-foot toned male:")
    print("  skull", head_bone_mass(person, SKULL).mass.to(GRAM), "g")
    print("  mandible", head_bone_mass(person, MANDIBLE).mass.to(GRAM), "g")
    print("  axis", head_bone_mass(person, C2).mass.to(GRAM), "g")
    print("  masseter", head_muscle_mass(person, MASSETER).mass.to(GRAM), "g")
    print(
        "  temporalis", head_muscle_mass(person, TEMPORALIS).mass.to(GRAM), "g"
    )
    print(
        "  sternocleidomastoid",
        head_muscle_mass(person, STERNOCLEIDOMASTOID).mass.to(GRAM),
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
    var looks = add_complexion(assets, person.genome)

    # Image-based light: three.js's RoomEnvironment through a PMREM.
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)

    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.55

    # The head's middle: between the ears, a little below the eyes. The
    # floor meets the neck at its base, where the torso would go on.
    var center = head_dimensions(person.stature, person.sex).at(0, 70.0, 0)
    var height = Float32(0.17)
    var first = len(scene.meshes)
    var anatomy = _hang(scene, -SPACING, height, center)
    _ = add_head(
        scene,
        assets,
        anatomy[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        BOTH,
        detail,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    var covered = _hang(scene, SPACING, height, center)
    _ = add_head(
        scene,
        assets,
        covered[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        SKIN.plus(HAIR).plus(EYES),
        detail,
        covering,
        skin_paint=looks.skin,
        hair_paint=looks.hair,
        eye_paint=looks.eyes,
        workers=available_workers(),
    )
    # The scalp's hair as strands, over the mass of it in shade.
    var hair = add_groom(scene, assets, covered[1], person, 1500, 6)
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
    lamp.set_position(1.2, 2.2, 2.0)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 244, 228), lamp_node, 2.2)
    sun.cast_shadow = True
    sun.shadow.map_size = 1024
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(Length(0.6, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 0.26, 1.05), Vector3(0.0, 0.2, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    # The lamp as the hair sees it, and the camera.
    var toward = Vector3(1.2, 2.2, 2.0)
    toward.normalize()
    var eye = Vector3(0.0, 0.26, 1.05)
    var turned = Float32(0)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        # The frame turns the head by `step`: carry the camera and the
        # lamp into its own frame, as it will stand.
        turned += step.value
        var lights = List[HairLight]()
        lights.append(
            HairLight(_turned(toward, -turned), Vector3(2.2, 1.97, 1.72))
        )
        var camera_at = (
            _turned(eye - Vector3(SPACING, height, 0), -turned) + center
        )
        hair.shade(assets, lights, camera_at, Vector3(0.11, 0.11, 0.12))
        frames.append(
            frame_at(
                renderer, camera, assets, scene, anatomy[0], covered[0], step
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
