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
    Obstacle,
    AIRBORNE,
    STANDING,
    MoveInput,
    no_input,
)
from extensions.village.day import DayCycle
from extensions.village.foes import Bandit, Den, Post
from extensions.village.gathering import BITING, CHEST, FISH, HERBS, Spot
from extensions.village.house import HouseParameters, house_lot
from extensions.humanoid.skeleton.head.expression import (
    ANGER,
    FEAR,
    SADNESS,
    SMILE,
    FacialExpression,
)
from extensions.village.faces import FaceLife
from extensions.village.battle_hud import DANGER
from extensions.village.foes import bandit_fighter
from extensions.village.hud import GOLD_TEXT
from extensions.village.sound import COIN, HIT, SPLASH, SWING
from extensions.village.talk import DONE, FAIR, NIGHT, SNOWY, TAKEN, WET
from extensions.village.residents import SIT, WORK
from extensions.village.props import BARREL, BENCH, CROPS, Prop, WELL, WOODPILE
from extensions.village.play import (
    FOCUS_HEIGHT,
    FOE_SIGHT,
    SILVER_MARK,
    GRIMACE,
    WINDED,
    player_mood,
    SPECIALTY_MIGHT,
    PlayParameters,
    TRUNK,
    VillageGame,
    default_residents,
    game_residents,
    tree_obstacles,
    prop_stops,
    trunks_reach,
    village_mood,
    HITSTOP,
)
from extensions.village.combat import (
    DODGE,
    FREE,
    FALL,
    FLINCH,
    HEAVY,
    LIGHT_ONE,
    STAGGER,
    WHIRLWIND,
    CombatMove,
    Fighter,
    FighterParameters,
)
from extensions.village.progress import (
    PLACE_SHIFT,
    Progress,
    pack_progress,
    unpack_progress,
)
from extensions.village.skills import FORAGING, style_skill
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
from extensions.village.raid import RaidParameters
from extensions.village.styles import ARCHERY, MACE, MAGIC, SWORD
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
    assert_raises,
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
    p.battle.dens = List[Den]()
    p.battle.posts = List[Post]()
    p.battle.allies = List[Bandit]()
    p.battle.raids = List[RaidParameters]()
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
    # Look around: the eye swings off the doorway, behind the front wall.
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
    # The herbs come back, and an herb that lifts foraging a level says so.
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
    # Before anyone speaks, the speech is as `Talk` holds it; the compass
    # points to her errand, in gold.
    assert_equal(game.speech(), "")
    var marks = game.compass_marks()
    assert_equal(len(marks), 1)
    assert_equal(marks[0].color.r, GOLD_TEXT.r)
    var use = no_input()
    use.use = True
    _ = game.tick(scene, assets, use, Duration(0.1, SECOND))
    assert_true(game.talk.speech != "")
    assert_true(game.residents.holds[0] > 0)
    # Her words show as far as her mouth has said them, in their full
    # width; the errand she gave is taken, in silver.
    assert_equal(game.talker, 0)
    var said = game.speech()
    assert_equal(said.byte_length(), game.talk.speech.byte_length())
    assert_true(said != game.talk.speech)
    assert_equal(game.compass_marks()[0].color.r, SILVER_MARK.r)
    for _ in range(40):
        _ = game.tick(scene, assets, no_input(), Duration(0.1, SECOND))
    assert_equal(game.speech(), game.talk.speech)
    # An errand done is not pointed to.
    game.talk.states[0] = DONE
    assert_equal(len(game.compass_marks()), 0)
    game.talk.states[0] = TAKEN
    # The compass's caption and strip draw over the frame.
    game.render(scene, assets)


def test_the_players_face_shows_the_fight() raises:
    var life = FaceLife(1)
    var fighter = Fighter(FighterParameters())
    player_mood(life, fighter)
    assert_equal(life.goal_strength, 0)
    assert_equal(life.breath, 0)
    var moods: List[CombatMove] = [
        LIGHT_ONE,
        HEAVY,
        WHIRLWIND,
        FLINCH,
        STAGGER,
        FALL,
    ]
    var felt: List[FacialExpression] = [
        ANGER,
        ANGER,
        ANGER,
        FEAR,
        FEAR,
        SADNESS,
    ]
    var strong: List[Float32] = [0.55, 0.9, 0.9, 0.7, 0.7, 1]
    for k in range(len(moods)):
        fighter.move = moods[k]
        player_mood(life, fighter)
        assert_true(life.goal == felt[k])
        assert_almost_equal(life.goal_strength, strong[k], atol=1e-6)
        assert_almost_equal(life.holding, GRIMACE, atol=1e-6)
    # A dodge shows nothing new.
    fighter.move = DODGE
    life.feel(SMILE, 0.2)
    player_mood(life, fighter)
    assert_true(life.goal == SMILE)
    # Out of stamina, the player pants; with none to lose, never.
    fighter.stamina = 0
    player_mood(life, fighter)
    assert_equal(life.breath, 1)
    fighter.stamina = fighter.parameters.stamina * WINDED
    player_mood(life, fighter)
    assert_equal(life.breath, 0)
    fighter.parameters.stamina = 0
    player_mood(life, fighter)
    assert_equal(life.breath, 0)


def test_the_compass_points_to_the_nearest_foe_that_stands() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = _game_parameters()
    parameters.gathering.spots = []
    parameters.battle.bandits = [
        Bandit(
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            Outfit(),
            -4,
            -9,
            Angle(0.0, DEGREE),
            5,
            bandit_fighter(),
            False,
        )
    ]
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
    assert_equal(len(game.battle.foes), 1)
    var marks = game.compass_marks()
    assert_equal(len(marks), 1)
    assert_equal(marks[0].color.r, DANGER.r)
    # A fallen foe, or one past the compass's sight, is not pointed to.
    game.battle.foes[0].down = 1
    assert_equal(len(game.compass_marks()), 0)
    game.battle.foes[0].down = -1
    game.battle.foes[0].character.position.z -= FOE_SIGHT * 2
    assert_equal(len(game.compass_marks()), 0)


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
    # An herb eaten to heal comes out of it.
    game.gathering.satchel.counts[HERBS.value] = 1
    game.battle.fighter.health = 100
    var heal = no_input()
    heal.heal = True
    _ = game.tick(scene, assets, heal, step)
    assert_equal(game.gathering.satchel.count(HERBS), 0)
    assert_equal(game.battle.eaten, 0)
    assert_true(game.battle.fighter.health > 200)
    # An herb a bandit dropped goes into the satchel.
    game.battle.found = 1
    _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.gathering.satchel.count(HERBS), 1)
    # Fighting trains swordplay; a new level is the note, and makes the
    # blows stronger.
    game.battle.trained[SWORD.value] = 50
    _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.note, "SWORDPLAY LEVEL 2!")
    _ = game.tick(scene, assets, no_input(), step)
    # The sword is the player's specialty: its blows are stronger still.
    assert_almost_equal(
        game.battle.fighter.parameters.might,
        1.05 * (1 + SPECIALTY_MIGHT),
        atol=1e-5,
    )
    # In another style, the might is that style's level alone.
    _ = game.battle.fighter.set_style(MACE)
    _ = game.tick(scene, assets, no_input(), step)
    assert_almost_equal(game.battle.fighter.parameters.might, 1, atol=1e-5)
    # A strong blow shakes the camera.
    game.battle.shake = 0.05
    _ = game.tick(scene, assets, no_input(), step)
    assert_true(game.battle.shake < 0.05)
    game.render(scene, assets)
    assert_equal(game.window.width, 64)
    # The player keeps their progress from one game to the next: the
    # experience, the satchel, a mastered combo, the specialty and the
    # style in hand. The levels teach the combos again.
    var kept = game.progress()
    assert_equal(kept.satchel[HERBS.value], 1)
    var before = Progress()
    before.experience[style_skill(MAGIC).value] = 2250
    before.satchel[HERBS.value] = 3
    before.mastery[0] = 400
    before.specialty = MAGIC
    before.style = MAGIC
    game.battle.parameters.styles = [SWORD, MAGIC]
    game.restore(scene, unpack_progress(pack_progress(before)))
    assert_true(game.battle.fighter.style == MAGIC)
    assert_equal(game.battle.style_at, 1)
    assert_true(game.battle.book.specialty == MAGIC)
    assert_equal(game.gathering.satchel.count(HERBS), 3)
    _ = game.tick(scene, assets, no_input(), step)
    assert_true(len(game.battle.book.known(MAGIC)) > 0)
    var back = game.progress()
    assert_equal(back.mastery[0], 400)
    assert_true(back.style == MAGIC)
    # A style the player does not carry is not taken up; nor one while
    # the player makes a move.
    before.style = ARCHERY
    game.restore(scene, before)
    assert_true(game.battle.fighter.style == MAGIC)
    before.style = SWORD
    game.battle.fighter.move = LIGHT_ONE
    game.restore(scene, before)
    assert_true(game.battle.fighter.style == MAGIC)
    # The world as the game left it comes back too: where the player
    # stood, the hour, the weather, the errands and the spots used up.
    var world = game.progress()
    assert_equal(len(world.place), 4)
    world.place[0] = PLACE_SHIFT + 150
    world.place[1] = PLACE_SHIFT - 220
    world.place[2] = PLACE_SHIFT + 20500
    world.place[3] = 2
    world.spent = [0, 99]
    game.restore(scene, unpack_progress(pack_progress(world)))
    assert_almost_equal(game.player.position.x, 1.5, atol=1e-4)
    assert_almost_equal(game.player.position.z, -2.2, atol=1e-4)
    assert_almost_equal(game.day.hour, 20.5, atol=1e-4)
    assert_equal(game.weather.kind.value, 2)
    # A place far away, an hour or a weather that is not one keeps the
    # game's own.
    world.place = [0, 0, PLACE_SHIFT + 30000, 9]
    game.restore(scene, world)
    assert_almost_equal(game.day.hour, 20.5, atol=1e-4)
    _ = before.mastery.pop()
    with assert_raises(contains="mastery"):
        game.restore(scene, before)


def test_a_game_builds_its_animals_no_finer_than_its_quality() raises:
    var game = PlayParameters(game_quality(LOW))
    game.residents = ResidentsParameters()
    assert_almost_equal(game.residents.animal_coarseness, 1, atol=1e-9)
    # The low preset's animals are three times coarser.
    var built = game_residents(game)
    assert_almost_equal(built.animal_coarseness, 3, atol=1e-6)
    # A coarser choice of the game's own is kept.
    game.residents.animal_coarseness = 5
    assert_almost_equal(game_residents(game).animal_coarseness, 5, atol=1e-9)


def test_the_rain_a_wader_and_a_bite_ripple_the_pond() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = _game_parameters()
    parameters.gathering.spots = [
        Spot(HERBS, -4, -3, Angle(0.0, RADIAN)),
        Spot(FISH, -4.5, 4, Angle(0.0, RADIAN)),
    ]
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
    assert_equal(len(game.gathering.spots), 2)
    var step = Duration(0.25, SECOND)
    scene.update()
    # A downpour rings the pond.
    game.weather.look.rain = 1
    game.ripple_pond(scene, step)
    var rained = len(game.village.water._drops)
    assert_true(rained > 0)
    # It rains on the frame, and not under the house's roof.
    game.render(scene, assets)
    assert_equal(game.window.width, 32)
    rained = len(game.village.water._drops)
    # A player who wades in the pond leaves a wake, a few taps a second.
    game.player.position = Vector3(0, game.village.level.to(METER) - 0.3, 4)
    game.player.velocity = Vector3(1, 0, 0)
    game.weather.look.rain = 0
    game.ripple_pond(scene, step)
    assert_equal(len(game.village.water._drops), rained + 1)
    game.ripple_pond(scene, Duration(0.01, SECOND))
    assert_equal(len(game.village.water._drops), rained + 1)
    # A fish that bites jerks its float.
    for index in range(len(game.gathering.spots)):
        if game.gathering.spots[index].spot.kind == FISH:
            game.gathering.spots[index].phase = BITING
    game.player.velocity = Vector3(0, 0, 0)
    game.ripple_pond(scene, step)
    assert_true(len(game.village.water._drops) >= rained + 1)
    # The game hears a wading footfall, a swing, and coins.
    game.player.position = Vector3(0, game.village.level.to(METER) - 0.3, 4)
    game.player.velocity = Vector3(2, 0, 0)
    game.player.grounded = True
    game.stride = 0
    game.coins_were = 0
    game.gathering.satchel.counts[CHEST.value] = 5
    game.battle.fighter.move = LIGHT_ONE
    game.swinging = False
    game.foes_health = 1000
    game.hear(step)
    var kinds = List[Int]()
    for voice in game.sounds.voices:
        kinds.append(voice.kind.value)
    assert_true(SPLASH.value in kinds)
    assert_true(SWING.value in kinds)
    assert_true(HIT.value in kinds)
    assert_true(COIN.value in kinds)
    assert_equal(len(game.audio(100)), 200)
    # A hard blow stops the world a moment, and a roll kicks up dust.
    assert_almost_equal(game.hitstop, HITSTOP, atol=1e-6)
    game.battle.fighter.move = DODGE
    game.was_kicking = False
    game.hear(step)
    assert_true(game.dust_since < 1)
    _ = game.tick(scene, assets, no_input(), step)
    assert_true(game.hitstop <= 0)
    # Near falling, and as a blow lands, the frame's edges redden.
    game.battle.fighter.health = 10
    assert_true(game.vignette() > 0.5)
    game.battle.fighter.health = game.battle.fighter.parameters.health
    assert_equal(game.vignette(), 0)
    game.battle.fighter.move = FREE
    # Paused, nothing moves; the map and the pause panel show.
    var before_pause = game.player.position
    game.paused = True
    game.show_map = True
    var push = no_input()
    push.forward = 1
    _ = game.tick(scene, assets, push, step)
    assert_almost_equal(game.player.position.x, before_pause.x, atol=1e-6)
    game.render(scene, assets)
    assert_equal(game.window.width, 32)
    var marks = game.map_marks(scene)
    assert_equal(len(marks.houses), len(game.village.houses))
    game.paused = False
    game.show_map = False
    # A fall costs a quarter of the coins the player carries.
    game.gathering.satchel.counts[CHEST.value] = 100
    game.battle.fell = True
    _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.gathering.satchel.count(CHEST), 75)
    assert_false(game.battle.fell)
    assert_equal(game.note, "YOU LOSE 25 COINS")
    # With no coins, a fall costs nothing.
    game.gathering.satchel.counts[CHEST.value] = 0
    game.battle.fell = True
    _ = game.tick(scene, assets, no_input(), step)
    assert_equal(game.gathering.satchel.count(CHEST), 0)


def test_the_camera_comes_in_before_a_trunk() raises:
    var trunks: List[Obstacle] = [Obstacle(0, 5, 0.5)]
    var focus = Vector3(0, 1.5, 0)
    # A trunk halfway along the sight brings the eye in before it.
    var reach = trunks_reach(trunks, focus, Vector3(0, 2, 10), 0.3)
    assert_almost_equal(reach, 0.45 - 0.03, atol=1e-4)
    # No trunk in the way, or the eye on the focus, is the whole way.
    assert_equal(trunks_reach(trunks, focus, Vector3(10, 2, 0), 0.3), 1)
    assert_equal(trunks_reach(trunks, focus, focus, 0.3), 1)
    # A trunk past the eye, or round the focus, stops nothing.
    assert_equal(trunks_reach(trunks, focus, Vector3(0, 2, 2), 0.3), 1)
    var round: List[Obstacle] = [Obstacle(0, 0, 1)]
    assert_equal(trunks_reach(round, focus, Vector3(0, 2, 10), 0.3), 1)
    # A trunk just past the margin leaves none of the way.
    var near: List[Obstacle] = [Obstacle(0, 0.6, 0.5)]
    assert_equal(trunks_reach(near, focus, Vector3(0, 2, 10), 0.3), 0)


def test_the_village_s_mood_and_its_props_stops() raises:
    assert_true(village_mood(0.2, 0, 0) == NIGHT)
    assert_true(village_mood(1, 0, 0.5) == SNOWY)
    assert_true(village_mood(1, 0.6, 0) == WET)
    assert_true(village_mood(1, 0, 0) == FAIR)
    var turn = Angle(0.0, DEGREE)
    var stops = prop_stops(
        [
            Prop(BENCH, 0, 0, turn, 1.6),
            Prop(WOODPILE, 5, 0, turn, 2),
            Prop(CROPS, 10, 0, turn, 3),
            Prop(WELL, 15, 0, turn, 0.8),
            Prop(BARREL, 20, 0, turn, 0.3),
        ]
    )
    assert_equal(len(stops), 4)
    assert_true(stops[0].activity == SIT)
    assert_true(stops[1].activity == WORK)
    assert_true(stops[3].activity == WORK)
    # A seat is before the bench, and the well's place beside it.
    assert_almost_equal(stops[0].z, 0.45, atol=1e-5)
    assert_almost_equal(stops[3].x, 15 + 0.8 + 0.7, atol=1e-5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
