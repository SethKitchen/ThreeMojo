# Groundwater flow

`extensions/groundwater/` is a port of the groundwater flow (GWF) model of MODFLOW 6. It reads a MODFLOW 6 simulation folder and runs it one time step at a time. For each supported case it gives the same heads and flows as MODFLOW 6.9.0.dev0, to the last bit. A checked result is a numerical result. It does not establish engineering validity.

## Run a simulation

`Simulation(folder)` reads `mfsim.nam` and each file that it names. `step()` runs one time step. `done()` is true after the last time step.

```mojo
from extensions.groundwater.simulation import Simulation

var sim = Simulation("assets/modflow/cases/confined_steady")
while not sim.done():
    sim.step()
var h = sim.head(1, 3, 4)
```

| After a step | Holds |
|---|---|
| `head(layer, row, column)` | The head of one cell, as a `Length64`. The unit is the `LENGTH_UNITS` of DIS6. A model without `LENGTH_UNITS` is read as meters. |
| `heads()` | The head of each cell by user node, from index 1, in the model unit. A cell outside the model has 1e30, as in the head file of MODFLOW 6. |
| `flowja` | The flow of each connection, by position. Position `ia[n]` holds the sum of the flows of cell n, as in the budget file. |
| `sto.strgss`, `sto.strgsy` | The flows from specific storage and from specific yield of each cell |
| `bnds[i].simvals` | The flow of each bound of a boundary package |
| `icnvg`, `kiter_last` | 1 if the time step converged, and its number of outer iterations |

The packages are in `bnds` in the order that MODFLOW 6 makes them: WEL, DRN, RIV, GHB, RCH, EVT and then CHD. Packages of one type keep the order of the name file. This order sets the order of the sums in a cell, so it must agree.

## What the port includes

| Part | Files | Port |
|---|---|---|
| Simulation | `mfsim.nam`, TDIS6 | One GWF6 model and one IMS6 solution. Stress periods, time steps and the time step multiplier. |
| Grid | DIS6 | A structured grid with `IDOMAIN`. A value of 0 or less removes a cell. A value of -1 makes a vertical pass-through cell. |
| Starting heads | IC6 | `STRT` |
| Node property flow | NPF6 | `ICELLTYPE`, `K`, `K22`, `K33`, `ANGLE1` to `ANGLE3`, `WETDRY`. The options `ALTERNATIVE_CELL_AVERAGING`, `THICKSTRT`, `VARIABLECV`, `DEWATERED`, `PERCHED`, `REWET`, `K22OVERK`, `K33OVERK` and `HIGHEST_CELL_SATURATION` |
| Storage | STO6 | `ICONVERT`, `SS`, `SY`, steady-state and transient periods, `STORAGECOEFFICIENT`, `SS_CONFINED_ONLY` and the development options for the original formulation |
| Boundaries | CHD6, WEL6, DRN6, RIV6, GHB6, RCH6, EVT6 | List input, array input (`READASARRAYS`), auxiliary variables, `AUXMULTNAME`, `FIXED_CELL`, ET segments and `SURF_RATE_SPECIFIED` |
| Formulation | GWF name file | The standard formulation, and `NEWTON` with and without `UNDER_RELAXATION` |
| Outer iterations | IMS6 | The `SIMPLE`, `MODERATE` and `COMPLEX` defaults, the `NONE`, `SIMPLE`, `COOLEY` and `DBD` under-relaxation, backtracking and pseudo-transient continuation |
| Inner iterations | IMS6 | `CG` and `BICGSTAB`, with ILU0 or MILU0, diagonal or L2 norm scaling, the five `INNER_RCLOSE` tests and orthogonalization |

The port reads OC6 and OBS6 entries in the name file, and skips them. The caller reads the results from the structures in the table above.

## What the port does not include

The port raises an `Error` for each of these:

- The DISV6 and DISU6 grids
- XT3D in NPF6
- The ILUT and MILUT preconditioners, and the RCM and MD reordering of IMS6
- Time series (TS6) and time array series (TAS6)
- The water mover (MVR6), `AUTO_FLOW_REDUCE` in WEL6 and `AUXDEPTHNAME` in DRN6
- More than one model, or a solution group with `MXITER` other than 1
- The advanced packages: MAW, SFR, LAK, UZF, CSUB, BUY and VSC

## Validation

`assets/modflow/make_modflow_cases.py` writes 58 simulations to `assets/modflow/cases/`. It runs MODFLOW 6.9.0.dev0, commit 59d89e9f, on each. It stores the heads and the budget of each time step in `expected.txt`. It also stores whether each step converged, from `mfsim.lst`. `tests/test_modflow.mojo` runs the port on each simulation. Each double must be the same, and each step must converge or fail as it does in MODFLOW 6.

The references come from Linux x86-64. The port takes each power and logarithm from `glibc_pow` and `glibc_log` of [Numerics](Numerics.md), so the same doubles hold on macOS.

| Case | What it tests |
|---|---|
| `confined_steady` | A confined layer between two constant heads, with a well |
| `unconfined_transient` | Two layers, a convertible top layer, GHB, RIV, DRN, WEL, RCH, and a steady period before a transient one |
| `newton_steady`, `newton_highest_cell` | Newton-Raphson with pseudo-transient continuation, and `HIGHEST_CELL_SATURATION` over a stepped bottom |
| `newton_dbd_backtracking` | Newton under-relaxation, delta-bar-delta with momentum, backtracking, MILU0, diagonal scaling and the L2 norm test |
| `cooley_bicgstab`, `simple_strict`, `l2norm_relative` | Cooley and simple under-relaxation, L2 norm scaling, orthogonalization, and the strict, relative and relative L2 norm tests |
| `complexity_simple`, `complexity_moderate` | The defaults of two complexities |
| `evt_list`, `arrays_two_layers` | ET with segments and with a rate at the surface, and RCH and EVT from arrays with `IRCH` and `FIXED_CELL` |
| `rewet_perched` | Cells that go dry and wet again, `PERCHED`, and `VARIABLECV DEWATERED` |
| `average_logarithmic`, `average_amt_lmk`, `average_amt_hmk` | The other cell averages |
| `thickstrt_anisotropy_idomain` | `THICKSTRT`, `K22OVERK`, `K33OVERK`, `ANGLE1`, and removed and pass-through cells |
| `storage_coefficient`, `ss_confined_only`, `original_ss` | The storage options, a time step multiplier, feet and seconds |
| `auxmult_periods` | Auxiliary multipliers, and bounds that change from one period to the next |
| `ptc_option_exponent`, `ptc_del0`, `ptc_no_first`, `ptc_none` | The development options of pseudo-transient continuation, and `NO_PTC` |
| `rewet_wetfct`, `rewet_ihdwet`, `rewet_vertical` | Each rewetting option, cells that wet only from below, and steps that do not converge under `CONTINUE` |
| `perched_varcv`, `varcv_lower_partial`, `mixed_celltype`, `dry_lower_layer` | `VARIABLECV` with and without `DEWATERED`, confined and convertible cells side by side, a negative cell type, and a layer that starts dry |
| `angles3d` | Anisotropy in three angles |
| `newton_nur_dry`, `nur_overshoot`, `nur_single_cell`, `nur_converges`, `newton_exact`, `newton_chd_downstream` | Newton under-relaxation that resets a head or converges at a reset, a linear Newton problem of two steps, and a confined cell upstream of a convertible one |
| `newton_sto_original`, `newton_sto_confined_only` | The Newton storage terms of each storage formulation |
| `single_cell`, `isolated_cell` | A residual of zero, and a cell with no neighbors |
| `bounds_edge`, `evt_depths` | DRN and RIV above the head, ET in each segment and under its extinction depth, auxiliary multipliers, and packages without names |
| `ims_keywords`, `dbd_theta_floor`, `cooley_oscillate`, `cooley_reverse` | IMS keywords that set a default again, the floor of theta, and Cooley under-relaxation |
| `backtrack_once`, `backtrack_res_limit` | Backtracking that stops at its count and at its residual limit |
| `solver_bicgstab_breakdown`, `solver_bicgstab_rho_omega`, `solver_bicgstab_alpha`, `solver_cg_same_rho`, `solver_cg_zero_rho`, `solver_cg_zero_residual`, `solver_ptc_zero_residual` | The breakdown tests of CG and BiCGSTAB, residuals of zero, and pseudo-transient continuation at the same residual. A search over small models found these settings |

Two more suites check the input readers and the small functions. `tests/test_modflow_input.mojo` changes one text of a small simulation and checks each option and each error. `tests/test_modflow_units.mojo` gives chosen values to the conductance, saturation and solver functions.

To make the cases again, build MODFLOW 6 at that commit. Then run `python3 assets/modflow/make_modflow_cases.py PATH_TO_MF6` in Linux.

## How the port keeps each bit

A double result depends on the order of each operation. The port keeps the Fortran order:

- Each product goes through `mul` in `cmath.mojo`. The compiler cannot fuse it with an addition, and gfortran does not fuse it at `-O3` without `-march`.
- Each expression keeps its Fortran grouping.
- `x**n` with an integer `n` uses `powi`, the square-and-multiply method of the gfortran runtime. A real exponent uses `cpow` from the C library.
- A single-precision constant, such as `0.01` in the inner tolerance, is converted to a double from its single-precision value.
- A dot product is a sequential sum. The L2 norm uses the scaled sum of squares.
- Each real constant in `constants.mojo` is a `Float64`. Mojo folds the arithmetic of two float literals exactly. Thus `1.0 - 0.9` of two literals is 0.1, but Fortran gives 0.09999999999999998.

MODFLOW 6 bundles BLAS, SPARSKIT and other libraries under the LGPL. The port copies no code from them. `ddot`, `dnrm2` and `amux` in `ims.mojo` implement the published algorithms.

## Errors

The port raises `Error` with the message of MODFLOW 6 where one exists. It raises `Error` in these cases:

- A file named by a name file is missing, or a block or an array that it needs is missing.
- A keyword, an option or a value is not known or not supported.
- A value is out of range: a negative K, SS or SY, a layer number in `IRCH`, or a cell outside the active grid.
- Two constant head packages share a cell.
- `CG` is used with `NEWTON`, because the Newton matrix is not symmetric.
- `head` gets a cell outside the grid or outside the model.

## References

- Langevin, Hughes, Banta, Niswonger, Panday and Provost, "Documentation for the MODFLOW 6 Groundwater Flow Model", Techniques and Methods 6-A55, US Geological Survey, 2017.
- Hughes, Langevin and Banta, "Documentation for the MODFLOW 6 framework", Techniques and Methods 6-A57, US Geological Survey, 2017.
- Saad, "Iterative Methods for Sparse Linear Systems", 2nd edition, SIAM, 2003: CG, BiCGSTAB and incomplete LU.
- Lawson, Hanson, Kincaid and Krogh, "Basic Linear Algebra Subprograms for Fortran usage", ACM TOMS 5, 1979. It gives the dot product and the L2 norm.
