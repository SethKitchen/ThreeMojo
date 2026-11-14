# The Mojo compiler hang

A `Bool` variable that is set to `True` inside a nested `for` loop and read after the loop hangs `mojo build`. Mojo 1.0.0 and Mojo 1.1.0 hang, and Mojo 1.2.0 builds the file. The coverage instrumenter emits an `Int` counter instead. Two reproducers are in `docs/mojo-compiler-issue/`.

## Affects

Mojo 1.0.0 and Mojo 1.1.0 hang. Mojo 1.2.0, the pinned toolchain, does not. Each toolchain was installed with `uv pip install mojo`. Each build of `repro_bool.mojo` had a limit of 60 seconds.

| Toolchain | Platform | `repro_bool.mojo` | `repro_int.mojo` |
|---|---|---|---|
| 1.0.0 (`ed45d567`) | macOS 25.6, Apple M4 Max | Hangs | 1 s |
| 1.0.0 (`ed45d567`) | Linux, x86-64 | Hangs | 2 s |
| 1.1.0 (`8189361e`) | Linux, x86-64 | Hangs | 2 s |
| 1.2.0 (`2016d0cd`) | Linux, x86-64 | 2 s | 2 s |

The macOS row is the first report. The Linux rows are a later check of all three toolchains on one machine. Mojo 1.1.0 and Mojo 1.2.0 are not checked on macOS.

The `Int` counter stays in the coverage instrumenter and in the library. It is correct on every toolchain, and it costs nothing.

The two reproducers keep the spelling they were written in, `@no_inline` included. They are evidence of what one toolchain did, so modernizing them would make them evidence of something else. `coverage/runtime.mojo`, which is live code, uses the current `@inline(.never)`.

## What happens

Type-checking is unaffected. `mojo doc` completes in under a second on the hanging file. Codegen is what hangs.

```mojo
var ran = False                # hangs the compiler when nested
for i in range(n):
    ran = True
    ...
_ = observe("loop", ran)

var ran = 0                    # builds in about a second
for i in range(n):
    ran += 1
    ...
_ = observe("loop", ran > 0)
```

## Why this project hit it

The coverage tool reports whether a `for` loop ever ran zero times. It emitted exactly the first pattern: a flag raised in the body and read after the loop. Every module with nested loops then took minutes to build under instrumentation. For a while the Makefile carried a growing exclusion list and blamed "statement-dense arithmetic". That diagnosis was wrong.

## How it was found

Bisecting the instrumented `geometries/sphere.mojo` by removing one kind of emitted code at a time, with each build capped at 25 seconds:

| Removed from the instrumented file | Build |
|---|---|
| Nothing, the plain file | 1 s |
| Every line probe | Hangs |
| Every branch probe | 2 s |
| The loop flag machinery | 1 s |
| Only the per-iteration probe inside loops | Hangs |
| Only the after-loop read of the flag | 2 s |

Candidate fixes on the full instrumented file:

| Change | Build |
|---|---|
| `Bool` flag to `Int` counter | 2 s |
| Copy the flag to a fresh local before the read | Hangs |
| Track only the outermost loop of each nest | 2 s |

Two earlier hypotheses were wrong, and are recorded so nobody tests them again. `@no_inline` on the probe functions does not help. Passing `StaticString` instead of `String` does not help. Both changes were kept as improvements.

## A second pattern on Mojo 1.1.0

A struct value that is built again in two nested loops, and read after them, also hangs codegen. This was on Mojo 1.1.0 in WSL. `postprocessing/ssr_node.mojo` hit it: its box blur summed its taps into a `FloatColor`. The fix was to sum four `Float32` values and build the color after the loops. A copy of the function with four floats built in 7 seconds. The same function with the `FloatColor` did not build in 200 seconds.

Four nested loops in one function hang codegen too, as `render/target.mojo` notes. Keep at most two loops in a function, and call a function for the inner two.

These two patterns have no reproducer file. A short file for each one was built on Linux x86-64 with Mojo 1.1.0 and Mojo 1.2.0. The first file sums a four-float struct in two nested loops. The second file has four nested loops in one function. Each build took about 2 seconds. So the short files do not show the hang, and the two workarounds stay in the library.

## Reproduce it

Two files, identical except for the flag type. Use Mojo 1.0.0 or Mojo 1.1.0: Mojo 1.2.0 builds both files. Do not add `repro_bool.mojo` to any build target. Time-box it:

```bash
perl -e 'alarm 25; exec @ARGV' .venv/bin/mojo build -o /tmp/b docs/mojo-compiler-issue/repro_bool.mojo
echo "exit $?"     # 142 when SIGALRM killed it after 25 s
.venv/bin/mojo build -o /tmp/i docs/mojo-compiler-issue/repro_int.mojo   # about 1 s
```

## Upstream

The report belongs on [modular/modular](https://github.com/modular/modular/issues). A search of that tracker found no existing report of this pattern. The report text is the section above, with `repro_bool.mojo` and `repro_int.mojo` attached.
