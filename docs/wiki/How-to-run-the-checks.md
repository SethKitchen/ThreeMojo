# How to run the checks

`make check` runs everything. Run it before every commit.

```bash
make check          # CPU and GPU halves
make check-cpu      # format, lint, tests, compile-fail cases, docs
make check-gpu      # the MAX backend, on a machine with a GPU
make test-gpu-host  # the MAX backend's layout suites, with no GPU
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

`make ci` forces everything.

## Check only what a change affects

```bash
make check-cpu coverage AFFECTED=origin/main
```

This checks only what the change since the merge base with `origin/main` can reach, as nx's "affected" does. The change includes the files you have not committed. `tools/affected.py` reads the import graph. A suite, an example or a module is checked when it imports a changed module, directly or through other modules. A test that quotes the path of a changed asset is checked too. The format check reads the changed files only.

A change to one leaf module, for example a loader, checks one suite in about a minute. A change to a module that most of the library imports, for example `core/scene.mojo`, still checks about half the suites. A documentation change checks no suite. A change to the Makefile, the CI workflow, the coverage tool or a file that the script cannot place checks everything.

Coverage is exact for each module it measures, because every suite that can reach the module runs. A test change can lower the coverage of a module that the change does not reach. `AFFECTED` does not see that. The full run does.

The CI workflow checks a pull request with `AFFECTED` set to its base branch. It checks everything on a push to `main`.

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
