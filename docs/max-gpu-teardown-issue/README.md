# A device-context teardown hang under CUDA, and the order this project uses

**Status:** worked around in `render/gpu.mojo` (`GpuRenderer.__del__`);
reproducer and a draft upstream report in this directory.

**Affects:** MAX 26.5.0 with Mojo 1.0.0 (`ed45d567`), installed with
`uv pip install "max==26.5.0"`, on WSL 2 (Ubuntu, kernel 6.18) over an NVIDIA
TITAN RTX with driver 591.86. Not reproduced on macOS / Metal, where the same
code has always passed.

## What happens

Destroy a `DeviceContext` while `DeviceBuffer`s it created are still alive,
then create a fresh `DeviceContext` and ask it for a buffer. The second
`enqueue_create_buffer` never returns. The process sits at zero CPU with the
GPU idle, and nothing times out.

Destroy the buffers first and the context afterwards, and the same sequence
works any number of times.

```mojo
var ctx = DeviceContext()
var buffer = ctx.enqueue_create_buffer[DType.uint8](256)
_ = ctx^          # context first: the next context's allocation hangs
_ = buffer^

var ctx = DeviceContext()
var buffer = ctx.enqueue_create_buffer[DType.uint8](256)
_ = buffer^       # buffers first: fine, repeatedly
_ = ctx^
```

Mojo destroys a struct's fields in declaration order. `GpuRenderer` declared
its context before its buffers, so every renderer tore its context down first,
and the *second* renderer created in a process hung in its constructor. The GPU
test suite builds one renderer per test, so on this machine the first test
passed and the second waited forever.

## How it was found

Five variants of the sequence, each capped at 45 seconds:

| sequence                                                        | result |
|-----------------------------------------------------------------|--------|
| renderer A drawn, renderer B created while A is still alive     | works  |
| renderer A drawn, synchronized, destroyed; then B               | hangs  |
| renderer A created but never drawn, destroyed; then B           | hangs  |
| two bare contexts, no buffers at all                            | works  |
| context + buffers, **buffers destroyed first**, twice           | works  |
| context + buffers, **context destroyed first**, twice           | hangs  |

Drawing, `map_to_host` and `synchronize` are all irrelevant; only the order of
the last two destructions matters.

## Reproducing it

`repro.mojo` alongside this file takes one argument, `buffers_first` or
`context_first`. Cap the second one:

```bash
timeout 45 .venv/bin/mojo run -I . docs/max-gpu-teardown-issue/repro.mojo buffers_first   # exit 0
timeout 45 .venv/bin/mojo run -I . docs/max-gpu-teardown-issue/repro.mojo context_first   # exit 124
```

`docs/` is outside every glob in the Makefile, so `make lint` and `make fmt`
never touch this file, and it is never built as part of `make check`.

## A second condition

With the order fixed, the suite got forty-one tests further and hung again,
after a test that had drawn into a renderer, never read the result back, and
let the renderer go. Waiting on the context in the destructor -- one
`synchronize()` before the buffers are released -- fixed that too, and the
suite has passed every run since. A minimal reproduction of the second
condition alone (draw, drop, create) did *not* hang, so its exact trigger is
narrower than that description; the wait is cheap and kept regardless.

## What this project does about it

`GpuRenderer.__deinit__` drains the queue, releases every buffer explicitly,
and releases the context last; the fields are declared in the same order so
the automatic destruction would agree even if the destructor were removed.
`make test-gpu` now runs under a time budget, `GPU_BUDGET`, so a hang of this
kind fails loudly instead of looking like a slow suite.

## Upstream

This should be filed against [modular/modular](https://github.com/modular/modular/issues)
with `repro.mojo` attached. Whether the fault is MAX's context refcounting or
the WSL 2 CUDA driver is not settled here; the reproducer is small enough to
tell them apart on a native Linux box.
