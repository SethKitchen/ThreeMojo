# Why the CPU and GPU share code

The CPU rasterizer and the GPU kernel call the same functions for the fill rule, texture wrapping, texel blending and light falloff. Two implementations of one rule drift. One implementation cannot.

## What is shared

| Module | Shared functions |
|---|---|
| `render/fillrule.mojo` | Snapping, the edge function, the top-left bias, the sample position. |
| `render/texture.mojo` | `wrap_index`, `blend_texels`, `mix_colour`. |
| `lights/lighting.mojo` | `falloff`. |

Each allocates nothing, prints nothing and raises nothing. That is what lets it compile for a device.

## What is not shared

The rasterizer writes pixels and the kernel writes device memory. The lighting sum has a host version, `Lighting.intensity_at`, and a device version, `_arriving`, because the kernel reads a flat float buffer. The parity tests hold those two to the same numbers.

## The standards

Coverage is integer arithmetic. The two backends must agree exactly, and the tests demand it.

Shading is floating point. A GPU contracts `a * b + c` into a fused multiply-add that rounds once where the CPU rounds twice. A channel whose exact value lands on a quantization midpoint can fall either side. Tests that interpolate shading allow one level per channel, and say so. One level cannot hide a wrong colour, a wrong depth or a wrong pixel.

## What parity cannot catch

A bug inside a shared function makes both sides wrong together. `tests/test_fillrule.mojo` pins the fill rule against values derived from the definitions, and it found exactly such a bug once. See [Why coverage uses fixed point](Why-coverage-uses-fixed-point).

## The list is the contract

`Renderer.prepare` produces one `List[RasterVertex]`. `rasterize_all` and `GpuRenderer.draw` consume that same list. The whole-scene parity tests prepare once and fill twice, so they compare two rasterizers rather than two pipelines.
