# A 1080p strand-hair frame by stage (#729)

This report measures one 1920 x 1080 frame of the default groom, as [issue 729](https://github.com/SethKitchen/ThreeMojo/issues/729) asks, split from [issue 298](https://github.com/SethKitchen/ThreeMojo/issues/298). A frame takes about 0.79 seconds on the CPU, about 47 times the 16.667 millisecond budget. Building and drawing the strand triangles takes almost all of it. The GPU rasterizer could not draw a 1080p frame within this machine's one-minute GPU limit, so issue 729 stays open: it asks for post-warm-up 1080p samples on both rasterizers.

## Method

`bench/hair_frame_bench.mojo` grows the default groom of a six-foot male under a head sphere of radius 0.09 m (48 x 32 segments), with one directional light and ambient light. A 30 degree camera frames the head at 1920 x 1080. The simulation steps the guides only.

| Property | Value |
|---|---|
| Strands | 10,185 (1,500 guides with 6 followers each, less the roots that failed) |
| Points | 68,495, 6.7 a strand |
| Strands with a point projected into the image, at rest | 10,185. This counts projected points before motion and before the depth test. It is not a count of strands that stay visible. |
| Coverage | 1 pixel wide lines, opacity 0.65, hashed strand coverage (`STRAND_LINE_COVERAGE`). Accepted samples write opaque depth. |
| Triangles emitted a frame | 1,750,484, from about 58,000 strand segments with feathered ribbons and caps |
| Density resolution | 24 cells a side |
| Raster workers | 24, every logical core |
| Warm-up | 2 frames; then 10 timed frames |

Each frame is timed by stage. `cpu render` is all of `Renderer.render`: its own triangle preparation, lighting, rasterization and resolve. `cpu prepare` times `Renderer.prepare_frame` alone, after the render, as a diagnostic. It is not added to the frame. The bench also renders the rest pose once with the hair hidden, the head hidden, or both. Those controls do not animate, so they are not same-frame costs.

The bench does not count allocations. The renderer and the hair stages have no allocation counter on this path, and the timings include whatever they allocate.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads) and NVIDIA TITAN RTX (24 GiB, driver 591.86), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0. These results are local. Hosted CI builds the bench but does not run it.

## Results on the CPU

The second column is from before [issue 732](https://github.com/SethKitchen/ThreeMojo/issues/732), which builds the wide-line triangles on every core.

| Stage, p50 | Before #732 | After #732 | After, p95 | After, max |
|---|---:|---:|---:|---:|
| Guides-only step and write | 2.09 ms | 2.27 ms | 2.59 ms | 2.59 ms |
| Density, shading and upload | 4.50 ms | 4.73 ms | 5.03 ms | 5.03 ms |
| `cpu render` | 1,192 ms | 784 ms | 829 ms | 829 ms |
| Whole frame | 1,198 ms | 791 ms | 837 ms | 837 ms |
| `cpu prepare` (diagnostic) | about 930 ms | 484 ms | 526 ms | 526 ms |

One render of the rest pose with parts hidden, after #732:

| Visible | Render time |
|---|---:|
| Nothing (background only) | 14 ms |
| Head only | 20 ms |
| Hair only | 775 ms |

The simulation and the shading take about 7 milliseconds together. Of the 784 millisecond render, preparing the 1.75 million triangles takes about 484 and drawing them about 300. Before #732, preparation took about 930 milliseconds on one thread.

## Results on the GPU

The device rasterizer gives each pixel one thread, which walks every primitive. The bench ran its GPU stages at 240 x 135, 1/64 of the pixels, before #732 and with diagnostic prints inside the timed draw stage. Both frames were warm-up frames:

| Stage at 240 x 135 | Frame 0 | Frame 1 |
|---|---:|---:|
| Host preparation (`prepare_frame`) | 888 ms | 1,578 ms |
| `GpuRenderer.draw`: upload and launch | 16,041 ms | 14,788 ms |
| `read_back`: the kernel and the copy back | 7,802 ms | 7,797 ms |

The run was stopped at 60 seconds, during the third frame, so there are no post-warm-up GPU samples. Even at 1/64 of the pixels, one frame takes over 20 seconds. The bench now prints progress only after a frame's last measured stage.

## Decisions

- **Drawing the strands is the bottleneck.** The hair stages take about 7 milliseconds. Preparing and drawing the strand triangles takes about 0.78 seconds after #732.
- **The GPU rasterizer does not suit strand hair.** Its per-pixel walk over every primitive, and the per-draw upload, cost seconds at a small size. A 1080p GPU frame needs tiled binning or a strand-specific path first. Issue 729 stays open for that evidence.
- **No 1080p, 60 frames-per-second claim is made.** These numbers describe this machine.
