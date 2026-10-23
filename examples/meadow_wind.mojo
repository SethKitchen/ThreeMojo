# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gusts sweep across the meadow and bend the tall grass.

    mojo run -I . examples/meadow_wind.mojo [path.png]

The page is Why grass is drawn in clusters. The camera stands still, so
the wind is all that moves. Each frame culls the clusters again and grows
the drawn ones bent by the wind at that time. A gust bends the blades it
reaches and brightens their tips, so it shows as a wave of light that
travels downwind.
"""

from tools._example_output import example_destination, write_example

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.vegetation.meadow import (
    Meadow,
    MeadowParameters,
    meadow_camera,
    meadow_renderer,
)
from render.framebuffer import Framebuffer
from units.si import METER, SECOND, Duration, Length

comptime DEFAULT_OUTPUT = "out/meadow-wind.png"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime FRAMES = 16
comptime DELAY_MS = 120


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var renderer = meadow_renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = Scene()
    var parameters = MeadowParameters()
    var meadow = Meadow(scene, assets, renderer, parameters)
    var camera = meadow_camera(parameters, WIDTH, HEIGHT, Length(0.0, METER))

    var clock = Clock()
    clock.start()
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var seconds = Float32(index) * Float32(DELAY_MS) / 1000
        _ = meadow.update(scene, assets, camera, Duration(seconds, SECOND))
        frames.append(renderer.render(scene, assets, camera))
    write_example(frames, destination, DELAY_MS, FRAMES, clock)
