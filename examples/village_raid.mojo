# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fight the Stone Warden of the village with a party, by a scripted
gamepad that reads the fight.

    mojo run -I . examples/village_raid.mojo [path.png] [seconds]

The page is Village raid. The player stands twelve meters before the
warden's ring of stones, with its four raiders behind them. The raiders
join the player's party. The script locks on to the warden, closes in,
and makes the sword's combos. When a zone that winds up holds the player,
it dodges out of it before it strikes. When a rockfall marks a member, it
runs to them, so they share the boulder. The fight starts with the
warden's poise worn low, so it staggers soon. Then the script calls a
linked strike, and the raiders strike with it. The raiders take their spots:
the tank before the warden, the striker behind it, the archer off its
flank and the healer behind the player.

The program needs no window and no pad. A pad of the web backend plays
the script at the `medium` quality in a window of 480 by 270. It writes
the frames as an animated PNG, and prints how the fight went as JSON. The
optional second argument is how long the fight lasts, in seconds; the
default is 14.
"""

from controls.third_person_controls import yaw_of
from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.gamepad.web import WebGamepadState, WebHub
from extensions.village.boss import inside
from extensions.village.pad_input import gamepad_input
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import MEDIUM, game_quality
from extensions.water.pebbles import pebble_bed
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Framebuffer
from render.jpeg import decode
from renderers.renderer import Renderer
from std.math import sqrt
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import MILLISECOND, SECOND, Duration

comptime DEFAULT_OUTPUT = "out/village_raid.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime FPS = 8
"""The frames a second of the scripted fight."""
comptime DEFAULT_SECONDS = Float32(14)
"""How long the scripted fight lasts, unless the command line says."""
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


def _flat(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def _pilot(mut state: WebGamepadState, game: VillageGame, frame: Int) raises:
    """Set the pad for a frame from what the fight shows: lock on, close
    in, make combos, dodge out of zones, and gather for a rockfall."""
    for index in range(len(state.axes)):
        state.axes[index] = 0
    for index in range(len(state.digital_buttons)):
        state.digital_buttons[index] = False
        state.analog_buttons[index] = 0
    ref battle = game.battle
    if len(battle.wardens) == 0:
        return
    ref warden = battle.wardens[0]
    ref feet = game.player.position
    if frame == 2:
        _hold(state, RIGHT_STICK)
        return
    if warden.boss.defeated():
        return
    # Call a linked strike on the staggered warden.
    if warden.boss.link_ready() and frame % 2 == 0:
        if _flat(feet, warden.character.position) < 4:
            _hold(state, NORTH)
            return
    # Out of a zone that winds up: lean away, and dodge as it closes.
    if warden.boss.busy() and warden.boss.warning() > 0:
        var zone = warden.boss.zone
        if inside(zone, feet, 0.6):
            var away = feet - zone.at
            if _flat(feet, zone.at) < 0.3:
                away = feet - warden.character.position
            away.y = 0
            away = away / max(away.length(), Float32(1.0e-3))
            # The stick is read in the camera's frame; the lock keeps the
            # camera behind the player, looking at the warden.
            var ahead = warden.character.position - feet
            ahead.y = 0
            ahead = ahead / max(ahead.length(), Float32(1.0e-3))
            var right = Vector3(-ahead.z, 0, ahead.x)
            state.axes[1] = Float64(-(away.x * ahead.x + away.z * ahead.z))
            state.axes[0] = Float64(away.x * right.x + away.z * right.z)
            if warden.boss.warning() > 0.7:
                _hold(state, EAST)
            return
    # Gather on a member that a rockfall marks.
    if warden.boss.marked > 0:
        var there = battle.members[warden.boss.marked - 1].character.position
        if _flat(feet, there) > 1.5:
            var way = there - feet
            var ahead = warden.character.position - feet
            ahead.y = 0
            ahead = ahead / max(ahead.length(), Float32(1.0e-3))
            var right = Vector3(-ahead.z, 0, ahead.x)
            way = way / max(way.length(), Float32(1.0e-3))
            state.axes[1] = Float64(-(way.x * ahead.x + way.z * ahead.z))
            state.axes[0] = Float64(way.x * right.x + way.z * right.z)
            return
    var gap = _flat(feet, warden.character.position)
    if gap > 3.4:
        state.axes[1] = -1
        return
    # A combo of light, light and heavy, a press every three frames; a
    # whirlwind now and then.
    var beat = frame % 12
    if beat == 0 or beat == 3:
        _hold(state, RIGHT_SHOULDER)
    elif beat == 6:
        _hold(state, NORTH)
    elif beat == 10 and frame % 48 == 10:
        _hold(state, LEFT_TRIGGER)
        _hold(state, NORTH)


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]
    var seconds = DEFAULT_SECONDS
    if len(words) > 2:
        seconds = Float32(Float64(words[2]))
    var clock = Clock()
    clock.start()
    var assets = Assets()
    var scene = Scene()
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var parameters = PlayParameters(game_quality(MEDIUM))
    ref raid = parameters.battle.raids[0]
    # Twelve meters before the warden, looking at it.
    parameters.start_x = raid.x
    parameters.start_z = raid.z - 12
    parameters.heading = yaw_of(Vector3(0, 0, 1))
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
    # The party has worn the warden's poise low.
    if len(game.battle.wardens) > 0:
        game.battle.wardens[0].boss.poise = 160
    var built = clock.elapsed().to(MILLISECOND)
    var hub = WebHub()
    var state = WebGamepadState(0, "Xbox Wireless Controller", 4, 17)
    _ = hub.connect(state)
    var frames = List[Framebuffer]()
    var count = Int(seconds * FPS)
    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    var drawing = Float32(0)
    var notes = List[String]()
    for frame in range(count):
        _pilot(state, game, frame)
        state.timestamp = Float64(frame + 1) * 1000.0 / Float64(FPS)
        _ = hub.update(state)
        var input = gamepad_input(hub.pads[0].gamepad)
        var began = clock.elapsed().to(MILLISECOND)
        var before = game.note
        _ = game.tick(scene, assets, input, step)
        if game.note != before and game.note.byte_length() > 0:
            notes.append(game.note)
        game.render(scene, assets)
        frames.append(
            Framebuffer(game.width, game.height, game.window.pixels.copy())
        )
        drawing += clock.elapsed().to(MILLISECOND) - began
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    var boss_share = Float32(0)
    var joined = 0
    var standing = 0
    if len(game.battle.wardens) > 0:
        ref boss = game.battle.wardens[0].boss
        boss_share = boss.health / boss.most
    for k in range(len(game.battle.members)):
        ref member = game.battle.members[k]
        if member.joined:
            joined += 1
        if member.down < 0:
            standing += 1
    var said = String()
    for k in range(len(notes)):
        if k > 0:
            said += ", "
        said += '"' + notes[k] + '"'
    print(
        '{"build_ms": ',
        built,
        ', "frame_ms": ',
        drawing / Float32(count),
        ', "frames": ',
        count,
        ', "wardens": ',
        len(game.battle.wardens),
        ', "warden_health": ',
        boss_share,
        ', "joined": ',
        joined,
        ', "standing": ',
        standing,
        ', "player_health": ',
        game.battle.fighter.health,
        ', "notes": [',
        said,
        "]}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
