# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Six heads from six genomes, in a lit studio.

    mojo run -I . examples/genomes.mojo [path.png] [quality] [frames]

The page is Genome. Each head is the six-foot template with a different
genome: its skin tone, its hair and eye color, and the shape of its
head, its eyes, its brows, its nose, its mouth and its ears. The heads
turn a little to each side, so the shape reads.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. The default is `high`. The optional third argument is
how many frames to draw, one or more. The default is 24.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.genome import (
    BROW_ARCH,
    BROW_HEIGHT,
    BROW_RIDGE,
    BROW_THICKNESS,
    CHEEKBONES,
    CHIN,
    EAR_LOBE,
    EAR_PROTRUSION,
    EAR_SIZE,
    EYE_DEPTH,
    EYE_SIZE,
    EYE_SPACING,
    EYE_TILT,
    Expression,
    FRECKLES,
    Gene,
    Genome,
    HAIR_MELANIN,
    HAIR_REDNESS,
    HEAD_HEIGHT,
    HEAD_LENGTH,
    HEAD_WIDTH,
    IRIS_MELANIN,
    JAW_WIDTH,
    LIP_FULLNESS,
    MELANIN,
    MOUTH_WIDTH,
    NECK_LENGTH,
    NOSE_BRIDGE,
    NOSE_LENGTH,
    NOSE_PROJECTION,
    NOSE_WIDTH,
    UNDERTONE,
)
from extensions.humanoid.quality import (
    anatomy_detail,
    quality_named,
    skin_detail,
)
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.skeleton.complexion import (
    hair_albedo,
    iris_albedo,
    skin_relief,
)
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import EYES, HAIR, SKIN
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.look import (
    eye_physical,
    hair_physical,
    skin_albedo,
    skin_physical,
)
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.athleticism import UNTONED
from geometries.plane import plane
from lights.light import directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import MaterialId, standard_material
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.math import sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/genomes.png"
comptime WIDTH = 960
comptime HEIGHT = 540
comptime DEFAULT_FRAMES = 24
comptime DELAY_MS = 70
comptime DEFAULT_QUALITY = "high"
comptime COLUMNS = 3
comptime SPACING_X = Float32(0.24)
comptime SPACING_Y = Float32(0.30)


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

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
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

    var relief_map = skin_relief(256)
    relief_map.repeat = Vector2(6, 5)
    var relief = assets.textures.add(relief_map^)
    var people = _people()
    var turners = List[NodeId]()
    for index in range(len(people)):
        var person = people[index]
        var albedo = skin_albedo(256, person.genome)
        albedo.repeat = Vector2(3, 2.5)
        var skin = assets.materials.add(
            skin_physical(
                assets.textures.add(albedo^),
                person.genome,
                relief,
                tinted=True,
            )
        )
        var strands = hair_albedo(256, person.genome)
        strands.repeat = Vector2(6, 2)
        var hair = assets.materials.add(
            hair_physical(person.genome, assets.textures.add(strands^))
        )
        var eye = assets.materials.add(
            eye_physical(assets.textures.add(iris_albedo(64, person.genome)))
        )
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
            hair_paint=hair,
            eye_paint=eye,
        )
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
    camera.place(Vector3(0.0, 0.34, 1.32), Vector3(0.0, 0.3, 0.0))

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
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", count, "frames")
