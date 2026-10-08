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

Suites that write fixtures use one private temporary directory for each run.
They honor `TMPDIR` and remove their files on success or an exception.
The direct run does not enforce a timeout. Use `tools/run_suite.py` for that:

```bash
python3 tools/run_suite.py --seconds 5 --suite tests/test_face_model.mojo -- .cache/bin/test_face_model
```

The runner also removes the directory after a timeout.
Run `make test-portability` to check asset roots from another working directory
and temporary-file isolation across concurrent native processes.
`make check-cpu` includes this check.

## Run CPU mode controls

The Sum2 environment suite needs a host C compiler. `CC` selects it.
The C fixture changes only the test process controls and restores them after each case.
Production code does not change those controls.

`make test-cpu` and `make coverage` link this fixture automatically.
The same fixture inventory controls linking, cache inputs and instrumented copies.
A missing compiler or fixture fails the check. It does not skip the suite.

For a direct build and a timed run, use:

```bash
python3 tools/native_test_support.py run --root . \
  --suite tests/test_carla_sum2_environment.mojo --cache .cache/native -- \
  .venv/bin/mojo build -I . --Werror \
  -o .cache/sum2-environment tests/test_carla_sum2_environment.mojo
python3 tools/run_suite.py --seconds 5 \
  --suite tests/test_carla_sum2_environment.mojo -- .cache/sum2-environment
```

The fixture has separate x86-64 and AArch64 controls.
Linux x86-64 results do not qualify Apple Silicon execution.
Both supported CPU CI jobs run the ordinary suite.

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

The CI workflow checks a pull request with `AFFECTED` set to its base branch. It checks everything on a push to `main`. It runs the checks on Ubuntu and on a macOS runner with Apple Silicon.

## Verify generated fixtures

`python3 tools/fixture_manifest.py` checks the accepted hashes. It does not regenerate fixtures.

The VTK and sRGB generators have a verified runtime: Node 24.19.0, V8 13.6.233.17-node.51, Linux x64 and three 0.180.0. VTK also needs @xmldom/xmldom 0.9.12. The sRGB verifier supplies `--no-use-std-math-pow`; the default flag changes 30 Float64 words.

Install the locked dependencies with `npm ci --ignore-scripts --prefix tools/fixture-runtime`. Then run `python3 tools/fixture_runtime.py vtk` and `python3 tools/fixture_runtime.py js_number`. Both commands use temporary output directories and compare against accepted results. They do not replace the fixtures.

These pins reproduce the current baseline. They do not identify the original generation environment. The separate `assets/js_number/v8.json` snapshot remains unreproduced. See the [runtime evidence and limits](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/fixture-runtime-baselines.md).

## Regenerate negative diagnostics

Use `--update-expectations` only after you review a changed or new negative fixture.
Normal checks read the manifest without changing it.
CI never regenerates expectations.

1. Use the pinned Mojo `1.1.0` (`8189361e`) toolchain from [How to install](How-to-install).
2. Run these commands from the repository root.
3. Name each fixture you intend to update. Do not use a wildcard for an unrelated subset.

```bash
.venv/bin/mojo --version
python3 tools/compile_fail.py --compiler=.venv/bin/mojo --flags='-I . --Werror' \
  --update-expectations \
  tests/compile_fail/raw_float_is_not_an_angle.mojo \
  tests/compile_fail/sqrt_of_volume.mojo
git diff -- tools/compile_fail_expectations.json
```

The command first builds a valid control.
Each selected fixture must fail with source errors located in that fixture.
Crashes, missing imports, dependency errors, timeouts and successful negative builds stop the update.
The command writes nothing unless every selected result is valid.

The update keeps unselected records.
It sorts fixture keys, error locations and messages, and candidate notes.
It replaces the manifest atomically and prints the diff.
An unchanged result does not rewrite the file.
If the manifest changes during compilation, the command refuses to overwrite it.

Updates refuse a symbolic link as the manifest path. Read-only checks can follow symbolic links.

Review every changed error location, full message and candidate note before you commit.
Each rejection must still prove the intended type boundary.
A syntax error or changed candidate list can indicate a broken fixture.
Do not approve a diff only because it names the expected type.
Fix unintended changes before you repeat the command.

Run the selected fixtures again without the update flag:

```bash
python3 tools/compile_fail.py --compiler=.venv/bin/mojo --flags='-I . --Werror' \
  tests/compile_fail/raw_float_is_not_an_angle.mojo \
  tests/compile_fail/sqrt_of_volume.mojo
make -B compile-fail
```

Commit the reviewed manifest with its fixture or API change.
Do not add regeneration to CI, `make check`, or a failure-recovery command.

## Split the suites over machines

A suite's time is almost all compilation. So CI splits the suites over runners that work at the same time. Set `SHARD=i/n` to run group `i` of `n`:

```bash
make test-cpu SHARD=2/3
```

`tools/shard.py` makes the groups. It weighs each suite by the source that the suite imports, and it gives the heaviest suite to the lightest group first. Every machine computes the same groups. `SHARD` splits the suites only. The format check, lint, the compile-fail cases and the documentation check run whole, in one job.

Coverage splits into three steps. Each CI runner runs `coverage-instrument` and then `coverage-capture` for its group. One more runner runs `coverage-instrument`, collects the captures of every group in `coverage/build/hits/`, and runs `coverage-report`. The report fails if a suite of the whole list left no capture.

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
