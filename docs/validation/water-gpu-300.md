# Clearwater water on a GPU (#300)

This report measures the GPU water shader that [issue 300](https://github.com/SethKitchen/ThreeMojo/issues/300) asks for, compares its pixels with the CPU frame, and states what the numbers decide for the 60 frames-per-second goal. The GPU shades a 1920 x 1080 frame in about 76 milliseconds; the CPU takes about 1.34 seconds on every core. A whole frame is still far over the 16.7 millisecond budget, because bloom, glare, grading and the composition depth pass stay on the CPU.

## Method

`bench/water_gpu_bench.mojo` builds a `WaterScene` with the page's settings, as `bench/water_bench.mojo` does: a 256 ocean spectrum, a 64-cell caustic grid, 256 caustic texels and a 128 glare transform. It loads `assets/pebbles.jpg`. Each workload runs two warm-up frames, then times each frame by stage. GPU rows time 10 frames. CPU rows time 3, because each takes over a second, so a CPU p95 is the slowest of three, not a stable tail.

- **Radiance only**: `GpuWater.radiance` at four image sizes. It includes the CPU surface FFT and caustics, the packing, the copies, the kernel and the copy back.
- **Water frame**: a whole 1920 x 1080 `FRAME`: `advance`, the surface and caustics, shading, then bloom, glare and grading on the CPU.
- **Composed scene**: 64 lit spheres of 24 x 16 segments standing above the water, lit from (3, 10, 5). The water takes the same sun. The CPU renderer draws the spheres at 1920 x 1080. The GPU path then shades every pixel and runs the depth pass, as `GpuWater.compose` does. The CPU path runs the depth pass first and shades the pixels that pass, as `WaterScene.compose` does. Both grade and write the water pixels. 995,300 of the 2,073,600 pixels show water.

The full output of the run is in [water-gpu-300-bench.txt](water-gpu-300-bench.txt).

Hardware: NVIDIA TITAN RTX (24 GiB, driver 591.86) and AMD Ryzen 9 5900X (12 cores, 24 threads), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0. These results are local. Hosted CI builds the kernel for sm_80 but has no GPU to run it.

## Results

Radiance only, in milliseconds:

| Image | p50 | p95 | max |
|---|---:|---:|---:|
| 320 x 180 | 46.6 | 47.1 | 47.1 |
| 640 x 360 | 49.7 | 50.8 | 50.8 |
| 1280 x 720 | 62.9 | 66.2 | 66.2 |
| 1920 x 1080 | 84.5 | 89.7 | 89.7 |

A 1920 x 1080 water frame, in milliseconds as p50 / p95 / max:

| Stage | GPU | CPU |
|---|---:|---:|
| `advance` | 12.8 / 13.1 / 13.1 | 12.9 / 12.9 / 12.9 |
| Surface and caustics | 43.8 / 44.4 / 44.4 | 44.0 / 44.0 / 44.0 |
| Shading | 76.2 / 123 / 123 | 1,344 / 1,355 / 1,355 |
| Bloom, glare and grading | 382 / 400 / 400 | 393 / 394 / 394 |
| Whole frame | 515 / 561 / 561 | 1,793 / 1,806 / 1,806 |

A 1920 x 1080 composed scene, in milliseconds as p50 / p95 / max:

| Stage | GPU | CPU |
|---|---:|---:|
| `advance` | 12.9 / 13.0 / 13.0 | 12.9 / 13.0 / 13.0 |
| Scene render | 91.7 / 96.7 / 96.7 | 100 / 103 / 103 |
| Surface and caustics | 42.6 / 43.0 / 43.0 | 42.9 / 43.4 / 43.4 |
| Depth pass | 621 / 625 / 625 | 620 / 623 / 623 |
| Shading | 85.0 / 138 / 138 | 637 / 643 / 643 |
| Grade and write | 115 / 119 / 119 | 117 / 117 / 117 |
| Whole frame | 971 / 1,024 / 1,024 | 1,533 / 1,533 / 1,533 |

Opening the device and copying the photograph took 703 milliseconds once.

## Agreement with the CPU

`tests/test_gpu_water.mojo` has seven device tests. Each radiance comparison divides the difference by the larger of the CPU value and 0.01, so it is relative for bright values and absolute near black. Every value on both paths must be finite.

- Radiance at 96 x 64 and at 97 x 61, which leaves partial tiles, at two pitches: at least 98 percent of values within 1 percent, at least 99.5 percent within 10 percent, and none beyond 2. Measured at 96 x 64: 98.7 and 99.0 percent within 1 percent, and 99.913 percent within 10 percent at both pitches. The worst value differed by 0.47.
- After `set_sun` and after `reset`, with active ripples: the same bounds.
- A whole `FRAME` at 64 x 48: at most 2 percent of pixels differ by more than 2 of 255 in a channel. `CAUSTICS` does not shade, and every channel of every pixel matches exactly.
- A composed scene at 40 x 30: the same water pixels and depths as the CPU. Every pixel that is not water keeps the scene's color exactly. At most 2 percent of water pixels differ by more than 2 of 255 in a channel.

The device fuses multiplies and adds where the host does not, and its math functions round differently. A last-bit change can flip an anisotropic tap count, a mip clamp or a noise band. That is why a few values differ a lot.

## Failures

A copy reads its host list until it completes. `GpuWater` waits for the device on every exit, success or failure, before the host lists of a frame or of the photograph can be freed. Then it re-raises the original error.

`GpuWater.compose` shades on the GPU before it changes the image. If shading fails, the image and its depths are unchanged. A test makes a frame fail after its uploads are queued: the next frame still matches the CPU, and a failed composition leaves the image as it was, after which a retry draws the same water as the CPU.

## Resources

`GpuWater` keeps the photograph and its mips on the device: about 16.8 MB for a 1024 x 1024 photograph. Each frame allocates its device storage, then frees it:

- the surface and its mips: 16 bytes a texel, about 1.33 times the 256 x 256 grid, about 1.4 MB;
- the ripple window: 16 bytes a texel, 1.0 MB;
- the caustics and their mips: 12 bytes a texel, about 1.33 times the 256 x 256 texture, about 1.0 MB;
- the output: 12 bytes a pixel, 24.9 MB at 1920 x 1080;
- the level tables and the frame values: under 1 KB.

So a 1920 x 1080 frame holds at most about 28.3 MB of device storage beyond the photograph. Its host lists match that size.

The resource tests read free device memory after each frame, never inside one. These readings are post-frame watermarks, not in-frame peaks; the in-frame peak is the bound above. Over two rounds of 60 frames at 64 x 48, 97 x 61 and 128 x 72, with a `reset` and a refused frame, free memory ends within 1 MiB of where warm-up left it, the post-frame readings stay within 16 MiB of it, and resident host memory grows by under 32 MiB. After an object is dropped, free device memory returns within 1 MiB of where it was before the object. This also holds for an object dropped with no frame, and for one dropped after a failed frame. Repeated whole `draw` calls are not part of these tests.

## Decisions

- **The GPU makes the shading about 18 times faster.** A 1920 x 1080 shade takes about 76 milliseconds on the GPU and 1,344 on every CPU core.
- **The whole frame does not reach 60 frames per second.** A water frame takes about 515 milliseconds, about 31 times the budget. A composed scene takes about 971.
- **The CPU stages around the shader are now the bottleneck.** Bloom, glare and grading take about 382 milliseconds. The composition depth pass takes about 621 milliseconds on one thread. The scene render takes about 92. Each is a candidate for parallel rows or the device.
- **CUDA is the only supported target.** `GpuWater` refuses a machine without an NVIDIA GPU. No Metal check covers this kernel.

These numbers describe this machine. They are not a hardware-independent claim.
