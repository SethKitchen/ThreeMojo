# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Eight people in the tailor's tops and bottoms, cut and shaped.

    mojo run -I . examples/tailoring.mojo [path.png] [turn]

The page is Garments, "The tailor". Left to right: a goodwife in a
chemise, a laced bodice, a skirt and an apron; a peasant in a laced
shirt and trousers; a merchant in a doublet and breeches over hose; a
courtier in a waistcoat under a frock coat; a lady in a ball gown over
a chemise; a gentleman in a waistcoat under a long coat; a lady in a
gown with banded sleeves; and a prince in a doublet under an open robe.
Most wear a design over their dyes: a floral bodice, tartan
trousers, pinstripe breeches, brocade and damask coats and gowns, a
diaper waistcoat and a herringbone coat. Each person's seed picks a
genome. It writes `out/tailoring.png`.

The optional second argument turns every person about the vertical, in
degrees. The default is 20.
"""

from tools._example_output import example_destination, gallery_camera
from tools._example_studio import (
    cast_received_shadows,
    studio_floor,
    studio_sun,
)

from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.attire.apparel import bodice, tall_boots, trousers
from extensions.attire.garment import (
    belt,
    boots,
    breeches,
    gown,
    hose,
    shirt,
)
from extensions.attire.kinds import (
    BANDED_SLEEVES,
    BROCADE,
    DAMASK,
    DIAPER,
    FLORAL,
    HERRINGBONE,
    PINSTRIPE,
    PRIMARY_DYE,
    TARTAN,
    SECONDARY_DYE,
    TRIM_DYE,
)
from extensions.attire.outfit import Outfit, dress
from extensions.attire.tailor import (
    GOLD_LACE,
    apron,
    ball_gown,
    chemise,
    doublet,
    frock_coat,
    laced_bodice,
    laced_shirt,
    long_coat,
    open_robe,
    skirt,
    waistcoat,
)
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.spec import HumanoidSpec
from lights.light import ambient_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, INCH, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/tailoring.png"
comptime DEFAULT_TURN = Float32(20.0)
comptime WIDTH = 1600
comptime HEIGHT = 560
comptime SPACING_X = Float32(0.72)
comptime TRIANGLES = 16000
comptime FIRST_SEED = 40


def _sexes() -> List[Sex]:
    """Return who wears each outfit."""
    return [FEMALE, MALE, MALE, MALE, FEMALE, MALE, FEMALE, MALE]


def _outfit(index: Int) raises -> Outfit:
    """Return the outfit of the person at `index`, left to right."""
    var outfit = Outfit()
    if index == 0:
        outfit.add(chemise())
        var laced = laced_bodice()
        laced.design = FLORAL
        outfit.add(laced^)
        outfit.add(skirt())
        outfit.add(apron())
        outfit.add(boots())
    elif index == 1:
        outfit.add(laced_shirt())
        var plaid = trousers()
        plaid.design = TARTAN
        plaid.dyes[SECONDARY_DYE.value] = Color(40, 70, 40)
        plaid.dyes[TRIM_DYE.value] = Color(170, 40, 30)
        outfit.add(plaid^)
        outfit.add(belt())
        outfit.add(tall_boots())
    elif index == 2:
        outfit.add(shirt())
        outfit.add(hose())
        var striped = breeches()
        striped.design = PINSTRIPE
        outfit.add(striped^)
        var coat = doublet()
        coat.design = BROCADE
        outfit.add(coat^)
        outfit.add(boots())
    elif index == 3:
        outfit.add(shirt())
        outfit.add(trousers())
        var vest = waistcoat()
        vest.design = FLORAL
        outfit.add(vest^)
        var coat = frock_coat()
        coat.design = DAMASK
        outfit.add(coat^)
        outfit.add(tall_boots())
    elif index == 4:
        outfit.add(chemise())
        var gown_ = ball_gown()
        gown_.design = BROCADE
        outfit.add(gown_^)
        outfit.add(boots())
    elif index == 5:
        outfit.add(shirt())
        outfit.add(trousers())
        var vest = waistcoat()
        vest.dyes[PRIMARY_DYE.value] = Color(196, 160, 72)
        vest.design = DIAPER
        outfit.add(vest^)
        var coat = long_coat()
        coat.design = HERRINGBONE
        outfit.add(coat^)
        outfit.add(tall_boots())
    elif index == 6:
        outfit.add(shirt())
        var dress_ = gown()
        dress_.pattern = BANDED_SLEEVES
        dress_.dyes[PRIMARY_DYE.value] = Color(32, 96, 112)
        dress_.dyes[SECONDARY_DYE.value] = GOLD_LACE
        dress_.dyes[TRIM_DYE.value] = GOLD_LACE
        dress_.design = DAMASK
        outfit.add(dress_^)
        outfit.add(belt())
        outfit.add(boots())
    else:
        outfit.add(shirt())
        outfit.add(hose())
        outfit.add(breeches())
        var coat = doublet()
        coat.dyes[PRIMARY_DYE.value] = Color(150, 150, 170)
        coat.design = DIAPER
        outfit.add(coat^)
        var robe = open_robe()
        robe.dyes[PRIMARY_DYE.value] = Color(132, 150, 176)
        robe.design = BROCADE
        outfit.add(robe^)
        outfit.add(boots())
    return outfit^


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var degrees = DEFAULT_TURN
    if len(args) > 2:
        degrees = Float32(Float64(String(args[2])))
    var workers = available_workers()
    var renderer = Renderer(WIDTH, HEIGHT, workers=workers)
    renderer.set_background(Color(20, 21, 24))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    var assets = Assets()
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.8
    var sexes = _sexes()
    var count = len(sexes)
    for index in range(count):
        var woman = sexes[index] == FEMALE
        var spec = HumanoidSpec(
            Length(Float32(65 if woman else 70), INCH),
            sexes[index],
            TONED,
            random_genome(FIRST_SEED + index),
        )
        var pivot = Object3D()
        pivot.set_position(
            (Float32(index) - Float32(count - 1) / 2) * SPACING_X, 0, 0
        )
        var pivot_id = scene.add(pivot^)
        scene.node(pivot_id).rotate_y(Angle(degrees, DEGREE))
        var at = scene.attach(Object3D(), pivot_id)
        var person = add_game_humanoid(
            scene, assets, at, spec, TRIANGLES, workers=workers
        )
        # Stand the soles on the floor.
        ref skin = assets.geometries.get(
            scene.skinned_meshes[person.skins[0]].geometry
        )
        ref placed = skin.attribute_view(String(POSITION))
        var lowest = Float32(1e9)
        for v in range(placed.count()):
            lowest = min(lowest, placed.vector3(v).y)
        scene.node(at).set_position(0, -lowest, 0)
        _ = dress(scene, assets, person, _outfit(index))
        print(index + 1, "of", count)
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(16.0, METER))
    studio_sun(scene, 1.0, 3.6, 3.4, Length(7.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.2))
    scene.update()
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 1.1, 6.6),
        Vector3(0, 0.92, 0),
        field_of_view=Angle(36.0, DEGREE),
        near=Length(0.05, METER),
        far=Length(30.0, METER),
    )
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
