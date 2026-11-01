# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One woman in every hairstyle, as a game humanoid with hair cards.

    mojo run -I . examples/game_hairstyles.mojo [path.png] [turn] [cards]

The page is Head, "Hair cards". The same woman wears each named style,
left to right and top to bottom, in the order of
`examples/hairstyles.mojo`. Each game humanoid grows the style's guide
strands over its shell and draws each as a card of fibers.
`GameHairMotion` settles the strands against her head and shoulders and
shades them for the scene's lights, as it shades strands. Each bust is
seen from behind and to one side.

The optional second argument turns every head about the vertical, in
degrees; zero shows the faces. The default is 140. The optional third
argument is the cards of each head; zero draws the shell alone, as "A
shell drawn alone" describes. The default is 700.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Expression, Gene, Genome
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.game_hair import GameHairMotion
from extensions.humanoid.rig.joints import HEAD
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import HairWind
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
from renderers.renderer import available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, FOOT, Length, RADIAN

comptime DEFAULT_OUTPUT = "out/game_hairstyles.png"
comptime DEFAULT_TURN = Float32(140.0)
comptime DEFAULT_CARDS = 700
# Steps that settle each groom against the head and the shoulders.
comptime SETTLE_STEPS = 8
comptime WIDTH = 1600
comptime HEIGHT = 760
comptime COLUMNS = 9
comptime SPACING_X = Float32(0.3)
comptime SPACING_Y = Float32(0.7)
# How far below the skull's joint each bust is cut, in meters.
comptime CUT_BELOW = Float32(0.36)
# The skin's triangle budget, as a game would draw her.
comptime TRIANGLES = 24000


def _model() raises -> HumanoidSpec:
    """Return the model of `examples/hairstyles.mojo`: medium brown skin
    and light brown hair.

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


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var degrees = DEFAULT_TURN
    if len(args) > 2:
        degrees = Float32(Float64(String(args[2])))
    var turn = degrees * Float32(0.017453292)
    var cards = DEFAULT_CARDS
    if len(args) > 3:
        cards = Int(String(args[3]))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(24, 25, 28))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.3
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
    var styles = named_hair_styles()
    var people = List[GameHumanoid]()
    for index in range(len(styles)):
        var column = index % COLUMNS
        var row = index // COLUMNS
        var x = (Float32(column) - Float32(COLUMNS - 1) / 2) * SPACING_X
        var y = (Float32(0.5) - Float32(row)) * SPACING_Y
        # A bust: the skin is cut off below the shoulders.
        var bust = assets.materials.get(looks.skin)
        bust.set_clipping_planes([Plane(Vector3(0, 1, 0), -(y - CUT_BELOW))])
        var skin = assets.materials.add(bust)
        var pivot = Object3D()
        pivot.set_position(x, y, 0)
        var pivot_id = scene.add(pivot^)
        scene.node(pivot_id).rotate_y(Angle(turn, RADIAN))
        var holder_id = scene.attach(Object3D(), pivot_id)
        var her = add_game_humanoid(
            scene,
            assets,
            holder_id,
            person,
            TRIANGLES,
            skin_paint=skin,
            hair_style=styles[index],
            cards=cards,
            workers=available_workers(),
        )
        var head = her.rig.joints[HEAD.value]
        scene.node(holder_id).set_position(-head.x, -head.y, -head.z)
        # The cards are cut off with the bust.
        for k in range(len(her.cards)):
            var paint = her.cards[k].material.value()
            var lines = assets.materials.get(paint)
            lines.set_clipping_planes(
                [Plane(Vector3(0, 1, 0), -(y - CUT_BELOW))]
            )
            assets.materials.materials[paint.value] = lines^
        people.append(her^)
        print(index + 1, "of", len(styles))

    # Lit from the camera's side, as the heads are turned away from it.
    var key = Object3D()
    key.set_position(1.4, 1.8, 2.2)
    var key_node = scene.add(key^)
    scene.add_light(directional_light(Color(255, 242, 226), key_node, 2.4))
    var fill = Object3D()
    fill.set_position(-1.4, 0.6, 1.6)
    var fill_node = scene.add(fill^)
    scene.add_light(directional_light(Color(210, 220, 255), fill_node, 0.9))
    var eye = Vector3(0.0, -0.02, 2.75)
    var camera = gallery_camera(WIDTH, HEIGHT, eye, Vector3(0.0, -0.06, 0.0))
    scene.update()
    # Settle each groom against her head and shoulders in still air, and
    # shade its cards for the two lights.
    var key_toward = Vector3(1.4, 1.8, 2.2)
    key_toward.normalize()
    var fill_toward = Vector3(-1.4, 0.6, 1.6)
    fill_toward.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(key_toward, Vector3(2.4, 2.3, 2.15)))
    lights.append(HairLight(fill_toward, Vector3(0.75, 0.8, 0.9)))
    for index in range(len(people)):
        if len(people[index].cards) == 0:
            continue
        var motion = GameHairMotion(
            scene, people[index], person, steps=SETTLE_STEPS
        )
        motion.update(
            scene,
            assets,
            people[index],
            lights,
            eye,
            Vector3(0.12, 0.12, 0.13),
            HairWind(Vector3(1, 0, 0), 0),
        )
        print("Settled", index + 1, "of", len(people))
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
