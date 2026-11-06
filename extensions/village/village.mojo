# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A village on the meadow: houses, a scanned building, and a pond.

`Village` puts the three subjects into one scene:

1. **The lots.** Each house and the scanned building stands on a `Lot`,
   and the meadow grows no grass, tree or bush on a lot or its apron. A
   worn footpath runs from each house's front door to the trail: see
   `door_path`. The paths are lots too, with narrow aprons.
2. **The meadow.** A `Meadow` with the lots and with the ground's `Pond`:
   a basin carved below the lowest hills.
3. **The buildings.** Each house is a building model, drawn by the
   village's own view on a stone plinth, with its doors on hinges: see
   `extensions.village.house` and `extensions.village.house_view`. The
   scanned building is cut out of its scan and stands as splats: see
   `extensions.village.scanned`.
4. **The water.** A `WaterScene` keeps the pond's Clearwater water. After
   the renderer draws the scene, `render` composes the water into the
   picture at the ground's `water_level`. The water plane goes on for
   ever, but the ground outside the basin lies above it, so it shows only
   in the basin.

The sun of the water is the meadow's sun, so the water's glints and the
grass's shadows agree.

`Village.terrain` gathers what carries and stops a character: the
ground, each house's walls, floor and steps, and, as solid lots, each
house's furniture and the scanned building. A character walks into a
house at its door: see `extensions.village.terrain`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from materials.material import MaterialId
from core.scene import Scene
from extensions.building.material import brick, timber
from extensions.building.model import Building
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.field import FieldStats
from extensions.vegetation.ground import (
    POND_FLAT,
    POND_FREEBOARD,
    Ground,
    Lot,
    Pond,
    footpath,
)
from extensions.vegetation.meadow import (
    Meadow,
    MeadowParameters,
    sun_direction,
)
from extensions.village.doors import Doors
from extensions.village.house import (
    BARN,
    DWELLING,
    OUTSIDE_WALL,
    BOARDED,
    BRICK_FACADE,
    HouseParameters,
    STONE_FACADE,
    THATCH,
    TIMBER_FRAMED,
    fieldstone,
    footing,
    house_lot,
    house_model,
    lime_plaster,
)
from extensions.village.interior import (
    Doorway,
    PLINTH_OVERHANG,
    house_interior,
)
from extensions.village.house_view import StandingHouse, stand_house
from extensions.village.props import (
    BARREL,
    BENCH,
    CART,
    CRATE,
    CROPS,
    FENCE,
    HAY_BALE,
    HEDGE,
    LAMP_POST,
    Prop,
    SCARECROW,
    SIGNPOST,
    StandingProps,
    TROUGH,
    WASHING_LINE,
    WELL,
    WOODPILE,
    WOODPILE_DEPTH,
    stand_props,
)
from extensions.village.surfaces import HouseLooks, house_looks
from extensions.village.terrain import Floor, Terrain
from extensions.village.scanned import CutBuilding, scan_lot, stand_scan
from extensions.water.frame import WaterScene
from render.antialias import SUPERSAMPLE, downsample
from core.fog import FogView
from extensions.village.day import DayCycle, dim_water
from extensions.village.pond import PondLook
from extensions.village.puffs import Puff, chimney_smoke, draw_puffs
from extensions.village.shore import (
    ShoreParameters,
    StandingShore,
    stand_shore,
)
from extensions.water.optics import Basin
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from render.framebuffer import Color, Framebuffer
from lights.light import PHYSICAL_DECAY, point_light
from renderers.game_renderer import GAME_LAMPS
from renderers.renderer import Renderer
from math.vector3 import Vector3
from std.math import atan2, cos, sin
from extensions.vegetation.crown import CrownParameters
from math.bounds import Sphere
from math.frustum import Frustum
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    InverseLength,
    Length,
)

# The water's clock at the start, in seconds: the Clearwater page's.
comptime WATER_START = Float32(5)
comptime SOAKED = Float32(0.3)
"""The share of a surface's light that the rain takes when it is soaked."""
comptime SNOW_WHITE = Color(236, 240, 248)
"""The color that snow shines, in sRGB bytes."""
comptime SNOW_SHINE = Float32(0.4)
"""How bright a full cover of snow shines in full daylight, as a
material's emissive intensity."""
comptime LAMP_COLOR = Color(255, 186, 110)
"""The color of a lamp's flame, in sRGB bytes."""
comptime LAMP_INTENSITY = Float32(6)
"""How bright a lamp burns, as a point light's intensity."""
comptime LAMP_REACH = Float32(9)
"""How far a lamp's light reaches, in meters."""
comptime SMOKE_DRIFT = Float32(0.6)
"""How fast the wind carries the chimneys' smoke, in meters a second."""
# The texels on a side of each texture of the houses.
comptime SURFACE_TEXELS = 128
comptime PATH_WIDTH = Float32(0.8)
"""How wide a footpath from a door is, in meters."""
comptime PATH_OUT = Float32(3.5)
"""How far a footpath runs straight out from its door before it turns
toward the trail, in meters."""
comptime PATH_REACH = Float32(60)
"""The furthest a footpath runs to the trail, in meters. A door further
from the trail has only the path straight out from it."""


def door_path(door: Doorway, ground: Ground) -> List[Lot]:
    """Return the footpath from a door: `PATH_OUT` straight out from it,
    and then on to the nearest point of the trail.

    The second leg is left out when the trail is not drawn, or is more
    than `PATH_REACH` from the end of the first.

    Args:
        door: The door.
        ground: The ground, with its trail.

    Returns:
        One lot for each leg, `PATH_WIDTH` wide.
    """
    var middle = door.middle()
    var bend_x = middle.x - door.swing_x * PATH_OUT
    var bend_z = middle.z - door.swing_z * PATH_OUT
    var legs: List[Lot] = [
        footpath(middle.x, middle.z, bend_x, bend_z, PATH_WIDTH)
    ]
    if ground.trail_width.to(METER) <= 0:
        return legs^
    # The nearest point of the trail, sought every half meter along z.
    var best = Float32(1.0e30)
    var best_z = bend_z
    for k in range(-240, 241):  # pragma: no branch
        var z = bend_z + 0.5 * Float32(k)
        var dx = ground.trail_x(z) - bend_x
        var dz = z - bend_z
        var gap = dx * dx + dz * dz
        if gap < best:
            best = gap
            best_z = z
    if best > PATH_REACH * PATH_REACH:
        return legs^
    legs.append(
        footpath(bend_x, bend_z, ground.trail_x(best_z), best_z, PATH_WIDTH)
    )
    return legs^


def oak(var crown: CrownParameters) -> CrownParameters:
    """Return a broadleaf tree with an oak's trunk, as a village's old
    trees have.

    The meadow's open trees have pale, thin trunks, as a eucalyptus has.
    An oak's twig tips are twice as thick, so by the pipe model its
    trunk and limbs are twice as thick too, and so is the thinnest wood
    drawn. Its trunk flares twice as much at its foot, into roots. Its bark is gray-brown, furrowed by
    dark marks four times as close.

    Args:
        crown: The tree. Its shape and its leaves are kept.

    Returns:
        The tree with an oak's wood.
    """
    crown.limbs.tip_radius = Length(crown.limbs.tip_radius.to(METER) * 2, METER)
    # The thinnest wood drawn grows as much, so the same branches are
    # drawn, and no more triangles.
    crown.wood_radius = Length(crown.wood_radius.to(METER) * 2, METER)
    crown.limbs.flare = min(Float32(3), crown.limbs.flare * 2)
    crown.bark = Vector3(0.165, 0.140, 0.110)
    crown.bark_dark = Vector3(0.045, 0.038, 0.030)
    crown.bark_marks = InverseLength(
        crown.bark_marks.to(PER_METER) * 4, PER_METER
    )
    return crown^


@fieldwise_init
struct HousePlacement(Copyable, Movable):
    """A house and where it stands."""

    var house: HouseParameters
    # The middle of its plan, in meters.
    var x: Float32
    var z: Float32
    # How far it is turned about +y.
    var turn: Angle


struct VillageParameters(Copyable, Movable):
    """What the village holds: its meadow, its houses, where a scanned
    building stands, and how finely its water is drawn."""

    # The meadow, its ground with the pond included.
    var meadow: MeadowParameters
    var houses: List[HousePlacement]
    # The well, the barrels, the crates, the hay, the fences and the
    # benches.
    var props: List[Prop]
    # The reeds, the stones and the lily pads at the pond.
    var shore: ShoreParameters
    # Where the middle of a scanned building's footprint stands, and how
    # far it is turned, if the village has one.
    var scan_x: Float32
    var scan_z: Float32
    var scan_turn: Angle
    # The water's ocean spectrum, the cells of its caustic ray grid and
    # the caustic texels on a side, and its glare's resolution.
    var ocean: SpectrumResolution
    var caustic_grid: Int
    var caustic_resolution: Int
    var glare: SpectrumResolution

    def __init__(out self) raises:
        """Create a village on the meadow.

        A pond lies right of the trail, 11 meters ahead of the camera. A
        stone cottage stands on the left of the trail, about 25 meters
        away. Past it, three houses face a green round the well, 50 to 60
        meters away: a brick house from the west, a thatched framed
        cottage from the south, and a framed house from across the trail.
        A timber barn stands about 90 meters away, and a scanned building
        on the right, about 110 meters away. The meadow's open and round
        trees grow as oaks: see `oak`.

        Raises:
            Error: Never; the defaults are in range.
        """
        self.meadow = MeadowParameters()
        # The open and the round trees grow as oaks.
        for index in [0, 1, 5, 10, 11]:
            self.meadow.crowns[index] = oak(self.meadow.crowns[index].copy())
        self.meadow.ground.pond = Pond(
            Length(8.0, METER),
            Length(19.0, METER),
            Length(6.0, METER),
            Length(1.2, METER),
        )
        self.houses = [
            HousePlacement(
                HouseParameters(
                    "brick house",
                    Length(9.0, METER),
                    Length(7.0, METER),
                    3,
                    brick(),
                    BRICK_FACADE,
                    roof=Vector3(0.78, 0.66, 0.62),
                    seed=3,
                ),
                -9,
                -22,
                Angle(90.0, DEGREE),
            ),
            HousePlacement(
                HouseParameters(
                    "timber barn",
                    Length(13.0, METER),
                    Length(8.0, METER),
                    1,
                    timber(),
                    BOARDED,
                    Length(4.2, METER),
                    Angle(35.0, DEGREE),
                    roof=Vector3(0.72, 0.70, 0.68),
                    trim=Vector3(0.3, 0.045, 0.03),
                    seed=5,
                    use=BARN,
                ),
                -7,
                -58,
                Angle(-12.0, DEGREE),
            ),
            HousePlacement(
                HouseParameters(
                    "stone cottage",
                    Length(7.0, METER),
                    Length(5.5, METER),
                    1,
                    fieldstone(),
                    STONE_FACADE,
                    Length(2.7, METER),
                    Angle(42.0, DEGREE),
                    trim=Vector3(0.12, 0.035, 0.02),
                    seed=7,
                ),
                -11,
                6,
                Angle(80.0, DEGREE),
            ),
            HousePlacement(
                HouseParameters(
                    "framed house",
                    Length(8.0, METER),
                    Length(6.0, METER),
                    2,
                    lime_plaster(),
                    TIMBER_FRAMED,
                    Length(2.6, METER),
                    Angle(48.0, DEGREE),
                    roof=Vector3(1.0, 0.9, 0.78),
                    trim=Vector3(0.02, 0.04, 0.09),
                    seed=11,
                ),
                21,
                -24,
                Angle(-80.0, DEGREE),
            ),
            HousePlacement(
                HouseParameters(
                    "framed cottage",
                    Length(6.5, METER),
                    Length(5.0, METER),
                    1,
                    lime_plaster(),
                    TIMBER_FRAMED,
                    Length(2.6, METER),
                    Angle(45.0, DEGREE),
                    trim=Vector3(0.09, 0.05, 0.015),
                    seed=13,
                    covering=THATCH,
                ),
                2,
                -32,
                Angle(0.0, DEGREE),
            ),
        ]
        self.props = default_props()
        # A house with a hearth keeps its firewood by the hearth's gable.
        for index in range(len(self.houses)):  # pragma: no branch
            ref placed = self.houses[index]
            if hearthed(placed.house):
                self.props.append(woodpile_by(placed))
        self.shore = ShoreParameters()
        self.scan_x = 22
        self.scan_z = -78
        self.scan_turn = Angle(28.0, DEGREE)
        self.ocean = SpectrumResolution(256)
        self.caustic_grid = 64
        self.caustic_resolution = 256
        self.glare = SpectrumResolution(128)

    def check(self) raises:
        """Refuse a village that cannot be built.

        Raises:
            Error: If the meadow, a house, a prop or the shore is refused; there are
                not from 0 to 64 houses or from 0 to 1,000 props; a house or
                the scanned building stands
                further than 10 kilometers away; a water resolution is not
                valid; or the caustic grid or texels are not from 4 to
                4,096.
        """
        self.meadow.check()
        require_count_between(
            len(self.houses), 0, 64, "A village must have from 0 to 64 houses"
        )
        require_count_between(
            len(self.props),
            0,
            1000,
            "A village must have from 0 to 1,000 props",
        )
        for prop in self.props:
            prop.check()
        self.shore.check()
        for index in range(len(self.houses)):
            ref placed = self.houses[index]
            placed.house.check()
            _require_near(placed.x, placed.z, "A house")
        _require_near(self.scan_x, self.scan_z, "A scanned building")
        if not (self.ocean.is_valid() and self.glare.is_valid()):
            raise Error("A water resolution must be a power of two to 256")
        require_count_between(
            self.caustic_grid,
            4,
            4096,
            "A caustic grid must have from 4 to 4,096 cells",
        )
        require_count_between(
            self.caustic_resolution,
            4,
            4096,
            "A caustic texture must have from 4 to 4,096 texels",
        )


def default_props() raises -> List[Prop]:
    """Return the props of the default village.

    Returns:
        A green round the well, with a bench, a trough, a handcart, a
        signpost where the paths meet the trail, and three lamp posts;
        barrels, crates and hay bales before the barn, and a hedge
        between the barn's yard and the green; a fenced garden behind the
        stone cottage, with a gate, three beds of cabbages and a
        scarecrow, and a washing line beside it; a bench before the
        framed house; and a pen for the sheep and the goat east of the
        trail, with a gate toward it and a trough in it.
    """
    return [
        Prop(WELL, 4, -18, Angle(20.0, DEGREE), 0.8),
        Prop(BENCH, 4.5, -15.6, Angle(10.0, DEGREE), 1.6),
        Prop(TROUGH, 6.2, -20.4, Angle(20.0, DEGREE), 1.6),
        Prop(CART, -1.5, -14.5, Angle(35.0, DEGREE), 1.4),
        Prop(SIGNPOST, 5.5, -11, Angle(-60.0, DEGREE), 2.2),
        Prop(LAMP_POST, -3.5, -20, Angle(0.0, DEGREE), 2.6),
        Prop(LAMP_POST, 4.5, -26.5, Angle(90.0, DEGREE), 2.6),
        Prop(LAMP_POST, 13.8, -20.5, Angle(180.0, DEGREE), 2.6),
        Prop(BARREL, -11, -52.2, Angle(0.0, DEGREE), 0.3),
        Prop(BARREL, -11.7, -52.6, Angle(30.0, DEGREE), 0.3),
        Prop(BARREL, -11.2, -51.5, Angle(60.0, DEGREE), 0.3),
        Prop(CRATE, -3.4, -52.4, Angle(10.0, DEGREE), 0.6),
        Prop(CRATE, -2.6, -52.6, Angle(-15.0, DEGREE), 0.6),
        Prop(HAY_BALE, 2.5, -55, Angle(30.0, DEGREE), 1.1),
        Prop(HAY_BALE, 2.9, -53.9, Angle(25.0, DEGREE), 1.1),
        Prop(HEDGE, -13, -41, Angle(0.0, DEGREE), 14),
        Prop(FENCE, -12, 15, Angle(0.0, DEGREE), 6),
        Prop(FENCE, -15, 13, Angle(90.0, DEGREE), 4),
        Prop(FENCE, -9, 13, Angle(90.0, DEGREE), 4),
        Prop(FENCE, -13.75, 11, Angle(0.0, DEGREE), 2.5),
        Prop(FENCE, -9.75, 11, Angle(0.0, DEGREE), 1.5),
        Prop(CROPS, -12, 13.6, Angle(0.0, DEGREE), 4.6),
        Prop(SCARECROW, -10, 12, Angle(15.0, DEGREE), 1.8),
        Prop(WASHING_LINE, -17, 7, Angle(90.0, DEGREE), 4),
        Prop(BENCH, 16.3, -21.5, Angle(-80.0, DEGREE), 1.6),
        # The sheep's pen, with its gate toward the trail.
        Prop(FENCE, 15, 11, Angle(0.0, DEGREE), 14),
        Prop(FENCE, 15, -3, Angle(0.0, DEGREE), 14),
        Prop(FENCE, 22, 4, Angle(90.0, DEGREE), 14),
        Prop(FENCE, 8, 0.5, Angle(90.0, DEGREE), 7),
        Prop(FENCE, 8, 9, Angle(90.0, DEGREE), 4),
        Prop(TROUGH, 20.5, 8, Angle(90.0, DEGREE), 1.6),
    ]


def hearthed(house: HouseParameters) -> Bool:
    """Return whether a house has a hearth: a brick or a stone dwelling.

    Args:
        house: The house.

    Returns:
        Whether `house_model` gives it a chimney breast.
    """
    if house.use != DWELLING:
        return False
    return house.facade == BRICK_FACADE or house.facade == STONE_FACADE


def woodpile_by(placed: HousePlacement) -> Prop:
    """Return a woodpile against a house's west gable, outside the wall
    that its hearth stands in, toward the back of the house.

    Args:
        placed: The house and where it stands.

    Returns:
        A woodpile along the gable, its logs' ends out from the wall, as
        long as the gable allows up to 2 meters.
    """
    ref house = placed.house
    var half_x = house.width.to(METER) / 2
    var half_y = house.depth.to(METER) / 2
    var length = min(Float32(2), 2 * half_y - 1.2)
    # In the plan: just out from the gable's plinth, its middle toward
    # the back wall, the plan's +y.
    var wall = Float32(OUTSIDE_WALL) / 2 + PLINTH_OVERHANG
    var px = -half_x - wall - WOODPILE_DEPTH / 2 - 0.03
    var py = half_y - 0.4 - length / 2
    # A plan point (x, y) stands at the lot's (x, -y), turned by the turn.
    var turn = placed.turn.to(RADIAN)
    var c = cos(turn)
    var s = sin(turn)
    var x = placed.x + px * c - py * s
    var z = placed.z - px * s - py * c
    # Its own x runs along the plan's -y, so its own z points out of the
    # gable, along the plan's -x.
    return Prop(WOODPILE, x, z, Angle(atan2(-c, s), RADIAN), length)


def _require_near(x: Float32, z: Float32, what: String) raises:
    """Refuse a place further than 10 kilometers from the middle."""
    require_between(x, -1.0e4, 1.0e4, what + " must stand within 10 kilometers")
    require_between(z, -1.0e4, 1.0e4, what + " must stand within 10 kilometers")


def pond_basin(ground: Ground) raises -> Basin:
    """Return the basin that a ground's pond holds its water in.

    The water's bed then follows the ground's own: level in the middle,
    rising to the shore, and standing above the water at the rim.

    Args:
        ground: The ground.

    Returns:
        The pond's basin, or no basin for ground with no pond.

    Raises:
        Error: If the pond cannot be a basin.
    """
    ref pond = ground.pond
    var radius = pond.radius.to(METER)
    if radius <= 0:
        return Basin()
    var level = ground.water_level()
    var x = pond.x.to(METER)
    var z = pond.z.to(METER)
    # The rim is the ground round the basin, above the water by at least
    # its freeboard.
    var rim = Float32(0)
    for k in range(8):  # pragma: no branch
        var a = Float32(k) * 0.7853982
        rim += max(
            ground.hills_at(x + radius * cos(a), z + radius * sin(a)) - level,
            POND_FREEBOARD,
        )
    return Basin(
        pond.x,
        pond.z,
        pond.radius,
        pond.depth,
        POND_FLAT,
        Length(min(rim / 8, Float32(10)), METER),
    )


def lamp_places(
    parameters: VillageParameters,
    houses: List[StandingHouse],
    ground: Ground,
) raises -> List[Vector3]:
    """Return where the village's lamps burn: by the front door of each
    dwelling, and in each lamp post's lantern.

    Args:
        parameters: The village's houses and props.
        houses: The houses as they stand, in the order of `parameters`.
        ground: The ground.

    Returns:
        The lamps, the doors' first, at most `GAME_LAMPS`.

    Raises:
        Error: If a dwelling has no door that leads outside.
    """
    var places = List[Vector3]()
    for index in range(len(houses)):
        if parameters.houses[index].house.use == BARN:
            continue
        var door = houses[index].interior.front_door()
        var middle = Vector3(
            door.hinge_x + door.along_x * door.width / 2,
            door.bottom + door.height - 0.15,
            door.hinge_z + door.along_z * door.width / 2,
        )
        # The lantern hangs beside the door, out from the wall: the door
        # swings in.
        places.append(
            middle
            + Vector3(door.along_x, 0, door.along_z) * (door.width / 2 + 0.25)
            - Vector3(door.swing_x, 0, door.swing_z) * 0.35
        )
    for prop in parameters.props:
        if prop.kind != LAMP_POST:
            continue
        var turn = prop.turn.to(RADIAN)
        places.append(
            Vector3(
                prop.x + 0.38 * cos(turn),
                ground.height_at(prop.x, prop.z) + prop.length - 0.25,
                prop.z - 0.38 * sin(turn),
            )
        )
    while len(places) > GAME_LAMPS:
        _ = places.pop()
    return places^


def chimney_tops(
    scene: Scene, houses: List[StandingHouse]
) raises -> List[Vector3]:
    """Return the top of each house's chimney pot, in the world.

    Args:
        scene: The scene, updated.
        houses: The houses as they stand.

    Returns:
        One top a house with a chimney, in the order of `houses`.

    Raises:
        Error: If the scene is stale.
    """
    var tops = List[Vector3]()
    for index in range(len(houses)):
        ref house = houses[index]
        if house.chimney:
            tops.append(scene.local_to_world(house.root, house.chimney.value()))
    return tops^


def _hang_lamps(
    mut scene: Scene,
    parameters: VillageParameters,
    houses: List[StandingHouse],
    ground: Ground,
) raises -> NodeId:
    """Add a warm point light at each lamp, under one node hidden by day,
    and return the node."""
    var root = Object3D()
    root.visible = False
    var lamps = scene.add(root^)
    for at in lamp_places(parameters, houses, ground):
        var node = Object3D()
        node.set_position(at.x, at.y, at.z)
        node.parent = lamps
        var bulb = scene.add(node^)
        scene.add_light(
            point_light(
                LAMP_COLOR, bulb, LAMP_INTENSITY, PHYSICAL_DECAY, LAMP_REACH
            )
        )
    return lamps


def _fill_pond(mut water: WaterScene, ground: Ground) raises:
    """Give the water its pond's basin, and lay its ripple window over the
    pond."""
    water.basin = pond_basin(ground)
    ref pond = ground.pond
    var radius = pond.radius.to(METER)
    water.place_ripples(
        pond.x, pond.z, Length(min(2 * radius + 1, Float32(200)), METER)
    )


struct Village(Movable):
    """The village in a scene: its meadow, its buildings and its pond."""

    var meadow: Meadow
    var water: WaterScene
    var bed: PebbleBed
    # The height of the pond's water.
    var level: Length
    # Each house: its node, its interior and its doors' hinges.
    var houses: List[StandingHouse]
    # Every door of every house.
    var doors: Doors
    # The props, and what of them stops a character.
    var props: StandingProps
    # The reeds, the stones and the lily pads at the pond.
    var shore: StandingShore
    # The lot of the scanned building, if the village has one.
    var scanned: Optional[Lot]
    # The houses' materials, which the props wear too.
    var looks: HouseLooks
    # What finishes the pond's water: the mirrored village, the fog and
    # the stars.
    var look: PondLook
    var chimneys: List[Vector3]
    """The top of each chimney's pot, in the world, in the order of the
    houses that have one."""
    var wind: Vector3
    """The wind that carries the chimneys' smoke, in meters a second."""
    var weathered: List[MaterialId]
    """The materials that the weather wets and the snow covers: the
    walls', the wood's and the stone's, the roofs', the grass's and the
    ground's."""
    var roofs: Int
    """How many of `weathered`, from its start, are walls and wood, which
    the rain darkens but no snow covers."""
    var lamps: NodeId
    """The node of the lamps' lights: a light at each dwelling's door
    lantern and at each lamp post, at most `GAME_LAMPS`. It is hidden by
    day."""

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        renderer: Renderer,
        parameters: VillageParameters,
        var bed: PebbleBed,
        var scan: Optional[CutBuilding],
    ) raises:
        """Build the village into a scene and its stores.

        Args:
            scene: The scene. The meadow, the houses and the scanned
                building are added to it.
            assets: The stores.
            renderer: What the sky's cube is drawn with.
            parameters: What the village holds.
            bed: The pebble photograph the pond's water shows through.
            scan: The scanned building, or None for none.

        Raises:
            Error: If `parameters.check` refuses a value, or a part cannot
                be built.
        """
        parameters.check()
        var meadow = parameters.meadow.copy()
        var lots = List[Lot]()
        var models = List[Building]()
        for index in range(len(parameters.houses)):
            ref placed = parameters.houses[index]
            var lot = house_lot(placed.house, placed.x, placed.z, placed.turn)
            var model = house_model(placed.house)
            # A worn path from the house's front door to the trail.
            var floor = footing(lot, meadow.ground)[1]
            var inside = house_interior(model, lot, floor, meadow.ground)
            meadow.lots.extend(door_path(inside.front_door(), meadow.ground))
            lots.append(lot)
            models.append(model^)
        if scan:
            meadow.lots.append(
                scan_lot(
                    scan.value(),
                    parameters.scan_x,
                    parameters.scan_z,
                    parameters.scan_turn,
                )
            )
        meadow.lots.extend(lots.copy())
        self.meadow = Meadow(scene, assets, renderer, meadow)
        ref ground = meadow.ground
        self.houses = List[StandingHouse]()
        self.doors = Doors()
        var looks = house_looks(assets, SURFACE_TEXELS, 17)
        self.looks = looks
        for index in range(len(parameters.houses)):
            ref house = parameters.houses[index].house
            var standing = stand_house(
                scene, assets, looks, house, models[index], lots[index], ground
            )
            # `house_model` gives every house a front door.
            for hinge in standing.hinges:  # pragma: no branch
                self.doors.add(hinge, standing.interior.doorways[hinge.door])
            self.houses.append(standing^)
        self.props = stand_props(scene, assets, looks, parameters.props, ground)
        self.shore = stand_shore(
            scene, assets, looks, parameters.shore, ground, meadow.lots
        )
        self.scanned = None
        if scan:
            self.scanned = stand_scan(
                scene,
                scan.value(),
                parameters.scan_x,
                parameters.scan_z,
                parameters.scan_turn,
                ground,
            )
        self.lamps = _hang_lamps(scene, parameters, self.houses, ground)
        self.weathered = [
            looks.brick,
            looks.fieldstone,
            looks.plaster,
            looks.boards,
            looks.wood,
            looks.ashlar,
            looks.tiles,
            looks.slates,
            looks.thatch,
            self.meadow.grass,
            self.meadow.wood_still,
        ]
        self.roofs = 6
        scene.update()
        self.chimneys = chimney_tops(scene, self.houses)
        var heading = meadow.wind.heading.to(RADIAN)
        self.wind = Vector3(cos(heading), 0, sin(heading)) * SMOKE_DRIFT
        self.water = WaterScene(
            parameters.ocean,
            parameters.caustic_grid,
            parameters.caustic_resolution,
            parameters.glare,
            Duration(WATER_START, SECOND),
        )
        self.water.set_sun(
            sun_direction(meadow.sun_elevation, meadow.sun_azimuth)
        )
        self.bed = bed^
        self.level = Length(ground.water_level(), METER)
        _fill_pond(self.water, ground)
        self.look = PondLook()

    def terrain(self) -> Terrain:
        """Return what carries and stops a character in the village.

        Returns:
            The ground; each house's walls, its furniture, its floors,
            its steps and its stair, and each fence; and, as solid lots,
            each other prop, and the scanned building, if there is one.
        """
        var lots = self.props.lots.copy()
        var walls = self.props.walls.copy()
        var floors = List[Floor]()
        if self.scanned:
            lots.append(self.scanned.value())
        for index in range(len(self.houses)):
            ref inside = self.houses[index].interior
            walls.extend(inside.walls.copy())
            walls.extend(inside.furniture.copy())
            floors.extend(inside.floors.copy())
        return Terrain(self.meadow.field.ground, lots^, walls^, floors^)

    def pond_seen(self, camera: PerspectiveCamera) raises -> Bool:
        """Return whether a camera can see any of the pond.

        The water is an endless plane, but it shows only in the pond's
        basin. A sphere around the basin, at the water's height, stands in
        for it: a camera whose view misses the sphere sees no water, and
        the water need not be composed.

        Args:
            camera: The camera, placed.

        Returns:
            False if the village has no pond, or the sphere lies outside
            the camera's view.

        Raises:
            Error: If the camera's matrices are invalid.
        """
        ref pond = self.meadow.field.ground.pond
        var radius = pond.radius.to(METER)
        if radius <= 0:
            return False
        var view = camera.view_matrix()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var frustum = Frustum.from_camera(
            clip, view, camera.near_distance(), camera.far_distance()
        )
        return frustum.intersects_sphere(
            Sphere(
                Vector3(
                    pond.x.to(METER), self.level.to(METER), pond.z.to(METER)
                ),
                radius + 1,
            )
        )

    def update(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        camera: PerspectiveCamera,
        time: Duration,
    ) raises -> FieldStats:
        """Prepare one frame: the meadow's, and the water's clock moved on
        to `time` if it is later.

        Args:
            scene: The scene the village is in.
            assets: The stores.
            camera: The camera of the frame, placed.
            time: The time of the frame.

        Returns:
            What the frame draws of the field.

        Raises:
            Error: If the meadow cannot prepare the frame.
        """
        var later = time.to(SECOND) - self.water.clock.to(SECOND)
        self.water.advance(Duration(max(Float32(0), later), SECOND), False)
        return self.meadow.update(scene, assets, camera, time)

    def smoke(self, seconds: Float32) -> List[Puff]:
        """Return the puffs of smoke over every chimney at a time.

        Args:
            seconds: The time, in seconds.

        Returns:
            `SMOKE_PUFFS` puffs for each chimney.
        """
        var puffs = List[Puff]()
        for index in range(len(self.chimneys)):
            puffs.extend(
                chimney_smoke(self.chimneys[index], seconds, self.wind, index)
            )
        return puffs^

    def keep_hour(mut self, mut scene: Scene, day: DayCycle) raises:
        """Set the village for an hour, for a still: the sun or the moon,
        the lamps and the windows.

        Call it before `update`. The meadow's sun sets its lights again in
        `update`, so scale the lights for the hour after it, with
        `DayCycle.light`.

        Args:
            scene: The scene.
            day: The hour.

        Raises:
            Error: If a node is missing, or the sun is not above the
                horizon.
        """
        var toward = day.sun_toward()
        scene.node(self.meadow.sun.node).set_position(
            toward.x * 100, toward.y * 100, toward.z * 100
        )
        self.water.set_sun(toward)
        var lamps = day.daylight() < 0.5
        for index in range(len(self.houses)):  # pragma: no branch
            ref house = self.houses[index]
            scene.node(house.lit).visible = lamps
            scene.node(house.daylit).visible = not lamps
        scene.node(self.props.lit).visible = lamps
        scene.node(self.props.daylit).visible = not lamps
        scene.node(self.lamps).visible = lamps
        scene.update()

    def weather_surfaces(
        self, mut assets: Assets, wet: Float32, snowed: Float32, light: Float32
    ) raises:
        """Darken the village's surfaces as the rain soaks them, and
        whiten its roofs, its grass and its ground under snow.

        A soaked surface keeps `1 - SOAKED` of its light. Snow shines with
        the light of the day: its white is the material's emissive color,
        at `light` of its strength, so it dims at night.

        Args:
            assets: The stores: the materials' colors and emissive light
                are set.
            wet: How wet the village is, from 0 to 1.
            snowed: How much snow lies on it, from 0 to 1.
            light: How much of the day's light the snow catches, from 0 to
                1.

        Raises:
            Error: If a value is not from 0 to 1.
        """
        for value in [wet, snowed, light]:
            if not (value >= 0 and value <= 1):
                raise Error("A surface's weather must be from 0 to 1")
        var gray = UInt8(Int(255 * (1 - SOAKED * wet) + 0.5))
        for index in range(len(self.weathered)):  # pragma: no branch
            ref m = assets.materials.materials[self.weathered[index].value]
            m.color = Color(gray, gray, gray)
            if index < self.roofs:
                continue
            m.emissive = SNOW_WHITE
            m.emissive_intensity = SNOW_SHINE * snowed * light

    def splash(
        mut self, x: Float32, z: Float32, radius: Length, strength: Float32
    ) raises:
        """Ripple the pond at a point on the next `update`.

        A point out of the pond's ripple window is let go.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.
            radius: The drop's radius, from 0 to 10 meters.
            strength: How far the drop pulls the water down, from 0 to 1.

        Raises:
            Error: If the point is not finite, or a value is out of range.
        """
        self.water.splash(Length(x, METER), Length(z, METER), radius, strength)

    def render(
        mut self,
        mut renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
        day: Optional[DayCycle] = None,
    ) raises -> Framebuffer:
        """Draw the scene and compose the pond's water into it, mirror the
        village and the stars in the water, and smoke the chimneys.

        Args:
            renderer: The renderer.
            scene: The scene, updated for the frame.
            assets: The stores.
            camera: The camera of the frame.
            day: The hour, for its night sky, its stars and its darker
                water. None draws the meadow's afternoon. Set the hour's
                light first with `keep_hour`.

        Returns:
            The picture.

        Raises:
            Error: If the scene cannot be drawn, or the camera is not a
                centered perspective camera above the water.
        """
        # The water is composed into each sample before they are averaged:
        # composed after, a grass blade that covers one sample of a pixel
        # keeps the whole pixel from the water, and shows as a dark line.
        var image = renderer.supersampled().render(
            scene, assets, camera
        ) if renderer.antialias else renderer.render(scene, assets, camera)
        var before = image.depth.copy()
        _ = self.water.compose(image, scene, camera, self.level, self.bed)
        var stars = Float32(0)
        var light = Float32(1)
        if day:
            ref hour = day.value()
            var share = hour.water_light()
            if share < 1:
                dim_water(image, before, share)
            stars = hour.night_look(camera, 1).stars
            light = 0.2 + 0.8 * hour.daylight()
        self.look.clock = self.water.clock.to(SECOND)
        _ = self.look.apply(
            image, before, camera, self.level, FogView(scene.fog), stars
        )
        if day:
            day.value().night_sky(image, camera, 1)
        _ = draw_puffs(
            image, self.smoke(self.water.clock.to(SECOND)), camera, light
        )
        if renderer.antialias:
            return downsample(image, SUPERSAMPLE)
        return image^
