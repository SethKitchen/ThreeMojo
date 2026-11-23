# Groundwater flow

`extensions/groundwater/` solves steady groundwater flow in one aquifer layer. It gives the head of each cell of a grid, by the block-centered finite differences of MODFLOW. A checked result is a numerical result. It does not establish engineering validity.

## Modules

| Module | What it gives |
|---|---|
| `kinds` | `CellKind` with `ACTIVE`, `FIXED_HEAD` and `INACTIVE`. `AquiferKind` with `CONFINED` and `UNCONFINED`. |
| `aquifer` | `Aquifer`, `solve_heads`, `HeadResult`, `HeadOptions` and `default_head_options` |

## Build a layer

An `Aquifer` is a grid of equal cells. Cell (i, j) is column i along x and row j along y. Each cell has a hydraulic conductivity. A new layer has active cells only.

```mojo
var aquifer = Aquifer(41, 41, Length64(410, METER), Length64(410, METER), CONFINED, Length64(0, METER), Length64(20, METER), Velocity64(1e-4, METER_PER_SECOND))
aquifer.set_fixed_head(0, 20, Length64(30, METER))
aquifer.add_well(20, 20, VolumeFlowRate64(-0.002, CUBIC_METER_PER_SECOND))
aquifer.set_recharge(Velocity64(2e-8, METER_PER_SECOND))
```

| Method | What it does |
|---|---|
| `set_conductivity(i, j, k)` | Sets the hydraulic conductivity of one cell |
| `set_fixed_head(i, j, head)` | Makes a cell a cell of fixed head, such as a river or a lake that cuts the layer |
| `set_inactive(i, j)` | Makes a cell pass no water, such as rock |
| `add_well(i, j, rate)` | Adds a well. A negative rate pumps water out, as in MODFLOW. |
| `set_recharge(rate)` | Sets the water that enters every cell from above, per area and per time |

The sides of the grid are no-flow boundaries. So are the faces of an inactive cell. A well in a cell that is not active has no effect.

A `CONFINED` layer is full between its bottom and its top. Its transmissivity is the conductivity times that thickness. An `UNCONFINED` layer has a water table. Its transmissivity is the conductivity times the head above the bottom. If the head is above the top, the layer is full, as a confined one is.

## Solve the heads

`solve_heads(aquifer, options)` returns a `HeadResult`.

```mojo
var result = solve_heads(aquifer, default_head_options())
var drawdown = Length64(30, METER) - result.head(20, 20)
var supply = result.fixed_head_flow()
```

| Result | Holds |
|---|---|
| `head(i, j)` | The head of a cell. An inactive cell has the bottom elevation. |
| `fixed_head_flow()` | The water that the cells of fixed head give to the layer. A negative flow leaves through them. |
| `from_wells`, `from_recharge` | The water from the wells and from the recharge of the active cells, in cubic meters per second |
| `balance()` | The sum of the three flows. It is zero but for round-off. |
| `iterations` | The number of solutions |

A confined layer needs one solution. An unconfined layer is solved again with the new heads, until the largest change of a head is below the tolerance. `default_head_options()` has a tolerance of 1e-9 m and a budget of 200 solutions.

## The method

The flow between two cells follows Darcy. It is their head difference times a conductance. The conductance is the width of their common face, over the distance of their centers, times the harmonic mean of their two transmissivities. The harmonic mean makes the flow through two zones in series exact.

Each active cell keeps its water. The flows from its four neighbors, its well and its recharge add to zero. This gives one linear equation per active cell. The matrix is symmetric and positive definite when each active cell has a path of cells to a fixed head. The solver factors it with the skyline factor of [Numerics](Numerics).

These are the equations of MODFLOW for one layer in steady flow. MODFLOW is in the public domain. The code is original.

## Validation

Each row is a test in `tests/test_groundwater.mojo`.

| Case | Reference | Error |
|---|---|---|
| Confined strip between two fixed heads | Darcy: a linear head | Below 1e-12 m |
| The same strip with two zones of conductivity | The flow of two zones in series | Below 1e-10 m |
| Unconfined strip with recharge, 41 cells | Dupuit: h² = h₁² - (h₁² - h₂²) x / L + (R / K) x (L - x) | Below 1 mm |
| The same strip, water budget | The recharge leaves through the fixed heads | Below 1e-12 m³/s |
| Well in a confined island of 41 by 41 cells | Thiem: Q / (2 π T) ln(r₂ / r₁) between 5 and 10 cells from the well | Below 2% |
| Strip with a wall of inactive cells across one row | A symmetric head, and no water in the wall | Below 1e-10 m |

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A cell count is not positive, the grid has more than 1048576 cells, or a size is not positive | `Aquifer` |
| The top is not above the bottom, or a conductivity is not positive | `Aquifer`, `set_conductivity` |
| A cell is out of range | The methods that take a cell |
| A head, a well rate or a recharge is not finite | `set_fixed_head`, `add_well`, `set_recharge` |
| The layer has no cell of fixed head, or an active cell has no path to one | `solve_heads` |
| A cell of an unconfined layer is dry | `solve_heads` |
| The heads do not settle within the budget | `solve_heads` |

## Limits

- The model has one layer, with one bottom and one top elevation.
- The flow is steady. The model has no storage and no time.
- A cell that goes dry raises an error. MODFLOW can make such a cell inactive and continue.
- A well is a source in a whole cell. The head of that cell is not the water level in the well.
- The model has no rivers, drains or head-dependent boundaries, and it reads no MODFLOW files.

## References

- McDonald and Harbaugh, "A modular three-dimensional finite-difference ground-water flow model", Techniques of Water-Resources Investigations 6-A1, US Geological Survey, 1988.
- Bear, "Hydraulics of Groundwater", McGraw-Hill, 1979: the Dupuit approximation and flow to wells.
- Fetter, "Applied Hydrogeology", 4th edition, Prentice Hall, 2001: Darcy's law and the Thiem equation.
