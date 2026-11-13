# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The summer grassland of `examples/meadow.mojo`, drawn on a GPU.

    mojo run -I . examples/meadow_gpu.mojo [path.png]

The page is Vegetation. The CPU still culls the grass clusters and grows
the ones in view. The GPU rasterizer then draws the prepared frame, in
place of the CPU rasterizer. The program prints, as JSON, how long each
step took and what the frame drew. It needs MAX and a GPU.
"""

from tools._example_output import example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.vegetation.gpu import MeadowDevice
from extensions.vegetation.meadow import (
    Meadow,
    MeadowParameters,
    meadow_camera,
    meadow_renderer,
)
from render.png import encode
from std.pathlib import Path
from std.sys import stderr
from units.si import METER, MILLISECOND, SECOND, Duration, Length

comptime DEFAULT_OUTPUT = "out/meadow_gpu.png"
comptime WIDTH = 1280
comptime HEIGHT = 720


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var clock = Clock()
    clock.start()
    var renderer = meadow_renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = Scene()
    var parameters = MeadowParameters()
    var meadow = Meadow(scene, assets, renderer, parameters)
    var device = MeadowDevice(renderer)
    device.upload(assets)
    var built = clock.elapsed().to(MILLISECOND)

    var camera = meadow_camera(parameters, WIDTH, HEIGHT, Length(0.0, METER))
    var frame = Clock()
    frame.start()
    var stats = meadow.update(scene, assets, camera, Duration(2.0, SECOND))
    var prepared = frame.elapsed().to(MILLISECOND)
    var image = device.draw(renderer, scene, assets, camera)
    var drawn = frame.elapsed().to(MILLISECOND) - prepared
    Path(destination).write_bytes(encode(image))
    print(
        '{"build_ms": ',
        built,
        ', "prepare_ms": ',
        prepared,
        ', "gpu_draw_ms": ',
        drawn,
        ', "clusters": ',
        stats.clusters,
        ', "drawn": ',
        stats.drawn,
        ', "culled": ',
        stats.culled,
        ', "beyond": ',
        stats.beyond,
        ', "blades": ',
        stats.blades,
        ', "grass_triangles": ',
        stats.triangles,
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
