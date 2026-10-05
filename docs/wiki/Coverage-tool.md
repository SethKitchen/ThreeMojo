# Coverage tool

`coverage/`. A source-to-source instrumenter and a report that measure line, branch, condition and MC/DC coverage. Mojo ships no coverage tool, and the toolchain has no `llvm-cov` to build one on.

This is original work with no three.js lineage.

## How it works

1. `build_cli.mojo` rewrites every covered module into `coverage/build/`, with a probe before each statement and around each decision. It writes a manifest of everything the probes can report.
2. The coverage tool and the suites are copied into `coverage/build/` as well, and the suites run from there. Each probe writes a hit or complete evaluation record to `stderr`. `stdout` is unchanged.
3. `report_cli.mojo` groups the records, matches them to the manifest, and prints the table. It exits with an error when anything is uncovered.

`make coverage` runs all three. See [How to measure coverage](How-to-measure-coverage).

### Why the run happens inside the build tree

Mojo 1.1 resolves a module beside the file being compiled before it looks at any `-I` path. A suite run from the repository root therefore imports the *real* library, whatever the search path says.

The suites used to run with `-I coverage/build -I .` and the first `-I` decided. Under 1.1 that arrangement measured nothing at all and reported a clean zero, which is the worst way for a coverage tool to fail. Copying the suites in makes the instrumented copies the ones beside them.

The repository coverage run copies the tool without instrumentation. Separate diagnostic runs can instrument the tool, but those results cannot independently validate the instrumenter.

## Modules

| Module | Job |
|---|---|
| `scanner.mojo` | Find statements, decisions and loop headers in a source file. |
| `instrument.mojo` | Emit probes around Boolean leaves and decisions. |
| `runtime.mojo` | The probe functions the instrumented code calls. |
| `mcdc.mojo` | Read complete decision vectors from version 2 records. |
| `report.mojo` | Build the report and decide whether it is complete. |
| `build_cli.mojo`, `report_cli.mojo` | The two commands the Makefile runs. |

## Metrics

| Metric | Question |
|---|---|
| Line | Did this statement run? |
| Branch | Did this decision go both ways? A `for` loop counts, including running zero times. |
| Condition | Did each Boolean leaf of a compound decision take both values? |
| MC/DC | Did each operand change the outcome on its own? |

MC/DC is the masking variant. Short-circuit evaluation makes unique-cause MC/DC unreachable for most compound decisions.

### Grouped conditions

The instrumenter preserves `and`, `or`, `not` and their parentheses. It wraps each Boolean leaf of a compound decision once. The leaf indexes follow source order. A skipped leaf emits no record. A `not` operator stays outside its leaf probe, so the probe records the value before negation.

Redundant parentheses and multiline headers do not remove leaf obligations. Calls, indexing, comparisons and conditional expressions remain atomic leaves. The tool does not split logical expressions inside call arguments, indexes or comparison operands. Those expressions supply values to a leaf. A decision with one leaf uses its decision probe without duplicate condition probes.

Before [issue #535](https://github.com/SethKitchen/ThreeMojo/issues/535), the instrumenter split only top-level `and` and `or` operators. An outer group could therefore report both decision outcomes with no leaf-condition or MC/DC records. Historical 100% reports described the old manifest. They did not establish coverage of these hidden leaves.

The baseline audit at `b0222cbcb0c111bfe78cf330d79b757864b40e9f` covered 759 CPU modules. Group recognition increases the condition count from 5760 to 7438. It adds 1678 MC/DC obligations across 609 decisions in 207 modules.

Quote-aware scanning also reveals code after multiline shader strings. The line count rises from 122629 to 122792. The decision count rises from 22221 to 22236. No old manifest entry is removed. These are manifest counts, not passing coverage results. The new obligations need fresh captures from the complete suite set.

`make test-coverage-tool` compares native and rewritten Mojo fixtures. It checks leaf manifests, short-circuit order, call counts, exceptions, and raw and reduced traces. It also verifies that both decision outcomes can pass while leaf coverage fails. It also checks recursion, abandoned evaluations, nested callbacks, repeated loop and `elif` decisions, and concurrent tasks.

## Report columns

The text report separates each field with at least one space. Long module
names and large counts cannot touch the next field. Short fields keep their
padding. Percentages and measured totals do not change.

Do not read the table by fixed character positions. Tools can use the manifest
and probe formats described on this page when they need structured records.

## Rules

- The Makefile's `COVERED` list is every CPU module. `COVERAGE_EXCLUDE` names the GPU modules, `render/gpu.mojo` and `render/gpu_vxgi.mojo`, because a kernel has no `stderr`.
- `# pragma: no branch` opts one decision out. Use it only when the other outcome is provably unreachable.
- Probes cannot reach compile-time code, and the instrumenter recognizes `def` and `async def` only.
- The tool does not measure itself.

## Limits

Coverage must reach 100% under the measured rules. A badge states this requirement. It does not prove that a revision passed its checks.

Executable trait defaults are measured. Abstract `...` declarations and docstrings are not runtime steps. See [trait defaults and generated names](#trait-defaults-and-generated-names).

Version 2 fixes the ambiguous evaluation boundaries tracked in [issue #385](https://github.com/SethKitchen/ThreeMojo/issues/385). Its supported limits are below. These targeted checks do not establish full repository coverage. The leaf obligations added by issue #535 still require a new complete repository capture. Check the source, test scope and trace limits with each result. A percentage is not an engineering validation certificate.

### Truth-conversion limit

Simple decisions accept any `Boolable` value. Their helper borrows the value and calls `__bool__` exactly once. Compound operands support `Bool`, `SIMD[DType.bool, 1]`, `Int`, `String`, `Optional[T]` and `List[T]`. Their pinned standard-library truth tests read only the value, presence flag or length. The element type does not supply their truth test.

Custom `Boolable` operands in compound decisions fail compilation with a coverage diagnostic. Mojo can test a selected custom operand twice when both logical operands have the same type. Converting that operand to `Bool` early can change side effects or the decision. A borrowing wrapper also changes type identity through its origin parameters. The tool must reject this case until it can preserve the native conversions. Do not omit the source or its obligations to bypass this limit.

[Issue #556](https://github.com/SethKitchen/ThreeMojo/issues/556) fixes standard-library truth conversion. Native and instrumented checks cover optional, string, list and integer operands, including throwing operand expressions and short-circuit order. A move-only custom operand verifies simple-decision borrowing and conversion side effects. Stable and changing custom truth tests verify the explicit compound rejection.

Destructor-order controls compare retained and temporary optional/list values with move-only elements. Shared drop-state observations cover later operands, grouped same-type and mixed-type decisions, and the final body. [Issue #560](https://github.com/SethKitchen/ThreeMojo/issues/560) tracks general custom compound semantics and lifetimes.

### Evaluation protocol

Each function invocation that has a compound decision owns one private operand buffer. Other functions have no buffer. The new buffer and helper names use a prefix absent from the source. The buffer factory also avoids unqualified caller-scope `List` and `Int` names.

A begin operation clears the buffer before each reached `if`, `elif` or `while` evaluation. It does not change the original operand order or short-circuit behavior. Each completed leaf writes its condition hit. The runtime accepts standard-library truth-testable operands without requiring implicit argument conversion. All hit records use `COVLINE`, including payloads with a condition index and a `T` or `F` outcome.

A completed decision writes its outcome hit and one `COVEVAL2:<decision>:<T|F>:<vector>;` record. Each vector character is `T`, `F` or `-` for an unevaluated leaf. The record ends with a newline.

Recursive calls and concurrent calls have separate local buffers. An exception before completion writes no evaluation record. The observed condition hits remain available. A later begin clears any abandoned operands.

A nested call that catches an exception cannot overwrite its caller's buffer. Normal function lifetime releases the buffer. The parser and reducer do not reconstruct vectors from pending condition records.

Each record uses one successful POSIX `write` call. The complete UTF-8 record, including its terminator and newline, must fit in 512 bytes. [POSIX write](https://pubs.opengroup.org/onlinepubs/9690949599/functions/write.html) guarantees atomic pipe records through `PIPE_BUF`. The [portable minimum](https://man7.org/linux/man-pages/man7/pipe.7.html) is 512 bytes. Concurrent probe writers cannot split a record.

Module IDs must fit in 480 UTF-8 bytes. This reserves enough bytes for line numbers and outcome suffixes. The instrumenter refuses an oversized module ID or decision vector. It does not remove the obligation.

A `write` interrupted before any byte is sent returns `-1` with `EINTR`. The runtime retries the complete record only for that result. It terminates on an oversized record, any other error, or a short write, including a zero-byte write. The parser rejects incomplete vector records. These checks prevent a partial capture from passing as a shorter complete vector.

The runtime uses the C library already used by the project. The pinned private `std.sys._libc_errno` adapter reads thread-local `errno` through `__errno_location` on Linux and `__error` on macOS. The native protocol checks inject repeated `EINTR` and other write results, and interrupt a blocked pipe with a real signal. It requires no helper library, global counter, thread-local key or new access permission. Linux x86-64 tests exercise overlapping task calls and concurrent 512-byte records through actual pipes. macOS and Linux aarch64 use the same POSIX guarantee, but require their own native execution checks.

All generated helper aliases and local names now avoid source identifiers. See [trait defaults and generated names](#trait-defaults-and-generated-names).

Old `COVBRANCH` condition records cannot distinguish recursion from an abandoned evaluation. The parser and reducer reject these ambiguous compound records and require a new capture. Old decision-only records remain readable, without condition evidence. `COVLINE` condition hits remain readable, but do not certify MC/DC on their own.

### Trait defaults and generated names

Trait scopes can contain abstract declarations and executable default methods. The scanner skips an abstract `...` body, including a trailing comment. It measures statements in a default method and preserves its docstring. Each invocation with compound decisions receives its own buffer. Nested functions have separate buffers, as they do outside traits.

The complete 759-module CPU manifest comparison against `e488e4ffc23cf85d006d5a5d111968de64f6cacb` adds 16 line obligations. Eleven are `NodeSource` default returns in `materials/nodes.mojo`. Five are `RenderHooks` default `pass` statements in `renderers/renderer.mojo`. No previous entry is removed.

No branch, condition or MC/DC obligation changes in these production sources. The line total is now 122808. These manifest counts do not certify full repository coverage.

The instrumenter checks the full source text before it chooses any injected name. Hit and branch aliases, evaluation helper and buffer names, and loop-counter prefixes must be absent from that text. A collision adds underscores until the name is unused. This includes names in nested functions, parameters and generic callbacks. A loop counter also includes its original source line number.

These names do not change probe IDs or manifest entries. The imported buffer factory avoids caller-scope `List` and `Int` names.

`make test-coverage-tool` checks exact inherited-default line, branch, condition and MC/DC entries. It also checks native versus instrumented output, full default-method probe streams, recursive defaults, exceptions, nested callbacks and collisions with loop line numbers. `tests/test_trait_defaults.mojo` calls all eleven defaults through `ProgramSource` and checks inherited values through the node interpreter. The render-hook suite checks sun and point-light shadows with inherited `NoHooks` defaults.

### Loop body indentation

The loop rewrite uses the actual indentation of the first body statement. Blank lines and comments do not set that indentation. Multiline headers and literals retain their original probe line IDs.

Physical lines can end with LF, CRLF or CR. The rewrite keeps literal line-ending bytes and tabs. A missing final newline does not change source identities. This fixes [issue #544](https://github.com/SethKitchen/ThreeMojo/issues/544).

A loop entry probe reports a nonempty sequence before a body can return or raise. For a loop with an `else` clause, the final probe runs at the start of that clause. This preserves the empty outcome when the clause returns or raises. A `break` skips the clause; the entry probe has already reported the nonempty outcome.

The instrumenter rejects inline loop and loop-else bodies. Put each body on a separate indented line. It also rejects a complete loop header without an indented body.

`make test-coverage-tool` compares native and instrumented loops at widths of one, two, three, four and eight spaces, and with mixed block widths. The checks pin line and branch identities and exact loop outcomes. They cover comments, multiline headers and literals, nested loops, `break`, `continue`, `return`, `for`-`else` and exceptions. An `else` header can have spaces or tabs before its colon. This correction leaves the rewrites and manifests of the 761 measured repository modules byte-identical.

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

The Makefile reduces each suite's stderr as it arrives, and compresses what is left. The report reads two things: the set of distinct probe payloads, and each decision's distinct MC/DC evaluations. A probe in a loop repeats both millions of times. `tools/coverage_io.py`'s `Reducer` keeps each payload once, as a `COVLINE:` record, and each distinct complete `COVEVAL2` record once.

The report receives evaluations in first-completion order. The reducer has no pending evaluation state. Its storage depends on distinct hits and vectors, not the number of repeated or abandoned evaluations.

`test_rasterizer` writes 9.9 million records. The reduced capture holds 3,477 lines, and the report reads it in 0.02 s instead of 8 s, with an identical result. The reduction runs on the capture runners, in parallel, and the report reads the captures on one core.

The reporter reads the captures through named pipes, one suite at a time. Other output from a suite passes through unchanged, for the summary of a failed suite.

## Capture scheduling and progress

CPU test groups use imported source size. Coverage groups use `tools/coverage_shard.py` and `tools/coverage_costs.json`. Probe output can take much longer than compilation. The scheduler puts the longest estimated capture in the group with the lowest total cost. Each group starts its longest captures first.

Ties use the suite path and group number. Every affected suite stays in exactly one group. CI uses eight groups and a budget of 9000 seconds a group. The budget is a hang detector, not a target. Hosted runners differ: one took a quarter longer than another on the same group.

The current profile uses [CI run 37256337159](https://github.com/SethKitchen/ThreeMojo/actions/runs/37256337159), from October 5, 2026. Its source commit is `0fb66c60b1cb657be67c92a8284bf503aa38d3ed`. It used Mojo `1.1.0` (`8189361e`) and four capture workers per runner. Each cost is the elapsed time on the capture's completion line.

That run used a budget of 6000 seconds, which stopped the captures still in progress. Each of these has 1.25 times its elapsed time, and at least its earlier figure. A suite that was not in that run keeps its figure from the first profile.

The first profile used [CI run 36903778725](https://github.com/SethKitchen/ThreeMojo/actions/runs/36903778725), from October 1, 2026. Its costs are estimates from artifact completion times, at two-second precision.

A new suite gets a source-size estimate. The scheduler uses the median measured seconds per imported byte among the selected known suites. If none are known, it uses one second per 10000 bytes. The estimate is at least one second.

Missing profile entries never remove a suite. Invalid costs fail the scheduling command. Timing data changes only placement and order, never coverage requirements or test validation.

Each capture prints its start, first probe, elapsed time and exit status. A running capture prints progress once per minute. Before the first probe, compilation or startup can still be in progress. Once probes arrive, the log identifies runtime work and gives the record count.

Output is flushed at each update. Failed CI captures upload separate diagnostic artifacts. The report job does not use those artifacts as completed captures.

Refresh the profile when completed capture logs show material changes. Use the per-suite completion times from those logs. Keep the source run, commit, compiler and worker count with the profile. A simulation from the initial estimates gives a longest group of 4554 seconds with longest-first scheduling. This is an estimate, not a guarantee for another runner.
