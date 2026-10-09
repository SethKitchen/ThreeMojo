# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A grid of city blocks, from three.js
`examples/jsm/generators/CityGenerator.js`.

The city is a grid of blocks with streets between them. Each block is cut
into lots, set back from the curb by a sidewalk, and each lot takes a
skyscraper of its own seed, height and footprint. A tower nearly fills
its lot and fronts the streets it borders, so neighbors make a continuous
street wall. Only the four corner lots of a block cut a chamfer, toward
their own corner of the block.

The blocks stand on raised sidewalk slabs when the curb has a height, and
the sidewalks are dressed with street furniture: streetlights along the
curb, street trees in pits, a hydrant and sometimes a bench on each edge,
pedestrians, parked cars clear of the corners and the hydrant, a few cars
in the travel lanes, a traffic signal on two opposite corners and a litter
basket on every corner.

One seeded generator lays out the whole city: the towers first, lot by
lot, then the furniture, edge by edge. The same seed gives the same city
as three.js. `plan` returns the layout without building a tower, and
`build` builds everything. The road, building and proxy materials are
not ported.
"""

from core.buffer_geometry import BufferGeometry
from generators.car import CarGenerator, CarPlacement
from generators.person import PersonGenerator
from generators.sidewalk import SidewalkGenerator, SidewalkInstances
from generators.skyscraper import SkyscraperGenerator, SkyscraperParameters
from generators.street_furniture import (
    BenchGenerator,
    HydrantGenerator,
    StreetTreeGenerator,
    StreetlightGenerator,
    TrafficlightGenerator,
    TrashcanGenerator,
    placed,
)
from generators.utils import (
    Instances,
    Vec3d,
    basis_matrix,
    generator_random,
    length_meters as _len,
    meters,
    place,
    place_yaw_scale,
)
from geometries.box import box
from math.matrix4 import Matrix4
from math.utils import SeededRandom
from std.math import floor, pi
from units.si import Length, METER


def car_colors() -> List[Int]:
    """Return the paints of the parked fleet, three.js's `CAR_COLORS`,
    as hex sRGB: yellow cabs, black, white, silver, graphite, gray, and
    now and then navy, burgundy or bronze.

    Returns:
        The paints, in the order of `car_color_thresholds`.
    """
    return [
        0xF5C518,
        0x111216,
        0xE9E8E3,
        0xB2B5B8,
        0x3E4247,
        0x74787C,
        0x1C2A3F,
        0x571F1F,
        0x5C4834,
    ]


def car_color_thresholds() -> List[Float64]:
    """Return the cumulative chances of the paints of `car_colors`.

    Returns:
        One threshold a paint. A draw below a threshold, and not below the
        one before, takes that paint.
    """
    return [0.22, 0.42, 0.59, 0.72, 0.84, 0.90, 0.95, 0.98, 1.01]


def car_color(mut random: SeededRandom) -> Int:
    """Draw a car's paint, three.js's `carColor`.

    Args:
        random: The city's generator.

    Returns:
        The paint, as hex sRGB.
    """
    var draw = random.next()
    var colors = car_colors()
    var thresholds = car_color_thresholds()
    var pick = len(colors) - 1
    for i in range(len(colors) - 1, -1, -1):  # pragma: no branch
        pick = i if draw < thresholds[i] else pick
    return colors[pick]


struct CityParameters(Copyable, Movable):
    """The parameters of a city, three.js's `CityGenerator.defaults`."""

    var seed: Int
    # The width of a street between two blocks.
    var street: Length
    # The size of a lot, along both axes.
    var lot: Length
    # The lots a block, along x and along z.
    var lots_x: Int
    var lots_z: Int
    # The blocks, along x and along z.
    var blocks_x: Int
    var blocks_z: Int
    # The height of the sidewalk above the road. Zero leaves no slabs.
    var curb_height: Length
    # The radius of a sidewalk slab's corners.
    var curb_radius: Length
    # The walking strip between the street wall and the curb.
    var sidewalk_width: Length

    def __init__(out self):
        """Create three.js's default city."""
        self.seed = 1
        self.street = Length(22, METER)
        self.lot = Length(30, METER)
        self.lots_x = 3
        self.lots_z = 2
        self.blocks_x = 2
        self.blocks_z = 2
        self.curb_height = Length(0.15, METER)
        self.curb_radius = Length(5, METER)
        self.sidewalk_width = Length(5, METER)


@fieldwise_init
struct CityLayout(ImplicitlyCopyable):
    """The dimensions that follow from a city's parameters, three.js's
    `cityLayout`, in meters. The road markings and the materials align to
    them."""

    var street: Float64
    var lots_x: Int
    var lots_z: Int
    var blocks_x: Int
    var blocks_z: Int
    var block_w: Float64
    var block_d: Float64
    var sidewalk_width: Float64
    # The lots tile the zone inside the sidewalk strip.
    var inner_lot_x: Float64
    var inner_lot_z: Float64
    var city_w: Float64
    var city_d: Float64

    def block_x(self, bx: Int) -> Float64:
        """Return the x of a block's near corner.

        Args:
            bx: The block's column.

        Returns:
            The x, in meters.
        """
        return -self.city_w / 2 + Float64(bx) * (self.block_w + self.street)

    def block_z(self, bz: Int) -> Float64:
        """Return the z of a block's near corner.

        Args:
            bz: The block's row.

        Returns:
            The z, in meters.
        """
        return -self.city_d / 2 + Float64(bz) * (self.block_d + self.street)


def city_layout(p: CityParameters) raises -> CityLayout:
    """Return a city's dimensions, three.js's `cityLayout`.

    Args:
        p: The city.

    Returns:
        The layout.

    Raises:
        Error: If a count is below one, or a length is not positive.
    """
    if p.lots_x < 1 or p.lots_z < 1 or p.blocks_x < 1 or p.blocks_z < 1:
        raise Error("A city needs one block and one lot at least each way")
    var lot = meters(p.lot)
    var street = meters(p.street)
    var sidewalk = meters(p.sidewalk_width)
    if not (lot > 0 and street >= 0 and sidewalk >= 0):
        raise Error(
            "A city's lot must be positive, its street and walk not less"
        )
    var block_w = Float64(p.lots_x) * lot
    var block_d = Float64(p.lots_z) * lot
    return CityLayout(
        street,
        p.lots_x,
        p.lots_z,
        p.blocks_x,
        p.blocks_z,
        block_w,
        block_d,
        sidewalk,
        (block_w - 2 * sidewalk) / Float64(p.lots_x),
        (block_d - 2 * sidewalk) / Float64(p.lots_z),
        Float64(p.blocks_x) * block_w + Float64(p.blocks_x - 1) * street,
        Float64(p.blocks_z) * block_d + Float64(p.blocks_z - 1) * street,
    )


@fieldwise_init
struct TowerPlan(Copyable, Movable):
    """One tower of the city: its parameters, where it stands, and the
    plain box three.js records for the global illumination proxy."""

    var parameters: SkyscraperParameters
    # Where the tower's base stands, on the sidewalk.
    var position: Vec3d
    # The box: its center and its size, in meters.
    var box_center: Vec3d
    var box_size: Vec3d


@fieldwise_init
struct BlockEdge(ImplicitlyCopyable):
    """One curb edge of a block, three.js's `blockEdges` entry: its start
    corner, its direction, its outward normal toward the road, and its
    length, in meters."""

    var x0: Float64
    var z0: Float64
    var dx: Float64
    var dz: Float64
    var nx: Float64
    var nz: Float64
    var length: Float64

    def on_walk(self, t: Float64, lateral: Float64, top: Float64) -> Matrix4:
        """Return a placement on the sidewalk, facing the road.

        Args:
            t: How far along the edge.
            lateral: How far in from the curb.
            top: The height of the sidewalk.

        Returns:
            The placement.
        """
        return place(
            self.x0 + self.dx * t - self.nx * lateral,
            top,
            self.z0 + self.dz * t - self.nz * lateral,
            self.nx,
            self.nz,
        )


def block_edges(
    x: Float64, z: Float64, w: Float64, d: Float64
) -> List[BlockEdge]:
    """Return a block's four curb edges, three.js's `blockEdges`.

    Args:
        x: The x of the block's near corner, in meters.
        z: The z of the near corner.
        w: The block's width.
        d: The block's depth.

    Returns:
        The edges at -z, +z, -x and +x.
    """
    return [
        BlockEdge(x, z, 1, 0, 0, -1, w),
        BlockEdge(x, z + d, 1, 0, 0, 1, w),
        BlockEdge(x, z, 0, 1, -1, 0, d),
        BlockEdge(x + w, z, 0, 1, 1, 0, d),
    ]


struct CityPlan(Movable):
    """A laid-out city: its dimensions, its towers, its sidewalk slabs and
    every placement of its furniture."""

    var layout: CityLayout
    var towers: List[TowerPlan]
    var slabs: List[Matrix4]
    var lights: List[Matrix4]
    var signals: List[Matrix4]
    var cans: List[Matrix4]
    var benches: List[Matrix4]
    var hydrants: List[Matrix4]
    var trees: List[Matrix4]
    var people: List[Matrix4]
    var cars: List[CarPlacement]

    def __init__(out self, layout: CityLayout):
        """Create an empty plan.

        Args:
            layout: The city's dimensions.
        """
        self.layout = layout
        self.towers = List[TowerPlan]()
        self.slabs = List[Matrix4]()
        self.lights = List[Matrix4]()
        self.signals = List[Matrix4]()
        self.cans = List[Matrix4]()
        self.benches = List[Matrix4]()
        self.hydrants = List[Matrix4]()
        self.trees = List[Matrix4]()
        self.people = List[Matrix4]()
        self.cars = List[CarPlacement]()


def _corner_sign(index: Int, count: Int) -> Int:
    """Return which way a lot fronts: minus one for the first, one for the
    last, zero between."""
    return -1 if index == 0 else (1 if index == count - 1 else 0)


def _front(near: Float64, lot: Float64, size: Float64, sign: Int) -> Float64:
    """Return where a tower's center stands across its lot: against the
    street it fronts, or centered."""
    return near + size / 2 if sign == -1 else (
        near + lot - size / 2 if sign == 1 else near + lot / 2
    )


def _plan_tower(
    mut plan: CityPlan,
    mut random: SeededRandom,
    zone_x: Float64,
    zone_z: Float64,
    lx: Int,
    lz: Int,
    curb: Float64,
):
    """Draw one lot's tower, three.js's lot loop in `build`."""
    ref layout = plan.layout
    var corner_x = _corner_sign(lx, layout.lots_x)
    var corner_z = _corner_sign(lz, layout.lots_z)
    var on_corner = corner_x != 0 and corner_z != 0
    var tall = random.next()
    var fw = layout.inner_lot_x - (0.4 + random.next() * 1)
    var fd = layout.inner_lot_z - (0.4 + random.next() * 1)
    var total_height = 38 + tall * tall * 114
    var p = SkyscraperParameters()
    p.seed = Int(floor(random.next() * 100000))
    p.total_height = _len(total_height)
    p.footprint_width = _len(fw)
    p.footprint_depth = _len(fd)
    p.floor_height = _len(3.4 + random.next() * 1.8)
    p.bay_width = _len(1.9 + random.next() * 2.1)
    p.pier_width = _len(0.4 + random.next() * 0.5)
    p.pier_depth = _len(0.3 + random.next() * 0.4)
    p.chamfer_width = _len(3 + random.next() * 4 if on_corner else 0.0)
    p.chamfer_corner_x = corner_x
    p.chamfer_corner_z = corner_z
    p.setback_depth = 0.8 + random.next() * 2 if random.next() < 0.4 else 0.0
    p.string_course_every = (
        3 + Int(floor(random.next() * 6)) if random.next() < 0.85 else 0
    )
    var cx = _front(
        zone_x + Float64(lx) * layout.inner_lot_x,
        layout.inner_lot_x,
        fw,
        corner_x,
    )
    var cz = _front(
        zone_z + Float64(lz) * layout.inner_lot_z,
        layout.inner_lot_z,
        fd,
        corner_z,
    )
    plan.towers.append(
        TowerPlan(
            p^,
            Vec3d(cx, curb, cz),
            Vec3d(cx, curb + total_height / 2, cz),
            Vec3d(fw, total_height, fd),
        )
    )


def _plan_edge(
    mut plan: CityPlan,
    mut random: SeededRandom,
    e: BlockEdge,
    top: Float64,
    walk: Float64,
):
    """Dress one curb edge, three.js's edge loop in `buildFurniture`."""
    var length = e.length
    var s = e.nx + e.nz
    var fdir = 1.0 if s >= 0 else -1.0
    var lights = max(1, Int(floor(length / 30 + 0.5)))
    for i in range(lights):  # pragma: no branch
        plan.lights.append(
            e.on_walk(length * (Float64(i) + 0.5) / Float64(lights), 0.8, top)
        )
    var trees = max(1, Int(floor(length / 16 + 0.5)))
    for i in range(trees):  # pragma: no branch
        var t = length * (Float64(i) + 0.5) / Float64(trees) + 5
        if t > 7 and t < length - 7 and random.next() < 0.85:
            var yaw = random.next() * pi * 2
            var scale = 0.8 + random.next() * 0.5
            plan.trees.append(
                place_yaw_scale(
                    e.x0 + e.dx * t - e.nx * 1.5,
                    top,
                    e.z0 + e.dz * t - e.nz * 1.5,
                    yaw,
                    scale,
                )
            )
    var hydrant = length * (0.25 + random.next() * 0.5)
    plan.hydrants.append(e.on_walk(hydrant, 0.7, top))
    if random.next() < 0.4:
        plan.benches.append(
            e.on_walk(length * (0.3 + random.next() * 0.4), 1.7, top)
        )
    var people = max(2, Int(floor(length / 9 + 0.5)))
    for i in range(people):  # pragma: no branch
        if random.next() < 0.7:
            var t = length * (Float64(i) + random.next()) / Float64(people)
            var lateral = 0.9 + random.next() * (walk - 2)
            var yaw = random.next() * pi * 2
            var scale = 0.92 + random.next() * 0.16
            plan.people.append(
                place_yaw_scale(
                    e.x0 + e.dx * t - e.nx * lateral,
                    top,
                    e.z0 + e.dz * t - e.nz * lateral,
                    yaw,
                    scale,
                )
            )
    var t = 9.0
    while t < length - 9:
        if abs(t - hydrant) > 3 and random.next() < 0.72:
            _park(plan, random, e, t, 1.5, fdir)
        t += 5.8
    t = 14.0
    while t < length - 14:
        if random.next() < 0.4:
            _park(plan, random, e, t, 5.5, fdir)
        t += 13


def _park(
    mut plan: CityPlan,
    mut random: SeededRandom,
    e: BlockEdge,
    t: Float64,
    offset: Float64,
    fdir: Float64,
):
    """Place a car in a lane, facing with the traffic on its side, and draw
    its paint."""
    var matrix = place(
        e.x0 + e.dx * t + e.nx * offset,
        0,
        e.z0 + e.dz * t + e.nz * offset,
        e.dx * fdir,
        e.dz * fdir,
    )
    plan.cars.append(CarPlacement(matrix, car_color(random)))


def _plan_corners(
    mut plan: CityPlan, block_x: Float64, block_z: Float64, top: Float64
):
    """Place a block's corner furniture: a signal on two opposite corners
    and a basket on every corner."""
    var w = plan.layout.block_w
    var d = plan.layout.block_d
    for corner in range(4):  # pragma: no branch
        var cx = corner % 2
        var cz = corner // 2
        var x = block_x + Float64(cx) * w
        var z = block_z + Float64(cz) * d
        var ix = -1.0 if cx == 1 else 1.0
        var iz = -1.0 if cz == 1 else 1.0
        if cx == cz:
            plan.signals.append(
                place(x + ix * 1.4, top, z + iz * 1.4, -ix, -iz)
            )
        plan.cans.append(place(x + ix * 2.2, top, z + iz * 2.2, ix, iz))


def _plan_block(
    mut plan: CityPlan,
    mut random: SeededRandom,
    bx: Int,
    bz: Int,
    curb: Float64,
):
    """Lay out one block: its slab when the curb has a height, and a tower
    on each lot, lot by lot."""
    var layout = plan.layout
    var block_x = layout.block_x(bx)
    var block_z = layout.block_z(bz)
    if curb > 0:
        plan.slabs.append(
            basis_matrix(
                Vec3d(1, 0, 0),
                Vec3d(0, 1, 0),
                Vec3d(0, 0, 1),
                Vec3d(
                    block_x + layout.block_w / 2,
                    0,
                    block_z + layout.block_d / 2,
                ),
            )
        )
    var walk = layout.sidewalk_width
    for lx in range(layout.lots_x):  # pragma: no branch
        for lz in range(layout.lots_z):  # pragma: no branch
            _plan_tower(
                plan, random, block_x + walk, block_z + walk, lx, lz, curb
            )


def _plan_block_furniture(
    mut plan: CityPlan, mut random: SeededRandom, bx: Int, bz: Int, top: Float64
):
    """Dress one block: its four curb edges, then its corners."""
    var layout = plan.layout
    var block_x = layout.block_x(bx)
    var block_z = layout.block_z(bz)
    var edges = block_edges(block_x, block_z, layout.block_w, layout.block_d)
    for i in range(4):  # pragma: no branch
        _plan_edge(plan, random, edges[i], top, layout.sidewalk_width)
    _plan_corners(plan, block_x, block_z, top)


struct City(Movable):
    """A built city: its plan, one geometry a tower, the sidewalk, and the
    instanced furniture. Each tower's geometry is in its own space; its
    plan's position is where it stands."""

    var plan: CityPlan
    var buildings: List[BufferGeometry]
    # The slabs and the curbs, or none when the curb has no height. three.js
    # builds the sidewalk then too, with no instance to draw.
    var sidewalk: Optional[SidewalkInstances]
    var furniture: List[Instances]

    def __init__(
        out self,
        var plan: CityPlan,
        var buildings: List[BufferGeometry],
        var sidewalk: Optional[SidewalkInstances],
        var furniture: List[Instances],
    ):
        """Gather the parts of a city.

        Args:
            plan: The layout.
            buildings: One geometry a tower.
            sidewalk: The slabs and the curbs, or none.
            furniture: The streetlights, signals, baskets, benches,
                hydrants and trees, then the people and the cars.
        """
        self.plan = plan^
        self.buildings = buildings^
        self.sidewalk = sidewalk^
        self.furniture = furniture^

    def building_matrix(self, index: Int) raises -> Matrix4:
        """Return where one tower stands, three.js's `building.position`.

        Args:
            index: Which tower, from zero.

        Returns:
            The placement: a move to the tower's base.

        Raises:
            Error: If there is no such tower.
        """
        if index < 0 or index >= len(self.plan.towers):
            raise Error("A city has no tower at that index")
        var at = self.plan.towers[index].position
        return basis_matrix(Vec3d(1, 0, 0), Vec3d(0, 1, 0), Vec3d(0, 0, 1), at)


struct CityGenerator(Movable):
    """Lays out and builds a city, three.js's `CityGenerator`."""

    var parameters: CityParameters

    def __init__(out self):
        """Create a generator with three.js's default city."""
        self.parameters = CityParameters()

    def __init__(out self, var parameters: CityParameters):
        """Create a generator with given parameters.

        Args:
            parameters: The city.
        """
        self.parameters = parameters^

    def layout(self) raises -> CityLayout:
        """Return the city's dimensions, three.js's `layout`.

        Returns:
            The layout.

        Raises:
            Error: If the parameters are refused; see `city_layout`.
        """
        return city_layout(self.parameters)

    def plan(self) raises -> CityPlan:
        """Lay the city out without building it: every tower's parameters
        and every placement, drawn from the seed in three.js's order.

        Returns:
            The plan.

        Raises:
            Error: If the parameters are refused; see `city_layout`.
        """
        var plan = CityPlan(self.layout())
        var layout = plan.layout
        var random = generator_random(self.parameters.seed)
        var curb = meters(self.parameters.curb_height)
        for bx in range(layout.blocks_x):  # pragma: no branch
            for bz in range(layout.blocks_z):  # pragma: no branch
                _plan_block(plan, random, bx, bz, curb)
        for bx in range(layout.blocks_x):  # pragma: no branch
            for bz in range(layout.blocks_z):  # pragma: no branch
                _plan_block_furniture(plan, random, bx, bz, curb)
        return plan^

    def sidewalk(self) raises -> SidewalkGenerator:
        """Return the sidewalk generator three.js's constructor makes: one
        slab the size of a block.

        Returns:
            The generator.

        Raises:
            Error: If the parameters are refused; see `city_layout`.
        """
        var layout = self.layout()
        var sidewalk = SidewalkGenerator()
        sidewalk.width = _len(layout.block_w)
        sidewalk.depth = _len(layout.block_d)
        sidewalk.height = self.parameters.curb_height
        sidewalk.radius = self.parameters.curb_radius
        return sidewalk^

    def build(self) raises -> City:
        """Lay the city out and build it, three.js's `build`.

        Returns:
            The city.

        Raises:
            Error: If the parameters are refused, or a part cannot be built.
        """
        var plan = self.plan()
        var buildings = List[BufferGeometry]()
        for i in range(len(plan.towers)):  # pragma: no branch
            buildings.append(
                SkyscraperGenerator(plan.towers[i].parameters.copy()).build()
            )
        var sidewalk = Optional[SidewalkInstances](None)
        if len(plan.slabs) > 0:
            sidewalk = self.sidewalk().build(plan.slabs)
        var furniture: List[Instances] = [
            StreetlightGenerator().build(plan.lights),
            TrafficlightGenerator().build(plan.signals),
            TrashcanGenerator().build(plan.cans),
            BenchGenerator().build(plan.benches),
            HydrantGenerator().build(plan.hydrants),
            StreetTreeGenerator().build(plan.trees),
        ]
        var people = PersonGenerator().build(plan.people)
        for _ in range(len(people)):  # pragma: no branch
            furniture.append(people.pop(0))
        var cars = CarGenerator().build(plan.cars)
        while len(cars) > 0:
            furniture.append(cars.pop(0))
        return City(plan^, buildings^, sidewalk^, furniture^)

    def build_proxy(self, plan: CityPlan) raises -> Instances:
        """Return one plain box a tower, three.js's `buildProxy`: a cheap
        stand-in for a global illumination bake, which casts the same
        street shadows.

        Args:
            plan: The city's plan.

        Returns:
            The boxes, named `CityProxy`, one unit box stretched a tower.

        Raises:
            Error: If the unit box cannot be built.
        """
        var boxes = List[Matrix4]()
        for i in range(len(plan.towers)):
            ref t = plan.towers[i]
            boxes.append(
                basis_matrix(
                    Vec3d(t.box_size.x, 0, 0),
                    Vec3d(0, t.box_size.y, 0),
                    Vec3d(0, 0, t.box_size.z),
                    t.box_center,
                )
            )
        return placed("CityProxy", box(_len(1), _len(1), _len(1)), boxes)
