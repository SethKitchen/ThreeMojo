# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's houses, as the game draws them: the street from above,
a framed house and the brick house from the trail, and a player before
the brick house's stair.

    mojo run -I . examples/village_houses.mojo [path.png]

The page is Village houses. The program builds the village game at the
`high` quality, in a window of 640 by 360 pixels. It stands the player at
four places, lets the camera settle, and draws each view into one tile of
a picture of 1280 by 720 pixels. For the last view, the player stands
in the brick house's hall before the open side of its stair. The program
prints, as JSON, how long the build and each view took.
"""

from tools._example_output import blit, example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from controls.third_person_controls import yaw_of
from extensions.village.character import no_input
from extensions.village.house import house_model, house_stair
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

comptime DEFAULT_OUTPUT = "out/village_houses.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime TILE_WIDTH = 640
comptime TILE_HEIGHT = 360


def _view(
    mut game: VillageGame,
    mut scene: Scene,
    mut assets: Assets,
    x: Float32,
    z: Float32,
    yaw: Float32,
    pitch: Float32,
    distance: Float32,
    foot: Float32,
) raises -> Framebuffer:
    """Stand the player at a place on the floor that feet at `foot` reach,
    facing a yaw, let the camera settle at a pitch and a distance, and
    draw the frame."""
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
    var game = VillageGame(
        scene,
        assets,
        Renderer(64, 64),
        PlayParameters(game_quality(HIGH)),
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
    # The street from above and behind the player.
    ref ground = game.terrain.ground
    blit(
        sheet,
        _view(game, scene, assets, 6, -6, -5, -24, 15, ground.height_at(6, -6)),
        0,
        0,
    )
    # The framed house from the trail.
    blit(
        sheet,
        _view(
            game,
            scene,
            assets,
            12.5,
            -22,
            -80,
            -10,
            5,
            ground.height_at(12.5, -22),
        ),
        TILE_WIDTH,
        0,
    )
    # The brick house, with the barn behind it.
    blit(
        sheet,
        _view(
            game,
            scene,
            assets,
            -19.5,
            -31,
            25,
            -10,
            6,
            ground.height_at(-19.5, -31),
        ),
        0,
        TILE_HEIGHT,
    )
    # The brick house's stair, from the hall before its open side. A plan
    # point (x, y) stands at the lot's (x, -y), turned by the lot's turn.
    var placed = PlayParameters(game_quality(HIGH)).village.houses[0].copy()
    var stair = house_stair(house_model(placed.house)).value()
    var turn = placed.turn.to(RADIAN)
    var c = cos(turn)
    var s = sin(turn)
    var px = Float32(stair.x0 + stair.x1) / 2
    var pz = -Float32(stair.y0) + 1.4
    # Facing the plan's +y, the back wall that the stair climbs along.
    var yaw = yaw_of(Vector3(-s, 0, -c)).to(DEGREE)
    blit(
        sheet,
        _view(
            game,
            scene,
            assets,
            placed.x + px * c + pz * s,
            placed.z - px * s + pz * c,
            yaw,
            -4,
            2.2,
            game.village.houses[0].interior.floor_height,
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
        ', "houses": ',
        len(game.village.houses),
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
