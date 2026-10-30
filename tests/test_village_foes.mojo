# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's foes: a bandit's brain, frame by frame, and the straw
dummies that rock as they are hit."""

from core.assets import Assets
from core.scene import Scene
from extensions.village.combat import (
    BITE,
    BURST,
    FREE,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
)
from extensions.village.foes import (
    WOLF_CIRCLE,
    WOLF_NOTICE,
    ALERT,
    ALERTED,
    ATTACKING,
    CIRCLE,
    CIRCLING,
    CLOSING,
    GUARDING,
    GUARD_TIME,
    LOSE,
    NOTICE,
    POSTED,
    RETREAT,
    RETREATING,
    RETURNING,
    Brain,
    Dummy,
    FoeState,
    Post,
    Sight,
    bandit_fighter,
    captain_fighter,
    den_places,
    default_dens,
    wolf_fighter,
    default_bandits,
    default_posts,
    dummy_fighter,
    plan_for,
    state_name,
    still,
)
from extensions.village.sheet import Sheet
from extensions.village.surfaces import house_looks
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, SECOND, Angle, Duration


def _sight(
    player: Vector3,
    home: Vector3 = Vector3(0, 0, 0),
    down: Bool = False,
    threat: Bool = False,
    free: Bool = True,
    ready: Bool = True,
    holds: Bool = False,
    unclaimed: Bool = True,
    raging: Bool = False,
) -> Sight:
    """Return what a bandit at the middle knows."""
    return Sight(
        Vector3(0, 0, 0),
        home,
        player,
        down,
        threat,
        free,
        ready,
        holds,
        unclaimed,
        raging,
    )


def _frame() -> Duration:
    """Return a frame of a tenth of a second."""
    return Duration(0.1, SECOND)


def _brain(state: FoeState, timer: Float32 = 0) -> Brain:
    """Return a brain in a state, with its timer set."""
    var brain = Brain(7)
    brain.state = state
    brain.timer = timer
    return brain^


def test_each_state_has_a_name() raises:
    assert_equal(state_name(POSTED), "posted")
    assert_equal(state_name(RETURNING), "returning")
    assert_true(FoeState(7).is_valid())
    assert_false(FoeState(8).is_valid())
    with assert_raises(contains="eight"):
        _ = state_name(FoeState(-1))
    var nothing = still()
    assert_true(nothing.attack == FREE)
    assert_false(nothing.claim)


def test_a_plan_follows_the_roll() raises:
    var two = plan_for(0.1)
    assert_equal(len(two), 2)
    assert_true(two[1] == LIGHT_TWO)
    var three = plan_for(0.5)
    assert_true(three[2] == LIGHT_THREE)
    var heavy = plan_for(0.7)
    assert_equal(len(heavy), 1)
    assert_true(heavy[0] == HEAVY)
    var both = plan_for(0.85)
    assert_true(both[0] == LIGHT_ONE)
    assert_true(both[1] == HEAVY)
    var burst = plan_for(0.95)
    assert_equal(len(burst), 1)
    assert_true(burst[0] == BURST)


def test_a_posted_bandit_notices_the_player_and_comes() raises:
    var brain = Brain(3)
    # Far away, it stands.
    var intent = brain.think(_sight(Vector3(0, 0, NOTICE + 1)), _frame())
    assert_true(brain.state == POSTED)
    assert_almost_equal(intent.way.length(), 0, atol=1e-6)
    # A fallen player is not noticed.
    _ = brain.think(_sight(Vector3(0, 0, 2), down=True), _frame())
    assert_true(brain.state == POSTED)
    # Away from its post, it walks back.
    var away = brain.think(
        _sight(Vector3(0, 0, NOTICE + 1), home=Vector3(5, 0, 0)), _frame()
    )
    assert_true(away.way.x > 0.4)
    # Near, it notices, and stares.
    intent = brain.think(_sight(Vector3(0, 0, 8)), _frame())
    assert_true(brain.state == ALERTED)
    assert_true(intent.face)
    assert_almost_equal(brain.timer, ALERT, atol=1e-6)
    _ = brain.think(_sight(Vector3(0, 0, 8)), _frame())
    assert_true(brain.state == ALERTED)
    _ = brain.think(_sight(Vector3(0, 0, 8)), Duration(1.0, SECOND))
    assert_true(brain.state == CLOSING)
    # It runs at a far player and walks at a near one.
    intent = brain.think(_sight(Vector3(0, 0, 8)), _frame())
    assert_true(intent.run)
    assert_true(intent.way.z > 0.9)
    intent = brain.think(_sight(Vector3(0, 0, 5)), _frame())
    assert_false(intent.run)
    # Within its circle, it waits its turn.
    _ = brain.think(_sight(Vector3(0, 0, 3)), _frame())
    assert_true(brain.state == CIRCLING)
    assert_true(brain.timer >= 0.8)


def test_a_bandit_returns_to_its_post() raises:
    # A player who falls, or leads it far from its post, sends it back.
    var brain = _brain(CLOSING)
    var intent = brain.think(
        _sight(Vector3(0, 0, 5), home=Vector3(10, 0, 0), down=True), _frame()
    )
    assert_true(brain.state == RETURNING)
    assert_true(intent.release)
    var led = _brain(CIRCLING)
    intent = led.think(
        _sight(Vector3(0, 0, 3), home=Vector3(0, 0, -LOSE)), _frame()
    )
    assert_true(led.state == RETURNING)
    assert_true(intent.release)
    # A posted bandit stays posted when the player falls.
    var posted = Brain(1)
    _ = posted.think(_sight(Vector3(0, 0, 40), down=True), _frame())
    assert_true(posted.state == POSTED)
    # On the way back, it walks home; a near player alerts it again.
    var going = _brain(RETURNING)
    intent = going.think(
        _sight(Vector3(0, 0, 40), home=Vector3(10, 0, 0), down=True),
        _frame(),
    )
    assert_true(going.state == RETURNING)
    assert_true(intent.way.x > 0.5)
    _ = going.think(_sight(Vector3(0, 0, 40), home=Vector3(10, 0, 0)), _frame())
    assert_true(going.state == RETURNING)
    _ = going.think(_sight(Vector3(0, 0, 4), home=Vector3(10, 0, 0)), _frame())
    assert_true(going.state == ALERTED)
    # At its post, it stands again.
    var home = _brain(RETURNING)
    _ = home.think(_sight(Vector3(0, 0, 40)), _frame())
    assert_true(home.state == POSTED)


def test_a_circling_bandit_steps_round_and_takes_its_turn() raises:
    var brain = _brain(CIRCLING, 5)
    var intent = brain.think(_sight(Vector3(0, 0, CIRCLE)), _frame())
    assert_true(brain.state == CIRCLING)
    # Round the player: across the way to them.
    assert_almost_equal(abs(intent.way.x), 0.5, atol=1e-4)
    assert_true(intent.face)
    # Too far, it closes again.
    _ = brain.think(_sight(Vector3(0, 0, CIRCLE + 3)), _frame())
    assert_true(brain.state == CLOSING)
    # Its wait over, it takes the free token and attacks.
    var turn = _brain(CIRCLING, 0)
    intent = turn.think(_sight(Vector3(0, 0, CIRCLE)), _frame())
    assert_true(turn.state == ATTACKING)
    assert_true(intent.claim)
    assert_true(len(turn.plan) >= 1)
    # Or the token it holds.
    var held = _brain(CIRCLING, 0)
    _ = held.think(
        _sight(Vector3(0, 0, CIRCLE), holds=True, unclaimed=False), _frame()
    )
    assert_true(held.state == ATTACKING)
    # Another holds it: it waits.
    var waits = _brain(CIRCLING, 0)
    intent = waits.think(
        _sight(Vector3(0, 0, CIRCLE), unclaimed=False), _frame()
    )
    assert_true(waits.state == CIRCLING)
    assert_false(intent.claim)
    # Over a long frame it turns the other way round; over none it keeps
    # its way.
    var taken = _sight(Vector3(0, 0, CIRCLE), unclaimed=False)
    var turning = _brain(CIRCLING, 5)
    _ = turning.think(taken, Duration(10.0, SECOND))
    assert_almost_equal(turning.side, -1, atol=1e-6)
    var keeping = _brain(CIRCLING, 5)
    _ = keeping.think(taken, Duration(0.0, SECOND))
    assert_almost_equal(keeping.side, 1, atol=1e-6)


def test_a_waiting_bandit_sometimes_guards_an_attack() raises:
    var guarded = 0
    var waited = 0
    for seed in range(40):
        var brain = Brain(seed)
        brain.state = CIRCLING
        brain.timer = 5
        var intent = brain.think(
            _sight(Vector3(0, 0, 3), threat=True), _frame()
        )
        if brain.state == GUARDING:
            guarded += 1
            assert_true(intent.guard)
            assert_almost_equal(brain.timer, GUARD_TIME, atol=1e-6)
        else:
            waited += 1
    assert_true(guarded > 0)
    assert_true(waited > 0)
    # A far attack, or none, is not guarded.
    var far = _brain(CIRCLING, 5)
    _ = far.think(_sight(Vector3(0, 0, 5), threat=True), _frame())
    assert_true(far.state == CIRCLING)
    # A guard holds for its time, then the bandit waits again.
    var guard = _brain(GUARDING, 0.5)
    var intent = guard.think(_sight(Vector3(0, 0, 3)), _frame())
    assert_true(intent.guard)
    intent = guard.think(_sight(Vector3(0, 0, 3)), Duration(1.0, SECOND))
    assert_false(intent.guard)
    assert_true(guard.state == CIRCLING)


def test_an_attacking_bandit_comes_strikes_and_backs_off() raises:
    var brain = _brain(ATTACKING)
    brain.plan = [LIGHT_ONE, LIGHT_TWO]
    var holds = _sight(Vector3(0, 0, 6), holds=True, unclaimed=False)
    var intent = brain.think(holds, _frame())
    assert_true(intent.run)
    var near = _sight(Vector3(0, 0, 3), holds=True, unclaimed=False)
    intent = brain.think(near, _frame())
    assert_false(intent.run)
    assert_true(intent.way.z > 0.9)
    var close = _sight(Vector3(0, 0, 1.5), holds=True, unclaimed=False)
    intent = brain.think(close, _frame())
    assert_true(intent.attack == LIGHT_ONE)
    # Not ready for the next yet: it waits.
    var busy = _sight(
        Vector3(0, 0, 1.5), ready=False, free=False, holds=True, unclaimed=False
    )
    intent = brain.think(busy, _frame())
    assert_true(intent.attack == FREE)
    intent = brain.think(close, _frame())
    assert_true(intent.attack == LIGHT_TWO)
    # The plan done, it backs off once it is free.
    _ = brain.think(busy, _frame())
    assert_true(brain.state == ATTACKING)
    intent = brain.think(close, _frame())
    assert_true(brain.state == RETREATING)
    assert_true(intent.release)
    assert_almost_equal(brain.timer, RETREAT, atol=1e-6)
    intent = brain.think(close, _frame())
    assert_true(intent.way.z < -0.5)
    _ = brain.think(close, Duration(1.0, SECOND))
    assert_true(brain.state == CIRCLING)
    # Without the token, it waits again.
    var lost = _brain(ATTACKING)
    lost.plan = [HEAVY]
    _ = lost.think(_sight(Vector3(0, 0, 1.5), unclaimed=False), _frame())
    assert_true(lost.state == CIRCLING)


def test_a_blow_breaks_off_an_attack() raises:
    var brain = _brain(ATTACKING)
    assert_true(brain.hurt())
    assert_true(brain.state == RETREATING)
    assert_false(brain.hurt())
    # A bandit on the player's feet still knows a way to face.
    var close = _brain(CLOSING)
    _ = close.think(_sight(Vector3(0, 0, 0)), _frame())
    assert_true(close.state == CIRCLING)


def test_bandits_and_dummies_have_their_strength() raises:
    var bandit = bandit_fighter()
    bandit.check()
    assert_almost_equal(bandit.health, 300, atol=1e-6)
    assert_almost_equal(bandit.might, 0.55, atol=1e-6)
    assert_almost_equal(bandit.parry.to(SECOND), 0, atol=1e-6)
    var dummy = dummy_fighter()
    dummy.check()
    assert_almost_equal(dummy.guard_arc.to(DEGREE), 0, atol=1e-6)
    var captain = captain_fighter()
    captain.check()
    assert_true(captain.health > bandit.health)
    assert_true(captain.might > bandit.might)
    var bandits = default_bandits()
    assert_equal(len(bandits), 4)
    assert_true(len(bandits[0].outfit.garments) >= 4)
    assert_almost_equal(bandits[3].fighter.health, captain.health, atol=1e-6)
    assert_equal(len(default_posts()), 2)


def test_a_dummy_rocks_back_upright() raises:
    var assets = Assets()
    var scene = Scene()
    var looks = house_looks(assets, 4, 1)
    var dummy = Dummy(
        scene, assets, looks, Post(2, 3, Angle(30.0, DEGREE)), 0.5
    )
    assert_equal(len(scene.meshes), 3)
    assert_almost_equal(dummy.where().y, 0.5, atol=1e-6)
    # Upright, it does not lean.
    dummy.rock(scene, _frame())
    assert_almost_equal(scene.node(dummy.pivot).quaternion.w, 1, atol=1e-6)
    # A blow along +z tips its top toward +z.
    dummy.knock(Vector3(0, 0, 1), 4)
    assert_true(dummy.spin.x > 0)
    var leaned = Float32(0)
    for _ in range(5):
        dummy.rock(scene, Duration(0.02, SECOND))
        leaned = max(leaned, dummy.tilt.length())
    assert_true(leaned > 0.05)
    assert_true(scene.node(dummy.pivot).quaternion.w < 1)
    # It comes to rest.
    for _ in range(300):
        dummy.rock(scene, Duration(0.02, SECOND))
    assert_true(dummy.tilt.length() < 0.01)


def test_a_wolf_bites_and_leaps_back_from_attacks() raises:
    var wolf = Brain.wolf(4)
    assert_true(wolf.beast)
    # It notices the player from further than a bandit does.
    _ = wolf.think(_sight(Vector3(0, 0, WOLF_NOTICE - 1)), _frame())
    assert_true(wolf.state == ALERTED)
    # Its turn come, it bites.
    var turn = Brain.wolf(4)
    turn.state = CIRCLING
    _ = turn.think(_sight(Vector3(0, 0, WOLF_CIRCLE)), _frame())
    assert_true(turn.state == ATTACKING)
    assert_equal(len(turn.plan), 1)
    assert_true(turn.plan[0] == BITE)
    # Where a bandit would guard, a wolf leaps back.
    var leapt = 0
    for seed in range(40):
        var shy = Brain.wolf(seed)
        shy.state = CIRCLING
        shy.timer = 5
        var intent = shy.think(_sight(Vector3(0, 0, 3), threat=True), _frame())
        if shy.state == RETREATING:
            leapt += 1
            assert_false(intent.guard)
            assert_true(intent.way.z < 0)
    assert_true(leapt > 0)
    # Wolves are wild and weaker than bandits, and keep a den.
    var p = wolf_fighter()
    p.check()
    assert_true(p.health < bandit_fighter().health)
    var dens = default_dens()
    assert_equal(len(dens), 1)
    var places = den_places(dens[0])
    assert_equal(len(places), 3)
    assert_almost_equal(places[0].x, dens[0].x, atol=1e-6)
    assert_almost_equal((places[1] - places[0]).length(), 1.8, atol=1e-4)
    # A den of no wolves has no places.
    var empty = dens[0].copy()
    empty.count = 0
    assert_equal(len(den_places(empty)), 0)


def test_a_raging_bandit_rolls_its_plans_high() raises:
    var twos = 0
    for seed in range(40):
        var calm = _brain(CIRCLING, 0)
        calm.seed = seed
        _ = calm.think(_sight(Vector3(0, 0, CIRCLE)), _frame())
        if len(calm.plan) == 2 and calm.plan[1] == LIGHT_TWO:
            twos += 1
        var mad = _brain(CIRCLING, 0)
        mad.seed = seed
        _ = mad.think(_sight(Vector3(0, 0, CIRCLE), raging=True), _frame())
        assert_true(mad.state == ATTACKING)
        assert_false(len(mad.plan) == 2 and mad.plan[1] == LIGHT_TWO)
    assert_true(twos > 0)
    # The captain rages at half its health; a bandit never does.
    assert_almost_equal(captain_fighter().rage, 0.5, atol=1e-6)
    assert_almost_equal(bandit_fighter().rage, 0, atol=1e-6)


def test_a_threatened_bandit_guards_or_sidesteps() raises:
    var guards = 0
    var steps = 0
    for seed in range(60):
        var brain = _brain(CIRCLING, 5)
        brain.seed = seed
        var intent = brain.think(
            _sight(Vector3(0, 0, 3), threat=True), _frame()
        )
        if brain.state == GUARDING:
            guards += 1
            assert_true(intent.guard)
        elif intent.dodge.length() > 0:
            steps += 1
            assert_true(brain.state == CIRCLING)
            # Across the way to the player.
            assert_almost_equal(intent.dodge.z, 0, atol=1e-6)
            assert_almost_equal(abs(intent.dodge.x), 1, atol=1e-6)
    assert_true(guards > 0)
    assert_true(steps > 0)
    assert_true(steps < guards)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
