# Building energy

`extensions/energy/` simulates the heat balance of the thermal zones of a building, step by step. It gives the air temperature of each zone and the ideal heating and cooling power that holds its setpoints. `extensions/building/views/thermal.mojo` makes the zone model from a `Building`.

![The rooms of an office floor warm and cool through a summer day](out/building-energy.png)

## Modules

| Module | What it gives |
|---|---|
| `energy/ids` | `ZoneId`, `SurfaceId`, `WindowId` and `BoundaryKind` (`EXTERIOR`, `INTERZONE`, `GROUND`) |
| `energy/weather` | `read_epw`, `parse_epw`, `design_day`, `ashrae_clear_sky`, `Weather`, `WeatherRecord` and `WeatherLocation` |
| `energy/solar` | `sun_position`, `sun_angles`, `declination`, `equation_of_time`, `orientation`, `incidence_cosine` and `tilted_irradiance` |
| `energy/conduction` | `LayeredWall`, the finite-difference mesh of a `Construction`, and `FaceCondition` |
| `energy/zone` | `ZoneModel`, `Zone`, `Surface`, `Window`, `InternalGains`, `typical_gains`, `gain_fraction` and the film coefficients |
| `energy/simulation` | `simulate`, `SimulationOptions`, `default_options`, `SimulationResult` and `ideal_loads` |
| `building/views/thermal` | `thermal_view`, `ThermalView`, `ThermalViewOptions` and `default_thermal_options` |

## Run a simulation

Make the zone model with `thermal_view`. Read the weather with `read_epw`, or make a clear day with `design_day`. Then call `simulate`.

```mojo
var view = thermal_view(building, default_thermal_options(), List[ZoneId]())
var weather = read_epw("site.epw")
var options = default_options()
var result = simulate(view.model, weather, options)
var heating = result.heating_energy(ZoneId(0)).to(KILOWATT_HOUR)
var air = result.air_temperature(12, ZoneId(0)).to(CELSIUS)
```

An empty grouping gives one zone per space. Give one `ZoneId` per space to group spaces into zones. The zone ids must start at 0 and have no gap.

`view.dropped` lists what the view leaves out. `view.space_zone`, `view.surface_face` and `view.window_opening` map the model back to the building.

You can edit the zone model before the simulation. For example, set a zone's `furniture` capacity or turn off its heating with a heating setpoint of 0 K. `simulate` checks the model again.

## Units

Every quantity at an API boundary carries a unit type.

| Quantity | Type | Unit inside |
|---|---|---|
| Temperature | `Temperature64` | K |
| Power, energy | `Power64`, `Energy64` | W, J |
| Irradiance, gain per floor area | `HeatFlux64` | W/m² |
| U-value, film coefficient | `ThermalTransmittance64` | W/(m² K) |
| Infiltration | `Frequency64`, with `AIR_CHANGE_PER_HOUR` | 1/s |
| Time step, time zone, time of day | `Duration64` | s |
| Latitude, longitude, slope, azimuth | `Angle64` | rad |

A `Vec3d` normal is in model coordinates: x east, y north and z up, turned by `Site.north`.

## The physical model

### Weather

An EPW file has 8 header lines and one record per line. The reader keeps the date, the hour, the air temperatures, the humidity and the pressure. It also keeps the three irradiation fields and the wind. It refuses a short header, a missing field, a field that is not a number and a value outside the ranges of the format. A missing value in the file, such as 99.9 for the dry-bulb, is out of range.

An irradiation in Wh/m² over an interval is the mean irradiance over that interval. The record holds over its interval, and the sun is placed at its middle.

`design_day` makes a clear day. The dry-bulb temperature is low + (high - low) (1 + cos(2π (t - 15) / 24)) / 2, with t in hours. The low is at 03:00 and the high at 15:00. The irradiance is the clear-sky model of the ASHRAE Handbook of Fundamentals (1985 to 2005 editions):

- I_DN = CN A exp(-B / cos θz), with the monthly A, B and C of the handbook table.
- I_d = C I_DN on the horizontal.
- I = I_DN cos θz + I_d.

The relative humidity follows from the dew point by the Magnus form of Alduchov and Eskridge (1996). The pressure is that of the standard atmosphere, 101.325 (1 - 2.25577e-5 Z)^5.2559 kPa.

### Sun and irradiance

The solar equations are those of Duffie and Beckman, "Solar Engineering of Thermal Processes", 4th edition, 2013:

| Quantity | Equation | Source |
|---|---|---|
| Day angle | B = 360 (n - 1) / 365 | eq. 1.4.2 |
| Equation of time | E = 229.2 (0.000075 + 0.001868 cos B - 0.032077 sin B - 0.014615 cos 2B - 0.04089 sin 2B) min | eq. 1.5.3, Spencer (1971) |
| Declination | Spencer's Fourier series | eq. 1.6.1b |
| Solar time | standard time + 4 min/degree (longitude - 15 × time zone) + E | eq. 1.5.2 |
| Zenith angle | cos θz = cos φ cos δ cos ω + sin φ sin δ | eq. 1.6.5 |
| Solar azimuth | γs = sign(ω) arccos((cos θz sin φ - sin δ) / (sin θz cos φ)) | eq. 1.6.6 |
| Incidence | cos θ = cos θz cos β + sin θz sin β cos(γs - γ) | eq. 1.6.3 |
| Irradiance on a surface | I_T = I_bn max(cos θ, 0) + I_d (1 + cos β) / 2 + I ρg (1 - cos β) / 2 | eq. 2.15.1, isotropic sky |

An azimuth is measured from south, west positive. A longitude and a time zone are east positive.

### Conduction

`LayeredWall` cuts each layer of a construction into equal elements, with a node at each element boundary. Each element is small enough that its Fourier number α Δt / Δx² is at least `fourier`. A layer gets at most 64 elements. The energy balance of node i is the implicit (backward Euler) form, Incropera section 5.10:

```text
C_i (T_i' - T_i) / Δt = K_(i-1) (T_(i-1)' - T_i') + K_i (T_(i+1)' - T_i')
```

A face node also gains h (T_env - T') + q. Here h is the film coefficient and q is the absorbed radiation. The system is tridiagonal, and `solve_tridiagonal` solves it.

### Zones

A zone is well-mixed air. Its balance in each step is:

```text
C (T' - T) / Δt = Σ h A (T_s' - T') + (Σ U A + ρ c_p V n) (T_out - T')
                  + G + Σ SHGC A I + Q
```

| Term | Meaning | Value |
|---|---|---|
| C | Air and furniture heat capacity | ρ c_p V + `Zone.furniture` |
| ρ c_p | Air at 20 °C and 101.325 kPa | 1.204 kg/m³ × 1006 J/(kg K), ASHRAE Handbook of Fundamentals chapter 1 |
| h A (T_s' - T') | Heat from each surface's inside face | The film coefficient times the net area |
| U A | Each window | The glazing U-value, films included |
| n | Infiltration | Air changes per second |
| G | Internal gains | `typical_gains(use)` × floor area × `gain_fraction(use, hour)` |
| SHGC A I | Solar gain of each window | The irradiance on the window's plane |
| Q | Ideal heating (positive) or cooling (negative) power | Found by the step |

A surface's node temperatures are linear in the zone temperatures. The step solves each wall three times: once with the known conditions, and once for a unit temperature on each face. The zone balances then form one small linear system.

A zone floats freely while its air stays between its setpoints. A zone that would leave its band is held at the setpoint it would cross. An active-set loop finds which zones are held. It frees a held zone whose power has the wrong sign, and it repeats until nothing changes.

### Film coefficients

The film coefficients combine convection and long-wave radiation:

| Face | Coefficient | Source |
|---|---|---|
| Inside, wall | 1/0.13 = 7.69 W/(m² K) | ISO 6946 |
| Inside, ceiling or roof (heat flows up) | 1/0.10 = 10 W/(m² K) | ISO 6946 |
| Inside, floor (heat flows down) | 1/0.17 = 5.88 W/(m² K) | ISO 6946 |
| Outside, default | 1/0.04 = 25 W/(m² K) | ISO 6946 |
| Outside, with `wind_film` | 4 + 4 v + 4 ε σ T³ | ISO 6946 Annex C |

With the ISO 6946 films, a surface's U-value equals `Construction.u_value`.

### Ground

A ground-contact surface sees the ground temperature of `SimulationOptions` through its outside film. This is a simplification of ISO 13370: the model has no soil layer.

### Internal gains

`typical_gains` gives these peak gains in W/m² of floor. They are typical values of the order of the ASHRAE Handbook of Fundamentals chapter 18 and ISO 17772-1. They are not design values. A project must use its own values.

| Use | People | Lighting | Equipment | Profile |
|---|---|---|---|---|
| office | 7 | 8 | 10 | work |
| corridor | 1 | 5 | 0 | work |
| core | 0 | 3 | 0 | work |
| lobby | 3 | 8 | 1 | work |
| retail | 6 | 12 | 3 | shop |
| living | 3 | 5 | 4 | home |
| bedroom | 2 | 4 | 1 | home |
| kitchen | 3 | 7 | 25 | home |
| bathroom | 1 | 6 | 2 | home |
| storage | 0 | 4 | 0 | work |
| mechanical | 0 | 5 | 10 | always |
| meeting | 20 | 10 | 5 | work |

| Profile | Share of the peak |
|---|---|
| work | 1 from 08:00 to 18:00, 0.1 otherwise |
| shop | 1 from 09:00 to 21:00, 0.1 otherwise |
| home | 1 from 18:00 to 23:00, 0.5 from 23:00 to 07:00, 0.3 otherwise |
| always | 1 |

## The thermal view

`thermal_view` makes one surface for each face of each wall, slab and roof:

| Face | Surface |
|---|---|
| A space on both sides | `INTERZONE`, between the two zones |
| The outside below a floor at level 0 | `GROUND` |
| The outside on any other side | `EXTERIOR` |

A window in an exterior wall becomes a `Window`. Its area leaves the area of the wall's surface. The view records these simplifications in `dropped`:

- A door stays part of its wall's construction.
- A window in an interior wall stays part of the wall.
- A wall that a window fills has no opaque surface.
- Columns and beams carry no heat.
- The model has no furniture. Set `Zone.furniture` to add it.
- A window is one plane in its wall, with no frame and no reveal.

## Validation

Each row is a test. The reference is in the test docstring.

| Test | Reference | Reference value | Measured |
|---|---|---|---|
| Steady load of a room | Σ U A ΔT + ρ c_p V n ΔT, U from `Construction.u_value` | 1102.126 W | Relative error 7e-8 |
| Steady wall | ISO 6946 series resistance | q = U ΔT | Error under 1e-9 W/m² |
| Semi-infinite solid, 6 h after a 100 K step | Incropera eq. 5.57, the error function | T(x, t) | Largest error 0.039 K |
| Slab, 2 h after a 100 K step, Δt = 900 to 112.5 s | Carslaw and Jaeger section 3.3, the Fourier series | T(L/2, t) | 2.04, 1.05, 0.53, 0.27 K: first order |
| Lumped zone cooling, τ = 10.8 h, Δt = 60 s | Incropera section 5.2: exp(-t/τ) | 2.160 °C after 24 h | 0.17%; 1.5e-13 K from (1 + Δt/τ)^-n |
| Two zones in series | Conductance divider | T_B | Error under 1e-6 K |
| Equation of time, February 3 | Duffie and Beckman Example 1.5.1 | -13.5 min, solar time 10:19 | -13.49 min |
| Incidence on a tilted surface | Duffie and Beckman Example 1.6.1 | cos θ = 0.817 | 0.8174 |
| Zenith and azimuth | Duffie and Beckman Example 1.6.2 | 66.5°, -40.0°; 79.6°, 112.0° | 66.55°, -40.08°; 79.64°, 112.02° |
| Declination | Duffie and Beckman Table 1.6.1 | 12 monthly values | Largest error 0.050° |
| Declination at the equinoxes and the solstice | The obliquity, 23.44° | Sign change on March 20 to 21 and September 23 to 24 | 23.45° on June 21 |
| EPW fixture | `assets/energy/fixture.epw` | The values of each field | Exact |
| EPW refusals | The ranges of the EPW format | Each malformed header and record in the tests | Each refused |
| Thermal view | The faces of the cell complex | Surface areas equal face areas less windows | Error under 1e-9 m² |

## Limits

- The model has no humidity balance. It computes sensible heat only.
- It has no HVAC system model. The loads are ideal, with no capacity limit.
- The interior films combine convection and radiation. The model has no long-wave exchange between surfaces, and no sky temperature below the air temperature.
- All internal and solar gains go to the zone air at once. The sun through a window does not heat the floor first.
- The solar heat gain coefficient of a window does not change with the angle of incidence. The model has no shading by overhangs or by other buildings.
- Gain profiles are the same every day, with no weekends or holidays.
- The ground is at one fixed temperature, with no soil layer.
- Conduction is one-dimensional. The model has no thermal bridges.

## References

- Duffie and Beckman, "Solar Engineering of Thermal Processes", 4th edition, 2013, chapters 1 and 2.
- Incropera, DeWitt, Bergman and Lavine, "Fundamentals of Heat and Mass Transfer", 6th edition, 2007, chapter 5.
- Carslaw and Jaeger, "Conduction of Heat in Solids", 2nd edition, 1959, chapter 3.
- ASHRAE Handbook of Fundamentals, chapters 1, 14, 16 and 18.
- ISO 6946, "Building components and building elements — Thermal resistance and thermal transmittance".
- ISO 13370, "Thermal performance of buildings — Heat transfer via the ground".
- ISO 17772-1, "Energy performance of buildings — Indoor environmental quality".
- Alduchov and Eskridge, "Improved Magnus form approximation of saturation vapor pressure", 1996.
- Liu and Jordan, "The interrelationship and characteristic distribution of direct, diffuse and total solar radiation", 1960.
