# Body triangles and thin strands on the CPU (#298)

This report measures one 1920 x 1080 CPU frame of body triangles and the default groom of one-pixel strands. It uses 1, 2 and 4 workers, as [issue 298](https://github.com/SethKitchen/ThreeMojo/issues/298) asks. Before this change, 60 percent of the strand triangles had zero area on the image. Neither rasterizer draws a sample of a zero-area triangle, so the renderer now does not emit them. The image is the same, byte for byte, at every worker count, before and after.

On this machine a whole render at 4 workers fell from about 1.8 seconds to about 0.95 seconds. These numbers describe this machine only.

## Method

`bench/hair_strand_raster_bench.mojo` grows the default groom of a six-foot male, 1500 guides with six followers each. It puts a head sphere (48 x 32 segments) and a larger torso sphere (128 x 64 segments) under the hair. It shades the groom once with one light. The scene does not move.

For each worker count, the bench renders one warm-up frame. Then it times five frames of each stage and reports the median and the slowest frame:

- `prepare`: `Renderer.prepare_frame` alone. This builds the screen-space triangles, the strand ribbons and caps among them.
- `render`: `Renderer.render`: its own preparation, lighting, rasterization and resolve.

The difference of the two medians estimates the lighting, rasterization and resolve. It is not a measured stage.

The bench computes the CRC-32 of each worker count's image. It stops with an error when a worker count draws a different image from one worker. It also renders the scene once with the hair hidden, as a control.

Run it with `mojo run -I . bench/hair_strand_raster_bench.mojo [frames [width height]]`. It needs no GPU.

| Property | Value |
|---|---|
| Image | 1920 x 1080 |
| Strands | 10,185 |
| Points | 68,495 |
| Segments | 58,310 |
| Coverage | 1 pixel wide lines, opacity 0.65, hashed strand coverage (`STRAND_LINE_COVERAGE`) |
| Body triangles in the frame | 4,237 of the two spheres, after back faces are culled: the corners less 90 a segment before, or 36 a segment after |
| Workers | 1, 2 and 4, every logical core |
| Warm-up | 1 frame per worker count; then 5 timed frames |

Hardware: Intel Xeon Processor @ 2.10GHz (model 207), 4 vCPUs (4 cores, 1 thread each), 8 MiB L2, 15 GiB, under KVM. Linux 6.18.44. Software: Mojo 1.1.0 (`8189361e`). Other jobs shared this machine during some earlier runs. The runs below were made when its load average was between 1.0 and 1.8.

## What the frame held

A one-pixel strand has a half width of half a pixel. Its box-filtered profile then has an inner radius of zero (`_strand_profile`). The inner corners of each end are therefore at the center line. Of the 30 triangles of each segment, 18 have two corners at the same place:

- the middle strip of the ribbon, 2 triangles;
- in each of the 4 steps of each round cap, 2 of the 3 triangles.

The CPU rasterizer returns from a triangle of zero area (`_Coverage.is_degenerate`). The device kernel skips it too (`area == 0`). These triangles cost preparation, memory and a per-triangle setup in the rasterizer, and they drew nothing.

A `Corner` is 256 bytes on this machine. The frame held 5,260,611 corners, about 1.35 GB, and every frame allocated and filled them again.

## The change

- `_emit_placed` leaves out a triangle that needs no cut and has two corners at the same pixel coordinates. A triangle that the clipper cuts is cut and projected as before, so its pieces do not change.
- Each strand corner is projected once (`_Placed`) and shared by every triangle that uses it. Before, each triangle projected its three corners again.
- A draw with a polygon offset projects each triangle again, as before, so its depths do not change.
- Each parallel run of wide-line segments reserves room for its corners before it starts. Before, its list grew and copied itself.

The two parts were not measured separately.

## Results

Each cell is the median of 5 frames, from two runs made in turn: before, after, after, before.

| Workers | Stage | Before | After |
|---:|---|---:|---:|
| 1 | `prepare` | 874, 901 ms | 704, 786 ms |
| 1 | `render` | 2,683, 2,706 ms | 1,763, 1,796 ms |
| 2 | `prepare` | 1,366, 1,423 ms | 460, 457 ms |
| 2 | `render` | 2,530, 2,409 ms | 1,142, 1,206 ms |
| 4 | `prepare` | 853, 796 ms | 253, 273 ms |
| 4 | `render` | 1,894, 1,793 ms | 938, 971 ms |

| Measure | Before | After |
|---|---:|---:|
| Corners in the frame | 5,260,611 | 2,111,871 |
| CRC-32 of the image, at 1, 2 and 4 workers | 2070011580 | 2070011580 |
| Render with the hair hidden, 4 workers | 60, 78 ms | 62, 74 ms |
| Whole bench process: user time | 71.7, 69.1 s | 45.3, 46.3 s |
| Whole bench process: system time | 29.0, 27.5 s | 1.7, 3.0 s |

Before the change, preparation on 2 workers was slower than on 1 worker. The system time of the process was about 28 seconds, which agrees with page faults from the large corner lists. The bench does not count page faults or allocations. That cause is an inference, not a measurement.

After the change, the estimate of rasterization and resolve at 4 workers is about 0.69 seconds. Preparation is about 0.26 seconds.

## Profile

`valgrind --tool=callgrind` ran one frame on one worker of a build for `haswell`, because valgrind does not decode the AVX-512 code of a native build. Before the change, preparation spent most of its instructions in `_Paint.raster`, `_Paint.emit` and `_emit_clipped`, and `_emit_strand_cap` held about three quarters of preparation. In the rasterizer, about 1.05 million of the 1.75 million triangles returned as degenerate, after their corners were joined. These counts guided the change. They are instruction counts, not times.

## Decisions

- **Do not emit a strand triangle of zero area.** Both rasterizers skip it, so the image and the depths do not change. The frame holds 60 percent fewer corners.
- **Keep the triangle ribbon for now.** A 1080p frame still takes about a second on this machine. Rasterization and resolve of the remaining strand triangles is now the larger part. A strand-specific primitive, or a smaller corner, remains open in issue 298.
- **No 60 frames-per-second claim is made.** These numbers describe this machine.
