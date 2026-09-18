# How to run the checks

`make check` runs everything. Run it before every commit.

```bash
make check          # CPU and GPU halves
make check-cpu      # format, lint, tests, compile-fail cases, docs
make check-gpu      # the MAX backend, on a machine with a GPU
```

The full list of targets is in [Commands](Commands).

## Run one test suite

Mojo needs the repository root on its import path. `-I .` does that.

```bash
.venv/bin/mojo run -I . tests/test_vector3.mojo
```

Without `-I .` the compiler reports `unable to locate module 'math'`.

## Run one example

```bash
mkdir -p out
.venv/bin/mojo run -I . examples/cubes.mojo out/cubes.png
```

Every example takes the output path as its first argument.

## Force a task to run again

Results are cached on a hash of the source contents and the toolchain version. A task with unchanged inputs is skipped. Force it:

```bash
make -B check
```

`make ci` forces everything, which is what the CI workflow runs.

## Measure the examples

```bash
make bench-examples
```

This times every example against a three.js scene of the same size. See [How to measure examples](How-to-measure-examples) and [Benchmarks](Benchmarks).

## Check the documentation

```bash
make docs-check
```

The tool checks `README.md`, `CONTRIBUTING.md` and every page in `docs/wiki/`. See [How to write documentation](How-to-write-documentation) for the rules.

## Audit the docstrings

```bash
make docstrings
```

This demands `Args`, `Returns` and `Raises` sections on every public symbol. It is strict and not part of `make check`.
