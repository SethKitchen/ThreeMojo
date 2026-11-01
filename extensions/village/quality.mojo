# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How finely the village game draws, so a slow machine can keep its
frame rate and a fast one can show everything.

Each costly part of a frame has its own setting in `GameQuality`, and
each can be turned up or down alone:

| Setting | Cheapest | Finest |
|---|---|---|
| `render_scale` | A third of the window, stretched to it | The window itself |
| `plants` | `FEWEST_PLANTS` | `ALL_PLANTS` |
| `grass_wind_every` | 0: still grass | 1: every blade every frame |
| `sky_step` | One sky sample every 3 pixels | Every pixel |
| `water_step` | One water sample every 8 pixels | Every pixel |
| `water_refresh_every` | The waves found every fourth frame | Every frame |
| `animal_coarseness` | Animals three times coarser | Each tier's own mesh |
| `shadows` | `NO_SHADOWS` | `FULL_SHADOWS`: every caster every frame |
| `shadow_size` | 64 texels | 8,192 texels |
| `smooth_edges` | False: stair steps on the edges | True: FXAA smooths them |
| `fight_reach` | Fighters past 12 meters posed every third frame | Every fighter every frame |

`game_quality` gives the four presets. `LOW` is for four cores, and
`ULTRA` draws the village as the still picture does.
"""

from core.ordinal import ordinal_valid
from extensions.vegetation.crown import CrownLevel
from extensions.vegetation.field import LodBand
from extensions.vegetation.checks import require_between, require_count_between
from extensions.village.village import VillageParameters
from extensions.water.resolution import SpectrumResolution
from renderers.game_renderer import (
    CACHED_SHADOWS,
    FULL_SHADOWS,
    ShadowMode,
)
from units.si import METER, Length


@fieldwise_init
struct QualityPreset(Equatable, ImplicitlyCopyable, Writable):
    """One of the four presets, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four presets there are.

        Returns:
            Whether the value names a preset.
        """
        return ordinal_valid(self.value, 3)


# For four cores: a third of the window, the fewest plants.
comptime LOW = QualityPreset(0)
# Half the window, fewer plants.
comptime MEDIUM = QualityPreset(1)
# Two thirds of the window, many plants.
comptime HIGH = QualityPreset(2)
# The window itself, every plant.
comptime ULTRA = QualityPreset(3)


@fieldwise_init
struct PlantDetail(Equatable, ImplicitlyCopyable, Writable):
    """How many leaves and blades the meadow grows near the camera, as a
    type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four details there are.

        Returns:
            Whether the value names a detail.
        """
        return ordinal_valid(self.value, 3)


# Cards for every leaf: 8 percent of each crown's leaves to 20 meters,
# fewer past that; sparse grass to 30 meters; coarse mountains.
comptime FEWEST_PLANTS = PlantDetail(0)
# A third of the leaves to 20 meters; grass to 40 meters.
comptime FEWER_PLANTS = PlantDetail(1)
# Most of the leaves to 30 meters; grass to 60 meters.
comptime MANY_PLANTS = PlantDetail(2)
# The still picture's meadow.
comptime ALL_PLANTS = PlantDetail(3)


@fieldwise_init
struct GameQuality(ImplicitlyCopyable):
    """How finely the village game draws each part of a frame."""

    # The share of the window's width and height the frame is drawn at,
    # from a quarter to one. The frame is stretched to the window.
    var render_scale: Float32
    # How many leaves and blades grow near the camera.
    var plants: PlantDetail
    # How often a cluster of grass is grown again for the wind: every
    # frame for 1, every `n`th frame for `n`, and never for 0.
    var grass_wind_every: Int
    # The pixels between two samples of the sky, from 1 to 32.
    var sky_step: Int
    # The pixels between two shaded samples of the pond's water, from 1 to
    # 64, and how many frames share one ocean surface, from 1 to 64.
    var water_step: Int
    var water_refresh_every: Int
    # How many times its tier's cell an animal's mesh's cell is, from 1 to
    # 8: a coarser animal has fewer triangles.
    var animal_coarseness: Float32
    # How the sun's shadows are drawn, and the still map's texels on a
    # side, from 64 to 8,192.
    var shadows: ShadowMode
    var shadow_size: Int
    # Whether the frame's edges are smoothed before it is stretched.
    var smooth_edges: Bool
    # How far from the player a fighter is posed every frame and leaves a
    # trail, in meters: see `extensions.village.battle`.
    var fight_reach: Float32

    def check(self) raises:
        """Refuse a quality that cannot be drawn.

        Raises:
            Error: If the render scale is not from a quarter to one, the
                plant detail is not one, the grass's wind is not from 0 to
                64 frames, the sky's step is not from 1 to 32 pixels, the
                water's step is not from 1 to 64 pixels, its surface is
                not found every 1 to 64 frames, the animals' coarseness
                is not from 1 to 8, the shadow mode is not one, the
                shadow map has not from 64 to 8,192 texels on a side, or
                the fight's reach is not from 5 to 10,000 meters.
        """
        require_between(
            self.render_scale,
            0.25,
            1,
            "A render scale must be from a quarter to one",
        )
        if not self.plants.is_valid():
            raise Error("A plant detail must be one of the four")
        require_count_between(
            self.grass_wind_every,
            0,
            64,
            "The grass's wind must come every 0 to 64 frames",
        )
        require_count_between(
            self.sky_step, 1, 32, "The sky's step must be from 1 to 32 pixels"
        )
        require_count_between(
            self.water_step,
            1,
            64,
            "The water's step must be from 1 to 64 pixels",
        )
        require_between(
            self.animal_coarseness,
            1,
            8,
            "An animal's coarseness must be from 1 to 8",
        )
        if not self.shadows.is_valid():
            raise Error("A shadow mode must be one of the four")
        require_count_between(
            self.shadow_size,
            64,
            8192,
            "A shadow map must have from 64 to 8,192 texels on a side",
        )
        require_count_between(
            self.water_refresh_every,
            1,
            64,
            "The water's surface must be found every 1 to 64 frames",
        )
        require_between(
            self.fight_reach,
            5,
            1.0e4,
            "A fight's reach must be from 5 to 10,000 meters",
        )

    def frame_size(self, width: Int, height: Int) raises -> Tuple[Int, Int]:
        """Return the size the frame is drawn at, for a window.

        Args:
            width: The window's width, in pixels.
            height: The window's height, in pixels.

        Returns:
            The width and the height times the render scale, rounded, and
            at least one pixel each.

        Raises:
            Error: If `check` refuses the quality, or a size is not
                positive.
        """
        self.check()
        if width <= 0 or height <= 0:
            raise Error("A window's size must be positive")
        return (
            max(1, Int(Float32(width) * self.render_scale + 0.5)),
            max(1, Int(Float32(height) * self.render_scale + 0.5)),
        )


def game_quality(preset: QualityPreset) raises -> GameQuality:
    """Return a preset's quality.

    Args:
        preset: The preset.

    Returns:
        `LOW`: a third of the window, the fewest plants, the grass's wind
        every fourth frame, a sky sample every 3 pixels, and a water
        sample every 8 pixels on a surface found every fourth frame,
        animals three times coarser, cached shadows on a map of 1,024
        texels, and fighters posed every frame within 12 meters. Every
        preset smooths the frame's edges.
        `MEDIUM`: half, fewer plants, every other frame, every 2 pixels,
        every 4 pixels, every other frame, twice as coarse, cached on
        2,048, within 20 meters. `HIGH`: two thirds, many plants, every
        frame, every 2 pixels, every 2 pixels, every frame, one and a half
        times as coarse, cached on 2,048, within 32 meters.
        `ULTRA`: the window, every plant, everything every frame and
        every pixel, full shadows on 4,096, and every fighter every
        frame.

    Raises:
        Error: If the preset is not one of the four.
    """
    if preset == LOW:
        return GameQuality(
            Float32(1) / 3,
            FEWEST_PLANTS,
            4,
            3,
            8,
            4,
            3,
            CACHED_SHADOWS,
            1024,
            True,
            12,
        )
    if preset == MEDIUM:
        return GameQuality(
            0.5, FEWER_PLANTS, 2, 2, 4, 2, 2, CACHED_SHADOWS, 2048, True, 20
        )
    if preset == HIGH:
        return GameQuality(
            Float32(2) / 3,
            MANY_PLANTS,
            1,
            2,
            2,
            1,
            1.5,
            CACHED_SHADOWS,
            2048,
            True,
            32,
        )
    if preset == ULTRA:
        return GameQuality(
            1, ALL_PLANTS, 1, 1, 1, 1, 1, FULL_SHADOWS, 4096, True, 1.0e4
        )
    raise Error("A quality preset must be one of the four")


def planted(
    var parameters: VillageParameters, plants: PlantDetail
) raises -> VillageParameters:
    """Return a village whose meadow grows as many plants as a detail says.

    `ALL_PLANTS` leaves the village as it is. The others keep fewer leaves
    and blades near the camera, scatter less on the ground, and draw the
    ground, the mountains and the canyon's wall more coarsely. They also
    draw the pond's water and the sky at smaller resolutions.

    Args:
        parameters: The village.
        plants: The detail.

    Returns:
        The village, with its meadow changed.

    Raises:
        Error: If the detail is not one of the four.
    """
    if not plants.is_valid():
        raise Error("A plant detail must be one of the four")
    if plants == ALL_PLANTS:
        return parameters^
    ref meadow = parameters.meadow
    if plants == FEWEST_PLANTS:
        meadow.crown_levels = [
            CrownLevel(Length(20.0, METER), 0.08, True),
            CrownLevel(Length(60.0, METER), 0.03, True),
            CrownLevel(Length(1.0e5, METER), 0.012, True),
        ]
        meadow.field.density = 120
        meadow.field.bands = [
            LodBand(Length(5.0, METER), 0.5, 2),
            LodBand(Length(14.0, METER), 0.15, 1),
            LodBand(Length(30.0, METER), 0.04, 1),
        ]
        meadow.litter = 8000
        meadow.ground_cells = 96
        meadow.ridge_columns = 240
        meadow.cliff_columns = 320
        meadow.cliff_rows = 24
    elif plants == FEWER_PLANTS:
        meadow.crown_levels = [
            CrownLevel(Length(20.0, METER), 0.35, False),
            CrownLevel(Length(80.0, METER), 0.1, True),
            CrownLevel(Length(1.0e5, METER), 0.03, True),
        ]
        meadow.field.density = 200
        meadow.field.bands = [
            LodBand(Length(6.0, METER), 0.6, 3),
            LodBand(Length(16.0, METER), 0.2, 2),
            LodBand(Length(40.0, METER), 0.05, 1),
        ]
        meadow.litter = 20000
        meadow.ground_cells = 128
        meadow.ridge_columns = 360
        meadow.cliff_columns = 640
        meadow.cliff_rows = 48
    else:
        meadow.crown_levels = [
            CrownLevel(Length(30.0, METER), 0.6, False),
            CrownLevel(Length(110.0, METER), 0.25, True),
            CrownLevel(Length(1.0e5, METER), 0.05, True),
        ]
        meadow.field.density = 400
        meadow.field.bands = [
            LodBand(Length(7.0, METER), 0.8, 3),
            LodBand(Length(18.0, METER), 0.3, 2),
            LodBand(Length(60.0, METER), 0.08, 1),
        ]
        meadow.litter = 80000
        meadow.ground_cells = 256
        meadow.ridge_columns = 480
        meadow.cliff_columns = 1200
        meadow.cliff_rows = 72
    meadow.sky_size = 256
    parameters.ocean = SpectrumResolution(64)
    parameters.glare = SpectrumResolution(64)
    parameters.caustic_resolution = 128
    return parameters^
