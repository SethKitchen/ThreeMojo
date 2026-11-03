# Rates and transport

Thermodynamics says whether a step can run. Rates say how long it takes. `extensions/chemistry/kinetics.mojo` and `transport.mojo` turn measured rate data into times, depths and temperature bounds.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

## Arrhenius rates

An `Arrhenius` rate constant is `k = A exp(-Ea / R T)`, first order, in 1/s.

- `rate(temperature)` gives k.
- `temperature_for(rate)` gives the temperature where k reaches a rate.
- `half_life(temperature)` gives ln 2 / k.

`RateAtLeast` is a `Constraint`. It holds where k reaches a minimum. A kinetic bound that practice states as a temperature, such as "above 900 degC", can then come from measured rate data instead.

```mojo
from extensions.chemistry.kinetics import Arrhenius, RateAtLeast
from extensions.chemistry.quantities import KILOJOULE_PER_MOLE, MolarEnergy64
from units.si import Frequency64

var law = Arrhenius(Frequency64(1e10), MolarEnergy64(150, KILOJOULE_PER_MOLE))
var need = RateAtLeast(law, Frequency64(1e-3))   # add with met_intervals
```

## Gas and solid: the shrinking core

`ShrinkingCore` is the model of Levenspiel ("Chemical Reaction Engineering", chapter 25) for a gas that reacts with a solid sphere. Three resistances act in series: the gas film, the layer of product ash, and the reaction at the core's surface. The time to convert a share X of the sphere is:

```text
t = tau_film X
  + tau_ash (1 - 3 (1 - X)^(2/3) + 2 (1 - X))
  + tau_reaction (1 - (1 - X)^(1/3))
```

`ShrinkingCore.from_properties` computes the three times from the properties of the sphere and the gas. These are the radius, the solid's molar density, the gas concentration and the stoichiometry. They also include the film coefficient, the ash diffusivity and the surface rate constant. `time_to(conversion)` gives the time, and `conversion_at(time)` inverts it by bisection. The largest of the three times shows which resistance controls the step.

## Evaporation

`evaporation_flux` is the Hertz-Knudsen-Langmuir rate at which a surface loses mass into a vacuum or a thin gas:

```text
J = alpha (p_sat - p) sqrt(M / (2 pi R T))
```

`vapor_pressure(condensed, vapor, temperature)` finds `p_sat` from the data. `evaporation_time` turns a flux into the time to remove a mass from an area. The vacuum distillation of a Kroll sponge is an example: it boils the leftover Mg and MgCl2 away.

## Diffusion into a surface

`Diffusivity` is an Arrhenius diffusion coefficient, `D = D0 exp(-Q / R T)`. `case_depth` and `time_to_depth` solve Fick's second law for a semi-infinite solid with a fixed surface concentration:

```text
(C - C0) / (Cs - C0) = erfc(x / (2 sqrt(D t)))
```

This is the case depth of carburizing and nitriding.

## Heating a part

`heating_time` is the lumped-capacitance time to heat a body in a furnace. It is valid where the Biot number `h L / k` is below about 0.1. `biot` gives that number, and `heating_time` raises an error above the limit.

## Checks

| Quantity | Computed | Reference |
|---|---|---|
| Carburizing time to 0.80 wt% C at 0.5 mm, 950 degC | 7.05 h | About 7.1 h, Callister |
| Mg vapor pressure at 971 K | Within 10 % of 1 kPa | 1 kPa, CRC Handbook |
| Shrinking core, one resistance at a time | Equal | Levenspiel's closed forms |

## Limits

A rate constant comes from a measurement on the real material. The library does not predict one. The shrinking-core model takes spheres of one size, and it does not model the heat of the reaction.
