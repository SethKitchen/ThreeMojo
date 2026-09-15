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
- Every public symbol must have a docstring with `Args`, `Returns` and `Raises` sections.
- Every id, mode and kind must be a type, not a bare integer. Add a file to `tests/compile_fail/` that proves the compiler rejects the integer.
- Every value that a type can hold but the code does not accept must be refused at the boundary. Add a test that constructs the wrong value.
- The CPU and GPU rasterizers must agree. Add a parity test to `tests/test_gpu.mojo` for any change that touches shading.
- Documentation must follow the [writing rules](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-write-documentation). `make docs-check` enforces the ones a tool can check.

## Add a feature

1. Open an issue, or take an open one from the checklist.
2. Write the module. Keep three.js names where Mojo allows them.
3. Write the tests. Cover every branch and every condition.
4. Run `make check`.
5. Write or update the wiki page in `docs/wiki/`. Follow [How to add a feature](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-add-a-feature).
6. Tick the box in the README checklist and link it to the wiki page.
7. Commit. Close the issue in the commit message.

## Commit messages

Write the first line as a statement of what the commit does, in fewer than 72 characters. Explain why in the body. Reference the issue.

## License

Your contribution is licensed on the same terms as the project, including the commercial licensing in [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md).
