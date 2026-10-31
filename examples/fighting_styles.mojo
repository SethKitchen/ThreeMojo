# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Six fighters, one for each fighting style, fight the air in a row.

    mojo run -I . examples/fighting_styles.mojo [path.png]

The page is Village combat. From the left: hand to hand, the sword, the
axe, the mace, magic and archery. Each fighter presses its style's
buttons in turn: three light attacks, the heavy attack, and the three
specials. Each move plays its style's clip with its style's weapon in
hand, at its style's pace. So the fists are quickest, and the mace is
slowest. The program writes the frames as an animated PNG, and prints how
long the build and each frame took.
"""

from tools._example_output import example_destination, gallery_camera
from tools._example_studio import (
    cast_received_shadows,
    studio_floor,
    studio_sun,
)

from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.ground import Ground
from extensions.village.arms import Arms
from extensions.village.blade import BRIGHT_STEEL, SwordLooks
from extensions.village.character import Character, CharacterParameters
from extensions.village.clothes import (
    CREAM_WOOL,
    GRAY_WOOL,
    MADDER,
    NETTLE,
    WALNUT,
    WELD,
    WOAD,
    village_outfit,
)
from extensions.village.combat import (
    FightButton,
    Fighter,
    FighterParameters,
    style_move,
)
from extensions.village.residents import Body
from extensions.village.styles import STYLES, FightingStyle
from extensions.village.terrain import Terrain
from lights.light import ambient_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.time import perf_counter_ns
from units.si import DEGREE, INCH, METER, SECOND, Angle, Duration, Length

comptime DEFAULT_OUTPUT = "out/fighting_styles.png"
comptime WIDTH = 960
comptime HEIGHT = 360
comptime FPS = 12
comptime SECONDS = Float32(7)
comptime GAP = Float32(1.9)
"""How far apart the fighters stand, in meters."""
comptime PRESS_EVERY = Float32(0.32)
"""How often each fighter presses its next button, in seconds."""


def _outfit(k: Int) raises -> Outfit:
    """Return the clothes of the `k`th fighter."""
    var dyes: List[Color] = [
        MADDER,
        WOAD,
        NETTLE,
        GRAY_WOOL,
        CREAM_WOOL,
        WALNUT,
    ]
    var trims: List[Color] = [WELD, CREAM_WOOL, WALNUT, WELD, WOAD, NETTLE]
    return village_outfit(dyes[k], trims[k], WALNUT, k % 2 == 1)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var began = perf_counter_ns()
    var assets = Assets()
    var scene = Scene()
    var terrain = Terrain(Ground(hill_height=Length(0.0, METER)))
    var looks = SwordLooks(assets)
    var bodies = List[Body]()
    var kits = List[Arms]()
    var characters = List[Character]()
    var fighters = List[Fighter]()
    for k in range(STYLES):
        var sex = MALE if k % 2 == 0 else FEMALE
        var spec = HumanoidSpec(
            Length(68.0 + Float32(k % 3) * 2, INCH),
            sex,
            TONED,
            random_genome(200 + k),
        )
        var body = Body(scene, assets, spec, _outfit(k), 3000, 24)
        var style = FightingStyle(k)
        var kit = Arms(scene, assets, body, looks, BRIGHT_STEEL, [style])
        var x = (Float32(k) - Float32(STYLES - 1) / 2) * GAP
        # Each faces the camera, a little turned to show the swing.
        var character = Character(
            CharacterParameters(), x, 0, Angle(160.0, DEGREE), terrain
        )
        var fighter = Fighter(FighterParameters())
        _ = fighter.set_style(style)
        bodies.append(body^)
        kits.append(kit^)
        characters.append(character^)
        fighters.append(fighter^)
    studio_floor(scene, assets, Length(30.0, METER))
    studio_sun(scene, 2.5, 6.0, 5.0, Length(14.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.5))
    cast_received_shadows(scene)
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 28, 32))
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 1.7, 7.4),
        Vector3(0, 0.95, 0),
        field_of_view=Angle(40.0, DEGREE),
    )
    print("Built in", Float64(perf_counter_ns() - began) / 1e9, "s")
    # Three light attacks, the heavy attack, and the three specials.
    var order: List[Int] = [0, 0, 0, 1, 2, 3, 4]
    var frames = List[Framebuffer]()
    var count = Int(SECONDS * FPS)
    var step = Float32(1) / Float32(FPS)
    var sub = 4
    var pressed = 0
    var drawing = Float64(0)
    for frame in range(count):
        var t = Float32(frame) * step
        var due = Int(t / PRESS_EVERY)
        while pressed < due:
            var button = FightButton(order[pressed % len(order)])
            for k in range(STYLES):
                ref f = fighters[k]
                var move = style_move(f.style, button, True, f.move)
                _ = f.request(move)
            pressed += 1
        for k in range(STYLES):
            for _ in range(sub):
                fighters[k].update(Duration(step / Float32(sub), SECOND))
                # The fighters fight in place: no stamina, no special gauge
                # runs out.
                fighters[k].stamina = fighters[k].parameters.stamina
                fighters[k].special = fighters[k].parameters.special_points
                fighters[k].mana = fighters[k].parameters.mana
            kits[k].pose(
                scene,
                bodies[k],
                characters[k],
                fighters[k],
                True,
                Duration(step, SECOND),
            )
        scene.update()
        var drawn = perf_counter_ns()
        frames.append(renderer.render(scene, assets, camera))
        drawing += Float64(perf_counter_ns() - drawn) / 1e6
    print("Drew", count, "frames,", drawing / Float64(count), "ms each")
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print("Wrote", destination)
