# How to use the GPU backend

The GPU backend runs the rasterizer as a kernel with one thread per pixel. It needs MAX and a supported accelerator. Nothing else in the project needs either.

## Install MAX

```bash
uv pip install "max==26.5.0"
```

On macOS, also install Apple's Metal toolchain. Xcode does not install it by default:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Without it every kernel fails with `Metal Compiler failed to compile metallib`. That message looks like a code error and is not.

## Check that a GPU is visible

```bash
.venv/bin/mojo run -I . tools/gpu_status.mojo
```

## Run the GPU checks

```bash
make check-gpu
```

The suite runs under a time budget of 300 seconds. A hang fails the run instead of looking slow. Raise the budget on a machine with a slow first kernel compile:

```bash
make test-gpu GPU_BUDGET=600
```

## Render on the GPU

Prepare the triangles with the CPU renderer, then draw them on the device:

```mojo
from render.gpu import render_triangles

var corners = renderer.prepare(scene, assets, camera)
var lighting = Lighting(scene)
var image = render_triangles(
    corners, width, height, background, SHADE_TEXTURE, assets.textures, lighting
)
```

For many frames, hold a `GpuRenderer` so the device buffers survive between frames. See [GPU backend](GPU-backend).

## Compare the backends

```bash
make bench
```

This times the CPU and GPU rasterizers across image sizes. The GPU numbers include allocation and the copy back.

## Windows

The backend runs under CUDA on WSL 2. Read [The CUDA teardown hang](The-CUDA-teardown-hang) if the second renderer in a process hangs.
