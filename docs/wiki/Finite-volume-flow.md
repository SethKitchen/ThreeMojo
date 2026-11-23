# Finite-volume flow

`extensions/cfd/` solves laminar incompressible flow on a block of cells in two dimensions. It advances the Navier-Stokes equations in time with the PISO algorithm, as the OpenFOAM solver icoFoam does. A checked result is a numerical result. It does not establish engineering validity.

## Modules

| Module | What it gives |
|---|---|
| `kinds` | `Side` with `WEST`, `EAST`, `SOUTH` and `NORTH`. `BoundaryKind` with `FIXED_VELOCITY` and `FIXED_PRESSURE`. `ConvectionScheme` with `UPWIND` and `CENTRAL`. |
| `quantities` | `DynamicViscosity64`, `KinematicViscosity64` and their units `PASCAL_SECOND`, `CENTIPOISE`, `SQUARE_METER_PER_SECOND` and `CENTISTOKES` |
| `flow` | `Grid`, `Boundary`, `FlowCase`, `FlowOptions` and `FlowSolver` |

## Set up a case

A `Grid` is a block of equal rectangles. Cell (i, j) is column i from the west and row j from the south. A `FlowCase` holds the grid, the density and the dynamic viscosity of the fluid, and one boundary for each side. A new case has a wall on each side.

```mojo
var grid = Grid(32, 32, Length64(1, METER), Length64(1, METER))
var flow = FlowCase(grid, Density64(1, KILOGRAM_PER_CUBIC_METER), DynamicViscosity64(0.01, PASCAL_SECOND))
flow.set_boundary(NORTH, fixed_velocity(Velocity64(1, METER_PER_SECOND), Velocity64(0, METER_PER_SECOND)))
```

| Boundary | Meaning |
|---|---|
| `wall()` | The velocity is zero. |
| `fixed_velocity(u, v)` | The velocity is fixed. An inlet has a velocity through the side. A moving wall has a velocity along it. The pressure has no gradient along the normal. |
| `fixed_pressure(p)` | The pressure is fixed. The velocity has no gradient along the normal, so the fluid can leave or enter. |

`set_scheme(UPWIND)` selects the upwind convection scheme. The default is `CENTRAL`. The central scheme is second order. The upwind scheme is first order, and it stays bounded on a coarse grid at a high Reynolds number.

## Run the flow

`FlowSolver(flow, options)` starts with the fluid at rest. `step(dt)` advances one time step. `run(dt, steps)` advances several. `run_to_steady(dt, tolerance, budget)` advances until the largest change of a velocity in one step is below the tolerance. It returns the number of steps.

```mojo
var solver = FlowSolver(flow^, default_options())
var steps = solver.run_to_steady(Duration64(0.1, SECOND), Velocity64(1e-5, METER_PER_SECOND), 2000)
var speed = solver.velocity_x(16, 16)
var push = solver.pressure(16, 16)
```

| Result | Holds |
|---|---|
| `velocity_x(i, j)`, `velocity_y(i, j)` | The velocity at the center of a cell |
| `pressure(i, j)` | The pressure at the center of a cell |
| `elapsed()`, `change()` | The time, and the largest change of a velocity in the last step |
| `imbalance()` | The largest net flux that leaves a cell, for a block one meter thick |
| `u`, `v`, `p`, `flux_x`, `flux_y` | The raw fields. `p` is the pressure over the density. |

If no side has a fixed pressure, the pressure is free by a constant. The solver then holds it near zero in the cell at the south-west corner.

The time step is implicit. For a transient result, keep the Courant number u Δt / Δx near one or below. For a steady result, a Courant number of 5 gives the same flow in fewer steps.

`FlowOptions(correctors, sweeps, pressure_tolerance, pressure_iterations)` sets the inner iterations. `default_options()` gives 2 correctors, 50 sweeps, a tolerance of 1e-8 and a budget of 10000 iterations.

## The method

The cells hold the velocity and the pressure at their centers. The faces hold the volume flux. Each time step has these parts:

1. The momentum predictor. It is implicit Euler in time, with the old face fluxes and the old pressure gradient. Gauss-Seidel sweeps solve it.
2. The pressure correctors. Each corrector writes the velocity as H / A - (1 / A) ∇p. It takes the face fluxes from H / A. It solves the pressure equation ∇·((1 / A) ∇p) = ∇·(H / A) by conjugate gradients. Then it corrects the fluxes and the velocity.

The face flux comes from H / A and the pressure difference between the two cells of the face. It does not come from an interpolated velocity. This is the method of Rhie and Chow. It keeps the pressure free of the checkerboard mode on a grid that holds both variables at the cell centers.

The diffusion term uses the difference of the two cell values over their distance. At a side of fixed velocity it uses the half distance to the face.

The equations, the PISO loop and the names H and A follow icoFoam. The code is original and shares no source with OpenFOAM.

## Validation

Each row is a test in `tests/test_cfd_flow.mojo`.

| Case | Reference | Result |
|---|---|---|
| Channel between two walls, 3 by 6 cells, pressure drop along it | The exact solution of the finite-volume equations: G y (H - y) / (2 μ) + G Δy² / (8 μ) | Below 1e-8 m/s, with both schemes |
| The same channel, pressure | Linear along the channel | Below 1e-8 Pa |
| The same channel, flow rate | G H³ / (12 μ) times 1 + 2 / n² for n cells across | Below 1e-7 |
| Lid-driven cavity, Reynolds number 100, 8 cells a side | Ghia, Ghia and Shin, tables I and II, 12 values | 0.19 of the lid speed |
| The same cavity, 16 cells a side | The same 12 values | 0.029 of the lid speed |
| Duct with an inlet and an outlet, upwind scheme | Outlet flux equals inlet flux | Below 1e-8 m²/s |
| Fluid at rest | Stays at rest | Exact |

With 32 cells a side, the cavity has u = -0.2064 at y = 0.484 on the vertical center line. Ghia, Ghia and Shin give -0.2058 at y = 0.5. That grid is too slow for a test of 5 seconds under coverage, so no test holds this value.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A cell count is not positive, the grid has more than 1048576 cells, or a size is not positive and finite | `Grid` |
| A cell is out of range | `Grid.cell`, the result accessors |
| A density or a viscosity is not positive and finite | `FlowCase` |
| A side, a boundary or a scheme is not valid | `set_boundary`, `set_scheme`, `FlowSolver` |
| A count or a tolerance of the options is not positive | `FlowOptions` |
| A time step is not positive and finite | `step`, `run`, `run_to_steady` |
| The pressure solution does not converge within its budget | `step`, `run`, `run_to_steady` |
| The flow is not steady within the step budget | `run_to_steady` |

## Limits

- The grid is one block of equal rectangles in two dimensions. It has no grading and no obstacles.
- The flow is laminar and incompressible, with a constant viscosity. It has no turbulence model, no heat and no gravity.
- Each side has one boundary along its whole length.
- A side of fixed pressure takes the velocity of the cell beside it. So an inflow through it has no fixed direction.
- The time scheme is implicit Euler, which is first order.

## References

- Issa, "Solution of the implicitly discretised fluid flow equations by operator-splitting", Journal of Computational Physics 62, 1986: the PISO algorithm.
- Rhie and Chow, "Numerical study of the turbulent flow past an airfoil with trailing edge separation", AIAA Journal 21, 1983: the face flux.
- Jasak, "Error analysis and estimation for the finite volume method with applications to fluid flows", PhD thesis, Imperial College, 1996: the OpenFOAM discretization.
- Ferziger and Peric, "Computational Methods for Fluid Dynamics", 3rd edition, 2002: chapters 7 and 8.
- Ghia, Ghia and Shin, "High-Re solutions for incompressible flow using the Navier-Stokes equations and a multigrid method", Journal of Computational Physics 48, 1982.
- White, "Viscous Fluid Flow", 3rd edition, 2006: plane Poiseuille flow.
