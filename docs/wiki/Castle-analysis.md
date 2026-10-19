# Castle analysis

`extensions/castle/` checks a [castle plan](Castle) the way a structural engineer would. It finds the wind on a tower and the line of thrust in a masonry arch. It checks a wall at the edge of the moat and the water balance of the moat. It also puts the sun over the site and draws the shadows.

![Wijnendale Castle from the morning to the evening of 19 October, with the shadow of the keep moving across the moat](out/castle-simulation.png)

`examples/wijnendale_simulation.mojo` renders the frames and prints the results below. Each frame puts the sun where the equations put it over Torhout. The program prints one line for each result. The numbers come from estimated dimensions and typical loads. They show what the modules do. They are not a design check of the real castle.

## Wind on a tower

`wind.mojo` follows EN 1991-1-4 (Eurocode 1, part 1-4). The mean speed is `vm(z) = kr ln(z / z0) vb`. The terrain factor is `kr = 0.19 (z0 / 0.05)^0.07`. The turbulence intensity is `Iv(z) = 1 / ln(z / z0)`. The peak pressure is `qp = (1 + 7 Iv) 0.5 rho vm^2`. Below 2 m the pressure at 2 m applies.

`tower_wind_load` cuts the shaft into 40 strips. A strip carries the force coefficient times `qp` times the width. The result is a force and its moment about the base. The structural factor `cs cd` is 1. `cantilever_frequency` gives the first natural frequency of the shaft, `f1 = (1.8751^2 / 2 pi) sqrt(E I / (m L^4))`. A frequency above 1 Hz makes the quasi-static load fair.

`check_tower_base` takes the weight of the shaft and the roof and the wind moment. It gives the edge stresses `N/A ± M/W`, the eccentricity against the kern, the use of the design strength and the equilibrium limit state of EN 1990. The equilibrium ratio is `0.9 N R / (1.5 M)`.

| Result for the keep | Value |
|---|---|
| Basic wind speed, open country | 26 m/s |
| Peak pressure at 10 m | 0.99 kPa |
| Wind force, moment about the base | 166 kN, 2,584 kN m |
| First natural frequency | 2.53 Hz |
| Base stress, windward to leeward | 0.42 to 0.60 MPa |
| Design strength of the masonry | 2.19 MPa |
| Use of the strength | 27 percent |
| Equilibrium ratio | 9.6 |

The finite element model of [Frame analysis](Frame-analysis) gives the same frequency to within one percent. It is lower by half a percent, because the element mass includes the rotary inertia of the section.

## Masonry strength

`characteristic_strength` is equation 3.1 of EN 1996-1-1: `fk = K fb^0.7 fm^0.3`. `clay_brick_masonry` uses units of 15 MPa, lime mortar of 2.5 MPa and K of 0.55. That gives `fk` of 4.82 MPa and a modulus of 1000 `fk`. The design strength is `fk` over a partial factor. The checks above use 2.2.

## A masonry arch

`arch.mojo` is a limit analysis. Heyman's safe theorem says that an arch stands if one line of thrust, in equilibrium with the loads, lies inside the masonry. The masonry has no tension and it does not crush.

The half arch is cut into voussoirs by radial joints. Each voussoir carries its weight, the fill above it and the load on the deck. The crown carries a horizontal thrust `H` at a height `m / H`. Moments about the two edge points of each joint give two bounds on `m`:

```text
y_in H - A_in <= m <= y_ex H - A_ex
```

`A` is the moment of the loads from the crown to the joint. The bounds are linear in `H`. For a thrust `H` they leave an interval for `m`. The interval is open between a least and a greatest thrust. The geometric factor is the ring thickness over the least thickness that still holds a line of thrust, with the loads unchanged.

The result is checked against a known value. A semicircular ring under its own weight needs a thickness of 0.1075 of its mean radius. The module finds 0.10746 with 40 voussoirs. The thrust at that thickness is 0.395 of the weight of the half arch.

| Result for one arch of the bridge | Value |
|---|---|
| Span, rise, ring, width | 5 m, 1.4 m, 0.4 m, 4.2 m |
| Fill over the crown, deck load | 0.5 m at 19 kN/m3, 5 kPa |
| A line of thrust fits | Yes |
| Horizontal thrust, least to greatest | 178 to 375 kN |
| Least ring that holds a line | 40 mm |
| Geometric factor | 10.1 |

## The wall at the edge of the moat

`wall.mojo` checks a rectangular masonry wall that holds back the island. The fill has a Rankine active thrust. The water table in the fill can stand higher than the water in front. That is the case when the moat is lowered for repair. The net water thrust and the uplift under the base follow `net_hydrostatic` of [Retaining walls](Retaining-walls).

The checks are the classical ones. The overturning and sliding factors must be at least 1.5. The resultant must be in the middle third of the base. The base pressure must be below the allowable pressure. `required_thickness` finds the least thickness that passes.

| Result for a 4 m wall | Value |
|---|---|
| Fill | 18 kN/m3, friction angle 30 degrees, load of 5 kPa |
| Base friction, allowable pressure | 0.40, 150 kPa |
| Least thickness, moat full | 3.45 m |
| Least thickness, moat drained | 3.77 m |

A plain wall needs more than three meters. A real wall of this height has a batter, a footing or a buttress, and these are not modeled.

## Water balance of the moat

`water_balance.mojo` runs the moat through a year, one day at a time. The moat gains water from a stream and from rain. It loses water by evaporation, by leakage through its lining and over a weir. The sides are vertical, so a volume is a level over the water area.

The weir is a sharp-crested rectangular weir, `Q = Cd (2/3) sqrt(2 g) b h^1.5`. It answers within hours. A daily step therefore passes the surplus of a day over the weir. A deficit lowers the level below the crest.

`flanders_climate` holds monthly values typical of the Flemish lowland: 824 mm of rain and 608 mm of open water evaporation a year. They are assumptions. Replace them with data from a weather station.

| Result for a moat of 2,073 m2 | Value |
|---|---|
| Normal year | The level stays at the crest. 147,000 m3 go over the weir. |
| Dry year, 60 percent of the rain, stream failed | The level falls 74 cm below the crest. |
| Days with more than 10 cm of drawdown | 275 |
| Stream flow that holds the level in July | 0.09 L/s |

## The sun

`sun.mojo` reads `extensions/energy/solar.mojo`, the equations of Duffie and Beckman. The castle gives the latitude and the longitude. The shadow of a point at a height `h` is `h / tan(a)` long for a sun at altitude `a`. It points away from the sun. `day_length` follows from `cos(w) = -tan(phi) tan(delta)`.

| Clock time (UTC+2) | Altitude | Azimuth from south | Shadow of the keep |
|---|---|---|---|
| 09:00 | 5.7 degrees | -66.8 degrees | 280 m |
| 10:35 | 18.2 degrees | -46.4 degrees | 85 m |
| 12:11 | 26.7 degrees | -22.6 degrees | 56 m |
| 13:46 | 29.2 degrees | 3.9 degrees | 50 m |
| 15:22 | 24.8 degrees | 29.9 degrees | 61 m |
| 16:57 | 14.9 degrees | 52.6 degrees | 105 m |
| 17:45 | 8.6 degrees | 62.8 degrees | 186 m |

The day is 10.37 hours long. Azimuth is measured from south, and west is positive. Belgian clocks are two hours ahead of Greenwich until 25 October in 2026.

## How the checks are verified

| Check | Reference |
|---|---|
| Peak pressure | EN 1991-1-4 evaluated by hand |
| Wind load | A fine numerical integration of the wind profile |
| Natural frequency | The beam formula and the finite element model |
| Arch ring thickness | Heyman's value of 0.1075 for a semicircular arch |
| Arch loads | The closed-form area of the ring and of the fill |
| Wall thrust | Rankine's `Ka gamma H^2 / 2`, and a numerical integration with water |
| Water balance | Conservation of volume over the year, and a climate of 1 mm a day |
| Sun | The noon altitude at the solstices and the length of the day |

## Limits

- The wind check uses a force coefficient and no gust response. It does not treat vortex shedding.
- The arch analysis takes a symmetric load. It does not treat a point load, a fill that stiffens the arch or a failure by sliding of the voussoirs.
- The wall check uses a rectangular section and a Rankine thrust. It does not treat a slip circle.
- The water balance uses vertical sides, a daily step and typical climate values.
- A result is not a design check of the real castle. Every size is an estimate.
