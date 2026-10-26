# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A house of the village: a building model, its meshes, and its plinth.

`house_model` builds a model with `extensions.building.model.assemble`:
each storey is one room, `width` by `depth`, `storey_height` tall. Its
outside walls are `cladding` over mineral wool and gypsum board, and it
has a row of windows in each outside wall and a door to each room.

`stand_house` adds the model's meshes to a scene with
`extensions.building.views.render.add_building`, turns it about +y and
stands its ground floor at the highest point of the ground under its
corners. Ground slopes, so a stone plinth fills the gap down to the lowest
corner, and a little below it, as a house's footing does.

A building model's roof is flat. A village house's roof is pitched, so
`stand_house` sets a gable roof on the flat one when `pitch` is above
zero: two slopes of tiles along the house's width, `EAVES` past its walls,
and a gable of `gable` color at each end.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.building.construction import (
    Construction,
    Layer,
    double_glazing,
)
from extensions.building.generate.openings import (
    WindowOptions,
    add_doors,
    add_windows,
)
from extensions.building.ids import ConstructionId, MaterialId
from extensions.building.kinds import LIVING
from extensions.building.material import (
    BuildingMaterial,
    concrete,
    gypsum_board,
    mineral_wool,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
)
from extensions.building.views.render import (
    FULL,
    RenderOptions,
    RenderedBuilding,
    add_building,
)
from extensions.topology.arrangement import Point2
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.ground import Ground, Lot
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import cos, sin, tan
from units.si import (
    DEGREE,
    DEGREE64,
    METER,
    RADIAN,
    Angle,
    Angle64,
    Length,
    Length64,
)

# How far the plinth reaches below the lowest corner, and past the walls,
# in meters.
comptime PLINTH_DEPTH = Float32(0.4)
comptime PLINTH_OVERHANG = Float32(0.15)
# The linear color of the plinth's stone, and of a roof's tiles.
comptime PLINTH = Vector3(0.090, 0.086, 0.080)
comptime TILES = Vector3(0.120, 0.040, 0.025)
# How far a pitched roof reaches past the walls, in meters.
comptime EAVES = Float32(0.35)


struct HouseParameters(Copyable, Movable):
    """What a house is made of and how large it is."""

    var name: String
    # The width and the depth of the plan, and the height of a storey.
    var width: Length
    var depth: Length
    var storey_height: Length
    var storeys: Int
    # The outer layer of the outside walls.
    var cladding: BuildingMaterial
    # How steep the gable roof is. Zero is the model's flat roof.
    var pitch: Angle
    # The linear color of the gables.
    var gable: Vector3

    def __init__(
        out self,
        var name: String,
        width: Length,
        depth: Length,
        storeys: Int,
        var cladding: BuildingMaterial,
        storey_height: Length = Length(2.8, METER),
        pitch: Angle = Angle(40.0, DEGREE),
        gable: Vector3 = Vector3(0.20, 0.07, 0.04),
    ):
        """Create a house's parameters.

        Args:
            name: A name for people and for exchange files.
            width: The plan's width, along its x.
            depth: The plan's depth, along its y.
            storeys: How many storeys.
            cladding: The outer layer of the outside walls.
            storey_height: The height of a storey.
            pitch: How steep the gable roof is. Zero keeps the flat roof.
            gable: The linear color of the gables.
        """
        self.name = name^
        self.width = width
        self.depth = depth
        self.storey_height = storey_height
        self.storeys = storeys
        self.cladding = cladding^
        self.pitch = pitch
        self.gable = gable

    def check(self) raises:
        """Refuse a house that cannot be built.

        Raises:
            Error: If the width or the depth is not from 3 to 60 meters,
                there are not from 1 to 6 storeys, a storey is not from
                2.4 to 6 meters tall, the pitch is not from 0 to 60
                degrees, or a gable color channel is not from 0 to 1.
        """
        require_between(
            self.width.to(METER),
            3,
            60,
            "A house must be from 3 to 60 meters wide",
        )
        require_between(
            self.depth.to(METER),
            3,
            60,
            "A house must be from 3 to 60 meters deep",
        )
        require_count_between(
            self.storeys, 1, 6, "A house must have from 1 to 6 storeys"
        )
        require_between(
            self.storey_height.to(METER),
            2.4,
            6,
            "A storey must be from 2.4 to 6 meters tall",
        )
        require_between(
            self.pitch.to(DEGREE),
            0,
            60,
            "A roof must pitch from 0 to 60 degrees",
        )
        require_between(self.gable.x, 0, 1, "A color must be 0 to 1")
        require_between(self.gable.y, 0, 1, "A color must be 0 to 1")
        require_between(self.gable.z, 0, 1, "A color must be 0 to 1")


def _m(meters: Float64) -> Length64:
    """Return a length of `meters`."""
    return Length64(meters, METER)


def house_model(parameters: HouseParameters) raises -> Building:
    """Return a house's model, with its windows and doors.

    Args:
        parameters: The house.

    Returns:
        The model, centered on its plan's middle.

    Raises:
        Error: If `parameters.check` refuses a value, or the model cannot
            be assembled.
    """
    parameters.check()
    var half_x = Float64(parameters.width.to(METER)) / 2
    var half_y = Float64(parameters.depth.to(METER)) / 2
    var outline: List[Point2] = [
        Point2(-half_x, -half_y),
        Point2(half_x, -half_y),
        Point2(half_x, half_y),
        Point2(-half_x, half_y),
    ]
    var plans = List[StoreyPlan]()
    for storey in range(parameters.storeys):  # pragma: no branch
        var rooms: List[SpacePlan] = [
            SpacePlan("room " + String(storey), LIVING, outline.copy())
        ]
        plans.append(
            StoreyPlan(
                "storey " + String(storey),
                _m(Float64(parameters.storey_height.to(METER))),
                rooms^,
            )
        )
    var materials: List[BuildingMaterial] = [
        parameters.cladding.copy(),
        mineral_wool(),
        gypsum_board(),
        concrete(),
    ]
    var constructions: List[Construction] = [
        Construction(
            "outside wall",
            [
                Layer(MaterialId(0), _m(0.12)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        ),
        Construction("inside wall", [Layer(MaterialId(2), _m(0.1))]),
        Construction("slab", [Layer(MaterialId(3), _m(0.2))]),
    ]
    var building = assemble(
        parameters.name,
        Site(Angle64(55, DEGREE64), Angle64(9, DEGREE64), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        _m(1e-6),
    )
    _ = add_windows(
        building,
        WindowOptions(_m(2.6), _m(1.4), _m(0.9), _m(1.3), double_glazing()),
    )
    _ = add_doors(building, _m(1.0), _m(2.1))
    return building^


def _plinth(
    half_width: Float32,
    half_depth: Float32,
    low: Float32,
    high: Float32,
) raises -> BufferGeometry:
    """Return a box of stone from `low` up to `high`, in the house's own
    frame, a little wider than the house, with its four sides and its
    top."""
    var x = half_width + PLINTH_OVERHANG
    var z = half_depth + PLINTH_OVERHANG
    var corners: List[Vector3] = [
        Vector3(-x, low, -z),
        Vector3(x, low, -z),
        Vector3(x, low, z),
        Vector3(-x, low, z),
        Vector3(-x, high, -z),
        Vector3(x, high, -z),
        Vector3(x, high, z),
        Vector3(-x, high, z),
    ]
    # Each face, wound to face out.
    var faces: List[List[Int]] = [
        [3, 2, 6, 7],
        [1, 0, 4, 5],
        [2, 1, 5, 6],
        [0, 3, 7, 4],
        [7, 6, 5, 4],
    ]
    var positions = List[Float32]()
    var colors = List[Float32]()
    var index = List[Int]()
    for f in range(len(faces)):  # pragma: no branch
        var first = len(positions) // 3
        for k in range(4):  # pragma: no branch
            ref p = corners[faces[f][k]]
            positions.append(p.x)
            positions.append(p.y)
            positions.append(p.z)
            colors.append(PLINTH.x)
            colors.append(PLINTH.y)
            colors.append(PLINTH.z)
        index.append(first)
        index.append(first + 1)
        index.append(first + 2)
        index.append(first)
        index.append(first + 2)
        index.append(first + 3)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
    geometry.set_index(index^)
    geometry.compute_vertex_normals()
    return geometry^


def gable_roof(parameters: HouseParameters) raises -> BufferGeometry:
    """Return a gable roof for a house, in the house's own frame, sitting
    on its flat roof.

    The ridge runs along the house's width, at the middle of its depth.
    Each slope reaches `EAVES` past the walls, and each gable closes an
    end.

    Args:
        parameters: The house.

    Returns:
        The roof, with `position`, `normal` and `color`.

    Raises:
        Error: If the geometry cannot be made.
    """
    var half_x = parameters.width.to(METER) / 2 + EAVES
    var half_z = parameters.depth.to(METER) / 2 + EAVES
    var base = parameters.storey_height.to(METER) * Float32(parameters.storeys)
    var rise = tan(parameters.pitch.to(RADIAN)) * (half_z - EAVES)
    var ridge = base + rise
    var eave = base - tan(parameters.pitch.to(RADIAN)) * EAVES
    var positions = List[Float32]()
    var colors = List[Float32]()
    var index = List[Int]()
    var tiles = TILES
    var gable = parameters.gable
    # Two slopes, front and back, wound to face up and out.
    var quads: List[List[Vector3]] = [
        [
            Vector3(-half_x, eave, half_z),
            Vector3(half_x, eave, half_z),
            Vector3(half_x, ridge, 0),
            Vector3(-half_x, ridge, 0),
        ],
        [
            Vector3(half_x, eave, -half_z),
            Vector3(-half_x, eave, -half_z),
            Vector3(-half_x, ridge, 0),
            Vector3(half_x, ridge, 0),
        ],
    ]
    for q in range(len(quads)):  # pragma: no branch
        var first = len(positions) // 3
        for k in range(4):  # pragma: no branch
            ref p = quads[q][k]
            positions.append(p.x)
            positions.append(p.y)
            positions.append(p.z)
            colors.append(tiles.x)
            colors.append(tiles.y)
            colors.append(tiles.z)
        index.append(first)
        index.append(first + 1)
        index.append(first + 2)
        index.append(first)
        index.append(first + 2)
        index.append(first + 3)
    # The gables, at each end of the ridge, wound to face out.
    var wall = half_x - EAVES
    var inner = half_z - EAVES
    var ends: List[List[Vector3]] = [
        [
            Vector3(wall, base, inner),
            Vector3(wall, base, -inner),
            Vector3(wall, ridge, 0),
        ],
        [
            Vector3(-wall, base, -inner),
            Vector3(-wall, base, inner),
            Vector3(-wall, ridge, 0),
        ],
    ]
    for e in range(len(ends)):  # pragma: no branch
        var first = len(positions) // 3
        for k in range(3):  # pragma: no branch
            ref p = ends[e][k]
            positions.append(p.x)
            positions.append(p.y)
            positions.append(p.z)
            colors.append(gable.x)
            colors.append(gable.y)
            colors.append(gable.z)
        index.append(first)
        index.append(first + 1)
        index.append(first + 2)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
    geometry.set_index(index^)
    geometry.compute_vertex_normals()
    return geometry^


def house_lot(
    parameters: HouseParameters, x: Float32, z: Float32, turn: Angle
) -> Lot:
    """Return the lot a house stands on.

    Args:
        parameters: The house.
        x: Its middle's x, in meters.
        z: Its middle's z, in meters.
        turn: How far it is turned about +y.

    Returns:
        The lot, as wide and as deep as the house.
    """
    return Lot(
        x,
        z,
        parameters.width.to(METER) / 2,
        parameters.depth.to(METER) / 2,
        turn.to(RADIAN),
    )


def stand_house(
    mut scene: Scene,
    mut assets: Assets,
    parameters: HouseParameters,
    building: Building,
    lot: Lot,
    ground: Ground,
) raises -> RenderedBuilding:
    """Add a house's meshes to a scene, standing on the ground on its lot.

    The model's +x runs along the lot's width and its +y along the lot's
    -z, both turned by the lot's turn. The ground floor stands at the
    highest of the ground under the lot's corners, on a stone plinth.

    Args:
        scene: The scene.
        assets: The stores for the geometries and the materials.
        parameters: The house: its gable roof is read.
        building: The house's model.
        lot: Where it stands: its middle, its half sizes and its turn.
        ground: The ground it stands on.

    Returns:
        The building's node and the count of its meshes and triangles, the
        plinth's and the roof's included.

    Raises:
        Error: If the building cannot be drawn.
    """
    var drawn = add_building(scene, assets, building, RenderOptions(FULL, -1))
    var c = cos(lot.turn)
    var s = sin(lot.turn)
    var high = Float32(-1.0e30)
    var low = Float32(1.0e30)
    for k in range(4):  # pragma: no branch
        var u = lot.half_width * (Float32(1) if k % 2 == 0 else Float32(-1))
        var v = lot.half_depth * (Float32(1) if k < 2 else Float32(-1))
        var y = ground.height_at(lot.x + u * c + v * s, lot.z - u * s + v * c)
        high = max(high, y)
        low = min(low, y)
    ref stand = scene.node(drawn.root)
    stand.set_position(lot.x, high, lot.z)
    stand.rotate_y(Angle(lot.turn, RADIAN))
    var stone = assets.materials.add(
        Material(Color(255, 255, 255), vertex_colors=True)
    )
    var plinth = _plinth(
        lot.half_width, lot.half_depth, low - high - PLINTH_DEPTH, 0.02
    )
    var triangles = len(plinth.index) // 3
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plinth^),
            stone,
            drawn.root,
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    var meshes = drawn.meshes + 1
    if parameters.pitch.to(DEGREE) > 0:
        var roof = gable_roof(parameters)
        triangles += len(roof.index) // 3
        scene.add_mesh(
            Mesh(
                assets.geometries.add(roof^),
                stone,
                drawn.root,
                cast_shadow=True,
                receive_shadow=True,
            )
        )
        meshes += 1
    return RenderedBuilding(drawn.root, meshes, drawn.triangles + triangles)
