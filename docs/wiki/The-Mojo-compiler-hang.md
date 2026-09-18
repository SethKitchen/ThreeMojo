# The Mojo compiler hang

A `Bool` variable that is set to `True` inside a nested `for` loop and read after the loop hangs `mojo build`. The coverage instrumenter emits an `Int` counter instead. Two reproducers are in `docs/mojo-compiler-issue/`.

## Affects

Mojo 1.0.0 (`ed45d567`), installed with `uv pip install mojo`, on macOS 25.6 with an Apple M4 Max. Not yet checked on other platforms, and not re-checked on Mojo 1.1.0.

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

## Reproduce it

Two files, identical except for the flag type. Do not add `repro_bool.mojo` to any build target. Time-box it:

```bash
perl -e 'alarm 25; exec @ARGV' .venv/bin/mojo build -o /tmp/b docs/mojo-compiler-issue/repro_bool.mojo
echo "exit $?"     # 142 when SIGALRM killed it after 25 s
.venv/bin/mojo build -o /tmp/i docs/mojo-compiler-issue/repro_int.mojo   # about 1 s
```

## Upstream

The report belongs on [modular/modular](https://github.com/modular/modular/issues). A search of that tracker found no existing report of this pattern. The report text is the section above, with `repro_bool.mojo` and `repro_int.mojo` attached.
