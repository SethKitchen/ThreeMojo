# Pipe networks

`extensions/epanet/` is a port of the engine of OWA EPANET 2.3.6. It reads an EPANET input file and runs the hydraulics and the water quality of the network over time. The tests compare it with the real EPANET program: on the seven example networks, on 540 small input files, and function by function. The values agree to the last bit in the function tests, and to ten significant digits over whole runs. A checked result is a numerical result. It does not establish engineering validity.

EPANET has the MIT license. A translation is allowed, so the port follows the C source line by line. See [THIRD-PARTY-NOTICES.md](https://github.com/SethKitchen/ThreeMojo/blob/main/THIRD-PARTY-NOTICES.md) and [Why the engineering solvers are original code](Why-the-engineering-solvers-are-original-code).

## Run a network

`EpanetProject(text)` reads the text of an `.inp` file. Then run the hydraulics, one step at a time, until the next step is zero.

```mojo
from extensions.epanet.kinds import EN_QUALITY
from extensions.epanet.project import EpanetProject

var p = EpanetProject(open("Net1.inp", "r").read())
var node = p.node_index("10")
p.open_hydraulics()
p.init_hydraulics(save=True)
while True:
    var t = p.run_hydraulics()
    var head = p.head(node)
    if p.next_hydraulics().value == 0.0:
        break
p.close_hydraulics()
```

Then run the water quality in the same way. After `close_hydraulics`, the water quality reads the hydraulics that `init_hydraulics(save=True)` saved.

```mojo
p.open_quality()
p.init_quality()
while True:
    var t = p.run_quality()
    var chlorine = p.node_value(node, EN_QUALITY)
    if p.next_quality().value == 0.0:
        break
p.close_quality()
```

You can also run the two together. Open both solvers, and call `run_quality` and `next_quality` after each hydraulic step. The water quality then uses the current hydraulic state. This is the same as the toolkit of EPANET.

## The functions

| Method | What it does | EPANET function |
|---|---|---|
| `EpanetProject(text)` | Reads a network. An error lists each bad line, as EPANET reports them. | `EN_open` |
| `open_hydraulics()` | Makes the hydraulic solver and checks the network | `EN_openH` |
| `init_hydraulics(save, init_flows)` | Sets the starting state. `save` keeps each step for the water quality. | `EN_initH` |
| `run_hydraulics()` | Solves the network at the current time. Returns the time. | `EN_runH` |
| `next_hydraulics()` | Moves to the next event. Returns the step, which is zero at the end. | `EN_nextH` |
| `close_hydraulics()` | Closes the hydraulic solver | `EN_closeH` |
| `open_quality()`, `init_quality()`, `run_quality()`, `next_quality()`, `close_quality()` | The same steps for the water quality | `EN_openQ` to `EN_closeQ` |
| `node_index(id)`, `link_index(id)` | The index of a name | `EN_getnodeindex`, `EN_getlinkindex` |
| `node_id(node)`, `link_id(link)` | The name of an index | `EN_getnodeid`, `EN_getlinkid` |
| `node_count()`, `link_count()` | The number of nodes and of links | `EN_getcount` |
| `duration()`, `report_step()`, `quality_type()` | The options of the file | `EN_gettimeparam`, `EN_getqualtype` |
| `head(node)`, `pressure_head(node)`, `demand(node)`, `flow(link)` | A result in SI units | `EN_getnodevalue`, `EN_getlinkvalue` |
| `node_value(node, property)`, `link_value(link, property)` | A result in the units of the input file | `EN_getnodevalue`, `EN_getlinkvalue` |

A node property is `EN_DEMAND`, `EN_HEAD`, `EN_PRESSURE` or `EN_QUALITY`. A link property is `EN_FLOW`, `EN_STATUS`, `EN_SETTING`, `EN_ENERGY` or `EN_LINKQUAL`. A `NodeIndex` and a `LinkIndex` start at 1, as in EPANET.

Each method raises `Error` with the EPANET error code and its text, for example `EPANET error 110: cannot solve network hydraulic equations`.

## What the port includes

The port has each part of the engine that changes a result.

| Part | C source | Mojo module |
|---|---|---|
| The input file, with each section, option and error code | `input1.c`, `input2.c`, `input3.c`, `rules.c` | `input`, `options`, `ruleparse`, `prepare`, `text`, `lookup` |
| The checks of a network | `input1.c`, `project.c` | `validate` |
| The ordering and the factorization of the sparse matrix | `smatrix.c`, `genmmd.c` | `smatrix`, `genmmd` |
| The hydraulics: the global gradient algorithm, with tanks, pumps, valves, check valves, controls, rules, patterns, curves, emitters, pressure driven demands and leaks | `hydraul.c`, `hydcoeffs.c`, `hydsolver.c`, `hydstatus.c`, `leakage.c`, `rules.c` | `hydraul`, `hydbase`, `coeffs`, `hydsolver`, `hydstatus`, `leakage`, `rules` |
| The energy of pumps | `hydraul.c` | `hydraul` |
| The water quality: chemicals, age, source trace, reactions and the four tank mixing models | `quality.c`, `qualroute.c`, `qualreact.c` | `quality` |
| The toolkit functions above | `epanet.c` | `project`, `api` |

The port does not include these parts. None of them changes a result.

- The report file and the binary output file. The reader keeps the `[REPORT]` options, but the port writes no report.
- The functions that edit a network, and the writer of an input file.
- The hydraulics file. The port keeps the saved steps in memory. It rounds each saved value to 32 bits, as the file does, so that the water quality is the same.
- The data of `[COORDINATES]`, `[VERTICES]`, `[LABELS]`, `[BACKDROP]` and `[TAGS]`. The reader reads these sections, and it checks their names as EPANET does.

## How the port stays exact

The equations amplify a small difference. One bit of difference in a head loss can change a flow in the fifth digit. So the port must do the same floating point operations as the C code, in the same order.

- A power or a logarithm calls the C library through `cpow` and `clog` in `cmath.mojo`. The `**` operator of Mojo can differ from `pow` in the last bits.
- A product is `mul(a, b)`. This stops the compiler from joining a product and a sum into one fused operation. The C build of EPANET does not join them.
- A formula keeps the grouping of the C code. For example, `PI*SQR(d)/4` is `PI * (d * d) / 4`, not `PI * d * d / 4`.
- The arrays start at index 1, as in the C code. A list that the C code builds by putting each new item first is read in reverse.

## Differences from EPANET

The port gives the same results as EPANET 2.3.6. It differs only where EPANET reads memory that it does not own.

- EPANET 2.3.6 reads past the end of two kinds of `[SOURCES]` line. One has an unknown source type, such as `J1 BRIGHT 1`. One has no strength, such as `J1 CONCEN`. The port gives error 213 for the first line and error 202 for the second.
- The ordering routine `genmmd` of EPANET can eliminate many nodes in one round. EPANET always calls it with one node in each round. The port has only that case, and so it does not have the tests that only many nodes in one round need. The docstring of `genmmd.mojo` gives the proof that each test it leaves out is always false.

## Validation

Each row is a test suite. Each reference comes from the real EPANET 2.3.6, built from commit `57d8bd8a`.

| Suite | Reference | Agreement |
|---|---|---|
| `tests/test_epanet_reference.mojo` | Net1, Net2 and Net3 of EPANET, and four more networks: valves, pumps, pressure driven demands with leaks and emitters, and tank mixing. Heads, demands, pressures, flows, statuses, settings, energy and quality at each step, from `assets/epanet/make_epanet.py`. | Ten significant digits |
| `tests/test_epanet_cases.mojo` | 540 small input files in `assets/epanet/cases.txt`. Each option, each form of each section, each input error, and each path of the solvers. Some run the hydraulics and the quality together. From `assets/epanet/make_epanet_cases.py`. | The same error codes for the same lines, and ten significant digits for each result |
| `tests/test_epanet_units.mojo` | Single functions of the C solver, on states that an input file cannot easily make. Examples are a valve at a node with no other path, a leak that has not converged and a demand that does not match its pressure. From `assets/epanet/make_epanet_units.py` and `epanet_units.c`. | Each bit |
| `tests/test_epanet_genmmd.mojo` | The ordering of the C routine `genmmd` on 291 graphs: paths, stars, grids, cubes, trees, random graphs and graphs in parts. From `assets/epanet/make_epanet_genmmd.py`. | Each value |
| `tests/test_epanet.mojo` | The order of the toolkit calls, and their errors | The EPANET error codes |

The references come from EPANET on Linux x86-64 with the GNU C library. The port calls the C library for `pow` and `log`, as EPANET does. On another platform the C library can round one of them differently in the last bit. A case whose links change status can amplify that.

On macOS one case moves by 4.4e-7 of a value. So on a platform other than Linux x86-64, the whole-run suites allow 1e-6 of a value. EPANET itself stops at a relative flow change of 1e-3.

To make a reference again, build EPANET as the docstring of `make_epanet.py` says. Then run the script that the suite names.

## References

- Rossman, Woo, Tryby, Shang, Janke and Haxton, "EPANET 2.2 User Manual", EPA/600/R-20/133, US Environmental Protection Agency, 2020.
- Todini and Pilati, "A gradient algorithm for the analysis of pipe networks", in "Computer Applications in Water Supply", volume 1, 1988.
- George and Liu, "The evolution of the minimum degree ordering algorithm", SIAM Review, 1989.
- OWA EPANET 2.3.6, <https://github.com/OpenWaterAnalytics/EPANET>.
