# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Walk, run and jump through the village as a person, with a gamepad.

    mojo run -I . examples/village_walk.mojo [path.png]
    mojo run -I . examples/village_walk.mojo --play [WIDTH HEIGHT [QUALITY]]

The page is Village walk. The village has people and animals: a woman by
the brick house, a man on the trail, a child who runs round the pond,
sheep, goats, cows, a horse, a pig, a dog, rabbits and deer. Each one
wanders and rests. The player is a man of six feet, seen from behind by a
third-person camera.

With `--play`, the program opens an X11 window, 1920 by 1080 pixels unless
given, and reads every gamepad on the machine and the keyboard. QUALITY is
`low`, `medium`, `high` or `ultra`, `low` unless given: see
`extensions.village.quality`. `low` keeps 24 frames a second on four
cores.

| Control | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick, or the d-pad | `W`, `A`, `S`, `D` |
| Look | Right stick | The arrows |
| Run | Hold the right trigger, the east button or the left stick | Hold Shift, or `R` |
| Jump | The south button | Space |
| Quit | The start button | Escape or `q` |

The game moves by the time each frame takes, so a slow frame moves the
player as far as many quick ones do. It prints the frames a second to the
standard error.

With a path, or no argument, the program needs no window and no pad. A
pad of the web backend plays a fixed script: walk, run, jump, look round
and stop, at the `medium` quality in a window of 480 by 270. The program
writes the frames as an animated PNG, and prints how long each step took,
as JSON.
"""

from controls.held_keys import HeldKeys
from controls.input import CTRL_C, ESCAPE, KEY_DOWN, KEY_UP, Key
from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.gamepad.gamepad import GAMEPAD_BUTTON_DOWN, Gamepad
from extensions.gamepad.hid import HidrawFile
from extensions.gamepad.hidapi import HidHub
from extensions.gamepad.ids import BUTTON_SOUTH, BUTTON_START
from extensions.gamepad.linux import (
    EvdevFile,
    EvdevHub,
    default_mapping_database,
)
from extensions.gamepad.web import WebGamepadState, WebHub
from extensions.village.character import MoveInput, no_input
from extensions.village.pad_input import (
    KEY_SPACE,
    combined,
    gamepad_input,
    keyboard_input,
)
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
from render.apng import encode
from render.framebuffer import Framebuffer
from render.jpeg import decode
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import MILLISECOND, SECOND, Duration
from window.x11 import X11Window

comptime DEFAULT_OUTPUT = "out/village_walk.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime PLAY_WIDTH = 1920
comptime PLAY_HEIGHT = 1080
comptime FPS = 8
"""The frames a second of the scripted walk."""
comptime SECONDS = Float32(6)
"""How long the scripted walk lasts."""
comptime QUIT = Key(113)
comptime POLL = Duration(1.0, MILLISECOND)
"""How long the play loop waits for input before it draws."""
comptime KEY_HOLD = Duration(10.0, SECOND)
"""How long a key counts as held with no repeat. An X11 window says when
each key goes up, so this only catches a key let go while the window was
not focused."""


def _script(mut state: WebGamepadState, t: Float32):
    """Set the scripted pad for the time `t`, in seconds, as a browser's
    standard layout reads it: axes 0 and 1 are the left stick, 2 and 3
    the right, button 0 is the south button and 7 the right trigger."""
    for index in range(len(state.axes)):
        state.axes[index] = 0
    for index in range(len(state.digital_buttons)):
        state.digital_buttons[index] = False
        state.analog_buttons[index] = 0
    if t < 1.5:
        # Walk toward the houses.
        state.axes[1] = -0.6
    elif t < 3.2:
        # Run, bearing left, and jump on the way.
        state.axes[1] = -1
        state.axes[0] = -0.35
        state.digital_buttons[7] = True
        state.analog_buttons[7] = 1
        if t >= 2.2 and t < 2.5:
            state.digital_buttons[0] = True
            state.analog_buttons[0] = 1
    elif t < 4.8:
        # Walk on, and look round to the right.
        state.axes[1] = -0.5
        state.axes[2] = 0.5
    # Then stand still, and let the camera settle.


def _scripted(destination: String) raises:
    """Play the scripted walk and write it as an animated PNG."""
    var clock = Clock()
    clock.start()
    var assets = Assets()
    var scene = Scene()
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var game = VillageGame(
        scene,
        assets,
        Renderer(64, 64),
        PlayParameters(game_quality(MEDIUM)),
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
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print(
        '{"build_ms": ',
        built,
        ', "frame_ms": ',
        drawing / Float32(count),
        ', "frames": ',
        count,
        ', "residents": ',
        len(game.residents.people) + len(game.residents.beasts),
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)


def _pad_input(
    hid: HidHub[HidrawFile], evdev: EvdevHub[EvdevFile]
) -> MoveInput:
    """Return the input of every gamepad, added."""
    var input = no_input()
    for index in range(len(hid.pads)):
        if hid.pads[index].pad:
            input = combined(input, gamepad_input(hid.pads[index].pad.value()))
    for index in range(len(evdev.pads)):
        input = combined(input, gamepad_input(evdev.pads[index].gamepad))
    return input


def _preset(name: String) raises -> QualityPreset:
    """Return the quality preset a name names."""
    if name == "low":
        return LOW
    if name == "medium":
        return MEDIUM
    if name == "high":
        return HIGH
    if name == "ultra":
        return ULTRA
    raise Error("A quality must be low, medium, high or ultra, not ", name)


def _play(width: Int, height: Int, preset: QualityPreset) raises:
    """Open a window and play until the player quits."""
    var assets = Assets()
    var scene = Scene()
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    print("Building the village...", file=stderr)
    var game = VillageGame(
        scene,
        assets,
        Renderer(64, 64),
        PlayParameters(game_quality(preset)),
        bed^,
        None,
        width,
        height,
    )
    var window = X11Window(width, height, "ThreeMojo village")
    var database = default_mapping_database()
    var hid = HidHub[HidrawFile]()
    var evdev = EvdevHub[EvdevFile]()
    var keys = HeldKeys(KEY_HOLD)
    var shift = False
    var clock = Clock()
    clock.start()
    var last = clock.elapsed()
    var running = True
    var frames = 0
    try:
        while running and not window.close_requested:
            var tapped = False
            for event in window.poll(POLL):
                if event.kind == KEY_DOWN:
                    if (
                        event.key == ESCAPE
                        or event.key == QUIT
                        or event.key == CTRL_C
                    ):
                        running = False
                    if event.key == KEY_SPACE:
                        tapped = True
                    keys.press(event.key)
                    shift = event.shift
                elif event.kind == KEY_UP:
                    _ = keys.release(event.key)
                    shift = event.shift
            _ = hid.detect(database)
            _ = evdev.detect(database, hid.claimed())
            for index in range(len(hid.pads)):
                for event in hid.pads[index].update():
                    if event.kind == GAMEPAD_BUTTON_DOWN:
                        if event.button == BUTTON_SOUTH:
                            tapped = True
                        elif event.button == BUTTON_START:
                            running = False
            for index in range(len(evdev.pads)):
                for event in evdev.pads[index].update():
                    if event.kind == GAMEPAD_BUTTON_DOWN:
                        if event.button == BUTTON_SOUTH:
                            tapped = True
                        elif event.button == BUTTON_START:
                            running = False
            var now = clock.elapsed()
            var delta = Duration(now.to(SECOND) - last.to(SECOND), SECOND)
            last = now
            _ = keys.advance(delta)
            var input = combined(
                _pad_input(hid, evdev), keyboard_input(keys, shift)
            )
            input.jump = input.jump or tapped
            _ = game.tick(scene, assets, input, delta)
            game.render(scene, assets)
            window.present(game.window)
            frames += 1
            if frames % 10 == 0:
                print(
                    "frames a second:",
                    Float32(1) / max(Float32(1.0e-3), delta.to(SECOND)),
                    file=stderr,
                )
    finally:
        window.close()


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    if len(words) > 1 and words[1] == "--play":
        var width = PLAY_WIDTH
        var height = PLAY_HEIGHT
        if len(words) > 3:
            width = Int(words[2])
            height = Int(words[3])
        var preset = _preset(words[4] if len(words) > 4 else "low")
        _play(width, height, preset)
        return
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]
    _scripted(destination)
