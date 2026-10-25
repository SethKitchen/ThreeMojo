# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village game: the lighter village, its residents, and a player who
walks and jumps in front of the third-person camera."""

from core.assets import Assets
from core.scene import Scene
from extensions.animals.registry import RABBIT
from extensions.building.material import brick
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.field import LodBand
from extensions.vegetation.ground import Ground, Pond
from extensions.vegetation.meadow import Planting
from extensions.village.character import (
    AIRBORNE,
    STANDING,
    MoveInput,
    no_input,
)
from extensions.village.house import HouseParameters
from extensions.village.play import (
    FOCUS_HEIGHT,
    PlayParameters,
    TRUNK,
    VillageGame,
    default_residents,
    play_village,
    tree_obstacles,
)
from extensions.village.residents import Herd, ResidentsParameters, Villager
from extensions.village.village import HousePlacement, VillageParameters
from extensions.water.pebbles import pebble_bed
from extensions.water.resolution import SpectrumResolution
from render.png import DecodedImage
from render.srgb import SRGB
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import (
    DEGREE,
    INCH,
    METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
)


def _village() raises -> VillageParameters:
    """Return a village small enough to build in a test: a field 16 meters
    across, a pond, one tree, one small house, and small water."""
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


def _game_parameters() raises -> PlayParameters:
    """Return a game of the small village, one rabbit, nobody else, and a
    small player."""
    var p = PlayParameters()
    p.village = _village()
    var residents = ResidentsParameters()
    residents.triangles = 500
    residents.detail = 8
    residents.phases = 2
    residents.herds = [Herd(RABBIT, 1, -4, 4, 1, 3)]
    p.residents = residents^
    p.player = HumanoidSpec(Length(60.0, INCH), FEMALE)
    p.start_x = -4
    p.start_z = -2
    return p^


def _bed() raises -> DecodedImage:
    """Return a gray pebble photograph 4 pixels on a side."""
    return DecodedImage(4, 4, List[UInt8](length=64, fill=128), SRGB)


def test_the_game_village_is_lighter_and_lived_in() raises:
    var light = play_village()
    light.check()
    assert_equal(len(light.meadow.crown_levels), 3)
    assert_equal(light.meadow.ground_cells, 128)
    var people = default_residents()
    people.check()
    assert_equal(len(people.villagers), 3)
    assert_equal(len(people.herds), 8)
    var game = PlayParameters()
    assert_almost_equal(game.start_z, 26, atol=1e-6)
    var trunks = tree_obstacles(_village())
    assert_equal(len(trunks), 1)
    assert_almost_equal(trunks[0].radius, TRUNK * 0.5, atol=1e-6)
    var bare = _village()
    bare.meadow.plantings = []
    assert_equal(len(tree_obstacles(bare)), 0)


def test_a_player_walks_jumps_and_is_followed() raises:
    var renderer = Renderer(32, 18)
    var assets = Assets()
    var scene = Scene()
    var game = VillageGame(
        scene, assets, renderer, _game_parameters(), pebble_bed(_bed()), None
    )
    assert_equal(len(game.residents.beasts), 1)
    var start = game.player.position
    var step = Duration(0.1, SECOND)
    for _ in range(10):
        _ = game.tick(scene, assets, MoveInput(1, 0, 0, 0, False, False), step)
    assert_true(game.player.position.z < start.z - 1)
    # The camera stands behind the player, and looks at a point above the
    # feet.
    assert_true(game.camera.position.z > game.player.position.z)
    assert_almost_equal(
        game.view.focus.y,
        game.player.position.y + FOCUS_HEIGHT,
        atol=0.3,
    )
    _ = game.tick(scene, assets, MoveInput(0, 0, 0, 0, False, True), step)
    assert_true(game.player.stance == AIRBORNE)
    # The look stick turns the camera, and the camera does not trail
    # while it is held.
    var yaw = game.view.yaw.to(DEGREE)
    _ = game.tick(scene, assets, MoveInput(0, 0, 1, 0, False, False), step)
    assert_true(game.view.yaw.to(DEGREE) < yaw - 5)
    for _ in range(20):
        _ = game.tick(scene, assets, no_input(), step)
    assert_true(game.player.stance == STANDING)
    assert_almost_equal(game.clock, 3.2, atol=1e-4)
    var image = game.render(renderer, scene, assets)
    assert_equal(image.width, 32)
    assert_equal(image.height, 18)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
