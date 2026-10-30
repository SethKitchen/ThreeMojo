# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village game: the lighter village, its residents, and a player who
walks and jumps in front of the third-person camera."""

from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.animals.registry import RABBIT
from extensions.building.material import brick
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.field import LodBand
from extensions.vegetation.ground import Ground, Lot, Pond, footpath
from extensions.vegetation.meadow import Planting
from controls.third_person_controls import yaw_of
from extensions.village.character import (
    AIRBORNE,
    STANDING,
    MoveInput,
    no_input,
)
from extensions.village.day import DayCycle
from extensions.village.foes import Bandit, Post
from extensions.village.gathering import CHEST, HERBS, Spot
from extensions.village.house import HouseParameters, house_lot
from extensions.village.play import (
    FOCUS_HEIGHT,
    PlayParameters,
    TRUNK,
    VillageGame,
    default_residents,
    tree_obstacles,
)
from extensions.village.skills import FORAGING
from extensions.village.quality import LOW, ULTRA, game_quality
from extensions.village.residents import (
    Herd,
    NO_HOUSE,
    ResidentsParameters,
    Villager,
)
from extensions.village.village import (
    HousePlacement,
    PATH_WIDTH,
    VillageParameters,
)
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
from math.vector3 import Vector3
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
    small player. Nobody fights."""
    var p = PlayParameters(game_quality(LOW))
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
    p.gathering.spots = [Spot(HERBS, -4, -3, Angle(0.0, RADIAN))]
    p.battle.bandits = List[Bandit]()
    p.battle.posts = List[Post]()
    return p^


def _bed() raises -> DecodedImage:
    """Return a gray pebble photograph 4 pixels on a side."""
    return DecodedImage(4, 4, List[UInt8](length=64, fill=128), SRGB)


def test_the_game_village_is_planted_at_its_quality_and_lived_in() raises:
    var game = PlayParameters(game_quality(LOW))
    game.village.check()
    assert_equal(len(game.village.meadow.crown_levels), 3)
    assert_equal(game.village.meadow.ground_cells, 96)
    assert_almost_equal(game.residents.animal_coarseness, 3, atol=1e-6)
    assert_almost_equal(game.start_z, 26, atol=1e-6)
    var people = default_residents()
    people.check()
    assert_equal(len(people.villagers), 5)
    assert_equal(len(people.herds), 8)
    # Every person of the village is dressed, and so is the player.
    for villager in people.villagers:
        assert_true(len(villager.outfit.garments) >= 4)
    assert_equal(len(game.outfit.garments), 4)
    var village = _village()
    ref placed = village.houses[0]
    var lots: List[Lot] = [
        house_lot(placed.house, placed.x, placed.z, placed.turn)
    ]
    var trunks = tree_obstacles(village, lots)
    assert_equal(len(trunks), 1)
    assert_almost_equal(trunks[0].radius, TRUNK * 0.5, atol=1e-6)
    # A planting on the house's lot, or in the pond, does not grow, and
    # has no trunk.
    var crowded = _village()
    crowded.meadow.plantings.append(Planting(0, 5, -6, 0.5))
    crowded.meadow.plantings.append(Planting(0, 0, 4, 0.5))
    assert_equal(len(tree_obstacles(crowded, lots)), 1)
    # Nor does one on any other lot the meadow leaves bare, such as a
    # footpath.
    var path: List[Lot] = [footpath(5, 6, 7, 6, PATH_WIDTH)]
    assert_equal(len(tree_obstacles(_village(), path)), 0)
    var bare = _village()
    bare.meadow.plantings = []
    assert_equal(len(tree_obstacles(bare, lots)), 0)


def test_a_player_walks_jumps_and_is_followed() raises:
    var renderer = Renderer(16, 16)
    var assets = Assets()
    var scene = Scene()
    var game = VillageGame(
        scene,
        assets,
        renderer,
        _game_parameters(),
        pebble_bed(_bed()),
        None,
        48,
        27,
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
    # The frame is drawn at a third of the window and stretched to it.
    game.render(scene, assets)
    assert_equal(game.fast.width, 16)
    assert_equal(game.fast.height, 9)
    assert_equal(game.window.width, 48)
    assert_equal(game.window.height, 27)
    assert_true(game.upscale_ms > 0)


def test_a_player_walks_into_a_house_through_its_door() raises:
    var assets = Assets()
    var scene = Scene()
    var game = VillageGame(
        scene,
        assets,
        Renderer(16, 16),
        _game_parameters(),
        pebble_bed(_bed()),
        None,
        32,
        18,
    )
    ref ways = game.village.houses[0].interior.doorways
    assert_equal(len(ways), 1)
    var door = ways[0]
    var middle = door.middle()
    # Stand three meters out from the door, facing in, with the camera
    # behind.
    var x = middle.x - door.swing_x * 3
    var z = middle.z - door.swing_z * 3
    var ground = game.terrain.ground.height_at(x, z)
    game.player.position = Vector3(x, game.terrain.height_at(x, z, ground), z)
    var yaw = yaw_of(Vector3(door.swing_x, 0, door.swing_z))
    game.player.heading = yaw
    game.view.yaw = yaw
    var ahead = MoveInput(1, 0, 0, 0, False, False)
    var step = Duration(0.1, SECOND)
    var nearest = Float32(1)
    var widest = Float32(0)
    for _ in range(45):
        _ = game.tick(scene, assets, ahead, step)
        nearest = min(nearest, game.reach)
        widest = max(widest, game.village.doors.angles[0])
    # Look round: the eye swings off the doorway, behind the front wall.
    var look = MoveInput(0, 0, 1, 0, False, False)
    for _ in range(8):
        _ = game.tick(scene, assets, look, step)
        nearest = min(nearest, game.reach)
    # The player stands on the house's floor, the door opened as the
    # player came, and a wall came between the player and the camera's
    # eye.
    var feet = game.player.position
    assert_true(game.terrain.floor_under(feet.x, feet.z, feet.y) >= 0)
    assert_almost_equal(
        feet.y, game.village.houses[0].interior.floor_height, atol=1e-4
    )
    assert_true(widest > 1)
    assert_true(nearest < 1)
    # Under the ceiling, the eye stays below it.
    var ceiling = game.terrain.ceiling_over(feet.x, feet.z, feet.y)
    assert_true(game.camera.position.y < ceiling)
    game.render(scene, assets)
    assert_equal(game.window.width, 32)


def test_a_player_gathers_and_the_display_says_so() raises:
    var assets = Assets()
    var scene = Scene()
    var game = VillageGame(
        scene,
        assets,
        Renderer(16, 16),
        _game_parameters(),
        pebble_bed(_bed()),
        None,
        64,
        36,
    )
    assert_equal(len(game.gathering.spots), 1)
    var step = Duration(0.1, SECOND)
    # Herbs a meter ahead: the prompt says how to gather them.
    _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.prompt(), "E  GATHER HERBS")
    game.render(scene, assets)
    var plain = game.window.pixels.copy()
    var use = no_input()
    use.use = True
    _ = game.tick(scene, assets, use, step)
    assert_equal(game.gathering.satchel.count(HERBS), 1)
    assert_equal(game.note, "+1 herbs")
    # The herb trained foraging, which the display lists.
    assert_equal(game.skills.lines()[0], "FORAGING 1  10/50")
    assert_equal(game.prompt(), "")
    game.render(scene, assets)
    # The display drew the satchel and the note, so the frame changed.
    var changed = 0
    for k in range(len(plain)):
        if plain[k] != game.window.pixels[k]:
            changed += 1
    assert_true(changed > 0)
    # The note ages with the frames.
    _ = game.tick(scene, assets, no_input(), step)
    assert_almost_equal(game.note_age, 0.1, atol=1e-5)
    # The herbs come back, and a herb that lifts foraging a level says so.
    game.skills.experience[FORAGING.value] = 45
    game.gathering.spots[0].wait = 0
    _ = game.tick(scene, assets, use, step)
    assert_equal(game.note, "FORAGING LEVEL 2!")
    # Facing away from the pond, the camera does not see it, and its water
    # is not composed. Facing it, the camera sees it.
    var x = Float32(-6)
    var z = Float32(-6)
    var ground = game.terrain.ground.height_at(x, z)
    game.player.position = Vector3(x, ground, z)
    game.view.yaw = Angle(0.0, DEGREE)
    for _ in range(3):
        _ = game.tick(scene, assets, no_input(), step)
    assert_false(game.village.pond_seen(game.camera))
    game.render(scene, assets)
    game.view.yaw = Angle(180.0, DEGREE)
    for _ in range(3):
        _ = game.tick(scene, assets, no_input(), step)
    assert_true(game.village.pond_seen(game.camera))
    game.render(scene, assets)


def test_at_night_the_lamps_are_lit_and_the_pond_darkens() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = _game_parameters()
    parameters.day = DayCycle(23)
    var game = VillageGame(
        scene,
        assets,
        Renderer(16, 16),
        parameters,
        pebble_bed(_bed()),
        None,
        32,
        18,
    )
    # Face the pond, at (0, 4).
    game.view.yaw = Angle(180.0, DEGREE)
    var step = Duration(0.1, SECOND)
    for _ in range(3):
        _ = game.tick(scene, assets, no_input(), step)
    assert_true(game.village.pond_seen(game.camera))
    game.render(scene, assets)
    assert_equal(game.window.width, 32)
    assert_true(scene.node(game.village.houses[0].lit).visible)
    assert_false(scene.node(game.village.houses[0].daylit).visible)


def test_a_full_size_frame_is_not_stretched() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = _game_parameters()
    parameters.quality = game_quality(ULTRA)
    # A village with no house and no prop.
    parameters.village.houses = []
    parameters.village.props = []
    # And no display over the frame.
    parameters.hud = False
    var game = VillageGame(
        scene,
        assets,
        Renderer(16, 16),
        parameters,
        pebble_bed(_bed()),
        None,
        24,
        14,
    )
    assert_equal(len(game.terrain.walls), 0)
    _ = game.tick(scene, assets, no_input(), Duration(0.1, SECOND))
    game.render(scene, assets)
    assert_equal(game.fast.width, 24)
    assert_equal(game.window.width, 24)
    assert_equal(game.window.height, 14)
    assert_equal(game.upscale_ms, 0)
    # Every preset smooths the frame's edges.
    assert_true(game.smooth_ms > 0)


def test_a_villager_moves_and_a_frame_one_row_short_is_stretched() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = _game_parameters()
    parameters.residents.herds = []
    parameters.residents.villagers = [
        Villager(
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            2,
            -2,
            1,
            1,
            False,
            Outfit(),
            NO_HOUSE,
        )
    ]
    # Nineteen twentieths of 10 by 20 rounds to 10 by 19: as wide as the
    # window, and a row short.
    parameters.quality = game_quality(ULTRA)
    parameters.quality.render_scale = 0.95
    # The edges are left as they are drawn.
    parameters.quality.smooth_edges = False
    var game = VillageGame(
        scene,
        assets,
        Renderer(16, 16),
        parameters,
        pebble_bed(_bed()),
        None,
        10,
        20,
    )
    assert_equal(len(game.residents.bodies), 1)
    assert_equal(len(game.residents.beasts), 0)
    _ = game.tick(scene, assets, no_input(), Duration(0.1, SECOND))
    game.render(scene, assets)
    assert_equal(game.fast.width, 10)
    assert_equal(game.fast.height, 19)
    assert_equal(game.window.height, 20)
    assert_true(game.upscale_ms > 0)
    assert_equal(game.smooth_ms, 0)
    # A press beside her speaks, and she stops and turns to the player.
    game.player.position = game.residents.people[0].position + Vector3(
        0.8, 0, 0
    )
    var use = no_input()
    use.use = True
    _ = game.tick(scene, assets, use, Duration(0.1, SECOND))
    assert_true(game.talk.speech != "")
    assert_true(game.residents.holds[0] > 0)


def test_the_player_cuts_a_dummy_and_takes_a_bandits_coins() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = _game_parameters()
    parameters.gathering.spots = []
    parameters.battle.posts = [Post(-4, -3.5, Angle(180.0, DEGREE))]
    var game = VillageGame(
        scene,
        assets,
        Renderer(16, 16),
        parameters,
        pebble_bed(_bed()),
        None,
        64,
        36,
    )
    assert_equal(len(game.battle.dummies), 1)
    var step = Duration(0.1, SECOND)
    var cut = no_input()
    cut.light = True
    _ = game.tick(scene, assets, cut, step)
    for _ in range(4):
        _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.battle.fighter.combo, 1)
    assert_true(game.battle.drawn)
    # Locked on, the camera does not trail behind the player.
    var lock = no_input()
    lock.lock = True
    _ = game.tick(scene, assets, lock, step)
    assert_equal(game.battle.lock, 0)
    # A stance's name is the note.
    var high = no_input()
    high.high = True
    _ = game.tick(scene, assets, high, step)
    assert_equal(game.note, "HIGH STANCE")
    # A fallen bandit's coins go into the satchel.
    game.battle.loot = 8
    _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.gathering.satchel.count(CHEST), 8)
    assert_equal(game.battle.loot, 0)
    # A herb eaten to heal comes out of it.
    game.gathering.satchel.counts[HERBS.value] = 1
    game.battle.fighter.health = 100
    var heal = no_input()
    heal.heal = True
    _ = game.tick(scene, assets, heal, step)
    assert_equal(game.gathering.satchel.count(HERBS), 0)
    assert_equal(game.battle.eaten, 0)
    assert_true(game.battle.fighter.health > 200)
    game.render(scene, assets)
    assert_equal(game.window.width, 64)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
