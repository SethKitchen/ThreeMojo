# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A summer meadow at head height: tall grass, poppies and a treeline.

    mojo run -I . examples/meadow.mojo [path.png]

The page is Vegetation. The camera stands in the grass and looks up the
slope to the trees. The field holds ten million blades in clusters. Only
the clusters in view are grown, each at the level of detail its distance
picks, so a few percent of the blades are drawn. The program prints, as
JSON, how long each step took and what the frame drew.
"""

from tools._example_output import example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
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

comptime DEFAULT_OUTPUT = "out/meadow.png"
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
    var built = clock.elapsed().to(MILLISECOND)

    var camera = meadow_camera(parameters, WIDTH, HEIGHT, Length(0.0, METER))
    var frame = Clock()
    frame.start()
    var stats = meadow.update(scene, assets, camera, Duration(2.0, SECOND))
    var prepared = frame.elapsed().to(MILLISECOND)
    var image = renderer.render(scene, assets, camera)
    var drawn = frame.elapsed().to(MILLISECOND) - prepared
    Path(destination).write_bytes(encode(image))
    print(
        '{"build_ms": ',
        built,
        ', "prepare_ms": ',
        prepared,
        ', "render_ms": ',
        drawn,
        ', "field_blades": ',
        meadow.field.full_blades(),
        ', "clusters": ',
        stats.clusters,
        ', "drawn": ',
        stats.drawn,
        ', "culled": ',
        stats.culled,
        ', "beyond": ',
        stats.beyond,
        ', "empty": ',
        stats.empty,
        ', "blades": ',
        stats.blades,
        ', "grass_triangles": ',
        stats.triangles,
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
