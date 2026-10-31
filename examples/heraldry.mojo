# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ten men, each in a surcoat dyed in one of the ten dye patterns.

    mojo run -I . examples/heraldry.mojo [path.png]

The page is Garments, "Dyes and wear". Left to right: solid, party,
stripes, quarterly, chevron, cross, saltire, bend, paly and checky. Each
surcoat is a rich dye, and its second dye is bone white or a second rich
dye, in turn. Each hem is trimmed in gold. Each man's seed picks his
genome. It writes `out/heraldry.png`.
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
from extensions.attire.garment import belt, boots, hose, shirt, surcoat
from extensions.attire.kinds import (
    DYE_PATTERN_COUNT,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
    DyePattern,
)
from extensions.attire.mix import rich_dye
from extensions.attire.outfit import Outfit, dress
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import MALE
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
from units.si import DEGREE, INCH, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/heraldry.png"
comptime WIDTH = 1400
comptime HEIGHT = 420
comptime SPACING_X = Float32(0.62)
comptime TRIANGLES = 12000
comptime FIRST_SEED = 7
comptime BONE = Color(232, 226, 210)
comptime GOLD_TRIM = Color(200, 160, 60)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
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
    var count = DYE_PATTERN_COUNT
    for k in range(count):
        var spec = HumanoidSpec(
            Length(Float32(70), INCH),
            MALE,
            TONED,
            random_genome(FIRST_SEED + k),
        )
        var at = scene.add(Object3D())
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
        var x = (Float32(k) - Float32(count - 1) / 2) * SPACING_X
        scene.node(at).set_position(x, -lowest, 0)
        var outfit = Outfit()
        outfit.add(shirt())
        outfit.add(hose())
        var coat = surcoat()
        coat.dyes[PRIMARY_DYE.value] = rich_dye(k)
        coat.dyes[SECONDARY_DYE.value] = BONE if k % 2 == 0 else rich_dye(k + 3)
        coat.dyes[TRIM_DYE.value] = GOLD_TRIM
        coat.pattern = DyePattern(k)
        outfit.add(coat^)
        outfit.add(belt())
        outfit.add(boots())
        _ = dress(scene, assets, person, outfit)
        print(k + 1, "of", count)
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(16.0, METER))
    studio_sun(scene, 1.0, 3.6, 3.4, Length(7.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.2))
    scene.update()
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 1.2, 6.2),
        Vector3(0, 0.95, 0),
        field_of_view=Angle(34.0, DEGREE),
        near=Length(0.05, METER),
        far=Length(30.0, METER),
    )
    var frames = List[Framebuffer]()
    frames.append(renderer.render(scene, assets, camera))
    Path(destination).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", destination)
