# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The raid in a fight: the Stone Warden and its raiders, the zones, the
rockfall, the summon, the taunt, threat and poise, the warden's fall, and
raiders who strike, shoot, mend and revive.

The player stands at the middle and faces -z. The warden stands `far`
meters behind them, along +z, and its four raiders three meters behind
them: see `tests/_village_arena.mojo`."""

from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.ground import Ground, Lot, Pond
from tests._village_arena import (
    Arena,
    arena_parameters,
    holds_text,
    popup_texts,
)
from extensions.village.battle import (
    SUNDER_POISE,
    RAID_HERBS,
    RAID_LOOT,
    TAUNT_RANGE,
    Battle,
)
from extensions.village.boss import (
    CHARGE,
    CIRCLE,
    LINK_RANGE,
    ROCK_DAMAGE,
    SLAM,
    SUMMON,
    Zone,
    link_damage,
)
from extensions.village.character import no_input
from controls.third_person_controls import yaw_of
from extensions.village.combat import (
    BITE,
    DODGE,
    FALL,
    FREE,
    HIT,
    LIGHT_ONE,
    Blow,
    Struck,
)
from extensions.village.combos import SUNDER
from extensions.village.party import TAUNT_EVERY
from extensions.village.foes import CIRCLING
from extensions.village.raid import (
    REVIVE_SHARE,
    RISE_SECONDS,
    WARDEN_RADIUS,
)
from extensions.village.residents import Body
from extensions.village.styles import MACE, FightingStyle
from extensions.village.surfaces import house_looks
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import (
    INCH,
    METER,
    METER_PER_SECOND,
    SECOND,
    Duration,
    Length,
    Velocity,
)


def _built(ground: Ground, lots: List[Lot]) raises -> Battle:
    """Return a fight with the raid, on some ground and lots."""
    var assets = Assets()
    var scene = Scene()
    var body = Body(
        scene,
        assets,
        HumanoidSpec(Length(60.0, INCH), FEMALE),
        Outfit(),
        500,
        8,
    )
    return Battle(
        scene,
        assets,
        arena_parameters(0, 0, 10, raid=True),
        house_looks(assets, 4, 1),
        Terrain(ground),
        lots,
        body,
        Vector3(0, 0, 0),
        500,
        8,
    )


def test_a_raid_raises_its_warden_stones_and_raiders() raises:
    var arena = Arena(arena_parameters(0, 1, 10, raid=True))
    ref battle = arena.battle
    assert_equal(len(battle.wardens), 1)
    assert_equal(len(battle.members), 4)
    assert_equal(battle.targets(), 2)
    assert_equal(battle.first_warden(), 1)
    assert_equal(battle.target_radius(1), WARDEN_RADIUS)
    assert_equal(battle.target_radius(0), 0.3)
    assert_true(battle.standing(1))
    assert_almost_equal(battle.target_at(1).z, 10, atol=1e-4)
    assert_equal(len(battle.obstacles()), 6)
    assert_equal(len(battle.movers()), 6)


def test_a_raid_on_a_lot_or_in_the_water_is_left_out() raises:
    var lots: List[Lot] = [Lot(0, 10, 2, 2, 0)]
    var flat = Ground(hill_height=Length(0.0, METER))
    assert_equal(len(_built(flat, lots).wardens), 0)
    var wet = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(0.0, METER),
            Length(10.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
        ),
    )
    assert_equal(len(_built(wet, List[Lot]()).wardens), 0)


def test_raiders_join_the_player_and_part_from_them() raises:
    var arena = Arena(arena_parameters(0, 0, 40, raid=True, raiders=2))
    arena.tick(no_input())
    for k in range(2):
        assert_true(arena.battle.members[k].joined)
    assert_true(holds_text(arena.battle.notes, "THE RAIDERS JOIN YOUR PARTY"))
    arena.player.position = Vector3(0, 0, -100)
    arena.tick(no_input())
    assert_false(arena.battle.members[0].joined)
    # Far off, they do not join again.
    arena.tick(no_input())
    assert_false(arena.battle.members[0].joined)


def test_a_fallen_player_draws_no_raider() raises:
    var fallen = Arena(arena_parameters(0, 0, 40, raid=True, raiders=1))
    fallen.battle.fighter.health = 0
    fallen.battle.fighter.move = FALL
    fallen.tick(no_input())
    assert_false(fallen.battle.members[0].joined)


def test_the_warden_strikes_everyone_in_its_zone() raises:
    var arena = Arena(arena_parameters(0, 0, 4, raid=True, raiders=2))
    arena.run(4)
    ref boss = arena.battle.wardens[0].boss
    assert_true(boss.engaged)
    var hurt = arena.battle.fighter.health < 500
    for k in range(2):
        ref m = arena.battle.members[k].fighter
        hurt = hurt or m.health < m.parameters.health
    assert_true(hurt)
    assert_true(boss.health < boss.most)


def test_a_charge_runs_the_warden_along_its_line() raises:
    var arena = Arena(arena_parameters(0, 0, 9, raid=True, raiders=0))
    ref boss = arena.battle.wardens[0].boss
    boss.engaged = True
    boss.turn = 3
    boss.health = boss.most * 0.6
    boss.summoned[0] = True
    var start = arena.battle.wardens[0].character.position
    var charged = False
    for _ in range(60):
        arena.tick(no_input())
        charged = charged or arena.battle.wardens[0].boss.attack == CHARGE
    assert_true(charged)
    var gone = arena.battle.wardens[0].character.position - start
    assert_true(gone.length() > 4)


def test_a_rockfall_falls_on_the_marked_and_those_near() raises:
    var arena = Arena(arena_parameters(0, 0, 12, raid=True, raiders=2))
    arena.tick(no_input())
    ref boss = arena.battle.wardens[0].boss
    boss.engaged = True
    boss.marked = 0
    boss.mark_clock = 0.01
    arena.tick(no_input(), 0.02)
    assert_true(holds_text(arena.battle.notes, "ROCKFALL!"))
    var lost = 500 - arena.battle.fighter.health
    assert_true(lost > 0 and lost < ROCK_DAMAGE)


def test_a_rockfall_on_a_raider_passes_the_fallen_by() raises:
    var other = Arena(arena_parameters(0, 0, 12, raid=True, raiders=3))
    other.tick(no_input())
    other.battle.members[2].down = 0
    ref warden = other.battle.wardens[0].boss
    warden.engaged = True
    warden.marked = 2
    warden.mark_clock = 0.01
    other.tick(no_input(), 0.02)
    ref second = other.battle.members[1].fighter
    assert_true(second.health < second.parameters.health)
    ref downed = other.battle.members[2].fighter
    assert_equal(downed.health, downed.parameters.health)


def test_the_warden_calls_its_wolves() raises:
    var arena = Arena(arena_parameters(0, 0, 8, 2, raid=True, raiders=0))
    ref foe = arena.battle.foes[0]
    foe.fighter.health = 0
    foe.fighter.move = FALL
    foe.down = 0
    ref boss = arena.battle.wardens[0].boss
    boss.engaged = True
    boss.health = boss.most * 0.5
    var summoned = False
    for _ in range(40):
        arena.tick(no_input())
        summoned = summoned or arena.battle.wardens[0].boss.attack == SUMMON
    assert_true(summoned)
    assert_true(holds_text(arena.battle.notes, "THE WARDEN CALLS ITS WOLVES!"))
    assert_true(arena.battle.foes[0].down < 0)


def test_the_player_taunts_the_warden_once_in_a_while() raises:
    var arena = Arena(arena_parameters(0, 0, 8, raid=True, raiders=0))
    var taunt = no_input()
    taunt.taunt = True
    arena.press(taunt)
    ref boss = arena.battle.wardens[0].boss
    assert_equal(boss.target, 0)
    assert_true(boss.taunted > 0)
    assert_true(holds_text(popup_texts(arena.battle), "TAUNT"))
    var wait = arena.battle.taunt_wait
    assert_true(wait > 0 and wait <= TAUNT_EVERY)
    boss.taunted = 0
    arena.press(taunt)
    assert_equal(arena.battle.wardens[0].boss.taunted, 0)
    # With no raiders, the player strikes a linked strike alone.
    arena.battle.wardens[0].character.position = Vector3(0, 0, 2)
    arena.battle.wardens[0].boss.staggered = 4
    var heavy = no_input()
    heavy.heavy = True
    arena.press(heavy)
    assert_true(holds_text(arena.battle.notes, "LINKED STRIKE x1!"))
    # With no raiders, a rockfall falls on the player alone.
    var health = arena.battle.fighter.health
    var rock: List[Float32] = [100]
    arena.battle._rockfall(arena.scene, rock, arena.player)
    assert_true(arena.battle.fighter.health < health)


def test_a_far_or_fallen_warden_is_not_taunted() raises:
    var taunt = no_input()
    taunt.taunt = True
    var far = Arena(
        arena_parameters(0, 0, TAUNT_RANGE + 10, raid=True, raiders=0)
    )
    far.press(taunt)
    assert_equal(far.battle.taunt_wait, 0)
    far.battle.wardens[0].character.position = Vector3(0, 0, 8)
    far.battle.wardens[0].boss.health = 0
    far.press(taunt)
    assert_equal(far.battle.taunt_wait, 0)


def test_blows_draw_threat_break_poise_and_fell_the_warden() raises:
    var styles: List[FightingStyle] = [MACE]
    var arena = Arena(
        arena_parameters(0, 0, 30, raid=True, styles=styles, raiders=0)
    )
    ref warden = arena.battle.wardens[0]
    warden.character.position = Vector3(0, 0, -1.8)
    var cut = no_input()
    cut.light = True
    # Each cut lands before the warden's first swing does.
    arena.tick(cut)
    arena.run(0.3)
    ref boss = arena.battle.wardens[0].boss
    assert_true(boss.threat[0] > 0)
    # Its poise breaks under the next.
    boss.poise = 1
    arena.run(0.35)
    arena.tick(cut)
    arena.run(0.3)
    assert_true(holds_text(arena.battle.notes, "THE WARDEN STAGGERS!"))
    # It falls, and gives its loot.
    arena.battle.wardens[0].boss.health = 1
    arena.run(0.35)
    arena.tick(cut)
    arena.run(0.3)
    assert_true(arena.battle.wardens[0].boss.defeated())
    assert_equal(arena.battle.loot, RAID_LOOT)
    assert_equal(arena.battle.found, RAID_HERBS)
    assert_true(
        holds_text(arena.battle.notes, "THE STONE WARDEN FALLS! +60 COINS")
    )
    assert_false(arena.battle.standing(arena.battle.first_warden()))
    # It lies, and comes back whole after the respawn.
    arena.run(2.5)
    ref back = arena.battle.wardens[0]
    assert_equal(back.down, -1)
    assert_false(back.boss.defeated())


def _links(battle: Battle) -> Int:
    """Return how many linked strikes the notes tell of."""
    var count = 0
    for note in battle.notes:
        if note.startswith("LINKED STRIKE"):
            count += 1
    return count


def test_heavy_by_a_staggered_warden_links_the_party() raises:
    var arena = Arena(arena_parameters(0, 0, 30, raid=True, raiders=2))
    arena.tick(no_input())
    var heavy = no_input()
    heavy.heavy = True
    ref warden = arena.battle.wardens[0]
    warden.character.position = Vector3(0, 0, -3)
    warden.boss.engaged = True
    warden.boss.staggered = 4
    # With no stamina for the heavy attack, it calls no linked strike.
    arena.battle.fighter.stamina = 0
    arena.press(heavy)
    assert_equal(_links(arena.battle), 0)
    # Each standing raider near joins it; a fallen one does not.
    arena.battle.fighter.stamina = arena.battle.fighter.parameters.stamina
    arena.battle.members[1].down = 1
    var health = arena.battle.wardens[0].boss.health
    arena.press(heavy)
    assert_true(holds_text(arena.battle.notes, "LINKED STRIKE x2!"))
    assert_true(holds_text(popup_texts(arena.battle), "LINKED"))
    var lost = health - arena.battle.wardens[0].boss.health
    assert_true(lost >= link_damage(2) - 1)
    # It strikes once in each stagger.
    arena.run(1.5)
    arena.press(heavy)
    assert_equal(_links(arena.battle), 1)
    # Too far from the warden, the player calls none.
    ref boss = arena.battle.wardens[0].boss
    boss.linked = False
    boss.staggered = 4
    arena.battle.wardens[0].character.position = Vector3(0, 0, -LINK_RANGE - 3)
    arena.run(1.5)
    arena.press(heavy)
    assert_equal(_links(arena.battle), 1)
    # It can fell the warden, which gives its loot. A raider who left and
    # one far from the warden do not join it.
    arena.run(1.5)
    arena.battle.wardens[0].character.position = Vector3(0, 0, -3)
    arena.battle.wardens[0].boss.health = 1
    arena.battle.wardens[0].boss.staggered = 4
    arena.battle.members[1].joined = False
    arena.battle.members[1].post = Vector3(100, 0, 100)
    arena.battle.members[0].character.position = Vector3(40, 0, 40)
    arena.press(heavy)
    assert_true(holds_text(arena.battle.notes, "LINKED STRIKE x1!"))
    assert_equal(_links(arena.battle), 2)
    assert_true(arena.battle.wardens[0].boss.defeated())
    assert_equal(arena.battle.loot, RAID_LOOT)


def test_the_raids_blows_and_heals_pass_by_the_fallen_and_the_far() raises:
    var arena = Arena(arena_parameters(0, 0, 12, raid=True, raiders=2))
    arena.tick(no_input())
    arena.battle.wardens[0].boss.engaged = True
    arena.battle.wardens[0].boss.attack = SLAM
    arena.battle.wardens[0].boss.zone = Zone(
        CIRCLE, Vector3(0, 0, 0), Vector3(0, 0, 1), 30, 0
    )
    # A zone passes by a fallen player, a fallen raider and one who left.
    arena.battle.fighter.health = 0
    arena.battle.fighter.move = FALL
    arena.battle.members[0].down = 0
    arena.battle.members[1].joined = False
    var full = arena.battle.members[1].fighter.health
    arena.battle._zone_strikes(arena.scene, 0, arena.player)
    assert_equal(arena.battle.fighter.health, 0)
    assert_equal(arena.battle.members[1].fighter.health, full)
    # A rockfall passes by the fallen player, and each raider with no share.
    var rock: List[Float32] = [100]
    arena.battle._rockfall(arena.scene, rock, arena.player)
    assert_equal(arena.battle.fighter.health, 0)
    # A revive passes by a fallen raider far off.
    arena.battle._revive_near(Vector3(40, 0, 40), 1)
    assert_equal(arena.battle.members[0].revive, 0)
    # A raider who left does not join a fallen player, nor fight; a fallen
    # player who holds the use button revives nobody.
    var use = no_input()
    use.use = True
    arena.tick(use)
    assert_false(arena.battle.members[1].joined)
    # A healer's mend passes by a fallen player and a fallen raider.
    arena.battle.members[1].joined = True
    arena.battle._party_mend(1, arena.player)
    assert_equal(arena.battle.fighter.health, 0)
    # Nor does it reach a player or a raider far off.
    arena.battle.fighter.revive()
    arena.battle.fighter.health = 100
    arena.battle.members[0].down = -1
    arena.battle.members[0].fighter.revive()
    arena.battle.members[0].fighter.health = 100
    arena.battle.members[0].character.position = Vector3(40, 0, 40)
    arena.battle.members[1].character.position = Vector3(-40, 0, 40)
    arena.battle._party_mend(1, arena.player)
    assert_equal(arena.battle.fighter.health, 100)
    assert_equal(arena.battle.members[0].fighter.health, 100)
    # A rockfall's share falls on the raider it is for alone.
    var shares: List[Float32] = [0, 0, 50]
    arena.battle._rockfall(arena.scene, shares, arena.player)
    assert_equal(arena.battle.fighter.health, 100)
    assert_equal(arena.battle.members[0].fighter.health, 100)
    # The player's mend heals each raider near, and draws threat; it
    # passes by a raider who left and a fallen one.
    arena.battle.wardens[0].boss.engaged = True
    arena.battle.members[0].character.position = Vector3(1, 0, 1)
    arena.battle.members[1].character.position = Vector3(-1, 0, 1)
    arena.battle.members[1].joined = False
    var threat = arena.battle.wardens[0].boss.threat[0]
    arena.battle._mend(arena.player)
    assert_true(arena.battle.members[0].fighter.health > 100)
    assert_true(arena.battle.wardens[0].boss.threat[0] > threat)
    arena.battle.members[1].joined = True
    arena.battle.members[1].down = 0
    arena.battle.members[1].fighter.health = 100
    # Nor one far off.
    arena.battle.members[0].character.position = Vector3(40, 0, 40)
    var far = arena.battle.members[0].fighter.health
    arena.battle._mend(arena.player)
    assert_equal(arena.battle.members[1].fighter.health, 100)
    assert_equal(arena.battle.members[0].fighter.health, far)
    # With no foe at all, a summon calls nobody.
    arena.battle._summon(0)
    assert_true(holds_text(arena.battle.notes, "THE WARDEN CALLS ITS WOLVES!"))
    # A sundering finisher takes the warden's poise; a wound bleeds it,
    # and does not fell it.
    for k in range(len(arena.battle.book.combos)):
        if arena.battle.book.combos[k].effect == SUNDER:
            arena.battle.finisher = k
            break
    var w = arena.battle.first_warden()
    arena.battle.wardens[0].boss.poise = 700
    var blow = Blow(
        40, 10, Velocity(0.0, METER_PER_SECOND), Velocity(0.0, METER_PER_SECOND)
    )
    arena.battle._afflict(arena.scene, w, Struck(HIT, 40, 10), blow)
    assert_almost_equal(
        arena.battle.wardens[0].boss.poise, 700 - SUNDER_POISE, atol=1e-3
    )
    arena.battle.wardens[0].boss.health = 5
    arena.battle._bleed(w, 50)
    assert_equal(arena.battle.wardens[0].boss.health, 1)


def test_raiders_see_the_mark_and_a_tired_one_cannot_dodge() raises:
    var arena = Arena(arena_parameters(0, 0, 12, raid=True, raiders=2))
    arena.tick(no_input())
    arena.battle.wardens[0].boss.engaged = True
    # A mark on a raider, then on the player: the raiders gather on it.
    arena.battle.wardens[0].boss.marked = 1
    arena.battle.wardens[0].boss.mark_clock = 3
    var before = arena.battle.members[1].character.position
    arena.tick(no_input())
    arena.battle.wardens[0].boss.marked = 0
    arena.tick(no_input())
    var after = arena.battle.members[1].character.position
    assert_true((after - before).length() > 0)
    arena.battle.wardens[0].boss.marked = -1
    # A raider with no stamina cannot dodge out of a zone.
    arena.battle.wardens[0].boss.attack = SLAM
    arena.battle.wardens[0].boss.clock = (
        arena.battle.wardens[0].boss.windup() * 0.9
    )
    arena.battle.wardens[0].boss.zone = Zone(
        CIRCLE, Vector3(0, 0, 3), Vector3(0, 0, 1), 20, 0
    )
    for k in range(2):
        arena.battle.members[k].fighter.move = FREE
        arena.battle.members[k].fighter.stamina = 0
    arena.tick(no_input())
    for k in range(2):
        assert_true(arena.battle.members[k].fighter.move != DODGE)
    # A raider who left, with its post far off, keeps out of the fight.
    arena.battle.members[1].joined = False
    arena.battle.members[1].post = Vector3(100, 0, 100)
    arena.tick(no_input())
    assert_false(arena.battle.members[1].joined)


def test_a_raiders_swing_passes_dummies_and_the_fallen() raises:
    var arena = Arena(arena_parameters(1, 1, 8, 1, raid=True, raiders=1))
    arena.tick(no_input())
    # The summon calls the wolf, and passes the bandit by.
    var post = arena.battle.foes[0].character.position
    arena.battle._summon(0)
    assert_equal((arena.battle.foes[0].character.position - post).length(), 0)
    var gap = (
        arena.battle.foes[1].character.position
        - arena.battle.wardens[0].character.position
    )
    assert_true(gap.length() < 5)
    # A tank's swing looks past the fallen bandit and the dummy.
    arena.battle.foes[0].down = 0
    ref tank = arena.battle.members[0].fighter
    _ = tank.request(LIGHT_ONE)
    for _ in range(100):
        if tank.swing():
            break
        tank.update(Duration(0.01, SECOND))
    assert_true(tank.swing())
    arena.battle._member_strikes(arena.scene, 0, arena.player)
    assert_true(arena.battle.foes[0].down >= 0)


def test_a_wolf_goes_for_the_nearest_raider_and_bites_them() raises:
    var arena = Arena(arena_parameters(0, 0, 30, 1, raid=True, raiders=1))
    arena.tick(no_input())
    var post = arena.battle.members[0].character.position
    # The wolf stands by the raider, far from the player: it goes for them.
    arena.battle.foes[0].character.position = post + Vector3(1, 0, 0)
    arena.tick(no_input())
    assert_equal(arena.battle.quarries[0], 0)
    # It attacks the raider without taking the player's attack token.
    arena.battle.foes[0].home = post + Vector3(2, 0, 0)
    arena.battle.foes[0].brain.state = CIRCLING
    arena.battle.foes[0].brain.timer = 0
    arena.tick(no_input())
    assert_equal(arena.battle.token, -1)
    # Beside the player, it goes for the player.
    arena.battle.foes[0].character.position = Vector3(1, 0, -1)
    arena.tick(no_input())
    assert_equal(arena.battle.quarries[0], -1)
    # A fallen raider is not one to go for; with the player fallen, the
    # standing raider is.
    arena.battle.foes[0].character.position = post + Vector3(1, 0, 0)
    arena.battle.members[0].down = 0
    arena.tick(no_input())
    assert_equal(arena.battle.quarries[0], -1)
    arena.battle.members[0].down = -1
    arena.battle.fighter.health = 0
    arena.battle.fighter.move = FALL
    arena.battle.foes[0].character.position = Vector3(1, 0, -1)
    arena.tick(no_input())
    assert_equal(arena.battle.quarries[0], 0)
    # Its bite strikes the raider it goes for, once a bite, and only within
    # its reach.
    ref wolf = arena.battle.foes[0].fighter
    wolf.move = FREE
    _ = wolf.request(BITE)
    for _ in range(100):
        if wolf.swing():
            break
        wolf.update(Duration(0.01, SECOND))
    assert_true(wolf.swing())
    var there = arena.battle.members[0].character.position
    arena.battle.foes[0].character.position = there + Vector3(9, 0, 0)
    arena.battle.foes[0].character.heading = yaw_of(Vector3(-1, 0, 0))
    var health = arena.battle.members[0].fighter.health
    arena.battle._foe_strikes(arena.scene, 0, arena.player)
    assert_equal(arena.battle.members[0].fighter.health, health)
    arena.battle.foes[0].character.position = there + Vector3(0.9, 0, 0)
    arena.battle._foe_strikes(arena.scene, 0, arena.player)
    var bitten = arena.battle.members[0].fighter.health
    assert_true(bitten < health)
    arena.battle._foe_strikes(arena.scene, 0, arena.player)
    assert_equal(arena.battle.members[0].fighter.health, bitten)


def test_raiders_strike_shoot_and_mend_in_the_fight() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True))
    arena.battle.fighter.health = 250
    var shot = False
    var healed = False
    for _ in range(100):
        var before = arena.battle.fighter.health
        arena.tick(no_input())
        healed = healed or arena.battle.fighter.health > before
        for s in arena.battle.shots:
            shot = shot or s.owner >= 0
    ref boss = arena.battle.wardens[0].boss
    var struck = False
    for k in range(1, 5):
        struck = struck or boss.threat[k] > 0
    assert_true(struck)
    assert_true(shot)
    assert_true(healed)


def test_a_fallen_raider_is_revived_or_stands_after_the_fight() raises:
    var arena = Arena(arena_parameters(0, 0, 40, raid=True, raiders=3))
    arena.tick(no_input())
    ref fallen = arena.battle.members[0]
    fallen.fighter.health = 0
    fallen.fighter.move = FALL
    arena.tick(no_input())
    assert_true(arena.battle.members[0].down >= 0)
    # The player stands by it, holding the use button.
    arena.player.position = arena.battle.members[
        0
    ].character.position + Vector3(0.5, 0, 0)
    var use = no_input()
    use.use = True
    arena.run(3, use)
    ref up = arena.battle.members[0]
    assert_equal(up.down, -1)
    assert_almost_equal(
        up.fighter.health, REVIVE_SHARE * up.fighter.parameters.health, atol=1
    )
    assert_true(holds_text(arena.battle.notes, "A RAIDER IS REVIVED"))
    # Out of the fight, a fallen raider stands up after a while.
    ref later = arena.battle.members[2]
    later.fighter.health = 0
    later.fighter.move = FALL
    later.down = RISE_SECONDS
    arena.tick(no_input())
    assert_equal(arena.battle.members[2].down, -1)


def test_the_healer_revives_a_raider_out_of_the_fight() raises:
    var arena = Arena(arena_parameters(0, 0, 40, raid=True, raiders=2))
    arena.tick(no_input())
    ref fallen = arena.battle.members[0]
    fallen.fighter.health = 0
    fallen.fighter.move = FALL
    arena.run(6)
    assert_equal(arena.battle.members[0].down, -1)


def test_the_companion_casts_at_the_warden_in_its_fight() raises:
    var arena = Arena(
        arena_parameters(0, 0, 8, ally=True, raid=True, raiders=0)
    )
    assert_equal(arena.battle.ally_target(Vector3(0, 0, 0)), -1)
    arena.battle.wardens[0].boss.engaged = True
    var warden = arena.battle.first_warden()
    assert_equal(arena.battle.ally_target(Vector3(0, 0, 0)), warden)
    arena.battle.wardens[0].boss.health = 0
    assert_equal(arena.battle.ally_target(Vector3(0, 0, 0)), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
