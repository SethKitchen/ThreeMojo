# Pipe networks

`extensions/hydraulics/` solves the steady flow of a network of pipes. It gives the head at each node and the flow in each link, by the global gradient algorithm that EPANET uses. A checked result is a numerical result. It does not establish engineering validity.

## Modules

| Module | What it gives |
|---|---|
| `kinds` | `NodeId`, `LinkId`, `NodeKind` with `JUNCTION` and `RESERVOIR`, `LinkKind` with `PIPE` and `PUMP`, `HeadLossFormula`, and `KinematicViscosity64` |
| `headloss` | `Roughness`, `hazen_williams`, `darcy_weisbach`, `chezy_manning`, `friction_factor`, `pipe_head_loss` and `HeadLoss` |
| `network` | `PipeNetwork` and `Link` |
| `solve` | `solve_network`, `NetworkResult`, `SolveOptions`, `default_options` and `link_head_loss` |

## Build a network

A network has nodes and links. A junction has an elevation and a demand, which is the flow that leaves the network there. A reservoir has a fixed head. A pipe joins two nodes and loses head to friction. A pump adds head from its start node to its end node.

```mojo
var network = PipeNetwork()
var lake = network.add_reservoir(Length64(60, METER))
var town = network.add_junction(Length64(20, METER), VolumeFlowRate64(0.05, CUBIC_METER_PER_SECOND))
var main = network.add_pipe(lake, town, Length64(1200, METER), Length64(0.3, METER), hazen_williams(120), 0)
```

| Method | Adds |
|---|---|
| `add_junction(elevation, demand)` | A junction. A negative demand is an inflow. |
| `add_reservoir(head)` | A node of fixed head |
| `add_pipe(start, end, length, diameter, roughness, minor_loss)` | A pipe. The minor loss is the sum of the coefficients K of its fittings. |
| `add_pump(start, end, design_flow, design_head)` | A pump with a one-point curve |
| `set_viscosity(viscosity)` | The kinematic viscosity of the fluid. The default is water at 20 °C, 1.004e-6 m²/s. |

Each pipe has its own formula. A network can mix the three.

| Roughness | Formula | Head loss of a flow q, in SI units |
|---|---|---|
| `hazen_williams(c)` | Hazen-Williams | 10.67 L q^1.852 / (C^1.852 d^4.8704) |
| `darcy_weisbach(height)` | Darcy-Weisbach | f (L / d) v² / (2 g) |
| `chezy_manning(n)` | Chezy-Manning | n² L v² / R^(4/3), with R = d / 4 |

A fitting adds K v² / (2 g).

The friction factor f follows EPANET. Below a Reynolds number of 2000 it is 64 / Re. From 4000 it is the formula of Swamee and Jain. Between them it is a cubic that meets both. `friction_factor(reynolds, relative_roughness)` gives it.

A pump has the one-point curve of EPANET. Its design flow is q₀ and its design head is h₀. At a flow q the pump adds a head of (4/3) h₀ - (1/3) h₀ (q / q₀)². So the shutoff head is 4/3 of the design head. The head is zero at twice the design flow.

## Solve the network

`solve_network(network, options)` returns a `NetworkResult`.

```mojo
var result = solve_network(network, default_options())
var pressure = result.pressure_head(town)
var flow = result.flow(main)
```

| Result | Holds |
|---|---|
| `head(node)` | The head at a node |
| `pressure_head(node)` | The head less the elevation. A negative value means that the network cannot supply the junction. |
| `flow(link)` | The flow from the start node to the end node. A negative flow runs the other way. |
| `velocity(link)` | The mean velocity in a pipe |
| `heads`, `flows`, `iterations` | The raw vectors, in meters and cubic meters per second, and the iteration count |

`link_head_loss(network, link, flow)` gives the head that a link loses at a flow. For a pump it is minus the head that the pump adds.

`default_options()` has an accuracy of 1e-10 and a budget of 200 iterations. The accuracy is the sum of the flow changes of one iteration over the sum of the flows. EPANET uses 0.001. `SolveOptions(accuracy, iterations)` sets both.

## The method

The unknowns are the head at each junction and the flow in each link. Each link gives one equation: the head at its start less the head at its end is its head loss h(q). Each junction gives one equation: the flows in, less the flows out, equal the demand.

The global gradient algorithm of Todini and Pilati is Newton's method on both sets of equations at once. Each iteration has these steps:

1. For each link, find p = 1 / h'(q) and y = p h(q).
2. Solve a symmetric positive definite system for the junction heads. Its matrix has the sum of p of the links at a junction on the diagonal, and -p between two joined junctions.
3. Set the flow of each link to q - y + p (H_start - H_end).

The flows of each iterate balance at each junction. The first guess is a velocity of 0.3048 m/s in each pipe and the design flow in each pump, as in EPANET.

A pipe at rest has a gradient of zero, which makes the system singular. So a flow whose gradient is below 1e-7 s/m² has the linear loss of that gradient. EPANET does the same. Laminar flow is linear already and keeps its own gradient.

The Darcy-Weisbach gradient takes the friction factor as constant, as EPANET does. The iteration still converges to the exact head loss.

EPANET is in the public domain. The solver follows the method of its manual. The code is original.

## Differences from EPANET

- EPANET states its formulas in US units, with rounded coefficients: 4.727 for Hazen-Williams and 4.66 for Chezy-Manning, with a diameter exponent of 5.33. This port uses the SI forms above. The Chezy-Manning form here is exact, with an exponent of 16/3. The head losses differ from EPANET by less than 0.1%.
- Each pipe has its own formula. EPANET has one formula for the whole network.
- A pump that runs backward raises an error. EPANET closes the pump and continues.

## Validation

Each row is a test in `tests/test_hydraulics.mojo`.

| Case | Reference | Error |
|---|---|---|
| Friction factor, relative roughness 1e-6 to 1e-2, Reynolds number 5000 to 1e8 | The Colebrook-White equation, solved by iteration | Below 3% |
| Friction factor at Reynolds numbers of 2000 and 4000 | The cubic meets 64 / Re and Swamee and Jain | Below 1e-9 |
| One pipe, each formula, with and without a fitting | The closed form of the head loss | Below 1e-9 m. Below 1e-5 of the loss for Darcy-Weisbach. |
| One pipe, laminar oil | Hagen and Poiseuille, 128 ν L q / (π g d⁴) | Below 1e-12 m |
| Two parallel pipes with C of 100 and 140 | Flows in the ratio 100 to 140 | Below 1e-10 m³/s |
| Two loops, two reservoirs, seven pipes, all formulas | The junction equations and the link equations | Below 1e-12 m³/s and 1e-8 m |
| Pump, pipe and a lift of 30 m | The operating point, by bisection | Below 1e-10 m³/s |
| Network with no demand | No flow, and the head of the reservoir | Below 1e-9 m |

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| An id is out of range | All methods that take an id |
| An elevation, a demand or a head is not finite | `add_junction`, `add_reservoir` |
| A link joins a node to itself | `add_pipe`, `add_pump` |
| A length, a diameter, a roughness or a minor loss is not valid | `add_pipe` |
| A design flow or a design head is not positive | `add_pump` |
| The network has no reservoir, or a junction has no path to one | `solve_network` |
| A pump runs backward | `solve_network` |
| The iteration does not converge within its budget | `solve_network` |
| A velocity is asked of a pump | `NetworkResult.velocity` |

## Limits

- The flow is steady. The solver has no tanks with a level, no demand patterns and no time.
- A link is a pipe or a pump. The solver has no valves and no check valves.
- A pump has a one-point curve and runs at one speed.
- The demands are fixed. A pressure below zero does not reduce a demand.
- The solver does not model water quality.

## References

- Todini and Pilati, "A gradient algorithm for the analysis of pipe networks", in "Computer Applications in Water Supply", volume 1, 1988.
- Rossman, "EPANET 2 Users Manual", EPA/600/R-00/057, US Environmental Protection Agency, 2000: section 3.1 and appendix D.
- Swamee and Jain, "Explicit equations for pipe-flow problems", Journal of the Hydraulics Division, ASCE, 1976.
- Colebrook, "Turbulent flow in pipes, with particular reference to the transition region between the smooth and rough pipe laws", ICE Journal, 1939.
- Dunlop, "WADI Users Manual", Local Government Computer Services Board, Dublin, 1991, as cited by Rossman: the friction factor in the critical zone.
