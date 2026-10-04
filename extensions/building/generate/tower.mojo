# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A seeded tower as a canonical building model.

`generate_tower` reads the same seeded style as the procedural skyscraper
of `generators.skyscraper`: the footprint with its cut corner, the floor
height, the bay width, the shares of the base and the crown, and the
crown's setback. It then writes a building model instead of a mesh:

- The first storey is a lobby with shops. The rest of the base and the
  crown are offices. The shaft holds offices or homes.
- The crown's footprint is the shaft's, set back by the setback depth
  times the bay width on every side.
- Each storey gets a floor plan from `plan_floor`. Storeys of one tier
  share a plan, so their walls stand on each other.
- Outside walls get a window per bay, and rooms get doors.
- A concrete frame stands on one column grid for every storey: columns
  along the outside and the corridor lines, joined by beams.
- Rooms get furniture from `furnish`.

The skyscraper generator is a port of three.js and keeps its own output.
This module only reads its style.

The model is z up with y north. A three.js point (x, y, z) is the plan
point (x, -z).
"""

from std.math import floor, sqrt
from extensions.building.construction import (
    Construction,
    Layer,
    double_glazing,
)
from extensions.building.generate.furnish import furnish
from extensions.building.generate.openings import (
    WindowOptions,
    add_doors,
    add_windows,
)
from extensions.building.generate.plan import (
    FloorProgram,
    LOBBY_FLOOR,
    OFFICE_FLOOR,
    PlanOptions,
    RESIDENTIAL_FLOOR,
    clip_half,
    default_plan_options,
    plan_floor,
)
from extensions.building.ids import ConstructionId, MaterialId, StoreyId
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
    steel,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    rectangle,
)
from extensions.topology.arrangement import Point2, contains
from generators.skyscraper import (
    SkyscraperParameters,
    SkyscraperStyle,
    build_footprint,
    pick_building_color,
)
from units.si import Angle64, DEGREE, Length64, METER


struct TowerOptions(Copyable, Movable):
    """What `generate_tower` builds."""

    var parameters: SkyscraperParameters
    # The program of the shaft's storeys.
    var shaft: FloorProgram
    var plan: PlanOptions
    var furnished: Bool
    var frame: Bool

    def __init__(out self, var parameters: SkyscraperParameters):
        """Create options with offices in the shaft, furniture and a frame.

        Args:
            parameters: The skyscraper parameters and seed.
        """
        self.parameters = parameters^
        self.shaft = OFFICE_FLOOR
        self.plan = default_plan_options()
        self.furnished = True
        self.frame = True


def inset(polygon: List[Point2], distance: Float64) -> List[Point2]:
    """Return a convex polygon with every edge moved inward by a distance.

    Args:
        polygon: The corners, counterclockwise.
        distance: How far to move each edge, in meters.

    Returns:
        The smaller polygon, or an empty list when nothing is left.
    """
    var out = polygon.copy()
    var n = len(polygon)
    for i in range(n):  # pragma: no branch
        var a = polygon[i]
        var b = polygon[(i + 1) % n]
        var d = b - a
        var length = sqrt(d.dot(d))
        # Outward normal of a counterclockwise edge.
        var normal = Point2(d.y / length, -d.x / length)
        out = clip_half(out, normal, normal.dot(a) - distance)
    return out^


def _materials(seed: Int) raises -> List[BuildingMaterial]:
    """Return the tower's materials, with the brick tinted by the seed."""
    var out = List[BuildingMaterial]()
    var facade = brick()
    var color = pick_building_color(seed)
    facade.name = "terracotta"
    facade.look.red = Float32((color >> 16) & 255) / 255
    facade.look.green = Float32((color >> 8) & 255) / 255
    facade.look.blue = Float32(color & 255) / 255
    out.append(facade^)
    out.append(mineral_wool())
    out.append(gypsum_board())
    out.append(concrete())
    out.append(steel())
    return out^


def _constructions() -> List[Construction]:
    """Return the outside wall, partition, ground slab, floor and roof."""
    var m = Length64(1, METER)
    var out = List[Construction]()
    out.append(
        Construction(
            "terracotta wall",
            [
                Layer(MaterialId(0), m.scaled(0.2)),
                Layer(MaterialId(1), m.scaled(0.1)),
                Layer(MaterialId(2), m.scaled(0.0125)),
            ],
        )
    )
    out.append(
        Construction(
            "partition",
            [
                Layer(MaterialId(2), m.scaled(0.0125)),
                Layer(MaterialId(1), m.scaled(0.075)),
                Layer(MaterialId(2), m.scaled(0.0125)),
            ],
        )
    )
    out.append(
        Construction("ground slab", [Layer(MaterialId(3), m.scaled(0.3))])
    )
    out.append(
        Construction("floor slab", [Layer(MaterialId(3), m.scaled(0.25))])
    )
    out.append(
        Construction(
            "roof",
            [
                Layer(MaterialId(1), m.scaled(0.15)),
                Layer(MaterialId(3), m.scaled(0.25)),
            ],
        )
    )
    return out^


def _grid(
    footprint: List[Point2], bay: Float64, corridor: Float64
) -> List[List[Point2]]:
    """Return column lines across the footprint: one list of points per
    line along its longest edge.

    The lines run along the footprint's longest edge: two just inside its
    long sides and two on the corridor's edges. The points along each line
    are every three bays.
    """
    var n = len(footprint)
    var u = Point2(1, 0)
    var best = Float64(0)
    for i in range(n):  # pragma: no branch
        var d = footprint[(i + 1) % n] - footprint[i]
        if d.dot(d) > best:
            best = d.dot(d)
            var length = sqrt(best)
            u = Point2(d.x / length, d.y / length)
    var v = Point2(-u.y, u.x)
    var u_low = Float64.MAX
    var u_high = -Float64.MAX
    var v_low = Float64.MAX
    var v_high = -Float64.MAX
    for i in range(n):  # pragma: no branch
        u_low = min(u_low, footprint[i].dot(u))
        u_high = max(u_high, footprint[i].dot(u))
        v_low = min(v_low, footprint[i].dot(v))
        v_high = max(v_high, footprint[i].dot(v))
    var middle = (v_low + v_high) / 2
    var lines: List[Float64] = [
        v_low + 0.5,
        middle - corridor / 2,
        middle + corridor / 2,
        v_high - 0.5,
    ]
    var step = 3 * bay
    var count = max(1, Int(floor((u_high - u_low - 1) / step)))
    var spacing = (u_high - u_low - 1) / Float64(count)
    var out = List[List[Point2]]()
    for l in range(4):  # pragma: no branch
        var row = List[Point2]()
        for k in range(count + 1):  # pragma: no branch
            var a = u_low + 0.5 + Float64(k) * spacing
            row.append(
                Point2(u.x * a + v.x * lines[l], u.y * a + v.y * lines[l])
            )
        out.append(row^)
    return out^


def _well_inside(footprint: List[Point2], p: Point2) -> Bool:
    """Return True if a point is inside a footprint, 0.3 m from its edges."""
    return contains(inset(footprint, 0.3), p)


def generate_tower(options: TowerOptions) raises -> Building:
    """Return a seeded tower as a building model.

    Args:
        options: The skyscraper parameters, the shaft's program, the plan
            sizes, and whether to add furniture and a frame.

    Returns:
        The model, with doors and windows, and with a frame and furniture
        when the options ask for them.

    Raises:
        Error: If the style or the plan options are not valid, the shaft's
            program is not valid, or the footprint is too small for a plan.
    """
    var p = options.parameters.copy()
    var style = SkyscraperStyle(p)
    var corners = build_footprint(
        style.footprint_width,
        style.footprint_depth,
        style.chamfer_width,
        style.chamfer_corner_x,
        style.chamfer_corner_z,
    )
    var footprint = List[Point2]()
    for i in range(len(corners)):  # pragma: no branch
        footprint.append(Point2(corners[i].x, -corners[i].z))
    # three.js's order runs clockwise in plan; the plans want it the other
    # way.
    footprint.reverse()
    var floors = max(
        1, Int(floor(style.total_height / style.floor_height + 0.5))
    )
    var base = min(
        floors, max(1, Int(floor(Float64(floors) * style.base_fraction + 0.5)))
    )
    var crown = min(
        floors - base, Int(floor(Float64(floors) * style.crown_fraction + 0.5))
    )
    var crown_footprint = inset(
        footprint, style.setback_depth * style.bay_width
    )
    var plans = List[StoreyPlan]()
    var tier_plans = List[List[SpacePlan]]()
    var programs = [LOBBY_FLOOR, OFFICE_FLOOR, options.shaft]
    for t in range(3):  # pragma: no branch
        tier_plans.append(
            plan_floor(footprint, programs[t], p.seed * 7 + t, options.plan)
        )
    # A crown too small for a plan keeps the shaft's footprint.
    try:
        tier_plans.append(
            plan_floor(
                crown_footprint, OFFICE_FLOOR, p.seed * 7 + 3, options.plan
            )
        )
    except:
        crown_footprint = footprint.copy()
        tier_plans.append(
            plan_floor(footprint, OFFICE_FLOOR, p.seed * 7 + 3, options.plan)
        )
    var height = Length64(style.floor_height, METER)
    for s in range(floors):  # pragma: no branch
        var tier = 2
        if s == 0:
            tier = 0
        elif s < base:
            tier = 1
        elif s >= floors - crown:
            tier = 3
        plans.append(
            StoreyPlan(String("storey ", s), height, tier_plans[tier].copy())
        )
    var building = assemble(
        String("tower ", p.seed),
        Site(
            Angle64(40.7, DEGREE),
            Angle64(-74.0, DEGREE),
            Length64(10, METER),
            Angle64(0),
        ),
        Length64(0, METER),
        plans,
        _materials(p.seed),
        _constructions(),
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(3),
            ConstructionId(4),
        ),
        Length64(1e-6, METER),
    )
    _ = add_doors(building, Length64(0.9, METER), Length64(2.1, METER))
    var sill = (style.floor_height - style.window_height) / 2
    _ = add_windows(
        building,
        WindowOptions(
            Length64(style.bay_width, METER),
            Length64(style.pier_width, METER),
            Length64(sill, METER),
            Length64(style.window_height, METER),
            double_glazing(),
        ),
    )
    if options.frame:
        var grid = _grid(
            footprint, style.bay_width, options.plan.corridor_width.to(METER)
        )
        var column = rectangle(Length64(0.5, METER), Length64(0.5, METER))
        var beam = rectangle(Length64(0.4, METER), Length64(0.6, METER))
        var material = MaterialId(3)
        for s in range(floors):  # pragma: no branch
            ref outline = crown_footprint if s >= floors - crown else footprint
            for l in range(len(grid)):  # pragma: no branch
                for k in range(len(grid[l])):  # pragma: no branch
                    var here = grid[l][k]
                    if not _well_inside(outline, here):
                        continue
                    _ = building.add_column(StoreyId(s), here, column, material)
                    # Beams to the next point along the line and across.
                    if k + 1 < len(grid[l]) and _well_inside(
                        outline, grid[l][k + 1]
                    ):
                        _ = building.add_beam(
                            StoreyId(s), here, grid[l][k + 1], beam, material
                        )
                    if l + 1 < len(grid) and _well_inside(
                        outline, grid[l + 1][k]
                    ):
                        _ = building.add_beam(
                            StoreyId(s), here, grid[l + 1][k], beam, material
                        )
    if options.furnished:
        _ = furnish(building, p.seed)
    return building^
