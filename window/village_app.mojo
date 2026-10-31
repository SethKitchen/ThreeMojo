# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village game that the C ABI's village library keeps: the player, the
residents and the third-person camera, played with a keyboard.

`window.capi_village` exports it under the C names. This module holds the
state and the rules, and exports nothing. The game is the one that
`examples/village_walk.mojo --play` opens in an X11 window. Here a host
owns the window, the loop and the clock instead. A macOS host needs no
XQuartz.

The host gives the app key events and the time since the last step. The
keys are those of the table in `extensions.village.pad_input`. The host
reports Shift as the key `KEY_SHIFT`, because a key event of the C ABI has
no modifiers. The number keys set the weather, and `5` moves the day on
three hours, as the X11 loop does. A host gives no gamepad: a pad needs a
host that reads it, and the macOS host does not.

A host with a GPU can draw the frame itself. The app then prepares the frame
on the CPU, with `prepare_gpu`, and describes it in three arrays, `frame`.
The host draws it, writes the colors and the depths into the image that the
arrays name, and calls `finish_gpu`, which adds the water, the weather and
the heads-up display. The environment variable `THREEMOJO_GPU` set to `1`
makes a game for a GPU: it draws at the window's size.

The weather turns by itself, and the day passes in twenty minutes from two
in the afternoon, as in the X11 loop.
"""

from controls.held_keys import HeldKeys
from controls.input import Key
from core.assets import Assets
from core.scene import Scene
from extensions.village.day import DayCycle
from extensions.village.pad_input import KEY_SPACE, keyboard_input
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import (
    HIGH,
    LOW,
    MEDIUM,
    QualityPreset,
    ULTRA,
    game_quality,
)
from extensions.village.weather import (
    CLEAR,
    FOG,
    OVERCAST,
    RAIN,
    WeatherKind,
    weather_look,
)
from extensions.water.pebbles import PebbleBed, pebble_bed
from render.jpeg import decode
from renderers.game_gpu import (
    GpuFrame,
    INT_DEPTH,
    POINTER_COLOR,
    POINTER_DEPTH,
)
from renderers.renderer import Renderer
from std.memory import Layout
from std.os import getenv
from std.pathlib import Path
from units.si import SECOND, Duration
from window.capi_abi import KEY_DOWN, KEY_SHIFT, KEY_UP

comptime PEBBLES = "assets/pebbles.jpg"
"""The pebble photograph, relative to the folder the program runs in."""
comptime QUALITY_VARIABLE = "THREEMOJO_QUALITY"
"""The environment variable that names the quality: `low`, `medium`, `high`
or `ultra`. `threemojo_host --quality` sets it."""
comptime DEFAULT_QUALITY = "medium"
"""The quality when nothing names one."""
comptime GPU_VARIABLE = "THREEMOJO_GPU"
"""The environment variable that, set to `1`, makes a game for a GPU to draw.
`threemojo_host --gpu` sets it."""
comptime HOUR_VARIABLE = "THREEMOJO_HOUR"
"""The environment variable that sets the hour the game begins at, from 0 to
less than 24. `threemojo_host --hour` sets it."""
comptime WEATHER_VARIABLE = "THREEMOJO_WEATHER"
"""The environment variable that sets the weather the game begins in: `clear`,
`overcast`, `rain` or `fog`. `threemojo_host --weather` sets it."""
comptime DAY_RATE = Float32(24.0 / 1200.0)
"""The hours a second that pass in play: a day in twenty minutes."""
comptime START_HOUR = 14
"""The hour the game begins at: two in the afternoon."""
comptime KEY_ONE = Key(49)
"""The `1` key: the number keys from it set the weather."""
comptime WEATHERS = 4
"""How many weathers the number keys set: clear, overcast, rain and fog."""
comptime TIME_KEY = 4
"""The number key, counted from `1` as zero, that moves the day on."""
comptime TIME_HOURS = 3
"""The hours that the time key moves the day on."""
comptime KEY_HOLD = Duration(10.0, SECOND)
"""How long a key counts as held with no repeat. The host says when each key
goes up, so this only catches a key let go while the window was not
focused."""
comptime LONGEST_MICROSECONDS = 100000
"""The most time that one step counts. A host that was stopped for a while
does not move the player a long way at once."""


def quality_named(name: String) raises -> QualityPreset:
    """Return the quality preset that a name names.

    Args:
        name: `low`, `medium`, `high` or `ultra`.

    Returns:
        The preset.

    Raises:
        Error: If the name is none of the four.
    """
    if name == "low":
        return LOW
    if name == "medium":
        return MEDIUM
    if name == "high":
        return HIGH
    if name == "ultra":
        return ULTRA
    raise Error("A quality must be low, medium, high or ultra, not ", name)


def play_parameters(
    preset: QualityPreset, gpu: Bool = False
) raises -> PlayParameters:
    """Return the game as `examples/village_walk.mojo --play` plays it: the
    default village at a quality, with weather that turns by itself and a day
    that passes in twenty minutes from two in the afternoon.

    Args:
        preset: The quality preset.
        gpu: Whether a GPU draws the game. The frame is then drawn at the
            window's size, whatever the preset's render scale is, and the
            steps of the sky and of the water grow to keep their spacing.
            The water's step is at least two.

    Returns:
        The game's parameters.

    Raises:
        Error: If the preset is not one of the four.
    """
    var quality = game_quality(preset)
    if gpu:
        # A preset draws a share of the window and stretches it. A GPU draws
        # the window itself, so the samples of the sky and of the water, which
        # are counted in pixels, keep their spacing in the picture by growing
        # as the frame does.
        var scale = quality.render_scale
        quality.render_scale = 1
        quality.sky_step = min(
            32, max(1, Int(Float32(quality.sky_step) / scale + 0.5))
        )
        # The water on a GPU shades a grid of samples, so its step is two
        # pixels or more.
        quality.water_step = min(
            64, max(2, Int(Float32(quality.water_step) / scale + 0.5))
        )
    var parameters = PlayParameters(quality)
    parameters.weather_cycle = True
    parameters.day = DayCycle(START_HOUR, DAY_RATE)
    return parameters^


def read_bed(path: String = PEBBLES) raises -> PebbleBed:
    """Read the pebble photograph, or return plain sand if it cannot be read.

    Args:
        path: The JPEG file.

    Returns:
        The photograph's bed, or a bed of one sand-colored texel.

    Raises:
        Error: Never in practice. The sand texel is one valid linear color.
    """
    try:
        return pebble_bed(decode(Path(path).read_bytes()))
    except:
        return PebbleBed(1, 1, [Float32(0.34), Float32(0.27), Float32(0.17)])


def quality_from_environment() raises -> QualityPreset:
    """Return the quality that the environment names.

    Returns:
        The preset that `QUALITY_VARIABLE` names, or `DEFAULT_QUALITY`'s if
        it is not set.

    Raises:
        Error: If the variable is set to none of the four names.
    """
    return quality_named(getenv(QUALITY_VARIABLE, DEFAULT_QUALITY))


def weather_named(name: String) raises -> WeatherKind:
    """Return the weather that a name names.

    Args:
        name: `clear`, `overcast`, `rain` or `fog`.

    Returns:
        The kind of weather.

    Raises:
        Error: If the name is none of the four.
    """
    if name == "clear":
        return CLEAR
    if name == "overcast":
        return OVERCAST
    if name == "rain":
        return RAIN
    if name == "fog":
        return FOG
    raise Error("A weather must be clear, overcast, rain or fog, not ", name)


def weather_from_environment() raises -> Int:
    """Return the weather that the environment sets for the game's start.

    Returns:
        The `WeatherKind` value that `WEATHER_VARIABLE` names, or -1 if it is
        not set.

    Raises:
        Error: If the variable is set to none of the four names.
    """
    var name = getenv(WEATHER_VARIABLE, "")
    if name == "":
        return -1
    return weather_named(name).value


def hour_from_environment() raises -> Float32:
    """Return the hour that the environment sets for the game's start.

    Returns:
        The hour that `HOUR_VARIABLE` holds, from 0 to less than 24, or -1 if
        it is not set.

    Raises:
        Error: If the variable is not a number from 0 to less than 24.
    """
    var text = getenv(HOUR_VARIABLE, "")
    if text == "":
        return -1
    var hour = Float32(atof(text))
    if not (hour >= 0 and hour < 24):
        raise Error("An hour must be from 0 to less than 24, not ", text)
    return hour


def gpu_from_environment() -> Bool:
    """Return whether the environment asks for a game that a GPU draws.

    Returns:
        True if `GPU_VARIABLE` is `1`.
    """
    return getenv(GPU_VARIABLE, "") == "1"


struct VillageApp(Movable):
    """The state that a host's handle points at."""

    var width: Int
    """The window's width, in pixels."""
    var height: Int
    """The window's height, in pixels."""
    var scene: Scene
    """The scene that the game stands in."""
    var assets: Assets
    """The stores of the scene."""
    var game: VillageGame
    """The village, its residents and the player."""
    var keys: HeldKeys
    """The keys held now."""
    var shift: Bool
    """Whether Shift is held."""
    var tapped: Bool
    """Whether the space bar went down since the last step: a tap shorter
    than a step still jumps."""
    var gpu: Bool
    """Whether a GPU draws the game: the host asks for `prepare_gpu`."""
    var passes: Bool
    """Whether the host's GPU also draws the weather, the night, the water
    and the smoothing of edges: see `VillageGame.prepare_gpu`."""
    var frame: GpuFrame
    """The frame that `prepare_gpu` last prepared, for the GPU."""

    def __init__(
        out self,
        width: Int,
        height: Int,
        parameters: PlayParameters,
        var bed: PebbleBed,
        gpu: Bool = False,
    ) raises:
        """Build the village and the game in it. No frame is drawn yet.

        Args:
            width: The window's width, in pixels.
            height: The window's height, in pixels.
            parameters: What the game holds.
            bed: The pebble photograph that the pond's water shows through.
            gpu: Whether a GPU draws the game. Its parameters must then have
                a render scale of one, as `play_parameters` makes them.

        Raises:
            Error: If a side is not positive, or the game cannot be built.
        """
        if width < 1 or height < 1:
            raise Error(
                "A village window must have positive sides, got ",
                width,
                " by ",
                height,
            )
        self.width = width
        self.height = height
        var scene = Scene()
        var assets = Assets()
        self.game = VillageGame(
            scene,
            assets,
            Renderer(64, 64),
            parameters,
            bed^,
            None,
            width,
            height,
        )
        self.scene = scene^
        self.assets = assets^
        self.keys = HeldKeys(KEY_HOLD)
        self.shift = False
        self.tapped = False
        self.gpu = gpu
        self.passes = False
        self.frame = GpuFrame()

    def handle(mut self, kind: Int, detail: Int) raises:
        """Take one input event.

        A key press holds the key, and a release lets it go. The space bar
        also counts as a tap, so that a press shorter than a step still
        jumps. `1` to `4` set the weather and `5` moves the day on three
        hours. These act once for a key held down: a repeat of the press does
        nothing more. Shift is `KEY_SHIFT`. A pointer or a wheel event is
        dropped.

        Args:
            kind: The event kind, as `window.capi_abi` numbers it.
            detail: The key code of a key event.

        Raises:
            Error: If a key event's code is not a key.
        """
        if kind != KEY_DOWN and kind != KEY_UP:
            return
        var down = kind == KEY_DOWN
        if detail == KEY_SHIFT:
            self.shift = down
            return
        var key = Key(detail)
        if not key.is_valid():
            raise Error("A key code must be a key, got ", detail)
        if not down:
            _ = self.keys.release(key)
            return
        # A held key repeats. Only the first press acts: the day must not
        # move on again and again while the time key is held.
        if not self.keys.is_held(key):
            self._act(key)
        self.keys.press(key)

    def _act(mut self, key: Key) raises:
        """Do what a key does at the moment it goes down: the space bar is a
        tap, a number key from `1` sets the weather, and `5` moves the day
        on.

        Args:
            key: The key that went down.

        Raises:
            Error: Never in practice. A weather number from 0 to 3 is a
                weather.
        """
        if key == KEY_SPACE:
            self.tapped = True
        var number = key.value - KEY_ONE.value
        if number >= 0 and number < WEATHERS:
            self.game.weather.set(WeatherKind(number))
        if number == TIME_KEY:
            self.game.day.hour = (self.game.day.hour + TIME_HOURS) % 24

    def advance(mut self, microseconds: Int):
        """Move the game on by a time delta.

        Time that is negative is ignored. Time over `LONGEST_MICROSECONDS`
        counts as that. A step that the game refuses leaves the game as it
        was.

        Args:
            microseconds: The time since the last step, in microseconds.
        """
        if microseconds < 0:
            return
        var seconds = Float32(min(microseconds, LONGEST_MICROSECONDS)) / 1.0e6
        var delta = Duration(seconds, SECOND)
        try:
            _ = self.keys.advance(delta)
            var input = keyboard_input(self.keys, self.shift)
            input.jump = input.jump or self.tapped
            self.tapped = False
            _ = self.game.tick(self.scene, self.assets, input, delta)
        except:
            pass

    def draw(mut self):
        """Draw the frame that the last step prepared into the game's
        window. A frame that cannot be drawn leaves the last one that
        could."""
        try:
            self.game.render(self.scene, self.assets)
        except:
            pass

    def start_at(mut self, hour: Float32, weather: Int) raises:
        """Begin the game at an hour, in a weather, instead of the afternoon's
        clear sky.

        Args:
            hour: The hour, from 0 to less than 24, or -1 to keep the
                game's own.
            weather: The weather's `WeatherKind` value, or -1 to keep the
                game's own. The sky has that look at once, with no ease.

        Raises:
            Error: If the hour is not from 0 to less than 24, or the weather
                is not a kind. The game is then as it was.
        """
        if hour >= 24:
            raise Error("An hour must be from 0 to less than 24, not ", hour)
        var kind = WeatherKind(weather)
        if weather >= 0 and not kind.is_valid():
            raise Error("A weather must be a kind, not ", weather)
        if hour >= 0:
            self.game.day.hour = hour
        if weather >= 0:
            self.game.weather.set(kind)
            self.game.weather.look = weather_look(kind)

    def take_passes(mut self, on: Bool) -> Bool:
        """Let the host's GPU draw the weather, the night, the water and the
        smoothing of edges after the triangles, or take them back.

        Args:
            on: Whether the GPU draws them from the next `prepare_gpu`.

        Returns:
            True if the app is one for a GPU, and the host has them as asked.
            False otherwise: the CPU draws them.
        """
        if not self.gpu:
            return False
        self.passes = on
        return True

    def prepare_gpu(mut self) -> Bool:
        """Prepare the frame that the last step left, for a GPU to draw.

        The arrays of `frame` then describe it. The GPU writes the colors and
        the depths into the image that `POINTER_COLOR` and `POINTER_DEPTH`
        name, and `finish_gpu` ends the frame. When the host has taken the
        passes (`passes`), the GPU draws the weather, the night, the water and
        the smoothing too, and `INT_DEPTH` is 0: the depths are not needed.

        Returns:
            True if the frame is prepared. False if the app is not one for a
            GPU, or the frame cannot be drawn: the host then keeps the last
            frame.
        """
        if not self.gpu:
            return False
        try:
            self.game.prepare_gpu(self.scene, self.assets, self.passes)
            self.frame = self.game.fast.gpu_frame()
            self.frame.ints[INT_DEPTH] = 1
            if self.passes:
                self.game.gpu_post.describe(
                    self.frame,
                    self.game.gpu_image.width,
                    self.game.gpu_image.height,
                )
            self.frame.pointers[POINTER_COLOR] = Int64(
                Int(self.game.gpu_image.pixels.unsafe_ptr())
            )
            self.frame.pointers[POINTER_DEPTH] = Int64(
                Int(self.game.gpu_image.depth.unsafe_ptr())
            )
            return True
        except:
            return False

    def finish_gpu(mut self):
        """End the frame that a GPU drew, adding what the CPU draws over it.
        A frame that cannot be finished leaves the last one that could."""
        try:
            self.game.finish_gpu(self.scene, self.assets)
        except:
            pass


def new_app(
    width: Int,
    height: Int,
    parameters: PlayParameters,
    var bed: PebbleBed,
    gpu: Bool = False,
    hour: Float32 = -1,
    weather: Int = -1,
) raises -> Pointer[VillageApp, MutUntrackedOrigin]:
    """Build the game and leave it on the heap, for a host's handle.

    Args:
        width: The window's width, in pixels.
        height: The window's height, in pixels.
        parameters: What the game holds.
        bed: The pebble photograph that the pond's water shows through.
        gpu: Whether a GPU draws the game.
        hour: The hour to begin at, or -1 for the game's own.
        weather: The weather to begin in, or -1 for the game's own.

    Returns:
        The app. The host frees it with `tm_destroy`.

    Raises:
        Error: If a side is not positive, the game cannot be built, or the
            hour or the weather is not valid.
    """
    var app = VillageApp(width, height, parameters, bed^, gpu)
    app.start_at(hour, weather)
    var slot = alloc(Layout[VillageApp](count=1)).unsafe_leak()
    slot.unsafe_write(app^)
    return slot
