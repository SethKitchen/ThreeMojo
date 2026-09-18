# Why a software rasterizer

ThreeMojo rasterizes in software because Mojo has no graphics pipeline to port `WebGLRenderer` to. That constraint turned out to teach more than a port would have.

![A cube turns through a model matrix and a flat rasterizer](out/cube.png)

## What Mojo offers

Mojo's GPU support is compute only, in the CUDA sense: kernels, buffers and thread indexing. There are no vertex or fragment shaders, no rasterization stage, no window and no swapchain. three.js's renderer drives exactly those things through WebGL.

## What this project does instead

The renderer writes pixels into a plain RGBA buffer. It decides which pixels a triangle covers with an edge function, tests depth per pixel, and shades each fragment itself. Every stage that a GPU hides is visible in the source.

The GPU backend is the same loop with one thread per pixel. Writing the per-pixel loop by hand first is what made that mapping obvious.

## What the buffer is for

The buffer is the product. Displaying it belongs to whatever presents it: a canvas, a window, a texture upload. `Framebuffer` knows nothing about files. The encoders read it. See [Image files](Image-files).

## What is missing

There is no window and no interactive loop. The examples write image files. Windowing is listed as future work in the README checklist.
