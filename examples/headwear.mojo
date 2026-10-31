# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Eight heads, each in a hat or a helmet shaped round it.

    mojo run -I . examples/headwear.mojo [path.png] [turn]

The page is Garments, "Hats and helmets". Left to right: a great helm
of blued steel gilt at its edges, a half helm of bronze, a horned helm
of iron, a wizard's hat, a straw hat, a feathered cap, a crown of gold
and a circlet of silver. Each person's seed picks a genome, and each
wears hair cards that the hat lays under its crown. A great helm hides
the hair; every other hat leaves it below its brim. Each bust is seen
from the front and a little to one side.

The optional second argument turns every head about the vertical, in
degrees. The default is 25.
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
from extensions.attire.apparel import (
    circlet,
    crown,
    feathered_cap,
    straw_hat,
    wizard_hat,
)
from extensions.attire.armory import great_helm, half_helm, horned_helm
from extensions.attire.garment import Garment, forged
from extensions.attire.metal import BLUED, BRONZE, GOLD, IRON
from extensions.attire.outfit import Outfit, dress
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.game_hair import GameHairMotion
from extensions.humanoid.rig.joints import HEAD
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.skeleton.head.hair.beard import (
    CLEAN_SHAVEN,
    FORKED_BEARD,
    LONG_BEARD,
    SHORT_BEARD,
    Beard,
)
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import HairWind
from extensions.humanoid.skeleton.head.hair.styles import (
    BRAID,
    CROPPED,
    GROWN,
    LONG,
    TWIN_BRAIDS,
    HairStyle,
)
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
from units.si import DEGREE, INCH, RADIAN, Angle, Length

comptime DEFAULT_OUTPUT = "out/headwear.png"
comptime DEFAULT_TURN = Float32(25.0)
comptime WIDTH = 1600
comptime HEIGHT = 420
comptime SPACING_X = Float32(0.36)
# How far below the skull's joint each bust is cut, in meters.
comptime CUT_BELOW = Float32(0.3)
comptime TRIANGLES = 24000
comptime CARDS = 600
comptime FIRST_SEED = 21


def _hats() raises -> List[Garment]:
    """Return the eight hats, left to right."""
    return [
        forged(great_helm(), BLUED, GOLD),
        forged(half_helm(), BRONZE),
        forged(horned_helm(), IRON),
        wizard_hat(),
        straw_hat(),
        feathered_cap(),
        crown(),
        circlet(),
    ]


def _sexes() -> List[Sex]:
    """Return who wears each hat."""
    return [MALE, MALE, FEMALE, MALE, FEMALE, MALE, MALE, FEMALE]


def _styles() -> List[HairStyle]:
    """Return the hairstyle under each hat."""
    return [CROPPED, GROWN, TWIN_BRAIDS, LONG, BRAID, GROWN, GROWN, LONG]


def _beards() -> List[Beard]:
    """Return the beard under each hat."""
    return [
        CLEAN_SHAVEN,
        SHORT_BEARD,
        CLEAN_SHAVEN,
        LONG_BEARD,
        CLEAN_SHAVEN,
        CLEAN_SHAVEN,
        FORKED_BEARD,
        CLEAN_SHAVEN,
    ]


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var degrees = DEFAULT_TURN
    if len(args) > 2:
        degrees = Float32(Float64(String(args[2])))
    var turn = degrees * Float32(0.017453292)

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(24, 25, 28))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.2
    renderer.local_clipping_enabled = True
    var assets = Assets()
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.8

    var hats = _hats()
    var sexes = _sexes()
    var styles = _styles()
    var beards = _beards()
    var people = List[GameHumanoid]()
    var specs = List[HumanoidSpec]()
    var count = len(hats)
    for index in range(count):
        var x = (Float32(index) - Float32(count - 1) / 2) * SPACING_X
        var seed = FIRST_SEED + 5 * index
        var woman = sexes[index] == FEMALE
        var spec = HumanoidSpec(
            Length(Float32(65 if woman else 70), INCH),
            sexes[index],
            TONED,
            random_genome(seed),
        )
        var looks = add_complexion(assets, spec.genome)
        # A bust: the skin is cut off below the shoulders.
        var bust = assets.materials.get(looks.skin)
        bust.set_clipping_planes([Plane(Vector3(0, 1, 0), CUT_BELOW)])
        var skin = assets.materials.add(bust)
        var pivot = Object3D()
        pivot.set_position(x, 0, 0)
        var pivot_id = scene.add(pivot^)
        scene.node(pivot_id).rotate_y(Angle(turn, RADIAN))
        var holder_id = scene.attach(Object3D(), pivot_id)
        var person = add_game_humanoid(
            scene,
            assets,
            holder_id,
            spec,
            TRIANGLES,
            skin_paint=skin,
            hair_style=styles[index],
            workers=available_workers(),
            beard=beards[index],
            cards=CARDS,
        )
        var head = person.rig.joints[HEAD.value]
        scene.node(holder_id).set_position(-head.x, -head.y, -head.z)
        # The cards are cut off with the bust.
        for k in range(len(person.cards)):
            var paint = person.cards[k].material.value()
            var lines = assets.materials.get(paint)
            lines.set_clipping_planes([Plane(Vector3(0, 1, 0), CUT_BELOW)])
            assets.materials.materials[paint.value] = lines^
        var outfit = Outfit()
        outfit.add(hats[index].copy())
        _ = dress(scene, assets, person, outfit)
        people.append(person^)
        specs.append(spec)
        print(index + 1, "of", count)

    var key_toward = Vector3(1.2, 1.6, 2.2)
    key_toward.normalize()
    var fill_toward = Vector3(-1.6, 0.4, 1.4)
    fill_toward.normalize()
    var key = Object3D()
    key.set_position(key_toward.x, key_toward.y, key_toward.z)
    var key_node = scene.add(key^)
    scene.add_light(directional_light(Color(255, 242, 226), key_node, 2.6))
    var fill = Object3D()
    fill.set_position(fill_toward.x, fill_toward.y, fill_toward.z)
    var fill_node = scene.add(fill^)
    scene.add_light(directional_light(Color(210, 220, 255), fill_node, 0.9))
    var eye = Vector3(0.0, 0.06, 2.6)
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        eye,
        Vector3(0.0, 0.02, 0.0),
        field_of_view=Angle(19.0, DEGREE),
    )
    scene.update()
    # Settle each groom against its head in still air, and shade it.
    var lights = List[HairLight]()
    lights.append(HairLight(key_toward, Vector3(2.5, 2.4, 2.2)))
    lights.append(HairLight(fill_toward, Vector3(0.75, 0.8, 0.9)))
    for index in range(len(people)):
        var motion = GameHairMotion(scene, people[index], specs[index], steps=8)
        motion.update(
            scene,
            assets,
            people[index],
            lights,
            eye,
            Vector3(0.12, 0.12, 0.13),
            HairWind(Vector3(1, 0, 0), 0),
        )
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
