# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nine people, each in one design woven or embroidered over the dyes.

    mojo run -I . examples/designs.mojo [path.png] [turn]

The page is Garments, "Designs". Left to right: damask on a gown;
brocade on a doublet, its trim braided; a tartan kilt; pinstripe
trousers; diaper on a robe; flowers on a skirt; checks on a skirt;
herringbone on a coat; and hide on a leather jerkin. Each person's seed
picks a genome. It writes `out/designs.png`.

The optional second argument turns every person about the vertical, in
degrees. The default is 15.
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
from extensions.attire.apparel import (
    fur_kilt,
    tall_boots,
    trousers,
    wizard_robe,
)
from extensions.attire.garment import (
    Garment,
    belt,
    boots,
    breeches,
    gown,
    hose,
    jerkin,
    shirt,
)
from extensions.attire.kinds import (
    BROCADE,
    CHECK,
    DAMASK,
    DIAPER,
    FLORAL,
    HERRINGBONE,
    PINSTRIPE,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TARTAN,
    TRIM_DYE,
    WOOL,
    Design,
)
from extensions.attire.outfit import Outfit, dress
from extensions.attire.tailor import (
    GOLD_LACE,
    chemise,
    doublet,
    laced_bodice,
    laced_shirt,
    long_coat,
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

comptime DEFAULT_OUTPUT = "out/designs.png"
comptime DEFAULT_TURN = Float32(15.0)
comptime WIDTH = 1800
comptime HEIGHT = 640
comptime SPACING_X = Float32(0.62)
comptime TRIANGLES = 16000
comptime FIRST_SEED = 60


def _sexes() -> List[Sex]:
    """Return who wears each outfit."""
    return [FEMALE, MALE, MALE, MALE, FEMALE, FEMALE, FEMALE, MALE, MALE]


def _in(
    var garment: Garment,
    design: Design,
    primary: Color,
    secondary: Color,
    trim: Color,
) -> Garment:
    """Return a garment in a design and three dyes."""
    garment.design = design
    garment.dyes[PRIMARY_DYE.value] = primary
    garment.dyes[SECONDARY_DYE.value] = secondary
    garment.dyes[TRIM_DYE.value] = trim
    return garment^


def _outfit(index: Int) raises -> Outfit:
    """Return the outfit of the person at `index`, left to right."""
    var cream = Color(232, 222, 196)
    var outfit = Outfit()
    if index == 0:
        outfit.add(shirt())
        var teal = Color(32, 104, 118)
        outfit.add(_in(gown(), DAMASK, teal, teal, GOLD_LACE))
        outfit.add(belt())
        outfit.add(boots())
    elif index == 1:
        outfit.add(shirt())
        outfit.add(hose())
        outfit.add(breeches())
        var crimson = Color(140, 18, 30)
        outfit.add(_in(doublet(), BROCADE, crimson, cream, GOLD_LACE))
        outfit.add(boots())
    elif index == 2:
        outfit.add(laced_shirt())
        var kilt = fur_kilt()
        kilt.name = "plaid kilt"
        kilt.fabric = WOOL
        outfit.add(
            _in(
                kilt^,
                TARTAN,
                Color(36, 70, 52),
                Color(28, 40, 86),
                Color(176, 36, 32),
            )
        )
        outfit.add(belt())
        outfit.add(tall_boots())
    elif index == 3:
        outfit.add(shirt())
        var slate = Color(54, 58, 66)
        outfit.add(_in(trousers(), PINSTRIPE, slate, slate, cream))
        outfit.add(
            _in(waistcoat(), DIAPER, Color(92, 22, 30), cream, GOLD_LACE)
        )
        outfit.add(tall_boots())
    elif index == 4:
        outfit.add(shirt())
        var night = Color(30, 40, 104)
        var silver = Color(200, 204, 214)
        outfit.add(_in(wizard_robe(), DIAPER, night, night, silver))
        outfit.add(boots())
    elif index == 5:
        outfit.add(chemise())
        var laced = Color(70, 46, 32)
        outfit.add(_in(laced_bodice(), FLORAL, laced, laced, cream))
        var sky = Color(60, 92, 140)
        outfit.add(_in(skirt(), FLORAL, sky, Color(196, 60, 72), cream))
        outfit.add(boots())
    elif index == 6:
        outfit.add(chemise())
        var moss = Color(70, 86, 48)
        outfit.add(_in(laced_bodice(), DAMASK, moss, moss, moss))
        var red = Color(150, 36, 34)
        outfit.add(_in(skirt(), CHECK, red, red, cream))
        outfit.add(boots())
    elif index == 7:
        outfit.add(shirt())
        outfit.add(trousers())
        outfit.add(waistcoat())
        var heather = Color(112, 96, 82)
        outfit.add(_in(long_coat(), HERRINGBONE, heather, heather, heather))
        outfit.add(tall_boots())
    else:
        outfit.add(shirt())
        outfit.add(trousers())
        # Leather wears hide unless it is given another design.
        var tan = Color(132, 86, 48)
        var vest = jerkin()
        vest.dyes[PRIMARY_DYE.value] = tan
        outfit.add(vest^)
        outfit.add(belt())
        outfit.add(tall_boots())
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
        Vector3(0, 1.25, 5.4),
        Vector3(0, 1.0, 0),
        field_of_view=Angle(28.0, DEGREE),
        near=Length(0.05, METER),
        far=Length(30.0, METER),
    )
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
