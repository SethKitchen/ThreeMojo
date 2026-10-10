# Clearwater water on a GPU (#300)

This report measures the GPU water shader that [issue 300](https://github.com/SethKitchen/ThreeMojo/issues/300) asks for. It compares its pixels with the CPU frame and states what the numbers decide for the 60 frames-per-second goal. A 1920 x 1080 frame of linear radiance takes about 78 milliseconds. The CPU takes about 1.36 seconds for the same pixels on every core.

## Method

`bench/water_gpu_bench.mojo` builds one `WaterScene` with the page's settings, as `bench/water_bench.mojo` does: a 256 ocean spectrum, a 64-cell caustic grid, 256 caustic texels and a 128 glare transform. It loads `assets/pebbles.jpg`. For each image size it resets the scene and runs two warm-up frames. Then it advances the scene and times `GpuWater.radiance` for each of 20 frames. It reports the median, the 95th percentile and the slowest frame. Last, it times the CPU radiance of one 1920 x 1080 frame on every core.

A timed frame includes the surface FFT and the caustics on the CPU, the copies to the device, the kernel, and the copy back. It does not include bloom, glare and grading.

Hardware: NVIDIA TITAN RTX (24 GiB, driver 591.86) and AMD Ryzen 9 5900X (12 cores, 24 threads), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0.

## Results

| Image | GPU p50 | GPU p95 | GPU max |
|---|---:|---:|---:|
| 320 x 180 | 46.8 ms | 47.4 ms | 47.6 ms |
| 640 x 360 | 49.9 ms | 52.5 ms | 54.0 ms |
| 1280 x 720 | 62.1 ms | 62.5 ms | 62.5 ms |
| 1920 x 1080 | 78.1 ms | 83.3 ms | 86.3 ms |

The CPU radiance of one 1920 x 1080 frame took 1,358 milliseconds on every core. Opening the device and copying the photograph took 694 milliseconds once.

The smallest image already takes about 47 milliseconds. That fixed part is the surface FFT, the caustics and the packing on the CPU. The kernel and its copies add about 31 milliseconds at 1920 x 1080.

## Agreement with the CPU

`tests/test_gpu_water.mojo` shades a 96 x 64 frame at two pitches on both paths. The table gives one run of each pitch. Each pitch has 18,432 values.

| Pitch | Within 1e-3 | Within 1e-2 | Over 1e-1 | Worst |
|---|---:|---:|---:|---:|
| -0.72 rad | 83.3 % | 98.7 % | 16 | 0.47 |
| -0.25 rad | 96.0 % | 99.0 % | 16 | 0.40 |

The device fuses multiplies and adds where the host does not, and its math functions round differently. Most values agree within 0.1 percent. A last-bit change can flip an anisotropic tap count, a mip clamp or a noise band, so a few values differ a lot. The test requires 98 percent of values within 1 percent and 99.5 percent within 10 percent.

The same test runs 40 more frames after two warm-up frames. Free device memory does not go down by more than 1 MiB. Each frame frees its device buffers.

## Decisions

- **The GPU path makes the shading 17 times faster.** It does not reach 60 frames per second at 1920 x 1080. A frame takes about 78 milliseconds, about 4.7 times the 16.7 millisecond budget.
- **The CPU work around the kernel is now the bottleneck.** The surface FFT and the caustics take about 45 milliseconds a frame. They are the next candidates for the device.
- **Bloom, glare and grading stay on the CPU.** At 1920 x 1080 they take about 0.35 seconds, as the [CPU report](water-cost-300.md) states.

These numbers describe this machine. They are not a hardware-independent claim.
