# Benchmarks

This page records compile time, run time and peak memory for every example. The same scene, size and frame count run in three.js. A standalone probe compares Mojo 1.1 to Mojo 1.0.

The numbers come from one machine. Other machines differ. The refresh command is in [How to measure examples](How-to-measure-examples).

## Machine

<!-- BENCH:HOST -->
- Date: `2026-09-18`
- OS: Linux 6.18.33.1-microsoft-standard-WSL2
- CPU: AMD Ryzen 9 5900X 12-Core Processor
- Mojo 1.1: `Mojo 1.1.0 (8189361e)`
- Mojo 1.0: `Mojo 1.0.0 (ed45d567)`
- Node: `v22.14.0`
- three.js backend: `cpu`
<!-- /BENCH:HOST -->

## What the columns measure

| Column | Meaning |
|---|---|
| compile | `mojo build`, in seconds. Paired in the 1.0 table. |
| run | The built binary or the Node process, in seconds |
| RSS | Peak resident set of that run, in MiB |

Paired columns sit next to each other. Dark green is faster by 30% or more. Light green is faster by 10% to 30%. Yellow is within 10%. A cell with no color is the slower side, or a value with no pair.

ThreeMojo draws in software on the CPU and writes PNG or APNG. three.js draws with WebGL when the `gl` package loads, or with a CPU fill of the same triangles when it does not. three.js does not encode an animated PNG.

The pin is Mojo 1.1. The 1.0 column is the same source built by Mojo 1.0.0. The probe is a standalone triangle fill that imports nothing from ThreeMojo.

## Example vs three.js

<!-- BENCH:EXAMPLES -->
| Example | Size | Frames | ThreeMojo compile (s) | ThreeMojo run (s) | three.js run (s) | ThreeMojo RSS (MiB) | three.js RSS (MiB) |
|---|---|---|---|---|---|---|---|
| `triangle` | 320×240 | 1 | 3.190 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.020</strong></span> | 0.140 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>14.9</strong></span> | 145.9 |
| `spin` | 160×120 | 24 | 3.230 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.040</strong></span> | 0.130 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>20.6</strong></span> | 145.7 |
| `cube` | 240×180 | 36 | 4.060 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.120</strong></span> | 0.150 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>39.8</strong></span> | 148.0 |
| `cubes` | 260×200 | 48 | 7.690 | 0.220 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.160</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>58.5</strong></span> | 149.3 |
| `uv` | 320×200 | 2 | 7.230 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.030</strong></span> | 0.140 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>16.1</strong></span> | 145.5 |
| `textured` | 260×200 | 36 | 7.820 | 0.190 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.160</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>43.6</strong></span> | 148.1 |
| `glass` | 260×200 | 36 | 7.810 | 0.180 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.160</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>43.4</strong></span> | 148.8 |
| `floor` | 320×200 | 30 | 7.900 | 0.210 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.150</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.4</strong></span> | 148.3 |
| `photo` | 260×200 | 36 | 9.030 | 0.190 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.170</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>43.9</strong></span> | 147.8 |
| `lamps` | 260×200 | 36 | 7.760 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.180</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.190</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>43.6</strong></span> | 150.0 |
| `first_scene` | 320×240 | 1 | 7.660 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.020</strong></span> | 0.140 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>15.6</strong></span> | 149.4 |
| `lit_scene` | 320×240 | 36 | 7.830 | 0.260 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.170</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>62.9</strong></span> | 148.5 |
| `rotations` | 240×180 | 36 | 9.940 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.170</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.4</strong></span> | 147.8 |
| `ortho` | 240×180 | 36 | 8.170 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.170</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.1</strong></span> | 148.5 |
| `geometry` | 240×180 | 36 | 9.070 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.180</strong></span> | 0.230 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>42.4</strong></span> | 150.1 |
| `instances` | 240×180 | 36 | 8.100 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.200</strong></span> | 0.640 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.4</strong></span> | 149.7 |
| `raycast` | 240×180 | 36 | 8.600 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.190</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.200</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.1</strong></span> | 151.0 |
| `curves` | 240×180 | 36 | 12.410 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.680</strong></span> | 1.150 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.5</strong></span> | 150.3 |
| `keyframes` | 240×180 | 36 | 29.170 | 0.410 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.270</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.4</strong></span> | 148.2 |
| `skinning` | 240×180 | 36 | 10.420 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.170</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.180</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.5</strong></span> | 149.4 |
| `phong` | 240×180 | 36 | 8.540 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.200</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.190</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>42.2</strong></span> | 150.7 |
| `fog` | 240×180 | 36 | 8.850 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.150</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.150</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.2</strong></span> | 148.1 |
| `culling` | 240×180 | 36 | 8.130 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.150</strong></span> | 0.180 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.5</strong></span> | 148.1 |
| `clipping` | 240×180 | 36 | 7.990 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.7</strong></span> | 148.5 |
| `gpu_backend` | 240×180 | 36 | 8.400 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.170</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.180</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.4</strong></span> | 148.3 |
| `exposure` | 240×180 | 36 | 8.260 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.180</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.180</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.2</strong></span> | 148.2 |
| `model` | 240×180 | 36 | 9.500 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.1</strong></span> | 148.6 |
| `orbit` | 240×180 | 36 | 7.950 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.170</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.8</strong></span> | 150.0 |
| `clock` | 240×180 | 36 | 8.130 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.150</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.150</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.2</strong></span> | 148.0 |
| `chain` | 240×180 | 36 | 8.190 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.150</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.5</strong></span> | 148.3 |
| `additive` | 240×180 | 36 | 7.900 | 0.180 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.160</strong></span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.8</strong></span> | 148.5 |
| `normals` | 240×180 | 36 | 8.150 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.190</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.190</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>41.1</strong></span> | 150.7 |
| `fragments` | 240×180 | 36 | 8.050 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.170</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>40.2</strong></span> | 148.5 |
| `edges` | 240×180 | 48 | 3.420 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.150</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.160</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 148.0 |

three.js backend for this run: `cpu`.
<!-- /BENCH:EXAMPLES -->

## Mojo 1.1 against Mojo 1.0

<!-- BENCH:MOJO10 -->
| Program | 1.1 compile (s) | 1.0 compile (s) | 1.1 run (s) | 1.0 run (s) | 1.1 RSS (MiB) | 1.0 RSS (MiB) |
|---|---|---|---|---|---|---|
| `probe` | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">2.530</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">2.530</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.040</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.040</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">13.2</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">14.3</span> |
| `triangle` | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">3.190</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">3.260</span> | 0.020 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.010</strong></span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">14.9</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">14.4</span> |
| `spin` | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">3.230</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">3.250</span> | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.040</strong></span> | 0.050 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">20.6</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">20.4</span> |
| `cube` | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">4.060</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">4.170</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.120</strong></span> | 0.160 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">39.8</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">39.8</span> |
| `cubes` | 7.690 | 2.510 | 0.220 | refused | 58.5 | — |
| `uv` | 7.230 | 2.380 | 0.030 | refused | 16.1 | — |
| `textured` | 7.820 | 2.500 | 0.190 | refused | 43.6 | — |
| `glass` | 7.810 | 2.490 | 0.180 | refused | 43.4 | — |
| `floor` | 7.900 | 2.460 | 0.210 | refused | 44.4 | — |
| `photo` | 9.030 | 2.980 | 0.190 | refused | 43.9 | — |
| `lamps` | 7.760 | 2.450 | 0.180 | refused | 43.6 | — |
| `first_scene` | 7.660 | 2.430 | 0.020 | refused | 15.6 | — |
| `lit_scene` | 7.830 | 2.500 | 0.260 | refused | 62.9 | — |
| `rotations` | 9.940 | 2.610 | 0.160 | refused | 40.4 | — |
| `ortho` | 8.170 | 2.650 | 0.160 | refused | 40.1 | — |
| `geometry` | 9.070 | 2.800 | 0.180 | refused | 42.4 | — |
| `instances` | 8.100 | 2.640 | 0.200 | refused | 40.4 | — |
| `raycast` | 8.600 | 2.700 | 0.190 | refused | 40.1 | — |
| `curves` | 12.410 | 12.270 | 0.680 | refused | 40.5 | — |
| `keyframes` | 29.170 | 5.130 | 0.410 | refused | 40.4 | — |
| `skinning` | 10.420 | 3.020 | 0.170 | refused | 40.5 | — |
| `phong` | 8.540 | 2.910 | 0.200 | refused | 42.2 | — |
| `fog` | 8.850 | 2.730 | 0.150 | refused | 40.2 | — |
| `culling` | 8.130 | 3.090 | 0.150 | refused | 40.5 | — |
| `clipping` | 7.990 | 2.520 | 0.160 | refused | 40.7 | — |
| `gpu_backend` | 8.400 | 2.660 | 0.170 | refused | 40.4 | — |
| `exposure` | 8.260 | 2.620 | 0.180 | refused | 40.2 | — |
| `model` | 9.500 | 2.700 | 0.160 | refused | 40.1 | — |
| `orbit` | 7.950 | 2.450 | 0.170 | refused | 40.8 | — |
| `clock` | 8.130 | 2.550 | 0.150 | refused | 40.2 | — |
| `chain` | 8.190 | 2.480 | 0.150 | refused | 40.5 | — |
| `additive` | 7.900 | 2.580 | 0.180 | refused | 40.8 | — |
| `normals` | 8.150 | 2.460 | 0.190 | refused | 41.1 | — |
| `fragments` | 8.050 | 2.500 | 0.160 | refused | 40.2 | — |
| `edges` | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">3.420</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">3.380</span> | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.150</strong></span> | 0.210 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">45.7</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">45.5</span> |
<!-- /BENCH:MOJO10 -->

Mojo 1.0.0 compiles the probe, `triangle`, `spin`, `cube` and `edges`. It refuses the other examples.

## Other benches

| Program | Shows |
|---|---|
| `bench/raster_bench.mojo` | CPU against GPU rasterization across image sizes. |
| `bench/scene_bench.mojo` | Each stage of the CPU renderer, one worker and every core. |
| `bench/probe.mojo` | The 1.1 half of the compiler comparison. |
| `bench/mojo10/probe.mojo` | The 1.0 half. `make lint` excludes this file. |
