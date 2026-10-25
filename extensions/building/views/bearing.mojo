# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bearing view of a building: the gravity load down its walls, storey
by storey, and the mass of each element.

A masonry or stone building carries its floors and its roof on its walls.
`structural_view` drops the walls, so it cannot check such a building.
`bearing_check` takes the load down instead:

- **Mass.** An element with a construction weighs its area times the sum
  of each layer's density times its thickness. A wall loses the area of
  its openings. A column or a beam weighs its section area times its
  length times its material's density.
- **Load at the base of a storey's walls.** The dead load is the weight
  of the walls of that storey and every storey above, of the floors above
  it and of the roofs from that storey up. The live load is each floor
  above it times the largest live load of its storey's spaces, and each
  roof times the roof live load. A ground slab rests on the ground and
  loads no wall.
- **Capacity.** Each wall bears on its strongest layer. The net length is
  the face's area over the storey's height, less the openings' widths.
  The capacity is the resistance factor times the strength times the net
  length times the layer's thickness, summed over the storey's walls.
- **Demand.** `dead_factor` times the dead load plus `live_factor` times
  the live load. The defaults, 1.2 and 1.6, are the strength combination
  of ASCE/SEI 7-16, section 2.3.1. The resistance factor 0.6 is that of
  unreinforced masonry in axial compression in TMS 402/602-16.

This is an average, not a design check. The load is spread over a
storey's walls by bearing area, with no tributary areas, eccentricity,
slenderness, buckling, lateral load or soil. A column or a beam adds its
weight; the walls get all of it. The materials and loads are typical
values. The result is a first look at whether a scanned or generated
building can stand, and how close it is.
"""

from extensions.building.ids import ElementId, StoreyId
from extensions.building.kinds import BEAM, COLUMN, ROOF, SLAB, WALL
from extensions.building.model import Building
from extensions.building.views.structural import live_load, roof_live_load
from extensions.topology.ids import FaceId
from math.finite import require_positive_finite
from std.math import inf, isfinite
from units.si import (
    Acceleration64,
    Area64,
    Force64,
    KILOGRAM,
    Length64,
    Mass64,
    METER,
    METER_PER_SECOND_SQUARED,
    NEWTON,
    Pressure64,
    SQUARE_METER,
)


@fieldwise_init
struct BearingOptions(ImplicitlyCopyable):
    """The gravity and the factors of a bearing check."""

    var gravity: Acceleration64
    """The acceleration of gravity, downward."""
    var dead_factor: Float64
    """The factor on the dead load."""
    var live_factor: Float64
    """The factor on the live load."""
    var resistance_factor: Float64
    """The resistance factor on the walls' strength."""

    def check(self) raises:
        """Refuse options that cannot weigh a building.

        Raises:
            Error: If the gravity or a factor is not positive and finite,
                or the resistance factor is above one.
        """
        require_positive_finite(
            self.gravity.value, "Bearing: the gravity must be positive"
        )
        require_positive_finite(
            self.dead_factor, "Bearing: the dead factor must be positive"
        )
        require_positive_finite(
            self.live_factor, "Bearing: the live factor must be positive"
        )
        require_positive_finite(
            self.resistance_factor,
            "Bearing: the resistance factor must be positive",
        )
        if self.resistance_factor > 1:
            raise Error("Bearing: the resistance factor is at most one")


def default_bearing_options() -> BearingOptions:
    """Return standard gravity and the ASCE 7 and TMS 402 factors.

    Returns:
        9.80665 m/s^2, 1.2 dead, 1.6 live and a resistance factor of 0.6.
    """
    return BearingOptions(
        Acceleration64(9.80665, METER_PER_SECOND_SQUARED), 1.2, 1.6, 0.6
    )


@fieldwise_init
struct StoreyBearing(ImplicitlyCopyable):
    """The load and the capacity at the base of one storey's walls."""

    var storey: StoreyId
    """The storey."""
    var dead: Force64
    """The unfactored dead load."""
    var live: Force64
    """The unfactored live load."""
    var demand: Force64
    """The factored load."""
    var capacity: Force64
    """The factored resistance of the storey's walls."""
    var wall_length: Length64
    """The net length of the storey's walls."""

    def utilization(self) -> Float64:
        """Return the demand over the capacity.

        Returns:
            The ratio. A storey with no wall capacity gives infinity.
        """
        if self.capacity.value <= 0:
            return inf[DType.float64]()
        return self.demand.value / self.capacity.value


struct BearingCheck(Movable):
    """The bearing view of a building."""

    var storeys: List[StoreyBearing]
    """One entry for each storey, from the lowest up."""
    var mass: Mass64
    """The mass of every element."""
    var notes: List[String]
    """What the check leaves out for this building."""

    def __init__(
        out self,
        var storeys: List[StoreyBearing],
        mass: Mass64,
        var notes: List[String],
    ):
        """Hold a check's results.

        Args:
            storeys: The storeys.
            mass: The building's mass.
            notes: The notes.
        """
        self.storeys = storeys^
        self.mass = mass
        self.notes = notes^

    def utilization(self) -> Float64:
        """Return the largest utilization of any storey.

        Returns:
            The ratio, or zero for a building with no storey.
        """
        var most = Float64(0)
        for storey in self.storeys:
            most = max(most, storey.utilization())
        return most


def _area(building: Building, element: ElementId) raises -> Area64:
    """Return the area of an element's faces, less its openings.

    Args:
        building: The model.
        element: The element.

    Returns:
        The net area.

    Raises:
        Error: If the element is not in the model.
    """
    building.check_element(element)
    var total = Float64(0)
    for face in building.elements[element.value].faces:
        total += building.topology.complex.face_area(face)
    for opening in building.openings_of(element):
        ref o = building.openings[opening.value]
        total -= o.width.to(METER) * o.height.to(METER)
    return Area64(max(total, 0), SQUARE_METER)


def element_mass(building: Building, element: ElementId) raises -> Mass64:
    """Return the mass of an element; see the module docstring.

    Args:
        building: The model.
        element: The element.

    Returns:
        The mass. An element with neither a construction nor a section and
        material weighs nothing.

    Raises:
        Error: If the element is not in the model.
    """
    building.check_element(element)
    ref e = building.elements[element.value]
    if e.construction:
        var per_area = Float64(0)
        for layer in building.constructions[
            e.construction.value().value
        ].layers:
            var material = building.materials[layer.material.value].copy()
            per_area += material.density.value * layer.thickness.to(METER)
        return Mass64(per_area * _area(building, element).value, KILOGRAM)
    if e.section and e.material:
        var length = (e.end - e.start).length()
        var density = building.materials[e.material.value().value].density
        return Mass64(
            density.value * e.section.value().area().value * length, KILOGRAM
        )
    return Mass64(0, KILOGRAM)


def _wall_capacity(
    building: Building,
    element: ElementId,
    height: Float64,
    factor: Float64,
) raises -> Tuple[Float64, Float64]:
    """Return a wall's net length and factored capacity.

    Args:
        building: The model.
        element: The wall.
        height: Its storey's height, in meters.
        factor: The resistance factor.

    Returns:
        The net length in meters and the capacity in newtons.

    Raises:
        Error: If the element is not in the model.
    """
    ref e = building.elements[element.value]
    var gross = Float64(0)
    for face in e.faces:
        gross += building.topology.complex.face_area(face)
    var length = gross / height
    for opening in building.openings_of(element):
        length -= building.openings[opening.value].width.to(METER)
    length = max(length, 0)
    var strongest = Float64(0)
    var thickness = Float64(0)
    if e.construction:
        for layer in building.constructions[
            e.construction.value().value
        ].layers:
            var strength = building.materials[
                layer.material.value
            ].strength.value
            if strength > strongest:
                strongest = strength
                thickness = layer.thickness.to(METER)
    return (length, factor * strongest * length * thickness)


def _floor_live_load(building: Building, storey: StoreyId) raises -> Float64:
    """Return the largest live load of a storey's spaces, in pascals.

    Args:
        building: The model.
        storey: The storey whose floor it is.

    Returns:
        The load, or zero for a storey with no space.

    Raises:
        Error: If a space use is not valid.
    """
    var most = Float64(0)
    for space in building.spaces:
        if space.storey == storey:
            most = max(most, live_load(space.use).value)
    return most


def bearing_check(
    building: Building, options: BearingOptions
) raises -> BearingCheck:
    """Return the gravity load and capacity at the base of each storey's
    walls; see the module docstring.

    Args:
        building: The model.
        options: The gravity and the factors.

    Returns:
        The check.

    Raises:
        Error: If the options are not valid, a storey height is not
            positive, or a space use is not valid.
    """
    options.check()
    var g = options.gravity.value
    var count = len(building.storeys)
    var masses = List[Float64]()
    var total = Float64(0)
    var members = False
    for e in range(len(building.elements)):
        var mass = element_mass(building, ElementId(e)).value
        masses.append(mass)
        total += mass
        var kind = building.elements[e].kind
        if kind == COLUMN or kind == BEAM:
            members = True
    var storeys = List[StoreyBearing]()
    for s in range(count):
        var height = building.storeys[s].height.to(METER)
        require_positive_finite(
            height, "Bearing: a storey height must be positive"
        )
        var dead = Float64(0)
        var live = Float64(0)
        var length = Float64(0)
        var capacity = Float64(0)
        for e in range(len(building.elements)):
            ref element = building.elements[e]
            var at = element.storey.value
            if element.kind == SLAB:
                if at > s:
                    dead += masses[e] * g
                    live += _area(
                        building, ElementId(e)
                    ).value * _floor_live_load(building, element.storey)
            elif element.kind == ROOF:
                if at >= s:
                    dead += masses[e] * g
                    live += (
                        _area(building, ElementId(e)).value
                        * roof_live_load().value
                    )
            elif at >= s:
                dead += masses[e] * g
            if element.kind == WALL and at == s:
                var wall = _wall_capacity(
                    building, ElementId(e), height, options.resistance_factor
                )
                length += wall[0]
                capacity += wall[1]
        storeys.append(
            StoreyBearing(
                StoreyId(s),
                Force64(dead, NEWTON),
                Force64(live, NEWTON),
                Force64(
                    options.dead_factor * dead + options.live_factor * live,
                    NEWTON,
                ),
                Force64(capacity, NEWTON),
                Length64(length, METER),
            )
        )
    var notes = List[String]()
    notes.append(
        "The load is spread over each storey's walls by bearing area: no"
        " tributary areas, eccentricity, slenderness, lateral load or soil."
    )
    if members:
        notes.append(
            "The columns and beams add their weight, and the walls carry all"
            " of it: a frame's own load path is not followed."
        )
    return BearingCheck(storeys^, Mass64(total, KILOGRAM), notes^)
