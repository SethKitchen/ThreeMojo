# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A head that talks: its mouth follows the words, its face the mood.

    mojo run -I . examples/talking.mojo [path.png] [quality] [frames]

The page is Head. A woman says four phrases. Her mouth takes each
word's visemes in turn. Her face greets, smiles, frowns and is
surprised, one phrase at a time, and she blinks now and then. Her
head sways a little, so the face reads in the round.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. The default is `high`. The optional third argument is
how many frames to draw, one or more. The default draws the whole
speech, twenty frames a second.
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
    FROWN,
    NEUTRAL,
    SMILE,
    SURPRISE,
    FaceWeights,
    FacialExpression,
    face_rig_shapes,
)
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from extensions.humanoid.skeleton.head.hair.styles import BUN
from extensions.humanoid.skeleton.head.speech import Speech
from extensions.humanoid.skeleton.look import add_complexion
from extensions.humanoid.skeleton.morph import smoothstep
from extensions.humanoid.spec import HumanoidSpec
from lights.light import directional_light
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

comptime DEFAULT_OUTPUT = "out/talking.png"
comptime DEFAULT_QUALITY = "high"
comptime WIDTH = 400
comptime HEIGHT = 400
comptime FPS = 20
comptime GUIDES = 2000
comptime FOLLOWERS = 5
# Strands are drawn a little wider than a pixel, close up, so the hair
# reads as a mass.
comptime STRAND_WIDTH = Float32(1.4)
# How long the face takes to change its mood, either side of a phrase's
# start, in seconds.
comptime MOOD_TIME = Float32(0.25)
# When she blinks, in seconds, and how long a blink takes.
comptime BLINKS: List[Float32] = [0.9, 2.6, 4.4]
comptime BLINK_TIME = Float32(0.16)
comptime KEY_RADIANCE = Vector3(2.4, 2.1, 1.8)
comptime RIM_RADIANCE = Vector3(0.52, 0.6, 0.9)
comptime AMBIENT = Vector3(0.12, 0.12, 0.13)


def _speaker() raises -> HumanoidSpec:
    """Return the speaker: fair and freckled, with red hair in a bun.

    Returns:
        Her spec.

    Raises:
        Error: Never, for these genes.
    """
    var values: List[Float32] = [
        -0.9,
        -0.5,
        0.9,
        -0.2,
        0.95,
        -0.9,
        0.3,
        0.1,
        0.2,
        -0.3,
        0.2,
        -0.3,
        0.4,
        -0.5,
        -0.5,
        0.2,
        0.1,
        -0.3,
        0.2,
        -0.2,
        0.6,
        0.3,
        -0.5,
        0.1,
        0.1,
        -0.6,
        -0.1,
        0.2,
        -0.4,
        0.3,
    ]
    var genome = Genome()
    for index in range(len(values)):
        genome = genome.with_gene(Gene(index), Expression(values[index]))
    return HumanoidSpec(Length(5.6, FOOT), FEMALE, UNTONED, genome)


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

    # What she says, and how she looks as she says it.
    var phrases: List[String] = [
        "Hello there!",
        "I can smile,",
        "and I can frown.",
        "Oh, what a surprise!",
    ]
    var moods: List[FacialExpression] = [NEUTRAL, SMILE, FROWN, SURPRISE]
    var strengths: List[Float32] = [0.0, 0.9, 0.8, 0.9]
    var speeches = List[Speech]()
    var starts = List[Float32]()
    var at = Float32(0.3)
    for phrase in phrases:
        starts.append(at)
        speeches.append(Speech(phrase))
        at += speeches[len(speeches) - 1].duration()
    var length = at + Float32(0.6)
    var count = Int(length * FPS)
    if len(args) > 3:
        count = max(1, Int(String(args[3])))

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

    var person = _speaker()
    var looks = add_complexion(assets, person.genome)
    # A bust: the skin is cut off under the chin.
    var bust = assets.materials.get(looks.skin)
    bust.set_clipping_planes([Plane(Vector3(0, 1, 0), Float32(0.16))])
    var skin = assets.materials.add(bust^)
    var center = head_dimensions(person.stature, person.sex, person.genome).at(
        0, 72.0, 0
    )
    var pivot = Object3D()
    var pivot_id = scene.add(pivot^)
    var holder = Object3D()
    holder.set_position(-center.x, -center.y, -center.z)
    var holder_id = scene.attach(holder^, pivot_id)
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
        face_shapes=face_rig_shapes(),
    )
    var rigged = List[Int]()
    for m in range(first, len(scene.meshes)):
        if len(scene.meshes[m].morph_target_dictionary) > 0:
            rigged.append(m)
    var hair = add_groom(
        scene,
        assets,
        holder_id,
        person,
        GUIDES,
        FOLLOWERS,
        width=STRAND_WIDTH,
        style=BUN,
    )

    var key = Object3D()
    key.set_position(1.0, 1.4, 2.4)
    var key_node = scene.add(key^)
    scene.add_light(directional_light(Color(255, 242, 226), key_node, 2.4))
    var rim = Object3D()
    rim.set_position(-1.4, 1.0, -1.2)
    var rim_node = scene.add(rim^)
    scene.add_light(directional_light(Color(200, 214, 255), rim_node, 0.9))
    var eye = Vector3(0.0, 0.04, 0.74)
    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(eye, Vector3(0.0, 0.025, 0.0))
    var key_toward = Vector3(1.0, 1.4, 2.4)
    key_toward.normalize()
    var rim_toward = Vector3(-1.4, 1.0, -1.2)
    rim_toward.normalize()

    var frames = List[Framebuffer]()
    var previous = Float32(0)
    for frame in range(count):
        var t = Float32(frame) / Float32(FPS)
        # Each phrase brings its mood in as it starts and lets it go as
        # the next comes in.
        var face = FaceWeights()
        for k in range(len(phrases)):
            var end = length
            if k + 1 < len(phrases):
                end = starts[k + 1]
            var mood = smoothstep(
                starts[k] - MOOD_TIME, starts[k] + MOOD_TIME, t
            ) * (1 - smoothstep(end - MOOD_TIME, end + MOOD_TIME, t))
            if mood > 0:
                face.add_expression(moods[k], mood * strengths[k])
            speeches[k].speak(face, t - starts[k])
        for blink in materialize[BLINKS]():
            var d = abs(t - blink) / BLINK_TIME
            if d < 1:
                face.blink(1 - d * d)
        for m in rigged:
            face.apply(scene.meshes[m])
        # A slow sway, so the face reads in the round.
        var angle = Float32(0.18) * sin(Float32(1.3) * t)
        scene.node(pivot_id).rotate_y(Angle(angle - previous, RADIAN))
        previous = angle
        var lights = List[HairLight]()
        lights.append(HairLight(_turned(key_toward, -angle), KEY_RADIANCE))
        lights.append(HairLight(_turned(rim_toward, -angle), RIM_RADIANCE))
        hair.shade(assets, lights, _turned(eye, -angle) + center, AMBIENT)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print("Wrote", destination, "-", count, "frames")
