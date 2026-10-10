# Clearwater water on a GPU (#300)

This report measures the GPU water shader that [issue 300](https://github.com/SethKitchen/ThreeMojo/issues/300) asks for, compares its pixels with the CPU frame, and states what the numbers decide for the 60 frames-per-second goal. The GPU shades a 1920 x 1080 frame in about 75 milliseconds; the CPU takes about 1.36 seconds on every core. A whole frame is still far over the 16.7 millisecond budget, because bloom, glare, grading and the composition depth pass stay on the CPU.

## Method

`bench/water_gpu_bench.mojo` builds a `WaterScene` with the page's settings, as `bench/water_bench.mojo` does: a 256 ocean spectrum, a 64-cell caustic grid, 256 caustic texels and a 128 glare transform. It loads `assets/pebbles.jpg`. Each workload runs two warm-up frames, then times each frame by stage. The GPU and CPU rows use the same stage boundaries. GPU rows time 10 frames; CPU rows time 3, because each takes over a second.

- **Radiance only**: `GpuWater.radiance` at four image sizes. It includes the CPU surface FFT and caustics, the packing, the copies, the kernel and the copy back.
- **Water frame**: a whole 1920 x 1080 `FRAME`: `advance`, the surface and caustics, shading, then bloom, glare and grading on the CPU.
- **Composed scene**: 64 lit spheres of 24 x 16 segments standing above the water. The CPU renderer draws them at 1920 x 1080. Composition then runs its depth pass on the CPU, shades on the GPU or the CPU, and grades and writes the water pixels. 995,300 of the 2,073,600 pixels show water.

Hardware: NVIDIA TITAN RTX (24 GiB, driver 591.86) and AMD Ryzen 9 5900X (12 cores, 24 threads), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0. These results are local. Hosted CI builds the kernel for sm_80 but has no GPU to run it.

## Results

Radiance only, in milliseconds:

| Image | p50 | p95 | max |
|---|---:|---:|---:|
| 320 x 180 | 46.7 | 47.1 | 47.1 |
| 640 x 360 | 49.5 | 50.2 | 50.2 |
| 1280 x 720 | 61.8 | 62.3 | 62.3 |
| 1920 x 1080 | 82.3 | 82.8 | 82.8 |

A 1920 x 1080 frame by stage, p50 in milliseconds:

| Stage | Water frame, GPU | Water frame, CPU | Composed, GPU | Composed, CPU |
|---|---:|---:|---:|---:|
| `advance` | 13.0 | 12.9 | 12.8 | 13.1 |
| Scene render | | | 98.0 | 99.9 |
| Surface and caustics | 43.9 | 43.7 | in depth | in depth |
| Depth pass | | | 701 | 703 |
| Shading | 75.2 | 1,355 | 117 | 636 |
| Bloom, glare, grading or write | 373 | 373 | 116 | 116 |
| Whole frame | 506 | 1,785 | 1,043 | 1,568 |

The whole-frame p95 was 519 milliseconds for the GPU water frame and 1,082 for the GPU composed scene. Opening the device and copying the photograph took 733 milliseconds once.

## Agreement with the CPU

`tests/test_gpu_water.mojo` compares the GPU with the CPU. Each comparison divides the difference by the larger of the CPU value and 0.01, so it is relative for bright values and absolute near black. Every value on both paths must be finite.

- Radiance at 96 x 64 and at 97 x 61, which leaves partial tiles, at two pitches: at least 98 percent of values within 1 percent, at least 99.5 percent within 10 percent, and none beyond 2. Measured at 96 x 64: 98.7 and 99.0 percent within 1 percent, and 99.913 percent within 10 percent at both pitches. The worst value differed by 0.47.
- After `set_sun` and after `reset`, with active ripples: the same bounds.
- A whole `FRAME` at 64 x 48: at most 2 percent of pixels differ by more than 2 of 255 in a channel. `CAUSTICS` does not shade and matches exactly.
- A composed scene at 40 x 30: the same water pixels and depths as the CPU, and at most 2 percent of pixels differ by more than 2 of 255 in green.

The device fuses multiplies and adds where the host does not, and its math functions round differently. A last-bit change can flip an anisotropic tap count, a mip clamp or a noise band. That is why a few values differ a lot.

## Resources

`GpuWater` copies the photograph once, waits for the copy, then frees the host copy. Each frame waits for its last copy before its host lists are freed. Its destructor waits for the device, frees the buffers, then frees the context, the order `render/gpu.mojo` needs on WSL 2.

The resource test runs two rounds. Each round makes a `GpuWater`, warms it at three sizes, then runs 60 frames that cycle 64 x 48, 97 x 61 and 128 x 72, with a `reset` and a refused frame on the way. Free device memory ends within 1 MiB of where warm-up left it, the frame peak stays under 16 MiB, and resident host memory grows by under 32 MiB. After the object is dropped, free device memory returns within 1 MiB of where it was before the object.

## Decisions

- **The GPU makes the shading about 18 times faster.** A 1920 x 1080 shade takes about 75 milliseconds on the GPU and 1,355 on every CPU core.
- **The whole frame does not reach 60 frames per second.** A water frame takes about 506 milliseconds, about 30 times the budget. A composed scene takes about 1,043.
- **The CPU stages around the shader are now the bottleneck.** Bloom, glare and grading take 373 milliseconds. The composition depth pass, which also builds the surface and caustics, takes 701 milliseconds on one thread. The scene render takes 98. Each is a candidate for parallel rows or the device.
- **CUDA is the only supported target.** `GpuWater` refuses a machine without an NVIDIA GPU. No Metal check covers this kernel.

These numbers describe this machine. They are not a hardware-independent claim.
