# How to measure coverage

`make coverage` measures line, branch, condition and MC/DC coverage for every CPU module. It fails when anything is uncovered.

```bash
make coverage
```

Each suite compiles the instrumented library, and that compile is most of the time. The suites run together, one process for each core. The run needs a C compiler named `cc`.

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

The coverage tool does not measure itself.

## Run a suite under instrumentation by hand

When a suite fails only under instrumentation, run its copy in the build tree. A suite beside the real library imports that library, and the probes never run.

`mojo run` ignores a linker flag. Build the suite, then run the binary.

```bash
cc -c -O2 -o coverage/build/state.o coverage/state.c
.venv/bin/mojo build -I coverage/build \
  -Xlinker "$(pwd)/coverage/build/state.o" \
  -o /tmp/suite coverage/build/tests/test_renderer.mojo
/tmp/suite
```

See [Coverage tool](Coverage-tool) for how the instrumentation works.
