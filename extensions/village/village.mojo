# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A village on the meadow: houses, a scanned building, and a pond.

`Village` puts the three subjects into one scene:

1. **The lots.** Each house and the scanned building stands on a `Lot`,
   and the meadow grows no grass, tree or bush on a lot or its apron.
2. **The meadow.** A `Meadow` with the lots and with the ground's `Pond`:
   a basin carved below the lowest hills.
3. **The buildings.** Each house is a building model, drawn as meshes on a
   stone plinth: see `extensions.village.house`. The scanned building is
   cut out of its scan and stands as splats: see
   `extensions.village.scanned`.
4. **The water.** A `WaterScene` keeps the pond's Clearwater water. After
   the renderer draws the scene, `render` composes the water into the
   picture at the ground's `water_level`. The water plane goes on for
   ever, but the ground outside the basin lies above it, so it shows only
   in the basin.

The sun of the water is the meadow's sun, so the water's glints and the
grass's shadows agree.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from extensions.building.material import brick, timber
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.field import FieldStats
from extensions.vegetation.ground import Lot, Pond
from extensions.vegetation.meadow import (
    Meadow,
    MeadowParameters,
    sun_direction,
)
from extensions.village.house import (
    HouseParameters,
    house_lot,
    house_model,
    stand_house,
)
from extensions.village.scanned import CutBuilding, scan_lot, stand_scan
from extensions.water.frame import WaterScene
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from render.framebuffer import Framebuffer
from renderers.renderer import Renderer
from math.vector3 import Vector3
from units.si import DEGREE, METER, RADIAN, SECOND, Angle, Duration, Length

# The water's clock at the start, in seconds: the Clearwater page's.
comptime WATER_START = Float32(5)


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
        brick house stands on the left, about 75 meters away, and a timber
        barn about 90 meters away. A scanned building stands on the right,
        about 110 meters away.

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
                    Length(4.2, METER),
                    Angle(35.0, DEGREE),
                    Vector3(0.11, 0.07, 0.04),
                ),
                -7,
                -58,
                Angle(-12.0, DEGREE),
            ),
        ]
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
            Error: If the meadow or a house is refused; there are not from
                0 to 64 houses; a house or the scanned building stands
                further than 10 kilometers away; a water resolution is not
                valid; or the caustic grid or texels are not from 4 to
                4,096.
        """
        self.meadow.check()
        require_count_between(
            len(self.houses), 0, 64, "A village must have from 0 to 64 houses"
        )
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
    # Each house's node.
    var houses: List[NodeId]
    # The lot of the scanned building, if the village has one.
    var scanned: Optional[Lot]

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
        for index in range(len(parameters.houses)):
            ref placed = parameters.houses[index]
            lots.append(
                house_lot(placed.house, placed.x, placed.z, placed.turn)
            )
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
        self.houses = List[NodeId]()
        for index in range(len(parameters.houses)):
            ref house = parameters.houses[index].house
            var model = house_model(house)
            self.houses.append(
                stand_house(
                    scene, assets, house, model, lots[index], ground
                ).root
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
