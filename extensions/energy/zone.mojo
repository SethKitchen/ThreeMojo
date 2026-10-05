# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Thermal zones, their surfaces and windows, and their gains.

A `ZoneModel` holds zones of well-mixed air, the opaque surfaces that bound
them and the windows in their exterior walls. A surface has a
construction, an area and a normal. Its inside face sees its zone. Its
outside face sees the outdoors, another zone or the ground.

The film coefficients combine convection and long-wave radiation:

- An inside film is the inverse of the inside surface resistance of
  ISO 6946: 1/0.13 W/(m² K) for a wall, 1/0.10 for a ceiling, where heat
  flows up, and 1/0.17 for a floor, where heat flows down.
- An outside film is 1/0.04 = 25 W/(m² K), the outside surface resistance
  of ISO 6946. With these films, a surface's transmittance equals
  `Construction.u_value`.
- `exterior_film` gives the wind-dependent alternative of ISO 6946
  Annex C: h_c = 4 + 4 v and h_r = 4 epsilon sigma T³.

The internal gains are typical values per floor area for each `SpaceUse`,
of the order of those in the ASHRAE Handbook of Fundamentals chapter 18
and ISO 17772-1 Annex. They are typical values, not design values. A
project must use its own.
"""

from std.math import isfinite
from extensions.building.construction import (
    Construction,
    DOWNWARD_FLOW,
    Glazing,
    HORIZONTAL_FLOW,
    UPWARD_FLOW,
    inside_film,
)
from extensions.building.ids import ConstructionId
from extensions.building.kinds import SpaceUse
from extensions.building.material import BuildingMaterial
from extensions.building.model import Site
from extensions.energy.ids import (
    BoundaryKind,
    INTERZONE,
    SurfaceId,
    WindowId,
    ZoneId,
)
from generators.utils import Vec3d

from units.si import (
    Area64,
    CUBIC_METER,
    FrequencyUnit,
    Frequency64,
    HeatCapacity64,
    HeatFlux64,
    JOULE_PER_KELVIN,
    METER_PER_SECOND,
    PER_SECOND,
    SQUARE_METER,
    SQUARE_METER_KELVIN_PER_WATT,
    ThermalConductance64,
    ThermalTransmittance64,
    Velocity64,
    Volume64,
    WATT_PER_KELVIN,
    WATT_PER_SQUARE_METER,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import Temperature64

# One air change per hour.
comptime AIR_CHANGE_PER_HOUR = FrequencyUnit(1.0 / 3600.0, "1/h")
# Dry air at 20 degrees Celsius and 101.325 kPa, ASHRAE Handbook of
# Fundamentals chapter 1: 1.204 kg/m³ and 1006 J/(kg K).
comptime AIR_DENSITY = 1.204
comptime AIR_SPECIFIC_HEAT = 1006.0
# The Stefan-Boltzmann constant, W/(m² K⁴).
comptime STEFAN_BOLTZMANN = 5.670374419e-8


def _nonnegative(value: Float64, message: String) raises:
    if not (value >= 0 and isfinite(value)):
        raise Error(message)


def _positive(value: Float64, message: String) raises:
    if not (value > 0 and isfinite(value)):
        raise Error(message)


def _check_normal(normal: Vec3d) raises:
    _positive(normal.length(), "A normal must be nonzero and finite")


@fieldwise_init
struct InternalGains(ImplicitlyCopyable):
    """The peak heat that people, lights and equipment give, per floor area.

    All of it enters the zone air at once. The gains are sensible heat.
    """

    var people: HeatFlux64
    var lighting: HeatFlux64
    var equipment: HeatFlux64

    def total(self) -> HeatFlux64:
        """Return the sum of the three gains.

        Returns:
            People plus lighting plus equipment.
        """
        return self.people + self.lighting + self.equipment

    def check(self) raises:
        """Refuse a gain that is negative or not finite.

        Raises:
            Error: If a gain is negative or not finite.
        """
        var values = [
            self.people.value,
            self.lighting.value,
            self.equipment.value,
        ]
        for i in range(len(values)):  # pragma: no branch
            _nonnegative(values[i], "An internal gain must be zero or more")


def typical_gains(use: SpaceUse) raises -> InternalGains:
    """Return typical peak internal gains for a space use.

    The values, in W/m² of floor, are typical, not design values:

    | Use | People | Lighting | Equipment |
    |---|---|---|---|
    | office | 7 | 8 | 10 |
    | corridor | 1 | 5 | 0 |
    | core | 0 | 3 | 0 |
    | lobby | 3 | 8 | 1 |
    | retail | 6 | 12 | 3 |
    | living | 3 | 5 | 4 |
    | bedroom | 2 | 4 | 1 |
    | kitchen | 3 | 7 | 25 |
    | bathroom | 1 | 6 | 2 |
    | storage | 0 | 4 | 0 |
    | mechanical | 0 | 5 | 10 |
    | meeting | 20 | 10 | 5 |

    Args:
        use: The space use.

    Returns:
        The gains.

    Raises:
        Error: If the use is not valid.
    """
    if not use.is_valid():
        raise Error("A space use is not valid")
    var people: List[Float64] = [7, 1, 0, 3, 6, 3, 2, 3, 1, 0, 0, 20]
    var lighting: List[Float64] = [8, 5, 3, 8, 12, 5, 4, 7, 6, 4, 5, 10]
    var equipment: List[Float64] = [10, 0, 0, 1, 3, 4, 1, 25, 2, 0, 10, 5]
    var i = use.value
    return InternalGains(
        HeatFlux64(people[i], WATT_PER_SQUARE_METER),
        HeatFlux64(lighting[i], WATT_PER_SQUARE_METER),
        HeatFlux64(equipment[i], WATT_PER_SQUARE_METER),
    )


def gain_fraction(use: SpaceUse, hour: Int) raises -> Float64:
    """Return the share of the peak gains present in an hour of the day.

    There are four daily profiles, the same every day of the year:

    - Work (office, corridor, core, lobby, storage, meeting): 1 from 08:00
      to 18:00 and 0.1 otherwise.
    - Shop (retail): 1 from 09:00 to 21:00 and 0.1 otherwise.
    - Home (living, bedroom, kitchen, bathroom): 1 from 18:00 to 23:00,
      0.5 from 23:00 to 07:00 and 0.3 otherwise.
    - Mechanical: 1 at every hour.

    Args:
        use: The space use.
        hour: The hour of the day, 0 to 23, from local standard midnight.

    Returns:
        The share, zero to one.

    Raises:
        Error: If the use is not valid or the hour is out of range.
    """
    if not use.is_valid():
        raise Error("A space use is not valid")
    if hour < 0 or hour > 23:
        raise Error("An hour of the day must be 0 to 23")
    # The profile of each use: 0 work, 1 shop, 2 home, 3 always.
    var profile: List[Int] = [0, 0, 0, 0, 1, 2, 2, 2, 2, 0, 3, 0]
    var p = profile[use.value]
    if p == 0:
        return 1.0 if hour >= 8 and hour < 18 else 0.1
    if p == 1:
        return 1.0 if hour >= 9 and hour < 21 else 0.1
    if p == 2:
        if hour >= 18 and hour < 23:
            return 1.0
        return 0.3 if hour >= 7 and hour < 18 else 0.5
    return 1.0


def interior_film(outward: Vec3d) raises -> ThermalTransmittance64:
    """Return the inside film coefficient of ISO 6946 for a surface.

    Args:
        outward: The unit normal that points from the zone into the
            surface.

    Returns:
        1/0.17 W/(m² K) for a floor (normal down), 1/0.10 for a ceiling
        (normal up) and 1/0.13 otherwise.

    Raises:
        Error: If the normal is zero or not finite.
    """
    _check_normal(outward)
    var z = outward.z / outward.length()
    var direction = HORIZONTAL_FLOW
    if z < -0.5:
        direction = DOWNWARD_FLOW
    elif z > 0.5:
        direction = UPWARD_FLOW
    var one = Area64(1, SQUARE_METER) / Area64(1, SQUARE_METER)
    return one / inside_film(direction)


def outside_film_coefficient() -> ThermalTransmittance64:
    """Return the outside film coefficient of ISO 6946.

    Returns:
        25 W/(m² K), the inverse of 0.04 m² K/W.
    """
    return ThermalTransmittance64(25.0, WATT_PER_SQUARE_METER_KELVIN)


def exterior_film(
    wind_speed: Velocity64, air: Temperature64, emissivity: Float64
) raises -> ThermalTransmittance64:
    """Return a wind-dependent outside film coefficient.

    ISO 6946 Annex C: h = 4 + 4 v + 4 epsilon sigma T³, with T the air
    temperature in kelvin. At 4 m/s, 10 degrees Celsius and an emissivity
    of 0.9 it is about 25 W/(m² K).

    Args:
        wind_speed: The wind speed near the surface.
        air: The outdoor air temperature.
        emissivity: The long-wave emissivity of the surface, zero to one.

    Returns:
        The film coefficient.

    Raises:
        Error: If the speed is negative or not finite, the temperature is
            not valid or the emissivity is outside zero to one.
    """
    var v = wind_speed.to(METER_PER_SECOND)
    _nonnegative(v, "A wind speed must be zero or more and finite")
    if not air.is_valid():
        raise Error("An air temperature must be valid")
    if not (emissivity >= 0 and emissivity <= 1):
        raise Error("An emissivity must be zero to one")
    var t = air.kelvin
    var h = 4 + 4 * v + 4 * emissivity * STEFAN_BOLTZMANN * t * t * t
    return ThermalTransmittance64(h, WATT_PER_SQUARE_METER_KELVIN)


struct Zone(Copyable, Movable):
    """A volume of well-mixed air with its gains and setpoints."""

    var name: String
    var use: SpaceUse
    var volume: Volume64
    var floor_area: Area64
    # The outdoor air that leaks in, in air changes.
    var infiltration: Frequency64
    var gains: InternalGains
    var heating_setpoint: Temperature64
    var cooling_setpoint: Temperature64
    # Heat stored by furniture and contents, lumped with the air.
    var furniture: HeatCapacity64

    def __init__(
        out self,
        var name: String,
        use: SpaceUse,
        volume: Volume64,
        floor_area: Area64,
        infiltration: Frequency64,
        gains: InternalGains,
        heating_setpoint: Temperature64,
        cooling_setpoint: Temperature64,
        furniture: HeatCapacity64,
    ):
        """Create a zone. `ZoneModel.add_zone` checks it.

        Args:
            name: A name for people.
            use: What it is used for. It sets the daily gain profile.
            volume: Its air volume.
            floor_area: Its floor area, which scales the gains.
            infiltration: Its leakage, in air changes per unit time.
            gains: Its peak internal gains per floor area.
            heating_setpoint: The air temperature heating holds it above.
            cooling_setpoint: The air temperature cooling holds it below.
            furniture: Heat stored by its contents.
        """
        self.name = name^
        self.use = use
        self.volume = volume
        self.floor_area = floor_area
        self.infiltration = infiltration
        self.gains = gains
        self.heating_setpoint = heating_setpoint
        self.cooling_setpoint = cooling_setpoint
        self.furniture = furniture

    def check(self) raises:
        """Refuse a zone that cannot exist.

        Raises:
            Error: If the use is not valid, the volume is not positive and
                finite, the area, infiltration, a gain or the furniture is
                negative or not finite, a setpoint is not valid, or the
                heating setpoint is above the cooling setpoint.
        """
        if not self.use.is_valid():
            raise Error("A space use is not valid")
        _positive(self.volume.value, "A zone volume must be positive")
        _nonnegative(self.floor_area.value, "A floor area must be zero or more")
        _nonnegative(
            self.infiltration.value, "An infiltration must be zero or more"
        )
        self.gains.check()
        _nonnegative(
            self.furniture.value, "A furniture capacity must be zero or more"
        )
        if not (
            self.heating_setpoint.is_valid()
            and self.cooling_setpoint.is_valid()
        ):
            raise Error("A setpoint must be a valid temperature")
        if self.cooling_setpoint < self.heating_setpoint:
            raise Error("A heating setpoint must not be above cooling")

    def air_capacity(self) -> HeatCapacity64:
        """Return the heat the zone air and its contents store per kelvin.

        Returns:
            The air's rho c_p V plus the furniture.
        """
        var air = AIR_DENSITY * AIR_SPECIFIC_HEAT * self.volume.to(CUBIC_METER)
        return HeatCapacity64(air, JOULE_PER_KELVIN) + self.furniture

    def infiltration_conductance(self) -> ThermalConductance64:
        """Return the conductance of the leaking air.

        Returns:
            The product rho c_p V n, with n the air changes per second.
        """
        var g = (
            AIR_DENSITY
            * AIR_SPECIFIC_HEAT
            * self.volume.to(CUBIC_METER)
            * self.infiltration.to(PER_SECOND)
        )
        return ThermalConductance64(g, WATT_PER_KELVIN)


struct Surface(Copyable, Movable):
    """An opaque surface between a zone and what is outside it.

    The construction's first layer is on the outside face. The normal
    points from the inside face to the outside face, in model coordinates.
    """

    var name: String
    var construction: ConstructionId
    var boundary: BoundaryKind
    var inside: ZoneId
    # The zone on the outside face, for an interzone surface only.
    var outside: Optional[ZoneId]
    var area: Area64
    var normal: Vec3d
    var inside_film: ThermalTransmittance64
    var outside_film: ThermalTransmittance64

    def __init__(
        out self,
        var name: String,
        construction: ConstructionId,
        boundary: BoundaryKind,
        inside: ZoneId,
        outside: Optional[ZoneId],
        area: Area64,
        normal: Vec3d,
        inside_film: ThermalTransmittance64,
        outside_film: ThermalTransmittance64,
    ):
        """Create a surface. `ZoneModel.add_surface` checks it.

        Args:
            name: A name for people.
            construction: Its layers.
            boundary: What its outside face sees.
            inside: The zone its inside face sees.
            outside: The zone its outside face sees, for an interzone
                surface; otherwise None.
            area: Its net area.
            normal: The direction from its inside face to its outside face.
            inside_film: The film coefficient of the inside face.
            outside_film: The film coefficient of the outside face.
        """
        self.name = name^
        self.construction = construction
        self.boundary = boundary
        self.inside = inside
        self.outside = outside
        self.area = area
        self.normal = normal
        self.inside_film = inside_film
        self.outside_film = outside_film


struct Window(Copyable, Movable):
    """A window in an exterior wall of a zone, by the simple glazing model.

    It has no heat capacity. It conducts U A (T_out - T_in) and admits
    SHGC A I of the solar irradiance I on its plane as a gain to the air.
    """

    var name: String
    var zone: ZoneId
    var area: Area64
    var glazing: Glazing
    # The direction the window faces, outward, in model coordinates.
    var normal: Vec3d

    def __init__(
        out self,
        var name: String,
        zone: ZoneId,
        area: Area64,
        glazing: Glazing,
        normal: Vec3d,
    ):
        """Create a window. `ZoneModel.add_window` checks it.

        Args:
            name: A name for people.
            zone: The zone it lets heat into.
            area: Its area, frame included.
            glazing: Its U-value, with films, and its solar heat gain
                coefficient.
            normal: The direction it faces, outward.
        """
        self.name = name^
        self.zone = zone
        self.area = area
        self.glazing = glazing
        self.normal = normal


struct ZoneModel(Movable):
    """Zones, surfaces and windows, with the constructions they use."""

    var site: Site
    var materials: List[BuildingMaterial]
    var constructions: List[Construction]
    var zones: List[Zone]
    var surfaces: List[Surface]
    var windows: List[Window]

    def __init__(
        out self,
        site: Site,
        var materials: List[BuildingMaterial],
        var constructions: List[Construction],
    ) raises:
        """Create an empty model.

        Args:
            site: Where it stands. Its north orients the surfaces.
            materials: The materials the constructions name.
            constructions: The constructions the surfaces name.

        Raises:
            Error: If the site, a material or a construction is not valid.
        """
        site.check()
        for i in range(len(materials)):
            materials[i].check()
        for i in range(len(constructions)):
            constructions[i].check(materials)
        self.site = site
        self.materials = materials^
        self.constructions = constructions^
        self.zones = List[Zone]()
        self.surfaces = List[Surface]()
        self.windows = List[Window]()

    def check_zone(self, id: ZoneId) raises:
        """Refuse a zone id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last zone.
        """
        if not id.is_valid() or id.value >= len(self.zones):
            raise Error("A zone id is out of range")

    def check_surface(self, id: SurfaceId) raises:
        """Refuse a surface id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last surface.
        """
        if not id.is_valid() or id.value >= len(self.surfaces):
            raise Error("A surface id is out of range")

    def check_window(self, id: WindowId) raises:
        """Refuse a window id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last window.
        """
        if not id.is_valid() or id.value >= len(self.windows):
            raise Error("A window id is out of range")

    def _check_surface(self, surface: Surface) raises:
        var c = surface.construction
        if not c.is_valid() or c.value >= len(self.constructions):
            raise Error("A construction id is out of range")
        if not surface.boundary.is_valid():
            raise Error("A boundary kind is not valid")
        self.check_zone(surface.inside)
        if surface.boundary == INTERZONE:
            if not surface.outside:
                raise Error("An interzone surface needs an outside zone")
            self.check_zone(surface.outside.value())
        elif surface.outside:
            raise Error("Only an interzone surface has an outside zone")
        _positive(surface.area.value, "A surface area must be positive")
        _check_normal(surface.normal)
        _positive(surface.inside_film.value, "A film must be positive")
        _positive(surface.outside_film.value, "A film must be positive")

    def _check_window(self, window: Window) raises:
        self.check_zone(window.zone)
        _positive(window.area.value, "A window area must be positive")
        window.glazing.check()
        _check_normal(window.normal)

    def add_zone(mut self, var zone: Zone) raises -> ZoneId:
        """Add a zone.

        Args:
            zone: The zone.

        Returns:
            Its id.

        Raises:
            Error: If `Zone.check` refuses it.
        """
        zone.check()
        self.zones.append(zone^)
        return ZoneId(len(self.zones) - 1)

    def add_surface(mut self, var surface: Surface) raises -> SurfaceId:
        """Add a surface.

        Args:
            surface: The surface.

        Returns:
            Its id.

        Raises:
            Error: If its construction or a zone is out of range, its kind
                is not valid, an interzone surface has no outside zone or
                another surface has one, its area or a film is not positive
                and finite, or its normal is zero.
        """
        self._check_surface(surface)
        self.surfaces.append(surface^)
        return SurfaceId(len(self.surfaces) - 1)

    def add_window(mut self, var window: Window) raises -> WindowId:
        """Add a window.

        Args:
            window: The window.

        Returns:
            Its id.

        Raises:
            Error: If its zone is out of range, its area is not positive and
                finite, its glazing is not valid or its normal is zero.
        """
        self._check_window(window)
        self.windows.append(window^)
        return WindowId(len(self.windows) - 1)

    def surface_u_value(self, id: SurfaceId) raises -> ThermalTransmittance64:
        """Return a surface's transmittance with its own two films.

        Args:
            id: The surface.

        Returns:
            1 / (1 / h_in + sum of layer resistances + 1 / h_out).

        Raises:
            Error: If the id is out of range.
        """
        self.check_surface(id)
        ref s = self.surfaces[id.value]
        var r = (
            self.constructions[s.construction.value]
            .resistance(self.materials)
            .to(SQUARE_METER_KELVIN_PER_WATT)
        )
        var total = 1 / s.inside_film.value + r + 1 / s.outside_film.value
        return ThermalTransmittance64(1 / total, WATT_PER_SQUARE_METER_KELVIN)

    def surfaces_of(self, zone: ZoneId) raises -> List[SurfaceId]:
        """Return the surfaces that a zone sees on either face.

        Args:
            zone: The zone.

        Returns:
            The surfaces, in order, once each.

        Raises:
            Error: If the id is out of range.
        """
        self.check_zone(zone)
        var out = List[SurfaceId]()
        for i in range(len(self.surfaces)):
            ref s = self.surfaces[i]
            var seen = s.inside == zone
            if s.outside and s.outside.value() == zone:
                seen = True
            if seen:
                out.append(SurfaceId(i))
        return out^

    def check(self) raises:
        """Refuse a model a simulation cannot run.

        Raises:
            Error: If it has no zone, or a zone, a surface or a window is
                not valid. The lists are public, so this checks each again.
        """
        if len(self.zones) == 0:
            raise Error("A zone model needs a zone")
        for i in range(len(self.zones)):  # pragma: no branch
            self.zones[i].check()
        for i in range(len(self.surfaces)):
            self._check_surface(self.surfaces[i])
        for i in range(len(self.windows)):
            self._check_window(self.windows[i])
