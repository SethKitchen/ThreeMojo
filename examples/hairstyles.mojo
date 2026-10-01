# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One woman in every hairstyle.

    mojo run -I . examples/hairstyles.mojo [path.png] [quality] [turn]

The page is Head. The same head wears each named style, left to right
and top to bottom: grown, layered, mohawk, long, ponytail, bun, high
ponytail, pigtails, space buns, braid, half up, bob and pixie. Each is
seen from behind and to one side, so the ties, the tails, the buns and
the braid show.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. The default is `high`. The optional third argument
turns every head about the vertical, in degrees; zero shows the faces.
The default is 140.
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
from extensions.humanoid.skeleton.head.contents import EYES, HAIR, SKIN
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_groom,
)
from extensions.humanoid.skeleton.head.hair.styles import named_hair_styles
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
from std.math import cos, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/hairstyles.png"
comptime DEFAULT_QUALITY = "high"
comptime DEFAULT_TURN = Float32(140.0)
comptime WIDTH = 1600
comptime HEIGHT = 720
comptime COLUMNS = 7
comptime SPACING_X = Float32(0.3)
comptime SPACING_Y = Float32(0.62)
# How far below a head's middle its bust is cut, in meters.
comptime CUT_BELOW = Float32(0.13)
comptime GUIDES = 1000
comptime FOLLOWERS = 5
comptime KEY_RADIANCE = Vector3(2.4, 2.1, 1.8)
comptime AMBIENT = Vector3(0.14, 0.14, 0.15)


def _model() raises -> HumanoidSpec:
    """Return the model: medium brown skin and light brown hair.

    Returns:
        Her spec.

    Raises:
        Error: Never, for these genes.
    """
    var values: List[Float32] = [
        0.3,
        0.3,
        -0.4,
        0.1,
        0.55,
        0.7,
        0.8,
        -0.1,
        0.3,
        -0.5,
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
    var degrees = DEFAULT_TURN
    if len(args) > 3:
        degrees = Float32(Float64(String(args[3])))
    var turn = degrees * Float32(0.017453292)

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
    scene.environment_intensity = 0.7

    var person = _model()
    var looks = add_complexion(assets, person.genome)
    var center = head_dimensions(person.stature, person.sex, person.genome).at(
        0, 66.0, 0
    )
    var styles = named_hair_styles()
    var hairs = List[HairStrands]()
    var places = List[Vector3]()
    for index in range(len(styles)):
        var column = index % COLUMNS
        var row = index // COLUMNS
        var x = (Float32(column) - Float32(COLUMNS - 1) / 2) * SPACING_X
        var y = (Float32(0.5) - Float32(row)) * SPACING_Y
        # A bust: the skin is cut off under the chin.
        var bust = assets.materials.get(looks.skin)
        bust.set_clipping_planes([Plane(Vector3(0, 1, 0), -(y - CUT_BELOW))])
        var skin = assets.materials.add(bust^)
        var pivot = Object3D()
        pivot.set_position(x, y, 0)
        var pivot_id = scene.add(pivot^)
        scene.node(pivot_id).rotate_y(Angle(turn, RADIAN))
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
            anatomy_detail(level),
            skin_detail(level),
            skin_paint=skin,
            hair_paint=looks.hair,
            eye_paint=looks.eyes,
            workers=available_workers(),
            hair_style=styles[index],
        )
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

    var key = Object3D()
    key.set_position(-1.2, 1.6, -2.0)
    var key_node = scene.add(key^)
    scene.add_light(directional_light(Color(255, 242, 226), key_node, 2.4))
    var fill = Object3D()
    fill.set_position(1.0, 0.8, 2.0)
    var fill_node = scene.add(fill^)
    scene.add_light(directional_light(Color(210, 220, 255), fill_node, 0.9))
    var eye = Vector3(0.0, 0.05, 2.75)
    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(eye, Vector3(0.0, 0.02, 0.0))
    var key_toward = Vector3(-1.2, 1.6, -2.0)
    key_toward.normalize()
    var fill_toward = Vector3(1.0, 0.8, 2.0)
    fill_toward.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(_turned(key_toward, -turn), KEY_RADIANCE))
    lights.append(
        HairLight(_turned(fill_toward, -turn), Vector3(0.5, 0.55, 0.65))
    )
    for index in range(len(hairs)):
        hairs[index].shade(
            assets,
            lights,
            _turned(eye - places[index], -turn) + center,
            AMBIENT,
        )
    scene.update()
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
