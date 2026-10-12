# Strand hair on the GPU rasterizer (#298)

This report measures the GPU rasterizer on the strand-hair frame of [issue 298](https://github.com/SethKitchen/ThreeMojo/issues/298). Tile binning makes the device kernel fast: the kernel and the read back of a 1920 x 1080 frame take about 38 milliseconds. Before binning, one frame took more than 20 seconds at 240 x 135, 1/64 of the pixels. A whole GPU frame now takes about 1.6 seconds. Almost all of it is host work that packs 2.1 million corners into the kernel's vertex layout. So the GPU path is still slower than the CPU path, which takes about 0.33 seconds.

These are local results. Hosted CI builds the bench but does not run it.

## Method

`bench/hair_frame_bench.mojo` draws the default groom as [the frame report](hair-frame-729.md) describes: 10,185 strands, a head sphere, one directional light and ambient light. The command is `mojo run -I . bench/hair_frame_bench.mojo 3 gpu W H`. Two warm-up frames come first, then three timed frames. The GPU stages are:

- `gpu prepare`: `Renderer.prepare_frame` at the GPU's size, and the lighting.
- `gpu draw`: `join_corners` and `GpuRenderer.draw`. It includes the join of the corners to their surfaces, the host checks, the upload and the launch.
- `gpu read back`: `GpuRenderer.read_back`, which waits for the kernel.

A separate run timed the stages inside `draw` with temporary timers. Those timers are not in the repository.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads) and NVIDIA TITAN RTX (24 GiB, driver 591.86), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0. Each GPU run was stopped after 60 seconds at most.

## What changed

- **Tile binning.** The host lists each 16 x 16 tile's triangles with `bin_triangles`, in the frame's order. The kernel tests a pixel only against its tile's list. A triangle goes in each tile where a pixel sample can lie inside its snapped bounds, by the kernel's own `snap` and `sample`. So each pixel sees the same covering triangles, in the same order. See [Tile binning](../wiki/GPU-backend.md#tile-binning).
- **Upload.** `flatten_into` writes the vertex lanes straight into the device buffer's host mapping, on every core. The 1.07 GB list that `flatten` built first is gone.
- **Join.** `join_corners` joins a frame's corners to their surfaces on every core, as `Frame.whole_corners` does on one. It is in `render/gpu.mojo` because `renderers/renderer.mojo` is pinned by a reviewed coverage proof.

## Results

The median of three timed frames:

| Stage, p50 | 240 x 135 | 1920 x 1080 |
|---|---:|---:|
| `gpu prepare` | 138 ms | 136 ms |
| `gpu draw` | 1,378 ms | 1,423 ms |
| `gpu read back` | 0.9 ms | 38 ms |
| Frame with the GPU raster | 1,520 ms | 1,600 ms |
| Frame with the CPU raster, for comparison | 336 ms | 334 ms |

Before this change, at 240 x 135, `draw` took about 15 seconds and `read back` about 7.8 seconds; see [the frame report](hair-frame-729.md#results-on-the-gpu).

Inside `draw` at 1920 x 1080, with the join still in the caller and before the join ran in parallel:

| Step | Time |
|---|---:|
| `whole_corners`, on one thread | about 1,200 ms |
| Per-triangle and per-segment checks | about 250 ms |
| Texture-id checks | about 175 ms |
| `flatten_into`, 2.1 million corners | 480 to 615 ms |
| `triangle_state` | about 110 ms |
| `bin_triangles` | about 32 ms |

## Verification

- `tests/test_gpu_layout.mojo` checks each covered pixel of a 240-triangle field against the bins. The field holds small, thin and large triangles of both windings on and around tile seams. The image is not a whole number of tiles. A triangle with a corner that is not finite, or too large to snap, must be in every tile. A triangle off the image must be in none. It checks the fallback when the bins would be too large. It also checks that `flatten_into` on four threads and on one gives the bits of `flatten`.
- `tests/test_gpu.mojo` draws a field of 300 thin, tiny and blended triangles across every seam on both backends. No pixel is different. It then draws a smaller frame into the grown buffer. All 281 device tests pass, and so do the parity tests that came before.
- `tests/test_gpu_layout.mojo` also checks that `join_corners` on one thread and on eight gives the bits of `Frame.whole_corners`.

## Decisions

- **The kernel is no longer the bottleneck.** It takes about 2 percent of a 1080p GPU frame.
- **Host packing is the bottleneck.** Each corner crosses as 128 floats, most of which are the surface's and the same for every corner of a draw. Packing them costs about 1.4 seconds a frame. The next step is a layout that uploads each surface once and each corner's own values once. It changes the kernel's reads and is not done here.
- **The CPU frame cost is in [the cost report](hair-cost-298.md).** Simulation and shading stay on the CPU.
- **No 60 frames-per-second claim is made.** The numbers describe this machine and this groom.
