# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fight the bandits of the village with a sword, by a scripted gamepad.

    mojo run -I . examples/village_combat.mojo [path.png]

The page is Village combat. The player stands on the meadow north-west
of the trail, six meters from the bandits' camp, with the companion
beside them. The bandits notice the player and come. The script locks on
to the nearest, guards as they come, steps in and cuts three times,
dodges, makes the rising edge and the whirlwind, cuts once heavily, and
ends with the ground wave. The companion casts at the locked bandit. The
camera follows the lock.

The program needs no window and no pad. A pad of the web backend plays
the script at the `medium` quality in a window of 480 by 270. The program
writes the frames as an animated PNG, and prints how long the build and
each frame took, and how the fight went, as JSON.

To play the fight yourself, run `examples/village_walk.mojo --play`: see
its controls.
"""

from controls.third_person_controls import yaw_of
from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.gamepad.web import WebGamepadState, WebHub
from extensions.village.pad_input import gamepad_input
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import MEDIUM, game_quality
from extensions.water.pebbles import pebble_bed
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Framebuffer
from render.jpeg import decode
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import MILLISECOND, SECOND, Duration

comptime DEFAULT_OUTPUT = "out/village_combat.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime FPS = 8
"""The frames a second of the scripted fight."""
comptime SECONDS = Float32(10)
"""How long the scripted fight lasts."""
# The buttons of the browser's standard layout.
comptime SOUTH = 0
comptime EAST = 1
comptime WEST = 2
comptime NORTH = 3
comptime LEFT_SHOULDER = 4
comptime RIGHT_SHOULDER = 5
comptime LEFT_TRIGGER = 6
comptime RIGHT_STICK = 11


def _hold(mut state: WebGamepadState, button: Int):
    """Hold a button of the pad all the way down."""
    state.digital_buttons[button] = True
    state.analog_buttons[button] = 1


def _tap(t: Float32, at: Float32) -> Bool:
    """Return whether a tap at `at` seconds is down at `t`: for one frame
    of the script."""
    return t >= at and t < at + Float32(1) / Float32(FPS)


def _script(mut state: WebGamepadState, t: Float32):
    """Set the scripted pad for the time `t`, in seconds."""
    for index in range(len(state.axes)):
        state.axes[index] = 0
    for index in range(len(state.digital_buttons)):
        state.digital_buttons[index] = False
        state.analog_buttons[index] = 0
    # Lock on to the nearest bandit, and guard as they come.
    if _tap(t, 0.5):
        _hold(state, RIGHT_STICK)
    if t >= 1.0 and t < 2.4:
        _hold(state, LEFT_SHOULDER)
    # Step in, and cut three times.
    if t >= 2.4 and t < 3.0:
        state.axes[1] = -1
    for at in [Float32(3.0), Float32(3.375), Float32(3.75)]:
        if _tap(t, at):
            _hold(state, RIGHT_SHOULDER)
    # A dodge back.
    if _tap(t, 4.75):
        _hold(state, EAST)
    # The rising edge; a step in, and the whirlwind.
    if t >= 5.5 and t < 5.75:
        _hold(state, LEFT_TRIGGER)
        if _tap(t, 5.5):
            _hold(state, RIGHT_SHOULDER)
    if t >= 6.0 and t < 6.4:
        state.axes[1] = -1
    if t >= 6.5 and t < 6.75:
        _hold(state, LEFT_TRIGGER)
        if _tap(t, 6.5):
            _hold(state, NORTH)
    # A heavy cut, and the ground wave.
    if _tap(t, 7.75):
        _hold(state, NORTH)
    if t >= 8.75 and t < 9.0:
        _hold(state, LEFT_TRIGGER)
        if _tap(t, 8.75):
            _hold(state, WEST)


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]
    var clock = Clock()
    clock.start()
    var assets = Assets()
    var scene = Scene()
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var parameters = PlayParameters(game_quality(MEDIUM))
    # On the meadow, facing the bandits' camp, six meters off.
    parameters.start_x = -15
    parameters.start_z = 38
    parameters.heading = yaw_of(Vector3(-5, 0, 3))
    var game = VillageGame(
        scene,
        assets,
        Renderer(64, 64),
        parameters,
        bed^,
        None,
        WIDTH,
        HEIGHT,
    )
    var built = clock.elapsed().to(MILLISECOND)
    var hub = WebHub()
    var state = WebGamepadState(0, "Xbox Wireless Controller", 4, 17)
    _ = hub.connect(state)
    var frames = List[Framebuffer]()
    var count = Int(SECONDS * FPS)
    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    var drawing = Float32(0)
    var landed = 0
    for frame in range(count):
        _script(state, Float32(frame) / Float32(FPS))
        state.timestamp = Float64(frame + 1) * 1000.0 / Float64(FPS)
        _ = hub.update(state)
        var input = gamepad_input(hub.pads[0].gamepad)
        var began = clock.elapsed().to(MILLISECOND)
        _ = game.tick(scene, assets, input, step)
        game.render(scene, assets)
        frames.append(
            Framebuffer(game.width, game.height, game.window.pixels.copy())
        )
        drawing += clock.elapsed().to(MILLISECOND) - began
        landed = max(landed, game.battle.fighter.combo)
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    var wounds = Float32(0)
    for index in range(len(game.battle.foes)):
        ref foe = game.battle.foes[index]
        wounds += foe.fighter.parameters.health - foe.fighter.health
    print(
        '{"build_ms": ',
        built,
        ', "frame_ms": ',
        drawing / Float32(count),
        ', "frames": ',
        count,
        ', "bandits": ',
        len(game.battle.foes),
        ', "longest_combo": ',
        landed,
        ', "bandit_damage": ',
        wounds,
        ', "player_health": ',
        game.battle.fighter.health,
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
