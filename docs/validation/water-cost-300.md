# Clearwater water CPU costs (#300)

This report measures the CPU cost of a persistent `WaterScene` frame, as
issue [#300](https://github.com/SethKitchen/ThreeMojo/issues/300) asks. It
then states what the numbers decide for the 60 frames-per-second goal.

## Method

`bench/water_bench.mojo` builds one `WaterScene` with the page's settings:
a 256 ocean spectrum, a 64-cell caustic grid, 256 caustic texels and a 128
glare transform. For each image size it resets the scene and draws two
warm-up frames. The first warm-up frame also builds the glare kernels. Then
it times each frame's `advance` and `draw` separately, with a 1/60 second
step and the idle camera sway. It reports the median, the 95th percentile
and the slowest frame.

Run it with `mojo run -I . bench/water_bench.mojo [frames]`. The figures
below use five timed frames.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads), 62 GiB, WSL 2 on
Windows 11, Mojo 1.1.0 (`8189361e`).

## Results

Before: `draw` shaded and graded every pixel on one thread.

| Image | Pixels | Advance p50 | Draw p50 | Draw p95 | Frame max |
|---|---:|---:|---:|---:|---:|
| 320 x 180 | 57,600 | 12.9 ms | 574 ms | 579 ms | 592 ms |
| 640 x 360 | 230,400 | 13.0 ms | 2,064 ms | 2,114 ms | 2,127 ms |
| 1280 x 720 | 921,600 | 12.9 ms | 8,016 ms | 8,046 ms | 8,059 ms |
| 1920 x 1080 | 2,073,600 | 13.0 ms | 17,985 ms | 18,013 ms | 18,027 ms |

On one thread the draw time was linear in the pixel count: about 77
milliseconds a frame, plus 8.6 microseconds a pixel. At 1920 x 1080, a
separate probe timed the image-sized post-processing: highlights 90 ms, the
two blur passes 120 ms and the glare convolution 136 ms. The rest, about
17.5 seconds, was the per-pixel shading. Each pixel takes several bilinear
wave taps, a mipmapped anisotropic pebble filter, a caustic filter of up to
sixteen taps, and two sky evaluations.

After: `draw` shades and grades runs of rows on every logical core.

| Image | Advance p50 | Draw p50 | Draw p95 | Frame max | Speedup |
|---|---:|---:|---:|---:|---:|
| 320 x 180 | 12.6 ms | 117 ms | 124 ms | 137 ms | 4.9x |
| 640 x 360 | 12.5 ms | 246 ms | 248 ms | 261 ms | 8.4x |
| 1280 x 720 | 12.3 ms | 789 ms | 798 ms | 811 ms | 10.2x |
| 1920 x 1080 | 12.4 ms | 1,688 ms | 1,725 ms | 1,738 ms | 10.7x |

Sky rows cost far less than water rows. One run of rows per thread left
the threads unbalanced, and a 1920 x 1080 draw took 2.9 seconds. Eight
runs per logical core bring it to 1.7 seconds. Each pixel keeps the serial
arithmetic, and tests compare the parallel result with one serial pass bit
for bit. `compose` keeps its depth test in pixel order and shades only the
pixels that pass, in parallel. The post-processing and the fixed transform
and caustic passes stay serial.

`advance` steps the ripple window and does not depend on the image size.

## Decisions

- **The CPU path cannot reach 60 frames per second at 1920 x 1080.** A
  parallel frame takes about 1.7 seconds, about 100 times the 16.7
  millisecond budget. The goal needs the GPU path that #300 also asks for.
- **The remaining CPU work is mostly serial post-processing.** The
  highlights, blur and glare passes take about 0.35 seconds at 1920 x 1080.
  They are the next candidates for parallel rows.
- **The ripple step needs its own budget.** At about 12 milliseconds a
  step, the simulation alone is near the frame budget. It is a candidate
  for the same parallel or GPU treatment.

These numbers describe this machine. They are not the named-hardware
benchmark that the owner runs for #300.
