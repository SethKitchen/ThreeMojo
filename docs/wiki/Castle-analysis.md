# Castle analysis

`extensions/castle/` checks the engineering of a [castle](Castle) from its plan. Five checks read the plan. They give the wind on a tower, the arch of a bridge, the quay wall, the moat's water and the sun's shadows. Each check reads the plan and states its assumptions. A checked box in the README records implemented scope. It does not establish the safety of the real castle.

![The castle drawn each hour from 09:00 to 18:00 on 19 October 2026, with the shadow of the donjon turning round the courtyard](out/wijnendale-simulation.png)

`examples/wijnendale_simulation.mojo` draws the picture and prints the report. The sun is where it stands over Torhout on 19 October 2026. The figures below are the example's output.

```bash
.venv/bin/mojo run -I . examples/wijnendale_simulation.mojo out/wijnendale-simulation.png
```

Every figure of the plan that no survey gives is marked as an estimate. The wall of the donjon, the wall of the quay, the weir and the soil are estimates. A project that relied on a figure would measure it.

## The sun and the shadows

`castle/sun.mojo` follows Meeus, Astronomical Algorithms, 2nd edition: the low-accuracy coordinates of the sun, the equation of time and the altitude. Its error is about 0.01 degree. Times are hours of UTC. Azimuth runs clockwise from north.

| Function | What it gives |
|---|---|
| `solar_position` | The height and the bearing of the sun, and `toward()`, a unit vector |
| `solar_noon`, `sunrise_and_sunset` | The times of the day |
| `shadow_length`, `shadow_tip` | How far a tower throws its shadow, and where its tip falls |
| `day_of_year` | A date's number in the year |

`castle/shadow.mojo` marches a ray toward the sun from a point of the courtyard, in half meter steps. Each step is tested against the solids of the plan. A tower is a cylinder, and a wing and the gate are prisms, each up to its top or ridge. A roof slopes below its ridge, so the shade of a wing is a little too large, which is safe. `lit_fraction` gives the share of the courtyard in the sun at an hour, and `donjon_shadow` the length and direction of the shadow of the donjon.

On 19 October 2026 the sun rises at 08:18, stands highest at 28.8 degrees at 13:33, and sets at 18:47.

| Local time | Height | Bearing | Donjon shadow | Courtyard in sun |
|---|---|---|---|---|
| 09:00 | 5.4 | 113 | 270 m | 14 % |
| 12:00 | 25.6 | 155 | 53.5 m | 50 % |
| 14:00 | 28.6 | 188 | 47.2 m | 78 % |
| 17:00 | 14.2 | 233 | 101.5 m | 93 % |

## Wind on the donjon

The donjon is a hollow round shaft of brick, so the rules for a circular cylinder of EN 1991-1-4:2005+A1:2010 apply. `castle/wind.mojo` names the clause at each function.

- **Peak velocity pressure**, 4.3 to 4.5: the roughness factor, the turbulence intensity and `qp = (1 + 7 Iv) (rho / 2) vm^2`.
- **Force coefficient**, 7.9.2: `cf0` from the Reynolds number and the roughness of brickwork, 3 mm. The slenderness is from Table 7.16 and the end-effect factor from Figure 7.36.
- **Structural factor**, 6.3.1 and Annex B. Clause 6.2(1)d allows 1 for a round chimney lower than 60 m and 6.5 diameters.
- **Vortex shedding**, Annex E: it need not be checked when the shaft is shorter than 6 diameters.

The natural frequency has three sources, and all three are computed. They are the empirical formula of F.3, the Euler-Bernoulli cantilever, and a finite element model of `extensions.structure`. The model and the beam must agree.

```mojo
var shaft = donjon_shaft(plan)
var frequency = shaft_frequency_fe(shaft)
var wind = tower_wind(wijnendale_wind_site(), shaft, frequency)
var base = base_check(shaft, wind)
```

| Quantity | Value |
|---|---|
| The shaft | 6.86 m across, a wall of 1.2 m (assumed), 29.28 m high from the water, 11.03 MN |
| Natural frequency | F.3 chimney formula 5.60 Hz, beam 2.42 Hz, finite element model 2.40 Hz |
| Wind | 26 m/s basic velocity, the top of the Belgian zones, terrain category II, 1.28 kN/m2 at the top |
| Force coefficient | Reynolds number 20.7e6, cf0 0.92, slenderness 3.2, end effect 0.65, cf 0.60 |
| Base | Shear 119 kN, moment 1.96 MN m |
| Stresses at the design level | Compression 0.81 MPa of 2.36 (34 percent), no tension, shear 11 percent, overturning 9 percent |

The F.3 formula gives a frequency more than twice that of the beam and the finite element model. The model is used.

## The arch of the bridge

`castle/arch.mojo` is Heyman's limit analysis. Masonry has no tensile strength, its compressive strength is so high that crushing does not govern, and one stone does not slide on another. The safe theorem then says that an arch stands if a line of thrust, in equilibrium with the loads, lies inside the masonry. For a semicircular ring of uniform thickness with only its own weight, the least thickness is 0.1075 of the mean radius (Couplet, 1730). The module finds it by bisection, and the tests hold it to that ratio. The ratio of the real thickness to the least is the geometrical factor of safety.

| Quantity | Value |
|---|---|
| The ring | Mean radius 2.90 m, thickness 0.60 m, t/R 0.207 |
| Geometrical factor of safety | 1.93 |
| Horizontal thrust | 14.6 to 24.9 kN per meter of width |
| The springing | 50.3 kN/m, 3.6 percent of the strength of the masonry |

## The quay wall

`castle/moat_wall.mojo` treats the wall at the edge of the moat as a gravity retaining wall. Per meter of wall it carries these loads:

- Its weight, at the middle of the base.
- The active thrust of the earth behind it, by Rankine's coefficient on the effective stress.
- The water behind it, if the ground is wet.
- The water of the moat in front of it.
- The uplift of the water under its base.

The checks are the classical ones: the moment about the toe, the friction on the base, and the resultant in the middle third. A factor of 1.5 is customary. `least_thickness` finds the smallest thickness at which all three hold.

| Case | Overturning factor | Sliding factor | Free-standing wall needs |
|---|---|---|---|
| Moat full | 0.28 | 0.33 | 4.1 m |
| Moat drawn down | 0.27 | 0.31 | 4.3 m |

The wall is 0.9 m thick (assumed) and 5.79 m high, and holds 5.09 m of earth. A wall of 0.9 m is a facing. The earth is held by ties, counterforts or the foundations of the buildings. The factors say that the wall cannot stand alone, which is what a facing is.

## The water of the moat

`castle/moat_water.mojo` is a balance of what comes in and what goes out. Water comes from a brook, from the rain on the water and from the ground that drains to it. It leaves over a weir, by seepage and by evaporation. The level changes by the net volume over the area. The weir is a thin-plate weir of the full width of its channel, by the Kindsvater-Carter formula of ISO 1438. A step of the fourth-order Runge-Kutta method advances the level by small steps.

The level of the moat, 34.31 m above TAW, is that of the airborne laser scan, one date of an unknown weather. The module takes it as the level of dry weather and sets the crest of the weir so that the base inflow holds it there. The inflow, the weir width and the catchment have no survey.

| Quantity | Value |
|---|---|
| The moat | 11,062 m3 on 7,360 m2 |
| The weir | 1.2 m wide (assumed), 27.1 L/s |
| Renewal | 4.7 days |

## Limits

- The checks read one plan with estimated figures. A report on the real castle would measure them.
- The wind check is for a round shaft. A square tower has other force coefficients.
- The shadows are those of solids that a roof's slope overestimates by a little. The sun is a point at infinity.
- The weather of the water balance is a day, with the rain and the evaporation of a given day.
