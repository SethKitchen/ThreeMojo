# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A village game small enough to build inside a test's five seconds.

The village is a field 16 meters across with a pond, one tree and one small
house. It has one rabbit, no other resident, and no fight. The player is a
small woman. Water, textures and plants are the smallest that the game
accepts.
"""

from extensions.building.material import brick
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.animals.registry import RABBIT
from extensions.vegetation.field import LodBand
from extensions.vegetation.ground import Ground, Pond
from extensions.vegetation.meadow import Planting
from extensions.village.foes import Bandit, Den, Post
from extensions.village.gathering import HERBS, Spot
from extensions.village.house import HouseParameters
from extensions.village.play import PlayParameters
from extensions.village.quality import LOW, game_quality
from extensions.village.residents import Herd, ResidentsParameters
from extensions.village.village import HousePlacement, VillageParameters
from extensions.water.resolution import SpectrumResolution
from render.png import DecodedImage
from render.srgb import SRGB
from units.si import DEGREE, INCH, METER, RADIAN, Angle, Length


def tiny_village() raises -> VillageParameters:
    """Return a village small enough to build in a test.

    Returns:
        A field 16 meters across, a pond, one tree, one small house, and
        small water.

    Raises:
        Error: If the village's parameters are refused.
    """
    var p = VillageParameters()
    p.meadow.field.span = Length(16.0, METER)
    p.meadow.field.cluster_size = Length(4.0, METER)
    p.meadow.field.density = 10
    p.meadow.field.bands = [LodBand(Length(60.0, METER), 0.001, 1)]
    p.meadow.ground = Ground(
        seed=11,
        pond=Pond(
            Length(0.0, METER),
            Length(4.0, METER),
            Length(3.0, METER),
            Length(1.0, METER),
        ),
    )
    p.meadow.crowns = [p.meadow.crowns[6].copy()]
    p.meadow.crowns[0].limbs.points = 100
    p.meadow.crown_levels = [p.meadow.crown_levels[0]]
    p.meadow.plantings = [Planting(0, 6, 6, 0.5)]
    p.meadow.ground_span = Length(30.0, METER)
    p.meadow.ground_cells = 30
    p.meadow.mountain_radius = Length(100.0, METER)
    p.meadow.sky_size = 8
    p.meadow.rocks = 0
    p.meadow.litter = 1000
    p.meadow.litter_reach = Length(8.0, METER)
    p.houses = [
        HousePlacement(
            HouseParameters(
                "test house",
                Length(5.0, METER),
                Length(4.0, METER),
                1,
                brick(),
            ),
            5,
            -6,
            Angle(10.0, DEGREE),
        )
    ]
    p.ocean = SpectrumResolution(16)
    p.caustic_grid = 8
    p.caustic_resolution = 16
    p.glare = SpectrumResolution(16)
    return p^


def tiny_game() raises -> PlayParameters:
    """Return a game of the tiny village.

    Returns:
        The game's parameters: one rabbit, nobody else, a small player and
        nobody to fight.

    Raises:
        Error: If the game's parameters are refused.
    """
    var p = PlayParameters(game_quality(LOW))
    p.village = tiny_village()
    var residents = ResidentsParameters()
    residents.triangles = 500
    residents.detail = 8
    residents.phases = 2
    residents.herds = [Herd(RABBIT, 1, -4, 4, 1, 3)]
    p.residents = residents^
    p.player = HumanoidSpec(Length(60.0, INCH), FEMALE)
    p.start_x = -4
    p.start_z = -2
    p.gathering.spots = [Spot(HERBS, -4, -3, Angle(0.0, RADIAN))]
    p.battle.bandits = List[Bandit]()
    p.battle.dens = List[Den]()
    p.battle.posts = List[Post]()
    p.battle.allies = List[Bandit]()
    return p^


def gray_photograph() raises -> DecodedImage:
    """Return a gray pebble photograph 4 pixels on a side.

    Returns:
        The photograph.

    Raises:
        Error: If the image's size does not fit its bytes.
    """
    return DecodedImage(4, 4, List[UInt8](length=64, fill=128), SRGB)
