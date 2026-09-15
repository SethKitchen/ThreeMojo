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

## Process

- Every feature has a GitHub issue and a line in the README checklist. Tick the box, link the wiki page, and close the issue in the same change.
- Build and test inside a Linux environment. Mojo has no native Windows build.
- Do not edit the wiki in the browser. Edit `docs/wiki/` and let the CI workflow publish it.
