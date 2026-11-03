# Chemical equilibrium

`equilibrate` finds what a charge of substances becomes at a temperature and a pressure. It minimizes the Gibbs energy with every element conserved. The gases form one ideal mixture, and each condensed substance is a pure phase that can enter or leave.

This page is a reference for `extensions/chemistry/equilibrium.mojo`. For the rest of the library, see [Process chemistry](Process-chemistry).

## Solve a charge

Give the candidates that can form, the charge, the temperature and the pressure:

```mojo
from extensions.chemistry.catalog import (
    carbon_dioxide, carbon_monoxide, graphite, oxygen,
)
from extensions.chemistry.equilibrium import Charge, equilibrate
from extensions.chemistry.quantities import Amount64, MOLE
from units.si import Pressure64
from units.temperature import Temperature64

var result = equilibrate(
    [graphite(), carbon_monoxide(), carbon_dioxide(), oxygen()],
    [Charge(graphite(), Amount64(2, MOLE)),
     Charge(carbon_dioxide(), Amount64(1, MOLE))],
    Temperature64(1000), Pressure64(1e5),
)
result.mole_fraction("CO(g)")   # about 0.69
```

An `Equilibrium` gives `amount_of(name)`, `gas_amount()`, `mole_fraction(name)` and `share(element, name)`. The share is the part of an element that ends in one substance.

## The method

The solver is the method of NASA CEA (Gordon and McBride, NASA RP-1311, 1994). A Newton iteration solves for the element potentials, the change in the total gas and the change in each condensed amount. The gas amounts follow from the potentials. The step is damped as CEA damps it, so a trace species cannot jump by many orders at once.

After each solution, a condensed phase with a negative amount leaves. Then the absent condensed phase with the most negative driving force enters. The search stops when no phase changes, or after `max_phase_changes`.

Some charges have element balances that are not independent. CaO, CaCO3 and CO2 are an example: the calcium and the carbon fix the oxygen. The solver drops the dependent balances by Gaussian elimination before it iterates. It then checks every balance of the result to 1e-9.

A candidate that holds an element the charge does not hold is left out. A condensed candidate whose data does not reach the temperature is left out too.

## A yield as a requirement

`EquilibriumShare` is a `Constraint`. It holds where the share of an element that ends in a product reaches a minimum. Add it to a window with `met_intervals`, as [Add a constraint](Process-chemistry#add-a-constraint) shows. For example, a chlorination can require that 99 % of the titanium leaves as TiCl4 gas.

## Checks

The tests compare each result with a closed form that the solver does not use:

| Case | Closed form |
|---|---|
| Excess carbon in CO2 where K = 1 | The CO fraction x solves x^2 / (1 - x) = 1: 0.618034, to 1e-14 |
| Limestone in argon | CO2 at the decomposition pressure while calcite and lime coexist |
| H2 at 3000 K | x^2 / (1 - x) = K for the H fraction |

`tools/check_chemistry_cantera.mojo` compares four gas mixtures with Cantera's solver. Both read the same NASA data, and they agree to 1e-13 in mole fraction. CI does not install Cantera, so this is a developer check:

```sh
uv pip install --python .venv/bin/python cantera
PYTHONPATH=$(ls -d .venv/lib/python3*/site-packages) \
    .venv/bin/mojo run -I . tools/check_chemistry_cantera.mojo
```

Cantera reads NASA files at a reference pressure of one atmosphere, but the NASA data is at one bar. The tool rebuilds each Cantera species at one bar first.

## Limits

Gases are ideal, and condensed phases are pure. For a solution phase, see [Binary solutions](Binary-solutions). Equilibrium says where a charge ends, not how fast it gets there. For rates, see [Rates and transport](Rates-and-transport).
