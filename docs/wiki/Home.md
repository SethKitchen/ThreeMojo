# ThreeMojo documentation

ThreeMojo is a port of three.js to Mojo. It renders 3D scenes in software on the CPU, or on a GPU, and writes the result to an image file.

The documentation follows [Diátaxis](https://diataxis.fr). Each page has one job.

## Tutorials

Learn by doing.

- [Render your first scene](Tutorial-Render-your-first-scene)
- [Light, texture and animate a scene](Tutorial-Light-texture-and-animate)

## How-to guides

Get a task done.

- [Install](How-to-install)
- [Run the checks](How-to-run-the-checks)
- [Use the GPU backend](How-to-use-the-GPU-backend)
- [Measure coverage](How-to-measure-coverage)
- [Measure examples](How-to-measure-examples)
- [Add a feature](How-to-add-a-feature)
- [Write documentation](How-to-write-documentation)

## Reference

Look something up.

- [Scene graph](Scene-graph)
- [Rotations](Rotations)
- [Cameras](Cameras)
- [Geometry](Geometry)
- [Meshes and assets](Meshes-and-assets)
- [Lines](Lines)
- [Points and sprites](Points-and-sprites)
- [Helpers](Helpers)
- [Raycasting](Raycasting)
- [Curves and paths](Curves)
- [Animation](Animation)
- [Skinning](Skinning)
- [Materials](Materials)
- [Lights](Lights)
- [Fog](Fog)
- [Textures](Textures)
- [Renderer](Renderer)
- [Rasterization](Rasterization)
- [GPU backend](GPU-backend)
- [Render target and framebuffer](Render-target-and-framebuffer)
- [Image files](Image-files)
- [Model files](Model-files)
- [Math](Math)
- [Units](Units)
- [Coverage tool](Coverage-tool)
- [Commands](Commands)
- [Examples](Examples)
- [Benchmarks](Benchmarks)

## Explanation

Understand why.

- [Why a software rasterizer](Why-a-software-rasterizer)
- [Why the scene graph is an array](Why-the-scene-graph-is-an-array)
- [Why color is linear](Why-color-is-linear)
- [Why a normal is not a color](Why-a-normal-is-not-a-color)
- [Why interpolation is perspective-correct](Why-interpolation-is-perspective-correct)
- [Why coverage uses fixed point](Why-coverage-uses-fixed-point)
- [Why shading is per fragment](Why-shading-is-per-fragment)
- [Why mipmaps](Why-mipmaps)
- [Why transparency is sorted](Why-transparency-is-sorted)
- [Why types and checks both exist](Why-types-and-checks-both-exist)
- [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code)
- [Why the CPU renderer uses bands](Why-the-CPU-renderer-uses-bands)
- [Why the PNG reader checks structure](Why-the-PNG-reader-checks-structure)
- [The CUDA teardown hang](The-CUDA-teardown-hang)
- [The Mojo compiler hang](The-Mojo-compiler-hang)

## Where the pages live

The source of every page is `docs/wiki/` in the repository. `make docs-check` checks the writing rules. `make wiki-publish` copies the pages to this wiki, and the CI workflow does the same on every push to `main`. Edit the files in the repository, not the wiki.
