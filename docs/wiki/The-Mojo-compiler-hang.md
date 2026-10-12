# The Mojo compiler hang

A `Bool` variable that is set to `True` inside a nested `for` loop and read after the loop hangs `mojo build`. The coverage instrumenter emits an `Int` counter instead. Two reproducers are in `docs/mojo-compiler-issue/`.

## Affects

Mojo 1.0.0 (`ed45d567`), installed with `uv pip install mojo`, on macOS 25.6 with an Apple M4 Max. Not yet checked on other platforms, and not re-checked on Mojo 1.1.0.

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

## A deadlock in the compile-time interpreter on Mojo 1.1.0

A `startswith` call that the compile-time interpreter runs can deadlock `mojo build`. The compiler then uses no CPU and never exits. The coverage runtime no longer calls `startswith` at compile time. It compares a byte slice of the name with `==`.

### What happened

Each `and` and `or` in a compound decision gets a check, `node`, that runs at compile time. See [Truth-conversion limit](Coverage-tool#truth-conversion-limit). `node` called two helper functions, and they called `StaticString.startswith`.

The instrumented `loaders/collada.mojo` did not build. In the full CI audit on `c6bb3ce`, `test_collada` and `test_collada_rig` wrote 29 or 30 probe records at compile time, and then no more. Both captures ran until the capture deadline stopped them. Without instrumentation, both suites build and pass.

`gdb` showed every compiler thread in `sem_wait`. With `--num-threads 1` the one thread waits on a semaphore that no other thread can post. It is a deadlock, not slow code generation.

### How it was found

Each build had the other modules uninstrumented. A build that used no CPU for 90 seconds counted as a hang.

| Instrumented in `loaders/collada.mojo` | Build |
|---|---|
| Every function | Hangs |
| The first or the second half of the functions | Builds |
| Only `build_material` and `build_geometry` | Hangs |
| Those two, with plain branch probes in place of MC/DC in one of them | Builds |
| Those two, with `_cov_eval_truth[True]` in place of the `node` checks | Builds |
| Those two, with a `node` that compares reflected names with `==` only | Builds |
| Those two, with a `node` that calls `startswith` on constant names | Hangs |
| Those two, with a `node` that compares `name[byte=0:n]` with `==` | Builds |

The pair is not special. Many decisions in `build_material` hang with the one decision in `build_geometry`. A struct of `comptime` members that still calls `startswith` also hangs. Refactoring the loops of the two functions does not help.

### The rule

Code that runs at compile time in the coverage runtime must not call `startswith`. A `comptime` slice compared with `==` gives the same result. `_Operand` in `coverage/runtime.mojo` holds these checks.

## Reproduce it

Two files, identical except for the flag type. Do not add `repro_bool.mojo` to any build target. Time-box it:

```bash
perl -e 'alarm 25; exec @ARGV' .venv/bin/mojo build -o /tmp/b docs/mojo-compiler-issue/repro_bool.mojo
echo "exit $?"     # 142 when SIGALRM killed it after 25 s
.venv/bin/mojo build -o /tmp/i docs/mojo-compiler-issue/repro_int.mojo   # about 1 s
```

## Upstream

The report belongs on [modular/modular](https://github.com/modular/modular/issues). A search of that tracker found no existing report of this pattern. The report text is the section above, with `repro_bool.mojo` and `repro_int.mojo` attached.
