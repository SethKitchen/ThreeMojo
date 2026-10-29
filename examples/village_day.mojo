# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village from late afternoon into the night, as the game draws it.

    mojo run -I . examples/village_day.mojo [path.png]

The page is Village day and night. The program builds the village game
at the `high` quality, in a window of 640 by 360 pixels. It draws four
views into the tiles of a picture of 1280 by 720 pixels: the trail at
five in the afternoon and at sunset, the brick house at eleven at night
with its windows lit, and the brick house's hall at the same hour, lit
by its lamps and its fire. The program prints, as JSON, how long the
build and the views took.
"""

from tools._example_output import blit, example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from controls.third_person_controls import yaw_of
from extensions.village.character import no_input
from extensions.village.house import house_breast, house_model, house_stair
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import HIGH, game_quality
from extensions.water.pebbles import pebble_bed
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from render.jpeg import decode
from render.png import encode
from renderers.renderer import Renderer
from std.math import cos, sin
from std.pathlib import Path
from std.sys import stderr
from units.si import (
    DEGREE,
    METER,
    MILLISECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
)

comptime DEFAULT_OUTPUT = "out/village_day.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime TILE_WIDTH = 640
comptime TILE_HEIGHT = 360


def _view(
    mut game: VillageGame,
    mut scene: Scene,
    mut assets: Assets,
    hour: Float32,
    x: Float32,
    z: Float32,
    yaw: Float32,
    pitch: Float32,
    distance: Float32,
    foot: Float32,
) raises -> Framebuffer:
    """Set the hour, stand the player at a place facing a yaw, let the
    camera settle, and draw the frame."""
    game.day.hour = hour
    game.player.position = Vector3(x, game.terrain.height_at(x, z, foot), z)
    game.player.velocity = Vector3(0, 0, 0)
    game.player.heading = Angle(yaw, DEGREE)
    game.view.yaw = Angle(yaw, DEGREE)
    game.view.pitch = Angle(pitch, DEGREE)
    game.view.distance = Length(distance, METER)
    game.view.focused = False
    game.reach = 1
    for _ in range(4):
        _ = game.tick(scene, assets, no_input(), Duration(0.05, SECOND))
    game.render(scene, assets)
    return Framebuffer(game.width, game.height, game.window.pixels.copy())


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var clock = Clock()
    clock.start()
    var assets = Assets()
    var scene = Scene()
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var parameters = PlayParameters(game_quality(HIGH))
    var game = VillageGame(
        scene,
        assets,
        Renderer(64, 64),
        parameters,
        bed^,
        None,
        TILE_WIDTH,
        TILE_HEIGHT,
    )
    var built = clock.elapsed().to(MILLISECOND)
    var sheet = Framebuffer(
        TILE_WIDTH * 2,
        TILE_HEIGHT * 2,
        List[UInt8](length=TILE_WIDTH * TILE_HEIGHT * 16, fill=255),
    )
    ref ground = game.terrain.ground
    var start = ground.height_at(0, 26)
    blit(sheet, _view(game, scene, assets, 17, 0, 26, 0, -6, 4, start), 0, 0)
    blit(
        sheet,
        _view(game, scene, assets, 19.6, 0, 26, 0, -6, 4, start),
        TILE_WIDTH,
        0,
    )
    # The brick house, from before its front door.
    ref placed = parameters.village.houses[0]
    var turn = placed.turn.to(RADIAN)
    var c = cos(turn)
    var s = sin(turn)
    var floor = game.village.houses[0].interior.floor_height
    var out_x = placed.x + 9 * s
    var out_z = placed.z + 9 * c
    var yaw = Float32(placed.turn.to(DEGREE))
    blit(
        sheet,
        _view(
            game,
            scene,
            assets,
            23,
            out_x,
            out_z,
            yaw,
            -8,
            4,
            ground.height_at(out_x, out_z),
        ),
        0,
        TILE_HEIGHT,
    )
    # Its hall, from its front corner: the fireplace in the gable wall and
    # the foot of the stair, as `village_houses.mojo` frames it.
    var model = house_model(placed.house)
    var stair = house_stair(model).value()
    var breast = house_breast(model).value()
    var tx = Float32(breast.x0 + breast.x1 + 2 * stair.x0) / 4
    var ty = Float32(breast.y0 + breast.y1 + stair.y0 + stair.y1) / 4
    var dx = Float32(-0.72)
    var dy = Float32(0.69)
    var px = tx - dx * 4
    var pz = -(ty - dy * 4)
    var look = yaw_of(Vector3(dx * c - dy * s, 0, -dx * s - dy * c))
    blit(
        sheet,
        _view(
            game,
            scene,
            assets,
            23,
            placed.x + px * c + pz * s,
            placed.z - px * s + pz * c,
            look.to(DEGREE),
            -6,
            2,
            floor,
        ),
        TILE_WIDTH,
        TILE_HEIGHT,
    )
    var drawn = clock.elapsed().to(MILLISECOND) - built
    Path(destination).write_bytes(encode(sheet))
    print(
        '{"build_ms": ',
        built,
        ', "views_ms": ',
        drawn,
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
