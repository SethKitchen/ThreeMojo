# ThreeMojo: rules for AI assistants and contributors

ThreeMojo ports three.js to Mojo. Read the [README](README.md) first and [CONTRIBUTING.md](CONTRIBUTING.md) second. The wiki source is `docs/wiki/`.

## Language

- Write American English everywhere: `color`, `meter`, `center`, `gray`, `-ize`. `make docs-check` flags British spellings in the documentation.
- Write documentation in Simplified Technical English (ASD-STE100). Short sentences, one instruction per sentence, active voice, "must" and "can". See [How to write documentation](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-write-documentation).
- Put the main point first, in every page and every section.
- Keep the Diátaxis types apart: a tutorial teaches, a how-to solves a task, a reference states, an explanation says why.

## Code

- `make check` must pass before a commit. `make coverage` must stay at 100%.
- Each test must run in 5 seconds or less (`TEST_TIMEOUT`). When a test is slower, make the library faster. Do not change the test.
- Every id, mode and kind is a type with `is_valid`. Every boundary that reads one checks it. Add a `tests/compile_fail/` file for each new type.
- Every quantity carries a unit type. A length is a `Length`, an angle is an `Angle`.
- The CPU and GPU rasterizers share their arithmetic and agree in the parity tests.
- Every public symbol has a docstring with `Args`, `Returns` and `Raises`.

## Toolchain

The pin is exact: Mojo `1.2.0` (`2016d0cd`), and MAX `26.7.0` for the GPU
half. It is a pin and not a floor, because one source cannot serve both 1.1
and 1.2: 1.1 cannot parse `__async`, and 1.2 has no `std.hashlib`. Several
things moved, and all are easy to write back the old way by habit:

- `TaskGroup` is `from std.runtime._asyncrt import TaskGroup`. The public
  `std.runtime` keeps only `parallelism_level` and `initialize_runtime`, and
  nothing public in `std` runs work on a thread pool. This is one of two places
  the project reaches past a leading underscore. 1.0 has no `_asyncrt`; 1.1
  and 1.2 have no `asyncrt`. Production modules import the adapter in
  `render/tasks.mojo`, which holds the private import.
- A task function is `__async def`, and an await is `__await`. 1.2 renamed
  the keywords to mark async as unstable. The bare `async def` still parses,
  but it warns, and `--Werror` makes that an error. The coverage tool, the
  scanner and `tools/coverage_loop_proofs.py` all read `__async def`.
- Coverage writes are the second narrow exception for a private import.
  `coverage/runtime.mojo` is the adapter boundary for `std.sys._libc_errno`.
  Keep this import inside that file in production code. It uses the pinned
  Mojo `1.2.0` accessor for thread-local `errno` on Linux and macOS.
  Retry only `-1` with `EINTR`. Short writes and other errors must still abort
  the capture. `tools/check_coverage_protocol.mojo` tests the accessor without
  an interposer, then tests repeated `EINTR`, real pipe interruptions, and
  failed, short, and zero writes on both platforms.
- `global_idx` is `from max.gpu import global_idx`. Much of `std.gpu` moved
  into the `max` package, and the compiler says so when it cannot find it.
- `Hasher` is `from std.hash import Hasher`. `std.hashlib` is gone.
- Pass a file descriptor to libc `read` and `write` as `Int32`, as in
  `external_call["write", Int](Int32(2), ...)`. The standard library declares
  these two functions with a 32-bit descriptor. A call with an `Int`
  descriptor compiles, and `mojo doc` accepts it. Then `mojo build` fails to
  lower the module with "existing function with conflicting signature". The
  compile-time interpreter is the exception: it accepts only an `Int`
  descriptor in `write`. Code that can run at compile time, such as the
  coverage probes, writes through `std.sys.stderr` there.
- `has_apple_gpu_accelerator()` and its two siblings are gone. Ask the target:
  `default_accelerator().is_apple_gpu()`, from `std.sys`.
- Do not write `x^` where the callee only reads its argument. 1.2 warns that
  the move has no effect, and `--Werror` makes that an error. Pass `x`.
- A module beside the file being compiled now beats any `-I` path. That is
  why `make coverage` copies the suites and the coverage tool into
  `coverage/build/` and runs them from there. Adding `-I` in front of the
  instrumented tree does *not* work any more: it measured nothing and
  reported a clean zero. See [Coverage tool](docs/wiki/Coverage-tool.md).

## Process

- Every feature has a GitHub issue and a line in the README checklist. Tick the box, link the wiki page, and close the issue in the same change.
- Keep each PR to the files its work needs. Hosted CI uses `tools/ci_scope.mojo` to select checks for changed inputs and their consumers. Inspect the selection before a run; do not drop selected checks. The legacy `AFFECTED` path uses `tools/affected.mojo`, where a changed test expands through its full imported-library closure. Shared inputs can still select every suite.
- Scoped coverage checks changed production modules and their affected production consumers at the full thresholds. Documentation changes select documentation checks. A manual CI run is the full audit. Scoped success does not establish global coverage of unchanged libraries.
- Update an existing branch from `main` for material or relevant changes, or to resolve conflicts. Do not refresh it after every unrelated minor change.
- Do not edit the `Makefile` for routine work. A new library module, test suite, helper library or gallery image needs no `Makefile` change. Helper libraries are `tests/_*.mojo` and `tools/_*.mojo`. The gallery is `examples/gallery.mk`. When routine work needs a `Makefile` edit, refactor that part first so the next change of the same kind does not.
- Do not edit shared build inputs unless the work cannot be done another way. The `Makefile`, shared build tools and unknown inputs select the full audit. CI routing and known Python tooling have scoped checks. Put an unavoidable shared change in its own PR, and group related changes together.
- Build and test inside a Linux environment. Mojo has no native Windows build.
- Do not edit the wiki in the browser. Edit `docs/wiki/` and let the CI workflow publish it.
- The agent skills in `skills-lock.json` are fetched with `npx skills experimental_install` and bumped with `npx skills update -p -y`. Never write `computedHash` by hand: the tool computes it over every file in the skill folder, and it has changed the way it computes it before.
