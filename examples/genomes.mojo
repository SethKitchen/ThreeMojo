# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Six heads from six genomes, in a lit studio.

    mojo run -I . examples/genomes.mojo [path.png] [quality] [frames]

The page is Genome. Each head is the six-foot template with a different
genome: its skin tone, its hair and eye color, and the shape of its
head, its eyes, its brows, its nose, its mouth and its ears. Two wear
Sintel's layered cut and one a mohawk, and their hair runs from straight
to tightly coiled; see Head's hairstyles. Each is a
bust, cut off under the chin. The heads turn a little to each side, so
the shape reads.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. The default is `high`. The optional third argument is
how many frames to draw, one or more. The default is 24.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.skeleton.head.hair.styles import (
    GROWN,
    LAYERED,
    MOHAWK,
    HairStyle,
)
from extensions.humanoid.genome import (
    HAIR_CURL,
    FACE_SHAPES,
    FACE_SHAPE_1,
    HAIR_LENGTH,
    Expression,
    Gene,
    Genome,
)
from extensions.humanoid.quality import (
    anatomy_detail,
    quality_named,
    skin_detail,
)
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import EYES, HAIR, SKIN
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_groom,
)
from extensions.humanoid.skeleton.look import add_complexion
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.athleticism import UNTONED
from geometries.plane import plane
from lights.light import directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import standard_material
from math.bounds import Plane
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.math import cos, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER, RADIAN

# The hair's strands: guides per head, and followers per guide.
comptime GUIDES = 1000
comptime FOLLOWERS = 5
# The key and the rim lights' linear radiance, and the room's, as the
# hair's shading reads them.
comptime KEY_RADIANCE = Vector3(2.4, 2.1, 1.8)
comptime RIM_RADIANCE = Vector3(0.52, 0.6, 0.9)
comptime AMBIENT = Vector3(0.12, 0.12, 0.13)
comptime DEFAULT_OUTPUT = "out/genomes.png"
comptime WIDTH = 960
comptime HEIGHT = 540
comptime DEFAULT_FRAMES = 24
comptime DELAY_MS = 70
comptime DEFAULT_QUALITY = "high"
comptime COLUMNS = 3
comptime SPACING_X = Float32(0.27)
comptime SPACING_Y = Float32(0.3)
# How far below a head's middle its bust is cut, in meters.
comptime CUT_BELOW = Float32(0.13)


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


def _people() raises -> List[HumanoidSpec]:
    """Return the six people the gallery shows.

    Returns:
        Six specs of the same stature with different genomes.

    Raises:
        Error: If a genome is refused.
    """
    var stature = Length(6.0, FOOT)
    var people = List[HumanoidSpec]()
    # fmt: off
    # Fair, freckled and red-haired, with blue eyes, a small upturned
    # nose, a narrow face and ears that stand out.
    people.append(HumanoidSpec(stature, FEMALE, UNTONED, _genome([
        -0.9, -0.5, 0.9, -0.2, 0.95, -0.9, 0.3, 0.1, 0.2, -0.3,
        0.2, -0.3, 0.4, -0.5, -0.5, 0.2, 0.1, -0.3, 0.2, -0.2,
        0.6, 0.3, -0.5, 0.1, 0.1, -0.6, -0.1, 0.2, -0.4, 0.3,
    ])))
    # Deep brown skin, dark eyes and hair, a broad nose, full lips and
    # a strong jaw.
    people.append(HumanoidSpec(stature, MALE, UNTONED, _genome([
        0.95, 0.2, -1.0, 1.0, -1.0, 0.9, 0.0, 0.3, 0.0, 0.2,
        -0.2, 0.5, -0.2, 0.0, 0.8, -0.1, -0.4, 0.4, 0.9, 0.1,
        -0.3, 0.0, 0.3, 0.0, 0.0, 0.7, 0.4, 0.3, 0.5, 0.2,
    ])))
    # Olive skin, hazel eyes, a long high-bridged nose and a long head.
    people.append(HumanoidSpec(stature, MALE, UNTONED, _genome([
        0.1, 0.9, -0.6, 0.6, -0.4, 0.05, -0.1, -0.2, -0.1, 0.5,
        -0.4, 0.8, -0.3, 0.8, 0.0, 0.7, 0.9, 0.0, -0.3, 0.3,
        -0.2, -0.5, -0.3, 0.7, 0.1, 0.2, 0.6, -0.2, 0.8, 0.0,
    ])))
    # Light warm skin, dark hair, almond eyes tilted up, a low bridge,
    # a broad round head and small ears.
    people.append(HumanoidSpec(stature, FEMALE, UNTONED, _genome([
        -0.3, 0.6, -0.8, 0.95, -0.8, 0.8, -0.2, 0.4, 0.9, -0.6,
        0.3, -0.2, 0.1, -0.3, 0.2, -0.6, -0.9, -0.3, 0.1, -0.5,
        -0.6, -0.8, 0.7, -0.6, 0.2, 0.1, -0.3, 0.8, -0.8, 0.1,
    ])))
    # Medium brown skin, big eyes, arched brows, a wide mouth and a
    # small chin.
    people.append(HumanoidSpec(stature, FEMALE, UNTONED, _genome([
        0.45, 0.3, -0.4, 0.8, -0.2, 0.7, 0.8, -0.1, 0.3, -0.5,
        0.5, 0.2, 0.9, -0.2, 0.3, 0.1, -0.2, 0.7, 0.6, 0.2,
        0.0, 0.8, 0.0, 0.0, 0.3, -0.5, -0.6, 0.4, -0.3, 0.6,
    ])))
    # Very fair and cool, blond, gray-blue eyes, deep-set under a heavy
    # brow ridge, big ears and a tall head.
    people.append(HumanoidSpec(stature, MALE, UNTONED, _genome([
        -0.6, -0.9, 0.2, -0.8, -0.1, -0.6, -0.3, 0.0, -0.4, 0.9,
        -0.6, 0.7, -0.6, 0.4, 0.2, 0.5, 0.6, -0.2, -0.6, 0.9,
        0.2, 1.0, -0.2, 0.4, 0.8, 0.5, 0.8, 0.6, 1.0, -0.3,
    ])))
    # fmt: on
    # How each one wears the hair: a bob, a crop, short, a bob to the
    # jaw, a longer bob and short.
    var lengths: List[Float32] = [0.9, -0.8, 0.1, 0.7, 1.0, -0.2]
    # The shape of each whole face, along the face model's first modes.
    # fmt: off
    var shapes: List[Float32] = [
        0.6, -0.2, 0.3, 0.0, -0.3, 0.2, 0.0, 0.1,
        -0.5, 0.4, 0.0, -0.3, 0.2, 0.0, 0.3, 0.0,
        0.3, 0.5, -0.4, 0.4, 0.0, -0.2, 0.0, 0.2,
        -0.4, -0.5, 0.2, -0.4, 0.3, 0.3, -0.2, 0.0,
        0.1, 0.2, 0.6, 0.0, -0.5, 0.4, 0.1, -0.2,
        0.4, -0.3, -0.5, 0.3, 0.5, -0.4, 0.3, -0.3,
    ]
    # fmt: on
    # Wavy, straight, coiled, curly, curly and straight.
    var curls: List[Float32] = [0.35, 0.0, 1.0, 0.7, 0.6, 0.0]
    for index in range(len(people)):
        people[index].genome = people[index].genome.with_gene(
            HAIR_LENGTH, Expression(lengths[index])
        )
        people[index].genome = people[index].genome.with_gene(
            HAIR_CURL, Expression(curls[index])
        )
        for mode in range(FACE_SHAPES):
            people[index].genome = people[index].genome.with_gene(
                Gene(FACE_SHAPE_1.value + mode),
                Expression(shapes[index * FACE_SHAPES + mode]),
            )
    return people^


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

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(24, 25, 28))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.0
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    renderer.local_clipping_enabled = True

    var assets = Assets()
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.6

    var people = _people()
    var turners = List[NodeId]()
    # How each head's hair is cut and laid.
    var styles: List[HairStyle] = [
        LAYERED,
        MOHAWK,
        GROWN,
        LAYERED,
        GROWN,
        GROWN,
    ]
    var hairs = List[HairStrands]()
    var places = List[Vector3]()
    var centers = List[Vector3]()
    for index in range(len(people)):
        var person = people[index]
        var looks = add_complexion(assets, person.genome)
        # A bust: the skin is cut off under the chin, so the neck's base
        # and the shoulders' slopes do not show.
        var bust = assets.materials.get(looks.skin)
        var cut = Float32(0.17) + Float32(1 - index // COLUMNS) * SPACING_Y
        bust.set_clipping_planes([Plane(Vector3(0, 1, 0), -(cut - CUT_BELOW))])
        var skin = assets.materials.add(bust^)
        var column = index % COLUMNS
        var row = index // COLUMNS
        var x = (Float32(column) - Float32(COLUMNS - 1) / 2) * SPACING_X
        var y = Float32(0.17) + Float32(1 - row) * SPACING_Y
        var pivot = Object3D()
        pivot.set_position(x, y, 0)
        var pivot_id = scene.add(pivot^)
        var center = head_dimensions(
            person.stature, person.sex, person.genome
        ).at(0, 70.0, 0)
        var holder = Object3D()
        holder.set_position(-center.x, -center.y, -center.z)
        var holder_id = scene.attach(holder^, pivot_id)
        _ = add_head(
            scene,
            assets,
            holder_id,
            person,
            skin,
            skin,
            skin,
            skin,
            SKIN.plus(HAIR).plus(EYES),
            detail,
            covering,
            skin_paint=skin,
            hair_paint=looks.hair,
            eye_paint=looks.eyes,
            workers=available_workers(),
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
        places.append(Vector3(x, y, 0))
        centers.append(center)
        turners.append(pivot_id)
    for index in range(len(scene.meshes)):
        scene.meshes[index].cast_shadow = True
        scene.meshes[index].receive_shadow = True

    var key = Object3D()
    key.set_position(1.0, 1.6, 2.2)
    var key_node = scene.add(key^)
    var sun = directional_light(Color(255, 242, 226), key_node, 2.4)
    sun.cast_shadow = True
    sun.shadow.map_size = 2048
    sun.shadow.bias = -0.0004
    sun.shadow.normal_bias = 0.008
    sun.shadow.set_extent(Length(0.8, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)
    var rim = Object3D()
    rim.set_position(-1.4, 1.0, -1.2)
    var rim_node = scene.add(rim^)
    scene.add_light(directional_light(Color(200, 214, 255), rim_node, 0.9))

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 0.36, 1.32), Vector3(0.0, 0.335, 0.0))

    # The lights as the hair sees them: toward each, and how bright.
    var key_toward = Vector3(1.0, 1.6, 2.2)
    key_toward.normalize()
    var rim_toward = Vector3(-1.4, 1.0, -1.2)
    rim_toward.normalize()
    var eye = Vector3(0.0, 0.36, 1.32)
    var frames = List[Framebuffer]()
    var previous = Float32(0)
    for frame in range(count):
        # Swing each head from a three-quarter view on one side to the
        # other and back.
        var angle = Float32(0.55) * sin(
            Float32(6.2831853) * Float32(frame) / Float32(count) + 0.6
        )
        for index in range(len(turners)):
            scene.node(turners[index]).rotate_y(Angle(angle - previous, RADIAN))
        previous = angle
        for index in range(len(hairs)):
            # Carry the camera and the lights into the head's own frame.
            var lights = List[HairLight]()
            lights.append(HairLight(_turned(key_toward, -angle), KEY_RADIANCE))
            lights.append(HairLight(_turned(rim_toward, -angle), RIM_RADIANCE))
            var camera_at = (
                _turned(eye - places[index], -angle) + centers[index]
            )
            hairs[index].shade(assets, lights, camera_at, AMBIENT)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", count, "frames")
