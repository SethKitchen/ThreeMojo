# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two forest outlaws with their longbows and quivers.

    mojo run -I . examples/outlaws.mojo [path.png] [turn]

The page is Outfits and armor, "The forest outlaw". A man in a hood and
a hood cape, and a woman in a feathered cap and a hood cape, each in a
forest-green tunic, a leather jerkin and tall boots. Each holds a
longbow and wears a quiver on the back. They are turned three-quarters
away, so the quivers show. Each person's seed picks a genome. It writes
`out/outlaws.png`.

The optional second argument turns every person about the vertical, in
degrees. The default is 150.
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
from extensions.attire.apparel import feathered_cap, hood_cape, tall_boots
from extensions.attire.archery import equip_archer
from extensions.attire.armory import bracers
from extensions.attire.garment import belt, hood, hose, jerkin, shirt, tunic
from extensions.attire.kinds import PRIMARY_DYE
from extensions.attire.outfit import Outfit, dress
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.spec import HumanoidSpec
from lights.light import ambient_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import (
    DOUBLE_SIDE,
    SCENE_ENVIRONMENT,
    physical_material,
)
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, INCH, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/outlaws.png"
comptime DEFAULT_TURN = Float32(150.0)
comptime WIDTH = 1200
comptime HEIGHT = 720
comptime SPACING_X = Float32(0.8)
comptime TRIANGLES = 16000
comptime FIRST_SEED = 90


def _sexes() -> List[Sex]:
    """Return who wears each outfit."""
    return [MALE, FEMALE]


def _outfit(index: Int) raises -> Outfit:
    """Return the outfit of the person at `index`, left to right."""
    var green = Color(58, 90, 44)
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(hose())
    var coat = tunic()
    coat.dyes[PRIMARY_DYE.value] = green
    if index == 1:
        coat.flare = 0.32
    outfit.add(coat^)
    outfit.add(jerkin())
    outfit.add(bracers())
    outfit.add(belt())
    if index == 0:
        var cowl = hood()
        cowl.dyes[PRIMARY_DYE.value] = green
        outfit.add(cowl^)
    else:
        outfit.add(feathered_cap())
    outfit.add(hood_cape())
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
    var look = physical_material(
        Color(255, 255, 255),
        roughness=0.55,
        side=DOUBLE_SIDE,
        env_map=SCENE_ENVIRONMENT,
    )
    look.vertex_colors = True
    var painted = assets.materials.add(look)
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
        _ = equip_archer(scene, assets, person, painted)
        print(index + 1, "of", count)
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(16.0, METER))
    studio_sun(scene, 1.0, 3.6, 3.4, Length(7.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.2))
    scene.update()
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 1.15, 3.9),
        Vector3(0, 0.9, 0),
        field_of_view=Angle(32.0, DEGREE),
        near=Length(0.05, METER),
        far=Length(30.0, METER),
    )
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
