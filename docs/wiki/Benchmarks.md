# Benchmarks

This page records compile time, run time and peak memory for every example. The same scene, size and frame count run in three.js. A standalone probe compares Mojo 1.1 to Mojo 1.0.

The numbers come from one machine. Other machines differ. The refresh command is in [How to measure examples](How-to-measure-examples).

## Machine

<!-- BENCH:HOST -->
- Date: `2026-09-19`
- OS: Darwin 25.6.0
- CPU: arm
- Mojo 1.1: `Mojo 1.1.0 (8189361e)`
- Mojo 1.0: `not installed`
- Node: `v24.20.0`
- three.js backend: `cpu-flat`
- A Mojo program that does nothing: `0.014` s
- A Node process that does nothing: `0.027` s
<!-- /BENCH:HOST -->

## What the columns measure

| Column | Meaning |
|---|---|
| compile | `mojo build`, in seconds. Paired in the 1.0 table. |
| run | The built binary or the Node process, whole, in seconds |
| three.js frames only | The draw loop alone, timed inside the Node process |
| RSS | Peak resident set of that run, in MiB |

Paired columns sit next to each other. Dark green is faster by 30% or more. Light green is faster by 10% to 30%. Yellow is within 10%. A cell with no color is the slower side, or a value with no pair.

**The two `run` columns do not measure the same work.** ThreeMojo transforms, clips, lights, textures and composites every frame in linear light on the CPU. It encodes every frame into an APNG and writes the file. three.js draws with WebGL when the `gl` package loads. three.js has no CPU renderer of its own.

When `gl` does not load, the `cpu-flat` backend fills the same projected triangles with each material's flat color and a depth test. It does no lighting, no textures, no sRGB and no transparency, and it writes no file. Most of a `cpu-flat` run is Node starting and importing three.js. The baselines under [Machine](#machine) say what each process costs before it draws anything.

Read the `three.js frames only` column against the ThreeMojo `run` column minus the Mojo baseline. That is the nearest the page comes to like against like.

The pin is Mojo 1.1. The 1.0 column is the same source built by Mojo 1.0.0. The probe is a standalone triangle fill that imports nothing from ThreeMojo.

## Example vs three.js

<!-- BENCH:EXAMPLES -->
| Example | Size | Frames | ThreeMojo compile (s) | ThreeMojo run (s) | three.js run (s) | three.js frames only (s) | ThreeMojo RSS (MiB) | three.js RSS (MiB) |
|---|---|---|---|---|---|---|---|---|
| `triangle` | 320×240 | 1 | 0.392 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.018</strong></span> | 0.040 | 0.002 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>14.3</strong></span> | 64.0 |
| `spin` | 160×120 | 24 | 0.397 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.020</strong></span> | 0.039 | 0.002 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>20.0</strong></span> | 64.1 |
| `cube` | 240×180 | 36 | 0.580 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.027</strong></span> | 0.043 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.6</strong></span> | 65.4 |
| `cubes` | 260×200 | 48 | 1.112 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.040</strong></span> | 0.047 | 0.010 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>59.1</strong></span> | 65.5 |
| `uv` | 320×200 | 2 | 1.021 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.020</strong></span> | 0.040 | 0.002 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>16.0</strong></span> | 64.1 |
| `textured` | 260×200 | 36 | 1.109 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.038</strong></span> | 0.044 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.1</strong></span> | 64.8 |
| `glass` | 260×200 | 36 | 1.127 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.035</strong></span> | 0.045 | 0.009 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>51.8</strong></span> | 65.5 |
| `floor` | 320×200 | 30 | 1.106 | 0.050 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.045</strong></span> | 0.008 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>41.2</strong></span> | 64.6 |
| `photo` | 260×200 | 36 | 1.240 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.041</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.042</span> | 0.007 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.1</strong></span> | 65.1 |
| `lamps` | 260×200 | 36 | 1.112 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.036</strong></span> | 0.052 | 0.013 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.1</strong></span> | 65.6 |
| `first_scene` | 320×240 | 1 | 1.087 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.023</strong></span> | 0.040 | 0.002 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>16.3</strong></span> | 63.9 |
| `lit_scene` | 320×240 | 36 | 1.107 | 0.050 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.045</strong></span> | 0.008 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">69.5</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">64.9</span> |
| `rotations` | 240×180 | 36 | 1.108 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.030</strong></span> | 0.042 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 65.3 |
| `ortho` | 240×180 | 36 | 1.111 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.030</strong></span> | 0.041 | 0.004 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>39.3</strong></span> | 64.9 |
| `geometry` | 240×180 | 36 | 1.117 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.037</strong></span> | 0.070 | 0.031 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.9</strong></span> | 65.8 |
| `instances` | 240×180 | 36 | 1.113 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.032</strong></span> | 0.047 | 0.011 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.2</strong></span> | 65.4 |
| `raycast` | 240×180 | 36 | 1.165 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.038</strong></span> | 0.058 | 0.018 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.8</strong></span> | 66.1 |
| `curves` | 240×180 | 36 | 1.150 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.035</strong></span> | 0.050 | 0.010 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 66.0 |
| `keyframes` | 240×180 | 36 | 1.202 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.030</strong></span> | 0.044 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 65.2 |
| `skinning` | 240×180 | 36 | 1.127 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.035</strong></span> | 0.041 | 0.004 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.9</strong></span> | 65.5 |
| `phong` | 240×180 | 36 | 1.115 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.038</strong></span> | 0.054 | 0.017 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>42.2</strong></span> | 65.7 |
| `fog` | 240×180 | 36 | 1.115 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.029</strong></span> | 0.042 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 65.5 |
| `culling` | 240×180 | 36 | 1.114 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.033</strong></span> | 0.046 | 0.011 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 65.3 |
| `clipping` | 240×180 | 36 | 1.119 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.032</strong></span> | 0.043 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 65.4 |
| `gpu_backend` | 240×180 | 36 | 1.166 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.032</strong></span> | 0.049 | 0.012 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 65.4 |
| `exposure` | 240×180 | 36 | 1.117 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.043</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.042</span> | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>42.0</strong></span> | 65.2 |
| `model` | 240×180 | 36 | 1.211 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.032</strong></span> | 0.043 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 65.3 |
| `orbit` | 240×180 | 36 | 1.108 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.033</strong></span> | 0.043 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.8</strong></span> | 65.7 |
| `clock` | 240×180 | 36 | 1.129 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.031</strong></span> | 0.043 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 65.2 |
| `chain` | 240×180 | 36 | 1.123 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.031</strong></span> | 0.042 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.1</strong></span> | 65.2 |
| `additive` | 240×180 | 36 | 1.116 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.037</strong></span> | 0.043 | 0.006 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>42.1</strong></span> | 65.2 |
| `normals` | 240×180 | 36 | 1.122 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.039</strong></span> | 0.053 | 0.015 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>42.2</strong></span> | 65.5 |
| `fragments` | 240×180 | 36 | 1.131 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.037</strong></span> | 0.047 | 0.009 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 65.3 |
| `edges` | 240×180 | 48 | 0.418 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.029</strong></span> | 0.041 | 0.004 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>50.7</strong></span> | 64.9 |

three.js backend for this run: `cpu-flat`.
The `gl` package did not load, so three.js did not render. The `cpu-flat` backend fills the same triangles with each material's flat color and a depth test. It does no lighting, no textures, no sRGB and no transparency, and it writes no file. The `three.js frames only` column is that fill, timed inside the process. The rest of the `three.js run` column is Node starting and importing three.js.
<!-- /BENCH:EXAMPLES -->

## Mojo 1.1 against Mojo 1.0

<!-- BENCH:MOJO10 -->
| Program | 1.1 compile (s) | 1.0 compile (s) | 1.1 run (s) | 1.0 run (s) | 1.1 RSS (MiB) | 1.0 RSS (MiB) |
|---|---|---|---|---|---|---|
| `probe` | 0.294 | not installed | 0.027 | — | 14.1 | — |
| `triangle` | 0.392 | not installed | 0.018 | — | 14.3 | — |
| `spin` | 0.397 | not installed | 0.020 | — | 20.0 | — |
| `cube` | 0.580 | not installed | 0.027 | — | 44.6 | — |
| `cubes` | 1.112 | not installed | 0.040 | — | 59.1 | — |
| `uv` | 1.021 | not installed | 0.020 | — | 16.0 | — |
| `textured` | 1.109 | not installed | 0.038 | — | 44.1 | — |
| `glass` | 1.127 | not installed | 0.035 | — | 51.8 | — |
| `floor` | 1.106 | not installed | 0.050 | — | 41.2 | — |
| `photo` | 1.240 | not installed | 0.041 | — | 44.1 | — |
| `lamps` | 1.112 | not installed | 0.036 | — | 44.1 | — |
| `first_scene` | 1.087 | not installed | 0.023 | — | 16.3 | — |
| `lit_scene` | 1.107 | not installed | 0.050 | — | 69.5 | — |
| `rotations` | 1.108 | not installed | 0.030 | — | 45.7 | — |
| `ortho` | 1.111 | not installed | 0.030 | — | 39.3 | — |
| `geometry` | 1.117 | not installed | 0.037 | — | 47.9 | — |
| `instances` | 1.113 | not installed | 0.032 | — | 46.2 | — |
| `raycast` | 1.165 | not installed | 0.038 | — | 47.8 | — |
| `curves` | 1.150 | not installed | 0.035 | — | 45.8 | — |
| `keyframes` | 1.202 | not installed | 0.030 | — | 45.8 | — |
| `skinning` | 1.127 | not installed | 0.035 | — | 45.9 | — |
| `phong` | 1.115 | not installed | 0.038 | — | 42.2 | — |
| `fog` | 1.115 | not installed | 0.029 | — | 45.8 | — |
| `culling` | 1.114 | not installed | 0.033 | — | 45.7 | — |
| `clipping` | 1.119 | not installed | 0.032 | — | 45.7 | — |
| `gpu_backend` | 1.166 | not installed | 0.032 | — | 45.8 | — |
| `exposure` | 1.117 | not installed | 0.043 | — | 42.0 | — |
| `model` | 1.211 | not installed | 0.032 | — | 45.8 | — |
| `orbit` | 1.108 | not installed | 0.033 | — | 47.8 | — |
| `clock` | 1.129 | not installed | 0.031 | — | 45.8 | — |
| `chain` | 1.123 | not installed | 0.031 | — | 46.1 | — |
| `additive` | 1.116 | not installed | 0.037 | — | 42.1 | — |
| `normals` | 1.122 | not installed | 0.039 | — | 42.2 | — |
| `fragments` | 1.131 | not installed | 0.037 | — | 45.7 | — |
| `edges` | 0.418 | not installed | 0.029 | — | 50.7 | — |
<!-- /BENCH:MOJO10 -->

Mojo 1.0.0 compiles the probe, `triangle`, `spin`, `cube` and `edges`. It refuses the other examples.

## PMREM and the coverage run

The heaviest suites now write a quarter to a half of the coverage records they wrote before issue #157. Every image is the same to the bit.

A coverage run writes one record for each statement that runs. So the cost of a suite under coverage follows the statements in its innermost loops, not its run time. `test_pmrem` takes a fifth of a second without coverage, but it wrote 14 GB under coverage. See [Coverage tool](Coverage-tool#the-capture-grows-with-every-statement-run).

| Suite, every CPU module instrumented | Before | After |
|---|---|---|
| `test_pmrem` | 13.95 GB, 390 s | 3.63 GB, 99 s |
| `test_renderer` | 3.22 GB, 84 s | 2.35 GB, 70 s |
| `test_environment` | 2.34 GB, 63 s | 1.24 GB, 38 s |
| `test_rasterizer` | 0.65 GB, 16 s | 0.49 GB, 15 s |

The times come from a Linux container with four shared cores, so they are approximate. The sizes are exact.

The changes:

- The PMREM blur finds its weights, sines, cosines and copy position once per pass. `CubeUvCopy` holds the position, and `cube_uv_coordinate` uses it too.
- A bilinear read wraps each of its two columns and two rows once.
- `FloatColor` and the `CLAMP` case of `wrap_index` have no statements to probe. `Vector3.cross` and the shadow texel clamp are one statement each.
- Spherical harmonics find only the weight they use.
- `test_pmrem` blurs four environments, not seven. Three tests only need a valid layout, and now use one made by hand.

Without coverage, a 256-texel cube prefilters in about 210 ms, from about 270 ms before.

The sums keep their order, so each blur gives the same bits. The Mojo compiler fuses a multiply and an add into one instruction when it can. Thus moving a product out of a loop can change the last bit. The blur keeps the cross product per tap for that reason. A scratch program compared the images before and after, bit for bit, at face sizes 16 to 256 and from a panorama.

## Other benches

| Program | Shows |
|---|---|
| `bench/raster_bench.mojo` | CPU against GPU rasterization across image sizes. |
| `bench/scene_bench.mojo` | Each stage of the CPU renderer, timed on its own, one worker and every core. |
| `bench/probe.mojo` | The 1.1 half of the compiler comparison. |
| `bench/noop.mojo` | A program that does nothing: the Mojo baseline. |
| `bench/mojo10/probe.mojo` | The 1.0 half. `make lint` excludes this file. |
