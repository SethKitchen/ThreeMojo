# A Mojo compiler hang, and the workaround this project uses

**Status:** worked around in `coverage/instrument.mojo`; reproducer and draft
upstream report in this directory.

**Affects:** Mojo 1.0.0 (`ed45d567`), installed with `uv pip install mojo`,
on macOS 25.6 / Apple M4 Max. Not yet checked on other platforms.

## What happens

A `Bool` variable that is assigned the constant `True` inside a `for` loop
and then *read after the loop* makes `mojo build` take minutes — or never
finish — once the loops are nested. Type-checking is unaffected: `mojo doc`
completes in under a second on the same file. It is codegen that hangs.

Change the `Bool` to an `Int` counter (`+= 1` instead of `= True`, `> 0` at
the read) and the identical program builds in about a second.

```mojo
var ran = False                # hangs the compiler when nested
for i in range(n):
    ran = True
    ...
_ = observe("loop", ran)

var ran = 0                    # builds in ~1s
for i in range(n):
    ran += 1
    ...
_ = observe("loop", ran > 0)
```

## Why this project hit it

The coverage tool in `coverage/` rewrites sources to report which lines and
branches ran. To learn whether a `for` loop ever ran zero times, it emitted
exactly the pattern above: a flag raised in the body and read after the loop.

Any module with nested loops — the rasterizer, the renderer, `sphere`, the
PNG encoder, `Matrix4.multiply` — then took minutes to build under
instrumentation. For a while the Makefile carried a growing exclusion list
and a comment blaming "statement-dense arithmetic". That diagnosis was wrong.

## How it was found

Bisecting the instrumented `geometries/sphere.mojo` by removing one kind of
emitted code at a time, each build capped at 25 seconds:

| removed from the instrumented file          | build   |
|---------------------------------------------|---------|
| nothing (control: the *plain* file)         | 1s      |
| every line probe                            | hangs   |
| every branch probe                          | 2s      |
| the loop flag machinery                     | 1s      |
| only the per-iteration probe inside loops   | hangs   |
| **only the after-loop read of the flag**    | **2s**  |

Then, for candidate fixes on the full instrumented file:

| change                                          | build   |
|-------------------------------------------------|---------|
| `Bool` flag → `Int` counter                     | **2s**  |
| copy the flag to a fresh local before reading it| hangs   |
| track only the outermost loop of each nest      | 2s      |

Two earlier hypotheses were tested and were wrong, and are recorded so nobody
re-tests them: forbidding inlining of the probe functions (`@no_inline`) does
not help, and passing `StaticString` instead of `String` to avoid a heap
temporary per probe does not help. Both changes were kept because they are
improvements anyway, but neither is the fix.

## Reproducing it

Two files, identical except for the flag type. **Do not add `repro_bool.mojo`
to any build target** — it will hang the build. Time-box it:

```bash
# macOS ships no `timeout`; perl's alarm does the job.
perl -e 'alarm 25; exec @ARGV' .venv/bin/mojo build -o /tmp/b docs/mojo-compiler-issue/repro_bool.mojo
echo "exit $?"     # 142 = killed by SIGALRM after 25s

.venv/bin/mojo build -o /tmp/i docs/mojo-compiler-issue/repro_int.mojo   # ~1s
```

`docs/` is deliberately outside every glob in the Makefile, so `make lint`
and `make fmt` never touch these files.

## Upstream

`ISSUE.md` alongside this file is the report as it should be filed against
[modular/modular](https://github.com/modular/modular/issues). A search of that
tracker for existing reports of compiler hangs found nothing describing this
pattern.
