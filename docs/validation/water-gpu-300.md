# Clearwater water on a GPU (#300)

This report measures the GPU water shader that [issue 300](https://github.com/SethKitchen/ThreeMojo/issues/300) asks for, compares its pixels with the CPU frame, and states what the numbers decide for the 60 frames-per-second goal. The GPU shades a 1920 x 1080 frame in about 41 to 76 milliseconds; the CPU takes about 1.36 seconds on every core. A whole frame is still far over the 16.7 millisecond budget, because bloom, glare, grading, the scene render and the surface FFT stay on the CPU.

## Method

`bench/water_gpu_bench.mojo` builds a `WaterScene` with the page's settings, as `bench/water_bench.mojo` does: a 256 ocean spectrum, a 64-cell caustic grid, 256 caustic texels and a 128 glare transform. It loads `assets/pebbles.jpg`. Each workload runs two warm-up frames, then times each frame by stage. GPU rows time 10 frames. CPU rows time 3, because each takes over a second, so a CPU p95 is the slowest of three, not a stable tail.

- **Radiance only**: `GpuWater.radiance` at four image sizes. It includes the CPU surface FFT and caustics, the packing, the copies, the kernel and the copy back.
- **Water frame**: a whole 1920 x 1080 `FRAME`: `advance`, the surface and caustics, shading, then bloom, glare and grading on the CPU.
- **Composed scene**: 64 lit spheres of 24 x 16 segments standing above the water, lit from (3, 10, 5). The water takes the same sun. The CPU renderer draws the spheres at 1920 x 1080. The GPU path then shades every pixel and runs the depth pass, as `GpuWater.compose` does. The CPU path runs the depth pass first and shades the pixels that pass, as `WaterScene.compose` does. Both grade and write the water pixels. 995,300 of the 2,073,600 pixels show water.

The full output of the run is in [water-gpu-300-bench.txt](water-gpu-300-bench.txt).

Hardware: NVIDIA TITAN RTX (24 GiB, driver 591.86) and AMD Ryzen 9 5900X (12 cores, 24 threads), WSL 2 on Windows 11. Software: Mojo 1.1.0 (`8189361e`) and MAX 26.6.0. These results are local. Hosted CI builds the kernel for sm_80 but has no GPU to run it.

## Results

The depth pass, the highlight and blur passes, and the grade-and-write pass run disjoint runs of rows on every logical core ([issue 733](https://github.com/SethKitchen/ThreeMojo/issues/733)). Each pixel has one writer and the serial arithmetic. `WaterScene.workers` sets how each pass is cut into tasks, not a thread limit. One worker runs each pass as one task over every row. A test draws `FRAME`, `LINEAR` and `GLARE` and composes a scene on one worker and on every core. It requires the same pixels, depths and drawn count. Other tests compare each pass with one serial pass bit for bit. The glare pass stays serial.

Radiance only, in milliseconds:

| Image | p50 | p95 | max |
|---|---:|---:|---:|
| 320 x 180 | 46.7 | 47.4 | 47.4 |
| 640 x 360 | 49.9 | 50.8 | 50.8 |
| 1280 x 720 | 62.9 | 65.8 | 65.8 |
| 1920 x 1080 | 82.7 | 85.3 | 85.3 |

A 1920 x 1080 water frame, in milliseconds as p50 / p95 / max:

| Stage | GPU | CPU |
|---|---:|---:|
| `advance` | 13.0 / 13.0 / 13.0 | 12.9 / 12.9 / 12.9 |
| Surface and caustics | 44.0 / 45.1 / 45.1 | 43.9 / 44.0 / 44.0 |
| Shading | 41.0 / 74.7 / 74.7 | 1,360 / 1,372 / 1,372 |
| Bloom, glare and grading | 154 / 163 / 163 | 152 / 161 / 161 |
| Whole frame | 255 / 294 / 294 | 1,578 / 1,581 / 1,581 |

A 1920 x 1080 composed scene, in milliseconds as p50 / p95 / max:

| Stage | GPU | CPU |
|---|---:|---:|
| `advance` | 13.4 / 13.8 / 13.8 | 13.2 / 13.3 / 13.3 |
| Scene render | 93.1 / 98.1 / 98.1 | 93.9 / 101 / 101 |
| Surface and caustics | 42.8 / 43.2 / 43.2 | 42.6 / 42.8 / 42.8 |
| Depth pass | 41.4 / 42.7 / 42.7 | 41.4 / 42.5 / 42.5 |
| Shading | 43.7 / 78.6 / 78.6 | 635 / 639 / 639 |
| Grade and write | 10.1 / 10.3 / 10.3 | 10.5 / 11.4 / 11.4 |
| Whole frame | 247 / 281 / 281 | 836 / 849 / 849 |

An earlier run gives a before observation. That run, at commit `d06143b1`, came before the row passes ran in parallel. It gave 382 ms for bloom, glare and grading, 621 ms for the depth pass and 115 ms for the grade and write. Its GPU water frame took 515 ms and its GPU composed scene 971 ms. Its full output is `water-gpu-300-bench.txt` at that commit.

The row passes explain the changes in the CPU stages. GPU shading also changed between the two runs, from 76 to 41 ms in the water frame and from 85 to 44 ms in the composed scene. The kernel did not change, so the row passes do not explain the whole frame gain.

Opening the device and copying the photograph took 634 milliseconds once.

## Agreement with the CPU

`tests/test_gpu_water.mojo` has eight device tests. Their output, with the revision, the command and the hardware, is in [water-gpu-300-tests.txt](water-gpu-300-tests.txt). Each radiance comparison divides the difference by the larger of the CPU value and 0.01, so it is relative for bright values and absolute near black. Every value on both paths must be finite.

- Radiance at 96 x 64 and at 97 x 61, which leaves partial tiles, at two pitches: at least 98 percent of values within 1 percent, at least 99.5 percent within 10 percent, and none beyond 2. Measured at 96 x 64: 98.7 and 99.0 percent within 1 percent, and 99.913 percent within 10 percent at both pitches. The worst value differed by 0.47.
- After `set_sun` and after `reset`, with active ripples: the same bounds.
- A whole `FRAME` at 64 x 48: at most 2 percent of pixels differ by more than 2 of 255 in a channel. `CAUSTICS` does not shade, and every channel of every pixel matches exactly.
- A composed scene at 40 x 30: the same water pixels and depths as the CPU. Every pixel that is not water keeps the scene's color exactly. At most 2 percent of the water pixels differ by more than 2 of 255 in a channel. The test divides by the count of water pixels, not by the count of all pixels.

The device fuses multiplies and adds where the host does not, and its math functions round differently. A last-bit change can flip an anisotropic tap count, a mip clamp or a noise band. That is why a few values differ a lot.

## Failures

A copy reads its host list until it completes. `GpuWater` waits for the device on every exit, success or failure, before the host lists of a frame or of the photograph can be freed. Then it re-raises the original error.

`GpuWater.compose` shades on the GPU before it changes the image. If shading fails, the image and its depths are unchanged. A test makes a frame fail after its uploads are queued. The next frame still matches the CPU. A failed composition leaves the image as it was. A retry then gives the same pixels, depths and drawn count as a first composition of a fresh image.

A second test makes the constructor fail after the photograph's first copy is queued. The failed construction releases its buffer and its context: free device memory returns within 1 MiB. The next construction then shades as the CPU does. The test does this twice.

### Supported failures

`GpuWater` recovers from the errors that it raises on the host: a refused image size, and the failures that the tests inject. After one of these, the object and the device stay usable.

A CUDA error that the driver reports is fatal. Restart the process after one. `GpuWater` does not try to recover a context, and no test exhausts device memory.

The cleanup relies on one guarantee of the pinned MAX 26.6.0: [`DeviceContext.synchronize`](https://max.modular.com/stable/api/mojo/max/gpu/host/device_context/DeviceContext/#synchronize) waits until the queued work completes. CUDA can also report an earlier asynchronous error from that call ([CUDA stream management](https://docs.nvidia.com/cuda/cuda-driver-api/cuda_driver_api/group__CUDA__STREAM.html)). So an error from `synchronize` does not show that a copy is still in progress. It shows a fatal device error.

## Resources

`GpuWater` keeps the photograph and its mips on the device: about 16.8 MB for a 1024 x 1024 photograph. Each frame allocates its device storage, then frees it:

- the surface and its mips: 16 bytes a texel, about 1.33 times the 256 x 256 grid, about 1.4 MB;
- the ripple window: 16 bytes a texel, 1.0 MB;
- the caustics and their mips: 12 bytes a texel, about 1.33 times the 256 x 256 texture, about 1.0 MB;
- the output: 12 bytes a pixel, 24.9 MB at 1920 x 1080;
- the level tables and the frame values: under 1 KB.

So a 1920 x 1080 frame holds at most about 28.3 MB of device storage beyond the photograph. The host keeps a mirrored staging payload of the same size: the packed lists that the copies read, and the list that the output is copied back to. This is not the peak host memory of a whole frame, which also holds the CPU stages' images.

The resource tests read free device memory after each frame, never inside one. These readings are post-frame watermarks, not in-frame peaks; the in-frame peak is the bound above. Over two rounds of 60 frames at 64 x 48, 97 x 61 and 128 x 72, with a `reset` and a refused frame, free memory ends within 1 MiB of where warm-up left it, the post-frame readings stay within 16 MiB of it, and resident host memory grows by under 32 MiB. After an object is dropped, free device memory returns within 1 MiB of where it was before the object. This also holds for an object dropped with no frame, and for one dropped after a failed frame. Repeated whole `draw` calls are not part of these tests.

An Apple GPU shares the system's memory. The free memory a context reports there moves with every other process, so the tests do not ask for the free-memory bounds on Apple GPUs. macOS has no `/proc`, so the host check reads the peak resident size from `getrusage`. A peak that does not grow means the resident size did not grow.

## Decisions

- **The GPU makes the shading about 15 to 30 times faster.** A 1920 x 1080 shade takes about 41 to 76 milliseconds on the GPU and 1,360 on every CPU core.
- **The whole frame does not reach 60 frames per second.** A GPU water frame takes about 255 milliseconds, about 15 times the budget. A GPU composed scene takes about 247.
- **The CPU stages around the shader are now the bottleneck.** Bloom, glare and grading take about 154 milliseconds, the scene render 93, the surface FFT and caustics 43, and the depth pass 41.
- **CUDA is the only supported target.** `GpuWater` refuses a machine without an NVIDIA GPU. No Metal check covers this kernel.

These numbers describe this machine. They are not a hardware-independent claim.
