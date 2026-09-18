# ThreeMojo: rules for AI assistants and contributors

ThreeMojo ports three.js to Mojo. Read the [README](README.md) first and [CONTRIBUTING.md](CONTRIBUTING.md) second. The wiki source is `docs/wiki/`.

## Language

- Write American English everywhere: `color`, `meter`, `center`, `gray`, `-ize`. `make docs-check` flags British spellings in the documentation.
- Write documentation in Simplified Technical English (ASD-STE100). Short sentences, one instruction per sentence, active voice, "must" and "can". See [How to write documentation](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-write-documentation).
- Put the main point first, in every page and every section.
- Keep the Diátaxis types apart: a tutorial teaches, a how-to solves a task, a reference states, an explanation says why.

## Code

- `make check` must pass before a commit. `make coverage` must stay at 100%.
- Every id, mode and kind is a type with `is_valid`. Every boundary that reads one checks it. Add a `tests/compile_fail/` file for each new type.
- Every quantity carries a unit type. A length is a `Length`, an angle is an `Angle`.
- The CPU and GPU rasterizers share their arithmetic and agree in the parity tests.
- Every public symbol has a docstring with `Args`, `Returns` and `Raises`.

## Toolchain

The pin is exact: Mojo `1.1.0` (`8189361e`), and MAX `26.6.0` for the GPU
half. It is a pin and not a floor, because one source cannot serve both 1.0
and 1.1. Three things moved, and all three are easy to write back the old
way by habit:

- `TaskGroup` is `from std.runtime._asyncrt import TaskGroup`. The public
  `std.runtime` keeps only `parallelism_level` and `initialize_runtime`, and
  nothing public in `std` runs work on a thread pool. This is the one place
  the project reaches past a leading underscore. 1.0 has no `_asyncrt`; 1.1
  has no `asyncrt`.
- `global_idx` is `from max.gpu import global_idx`. Much of `std.gpu` moved
  into the `max` package, and the compiler says so when it cannot find it.
- A module beside the file being compiled now beats any `-I` path. That is
  why `make coverage` copies the suites and the coverage tool into
  `coverage/build/` and runs them from there. Adding `-I` in front of the
  instrumented tree does *not* work any more: it measured nothing and
  reported a clean zero. See [Coverage tool](docs/wiki/Coverage-tool.md).

## Process

- Every feature has a GitHub issue and a line in the README checklist. Tick the box, link the wiki page, and close the issue in the same change.
- Build and test inside a Linux environment. Mojo has no native Windows build.
- Do not edit the wiki in the browser. Edit `docs/wiki/` and let the CI workflow publish it.
