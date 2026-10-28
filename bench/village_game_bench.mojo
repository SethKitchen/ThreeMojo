# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure the village game's frames at a quality preset, by stage.

    mojo run -I . bench/village_game_bench.mojo [PRESET [WIDTH HEIGHT [FRAMES]]]

PRESET is `low`, `medium`, `high` or `ultra`, `low` by default. The
window is 1920 by 1080 pixels unless given, and the walk lasts 240 frames
unless given. A scripted player walks, runs, jumps and looks round the
village at 24 frames a second of game time, as `examples/village_walk.mojo`
does. After ten warm-up frames each frame is timed by stage:

- `tick`: `VillageGame.tick`: the player, the residents, the grass's wind
  and the water's clock.
- `draw`: `GameRenderer.render` at the preset's smaller size.
- `water`: the pond's water composed into the frame.
- `smooth`: the frame's edges smoothed.
- `upscale`: the frame stretched to the window.
- `frame`: all five.

It prints, as JSON, the median, the 95th percentile and the slowest of
each stage in milliseconds, and the frames a second of the median frame.
The numbers describe the machine that runs it.
"""

from tools._bench_timing import _percentile, _sorted
from core.assets import Assets
from core.scene import Scene
from extensions.village.character import MoveInput
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import (
    HIGH,
    LOW,
    MEDIUM,
    QualityPreset,
    ULTRA,
    game_quality,
)
from extensions.water.pebbles import pebble_bed
from render.jpeg import decode
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv, stderr
from std.time import perf_counter_ns
from units.si import SECOND, Duration

comptime WARM_UP = 10
comptime FPS = 24


def _preset(name: String) raises -> QualityPreset:
    """Return the preset a name names."""
    if name == "low":
        return LOW
    if name == "medium":
        return MEDIUM
    if name == "high":
        return HIGH
    if name == "ultra":
        return ULTRA
    raise Error("A preset must be low, medium, high or ultra, not ", name)


def _input(t: Float32) -> MoveInput:
    """Return the scripted input at a time, in seconds, on a 10-second
    loop: walk, run bearing left with a jump, walk while looking round,
    and stand."""
    var s = t - Float32(Int(t / 10)) * 10
    if s < 3:
        return MoveInput(0.6, 0, 0, 0, False, False)
    if s < 6:
        return MoveInput(1, -0.35, 0, 0, True, s >= 4.5 and s < 4.8)
    if s < 9:
        return MoveInput(0.5, 0, 0.5, 0, False, False)
    return MoveInput(0, 0, 0, 0, False, False)


def _summary(name: String, var values: List[Int]) -> String:
    """Return one stage's median, 95th percentile and slowest, as JSON."""
    var ordered = _sorted(values^)
    return String(
        '"',
        name,
        '": {"median": ',
        _percentile(ordered, 0.5),
        ', "p95": ',
        _percentile(ordered, 0.95),
        ', "max": ',
        Float64(ordered[len(ordered) - 1]) / 1.0e6,
        "}",
    )


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var preset = _preset(words[1] if len(words) > 1 else "low")
    var width = 1920
    var height = 1080
    if len(words) > 3:
        width = Int(words[2])
        height = Int(words[3])
    var frames = 240
    if len(words) > 4:
        frames = Int(words[4])
    var assets = Assets()
    var scene = Scene()
    var bed = pebble_bed(decode(Path("assets/pebbles.jpg").read_bytes()))
    var painter = Renderer(64, 64)
    var built = perf_counter_ns()
    var game = VillageGame(
        scene,
        assets,
        painter,
        PlayParameters(game_quality(preset)),
        bed^,
        None,
        width,
        height,
    )
    var build_ms = Float64(perf_counter_ns() - built) / 1.0e6
    # Each stage's times, in nanoseconds.
    var ticks = List[Int]()
    var draws = List[Int]()
    var waters = List[Int]()
    var smooths = List[Int]()
    var upscales = List[Int]()
    var totals = List[Int]()
    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    for frame in range(WARM_UP + frames):
        var began = perf_counter_ns()
        var input = _input(Float32(frame) / Float32(FPS))
        _ = game.tick(scene, assets, input, step)
        var ticked = perf_counter_ns()
        game.render(scene, assets)
        var done = perf_counter_ns()
        if frame < WARM_UP:
            continue
        ticks.append(Int(ticked - began))
        draws.append(Int(game.render_ms * 1.0e6))
        waters.append(Int(game.water_ms * 1.0e6))
        smooths.append(Int(game.smooth_ms * 1.0e6))
        upscales.append(Int(game.upscale_ms * 1.0e6))
        totals.append(Int(done - began))
    var median = _percentile(_sorted(totals.copy()), 0.5)
    print(
        '{"preset": "',
        words[1] if len(words) > 1 else "low",
        '", "window": [',
        width,
        ", ",
        height,
        '], "frame_size": [',
        game.fast.width,
        ", ",
        game.fast.height,
        '], "build_ms": ',
        build_ms,
        ", ",
        _summary("tick", ticks^),
        ", ",
        _summary("draw", draws^),
        ", ",
        _summary("water", waters^),
        ", ",
        _summary("smooth", smooths^),
        ", ",
        _summary("upscale", upscales^),
        ", ",
        _summary("frame", totals^),
        ', "median_fps": ',
        1000.0 / median,
        "}",
        sep="",
    )
