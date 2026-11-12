# Process chemistry

`extensions/chemistry/` is a library that models the requirements of a process step: what must hold for a material to become a product. It computes driving forces, equilibria and phase changes from thermochemical data. It checks stated bounds from experiments and from the equipment. It returns the operating window, the temperatures where every requirement holds, and a report that says why each bound is there.

This is not a three.js port. See [Extensions](Extensions). For the reasons behind the method, see [Why a process runs where it does](Why-a-process-runs-where-it-does).

## Pages

This page covers steps, requirements, windows and reactions. Each area of the library has its own page:

| Page | What it covers |
|---|---|
| [Thermochemical data](Thermochemical-data) | NASA-7, NASA-9 and Shomate fits, CHEMKIN and CEA files, fitting a table, uncertainty |
| [Chemical equilibrium](Chemical-equilibrium) | The composition of a charge at a temperature and a pressure |
| [Process maps](Process-maps) | Scans of two variables, Ellingham diagrams and predominance maps |
| [Rates and transport](Rates-and-transport) | Arrhenius rates, the shrinking core, evaporation, case depth and heating |
| [Electrolysis and film color](Electrolysis-and-film-color) | Cell voltages, Faraday's law and the color of thin oxides |
| [Binary solutions](Binary-solutions) | Activities and phase boundaries of alloys |
| [Flowsheets and routes](Flowsheets-and-routes) | Steps joined by streams with recycle, and the search for routes |
| [Materials and coatings](Materials-and-coatings) | Expansion curves, melting points, eutectics and coating mechanics |
| [Crystals and figures](Crystals-and-figures) | A CIF reader, chart axes and the gallery figures |
| [Diamond growth](Diamond-growth) | HPHT and plasma CVD growth of diamond crystals, and the cost per carat |

## Layers

Each layer uses only the layers above it in this table. Extend the library at the layer that owns the concept.

| Module | What it gives |
|---|---|
| `quantities` | `Molar` values per mole, `Amount64`, `GAS_CONSTANT`, `STANDARD_PRESSURE`, `BAR`, `ATMOSPHERE`, `TORR`, `MICROMETER`, `ANGSTROM`, `FractureEnergy64` and `amount_of` |
| `kinds` | `Phase`, `RequirementKind`, `Check` and `Hazard` |
| `elements` | `Element` for the 84 elements with an IUPAC standard atomic weight, `element_from_symbol`, `Formula` and `parse_formula` |
| `thermo` | `ThermoFit` with `nasa7`, `nasa9` and `shomate`, `Species` and `Substance` |
| `chemkin` | `read_chemkin_thermo` and `write_chemkin_thermo` |
| `cea` | `read_cea_thermo`, a reader for NASA CEA `thermo.inp` files |
| `fitting` | `ThermoPoint` and `fit_nasa7` |
| `catalog` | Built-in substances, with NASA data |
| `reaction` | `Term`, `reactant`, `product` and `Reaction`, with `delta_g`, `delta_h`, `equilibrium_temperature`, `equilibrium_pressure`, `mass_ratio` and their uncertainties |
| `requirement` | The `Constraint` trait, `Requirement` and its constructors |
| `window` | `Interval`, `met_intervals`, `intersect` and `window_of`, for any constraint |
| `step` | `Step`, `operating_window`, `unmet` and `report` |
| `equilibrium` | `Charge`, `equilibrate`, `Equilibrium` and `EquilibriumShare` |
| `maps` | `scan`, `boundary`, `ellingham`, `oxygen_pressure`, `reducing_ratio`, `predominance` and `oxide_map` |
| `kinetics` | `Arrhenius`, `RateAtLeast` and `ShrinkingCore` |
| `transport` | `vapor_pressure`, `evaporation_flux`, `Diffusivity`, `case_depth` and `heating_time` |
| `electrochemistry` | `reversible_voltage`, `decomposition_voltage`, `faraday_mass`, `CellVoltage` and `specific_energy` |
| `optics` | `film_reflectance`, `film_color`, `linear_srgb` and `anodic_thickness` |
| `solution` | `Linear`, `PhaseModel` and `phase_boundaries` |
| `balance` | `StreamItem`, `stream_enthalpy` and `heat_duty` |
| `flowsheet` | `Flowsheet`, `StreamId` and `UnitKind` |
| `routes` | `find_routes` |
| `materials` | `ExpansionCurve`, `melting_point` and `eutectic_temperature` |
| `coating` | `ElasticLayer`, the coating stresses, and the peeling, buckling and cracking limits |
| `crystal` | `read_cif`, `Crystal` and `bonds` |
| `plot` | `Axes`, `nice_ticks` and `tick_text` |
| `production` | `Money64`, `Price`, `GrowthRun`, `run_cost`, `cost_floor` and `growth_for_price` |
| `processes` | Worked processes: `titanium`, `diamond`, `lime`, `hpht` and `mpcvd` |

## Model a step

Make a `Step` with its pressure, a range to search and the planned temperature. Add one requirement for each condition. Then ask for the window and the report.

```mojo
from extensions.chemistry.catalog import (
    magnesium, magnesium_chloride, magnesium_gas, titanium,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.kinds import ENGINEERING, PHASE, THERMODYNAMIC
from extensions.chemistry.quantities import ATMOSPHERE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.requirement import above, below, held_back, proceeds
from extensions.chemistry.step import Step, operating_window, report
from units.si import Pressure64
from units.temperature import CELSIUS, Temperature64

var step = Step(
    "Reduce TiCl4", Pressure64(1, ATMOSPHERE),
    Temperature64(800), Temperature64(1500), Temperature64(850, CELSIUS),
)
step.add(proceeds(THERMODYNAMIC, Reaction([
    reactant(titanium_tetrachloride_gas()), reactant(magnesium(), 2),
    product(titanium()), product(magnesium_chloride(), 2),
]), "Magnesium must reduce the chloride."))
step.add(above(PHASE, magnesium_chloride().melting_point(),
    "MgCl2 must drain as a liquid.", "NASA TM-4513"))
step.add(held_back(PHASE,
    Reaction([reactant(magnesium()), product(magnesium_gas())]),
    "Magnesium must not boil."))
step.add(below(ENGINEERING, Temperature64(1085, CELSIUS),
    "The steel retort must stay below the Fe-Ti eutectic.", "Murray (1981)"))
var window = operating_window(step)   # 987 K to 1358 K
print(report(step))
```

The report gives each requirement at the planned temperature, with its number and its source:

```text
Reduce TiCl4
  Hazards: none listed
  Pressure: 101.325 kPa
  Window: 987.0 K (713.9 degC) to 1358.2 K (1085.0 degC)
  Planned: 1123.2 K (850.0 degC), every requirement met
  [met] thermodynamic: Magnesium must reduce the chloride.
      TiCl4(g) + 2 Mg -> Ti + 2 MgCl2: dG -309.9 kJ/mol; computed from the thermochemical data
  [met] phase: MgCl2 must drain as a liquid.
      bound 987.0 K (713.9 degC); NASA TM-4513
  ...
```

`step.add_hazard` adds a `Hazard`. `step.add_fact` adds a reaction that the report evaluates at the planned temperature. A fact does not limit the window. `unmet(step)` counts the requirements that fail at the planned temperature.

## Requirements

Each requirement has a `RequirementKind`: `THERMODYNAMIC`, `PHASE`, `KINETIC`, `PHYSICAL` or `ENGINEERING`. The kind names the science that the requirement comes from. The `Check` says how the library tests it:

| Constructor | Check | Holds where |
|---|---|---|
| `proceeds` | `PROCEEDS` | The reaction's Gibbs energy change is below zero |
| `held_back` | `HELD_BACK` | The change is above zero |
| `above`, `below` | `ABOVE`, `BELOW` | The temperature is above or below the stated bound |
| `pressure_above`, `pressure_below` | `PRESSURE_ABOVE`, `PRESSURE_BELOW` | The pressure is above or below the bound |
| `action` | `ACTION` | Always. The report lists it as a thing to do |

A reaction check computes its result. A phase change is a reaction too, so a boiling point at the step's pressure comes from the data. A stated bound names its source. A reaction check is not met where a substance's data does not reach.

## Add a constraint

`Constraint` is the extension point for a new kind of requirement. A type that implements `holds` and `describe` works with `met_intervals`, `intersect` and `window_of`. It needs no change to the library.

```mojo
from extensions.chemistry.requirement import Constraint
from extensions.chemistry.window import intersect, met_intervals

@fieldwise_init
struct Near(Constraint):
    var target: Float64

    def holds(self, temperature: Temperature64, pressure: Pressure64) raises -> Bool:
        return abs(temperature.kelvin - self.target) < 50

    def describe(self, temperature: Temperature64, pressure: Pressure64) raises -> String:
        return String("within 50 K of ", self.target)

var narrowed = intersect(
    operating_window(step),
    met_intervals(Near(1000), step.low, step.high, step.pressure),
)
```

`window_of(constraints, low, high, pressure)` intersects a list of constraints of one type. `met_intervals` samples a constraint at 400 points in the range and finds each change by bisection. A feature narrower than a 400th of the range can be missed.

## Load your own data

`read_chemkin_thermo` reads NASA seven-coefficient data in the CHEMKIN thermo format. GRI-Mech, the Burcat tables and most combustion codes publish their data in this format. Each record gives one `Species`. Join the phases of one formula in a `Substance`, coldest first:

```mojo
from std.pathlib import Path
from extensions.chemistry.chemkin import read_chemkin_thermo
from extensions.chemistry.thermo import Substance

var species = read_chemkin_thermo(Path("thermo.dat").read_text())
var methane = Substance("CH4(g)", [species[0].copy()])
```

The reader refuses a short or misnumbered record with its line number. A loaded species has no molar volume. Set one where the pressure term of a condensed phase matters. For NASA-9 and Shomate data, CEA files, fitted tables and uncertainties, see [Thermochemical data](Thermochemical-data).

`parse_formula` reads a formula from text, with groups: `parse_formula("Ca(OH)2")` has one calcium, two oxygen and two hydrogen. `element_from_symbol` accepts either case, as data files write `TI` for titanium.

## The driving force

A `Term` is a substance with a coefficient: `reactant` makes it negative and `product` makes it positive. A gas term also has a mole fraction of the total pressure. A condensed term has an activity, one for a pure phase. `Reaction` refuses terms that do not balance every element.

The change is the sum of coefficient times chemical potential. For an ideal gas, the potential is `G(T) + R T ln(x P / p0)`. For a condensed phase that does not compress, it is `G(T) + V (P - p0) + R T ln a`. `p0` is one bar. Below zero, the reaction proceeds.

`equilibrium_temperature` finds where the change crosses zero between two temperatures. `equilibrium_pressure` finds where it crosses zero between two pressures, on a logarithmic scale. For an evaporation into a pure vapor, that is the vapor pressure. `mass_ratio` gives the kilograms of one substance per kilogram of another.

## The built-in data

The built-in coefficients are the NASA polynomials of McBride, Gordon and Reno, NASA TM-4513, 1993. Iron's solid phase uses the NASA-9 data of NASA TP-2002-211556. All were copied unchanged from the conversion that Cantera 3.2 ships. The comment above each species gives its source code. See [Thermochemical data](Thermochemical-data#the-catalog) and [THIRD-PARTY-NOTICES.md](https://github.com/SethKitchen/ThreeMojo/blob/main/THIRD-PARTY-NOTICES.md).

A `Species` is one phase of one formula, valid over the range of its data. A `Substance` joins the condensed phases of one formula, or holds one gas. It uses the phase whose range holds the temperature. The ends of adjacent ranges are the transitions, so `melting_point` reads the data.

TM-4513 has no diamond. `diamond` is graphite's data, moved by the CODATA change at 298.15 K: 1.895 kJ/mol and -3.363 J/(mol K). That assumes equal heat capacities, so the change is low by roughly 1 kJ/mol at 1000 K.

Each piece of data stops at its range. The calcite data ends at 1200 K, and the liquid TiCl4 data starts at 300 K. A computation outside a range raises an error.

## Worked processes

| Step | Window | Lower bound | Upper bound |
|---|---|---|---|
| Chlorinate rutile with coke | 900 to 1227 degC | Rate (kinetic, stated) | End of the search |
| Distill TiCl4 | From 136 degC | TiCl4 boils (computed) | End of the search |
| Reduce TiCl4 with Mg (Kroll) | 714 to 1085 degC | MgCl2 melts (data) | Fe-Ti eutectic (stated) |
| Vacuum distillation at 10 Pa | 702 to 1085 degC | MgCl2 evaporates (computed) | Fe-Ti eutectic (stated) |
| Diamond on carbide at 30 Torr | 700 to 1000 degC | Growth rate (stated) | Cobalt (stated) |
| Hydrogen filament at 30 Torr | 1758 to 3422 degC | 1 % atomic hydrogen (computed) | Tungsten melts (stated) |
| Lime burning | 894 to 927 degC | CaCO3 gives off CO2 (computed) | The calcite data ends |
| HPHT diamond at 5.7 GPa | 1392 to 1504 degC | Fe-Ni solvent melts (stated) | Graphite-diamond line (stated) |
| Diamond on seeds at 200 Torr | 700 to 1200 degC | Growth quality (stated) | Growth quality (stated) |
| Microwave plasma at 200 Torr | From 2239 degC | 5 % atomic hydrogen (computed) | End of the search |

Print them with `tools/process_report.mojo`:

```sh
.venv/bin/mojo run -I . tools/process_report.mojo            # every process
.venv/bin/mojo run -I . tools/process_report.mojo titanium   # titanium, diamond, lime, hpht or mpcvd
```

The diamond step shows a metastable product. Graphite to diamond does not proceed at 30 Torr: its change is +5.7 kJ/mol at 850 degC. Methane at 1 % in hydrogen can still deposit diamond, at -14.5 kJ/mol. Atomic hydrogen from the filament etches graphite faster than diamond, so the diamond survives. That last requirement is kinetic, so the step states it as an action. For diamond crystals grown in a press or on seeds, and their cost, see [Diamond growth](Diamond-growth).

## Add a process

1. Add a module to `extensions/chemistry/processes/`.
2. Build each step from the public layers: substances from `catalog` or from your own data, reactions, and requirements.
3. Give each stated bound its source. Leave a computed bound to the data.
4. Test each window edge against a reference that does not come from the same data.

## Coatings

`mismatch_stress` gives the biaxial stress in a thin coating on a thick substrate after cooling. `delamination_thickness` gives the thickest coating that does not peel from an edge. `processes.diamond` holds typical properties in `CVD_DIAMOND` and `CEMENTED_CARBIDE`. Diamond on carbide cools to about 2.5 GPa of compression, which limits it to about 11 micrometers at 30 J/m². For expansion curves, Stoney's stress, buckling and thermal shock, see [Materials and coatings](Materials-and-coatings).

## Energy balances

A `StreamItem` is an amount of a substance at a temperature. `heat_duty` returns the enthalpy that leaves minus the enthalpy that enters. Above zero, the step needs heat. Below zero, it gives off heat that the equipment must remove. The Kroll reduction gives off about 1.35 kWh per kilogram of titanium, from a feed at 300 K to products at 850 degC.

## Checks against references

The tests compare computed values with references that do not come from TM-4513:

| Quantity | Computed | Reference |
|---|---|---|
| TiCl4 normal boiling point | 409.2 K | 409.6 K, CRC Handbook |
| Mg normal boiling point | 1365.7 K | 1363 K, CRC Handbook |
| Mg vapor pressure, 701 K to 1361 K | Within 10 % | 1 Pa to 100 kPa, CRC Handbook |
| CaCO3 to CaO in 1 atm of CO2 | 1167 K | About 1171 K |
| Boudouard balance at 1 bar | 973 K | About 973 K |
| Methane to graphite and H2 at 1 bar | 818 K | About 818 K |
| Graphite to diamond at 298 K | 1.54 GPa | About 1.5 GPa, Berman and Simon |
| Methane read from a CHEMKIN record | The catalog's G | Equal to 1e-6 J/mol |

The MgCl2 vapor data gives a boiling point of 1631 K at one atmosphere. The measured value is about 1685 K, so treat MgCl2 evaporation as an estimate.

## Limits

Gases are ideal. A condensed phase is pure, or a binary solution with given parameters. There are no slags or aqueous species, so there are no Pourbaix diagrams. Rates come from measured constants. The library does not predict them.

A hazard list names the dangers of a step. It is not a risk assessment. The worked processes are models of requirements, not operating procedures. Chemistry separates and combines elements. It does not change one element into another.
