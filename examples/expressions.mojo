# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One face in eight expressions.

    mojo run -I . examples/expressions.mojo [path.png] [quality]

The page is Head. The same woman shows each named expression in turn,
left to right and top to bottom: neutral, smile, frown, sadness,
surprise, anger, disgust and fear. Each head is rigged once, and the
expression is only a set of morph weights.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. The default is `high`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Expression, Gene, Genome
from extensions.humanoid.quality import (
    anatomy_detail,
    quality_named,
    skin_detail,
)
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import (
    EYES,
    HAIR,
    MOUTH,
    SKIN,
)
from extensions.humanoid.skeleton.head.expression import (
    FaceWeights,
    face_rig_shapes,
    named_facial_expressions,
)
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_groom,
)
from extensions.humanoid.skeleton.head.hair.styles import BUN
from extensions.humanoid.skeleton.look import add_complexion
from extensions.humanoid.spec import HumanoidSpec
from lights.light import directional_light
from math.bounds import Plane
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/expressions.png"
comptime DEFAULT_QUALITY = "high"
comptime WIDTH = 960
comptime HEIGHT = 540
comptime COLUMNS = 4
comptime SPACING_X = Float32(0.22)
comptime SPACING_Y = Float32(0.27)
# How far below a head's middle its bust is cut, in meters.
comptime CUT_BELOW = Float32(0.12)
comptime GUIDES = 1000
comptime FOLLOWERS = 5
comptime KEY_RADIANCE = Vector3(2.4, 2.1, 1.8)
comptime RIM_RADIANCE = Vector3(0.52, 0.6, 0.9)
comptime AMBIENT = Vector3(0.12, 0.12, 0.13)


def _model() raises -> HumanoidSpec:
    """Return the face: light warm skin, dark hair and almond eyes.

    Returns:
        Her spec.

    Raises:
        Error: Never, for these genes.
    """
    var values: List[Float32] = [
        -0.3,
        0.6,
        -0.8,
        0.95,
        -0.8,
        0.8,
        -0.2,
        0.4,
        0.9,
        -0.6,
        0.3,
        -0.2,
        0.1,
        -0.3,
        0.2,
        -0.6,
        -0.9,
        -0.3,
        0.1,
        -0.5,
        -0.6,
        -0.8,
        0.7,
        -0.6,
        0.2,
        0.1,
        -0.3,
        0.8,
        -0.8,
        0.1,
    ]
    var genome = Genome()
    for index in range(len(values)):
        genome = genome.with_gene(Gene(index), Expression(values[index]))
    return HumanoidSpec(Length(5.6, FOOT), FEMALE, UNTONED, genome)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(24, 25, 28))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.0
    renderer.local_clipping_enabled = True
    var assets = Assets()
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.6

    var person = _model()
    var looks = add_complexion(assets, person.genome)
    var center = head_dimensions(person.stature, person.sex, person.genome).at(
        0, 71.0, 0
    )
    var expressions = named_facial_expressions()
    var shapes = face_rig_shapes()
    var hairs = List[HairStrands]()
    var places = List[Vector3]()
    for index in range(len(expressions)):
        var column = index % COLUMNS
        var row = index // COLUMNS
        var x = (Float32(column) - Float32(COLUMNS - 1) / 2) * SPACING_X
        var y = (Float32(0.5) - Float32(row)) * SPACING_Y
        # A bust: the skin is cut off under the chin.
        var bust = assets.materials.get(looks.skin)
        bust.set_clipping_planes([Plane(Vector3(0, 1, 0), -(y - CUT_BELOW))])
        var skin = assets.materials.add(bust^)
        var holder = Object3D()
        holder.set_position(x - center.x, y - center.y, -center.z)
        var holder_id = scene.add(holder^)
        var first = len(scene.meshes)
        _ = add_head(
            scene,
            assets,
            holder_id,
            person,
            skin,
            skin,
            skin,
            skin,
            SKIN.plus(HAIR).plus(EYES).plus(MOUTH),
            anatomy_detail(level),
            skin_detail(level),
            skin_paint=skin,
            hair_paint=looks.hair,
            eye_paint=looks.eyes,
            workers=available_workers(),
            hair_style=BUN,
            face_shapes=shapes,
        )
        var face = FaceWeights()
        face.add_expression(expressions[index])
        for m in range(first, len(scene.meshes)):
            if len(scene.meshes[m].morph_target_dictionary) > 0:
                face.apply(scene.meshes[m])
        hairs.append(
            add_groom(
                scene,
                assets,
                holder_id,
                person,
                GUIDES,
                FOLLOWERS,
                style=BUN,
            )
        )
        places.append(Vector3(x, y, 0))

    var key = Object3D()
    key.set_position(1.0, 1.4, 2.4)
    var key_node = scene.add(key^)
    scene.add_light(directional_light(Color(255, 242, 226), key_node, 2.4))
    var rim = Object3D()
    rim.set_position(-1.4, 1.0, -1.2)
    var rim_node = scene.add(rim^)
    scene.add_light(directional_light(Color(200, 214, 255), rim_node, 0.9))
    var eye = Vector3(0.0, 0.03, 1.25)
    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(eye, Vector3(0.0, 0.0, 0.0))
    var key_toward = Vector3(1.0, 1.4, 2.4)
    key_toward.normalize()
    var rim_toward = Vector3(-1.4, 1.0, -1.2)
    rim_toward.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(key_toward, KEY_RADIANCE))
    lights.append(HairLight(rim_toward, RIM_RADIANCE))
    for index in range(len(hairs)):
        hairs[index].shade(
            assets, lights, eye - places[index] + center, AMBIENT
        )
    scene.update()
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
