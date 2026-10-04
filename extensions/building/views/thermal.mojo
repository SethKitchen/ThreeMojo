# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The thermal view: a `ZoneModel` from a `Building`.

Each space becomes a zone, or a group of spaces becomes one zone. Each
face of a wall, slab or roof becomes a surface with the element's
construction:

| Face | Surface |
|---|---|
| A space on both sides | `INTERZONE`, between the two zones |
| The outside below a floor at level 0 | `GROUND` |
| The outside on any other side | `EXTERIOR` |

A window in an exterior wall becomes a `Window` with its glazing, and its
area leaves the wall's surface. The view records what it drops in
`ThermalView.dropped`.
"""

from extensions.building.ids import OpeningId, SpaceId
from extensions.building.kinds import COLUMN, BEAM, DOOR
from extensions.building.model import Building
from extensions.energy.ids import EXTERIOR, GROUND, INTERZONE, ZoneId
from extensions.energy.zone import (
    AIR_CHANGE_PER_HOUR,
    InternalGains,
    Surface,
    Window,
    Zone,
    ZoneModel,
    interior_film,
    outside_film_coefficient,
    typical_gains,
)
from extensions.topology.ids import CellId, FaceId
from generators.utils import Vec3d
from units.si import (
    Area64,
    Frequency64,
    HeatCapacity64,
    HeatFlux64,
    METER,
    SQUARE_METER,
    Volume64,
    WATT_PER_SQUARE_METER,
)
from units.temperature import CELSIUS, Temperature64


@fieldwise_init
struct ThermalViewOptions(ImplicitlyCopyable):
    """The settings the view gives every zone."""

    var heating_setpoint: Temperature64
    var cooling_setpoint: Temperature64
    var infiltration: Frequency64


def default_thermal_options() -> ThermalViewOptions:
    """Return typical settings for an occupied building.

    Returns:
        Heating to 20 and cooling to 26 degrees Celsius, and 0.5 air
        changes per hour of infiltration.
    """
    return ThermalViewOptions(
        Temperature64(20, CELSIUS),
        Temperature64(26, CELSIUS),
        Frequency64(0.5, AIR_CHANGE_PER_HOUR),
    )


struct ThermalView(Movable):
    """A zone model and how it maps to the building."""

    var model: ZoneModel
    # The zone of each space.
    var space_zone: List[ZoneId]
    # The face of the complex under each surface.
    var surface_face: List[FaceId]
    # The opening under each window.
    var window_opening: List[OpeningId]
    # What the view leaves out, one line each.
    var dropped: List[String]

    def __init__(out self, var model: ZoneModel):
        """Hold a zone model with empty maps.

        Args:
            model: The zone model.
        """
        self.model = model^
        self.space_zone = List[ZoneId]()
        self.surface_face = List[FaceId]()
        self.window_opening = List[OpeningId]()
        self.dropped = List[String]()


def _zone_ids(
    building: Building, grouping: List[ZoneId]
) raises -> List[ZoneId]:
    var spaces = len(building.spaces)
    var out = List[ZoneId]()
    if len(grouping) == 0:
        for i in range(spaces):
            out.append(ZoneId(i))
        return out^
    if len(grouping) != spaces:
        raise Error("A grouping needs one zone per space")
    var count = 0
    for i in range(spaces):  # pragma: no branch
        if not grouping[i].is_valid():
            raise Error("A zone id is out of range")
        count = max(count, grouping[i].value + 1)
    var used = List[Bool](length=count, fill=False)
    for i in range(spaces):  # pragma: no branch
        used[grouping[i].value] = True
    for k in range(count):  # pragma: no branch
        if not used[k]:
            raise Error("A grouping must use every zone from 0 up")
    return grouping.copy()


@fieldwise_init
struct _Side(ImplicitlyCopyable):
    # The cell on the construction's inside face, the cell on its outside
    # face if any, and the unit normal from the inside face outward.
    var inside: CellId
    var outside: Optional[CellId]
    var normal: Vec3d


def _side(building: Building, face: FaceId) raises -> _Side:
    # The positive cell of a face between two cells is inside. An
    # exterior face has its one cell inside.
    ref f = building.topology.complex.faces[face.value]
    var n = building.topology.complex.face_normal(face)
    if f.positive and f.negative:
        return _Side(f.positive.value(), f.negative.value(), n * -1.0)
    if f.positive:
        return _Side(f.positive.value(), None, n * -1.0)
    return _Side(f.negative.value(), None, n)


def thermal_view(
    building: Building, options: ThermalViewOptions, grouping: List[ZoneId]
) raises -> ThermalView:
    """Return the zone model of a building.

    Args:
        building: The model, as `assemble` makes it.
        options: The setpoints and infiltration of every zone.
        grouping: The zone of each space, numbered from 0 with no gap; or
            empty for one zone per space.

    Returns:
        The zones, surfaces and windows, the maps back to the building
        and what the view dropped.

    Raises:
        Error: If the building is not valid, the grouping has the wrong
            length or skips a zone, or a zone setting is not valid.
    """
    building.validate()
    var zone_of_space = _zone_ids(building, grouping)
    var zone_count = 0
    for i in range(len(zone_of_space)):
        zone_count = max(zone_count, zone_of_space[i].value + 1)
    ref complex = building.topology.complex
    var zone_of_cell = List[ZoneId](
        length=complex.cell_count(), fill=ZoneId(-1)
    )
    for i in range(len(building.spaces)):
        zone_of_cell[building.spaces[i].cell.value] = zone_of_space[i]

    var view = ThermalView(
        ZoneModel(
            building.site,
            building.materials.copy(),
            building.constructions.copy(),
        )
    )
    view.space_zone = zone_of_space.copy()

    # Zones: the sums of their spaces, with area-weighted gains.
    for k in range(zone_count):
        var name = String()
        var first = -1
        var volume = 0.0
        var area = 0.0
        var people = 0.0
        var lighting = 0.0
        var equipment = 0.0
        for i in range(len(building.spaces)):  # pragma: no branch
            if zone_of_space[i].value != k:
                continue
            ref space = building.spaces[i]
            if first < 0:
                first = i
                name = space.name
            else:
                name += String(" + ", space.name)
            var a = building.floor_area(SpaceId(i)).to(SQUARE_METER)
            volume += building.volume(SpaceId(i)).value
            area += a
            var g = typical_gains(space.use)
            people += g.people.value * a
            lighting += g.lighting.value * a
            equipment += g.equipment.value * a
        var scale = 1.0 / area
        _ = view.model.add_zone(
            Zone(
                name^,
                building.spaces[first].use,
                Volume64(volume),
                Area64(area, SQUARE_METER),
                options.infiltration,
                InternalGains(
                    HeatFlux64(people * scale, WATT_PER_SQUARE_METER),
                    HeatFlux64(lighting * scale, WATT_PER_SQUARE_METER),
                    HeatFlux64(equipment * scale, WATT_PER_SQUARE_METER),
                ),
                options.heating_setpoint,
                options.cooling_setpoint,
                HeatCapacity64(0),
            )
        )

    # Windows in exterior walls; the area they take from each element.
    var glazed = List[Float64](length=len(building.elements), fill=0.0)
    var doors = 0
    for i in range(len(building.openings)):
        ref opening = building.openings[i]
        if opening.kind == DOOR:
            doors += 1
            continue
        var host = opening.host.value
        var side = _side(building, building.elements[host].faces[0])
        if side.outside:
            view.dropped.append(
                String(opening.name, ": in an interior wall, kept as wall")
            )
            continue
        var area = opening.width.to(METER) * opening.height.to(METER)
        glazed[host] += area
        _ = view.model.add_window(
            Window(
                opening.name,
                zone_of_cell[side.inside.value],
                Area64(area, SQUARE_METER),
                opening.glazing.value(),
                side.normal,
            )
        )
        view.window_opening.append(OpeningId(i))
    if doors > 0:
        view.dropped.append(
            String(doors, " doors: kept as part of their walls' construction")
        )

    # Surfaces: one per face of each wall, slab and roof. The windows of an
    # element leave its first face.
    var frames = 0
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        if element.kind == COLUMN or element.kind == BEAM:
            frames += 1
            continue
        var construction = element.construction.value()
        var glass = glazed[e]
        for j in range(len(element.faces)):  # pragma: no branch
            var face = element.faces[j]
            var area = complex.face_area(face) - glass
            glass = 0
            if area <= 1e-9:
                view.dropped.append(
                    String(element.name, ": fully glazed, no opaque surface")
                )
                continue
            var side = _side(building, face)
            var boundary = EXTERIOR
            var outside = Optional[ZoneId](None)
            var outside_film = outside_film_coefficient()
            if side.outside:
                boundary = INTERZONE
                outside = zone_of_cell[side.outside.value().value]
                outside_film = interior_film(side.normal * -1.0)
            else:
                var level = building.topology.face_level[face.value]
                if side.normal.z < -0.5 and level == 0:
                    boundary = GROUND
            _ = view.model.add_surface(
                Surface(
                    String(element.name, " face ", face.value),
                    construction,
                    boundary,
                    zone_of_cell[side.inside.value],
                    outside,
                    Area64(area, SQUARE_METER),
                    side.normal,
                    interior_film(side.normal),
                    outside_film,
                )
            )
            view.surface_face.append(face)
    if frames > 0:
        view.dropped.append(
            String(frames, " columns and beams: frame members carry no heat")
        )
    view.dropped.append(
        "Furniture and contents: not in the model; set Zone.furniture"
    )
    view.dropped.append(
        "Window frames and reveals: each window is one plane in its wall"
    )
    return view^
