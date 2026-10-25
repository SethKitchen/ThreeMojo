# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gusts sweep across the meadow and bend the tall grass, in a loop.

    mojo run -I . examples/meadow_wind.mojo [path.png] [width height]

The page is Why grass is drawn in clusters. The camera stands still, so
the wind is all that moves. The wind repeats itself every `LOOP` seconds,
and the frames divide the loop evenly, so the animation plays round and
round with no jump. Each frame culls the clusters again and grows the
drawn ones bent by the wind at that time. Each frame is the blend of
`SHUTTER` moments across half of its time, as a film camera's shutter is
open for half of each frame, so the blades that move blur and do not
jump. The size is 400 by 225 unless the arguments give another.
"""

from tools._example_output import example_destination, write_example

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.vegetation.meadow import (
    Meadow,
    MeadowParameters,
    blend_frames,
    meadow_camera,
    meadow_renderer,
)
from render.framebuffer import Framebuffer
from std.sys import argv
from units.si import METER, SECOND, Duration, Length

comptime DEFAULT_OUTPUT = "out/meadow-wind.png"
comptime WIDTH = 400
comptime HEIGHT = 225
# The frames a second, and how long the wind takes to repeat itself.
comptime RATE = 24
comptime LOOP = Float32(2.0)
# The moments blended into each frame, and the share of a frame's time
# the shutter is open.
comptime SHUTTER = 4
comptime OPEN = Float32(0.5)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var args = argv()
    var width = WIDTH
    var height = HEIGHT
    if len(args) > 3:
        width = Int(String(args[2]))
        height = Int(String(args[3]))
    var renderer = meadow_renderer(width, height)
    var assets = Assets()
    var scene = Scene()
    var parameters = MeadowParameters()
    parameters.wind.loop = Duration(LOOP, SECOND)
    var meadow = Meadow(scene, assets, renderer, parameters)
    var camera = meadow_camera(parameters, width, height, Length(0.0, METER))

    var frames_count = Int(LOOP * Float32(RATE))
    var clock = Clock()
    clock.start()
    var frames = List[Framebuffer]()
    var step = LOOP / Float32(frames_count)
    for index in range(frames_count):
        var moments = List[Framebuffer]()
        for k in range(SHUTTER):
            var within = (Float32(k) + 0.5) / Float32(SHUTTER) - 0.5
            var seconds = step * (Float32(index) + OPEN * within)
            _ = meadow.update(scene, assets, camera, Duration(seconds, SECOND))
            moments.append(renderer.render(scene, assets, camera))
        frames.append(blend_frames(moments))
    write_example(frames, destination, 1000 // RATE, frames_count, clock)
