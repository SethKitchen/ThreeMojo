# Coverage tool

`coverage/`. A source-to-source instrumenter and a report that measure line, branch, condition and MC/DC coverage. Mojo 1.0 ships no coverage tool, and the toolchain has no `llvm-cov` to build one on.

This is original work with no three.js lineage.

## How it works

1. `build_cli.mojo` rewrites every covered module into `coverage/build/`, with a probe before each statement and around each decision. It writes a manifest of everything the probes can report.
2. The test suites run with `-I coverage/build -I .`, so imports resolve to the instrumented copies. Each probe writes one record to `stderr`. `stdout` is unchanged.
3. `report_cli.mojo` groups the records, matches them to the manifest, and prints the table. It exits with an error when anything is uncovered.

`make coverage` runs all three. See [How to measure coverage](How-to-measure-coverage).

## Modules

| Module | Job |
|---|---|
| `scanner.mojo` | Find statements, decisions and loop headers in a source file. |
| `instrument.mojo` | Emit the probes. Split `and` and `or` conditions. |
| `runtime.mojo` | The probe functions the instrumented code calls. |
| `mcdc.mojo` | Reconstruct decision vectors from the ordered record stream. |
| `report.mojo` | Build the report and decide whether it is complete. |
| `build_cli.mojo`, `report_cli.mojo` | The two commands the Makefile runs. |

## Metrics

| Metric | Question |
|---|---|
| Line | Did this statement run? |
| Branch | Did this decision go both ways? A `for` loop counts, including running zero times. |
| Condition | Did each `and` or `or` operand take both values? |
| MC/DC | Did each operand change the outcome on its own? |

MC/DC is the masking variant. Short-circuit evaluation makes unique-cause MC/DC unreachable for most compound decisions.

## Rules

- The Makefile's `COVERED` list is every CPU module. `COVERAGE_EXCLUDE` names `render/gpu.mojo`, because a kernel has no `stderr`.
- `# pragma: no branch` opts one decision out. Use it only when the other outcome is provably unreachable.
- Probes cannot reach compile-time code, and the instrumenter recognizes `def` and `async def` only.
- The tool does not measure itself.

## Limits

Two threads reporting one decision at once would interleave their records. The renderer therefore defaults to one worker, and the coverage run uses it.

A `Bool` loop flag read after nested loops hangs the Mojo compiler. The instrumenter emits an `Int` counter instead. See [The Mojo compiler hang](The-Mojo-compiler-hang).
