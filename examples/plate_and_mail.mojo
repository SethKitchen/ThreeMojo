# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Eight people in plate and mail: four kits, each on a man and a woman.

    mojo run -I . examples/plate_and_mail.mojo [path.png] [turn]

The page is Outfits and armor, "Plate". Four men stand in front and
four women behind them, each in one of four kits:

- a full harness under a full helmet, with great pauldrons and a plate
  skirt: bright steel for the man, gilt silver for the woman;
- a full harness under a half helmet, with pauldrons and a plate skirt:
  blued steel trimmed with gold, and blackened steel trimmed with brass;
- a hauberk and a coif of mail, mail on the legs and plate on the
  shoulders: iron, and steel;
- a chain shirt over plate legs and a plate skirt, with great pauldrons
  and a half helmet: bronze, and copper trimmed with brass.

Each person's seed picks a genome. It writes
`out/plate_and_mail.png`.

The optional second argument turns every person about the vertical, in
degrees. The default is 25.
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
from extensions.attire.armory import (
    arm_harness,
    chain_shirt,
    great_helm,
    great_pauldrons,
    half_helm,
    mail_chausses,
    plate_legs,
    plate_skirt,
    platebody,
)
from extensions.attire.garment import (
    belt,
    boots,
    coif,
    forged,
    gambeson,
    gauntlets,
    hauberk,
    hose,
    pauldrons,
    sabatons,
    shirt,
)
from extensions.attire.metal import (
    BLACKENED,
    BLUED,
    BRASS,
    BRONZE,
    COPPER,
    GOLD,
    IRON,
    SILVER,
    STEEL,
    Metal,
)
from extensions.attire.outfit import Outfit, dress
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

comptime DEFAULT_OUTPUT = "out/plate_and_mail.png"
comptime DEFAULT_TURN = Float32(25.0)
comptime WIDTH = 1600
comptime HEIGHT = 820
comptime SPACING_X = Float32(0.92)
comptime TRIANGLES = 16000
comptime FIRST_SEED = 100


def _sexes() -> List[Sex]:
    """Return who wears each outfit: four men in front, four women behind."""
    return [MALE, MALE, MALE, MALE, FEMALE, FEMALE, FEMALE, FEMALE]


def _kit(kit: Int, metal: Metal, trim: Optional[Metal]) raises -> Outfit:
    """Return one of the four kits, forged of a metal."""
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(hose())
    outfit.add(gambeson())
    if kit == 0:
        # The legs first: the skirt over them hangs clear of their plate.
        outfit.add(forged(plate_legs(), metal, trim))
        outfit.add(forged(platebody(), metal, trim))
        outfit.add(forged(arm_harness(), metal, trim))
        outfit.add(forged(great_pauldrons(), metal, trim))
        outfit.add(forged(plate_skirt(), metal, trim))
        outfit.add(forged(gauntlets(), metal, trim))
        outfit.add(forged(sabatons(), metal, trim))
        outfit.add(forged(great_helm(), metal, trim))
    elif kit == 1:
        outfit.add(forged(plate_legs(), metal, trim))
        outfit.add(forged(platebody(), metal, trim))
        outfit.add(forged(arm_harness(), metal, trim))
        outfit.add(forged(pauldrons(), metal, trim))
        outfit.add(forged(plate_skirt(), metal, trim))
        outfit.add(forged(gauntlets(), metal, trim))
        outfit.add(forged(sabatons(), metal, trim))
        outfit.add(forged(half_helm(), metal, trim))
    elif kit == 2:
        outfit.add(forged(mail_chausses(), metal))
        outfit.add(forged(hauberk(), metal))
        outfit.add(forged(coif(), metal))
        outfit.add(forged(pauldrons(), metal, trim))
        outfit.add(belt())
        outfit.add(boots())
    else:
        outfit.add(forged(plate_legs(), metal, trim))
        outfit.add(forged(chain_shirt(), metal))
        outfit.add(forged(great_pauldrons(), metal, trim))
        outfit.add(forged(plate_skirt(), metal, trim))
        outfit.add(forged(sabatons(), metal, trim))
        outfit.add(forged(half_helm(), metal, trim))
        outfit.add(belt())
    return outfit^


def _outfit(index: Int) raises -> Outfit:
    """Return the outfit of the person at `index`: the men in front, left
    to right, then the women behind them in the same kits and other
    metals."""
    var none = Optional[Metal](None)
    if index == 0:
        return _kit(0, STEEL, none)
    if index == 1:
        return _kit(1, BLUED, Optional[Metal](GOLD))
    if index == 2:
        return _kit(2, IRON, none)
    if index == 3:
        return _kit(3, BRONZE, none)
    if index == 4:
        return _kit(0, SILVER, Optional[Metal](GOLD))
    if index == 5:
        return _kit(1, BLACKENED, Optional[Metal](BRASS))
    if index == 6:
        return _kit(2, STEEL, none)
    return _kit(3, COPPER, Optional[Metal](BRASS))


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
        # The women stand a row behind, between the men.
        var row = index // 4
        pivot.set_position(
            (Float32(index % 4) - 1.5 + 0.5 * Float32(row)) * SPACING_X,
            0,
            -1.1 * Float32(row),
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
        Vector3(0, 1.7, 5.0),
        Vector3(0, 0.95, -0.5),
        field_of_view=Angle(30.0, DEGREE),
        near=Length(0.05, METER),
        far=Length(30.0, METER),
    )
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
