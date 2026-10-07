# How to measure coverage

`make coverage` measures line, branch, condition and MC/DC coverage for every CPU module. It fails when anything is uncovered.

```bash
make coverage
```

The run time depends on the selected suites and the amount of probe output.


## Choose the capture profile

`COV_PROFILE=raw` remains the local default. It uses Mojo `run`, except that
suites needing a native C fixture use a fresh build and execution so their
linker objects are effective. `COV_PROFILE=aot` builds every selected suite.
`COV_PROFILE=aot-hits` adds an exact hit cache to compiled Linux captures.
Hosted Linux coverage explicitly selects `aot-hits`; other jobs keep their
existing execution modes. The measured modules, suites, coverage obligations
and 9,000-second hosted group budget are unchanged.

```bash
make coverage-instrument
make coverage-capture COV_PROFILE=aot-hits COV_BUDGET=9000
make coverage-report
```

Compiled profiles preserve the source argument as `argv[0]`, trailing
arguments, working directory, environment and ordinary diagnostic streams.
The actual executable is a temporary binary, so executable-path inspection
and self-execution differ from the JIT. The wrapper supports the official
Mojo command shape. Use `raw` for programs requiring other run-only behavior.
A build failure stops that suite; compilation and execution share the original
capture deadline and process cleanup scope.

The Linux private profile reserves a blocking writer to the supervisor's
capture pipe. Runtime probes continue to that pipe if the program redirects
stderr; ordinary diagnostics follow stderr.

Each full static hit ID, including
condition index and true/false suffix, is cached only after a complete write.
The fixed 4,096-entry cache stores exact bytes. Collisions, eviction and
contention can add duplicate writes.

Every complete `COVEVAL2` record is still
written, including repeated vectors, and truth conversion and operand-buffer
updates still execute each time. A cached hit records an already delivered
fact and does not repeat an I/O operation or its possible error.

The private descriptor belongs exclusively to the helper. Programs must not
close or reuse arbitrary descriptors or bypass libc fork hooks with direct
fork/clone syscalls. Libc fork children close the inherited private writer and
use uncached stderr; exec closes the private writer. Each new supervised
process gets its own cache. Requested private initialization fails closed if
pipe identity, descriptor setup or fork-hook registration fails. This ownership
contract does not make arbitrary concurrent descriptor replacement safe.

Compiler-time probes retain their original raw write path. Start release
qualification with a new, empty compiler-cache directory. In every profile,
a warm compiler cache can reuse compile-time results without repeating their
side effects. Matched cold and warm controls test this distinction explicitly;
old captures must not be reused as evidence for a new source or cache scope.

`make test-tools` includes compiler-free command, object-linking and fault-driver
controls. `make test-coverage-tool` keeps all existing raw protocol checks and
adds native cold/warm phase, argv, complete-vector and Linux transport-fault
controls. The new native tests retain the five-second per-test limit.

The local pilot used published production source and full 908-module
instrumentation with an explicit x86-64-v3 target. Its 1,776.6-second capture
completed all 33 original `test_carla_render_scene` tests. The composed
FP-state fixture retained byte-identical cold evidence. A repeated-hit
microbenchmark improved, while a vector-dense control was about 20% slower.
These results support the profile's qualification; they are not a matched
hosted speedup or proof that every complete coverage group meets its budget.

## Read the report

```
render/rasterizer   lines 231/231 100%  branches 120/120 100%  mcdc 12/12 100%
core/scene          lines 67/67   100%  branches 68/68   100%  mcdc 16/16 100%
TOTAL               3446/3446 100%
```

An incomplete run lists what was missed:

```
core/scene   lines 67/67 100%   branches 67/68 98%   mcdc 15/16 93%
    line 257 condition 0: never evaluated True
```

The line number refers to the source file. Write a test that takes the missing branch, or makes the missing condition decide the outcome.

## Exclude a decision that cannot go both ways

A loop over a length that an invariant proves non-zero never runs zero times. Mark it, so the exclusion is visible in review:

```mojo
for y in range(self.height):  # pragma: no branch
```

Use the pragma only when the other outcome is provably unreachable.

## Raise the time budget

The Makefile gives the run one second per suite. A slower machine exceeds that budget without anything being wrong:

```bash
make coverage COV_BUDGET=300
```

The budget exists to catch a construct that sends the compiler superlinear. See [The Mojo compiler hang](The-Mojo-compiler-hang).

## What is not measured

`render/gpu.mojo` is excluded. Its probes would write to `stderr`, and a GPU kernel has none. The parity tests in `tests/test_gpu.mojo` cover it instead. The layout tests in `tests/test_gpu_layout.mojo` check its host side. They need MAX but no GPU, so CI runs them in a job of their own.

The repository coverage run does not measure the coverage tool itself.

Grouped and multiline decisions have leaf-condition and MC/DC obligations. A decision that takes both outcomes can still miss a leaf or its independence pair. Historical reports made before grouped-leaf instrumentation did not measure those hidden obligations. See [Coverage tool](Coverage-tool#grouped-conditions).

After an instrumenter change, regenerate the manifest and every capture. The content-based coverage cache includes the instrumenter source. An affected run selects all suites for a coverage-tool change. Do not combine old captures with a new manifest.

Run the native instrumentation regressions with `make test-coverage-tool`.

## Run a suite under instrumentation by hand

When a suite fails only under instrumentation, run it against the instrumented copies:

```bash
cd coverage/build
../../.venv/bin/mojo run -I . tests/test_renderer.mojo
```

See [Coverage tool](Coverage-tool) for how the instrumentation works.
