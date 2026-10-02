# Coverage tool

`coverage/`. A source-to-source instrumenter and a report that measure line, branch, condition and MC/DC coverage. Mojo ships no coverage tool, and the toolchain has no `llvm-cov` to build one on.

This is original work with no three.js lineage.

## How it works

1. `build_cli.mojo` rewrites every covered module into `coverage/build/`, with a probe before each statement and around each decision. It writes a manifest of everything the probes can report.
2. The coverage tool and the suites are copied into `coverage/build/` as well, and the suites run from there. Each probe writes one record to `stderr`. `stdout` is unchanged.
3. `report_cli.mojo` groups the records, matches them to the manifest, and prints the table. It exits with an error when anything is uncovered.

`make coverage` runs all three. See [How to measure coverage](How-to-measure-coverage).

### Why the run happens inside the build tree

Mojo 1.1 resolves a module beside the file being compiled before it looks at any `-I` path. A suite run from the repository root therefore imports the *real* library, whatever the search path says.

The suites used to run with `-I coverage/build -I .` and the first `-I` decided. Under 1.1 that arrangement measured nothing at all and reported a clean zero, which is the worst way for a coverage tool to fail. Copying the suites in makes the instrumented copies the ones beside them.

The copies of the tool itself are never instrumented. Measuring the tool with the tool is still not attempted.

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

- The Makefile's `COVERED` list is every CPU module. `COVERAGE_EXCLUDE` names the GPU modules, `render/gpu.mojo` and `render/gpu_vxgi.mojo`, because a kernel has no `stderr`.
- `# pragma: no branch` opts one decision out. Use it only when the other outcome is provably unreachable.
- Probes cannot reach compile-time code, and the instrumenter recognizes `def` and `async def` only.
- The tool does not measure itself.

## Limits

Coverage must reach 100% under the measured rules. A badge states this requirement. It does not prove that a revision passed its checks.

The current trace protocol can lose an outer operand when a recursive call reports the same decision. Two threads that report the same decision can also interleave their records. A single-worker test avoids that thread conflict, but does not fix recursion. [Issue #385](https://github.com/SethKitchen/ThreeMojo/issues/385) tracks the protocol work and its tests.

Until that work is complete and validated, a reported percentage is not a general proof of MC/DC correctness. Check the source, test scope and trace limits with each result. It is not an engineering validation certificate.

### The capture grows with every statement run

Each statement that runs writes one record, so the capture grows with the work a suite does. A PMREM blur reads its source about half a million times, and each read ran about 150 statements. That made `test_pmrem` write 14 GB and run for six and a half minutes.

Keep the innermost helpers short for this reason:

- A small value type uses `@fieldwise_init`. Its constructor then has no body and writes no record. `FloatColor` and `Vector3` do this.
- A helper that runs per texel or per tap is one statement where the code stays clear. `Vector3.cross` and the `CLAMP` case of `wrap_index` are.
- Work that is the same for every texel is done once, outside the loop. The PMREM blur finds its weights, sines, cosines and copy position once per pass.

See [Benchmarks](Benchmarks#pmrem-and-the-coverage-run) for the numbers.

## Compiler hang

A `Bool` loop flag read after nested loops hangs the Mojo compiler. The instrumenter emits an `Int` counter instead. See [The Mojo compiler hang](The-Mojo-compiler-hang).

## Capture storage

The Makefile reduces each suite's stderr as it arrives, and compresses what is left. The report reads two things: the set of distinct probe payloads, and each decision's distinct MC/DC evaluations. A probe in a loop repeats both millions of times. `tools/coverage_io.py`'s `Reducer` keeps each payload once, as a `COVLINE:` record, and each distinct evaluation once, rebuilt from its pending conditions when its decision closes. The report receives the retained payloads and reconstructed evaluations in the order they first close. Reduction does not repair the trace limits above.

`test_rasterizer` writes 9.9 million records. The reduced capture holds 3,477 lines, and the report reads it in 0.02 s instead of 8 s, with an identical result. The reduction runs on the capture runners, in parallel, and the report reads the captures on one core.

The reporter reads the captures through named pipes, one suite at a time. Other output from a suite passes through unchanged, for the summary of a failed suite.

## Capture scheduling and progress

CPU test groups use imported source size. Coverage groups use `tools/coverage_shard.py` and `tools/coverage_costs.json`. Probe output can take much longer than compilation. The scheduler puts the longest estimated capture in the group with the lowest total cost. Each group starts its longest captures first.

Ties use the suite path and group number. Every affected suite stays in exactly one group. The six CI groups and the 6000-second budget are unchanged.

The first profile uses [CI run 36903778725](https://github.com/SethKitchen/ThreeMojo/actions/runs/36903778725), from October 1, 2026. Its source commit is `a8f0651a165ffcc64d1b541f35304fda5dfb2e39`. It used Mojo `1.1.0` (`8189361e`) and four capture workers per runner. These costs are estimates, not direct timers.

The artifact ZIP files record completion times with two-second precision. The original groups ran in path order. The first four suites started together. Each completion started the next suite. This reconstructs compile-and-run time. The initial start estimate uses the last affected-selection log, so those first four costs also include Make setup.

A new suite gets a source-size estimate. The scheduler uses the median measured seconds per imported byte among the selected known suites. If none are known, it uses one second per 10000 bytes. The estimate is at least one second.

Missing profile entries never remove a suite. Invalid costs fail the scheduling command. Timing data changes only placement and order, never coverage requirements or test validation.

Each capture prints its start, first probe, elapsed time and exit status. A running capture prints progress once per minute. Before the first probe, compilation or startup can still be in progress. Once probes arrive, the log identifies runtime work and gives the record count.

Output is flushed at each update. Failed CI captures upload separate diagnostic artifacts. The report job does not use those artifacts as completed captures.

Refresh the profile when completed capture logs show material changes. Use the per-suite completion times from those logs. Keep the source run, commit, compiler and worker count with the profile. A simulation from the initial estimates gives a longest group of 4554 seconds with longest-first scheduling. This is an estimate, not a guarantee for another runner.
