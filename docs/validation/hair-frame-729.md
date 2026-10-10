# A 1080p strand-hair frame by stage (#729)

This report measures one 1920 x 1080 frame of the default groom, as [issue 729](https://github.com/SethKitchen/ThreeMojo/issues/729) asks, split from [issue 298](https://github.com/SethKitchen/ThreeMojo/issues/298). A frame takes about 1.2 seconds on the CPU, about 72 times the 16.667 millisecond budget. Rasterizing the strands takes almost all of it. The GPU rasterizer is slower still for this scene.

## Method

`bench/hair_frame_bench.mojo` grows the default groom of a six-foot male under a head sphere of radius 0.09 m (48 x 32 segments), with one directional light and ambient light. A 30 degree camera frames the head at 1920 x 1080. The simulation steps the guides only.

| Property | Value |
|---|---|
| Strands | 10,185 (1,500 guides with 6 followers each, less the roots that failed) |
| Points | 68,495, 6.7 a strand |
| Strands with a point in the image | 10,185 |
| Coverage width | 1 pixel, opaque wide lines |
| Density resolution | 24 cells a side |
| Raster workers | 24, every logical core |
| Warm-up | 2 frames; then 10 timed frames |

Each frame is timed by stage. The bench also times one render of the frame with the hair hidden, the head hidden, or both.

The bench does not count allocations. The renderer and the hair stages have no allocation counter on this path, and the timings include whatever they allocate. [Issue 298](https://github.com/SethKitchen/ThreeMojo/issues/298)'s CPU cost report counts geometry bytes instead.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads) and NVIDIA TITAN RTX (24 GiB, driver 591.86), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0. These results are local. Hosted CI builds the bench but does not run it.

## Results on the CPU

| Stage | p50 | p95 | max |
|---|---:|---:|---:|
| Guides-only step and write | 2.09 ms | 2.51 ms | 2.51 ms |
| Density, shading and upload | 4.50 ms | 4.77 ms | 4.77 ms |
| CPU raster, 24 workers | 1,192 ms | 1,225 ms | 1,225 ms |
| Whole frame | 1,198 ms | 1,232 ms | 1,232 ms |

One render with parts hidden:

| Visible | Raster time |
|---|---:|
| Nothing (background only) | 30 ms |
| Head only | 20 ms |
| Hair only | 1,969 ms |

The simulation and the shading fit in the budget: together they take about 6.6 milliseconds. Rasterizing about 58,000 one-pixel wide-line segments takes about 1.2 to 2.0 seconds. The head hides some strands, so the frame with both is faster than the hair alone.

## Results on the GPU

The device rasterizer gives each pixel one thread, which walks every primitive. A 1920 x 1080 frame would run far past the one-minute limit this machine keeps for GPU work, so the bench ran the GPU stages at 240 x 135, 1/64 of the pixels:

| Stage at 240 x 135 | Frame 0 | Frame 1 |
|---|---:|---:|
| Host preparation (`prepare_frame`) | 888 ms | 1,578 ms |
| `GpuRenderer.draw`: upload and launch | 16,041 ms | 14,788 ms |
| `read_back`: the kernel and the copy back | 7,802 ms | 7,797 ms |

The run was stopped at 60 seconds, during the third frame. Even at 1/64 of the pixels, one frame takes over 20 seconds. The GPU path cannot draw this groom at an interactive rate.

## Decisions

- **The CPU rasterizer is the bottleneck.** The hair stages take about 6.6 milliseconds, but drawing the strands takes about 1.2 seconds. Wide-line rasterization needs its own work before any 60 frames-per-second claim.
- **The GPU rasterizer does not suit strand hair.** Its per-pixel walk over every primitive, and the per-draw upload, cost seconds at a small size. It is not a path to the target until it bins primitives into tiles.
- **No 1080p, 60 frames-per-second claim is made.** These numbers describe this machine.
