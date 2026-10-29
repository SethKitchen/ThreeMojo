# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village: scanned buildings cut out of their ground, and the meadow
with its houses, its pond and its water. The houses have suites of their
own: see `test_village_house.mojo` and `test_village_house_view.mojo`."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from core.scene import Scene
from extensions.building.material import brick
from extensions.scan.frame import supersplat_frame
from extensions.vegetation.field import LodBand
from extensions.vegetation.ground import (
    Ground,
    Lot,
    Pond,
    lot_openness,
    no_pond,
)
from extensions.vegetation.meadow import MeadowParameters, Planting
from extensions.village.house import (
    BARN,
    BOARDED,
    DWELLING,
    HouseParameters,
    OUTSIDE_WALL,
    STONE_FACADE,
    TIMBER_FRAMED,
)
from extensions.scan.occupancy import ScanRegion
from extensions.village.scanned import (
    MAX_VOXELS,
    SINK,
    cut_building,
    grid_voxel,
    linear_splats,
    scan_lot,
    stand_scan,
)
from extensions.village.props import (
    CRATE,
    FENCE,
    WELL,
    WOODPILE,
    WOODPILE_DEPTH,
    Prop,
)
from extensions.village.interior import Doorway, PLINTH_OVERHANG
from extensions.village.village import (
    HousePlacement,
    PATH_OUT,
    PATH_WIDTH,
    Village,
    VillageParameters,
    door_path,
    default_props,
    hearthed,
    oak,
    woodpile_by,
)
from extensions.water.pebbles import pebble_bed
from extensions.water.resolution import SpectrumResolution
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.srgb import SRGB
from render.png import DecodedImage
from renderers.renderer import Renderer
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
)


def _house(storeys: Int) -> HouseParameters:
    """Return a small brick house, 5 by 4 meters, of `storeys`."""
    return HouseParameters(
        "test house", Length(5.0, METER), Length(4.0, METER), storeys, brick()
    )


def _splat(
    mut centers: List[Float32],
    mut covariances: List[Float32],
    mut colors: List[UInt8],
    x: Float32,
    y: Float32,
    z: Float32,
    color: UInt8,
):
    """Add one small round splat at a building point; in SuperSplat's
    frame building x, y and z are scan -x, -z and -y."""
    centers.extend([-x, -z, -y])
    covariances.extend([0.04, 0, 0, 0.04, 0, 0.04])
    colors.extend([color, color, color, 240])


def _scan(building: Bool) -> GaussianSplatGeometry:
    """Return a test scan in SuperSplat's frame: flat ground 16 meters on a
    side, and on it, with `building`, a box 4 by 3 meters and 3 meters
    tall, with its middle at (1, 2)."""
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    for a in range(33):
        for b in range(33):
            _splat(
                centers,
                covariances,
                colors,
                Float32(a) * 0.5 - 8,
                Float32(b) * 0.5 - 8,
                0,
                120,
            )
    if building:
        for k in range(7):
            var z = Float32(k) * 0.5
            for a in range(9):
                var x = Float32(a) * 0.5 - 1
                _splat(centers, covariances, colors, x, 0.5, z, 200)
                _splat(centers, covariances, colors, x, 3.5, z, 200)
            for b in range(7):
                var y = Float32(b) * 0.5 + 0.5
                _splat(centers, covariances, colors, -1, y, z, 200)
                _splat(centers, covariances, colors, 3, y, z, 200)
        for a in range(9):
            for b in range(7):
                _splat(
                    centers,
                    covariances,
                    colors,
                    Float32(a) * 0.5 - 1,
                    Float32(b) * 0.5 + 0.5,
                    3,
                    200,
                )
    try:
        return create_gaussian_splat_geometry(centers^, covariances^, colors^)
    except:
        return GaussianSplatGeometry()


def test_a_building_is_cut_out_of_its_scan() raises:
    """The cut keeps the box and leaves the ground: its footprint is the
    box's, give or take a voxel, and it holds fewer splats than the scan.
    A scan of bare ground has no building."""
    var scan = _scan(True)
    var cut = cut_building(scan, supersplat_frame(), Length(0.5, METER))
    var wide = cut.region.high.x - cut.region.low.x
    var deep = cut.region.high.y - cut.region.low.y
    assert_true(wide > 3 and wide < 5.5)
    assert_true(deep > 2 and deep < 4.5)
    assert_true(cut.splats.count() > 100)
    assert_true(cut.splats.count() < scan.count())
    with assert_raises(contains="no building"):
        _ = cut_building(_scan(False), supersplat_frame(), Length(0.5, METER))


def test_a_large_scan_gets_larger_voxels() raises:
    """A box small enough for its voxel keeps it. A box too large doubles
    the voxel until its grid holds at most `MAX_VOXELS`, counted in whole
    voxels as the grid lays them. A voxel that is not positive and finite
    is refused."""
    var small = ScanRegion(Vec3d(0, 0, 0), Vec3d(16, 16, 4))
    assert_almost_equal(grid_voxel(small, Length(0.5, METER)).to(METER), 0.5)
    var large = ScanRegion(Vec3d(0, 0, 0), Vec3d(1000, 1000, 100))
    var edge = grid_voxel(large, Length(0.1, METER)).to(METER)
    assert_almost_equal(edge, 3.2, atol=1e-6)
    assert_true(313 * 313 * 32 <= MAX_VOXELS)
    assert_true(625 * 625 * 63 > MAX_VOXELS)
    with assert_raises(contains="voxel"):
        _ = grid_voxel(small, Length(0.0, METER))
    with assert_raises(contains="voxel"):
        _ = grid_voxel(small, Length(Float32.MAX * 2, METER))


def test_linear_splats_turn_colors_to_light() raises:
    """Each color byte becomes linear light, opacity is kept, and the
    spherical harmonics are left out."""
    var geometry = create_gaussian_splat_geometry(
        [Float32(0), 0, 0],
        [Float32(0.01), 0, 0, 0.01, 0, 0.01],
        [UInt8(255), 128, 0, 200],
        List[UInt8](length=12, fill=128),
    )
    var light = linear_splats(geometry)
    assert_equal(Int(light.colors[0]), 255)
    assert_equal(Int(light.colors[1]), 55)
    assert_equal(Int(light.colors[2]), 0)
    assert_equal(Int(light.colors[3]), 200)
    assert_equal(light.spherical_harmonics_degree(), 0)
    assert_equal(geometry.spherical_harmonics_degree(), 1)


def test_a_scan_stands_on_its_lot() raises:
    """A scanned building's lot is its footprint, turned. It stands as one
    splat object, its footprint's middle at the point, and its foot just
    below the ground."""
    var cut = cut_building(_scan(True), supersplat_frame(), Length(0.5, METER))
    var lot = scan_lot(cut, -4, 6, Angle(0.5, RADIAN))
    assert_almost_equal(
        lot.half_width,
        Float32((cut.region.high.x - cut.region.low.x) / 2),
        atol=1e-5,
    )
    var scene = Scene()
    var ground = Ground()
    var stood = stand_scan(scene, cut, -4, 6, Angle(0.5, RADIAN), ground)
    assert_almost_equal(stood.half_depth, lot.half_depth)
    assert_equal(len(scene.gaussian_splats), 1)
    scene.update()
    ref splat = scene.gaussian_splats[0][]
    var world = scene.world_matrix(splat.node)
    var low = Float32(1.0e30)
    var mean = Vector3(0, 0, 0)
    var count = splat.splat_geometry.count()
    for index in range(count):
        ref c = splat.splat_geometry.centers
        var p = world.transform_point(
            Vector3(c[index * 3], c[index * 3 + 1], c[index * 3 + 2])
        )
        low = min(low, p.y)
        mean = mean + p / Float32(count)
    assert_true(abs(mean.x + 4) < 0.6)
    assert_true(abs(mean.z - 6) < 0.6)
    var foot = ground.height_at(-4, 6) - SINK
    assert_true(abs(low - foot) < 0.8)


def _parameters() raises -> VillageParameters:
    """Return a village small enough to build in a test: a field 16 meters
    across, a pond, one small house, and small water."""
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
    p.houses = [HousePlacement(_house(1), 5, -4, Angle(10.0, DEGREE))]
    p.props = [
        Prop(WELL, -6, -1, Angle(0.0, DEGREE), 0.8),
        Prop(FENCE, 3, 5, Angle(0.0, DEGREE), 4),
    ]
    p.scan_x = -5
    p.scan_z = -4
    p.ocean = SpectrumResolution(16)
    p.caustic_grid = 8
    p.caustic_resolution = 16
    p.glare = SpectrumResolution(16)
    return p^


def _bed() raises -> DecodedImage:
    """Return a gray pebble photograph 4 pixels on a side."""
    return DecodedImage(4, 4, List[UInt8](length=64, fill=128), SRGB)


def _refused(p: VillageParameters, text: String) raises:
    """Assert that the village is refused with `text`."""
    with assert_raises(contains=text):
        p.check()


def test_village_parameters_are_checked() raises:
    """The default village passes, with a pond and five houses, the second
    of them a barn; each field out of range is refused, and so is a meadow
    or a house its own check refuses."""
    var village = VillageParameters()
    village.check()
    assert_equal(len(village.houses), 5)
    for k in range(5):
        var use = BARN if k == 1 else DWELLING
        assert_true(village.houses[k].house.use == use)
    # The default props, and a woodpile by the brick house's and the stone
    # cottage's hearths.
    assert_equal(len(village.props), len(default_props()) + 2)
    for k in range(len(default_props()), len(village.props)):
        assert_true(village.props[k].kind == WOODPILE)
    assert_true(village.meadow.ground.pond.radius.to(METER) > 0)
    var p = VillageParameters()
    p.meadow.rocks = 2000
    _refused(p, "boulders")
    p = VillageParameters()
    for _ in range(63):
        p.houses.append(HousePlacement(_house(1), 0, 0, Angle(0.0, DEGREE)))
    _refused(p, "houses")
    p = VillageParameters()
    p.houses[0].house.width = Length(1.0, METER)
    _refused(p, "wide")
    p = VillageParameters()
    for _ in range(1000):
        p.props.append(Prop(CRATE, 0, 0, Angle(0.0, DEGREE), 1))
    _refused(p, "props")
    p = VillageParameters()
    p.props[0].length = 100
    _refused(p, "long")
    p = VillageParameters()
    p.houses[0].x = 2.0e4
    _refused(p, "A house must stand")
    p = VillageParameters()
    p.houses[0].z = -2.0e4
    _refused(p, "A house must stand")
    p = VillageParameters()
    p.scan_z = 2.0e4
    _refused(p, "A scanned building must stand")
    p = VillageParameters()
    p.ocean = SpectrumResolution(3)
    _refused(p, "resolution")
    p = VillageParameters()
    p.glare = SpectrumResolution(512)
    _refused(p, "resolution")
    p = VillageParameters()
    p.caustic_grid = 2
    _refused(p, "caustic grid")
    p = VillageParameters()
    p.caustic_resolution = 5000
    _refused(p, "caustic texture")


def test_a_village_stands_its_buildings_and_draws_its_pond() raises:
    """A village stands its houses and its scanned building on lots where
    nothing grows. Its water's clock moves on to a later frame and stays
    for an earlier one. Its pond shows in a frame that looks into it. A
    village with no houses and no scan has no lot."""
    var renderer = Renderer(32, 18)
    var assets = Assets()
    var scene = Scene()
    var p = _parameters()
    var cut = cut_building(_scan(True), supersplat_frame(), Length(0.5, METER))
    var village = Village(scene, assets, renderer, p, pebble_bed(_bed()), cut^)
    assert_equal(len(village.houses), 1)
    assert_true(Bool(village.scanned))
    # The house, its footpath's legs, and the scanned building.
    var door = village.houses[0].interior.front_door()
    var legs = len(door_path(door, village.meadow.field.ground))
    assert_true(legs >= 1)
    assert_equal(len(village.meadow.field.lots), 2 + legs)
    # The house's front door opens: its doorway and its hinge are the
    # village's door.
    assert_equal(len(village.doors.ways), 1)
    assert_true(village.doors.ways[0].outside)
    # The terrain holds the house's walls, its floor and its furniture,
    # and the scanned building as a solid lot.
    var terrain = village.terrain()
    ref inside = village.houses[0].interior
    # The house's walls and furniture and the fence; the well and the
    # scanned building.
    assert_equal(
        len(terrain.walls), len(inside.walls) + len(inside.furniture) + 1
    )
    assert_equal(len(terrain.floors), len(inside.floors))
    assert_equal(len(terrain.lots), 2)
    assert_almost_equal(
        terrain.height_at(5, -4, inside.floor_height),
        inside.floor_height,
        atol=1e-6,
    )
    assert_almost_equal(village.meadow.field.cover_at(5, -4), 0)
    assert_almost_equal(village.meadow.field.cover_at(-5, -4), 0)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(300.0, METER),
    )
    camera.place(Vector3(0, 6, 10), Vector3(0, -1, 4))
    _ = village.update(scene, assets, camera, Duration(6.0, SECOND))
    assert_almost_equal(village.water.clock.to(SECOND), 6, atol=1e-5)
    _ = village.update(scene, assets, camera, Duration(1.0, SECOND))
    assert_almost_equal(village.water.clock.to(SECOND), 6, atol=1e-5)
    var dry = renderer.render(scene, assets, camera)
    var wet = village.render(renderer, scene, assets, camera)
    assert_equal(wet.width, 32)
    var changed = 0
    for index in range(len(wet.pixels)):
        if wet.pixels[index] != dry.pixels[index]:
            changed += 1
    assert_true(changed > 0)
    # The camera sees the pond at (0, 4); one that looks away does not.
    assert_true(village.pond_seen(camera))
    var away = camera
    away.place(Vector3(0, 6, 10), Vector3(0, 6, 30))
    assert_false(village.pond_seen(away))
    var bare = Scene()
    var empty = _parameters()
    empty.houses = []
    empty.props = []
    empty.meadow.ground.pond = no_pond()
    var plain = Village(bare, assets, renderer, empty, pebble_bed(_bed()), None)
    assert_false(Bool(plain.scanned))
    assert_equal(len(plain.houses), 0)
    assert_equal(len(plain.meadow.field.lots), 0)
    assert_equal(len(plain.doors.ways), 0)
    var open = plain.terrain()
    assert_equal(len(open.walls) + len(open.floors) + len(open.lots), 0)
    # A village with no pond has no water to see.
    assert_false(plain.pond_seen(camera))


def test_a_footpath_leads_from_a_front_door_to_the_trail() raises:
    # A door a meter wide along x at (2, 4), that swings into its house
    # toward -z: its path runs out along +z.
    var door = Doorway(2, 4, 1, 0, 0, -1, 1, 2.1, 0, True)
    var trail = Ground(
        hill_height=Length(0.0, METER), trail_width=Length(1.2, METER)
    )
    var legs = door_path(door, trail)
    assert_equal(len(legs), 2)
    assert_almost_equal(legs[0].half_width, PATH_OUT / 2, atol=1e-5)
    assert_almost_equal(legs[0].half_depth, PATH_WIDTH / 2, atol=1e-5)
    var first: List[Lot] = [legs[0]]
    assert_equal(lot_openness(first, 2.5, 4 + PATH_OUT / 2), 0)
    assert_equal(lot_openness(first, 4.5, 4 + PATH_OUT / 2), 1)
    # The second leg starts where the first ends and ends on the trail's
    # middle.
    ref second = legs[1]
    var c = cos(second.turn)
    var s = sin(second.turn)
    var start_x = second.x - c * second.half_width
    var start_z = second.z + s * second.half_width
    var end_x = second.x + c * second.half_width
    var end_z = second.z - s * second.half_width
    assert_almost_equal(start_x, 2.5, atol=1e-3)
    assert_almost_equal(start_z, 4 + PATH_OUT, atol=1e-3)
    assert_almost_equal(end_x, trail.trail_x(end_z), atol=1e-3)
    # With no trail, or a trail too far away, only the first leg.
    var open = Ground(hill_height=Length(0.0, METER))
    assert_equal(len(door_path(door, open)), 1)
    var far = Doorway(200, 4, 1, 0, 0, -1, 1, 2.1, 0, True)
    assert_equal(len(door_path(far, trail)), 1)


def test_the_village_s_old_trees_grow_as_oaks() raises:
    var meadow = MeadowParameters()
    var village = VillageParameters()
    ref plain = meadow.crowns[0]
    ref grown = village.meadow.crowns[0]
    # Twice as thick from the twigs down, and flared twice as much.
    assert_almost_equal(
        grown.limbs.tip_radius.to(METER),
        2 * plain.limbs.tip_radius.to(METER),
        atol=1e-7,
    )
    assert_almost_equal(grown.limbs.flare, 2 * plain.limbs.flare, atol=1e-6)
    assert_almost_equal(
        grown.wood_radius.to(METER), 2 * plain.wood_radius.to(METER), atol=1e-7
    )
    # Brown bark, furrowed four times as close.
    assert_true(grown.bark.x > grown.bark.z)
    assert_true(grown.bark.x < plain.bark.x)
    assert_almost_equal(
        grown.bark_marks.to(PER_METER),
        4 * plain.bark_marks.to(PER_METER),
        atol=1e-5,
    )
    grown.check()
    # The birches and the bushes keep their own wood, and a flare is
    # never more than three.
    assert_almost_equal(
        village.meadow.crowns[8].bark.x, meadow.crowns[8].bark.x, atol=1e-7
    )
    var flared = meadow.crowns[0].copy()
    flared.limbs.flare = 2
    assert_almost_equal(oak(flared^).limbs.flare, 3, atol=1e-6)


def test_a_hearth_keeps_its_woodpile_by_its_gable() raises:
    # A brick or a stone dwelling has a hearth; a framed one, a boarded
    # one, and a barn of brick have none.
    var house = _house(2)
    assert_true(hearthed(house))
    house.facade = STONE_FACADE
    assert_true(hearthed(house))
    house.facade = TIMBER_FRAMED
    assert_false(hearthed(house))
    house.facade = BOARDED
    assert_false(hearthed(house))
    var barn = _house(1)
    barn.storey_height = Length(4.0, METER)
    barn.use = BARN
    assert_false(hearthed(barn))
    # Unturned, at (10, 20): the woodpile stands out from the west gable's
    # plinth, toward the back, the scene's -z, and faces -x.
    var placed = HousePlacement(_house(2), 10, 20, Angle(0.0, DEGREE))
    var pile = woodpile_by(placed)
    var half_x = placed.house.width.to(METER) / 2
    var out = Float32(OUTSIDE_WALL) / 2 + PLINTH_OVERHANG
    assert_true(pile.kind == WOODPILE)
    assert_almost_equal(
        pile.x, 10 - half_x - out - WOODPILE_DEPTH / 2 - 0.03, atol=1e-4
    )
    assert_true(pile.z < 20)
    var turn = pile.turn.to(RADIAN)
    # Its own z, (sin, cos) of its turn, points along -x.
    assert_almost_equal(sin(turn), -1, atol=1e-5)
    assert_almost_equal(cos(turn), 0, atol=1e-5)
    pile.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
