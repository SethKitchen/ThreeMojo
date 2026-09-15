# Why the CPU renderer uses bands

The CPU renderer cuts the image into horizontal bands and draws each on its own thread. A band owns its rows, so no two threads touch one pixel, and the image is byte for byte what one thread produces.

## Ownership instead of locks

Every triangle is offered to every band. A band draws only the rows it owns. The depth test needs no atomics, and draw order within a band is submission order, which is what keeps blending correct. This is the same argument the GPU kernel makes with one thread per pixel.

The encode from linear light to sRGB, three `pow` calls per pixel, is split the same way.

## Threads before SIMD

A band is the same code with a row range. SIMD would need new arithmetic. The scene benchmark showed that rasterization and the resolve were most of the frame, and both scale with cores now.

## What it measured

`make bench-scene` renders a mipmapped checkerboard sphere of twelve thousand triangles at 1280 by 720:

| Workers | Rasterize | Resolve | Whole frame |
|---|---|---|---|
| 1 | 66 ms | 48 ms | 122 ms |
| 24 | 6 ms | 6 ms | 19 ms |

`prepare` is single threaded at about 7 ms and is now the largest stage.

## One worker by default

The coverage tool reconstructs MC/DC vectors from the order its probe records arrive in. Two threads reporting one decision at once would interleave them. The examples and the benchmark ask for every core with `available_workers()`.

## Errors on a thread

A task cannot raise. A band writes its error into a slot, and `rasterize_all` raises it after every band has finished. Malformed triangle state never reaches a band: `rasterize_all` refuses it first, so the answer does not depend on which band a triangle falls in.

## Keeping the arguments alive

Mojo destroys a value after its last visible use. A coroutine that borrows an argument outlives the call, so `rasterize_all` takes its inputs as borrowed parameters and hands the tasks pointers to them. Everything the tasks read stays alive until `TaskGroup.wait` returns.
