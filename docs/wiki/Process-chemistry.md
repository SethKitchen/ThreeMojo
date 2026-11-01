# Process chemistry

`extensions/chemistry/` models the requirements of a process step: what must hold for a material to become a product. It computes driving forces and phase changes from NASA thermochemical data. It checks stated bounds from practice and from the equipment. It returns the operating window, the temperatures where every requirement holds, and a report that says why each bound is there.

This is not a three.js port. See [Extensions](Extensions). For the reasons behind the method, see [Why a process runs where it does](Why-a-process-runs-where-it-does).

## Print the recipes

```sh
.venv/bin/mojo run -I . tools/process_report.mojo            # every recipe
.venv/bin/mojo run -I . tools/process_report.mojo titanium   # one recipe
```

The names are `titanium`, `diamond`, `bismuth` and `lime`. Each step prints its setting, its hazards, its window and each requirement at the planned temperature:

```text
Reduce TiCl4 with magnesium (Kroll)
  Setting: industrial plant
  Hazards: toxic gas, pyrophoric, burn
  Pressure: 101.325 kPa
  Window: 987.0 K (713.9 degC) to 1358.2 K (1085.0 degC)
  Planned: 1123.2 K (850.0 degC), every requirement met
  [met] thermodynamic: Magnesium must reduce the chloride.
      TiCl4(g) + 2 Mg -> Ti + 2 MgCl2: dG -309.9 kJ/mol; computed from NASA TM-4513 data
  [met] phase: MgCl2 must be liquid, so it can be drained from the retort.
      bound 987.0 K (713.9 degC); melting point in the NASA TM-4513 data
  [met] phase: Magnesium must not boil away at the retort pressure.
      Mg -> Mg(g): dG +23.0 kJ/mol; computed from NASA TM-4513 data
  [met] engineering: The steel retort must stay below the Fe-Ti eutectic.
      bound 1358.2 K (1085.0 degC); Murray (1981), the Fe-Ti phase diagram: 1085 degC
  [do] engineering: Fill the retort with argon. ...
  Fact: Ti + O2(g) -> TiO2: dG -741.0 kJ/mol, proceeds
```

The titanium recipe also prints the magnesium and the heat per kilogram of titanium. The diamond recipe prints the stress in the coating and the thickest coating that does not peel. The lime recipe prints a ledger. The fracture energy and the prices in the tool are example inputs. Replace them with your own measurements and quotes.

## Modules

| Module | What it gives |
|---|---|
| `kinds` | `Phase`, `RequirementKind`, `Check`, `Hazard` and `Setting` |
| `quantities` | `Molar` values per mole, `Amount64`, `GAS_CONSTANT`, `STANDARD_PRESSURE`, `BAR`, `ATMOSPHERE`, `TORR`, `MICROMETER`, `FractureEnergy64` and `amount_of` |
| `elements` | `Element` for 41 elements, with IUPAC 2021 atomic weights, and `Formula` |
| `thermo` | `Nasa7`, `Species` and `Substance` |
| `catalog` | The substances of the recipes, with NASA TM-4513 data |
| `reaction` | `Term`, `reactant`, `product` and `Reaction`, with `delta_g`, `delta_h`, `equilibrium_temperature` and `mass_ratio` |
| `process` | `Requirement`, its constructors, `Step`, `met_intervals`, `operating_window`, `unmet` and `report` |
| `coating` | `ElasticLayer`, `mismatch_stress` and `delamination_thickness` |
| `economics` | `StreamItem`, `stream_enthalpy`, `heat_duty`, `Money64`, `UnitPrice64`, `EnergyPrice64` and `Ledger` |
| `recipes` | The Kroll route, a diamond coating on a carbide tool, bismuth crystals and lime |

## Model a step

Make a `Step` with its setting, its pressure, a range to search and the planned temperature. Add one requirement for each condition. Then ask for the window and the report.

```mojo
from extensions.chemistry.catalog import (
    magnesium, magnesium_chloride, magnesium_gas, titanium,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.kinds import (
    ENGINEERING, INDUSTRIAL_PLANT, PHASE, THERMODYNAMIC,
)
from extensions.chemistry.process import (
    Step, above, below, held_back, operating_window, proceeds, report,
)
from extensions.chemistry.quantities import ATMOSPHERE
from extensions.chemistry.reaction import Reaction, product, reactant
from units.si import Pressure64
from units.temperature import CELSIUS, Temperature64

var step = Step(
    "Reduce TiCl4", INDUSTRIAL_PLANT, Pressure64(1, ATMOSPHERE),
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

`step.add_hazard` adds a `Hazard`. `step.add_fact` adds a reaction that the report evaluates at the planned temperature. A fact does not limit the window. `unmet(step)` counts the requirements that fail at the planned temperature.

## Requirements

Each requirement has a `RequirementKind`: `THERMODYNAMIC`, `PHASE`, `KINETIC`, `PHYSICAL` or `ENGINEERING`. The kind names the science that the requirement comes from. The `Check` says how the module tests it:

| Constructor | Check | Holds where |
|---|---|---|
| `proceeds` | `PROCEEDS` | The reaction's Gibbs energy change is below zero |
| `held_back` | `HELD_BACK` | The change is above zero |
| `above`, `below` | `ABOVE`, `BELOW` | The temperature is above or below the stated bound |
| `pressure_above`, `pressure_below` | `PRESSURE_ABOVE`, `PRESSURE_BELOW` | The step's pressure is above or below the bound |
| `action` | `ACTION` | Always. The report lists it as a thing to do |

A reaction check computes its result. A phase change is a reaction too, so a boiling point at the step's pressure comes from the data. A stated bound names its source. A reaction check is not met where a substance's data does not reach.

`met_intervals` samples a requirement at 400 points in the range and finds each change by bisection. `operating_window` intersects the intervals of every requirement. A feature narrower than a 400th of the range can be missed.

## The driving force

A `Term` is a substance with a coefficient: `reactant` makes it negative and `product` makes it positive. A gas term also has a mole fraction of the total pressure. `Reaction` refuses terms that do not balance every element.

The change is the sum of coefficient times chemical potential. For an ideal gas, the potential is `G(T) + R T ln(x P / p0)`. For a pure condensed phase that does not compress, it is `G(T) + V (P - p0)`. `p0` is one bar. Below zero, the reaction proceeds.

`equilibrium_temperature` finds where the change crosses zero between two temperatures. `mass_ratio` gives the kilograms of one substance per kilogram of another.

## The data

The coefficients are the seven-coefficient NASA polynomials of McBride, Gordon and Reno, NASA TM-4513, 1993. They were copied unchanged from the conversion that Cantera 3.2 ships. The comment above each species gives the source code that TM-4513 assigns to it. See [THIRD-PARTY-NOTICES.md](https://github.com/SethKitchen/ThreeMojo/blob/main/THIRD-PARTY-NOTICES.md).

A `Species` is one phase of one formula, valid over the range of its data. A `Substance` joins the condensed phases of one formula, solid to liquid, or holds one gas. It uses the phase whose range holds the temperature. The ends of adjacent ranges are the transitions, so `melting_point` reads the data.

TM-4513 has no diamond. `diamond` is graphite's data, moved by the CODATA change at 298.15 K: 1.895 kJ/mol and -3.363 J/(mol K). That assumes equal heat capacities, so the change is low by roughly 1 kJ/mol at 1000 K. TM-4513 has no bismuth, so the bismuth recipe uses the CRC Handbook melting point as a stated bound.

Each piece of data stops at its range. The calcite data ends at 1200 K, and the liquid TiCl4 data starts at 300 K. A computation outside a range raises an error.

## The recipes

| Step | Setting | Window | Lower bound | Upper bound |
|---|---|---|---|---|
| Chlorinate rutile with coke | Industrial plant | 900 to 1227 degC | Rate (kinetic, stated) | End of the search |
| Distill TiCl4 | Industrial plant | From 136 degC | TiCl4 boils (computed) | End of the search |
| Reduce TiCl4 with Mg (Kroll) | Industrial plant | 714 to 1085 degC | MgCl2 melts (data) | Fe-Ti eutectic (stated) |
| Vacuum distillation at 10 Pa | Industrial plant | 702 to 1085 degC | MgCl2 evaporates (computed) | Fe-Ti eutectic (stated) |
| Diamond on carbide at 30 Torr | Equipped lab | 700 to 1000 degC | Growth rate (stated) | Cobalt (stated) |
| Hydrogen filament at 30 Torr | Equipped lab | 1758 to 3422 degC | 1 % atomic hydrogen (computed) | Tungsten melts (stated) |
| Bismuth crystals | Home workshop | From 271 degC | Bismuth melts (stated) | End of the search |
| Lime | Home workshop | 894 to 927 degC | CaCO3 gives off CO2 (computed) | The calcite data ends |

The diamond step shows a metastable product. Graphite to diamond does not proceed at 30 Torr: its change is +5.7 kJ/mol at 850 degC. Methane at 1 % in hydrogen can still deposit diamond, at -14.5 kJ/mol. Atomic hydrogen from the filament etches graphite faster than diamond, so the diamond survives. That last requirement is kinetic, so the recipe states it as an action.

The recipes are models for learning and planning. They are not operating procedures. Check each bound against your equipment's own limits.

## Coatings

`mismatch_stress` gives the biaxial stress in a thin coating on a thick substrate after cooling. Positive is compression in the coating:

```text
sigma = E_c / (1 - nu_c) * (alpha_s - alpha_c) * (T_deposition - T_service)
```

`delamination_thickness` gives the thickest coating that does not peel from an edge. It uses the plane-strain energy release rate of Hutchinson and Suo (1992), `G = (1 - nu_c^2) sigma^2 h / (2 E_c)`. The coating peels when `G` reaches the interface fracture energy.

`CVD_DIAMOND` and `CEMENTED_CARBIDE` hold typical values. Diamond deposited at 850 degC on carbide with 6 % cobalt cools to about 2.5 GPa of compression. At an example fracture energy of 30 J/m², the limit is about 11 micrometers. The fracture energy depends on the surface preparation. Measure it on the real surface, for example with a scratch test.

## Energy and money

A `StreamItem` is an amount of a substance at a temperature. `heat_duty` returns the enthalpy that leaves minus the enthalpy that enters. Above zero, the step needs heat. Below zero, it gives off heat that the equipment must remove. The Kroll reduction gives off about 1.35 kWh per kilogram of titanium, from a feed at 300 K to products at 850 degC.

A `Ledger` records purchases, the energy bought for a heat duty, and sales. `heat` divides the duty by an efficiency, and a duty of zero or below costs nothing. `margin` returns earnings minus spending. The ledger leaves out labor, equipment, waste, losses and taxes. `Money64` holds one currency, which you choose.

## Checks against references

The tests compare computed values with references that do not come from TM-4513:

| Quantity | Computed | Reference |
|---|---|---|
| TiCl4 normal boiling point | 409.2 K | 409.6 K, CRC Handbook |
| Mg normal boiling point | 1365.7 K | 1363 K, CRC Handbook |
| CaCO3 to CaO in 1 atm of CO2 | 1167 K | About 1171 K |
| Boudouard balance at 1 bar | 973 K | About 973 K |
| Methane to graphite and H2 at 1 bar | 818 K | About 818 K |
| Graphite to diamond at 298 K | 1.54 GPa | About 1.5 GPa, Berman and Simon |

The MgCl2 vapor data gives a boiling point of 1631 K at one atmosphere. The measured value is about 1685 K, so treat MgCl2 evaporation as an estimate.

## Add a substance

1. Find the species in NASA TM-4513, or in another public-domain table.
2. Make one `Species` for each phase, with its `Formula`, `Phase`, `Nasa7` data and molar volume.
3. Join condensed phases in a `Substance`, coldest first. Each range must start where the last ends.
4. Keep each gas a `Substance` of its own.
5. Test it at 298.15 K against the CODATA or NBS enthalpy and entropy.

## Limits

Gases are ideal. Condensed phases are pure and do not compress. There are no solutions, alloys, slags or aqueous species, and no activity coefficients. The module does not compute rates or mass transfer. Practice supplies kinetic bounds as stated values.

A hazard list names the dangers of a step. It is not a risk assessment. The `Setting` names the least equipped place where a step can be done safely. Do not do an `INDUSTRIAL_PLANT` step anywhere else.

Prices, fracture energies and material properties in the recipes are example inputs. Replace them with data for your materials and your supplier.
