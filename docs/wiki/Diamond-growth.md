# Diamond growth

ThreeMojo models two ways to grow diamond crystals, and the cost of each. A press grows diamond from graphite at high pressure and high temperature (HPHT). A microwave plasma grows diamond on seeds by chemical vapor deposition (CVD). The cost model gives the cost per kept carat, the lowest cost that longer runs can reach, and the growth time for a target cost.

For steps, requirements and windows, see [Process chemistry](Process-chemistry). For the reasons behind the method, see [Why a process runs where it does](Why-a-process-runs-where-it-does).

## Modules

| Module | What it gives |
|---|---|
| `production` | `Money64`, `Price` and its units, `CARAT`, `GrowthRun`, `run_cost`, `cost_floor`, `growth_for_price`, `layer_rate` and `cost_report` |
| `processes.hpht` | `diamond_pressure`, `graphite_temperature`, `hpht_growth` and the example `hpht_run` |
| `processes.mpcvd` | `seed_growth`, `plasma_hydrogen` and the example `mpcvd_run` |

Print the steps and the cost of an example run:

```sh
.venv/bin/mojo run -I . tools/process_report.mojo hpht
.venv/bin/mojo run -I . tools/process_report.mojo mpcvd
```

## HPHT growth

`hpht_growth` grows diamond on seeds from carbon in a molten Fe-Ni solvent at 5.7 GPa. Its window is 1665 K to 1777 K, or 1392 to 1504 degC. This is the temperature-gradient method of Wentorf (1971). The carbon source sits at the hot end of the cell and the seeds sit at the cold end. The solvent dissolves the carbon and carries it down the gradient to the seeds.

| Bound | Value at 5.7 GPa | Requirement | Source |
|---|---|---|---|
| Lower | 1665 K (1392 degC) | The Fe-Ni solvent must melt | Fe-Ni-C eutectic, Pavel et al. (1991) |
| Upper | 1777 K (1504 degC) | Diamond must stay the stable form of carbon | Kennedy and Kennedy (1976) |

`graphite_temperature(pressure)` gives the upper bound at other pressures. `diamond_pressure(temperature)` gives the inverse. Both use the line of Kennedy and Kennedy: P = 19.4 kbar + T / 40 kbar per degC. The two functions refuse a point outside 1100 to 1625 degC, where the line was measured.

The window is narrow, about 110 K. A higher pressure moves the upper bound up by 40 K for each 0.1 GPa. The eutectic moves much less. So a higher pressure gives a wider window, but it puts more load on the anvils.

The step also lists four actions:

- Keep the carbon source a few tens of kelvin hotter than the seeds.
- Grow slowly, because a fast crystal traps the solvent as metal inclusions.
- Add aluminum or titanium to the solvent, for colorless crystals.
- Set the temperature by the heater power after a calibration run.

### Why the line is stated

The built-in data puts the graphite-diamond balance at 2625 K at 5.7 GPa. The measured value is 1777 K. The data takes the two heat capacities as equal and the solids as incompressible, so it is wrong by about 850 K here. The step states the measured line. It keeps the computed reaction to check the sign of the driving force, which the data gets right.

## Microwave plasma CVD on seeds

`seed_growth` grows single-crystal diamond on seeds in 6 % methane in hydrogen at 200 Torr. Its window is 700 to 1200 degC. The plasma runs at 100 to 300 Torr, which is much denser than a hot filament. The denser plasma splits more hydrogen, so the crystal grows faster than a coating does.

| Requirement | Kind | Bound | Source |
|---|---|---|---|
| Methane must be able to deposit diamond | Thermodynamic | Computed, below 700 degC | The data |
| The crystal must grow fast and clean | Kinetic | 700 to 1200 degC | Hemley et al., US patent 7452420 |
| The plasma must be dense and stable | Physical | 100 to 300 Torr | Hemley et al., US patent 7452420 |

Diamond is metastable at 200 Torr. Graphite to diamond does not proceed: its change is +6.2 kJ/mol at 1000 degC. Atomic hydrogen etches graphite faster than diamond, so the diamond survives.

`plasma_hydrogen` is the core of the plasma. Hydrogen splits to 5 % atoms at equilibrium above 2512 K at 200 Torr. A hot filament at 30 Torr needs less heat for 1 % atoms. A microwave plasma is not at equilibrium, so treat this bound as a lower limit on the gas temperature.

The step lists three actions. Add nitrogen at about 3 % of the methane to grow faster: Yan et al. (2002) grew at 50 to 150 micrometers per hour. Polish the seeds and etch them in the plasma before growth. Cut each grown layer off its seed and polish the seed again, so that one seed serves many runs.

## The cost of a run

`run_cost(run, electricity)` returns the cost of one run by what it is spent on, and the mass that is sold. A `GrowthRun` holds the growth time t and the turnaround t0. It also holds the power P, the crystals n, the rate r of one crystal and the kept share k. The consumables C and the price Q of an hour of equipment time complete it. With e the price of electric energy:

```text
cost of a run       = P t e + Q (t + t0) + C
kept mass           = r n k t
floor for long runs = (P e + Q) / (r n k)
```

`cost_floor` gives the floor. The fixed costs, Q t0 + C, spread over more mass as t grows, so the cost per kept carat falls toward the floor. `growth_for_price(run, electricity, target)` gives the shortest growth time that reaches a target cost. It refuses a target at or below the floor, because no growth time reaches it.

```mojo
from extensions.chemistry.processes.mpcvd import mpcvd_run
from extensions.chemistry.production import (
    EnergyPrice64, MassPrice64, PER_CARAT, PER_KILOWATT_HOUR,
    cost_floor, growth_for_price, run_cost,
)
from units.si import HOUR

var run = mpcvd_run()
var e = EnergyPrice64(0.10, PER_KILOWATT_HOUR)
print(run_cost(run, e).per_mass().to(PER_CARAT))   # 75.35
print(cost_floor(run, e).to(PER_CARAT))            # 59.35
print(growth_for_price(run, e, MassPrice64(70, PER_CARAT)).to(HOUR))
```

`Money64` is in the currency that you choose. A `Price` is money per a quantity, so a price per kilowatt-hour and a price per carat have different types. `layer_rate` gives the mass rate of a layer on one seed face, from its thickness rate and its area.

## The example runs

`hpht_run` and `mpcvd_run` are example numbers for the model. They are not quotes. Use the measured rates and the prices of your own plant.

| Example | Grown | Kept | Cost per kept carat | Floor | Equipment share |
|---|---|---|---|---|---|
| Press, 12 seeds at 3 mg/h for 60 h | 10.80 ct | 3.78 ct | 198.94 | 150.79 | 68.1 % |
| Plasma, 30 seeds of 7 mm at 10 um/h for 400 h | 103.34 ct | 31.00 ct | 75.35 | 59.35 | 72.6 % |

Both examples use electric energy at 0.10 per kWh. In both, the equipment time is most of the cost and the electric energy is less than an eighth. So a cheaper crystal comes first from more kept mass per hour of each machine. Grow more seeds at once, grow them faster, and keep more of each crystal. A lower electricity price helps less.

## Checks against references

| Quantity | Computed | Reference |
|---|---|---|
| Graphite-diamond line, 1100 to 1625 degC | Kennedy and Kennedy (1976) | Within 0.3 GPa of Berman and Simon (1955) |
| HPHT window at 5.7 GPa | 1392 to 1504 degC | 1360 to 1600 degC, Fe-Ni-C practice (Mu et al. 2021) |
| One carat | 0.2 g | 200 mg, the metric carat |
| Example run costs | The model | Hand arithmetic |

## Limits

The cost model has a constant growth rate. A real crystal can grow faster as its faces grow, and its quality can fall in a long run. Measure the rate and the kept share for each recipe. The bounds of the CVD step are ranges from practice, not limits computed from rates. The model is not an operating procedure, and a press or a plasma reactor needs a trained operator.
