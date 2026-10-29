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
from core.object3d import NodeId
from core.scene import Scene
from extensions.building.material import brick, timber
from extensions.building.model import Building
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.field import FieldStats
from extensions.vegetation.ground import Ground, Lot, Pond, footpath
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
    CRATE,
    FENCE,
    HAY_BALE,
    Prop,
    StandingProps,
    WELL,
    WOODPILE,
    WOODPILE_DEPTH,
    stand_props,
)
from extensions.village.surfaces import HouseLooks, house_looks
from extensions.village.terrain import Floor, Terrain, WallSpan
from extensions.village.scanned import CutBuilding, scan_lot, stand_scan
from extensions.water.frame import WaterScene
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from render.framebuffer import Framebuffer
from renderers.renderer import Renderer
from math.vector3 import Vector3
from std.math import atan2, cos, sin
from units.si import DEGREE, METER, RADIAN, SECOND, Angle, Duration, Length

# The water's clock at the start, in seconds: the Clearwater page's.
comptime WATER_START = Float32(5)
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
        away, and a framed cottage and a framed house stand on each side
        of it, about 60 meters away. A brick house stands on the left,
        about 75 meters away, and a timber barn about 90 meters away. A
        scanned building stands on the right, about 110 meters away.

        Raises:
            Error: Never; the defaults are in range.
        """
        self.meadow = MeadowParameters()
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
                    2,
                    brick(),
                    BRICK_FACADE,
                    seed=3,
                ),
                -24,
                -42,
                Angle(20.0, DEGREE),
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
                ),
                2,
                -32,
                Angle(70.0, DEGREE),
            ),
        ]
        self.props = default_props()
        # A house with a hearth keeps its firewood by the hearth's gable.
        for index in range(len(self.houses)):  # pragma: no branch
            ref placed = self.houses[index]
            if hearthed(placed.house):
                self.props.append(woodpile_by(placed))
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
            Error: If the meadow, a house or a prop is refused; there are
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


def default_props() -> List[Prop]:
    """Return the props of the default village.

    Returns:
        A well by the trail with a bench beside it; barrels, crates and
        hay bales before the barn; a fenced garden behind the stone
        cottage; and a bench before the framed house.
    """
    return [
        Prop(WELL, 4, -18, Angle(20.0, DEGREE), 0.8),
        Prop(BENCH, 4.5, -15.6, Angle(10.0, DEGREE), 1.6),
        Prop(BARREL, -11, -52.2, Angle(0.0, DEGREE), 0.3),
        Prop(BARREL, -11.7, -52.6, Angle(30.0, DEGREE), 0.3),
        Prop(BARREL, -11.2, -51.5, Angle(60.0, DEGREE), 0.3),
        Prop(CRATE, -3.4, -52.4, Angle(10.0, DEGREE), 0.6),
        Prop(CRATE, -2.6, -52.6, Angle(-15.0, DEGREE), 0.6),
        Prop(HAY_BALE, 2.5, -55, Angle(30.0, DEGREE), 1.1),
        Prop(HAY_BALE, 2.9, -53.9, Angle(25.0, DEGREE), 1.1),
        Prop(FENCE, -12, 15, Angle(0.0, DEGREE), 6),
        Prop(FENCE, -15, 13, Angle(90.0, DEGREE), 4),
        Prop(FENCE, -9, 13, Angle(90.0, DEGREE), 4),
        Prop(BENCH, 16.3, -21.5, Angle(-80.0, DEGREE), 1.6),
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
    # The lot of the scanned building, if the village has one.
    var scanned: Optional[Lot]
    # The houses' materials, which the props wear too.
    var looks: HouseLooks

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
        scene.update()
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

    def render(
        mut self,
        mut renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        """Draw the scene and compose the pond's water into it.

        Args:
            renderer: The renderer.
            scene: The scene, updated for the frame.
            assets: The stores.
            camera: The camera of the frame.

        Returns:
            The picture.

        Raises:
            Error: If the scene cannot be drawn, or the camera is not a
                centered perspective camera above the water.
        """
        var image = renderer.render(scene, assets, camera)
        _ = self.water.compose(image, scene, camera, self.level, self.bed)
        return image^
