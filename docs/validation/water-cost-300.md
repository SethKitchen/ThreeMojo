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
Windows 11, Mojo 1.1.0 (`8189361e`). The water module draws on one thread.

## Results

| Image | Pixels | Advance p50 | Draw p50 | Draw p95 | Frame p50 | Frame max |
|---|---:|---:|---:|---:|---:|---:|
| 320 x 180 | 57,600 | 12.9 ms | 574 ms | 579 ms | 587 ms | 592 ms |
| 640 x 360 | 230,400 | 13.0 ms | 2,064 ms | 2,114 ms | 2,077 ms | 2,127 ms |
| 1280 x 720 | 921,600 | 12.9 ms | 8,016 ms | 8,046 ms | 8,028 ms | 8,059 ms |
| 1920 x 1080 | 2,073,600 | 13.0 ms | 17,985 ms | 18,013 ms | 17,998 ms | 18,027 ms |

Building the scene takes about 8 milliseconds.

The draw time is linear in the pixel count: about 77 milliseconds a frame,
plus 8.6 microseconds a pixel. The fixed part is the ocean transform and the
caustic pass. At 1920 x 1080, a separate probe timed the image-sized
post-processing: highlights 90 ms, the two blur passes 120 ms and the glare
convolution 136 ms. The rest, about 17.5 seconds, is the per-pixel shading
in `water_radiance`. Each pixel takes several bilinear wave taps, a mipmapped
anisotropic pebble filter and a caustic filter of up to sixteen taps, and
two sky evaluations.

`advance` steps the ripple window and does not depend on the image size.
At 13 milliseconds it uses most of a 16.7 millisecond frame by itself.

## Decisions

- **The CPU path cannot reach 60 frames per second at 1920 x 1080.** A
  frame takes about 18 seconds, about 1,080 times the budget. Shading the
  rows on all 24 hardware threads would still leave about 0.75 seconds a
  frame. The 60 frames-per-second goal therefore needs the GPU path that
  #300 also asks for.
- **Parallel rows are the next CPU step.** Each pixel is independent, so
  disjoint runs of rows can shade in parallel, as the hair shading does.
  This waits for the open composition work in
  [#709](https://github.com/SethKitchen/ThreeMojo/pull/709), which edits
  the same draw path.
- **The ripple step needs its own budget.** At 13 milliseconds a step, the
  simulation alone is near the frame budget. It is a candidate for the same
  parallel or GPU treatment.

These numbers describe this machine. They are not the named-hardware
benchmark that the owner runs for #300.
