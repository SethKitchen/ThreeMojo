# Binary solutions

`extensions/chemistry/solution.mojo` models the phases of a binary system, such as the liquid and the solid solutions of an alloy. It gives each component's activity and finds the two-phase regions at a temperature.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

## A phase model

A `PhaseModel` is one phase of components 1 and 2. Its molar Gibbs energy at the mole fraction x of component 2 is:

```text
G   = (1 - x) G1 + x G2 + R T ((1 - x) ln(1 - x) + x ln x) + Gex
Gex = x (1 - x) sum_k L_k (1 - 2 x)^k
```

G1 and G2 are the pure components' energies in this phase. The L_k are the Redlich-Kister parameters. Each is a `Linear` function of temperature, `a + b T`. With no L_k, the solution is ideal. With L0 only, it is regular.

| Method | Gives |
|---|---|
| `excess(x, T)` | Gex, in J/mol |
| `gibbs(x, T)` | G, in J/mol |
| `log_gamma(component, x, T)` | The natural log of a component's activity coefficient |
| `activity(component, x, T)` | The activity, x times the coefficient |

A reaction can take an activity as the fraction of a condensed term. A dissolved metal then has a lower driving force than the pure metal.

## Phase boundaries

`phase_boundaries(phases, T)` finds the two-phase regions at a temperature. It samples every phase's Gibbs curve and takes their lower convex hull. A stretch of the hull that spans no sampled point is a `TieLine`. The tie line joins two phases, or two compositions of one phase across a miscibility gap.

The ends of each tie line are the phase boundaries, to the sampling step. The default is 2000 samples, and `MAX_SAMPLES` is the most. Scan the temperature to draw a phase diagram.

## Checks

The tests compare the hull with closed forms that it does not use:

- A symmetric regular solution with parameter W has a miscibility gap below `Tc = W / (2 R)`. Its edges solve `ln(x / (1 - x)) = W (2x - 1) / (R T)`.
- Two ideal phases form a lens. With `k_i = exp((Gs_i - Gl_i) / R T)`, the solidus is `(1 - k1) / (k2 - k1)`, and the liquidus is k2 times that.
- An activity coefficient equals the partial molar excess energy, from a finite difference of `excess`.

## Where the parameters come from

The parameters of a real alloy come from an assessment, such as a CALPHAD database. Most such databases are licensed, so the module takes the parameters as inputs. Give each parameter's source beside it, as a stated bound gives its source.

## Limits

A model has two components. Each phase is one sublattice, with no order. Magnetic and pressure terms are not modeled.
