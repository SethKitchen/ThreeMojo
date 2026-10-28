# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's houses, as the game draws them: the street from above,
a framed house and the brick house from the trail, and a player inside
the stone cottage.

    mojo run -I . examples/village_houses.mojo [path.png]

The page is Village houses. The program builds the village game at the
`high` quality, in a window of 640 by 360 pixels. It stands the player at
four places, lets the camera settle, and draws each view into one tile of
a picture of 1280 by 720 pixels. For the last view, the player walks
through the stone cottage's front door. The program prints, as JSON, how
long the build and each view took.
"""

from tools._example_output import blit, example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.village.character import MoveInput, no_input
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import HIGH, game_quality
from extensions.water.pebbles import pebble_bed
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from render.jpeg import decode
from render.png import encode
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import stderr
from units.si import DEGREE, METER, MILLISECOND, SECOND, Angle, Duration, Length

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
) raises -> Framebuffer:
    """Stand the player at a place, facing a yaw, let the camera settle at
    a pitch and a distance, and draw the frame."""
    game.player.position = Vector3(x, game.terrain.height_at(x, z), z)
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
    blit(sheet, _view(game, scene, assets, 6, -6, -5, -24, 15), 0, 0)
    # The framed house from the trail.
    blit(
        sheet,
        _view(game, scene, assets, 12.5, -22, -80, -10, 5),
        TILE_WIDTH,
        0,
    )
    # The brick house, with the barn behind it.
    blit(
        sheet,
        _view(game, scene, assets, -19.5, -31, 25, -10, 6),
        0,
        TILE_HEIGHT,
    )
    # In through the stone cottage's door.
    var door = game.village.houses[2].interior.front_door()
    var middle = door.middle()
    var yaw = Float32(80)
    _ = _view(
        game,
        scene,
        assets,
        middle.x - door.swing_x * 2.5,
        middle.z - door.swing_z * 2.5,
        yaw,
        -12,
        4,
    )
    var ahead = MoveInput(1, 0, 0, 0, False, False)
    for _ in range(100):
        _ = game.tick(scene, assets, ahead, Duration(1.0 / 30.0, SECOND))
    game.render(scene, assets)
    blit(sheet, game.window, TILE_WIDTH, TILE_HEIGHT)
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
