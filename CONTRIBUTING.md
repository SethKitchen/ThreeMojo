<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Contributing

Open an issue before you start a large change. The project ports three.js in a deliberate order, one feature at a time.

Every feature has one GitHub issue. The [README checklist](README.md#features) lists them. Pick an open one, or open a new one.

## Rules

- `make check` must pass before you commit.
- `make coverage` must stay at 100% for lines, branches, conditions and MC/DC.
- Each test must run in 5 seconds or less. `make test-cpu` fails a slower test. Make the code under test faster. Do not change the test.
- Every public symbol must have a docstring with `Args`, `Returns` and `Raises` sections.
- Every id, mode and kind must be a type, not a bare integer. Add a file to `tests/compile_fail/` that proves the compiler rejects the integer.
- Every value that a type can hold but the code does not accept must be refused at the boundary. Add a test that constructs the wrong value.
- Original content that is not a three.js port lives under `extensions/`.
- The CPU and GPU rasterizers must agree. Add a parity test to `tests/test_gpu.mojo` for any change that touches shading.
- Documentation must follow the [writing rules](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-write-documentation). `make docs-check` enforces the ones a tool can check.
- Everything is written in American English: `color`, `meter`, `center`, `gray`. That includes identifiers, docstrings and comments.

## Focused changes and checks

Keep each pull request focused on one correction. Use the affected test subset
for that change. Inspect the selection with `AFFECTED=<base-ref>` before a run.
Shared imports can still select the full suite. Do not drop selected tests or
weaken coverage checks to make a run smaller.

Avoid changes to the root Makefile, CI workflows, and shared build or coverage
tools for a feature correction. When a shared change is necessary, put it in a
separate infrastructure pull request. Explain why it is needed and which checks
it selects. Keep that exception rare.

## Upstream behavior and correctness

Keep the upstream API and behavior where they meet the documented contract.
A proven upstream defect can be corrected even when the result differs from
three.js or CARLA. Correctness takes priority over reproducing that defect.
A visual preference or a speed gain alone does not prove an upstream defect.

For each correction:

1. Name the pinned upstream version and give a reproducible counterexample.
2. Check the corrected result with an independent geometric, mathematical,
   or format reference. Keep the original test tolerances and workloads.
3. List the changed behavior in the module's differences section and its
   wiki page. State how it affects existing callers or scenario replay.
4. Keep tests for the corrected case and for ordinary upstream behavior.

Do not claim exact upstream output when a documented correction changes it.
A compatibility mode is a separate feature. It needs an explicit contract
and tests for both modes; do not add one merely to retain a known defect.

The Octree contact corrections and CARLA route and traffic-manager corrections
follow this rule. Their current APIs have no legacy-bug compatibility mode.
See [Octree](docs/wiki/Math-addons.md#octree),
[CARLA agents](docs/wiki/CARLA-agents.md#the-route-planner), and
[CARLA traffic manager](docs/wiki/CARLA-traffic-manager.md#differences-from-carla).

## Add a feature

1. Open an issue, or take an open one from the checklist.
2. Write the module. Keep three.js names where Mojo allows them.
3. Write the tests. Cover every branch and every condition.
4. Run `make check`.
5. Write or update the wiki page in `docs/wiki/`. Follow [How to add a feature](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-add-a-feature).
6. Tick the box in the README checklist and link it to the wiki page.
7. Commit. Close the issue in the commit message.

## Agent skills

`skills-lock.json` pins three Modular skills that teach an AI agent to write
Mojo. It is committed; the skills themselves are not, the same way a lockfile
is tracked and its packages are not. They are fetched with
[`skills`](https://skills.sh), which any agent can use.

Restore the pinned skills after a clone:

```bash
npx skills experimental_install
```

Bump them to the latest upstream, which rewrites the lockfile:

```bash
npx skills update -p -y
```

The skills land in `.agents/skills/` or `.claude/skills/`, both ignored by git.
Commit the lockfile when the hashes change, so everyone fetches the same
revision. `computedHash` is a SHA-256 over every file in the skill folder,
written by the tool. Do not edit it by hand.

## Commit messages

Write the first line as a statement of what the commit does, in fewer than 72 characters. Explain why in the body. Reference the issue.

## License

Your contribution is licensed on the same terms as the project, including the commercial licensing in [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md).

## Rendered gallery files

Run `make out/NAME.png` to render one example. Its prerequisites include its
imports and quoted assets. An unrelated extension does not rebuild the image.
Use `make -B out/NAME.png` after changing an external asset cache.

Each gallery target compresses its PNG or APNG after rendering. Compression
keeps the samples, frame timing and metadata. `make optimize-images` compresses
all tracked gallery PNG files without rendering them again.

New files in `out/` are ignored. To add a documentation image, review it,
compress it with `python3 tools/optimize_png.py out/NAME.png`, then use
`git add -f out/NAME.png`. Existing tracked images still update normally.
Compression does not remove old files from Git history.

## Temporary test files

Use `temporary_path` from `tests/test_scratch.mojo` for temporary fixtures.
The CPU test runner and coverage capture give each process a private directory.
They honor `TMPDIR` and remove that directory when the child exits.
The CPU runner also cleans up after a test timeout.
The helper rejects names that escape that directory.

Wrap each fixture-using suite's `main` body in `with TestScratch():`.
Import `TestScratch` beside `temporary_path` from `tests/test_scratch.mojo`.
A direct `mojo run` then creates one private root for the suite.
It honors `TMPDIR` and restores the environment on success or an exception.

Nested contexts borrow the same root. A runner-supplied root stays runner-owned.
A supplied root must be an absolute path to an existing directory.
Only a root created by the context is removed by it.

The context restores the environment before cleanup. A cleanup error propagates.
The pinned standard library refuses symbolic links during cleanup.
If cleanup fails, inspect and remove the remaining private directory.

Direct runs cannot clean up after a forced process termination.
Use the runner to enforce the five-second gate and clean up after a timeout.
For a directly built suite, use:

```sh
python3 tools/run_suite.py --seconds 5 --suite tests/test_face_model.mojo -- .cache/bin/test_face_model
```

Do not set `THREEMOJO_TEST_TMPDIR` yourself. Its active test scope or runner
owns that directory's lifetime. X11 socket paths remain system protocol paths, not test fixtures.
