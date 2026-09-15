# The CUDA teardown hang

A `DeviceContext` destroyed before its buffers hangs the next context's first allocation, under MAX 26.5.0 on CUDA. `GpuRenderer.__deinit__` releases its buffers first, and the GPU suite runs under a time budget. A reproducer is in `docs/max-gpu-teardown-issue/repro.mojo`.

## Affects

MAX 26.5.0 with Mojo 1.0.0 (`ed45d567`), on WSL 2 Ubuntu over an NVIDIA TITAN RTX with driver 591.86. Not reproduced on macOS with Metal.

## What happens

Destroy a `DeviceContext` while `DeviceBuffer`s it created are alive. Then create a fresh context and ask it for a buffer. The second `enqueue_create_buffer` never returns. The process sits at zero CPU with the GPU idle, and nothing times out.

Destroy the buffers first and the context afterwards, and the same sequence works any number of times.

```mojo
var ctx = DeviceContext()
var buffer = ctx.enqueue_create_buffer[DType.uint8](256)
_ = ctx^          # context first: the next context's allocation hangs
_ = buffer^
```

Mojo destroys a struct's fields in declaration order. `GpuRenderer` declared its context before its buffers, so every renderer tore its context down first. The second renderer in a process hung in its constructor. The suite builds one renderer per test, so the first test passed and the second waited forever.

## How it was found

Five variants, each capped at 45 seconds:

| Sequence | Result |
|---|---|
| Renderer A drawn, B created while A is alive | Works |
| Renderer A drawn, synchronized, destroyed, then B | Hangs |
| Renderer A created but never drawn, destroyed, then B | Hangs |
| Two bare contexts, no buffers | Works |
| Context and buffers, buffers destroyed first, twice | Works |
| Context and buffers, context destroyed first, twice | Hangs |

Drawing, `map_to_host` and `synchronize` are irrelevant. Only the order of the last two destructions matters.

## A second condition

With the order fixed, the suite got forty-one tests further and hung again, after a test that drew, never read back, and dropped its renderer. One `synchronize()` in the destructor, before the buffers are released, fixed that too. A minimal reproduction of the second condition alone did not hang, so its trigger is narrower than the description. The wait is cheap and kept.

## Reproduce it

```bash
timeout 45 .venv/bin/mojo run -I . docs/max-gpu-teardown-issue/repro.mojo buffers_first   # exit 0
timeout 45 .venv/bin/mojo run -I . docs/max-gpu-teardown-issue/repro.mojo context_first   # exit 124
```

`docs/` is outside every Makefile glob. The reproducer is never built by `make check`.

## What the project does

- `GpuRenderer` declares its context last and releases it last.
- `__deinit__` waits for the queue, releases every buffer, and then releases the context.
- `make test-gpu` runs under `GPU_BUDGET`, 300 seconds by default, so a hang fails instead of looking slow.
- `set_textures` waits for the queue before it releases the buffers it replaces. Replacing a resource and tearing the renderer down are two different lifetimes.
