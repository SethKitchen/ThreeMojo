# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A time-stepping heat balance of the zones of a `ZoneModel`.

Each step solves, by the implicit (backward Euler) method, the energy
balance of every zone's air and of every node of every surface together.
The balance of zone z is:

    C_z (T_z' - T_z) / dt = sum over surfaces h A (T_s' - T_z')
        + (U A of windows + rho c_p V n) (T_out - T_z')
        + internal gains + SHGC A I of windows + Q_z

The surface temperatures are linear in the zone temperatures: a wall's
nodes are u + v_in T_in' + v_out T_out', with u the response to the
known conditions and v the response to a unit zone temperature on each
face. Three tridiagonal solves give u and v for each surface. The zone
balances then form a small linear system M T' = b + Q, with one row per
zone.

Q is the ideal heating (positive) or cooling (negative) power. A zone
floats freely with Q = 0 while its air stays between its setpoints. A
zone that would fall below its heating setpoint is held at it, and one
that would rise above its cooling setpoint is held at that. Because the
zones couple, an active-set loop finds which zones are held: it holds
each zone outside its band, solves, frees each held zone whose power has
the wrong sign, and repeats until nothing changes.

The simulation is deterministic: it has no random input and no thread.
"""

from std.math import isfinite

from extensions.energy.conduction import FaceCondition, LayeredWall
from extensions.energy.ids import EXTERIOR, GROUND, INTERZONE, ZoneId
from extensions.energy.solar import (
    SurfaceOrientation,
    orientation,
    sun_position,
    tilted_irradiance,
)
from extensions.energy.weather import Weather
from extensions.energy.zone import ZoneModel, exterior_film, gain_fraction
from extensions.numerics.dense import DenseMatrix, solve
from units.si import (
    Duration64,
    Energy64,
    HOUR,
    HeatFlux64,
    JOULE,
    Power64,
    SECOND,
    WATT,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

# Zones held at a setpoint, or free.
comptime _FREE = 0
comptime _HEATING = 1
comptime _COOLING = 2
# A zone is held when it would leave its band by more than this, in K.
comptime _BAND_TOLERANCE = 1e-9
# A held zone is freed when its power has the wrong sign by more, in W.
comptime _POWER_TOLERANCE = 1e-9


@fieldwise_init
struct SimulationOptions(ImplicitlyCopyable):
    """The settings of a simulation."""

    # Steps per weather record. The weather holds over the record.
    var substeps: Int
    # The smallest Fourier number of a wall element.
    var fourier: Float64
    # The temperature under a ground-contact surface.
    var ground_temperature: Temperature64
    # The albedo of the ground, zero to one.
    var ground_reflectance: Float64
    # The share of solar irradiance an exterior surface absorbs.
    var solar_absorptance: Float64
    # The long-wave emissivity of an exterior surface, for `wind_film`.
    var emissivity: Float64
    # True to use the wind-dependent `exterior_film` on exterior surfaces;
    # False to use each surface's own outside film.
    var wind_film: Bool
    # The temperature of every zone and wall node at the start.
    var initial_temperature: Temperature64
    # Days that repeat the first day of weather before the results start.
    var warmup_days: Int

    def check(self) raises:
        """Refuse settings a simulation cannot use.

        Raises:
            Error: If the substeps are not 1 to 60, the Fourier number is
                not positive and finite, a temperature is not valid, a share
                is outside zero to one, or the warm-up days are not 0 to
                365.
        """
        if self.substeps < 1 or self.substeps > 60:
            raise Error("Substeps must be 1 to 60")
        if not (self.fourier > 0 and isfinite(self.fourier)):
            raise Error("A Fourier number must be positive and finite")
        if not (
            self.ground_temperature.is_valid()
            and self.initial_temperature.is_valid()
        ):
            raise Error("A ground and an initial temperature must be valid")
        var shares = [
            self.ground_reflectance,
            self.solar_absorptance,
            self.emissivity,
        ]
        for i in range(len(shares)):  # pragma: no branch
            if not (shares[i] >= 0 and shares[i] <= 1):
                raise Error("A reflectance, absorptance or emissivity is 0-1")
        if self.warmup_days < 0 or self.warmup_days > 365:
            raise Error("Warm-up days must be 0 to 365")


def default_options() -> SimulationOptions:
    """Return typical settings.

    Returns:
        One step per record, a Fourier number of 2, ground at 10 degrees
        Celsius, a ground reflectance of 0.2, a solar absorptance of 0.6,
        an emissivity of 0.9, the surfaces' own outside films, a start at
        20 degrees Celsius and 7 warm-up days.
    """
    return SimulationOptions(
        1,
        2.0,
        Temperature64(10, CELSIUS),
        0.2,
        0.6,
        0.9,
        False,
        Temperature64(20, CELSIUS),
        7,
    )


struct SimulationResult(Movable):
    """The state of each zone at the end of each step."""

    var zone_count: Int
    var step: Duration64
    # Step-major: entry step * zone_count + zone. Kelvin and watts.
    var air: List[Float64]
    var heating_power: List[Float64]
    var cooling_power: List[Float64]
    # Per zone, in joules.
    var heating_total: List[Float64]
    var cooling_total: List[Float64]

    def __init__(out self, zone_count: Int, step: Duration64):
        """Hold an empty result.

        Args:
            zone_count: The number of zones.
            step: The length of one step.
        """
        self.zone_count = zone_count
        self.step = step
        self.air = List[Float64]()
        self.heating_power = List[Float64]()
        self.cooling_power = List[Float64]()
        self.heating_total = List[Float64](length=zone_count, fill=0.0)
        self.cooling_total = List[Float64](length=zone_count, fill=0.0)

    def step_count(self) -> Int:
        """Return the number of steps held.

        Returns:
            The number of steps.
        """
        return len(self.air) // self.zone_count

    def _index(self, step: Int, zone: ZoneId) raises -> Int:
        self._check_zone(zone)
        if step < 0 or step >= self.step_count():
            raise Error("A step is out of range")
        return step * self.zone_count + zone.value

    def _check_zone(self, zone: ZoneId) raises:
        if not zone.is_valid() or zone.value >= self.zone_count:
            raise Error("A zone id is out of range")

    def air_temperature(self, step: Int, zone: ZoneId) raises -> Temperature64:
        """Return a zone's air temperature at the end of a step.

        Args:
            step: The step, from 0.
            zone: The zone.

        Returns:
            The air temperature.

        Raises:
            Error: If the step or the zone is out of range.
        """
        return Temperature64(self.air[self._index(step, zone)], KELVIN)

    def heating(self, step: Int, zone: ZoneId) raises -> Power64:
        """Return the ideal heating power of a zone during a step.

        Args:
            step: The step, from 0.
            zone: The zone.

        Returns:
            The heating power, zero or more.

        Raises:
            Error: If the step or the zone is out of range.
        """
        return Power64(self.heating_power[self._index(step, zone)], WATT)

    def cooling(self, step: Int, zone: ZoneId) raises -> Power64:
        """Return the ideal cooling power of a zone during a step.

        Args:
            step: The step, from 0.
            zone: The zone.

        Returns:
            The heat removed per unit time, zero or more.

        Raises:
            Error: If the step or the zone is out of range.
        """
        return Power64(self.cooling_power[self._index(step, zone)], WATT)

    def heating_energy(self, zone: ZoneId) raises -> Energy64:
        """Return the heating energy of a zone over the whole period.

        Args:
            zone: The zone.

        Returns:
            The sum of heating power times the step.

        Raises:
            Error: If the zone is out of range.
        """
        self._check_zone(zone)
        return Energy64(self.heating_total[zone.value], JOULE)

    def cooling_energy(self, zone: ZoneId) raises -> Energy64:
        """Return the cooling energy of a zone over the whole period.

        Args:
            zone: The zone.

        Returns:
            The sum of cooling power times the step.

        Raises:
            Error: If the zone is out of range.
        """
        self._check_zone(zone)
        return Energy64(self.cooling_total[zone.value], JOULE)

    def total_heating_energy(self) -> Energy64:
        """Return the heating energy of every zone over the whole period.

        Returns:
            The sum over the zones.
        """
        var total = 0.0
        for z in range(self.zone_count):  # pragma: no branch
            total += self.heating_total[z]
        return Energy64(total, JOULE)

    def total_cooling_energy(self) -> Energy64:
        """Return the cooling energy of every zone over the whole period.

        Returns:
            The sum over the zones.
        """
        var total = 0.0
        for z in range(self.zone_count):  # pragma: no branch
            total += self.cooling_total[z]
        return Energy64(total, JOULE)


def _solve_mode(
    m: DenseMatrix,
    b: List[Float64],
    target: List[Float64],
    mode: List[Int],
    mut temperature: List[Float64],
    mut load: List[Float64],
) raises:
    # Hold the zones that are not free at their targets; solve the rest.
    var n = m.rows
    var free = List[Int]()
    for z in range(n):  # pragma: no branch
        if mode[z] == _FREE:
            free.append(z)
        else:
            temperature[z] = target[z]
    if len(free) > 0:
        var count = len(free)
        var sub = DenseMatrix(count, count)
        var rhs = List[Float64](length=count, fill=0.0)
        for i in range(count):  # pragma: no branch
            var zi = free[i]
            var value = b[zi]
            for j in range(n):  # pragma: no branch
                if mode[j] != _FREE:
                    value -= m.get(zi, j) * temperature[j]
            rhs[i] = value
            for k in range(count):  # pragma: no branch
                sub.set(i, k, m.get(zi, free[k]))
        var x = solve(sub, rhs)
        for i in range(count):  # pragma: no branch
            temperature[free[i]] = x[i]
    for z in range(n):  # pragma: no branch
        var q = 0.0
        if mode[z] != _FREE:
            q = -b[z]
            for j in range(n):  # pragma: no branch
                q += m.get(z, j) * temperature[j]
        load[z] = q


def ideal_loads(
    m: DenseMatrix,
    b: List[Float64],
    heating: List[Float64],
    cooling: List[Float64],
) raises -> List[List[Float64]]:
    """Return the zone temperatures and the ideal loads of one step.

    Solves M T = b + Q with each zone free (Q = 0) between its setpoints
    or held at the setpoint it would cross. M must be an M-matrix, as the
    heat balance of zones is.

    Args:
        m: The zone matrix, in W/K.
        b: The known heat of each zone, in W.
        heating: The heating setpoint of each zone, in kelvin.
        cooling: The cooling setpoint of each zone, in kelvin.

    Returns:
        Two lists: the zone temperatures in kelvin, and the powers in W,
        heating positive.

    Raises:
        Error: If the sizes differ or a solve meets a zero pivot.
    """
    var n = m.rows
    if m.cols != n or len(b) != n or len(heating) != n or len(cooling) != n:
        raise Error("Ideal loads need one row and setpoint pair per zone")
    var mode = List[Int](length=n, fill=_FREE)
    var target = List[Float64](length=n, fill=0.0)
    var temperature = List[Float64](length=n, fill=0.0)
    var load = List[Float64](length=n, fill=0.0)
    for _ in range(2 * n + 2):  # pragma: no branch
        _solve_mode(m, b, target, mode, temperature, load)
        var changed = False
        for z in range(n):
            if mode[z] == _FREE:
                if temperature[z] < heating[z] - _BAND_TOLERANCE:
                    mode[z] = _HEATING
                    target[z] = heating[z]
                    changed = True
                elif temperature[z] > cooling[z] + _BAND_TOLERANCE:
                    mode[z] = _COOLING
                    target[z] = cooling[z]
                    changed = True
            elif mode[z] == _HEATING:
                if load[z] < -_POWER_TOLERANCE:
                    mode[z] = _FREE
                    changed = True
            elif load[z] > _POWER_TOLERANCE:
                mode[z] = _FREE
                changed = True
        if not changed:
            break
    return [temperature^, load^]


def simulate(
    model: ZoneModel, weather: Weather, options: SimulationOptions
) raises -> SimulationResult:
    """Run the heat balance of a zone model through a weather series.

    The weather location places the sun. The site's north orients the
    surfaces. Each record holds over its interval, and the sun is placed
    at its middle. The first day of weather repeats `warmup_days` times
    before the results start, so the walls start near a periodic state.

    Args:
        model: The zones, surfaces and windows.
        weather: The weather, one record per interval.
        options: The settings.

    Returns:
        The air temperature and the ideal powers of each zone at each
        step, and their energy totals.

    Raises:
        Error: If the model, the options or the weather location is not
            valid, the weather has no record or a record's date is not in
            the calendar.
    """
    model.check()
    options.check()
    weather.location.check()
    if len(weather.records) == 0:
        raise Error("A simulation needs a weather record")
    var record_seconds = weather.step.to(SECOND)
    if not (record_seconds > 0 and record_seconds <= 3600):
        raise Error("A weather step must be over zero and up to one hour")
    var dt = record_seconds / Float64(options.substeps)
    var zones = len(model.zones)
    var surfaces = len(model.surfaces)
    var windows = len(model.windows)
    var north = model.site.north

    var walls = List[LayeredWall]()
    var facing = List[SurfaceOrientation]()
    for i in range(surfaces):
        ref s = model.surfaces[i]
        walls.append(
            LayeredWall(
                model.constructions[s.construction.value],
                model.materials,
                Duration64(dt, SECOND),
                options.fourier,
                options.initial_temperature,
            )
        )
        facing.append(orientation(s.normal, north))
    var window_facing = List[SurfaceOrientation]()
    for i in range(windows):
        window_facing.append(orientation(model.windows[i].normal, north))

    var capacity = List[Float64](length=zones, fill=0.0)
    var leak = List[Float64](length=zones, fill=0.0)
    var heat_set = List[Float64](length=zones, fill=0.0)
    var cool_set = List[Float64](length=zones, fill=0.0)
    for z in range(zones):  # pragma: no branch
        ref zone = model.zones[z]
        capacity[z] = zone.air_capacity().value / dt
        leak[z] = zone.infiltration_conductance().value
        heat_set[z] = zone.heating_setpoint.kelvin
        cool_set[z] = zone.cooling_setpoint.kelvin
    for i in range(windows):
        ref w = model.windows[i]
        leak[w.zone.value] += w.glazing.u_value.value * w.area.value
    var air = List[Float64](
        length=zones, fill=options.initial_temperature.kelvin
    )

    # The unit responses of each wall, kept while its outside film holds.
    var v_in = List[List[Float64]]()
    var v_out = List[List[Float64]]()
    var cached_film = List[Float64]()
    for _ in range(surfaces):
        v_in.append(List[Float64]())
        v_out.append(List[Float64]())
        cached_film.append(-1.0)

    var records = len(weather.records)
    var first_day = min(records, 24 * weather.records_per_hour())
    var warmup = options.warmup_days * first_day
    var result = SimulationResult(zones, Duration64(dt, SECOND))
    var zero = Temperature64(0, KELVIN)
    var unit = Temperature64(1, KELVIN)
    var no_flux = HeatFlux64(0)
    var location = weather.location.copy()

    for visit in range(warmup + records):  # pragma: no branch
        var keep = visit >= warmup
        var r = visit - warmup if keep else visit % first_day
        ref rec = weather.records[r]
        var middle = rec.end.to(HOUR) - weather.step.to(HOUR) / 2
        var sun = sun_position(
            location.latitude,
            location.longitude,
            location.time_zone,
            rec.day_of_year(),
            Duration64(middle, HOUR),
        )
        var outdoor = rec.dry_bulb.kelvin
        var hour = Int(middle) % 24
        var wind = exterior_film(
            rec.wind_speed, rec.dry_bulb, options.emissivity
        )
        var known = List[Float64](length=zones, fill=0.0)
        for z in range(zones):  # pragma: no branch
            ref zone = model.zones[z]
            known[z] = (
                zone.gains.total().value
                * zone.floor_area.value
                * gain_fraction(zone.use, hour)
            )
        for i in range(windows):
            ref w = model.windows[i]
            var irradiance = tilted_irradiance(
                window_facing[i],
                sun,
                rec.direct_normal,
                rec.diffuse_horizontal,
                rec.global_horizontal,
                options.ground_reflectance,
            )
            known[w.zone.value] += (
                w.glazing.solar_heat_gain * w.area.value * irradiance.value
            )
        var outside = List[FaceCondition]()
        for i in range(surfaces):
            ref s = model.surfaces[i]
            var film = s.outside_film
            var environment = zero
            var absorbed = no_flux
            if s.boundary == EXTERIOR:
                if options.wind_film:
                    film = wind
                environment = rec.dry_bulb
                var irradiance = tilted_irradiance(
                    facing[i],
                    sun,
                    rec.direct_normal,
                    rec.diffuse_horizontal,
                    rec.global_horizontal,
                    options.ground_reflectance,
                )
                absorbed = irradiance.scaled(options.solar_absorptance)
            elif s.boundary == GROUND:
                environment = options.ground_temperature
            outside.append(FaceCondition(film, environment, absorbed))

        for _ in range(options.substeps):  # pragma: no branch
            var m = DenseMatrix(zones, zones)
            var b = List[Float64](length=zones, fill=0.0)
            for z in range(zones):  # pragma: no branch
                m.add(z, z, capacity[z] + leak[z])
                b[z] = capacity[z] * air[z] + leak[z] * outdoor + known[z]
            var u = List[List[Float64]]()
            for i in range(surfaces):
                ref s = model.surfaces[i]
                ref wall = walls[i]
                var inside = FaceCondition(s.inside_film, zero, no_flux)
                u.append(wall.solve(outside[i], inside, True))
                var film = outside[i].film
                if cached_film[i] != film.value:
                    cached_film[i] = film.value
                    v_in[i] = wall.solve(
                        FaceCondition(film, zero, no_flux),
                        FaceCondition(s.inside_film, unit, no_flux),
                        False,
                    )
                    if s.boundary == INTERZONE:
                        v_out[i] = wall.solve(
                            FaceCondition(film, unit, no_flux),
                            inside,
                            False,
                        )
                var last = wall.node_count() - 1
                var a = s.inside.value
                var hi = s.inside_film.value * s.area.value
                m.add(a, a, hi * (1 - v_in[i][last]))
                b[a] += hi * u[i][last]
                if s.boundary == INTERZONE:
                    var o = s.outside.value().value
                    var ho = film.value * s.area.value
                    m.add(a, o, -hi * v_out[i][last])
                    m.add(o, o, ho * (1 - v_out[i][0]))
                    m.add(o, a, -ho * v_in[i][0])
                    b[o] += ho * u[i][0]
            var solved = ideal_loads(m, b, heat_set, cool_set)
            for z in range(zones):  # pragma: no branch
                air[z] = solved[0][z]
            for i in range(surfaces):
                ref s = model.surfaces[i]
                var t_in = air[s.inside.value]
                var nodes = u[i].copy()
                for k in range(len(nodes)):  # pragma: no branch
                    nodes[k] += v_in[i][k] * t_in
                if s.boundary == INTERZONE:
                    var t_out = air[s.outside.value().value]
                    for k in range(len(nodes)):  # pragma: no branch
                        nodes[k] += v_out[i][k] * t_out
                walls[i].set_temperatures(nodes^)
            if keep:
                for z in range(zones):  # pragma: no branch
                    var q = solved[1][z]
                    var heat = max(q, 0.0)
                    var cool = max(-q, 0.0)
                    result.air.append(air[z])
                    result.heating_power.append(heat)
                    result.cooling_power.append(cool)
                    result.heating_total[z] += heat * dt
                    result.cooling_total[z] += cool * dt
    return result^
