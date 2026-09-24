# Commands

Every `make` target, as `make help` lists them. Every command is the same on macOS, Linux and WSL.

| Command | What it does |
|---|---|
| `make help` | List the targets and the current input hash. |
| `make check` | Everything. Run it before you commit. |
| `make check-cpu` | Format check, lint, the CPU suites, the compile-fail cases and the documentation check. |
| `make check-gpu` | Lint and test the MAX backend. Needs a GPU. |
| `make test-gpu-host` | Run the MAX backend's layout suites. Needs MAX but no GPU. CI runs it. |
| `make ci` | `check`, ignoring the cache. |
| `make test` | Every `tests/test_*.mojo` suite. |
| `make lint` | Compile everything with warnings as errors. |
| `make fmt` | Reformat every source in place. |
| `make fmt-check` | Verify the formatting. Changes nothing. |
| `make coverage` | Line, branch, condition and MC/DC coverage. Fails on any gap. |
| `make compile-fail` | Assert that every file in `tests/compile_fail/` fails to compile. |
| `make docstrings` | Audit every public symbol for `Args`, `Returns` and `Raises`. Not part of `check`. |
| `make docs-check` | Check the documentation against the writing rules. |
| `make wiki-publish` | Copy `docs/wiki/` to the GitHub wiki. |
| `make example` | Render `out/triangle.png`. |
| `make animation` | Render every animated example into `out/`. |
| `make viewer` | Orbit a scene in this terminal with the mouse. |
| `make bench` | Time the CPU and GPU rasterizers across image sizes. |
| `make bench-scene` | Time each stage of the CPU renderer on a textured sphere. |
| `make bench-examples` | Time every example against three.js and, when present, Mojo 1.0. |
| `make clean` | Remove the coverage build and the task cache. Keeps `out/`. |
| `make clean-images` | Remove the rendered images in `out/`. |

## The cache

Results are cached on a SHA-256 of the source contents, the Makefile and the toolchain version. A task with unchanged inputs is skipped. `make -B <task>` forces one. `test-gpu` and `docs-check` are never cached.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `COV_BUDGET` | One second per suite | Seconds the coverage run gets before it is killed. |
| `GPU_BUDGET` | 300 | Seconds the GPU suite gets. |
| `JOBS` | The core count | Suites run in parallel. |
