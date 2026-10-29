# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Things a player gathers about the village: herbs, mushrooms, berries,
ore, a chest and trinkets."""

from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.ground import Ground, Lot, Pond
from extensions.village.gathering import (
    BERRIES,
    BITE,
    BITING,
    CAST,
    CHEST,
    CHEST_COINS,
    FISH,
    IDLE,
    WAITING,
    GatherKind,
    GatherParameters,
    Gathering,
    HERBS,
    KINDS,
    LID_OPEN,
    MUSHROOMS,
    ORE,
    STRIKES,
    Satchel,
    Spot,
    TRINKET,
    TRINKET_LIFT,
    default_spots,
    kind_name,
    respawns,
    solid_radius,
)
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
from units.si import METER, RADIAN, SECOND, Angle, Duration, Length


def test_the_kinds_are_named_and_checked() raises:
    assert_true(TRINKET.is_valid())
    assert_false(GatherKind(KINDS).is_valid())
    assert_false(GatherKind(-1).is_valid())
    assert_equal(kind_name(HERBS), "herbs")
    assert_equal(kind_name(CHEST), "coins")
    assert_equal(kind_name(TRINKET), "trinkets")
    assert_equal(kind_name(FISH), "fish")
    assert_true(respawns(FISH))
    assert_equal(solid_radius(FISH), 0)
    with assert_raises(contains="one of the seven"):
        _ = kind_name(GatherKind(9))
    # A chest and a trinket are found once; the rest come back.
    assert_false(respawns(CHEST))
    assert_false(respawns(TRINKET))
    assert_true(respawns(HERBS))
    assert_true(respawns(ORE))
    # A boulder, a chest and a bush are solid.
    assert_almost_equal(solid_radius(ORE), 0.6, atol=1e-6)
    assert_almost_equal(solid_radius(CHEST), 0.45, atol=1e-6)
    assert_almost_equal(solid_radius(BERRIES), 0.4, atol=1e-6)
    assert_equal(solid_radius(MUSHROOMS), 0)


def test_a_spot_and_a_satchel_are_checked() raises:
    Spot(HERBS, 3, -4, Angle(0.0, RADIAN)).check()
    with assert_raises(contains="one of the seven"):
        Spot(GatherKind(7), 0, 0, Angle(0.0, RADIAN)).check()
    with assert_raises(contains="10 kilometers"):
        Spot(HERBS, 2.0e4, 0, Angle(0.0, RADIAN)).check()
    with assert_raises(contains="10 kilometers"):
        Spot(HERBS, 0, -2.0e4, Angle(0.0, RADIAN)).check()
    var satchel = Satchel()
    assert_equal(satchel.total(), 0)
    satchel.counts[ORE.value] = 2
    satchel.counts[HERBS.value] = 1
    assert_equal(satchel.count(ORE), 2)
    assert_equal(satchel.total(), 3)
    with assert_raises(contains="one of the seven"):
        _ = satchel.count(GatherKind(7))
    # The default village has a spot of every kind.
    var spots = default_spots()
    for k in range(KINDS):
        var found = False
        for spot in spots:
            if spot.kind.value == k:
                found = True
        assert_true(found)
    var parameters = GatherParameters()
    assert_equal(len(parameters.spots), len(spots))
    assert_almost_equal(parameters.reach.to(METER), 1.8, atol=1e-6)
    assert_almost_equal(parameters.respawn.to(SECOND), 60, atol=1e-6)


def _spots() -> List[Spot]:
    """Return a spot of each kind in a row along x, 4 meters apart, and
    two more trinkets, so both gems are drawn."""
    var out = List[Spot]()
    for k in range(KINDS):
        out.append(Spot(GatherKind(k), Float32(4 * k), 0, Angle(0.5, RADIAN)))
    out.append(Spot(TRINKET, 28, 0, Angle(0.0, RADIAN)))
    out.append(Spot(TRINKET, 32, 0, Angle(0.0, RADIAN)))
    return out^


def _gathering(
    mut scene: Scene, mut assets: Assets, var spots: List[Spot]
) raises -> Gathering:
    """Build a gathering of some spots on level, dry ground."""
    var parameters = GatherParameters()
    parameters.spots = spots^
    parameters.respawn = Duration(2.0, SECOND)
    var looks = house_looks(assets, 4, 1)
    return Gathering(scene, assets, looks, parameters, Ground(), List[Lot]())


def test_every_kind_is_drawn_and_the_solid_ones_stop() raises:
    var assets = Assets()
    var scene = Scene()
    var gathering = _gathering(scene, assets, _spots())
    assert_equal(len(gathering.spots), KINDS + 2)
    assert_true(gathering.triangles > 1000)
    assert_equal(gathering.meshes, len(scene.meshes))
    assert_equal(gathering.focus, -1)
    # The marker hides until a spot can be used.
    assert_false(scene.node(gathering.marker).visible)
    var solid = gathering.obstacles()
    assert_equal(len(solid), 3)
    assert_almost_equal(solid[0].x, 8, atol=1e-6)
    # Each spot stands on the ground and is ready.
    var ground = Ground()
    for g in gathering.spots:
        assert_almost_equal(g.foot, ground.height_at(g.spot.x, 0), atol=1e-5)
        assert_true(g.ready)
    # A trinket hangs in the air.
    assert_true(gathering.spots[5].top > TRINKET_LIFT)


def test_a_spot_on_a_lot_or_in_the_water_is_left_out() raises:
    var assets = Assets()
    var scene = Scene()
    var parameters = GatherParameters()
    parameters.spots = [
        Spot(HERBS, 0, 0, Angle(0.0, RADIAN)),
        Spot(HERBS, 10, 0, Angle(0.0, RADIAN)),
        Spot(HERBS, 0, 30, Angle(0.0, RADIAN)),
    ]
    var ground = Ground(
        pond=Pond(
            Length(10.0, METER),
            Length(0.0, METER),
            Length(4.0, METER),
            Length(1.0, METER),
        )
    )
    var lots: List[Lot] = [Lot(0, 30, 3, 3, 0)]
    var gathering = Gathering(
        scene, assets, house_looks(assets, 4, 1), parameters, ground, lots
    )
    assert_equal(len(gathering.spots), 1)
    assert_equal(gathering.spots[0].spot.x, 0)
    # No spot at all draws only the marker.
    var empty = GatherParameters()
    empty.spots = []
    var none = Gathering(
        scene, assets, house_looks(assets, 4, 1), empty, ground, lots
    )
    assert_equal(len(none.spots), 0)
    assert_equal(len(none.obstacles()), 0)
    assert_equal(none.meshes, 1)
    assert_equal(none.nearest(Vector3(0, 0, 0)), -1)
    _ = none.update(scene, Vector3(0, 0, 0), True, Duration(0.1, SECOND))


def test_a_gathering_refuses_a_bad_spot_reach_or_respawn() raises:
    var assets = Assets()
    var scene = Scene()
    var looks = house_looks(assets, 4, 1)
    var bad = GatherParameters()
    bad.spots = [Spot(GatherKind(12), 0, 0, Angle(0.0, RADIAN))]
    with assert_raises(contains="one of the seven"):
        _ = Gathering(scene, assets, looks, bad, Ground(), List[Lot]())
    var far = GatherParameters()
    far.reach = Length(-1.0, METER)
    with assert_raises(contains="must not be negative"):
        _ = Gathering(scene, assets, looks, far, Ground(), List[Lot]())
    var never = GatherParameters()
    never.respawn = Duration(-1.0, SECOND)
    with assert_raises(contains="must not be negative"):
        _ = Gathering(scene, assets, looks, never, Ground(), List[Lot]())
    var gathering = _gathering(scene, assets, _spots())
    with assert_raises(contains="negative"):
        _ = gathering.update(
            scene, Vector3(0, 0, 0), False, Duration(-1.0, SECOND)
        )


def _at(g: Gathering, index: Int, dx: Float32) -> Vector3:
    """Return feet standing `dx` meters along x from a spot."""
    ref spot = g.spots[index]
    return Vector3(spot.spot.x + dx, spot.foot, spot.spot.z)


def test_the_nearest_ready_spot_in_reach_is_the_focus() raises:
    var assets = Assets()
    var scene = Scene()
    var gathering = _gathering(scene, assets, _spots())
    # Between the herbs and the mushrooms, nearer the mushrooms.
    assert_equal(gathering.nearest(_at(gathering, 0, 2.4)), 1)
    assert_equal(gathering.nearest(_at(gathering, 0, 1.0)), 0)
    # Out of reach, or too far above, nothing.
    assert_equal(gathering.nearest(_at(gathering, 0, -2.0)), -1)
    var high = _at(gathering, 0, 0.5)
    high.y += 2
    assert_equal(gathering.nearest(high), -1)
    # The marker hangs over the focus once the frame runs.
    _ = gathering.update(
        scene, _at(gathering, 0, 0.5), False, Duration(0.1, SECOND)
    )
    assert_equal(gathering.focus, 0)
    ref marker = scene.node(gathering.marker)
    assert_true(marker.visible)
    assert_almost_equal(marker.position.x, 0, atol=1e-6)
    assert_true(marker.position.y > gathering.spots[0].foot)


def _press(
    mut gathering: Gathering, mut scene: Scene, feet: Vector3
) raises -> Bool:
    """Press and let go of the use button; return whether the press
    gathered something."""
    var step = Duration(0.05, SECOND)
    var got = gathering.update(scene, feet, True, step)
    _ = gathering.update(scene, feet, False, step)
    return Bool(got)


def test_a_press_gathers_herbs_mushrooms_and_berries() raises:
    var assets = Assets()
    var scene = Scene()
    var gathering = _gathering(scene, assets, _spots())
    var step = Duration(0.05, SECOND)
    var feet = _at(gathering, 0, 0.5)
    # A held button gathers once, on its press.
    var got = gathering.update(scene, feet, True, step)
    assert_true(Bool(got))
    assert_true(got.value() == HERBS)
    assert_false(Bool(gathering.update(scene, feet, True, step)))
    assert_equal(gathering.satchel.count(HERBS), 1)
    assert_equal(gathering.satchel.last, 1)
    assert_false(gathering.spots[0].ready)
    assert_false(scene.node(gathering.spots[0].node).visible)
    assert_false(scene.node(gathering.spots[0].glint).visible)
    # A press with nothing in reach gathers nothing.
    _ = gathering.update(scene, feet, False, step)
    assert_false(_press(gathering, scene, feet))
    assert_false(scene.node(gathering.marker).visible)
    assert_true(_press(gathering, scene, _at(gathering, 1, 0.5)))
    assert_equal(gathering.satchel.count(MUSHROOMS), 2)
    assert_true(_press(gathering, scene, _at(gathering, 2, 0.8)))
    assert_equal(gathering.satchel.count(BERRIES), 3)
    assert_equal(gathering.satchel.last, 3)
    # After the respawn time the herbs come back.
    for _ in range(50):
        _ = gathering.update(scene, Vector3(100, 0, 100), False, step)
    assert_true(gathering.spots[0].ready)
    assert_equal(gathering.spots[0].wait, 0)
    assert_true(scene.node(gathering.spots[0].node).visible)
    assert_true(scene.node(gathering.spots[0].glint).visible)


def test_a_boulder_takes_strikes_and_a_chest_opens_once() raises:
    var assets = Assets()
    var scene = Scene()
    var gathering = _gathering(scene, assets, _spots())
    var rock = _at(gathering, 3, 0.9)
    for _ in range(STRIKES - 1):
        assert_false(_press(gathering, scene, rock))
    assert_equal(gathering.spots[3].strikes, STRIKES - 1)
    assert_true(_press(gathering, scene, rock))
    assert_equal(gathering.satchel.count(ORE), 1)
    assert_equal(gathering.spots[3].strikes, 0)
    var chest = _at(gathering, 4, 0.9)
    assert_true(_press(gathering, scene, chest))
    assert_equal(gathering.satchel.count(CHEST), CHEST_COINS)
    # The lid swings open over a second, and stays open.
    var step = Duration(0.1, SECOND)
    for _ in range(30):
        _ = gathering.update(scene, chest, False, step)
    assert_almost_equal(gathering.spots[4].lid, LID_OPEN, atol=1e-6)
    assert_false(gathering.spots[4].ready)
    assert_false(_press(gathering, scene, chest))
    # A trinket is taken once.
    var trinket = _at(gathering, 5, 0.5)
    assert_true(_press(gathering, scene, trinket))
    assert_false(_press(gathering, scene, trinket))
    assert_equal(gathering.satchel.count(TRINKET), 1)
    assert_equal(gathering.satchel.total(), 1 + CHEST_COINS + 1)


def test_a_trinket_bobs_and_turns() raises:
    var assets = Assets()
    var scene = Scene()
    var gathering = _gathering(scene, assets, _spots())
    var far = Vector3(100, 0, 100)
    var lowest = Float32(10)
    var highest = Float32(-10)
    for _ in range(30):
        _ = gathering.update(scene, far, False, Duration(0.1, SECOND))
        var y = scene.node(gathering.spots[5].node).position.y
        lowest = min(lowest, y)
        highest = max(highest, y)
    assert_true(highest - lowest > 0.1)
    assert_true(lowest > TRINKET_LIFT - 0.1)


def test_a_fish_is_cast_for_waited_on_and_hooked() raises:
    var assets = Assets()
    var scene = Scene()
    var gathering = _gathering(scene, assets, _spots())
    assert_true(gathering.spots[6].spot.kind == FISH)
    var hinge = gathering.spots[6].hinge
    var foot = gathering.spots[6].foot
    var shore = _at(gathering, 6, 0.5)
    assert_false(scene.node(hinge).visible)
    # The float lies on the water, out along the spot's turn.
    assert_almost_equal(scene.node(hinge).position.x, CAST, atol=1e-6)
    var step = Duration(0.1, SECOND)
    # Cast: the float shows, and a fish bites in two to six seconds.
    assert_false(_press(gathering, scene, shore))
    assert_equal(gathering.spots[6].phase, WAITING)
    assert_true(scene.node(hinge).visible)
    assert_true(gathering.spots[6].timer >= 2)
    # Reel in before it bites: nothing.
    assert_false(_press(gathering, scene, shore))
    assert_equal(gathering.spots[6].phase, IDLE)
    assert_false(scene.node(hinge).visible)
    # Cast again, and wait for the bite.
    assert_false(_press(gathering, scene, shore))
    var waited = 0
    while gathering.spots[6].phase == WAITING and waited < 100:
        _ = gathering.update(scene, shore, False, step)
        waited += 1
    assert_equal(gathering.spots[6].phase, BITING)
    assert_true(scene.node(hinge).position.y < gathering.water - foot)
    # Hook it.
    assert_true(_press(gathering, scene, shore))
    assert_equal(gathering.satchel.count(FISH), 1)
    assert_equal(gathering.spots[6].phase, IDLE)
    # The spot stays ready, so a player can fish again.
    assert_true(gathering.spots[6].ready)
    # A bite missed lets the fish get away.
    assert_false(_press(gathering, scene, shore))
    for _ in range(100):
        if gathering.spots[6].phase == BITING:
            break
        _ = gathering.update(scene, shore, False, step)
    for _ in range(Int(BITE / 0.1) + 2):
        _ = gathering.update(scene, shore, False, step)
    assert_equal(gathering.spots[6].phase, IDLE)
    assert_equal(gathering.satchel.count(FISH), 1)
    # Walking away reels the line in.
    assert_false(_press(gathering, scene, shore))
    _ = gathering.update(scene, Vector3(100, 0, 100), False, step)
    assert_equal(gathering.spots[6].phase, IDLE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
