# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village in four weathers, as the game draws them: clear, overcast,
rain and fog.

    mojo run -I . examples/village_weather.mojo [path.png]

The page is Village weather. The program builds the village game at the
`high` quality, in a window of 640 by 360 pixels. It stands the player on
the trail before the pond, and draws one view for each weather into one
tile of a picture of 1280 by 720 pixels. Each weather is set at once,
and the game runs a second in it before the view is drawn. The program
prints, as JSON, how long the build and the views took.
"""

from tools._example_output import blit, example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.village.character import no_input
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import HIGH, game_quality
from extensions.village.weather import (
    CLEAR,
    FOG,
    OVERCAST,
    RAIN,
    WeatherKind,
    weather_look,
)
from extensions.water.pebbles import pebble_bed
from render.framebuffer import Framebuffer
from render.jpeg import decode
from render.png import encode
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import stderr
from units.si import MILLISECOND, SECOND, Duration

comptime DEFAULT_OUTPUT = "out/village_weather.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime TILE_WIDTH = 640
comptime TILE_HEIGHT = 360


def _view(
    mut game: VillageGame,
    mut scene: Scene,
    mut assets: Assets,
    kind: WeatherKind,
) raises -> Framebuffer:
    """Set a weather at once, run the game a second in it, and draw."""
    game.weather.set(kind)
    game.weather.look = weather_look(kind)
    for _ in range(10):
        _ = game.tick(scene, assets, no_input(), Duration(0.1, SECOND))
    # No flash of lightning in the picture.
    game.weather.flash = 0
    _ = game.tick(scene, assets, no_input(), Duration(0.0, SECOND))
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
    var kinds: List[WeatherKind] = [CLEAR, OVERCAST, RAIN, FOG]
    for k in range(4):
        blit(
            sheet,
            _view(game, scene, assets, kinds[k]),
            (k % 2) * TILE_WIDTH,
            (k // 2) * TILE_HEIGHT,
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
