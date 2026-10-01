# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two parents and their two grown children, in a lit studio.

    mojo run -I . examples/family.mojo [path.png] [quality] [frames]

The page is Genome. The mother and the father have genomes of their
own. Each child's genome is `offspring` of theirs: every gene lands
between the parents' two, with a small mutation. The four stand in a
row and turn, so the frame genes show as well as the face's and the
skin's: the breadth of the shoulders, the depth of the chest and the
length of the arms.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. The default is `high`. The optional third argument is
how many frames to draw, one or more. The default is 30.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.genome import Expression, Gene, Genome, offspring
from extensions.humanoid.quality import (
    anatomy_detail,
    hand_skin_detail,
    quality_named,
    skin_detail,
)
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.styles import (
    GROWN,
    LONG,
    PONYTAIL,
    HairStyle,
)
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_groom,
)
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.look import add_complexion
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.torso.body import add_body
from extensions.humanoid.skeleton.torso.contents import SKIN
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
from units.si import Angle, DEGREE, INCH, Length, METER

comptime DEFAULT_OUTPUT = "out/family.png"
comptime WIDTH = 800
comptime HEIGHT = 450
comptime DEFAULT_FRAMES = 30
comptime DELAY_MS = 70
comptime DEFAULT_QUALITY = "high"
comptime SPACING = Float32(0.8)
# The hair's strands: guides per head, and followers per guide.
comptime GUIDES = 900
comptime FOLLOWERS = 5
# The key and the rim lights' linear radiance, and the room's, as the
# hair's shading reads them.
comptime KEY_RADIANCE = Vector3(2.4, 2.1, 1.8)
comptime RIM_RADIANCE = Vector3(0.46, 0.54, 0.8)
comptime AMBIENT = Vector3(0.12, 0.12, 0.13)


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


def _genome(values: List[Float32]) raises -> Genome:
    """Return a genome whose genes 0, 1, 2, ... take `values` in order.

    Args:
        values: One expression per gene, from `MELANIN` on.

    Returns:
        The genome.

    Raises:
        Error: If a value lies outside -1 through 1.
    """
    var genome = Genome()
    for index in range(len(values)):
        genome = genome.with_gene(Gene(index), Expression(values[index]))
    return genome


def _family() raises -> List[HumanoidSpec]:
    """Return the mother, the father, the son and the daughter.

    Returns:
        Four specs.

    Raises:
        Error: If a genome is refused.
    """
    # fmt: off
    # Fair and freckled, red-haired and blue-eyed, with narrow
    # shoulders, a small nose and full lips.
    var mother = _genome([
        -0.8, -0.3, 0.7, -0.1, 0.9, -0.9, 0.3, 0.1, 0.2, -0.3,
        0.2, -0.3, 0.4, -0.4, -0.4, 0.1, 0.0, -0.2, 0.4, -0.2,
        0.3, 0.3, -0.4, 0.1, 0.1, -0.5, -0.1, 0.2, -0.4, 0.3,
        -0.7, -0.3, -0.2, 0.9,
    ])
    # Deep brown skin, black hair, dark eyes, a broad nose, broad
    # shoulders, a deep chest and long arms.
    var father = _genome([
        0.9, 0.2, -1.0, 1.0, -1.0, 0.9, 0.0, 0.3, 0.0, 0.2,
        -0.2, 0.5, -0.2, 0.0, 0.8, -0.1, -0.4, 0.4, 0.9, 0.1,
        -0.3, 0.0, 0.3, 0.0, 0.0, 0.7, 0.4, 0.3, 0.5, 0.2,
        0.9, 0.6, 0.7, -0.8,
    ])
    # fmt: on
    var people = List[HumanoidSpec]()
    people.append(HumanoidSpec(Length(66.0, INCH), FEMALE, UNTONED, mother))
    people.append(HumanoidSpec(Length(73.0, INCH), MALE, TONED, father))
    people.append(
        HumanoidSpec(
            Length(70.0, INCH), MALE, TONED, offspring(mother, father, 11)
        )
    )
    people.append(
        HumanoidSpec(
            Length(65.0, INCH), FEMALE, UNTONED, offspring(mother, father, 29)
        )
    )
    return people^


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))
    var count = DEFAULT_FRAMES
    if len(args) > 3:
        count = max(1, Int(String(args[3])))
    var detail = anatomy_detail(level)
    var covering = skin_detail(level)
    var hand_covering = hand_skin_detail(level)
    var workers = available_workers()

    var renderer = Renderer(WIDTH, HEIGHT, workers=workers)
    renderer.set_background(Color(24, 25, 28))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.0
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP

    var assets = Assets()
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.6

    var people = _family()
    var turners = List[NodeId]()
    var hairs = List[HairStrands]()
    var places = List[Vector3]()
    # How each one wears the hair: the mother long, the father and the
    # son grown, and the daughter in a ponytail.
    var styles: List[HairStyle] = [LONG, GROWN, GROWN, PONYTAIL]
    for index in range(len(people)):
        var person = people[index]
        var looks = add_complexion(assets, person.genome, whole_body=True)
        # The soles' height below the hip joint centers: the leg's
        # origin, its plafond, and the foot's ankle height.
        var pose = assemble_pelvis(person)
        var leg = assemble_leg(person, RIGHT)
        var ground = -(
            pose.leg_origin(RIGHT).y
            + leg.ankle_center().y
            - Float32(0.048) * person.stature.value
        )
        var pivot = Object3D()
        pivot.set_position(
            (Float32(index) - Float32(len(people) - 1) / 2) * SPACING, 0, 0
        )
        var pivot_id = scene.add(pivot^)
        var holder = Object3D()
        holder.set_position(0, ground, 0)
        var holder_id = scene.attach(holder^, pivot_id)
        _ = add_body(
            scene,
            assets,
            holder_id,
            person,
            looks.skin,
            looks.skin,
            looks.skin,
            looks.skin,
            looks.skin,
            looks.skin,
            SKIN,
            detail,
            covering,
            hand_covering,
            skin_paint=looks.skin,
            hair_paint=looks.hair,
            eye_paint=looks.eyes,
            workers=workers,
            hair_style=styles[index],
        )
        # The scalp's hair as strands, over the mass of it in shade.
        hairs.append(
            add_groom(
                scene,
                assets,
                holder_id,
                person,
                GUIDES,
                FOLLOWERS,
                style=styles[index],
            )
        )
        places.append(
            Vector3(
                (Float32(index) - Float32(len(people) - 1) / 2) * SPACING,
                ground,
                0,
            )
        )
        turners.append(pivot_id)
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

    var key = Object3D()
    key.set_position(1.4, 2.8, 2.6)
    var key_node = scene.add(key^)
    var sun = directional_light(Color(255, 242, 226), key_node, 2.4)
    sun.cast_shadow = True
    sun.shadow.map_size = 2048
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(Length(2.2, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(9.0, METER)
    scene.add_light(sun)
    var rim = Object3D()
    rim.set_position(-2.0, 1.8, -2.0)
    var rim_node = scene.add(rim^)
    scene.add_light(directional_light(Color(200, 214, 255), rim_node, 0.8))

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 1.2, 4.6), Vector3(0.0, 0.95, 0.0))

    var step = Angle(Float32(360) / Float32(count), DEGREE)
    # The lights as the hair sees them: toward each.
    var key_toward = Vector3(1.4, 2.8, 2.6)
    key_toward.normalize()
    var rim_toward = Vector3(-2.0, 1.8, -2.0)
    rim_toward.normalize()
    var eye = Vector3(0.0, 1.2, 4.6)
    var turned = Float32(0)
    var frames = List[Framebuffer]()
    for _ in range(count):
        for index in range(len(turners)):
            scene.node(turners[index]).rotate_y(step)
        turned += step.value
        for index in range(len(hairs)):
            # Carry the camera and the lights into the body's own frame.
            var lights = List[HairLight]()
            lights.append(HairLight(_turned(key_toward, -turned), KEY_RADIANCE))
            lights.append(HairLight(_turned(rim_toward, -turned), RIM_RADIANCE))
            var at = places[index]
            var camera_at = _turned(
                eye - Vector3(at.x, 0, 0), -turned
            ) - Vector3(0, at.y, 0)
            hairs[index].shade(assets, lights, camera_at, AMBIENT)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", count, "frames")
