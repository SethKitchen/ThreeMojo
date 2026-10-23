# Benchmarks

This page records CPU compile time, draw time and peak memory for `bench/catalog.json`.
The same size and frame count run in three.js.
The previous Mojo release is compared when that compiler is installed.

The draw column names the faster frame loop.
Whole-process time is summarized, because startup can hide the draw.
Displayed times are rounded.
The results file keeps the recorded values before display rounding.

The dates below describe saved runs, not exact source revisions.
These retained files do not record the tested commit.
They do not establish performance for later source changes, including the merge of [#594](https://github.com/SethKitchen/ThreeMojo/pull/594).
Rerun the benchmarks to measure a later revision.

## Who wins

Draw time is the frame loop inside the process.
A gap under 10% is a tie.
A gap of 30% or more is a large win.

cpu-flat fills triangles with a flat color and a depth test.
It does no lighting, no textures and no file write, so it is not the language comparison.

WebGL is three.js drawing with WebGL 2 when the context runs.
The table uses that draw when WebGL runs.
The renderer, backend and work differ, so this does not isolate language speed.
A host with no GPU compares the CPU flat fill instead.

<!-- BENCH:SCORE:linux -->
### Linux

WebGL did not run on this host.
cpu-flat is a flat color fill, so the comparison is the CPU fill.

cpu-flat is the draw comparison on this host.
ThreeMojo wins 6 draws, 6 of them by 30% or more.
cpu-flat wins 67 draws, 67 of them by 30% or more.
3 draws are within 10% and count as ties.
The median cpu-flat draw takes 0.42 times the ThreeMojo draw.
The flat fill does less work than the ThreeMojo frame.

ThreeMojo uses less memory on 75 of 76 examples.
The median resident set is 45 MiB for ThreeMojo and 64 MiB for cpu-flat.

Whole-process time includes startup and writing the image.
The median ThreeMojo process takes 0.096 s.
The median cpu-flat process takes 0.073 s.
A Mojo program that does nothing takes 0.007 s.
A Node process that does nothing takes 0.019 s.
The median Mojo 1.2.0 compile takes 26.4 s.

Mojo 1.1.0 runs 2 programs.
Refused programs: 75.
A refused compile is not a faster compile.
On those programs, Mojo 1.2.0 compiles faster on 1 of 2.
1 compile is within 10%.

2 runs are within 10%.

The catalog lists 76 examples.
This host measures 76 of them.
<!-- /BENCH:SCORE:linux -->

<!-- BENCH:SCORE:macos -->
### macOS

This file has no ThreeMojo draw times.
The draw winner stays blank until the next measurement.

ThreeMojo uses less memory on 61 of 61 examples.
The median resident set is 46 MiB for ThreeMojo and 87 MiB for WebGL.

Whole-process time includes startup and writing the image.
The median ThreeMojo process takes 0.058 s.
The median WebGL process takes 0.099 s.
A Mojo program that does nothing takes 0.010 s.
A Node process that does nothing takes 0.023 s.
The median Mojo 1.1.0 compile takes 8.79 s.

Mojo 1.0.0 runs 5 programs.
Refused programs: 57.
A refused compile is not a faster compile.
On those programs, Mojo 1.1.0 compiles faster on 5 of 5.

Mojo 1.1.0 runs faster on 4 of 5.
1 run is within 10%.

The catalog lists 76 examples.
This host measures 61 of them.
<!-- /BENCH:SCORE:macos -->

## Linux against macOS

<!-- BENCH:CROSS -->
For these saved runs, the median Linux/macOS whole-process time ratio is 1.6.
The median Linux/macOS compile-time ratio is 3.0.
Each ratio is Linux time divided by macOS time.

The Linux date is 2026-10-23. The macOS date is 2026-09-26.
The source and software can differ between these snapshots.
These ratios do not isolate hardware speed.
The comparison uses 61 shared examples.
<!-- /BENCH:CROSS -->

## Machines

### Linux

<!-- BENCH:HOST:linux -->
- Latest refresh: `2026-10-23`
- OS: Linux 6.12.94+
- CPU: Intel(R) Xeon(R) Processor
- Mojo: `Mojo 1.2.0 (2016d0cd)`
- Previous Mojo: `Mojo 1.1.0 (8189361e)`
- Node: `v22.23.4`
- three.js backends: `cpu-flat` (`webgl` did not run)
- A Mojo program that does nothing: `0.007` s
- A Node process that does nothing: `0.019` s
<!-- /BENCH:HOST:linux -->

### macOS

<!-- BENCH:HOST:macos -->
- Latest refresh: `2026-09-26`
- OS: macOS 26.7 (arm64)
- CPU: Apple M4 Max, 16 cores
- Mojo: `Mojo 1.1.0 (8189361e)`
- Previous Mojo: `Mojo 1.0.0 (ed45d567)`
- Node: `v24.20.0`
- three.js backends: `cpu-flat` and `webgl`
- A Mojo program that does nothing: `0.010` s
- A Node process that does nothing: `0.023` s
<!-- /BENCH:HOST:macos -->

The macOS record is from Mojo 1.1.0.
No Mac was available for the move to Mojo 1.2.0, so that record is not measured again.
Run `make bench-examples` on a Mac to refresh it.

## What the columns measure

| Column | Meaning |
|---|---|
| Compile | `mojo build`, in seconds, rounded |
| Mojo draw | The frame loop inside the ThreeMojo process, in seconds |
| cpu-flat draw | The three.js flat fill, in seconds |
| WebGL draw | The three.js WebGL 2 draw, in seconds |
| Draw winner | The faster draw. `tie` means a gap under 10% |
| Mojo RSS | Peak resident set of the ThreeMojo run, in MiB |
| Measured | The date of that row |

Whole-process time and the cpu-flat resident set stay in `bench/results-linux.json` and `bench/results-macos.json`.
The refresh command is in [How to measure examples](How-to-measure-examples).

## Catalog examples

### Linux

<!-- BENCH:EXAMPLES:linux -->
| Example | Size | Frames | Compile (s) | Mojo draw (s) | cpu-flat draw (s) | WebGL draw (s) | Draw winner | Mojo RSS (MiB) | Measured |
|---|---|---|---|---|---|---|---|---|---|
| `triangle` | 320×240 | 1 | 2.91 | 0.001 | 0.006 | unavailable | Mojo | 11 | 2026-10-23 |
| `spin` | 160×120 | 24 | 3.02 | 0.002 | 0.007 | unavailable | Mojo | 18 | 2026-10-23 |
| `cube` | 240×180 | 36 | 4.95 | 0.009 | 0.015 | unavailable | Mojo | 41 | 2026-10-23 |
| `cubes` | 260×200 | 48 | 25.9 | 0.052 | 0.026 | unavailable | cpu-flat | 56 | 2026-10-23 |
| `uv` | 320×200 | 2 | 18.1 | 0.008 | 0.008 | unavailable | tie | 14 | 2026-10-23 |
| `textured` | 260×200 | 36 | 26.0 | 0.15 | 0.017 | unavailable | cpu-flat | 48 | 2026-10-23 |
| `glass` | 260×200 | 36 | 25.6 | 0.068 | 0.021 | unavailable | cpu-flat | 48 | 2026-10-23 |
| `floor` | 320×200 | 30 | 25.9 | 0.20 | 0.018 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `photo` | 260×200 | 36 | 26.5 | 0.092 | 0.017 | unavailable | cpu-flat | 48 | 2026-10-23 |
| `lamps` | 260×200 | 36 | 25.7 | 0.063 | 0.032 | unavailable | cpu-flat | 51 | 2026-10-23 |
| `first_scene` | 320×240 | 1 | 25.3 | 0.003 | 0.007 | unavailable | Mojo | 14 | 2026-10-23 |
| `lit_scene` | 320×240 | 36 | 25.7 | 0.13 | 0.020 | unavailable | cpu-flat | 65 | 2026-10-23 |
| `rotations` | 240×180 | 36 | 26.6 | 0.033 | 0.015 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `ortho` | 240×180 | 36 | 25.7 | 0.033 | 0.012 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `geometry` | 240×180 | 36 | 25.9 | 0.061 | 0.060 | unavailable | tie | 44 | 2026-10-23 |
| `instances` | 240×180 | 36 | 25.6 | 0.043 | 0.028 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `raycast` | 240×180 | 36 | 26.7 | 0.063 | 0.041 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `curves` | 240×180 | 36 | 26.3 | 0.035 | 0.023 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `keyframes` | 240×180 | 36 | 28.3 | 0.025 | 0.016 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `skinning` | 240×180 | 36 | 26.2 | 0.037 | 0.013 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `phong` | 240×180 | 36 | 25.4 | 0.082 | 0.040 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `fog` | 240×180 | 36 | 25.9 | 0.021 | 0.015 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `culling` | 240×180 | 36 | 26.1 | 0.025 | 0.027 | unavailable | tie | 43 | 2026-10-23 |
| `clipping` | 240×180 | 36 | 25.6 | 0.039 | 0.015 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `gpu_backend` | 240×180 | 36 | 27.6 | 0.061 | 0.027 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `exposure` | 240×180 | 36 | 26.9 | 0.077 | 0.015 | unavailable | cpu-flat | 46 | 2026-10-23 |
| `model` | 240×180 | 36 | 27.2 | 0.037 | 0.015 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `orbit` | 240×180 | 36 | 26.4 | 0.036 | 0.016 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `clock` | 240×180 | 36 | 27.4 | 0.032 | 0.015 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `chain` | 240×180 | 36 | 26.3 | 0.038 | 0.015 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `additive` | 240×180 | 36 | 26.3 | 0.057 | 0.015 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `normals` | 240×180 | 36 | 26.7 | 0.071 | 0.035 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `fragments` | 240×180 | 36 | 26.0 | 0.060 | 0.023 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `edges` | 240×180 | 48 | 2.87 | 0.007 | 0.011 | unavailable | Mojo | 47 | 2026-10-23 |
| `lines` | 240×180 | 36 | 26.0 | 0.036 | 0.017 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `sprites` | 240×180 | 36 | 26.0 | 0.043 | 0.024 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `stereo` | 240×120 | 36 | 29.1 | 0.049 | 0.021 | unavailable | cpu-flat | 34 | 2026-10-23 |
| `television` | 240×180 | 36 | 27.3 | 0.10 | 0.017 | unavailable | cpu-flat | 49 | 2026-10-23 |
| `mirror` | 240×180 | 30 | 27.2 | 0.25 | 0.032 | unavailable | cpu-flat | 41 | 2026-10-23 |
| `split` | 240×180 | 36 | 27.0 | 0.068 | 0.027 | unavailable | cpu-flat | 47 | 2026-10-23 |
| `physical` | 480×220 | 1 | 25.5 | 0.022 | 0.009 | unavailable | cpu-flat | 39 | 2026-10-23 |
| `outlines` | 240×180 | 36 | 26.1 | 0.032 | 0.013 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `shadows` | 240×180 | 36 | 25.3 | 0.13 | 0.021 | unavailable | cpu-flat | 46 | 2026-10-23 |
| `wide` | 240×180 | 36 | 26.1 | 0.053 | 0.030 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `bloom` | 240×180 | 36 | 38.1 | 0.23 | 0.048 | unavailable | cpu-flat | 52 | 2026-10-23 |
| `gizmo` | 240×180 | 36 | 27.1 | 0.057 | 0.021 | unavailable | cpu-flat | 47 | 2026-10-23 |
| `json_scene` | 240×180 | 36 | 54.7 | 0.034 | 0.014 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `reloaded` | 240×180 | 36 | 55.6 | 0.10 | 0.051 | unavailable | cpu-flat | 46 | 2026-10-23 |
| `gem` | 240×180 | 36 | 27.9 | 0.25 | 0.034 | unavailable | cpu-flat | 51 | 2026-10-23 |
| `distance` | 240×180 | 36 | 25.7 | 0.093 | 0.039 | unavailable | cpu-flat | 47 | 2026-10-23 |
| `unfogged` | 240×180 | 36 | 26.2 | 0.033 | 0.014 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `targets` | 240×180 | 36 | 26.5 | 0.12 | 0.035 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `layers` | 320×180 | 36 | 26.5 | 0.18 | 0.048 | unavailable | cpu-flat | 57 | 2026-10-23 |
| `graph` | 240×180 | 36 | 27.2 | 0.13 | 0.036 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `basis` | 320×180 | 36 | 32.6 | 0.062 | 0.012 | unavailable | cpu-flat | 54 | 2026-10-23 |
| `coats` | 320×180 | 36 | 26.2 | 0.16 | 0.049 | unavailable | cpu-flat | 64 | 2026-10-23 |
| `skyjson` | 240×180 | 36 | 52.7 | 0.22 | 0.029 | unavailable | cpu-flat | 51 | 2026-10-23 |
| `daylight` | 240×180 | 36 | 39.6 | 1.50 | 0.100 | unavailable | cpu-flat | 48 | 2026-10-23 |
| `faces` | 240×180 | 36 | 26.0 | 0.045 | 0.020 | unavailable | cpu-flat | 43 | 2026-10-23 |
| `utah` | 240×180 | 36 | 28.9 | 0.11 | 0.061 | unavailable | cpu-flat | 49 | 2026-10-23 |
| `blobs` | 240×180 | 36 | 36.0 | 0.034 | 0.080 | unavailable | Mojo | 43 | 2026-10-23 |
| `flipbook` | 240×180 | 36 | 28.4 | 0.048 | 0.027 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `ripples` | 240×180 | 36 | 37.5 | 0.22 | 0.053 | unavailable | cpu-flat | 51 | 2026-10-23 |
| `baked` | 240×180 | 36 | 30.7 | 0.62 | 0.022 | unavailable | cpu-flat | 46 | 2026-10-23 |
| `diagram` | 240×180 | 36 | 12.0 | 0.036 | 0.026 | unavailable | cpu-flat | 42 | 2026-10-23 |
| `bricks` | 240×180 | 36 | 30.7 | 0.046 | 0.017 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `terrain` | 240×180 | 36 | 26.3 | 0.059 | 0.038 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `override` | 240×180 | 36 | 26.1 | 0.083 | 0.042 | unavailable | cpu-flat | 47 | 2026-10-23 |
| `clay` | 240×180 | 36 | 29.6 | 0.057 | 0.041 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `cells` | 240×180 | 36 | 28.6 | 0.70 | 0.053 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `cloud` | 240×180 | 36 | 26.1 | 0.061 | 0.003 | unavailable | cpu-flat | 44 | 2026-10-23 |
| `bounce` | 240×180 | 36 | 27.6 | 7.64 | 0.030 | unavailable | cpu-flat | 49 | 2026-10-23 |
| `sunlight` | 240×180 | 36 | 27.2 | 0.15 | 0.024 | unavailable | cpu-flat | 46 | 2026-10-23 |
| `vase` | 240×180 | 36 | 27.1 | 0.045 | 0.032 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `sapling` | 240×180 | 36 | 27.0 | 0.034 | 0.014 | unavailable | cpu-flat | 45 | 2026-10-23 |
| `particles` | 240×180 | 36 | 28.6 | 0.041 | 0.023 | unavailable | cpu-flat | 44 | 2026-10-23 |

A legacy date is from an older aggregate file; its per-row measurement date is unknown.

Draw time is the frame loop inside the process.
A gap under 10% is a tie.
cpu-flat is a flat color fill with a depth test.
WebGL did not run, so the draw winner uses cpu-flat.
<!-- /BENCH:EXAMPLES:linux -->

### macOS

<!-- BENCH:EXAMPLES:macos -->
| Example | Size | Frames | Compile (s) | Mojo draw (s) | cpu-flat draw (s) | WebGL draw (s) | Draw winner | Mojo RSS (MiB) | Measured |
|---|---|---|---|---|---|---|---|---|---|
| `triangle` | 320×240 | 1 | 1.39 | — | 0.002 | 0.014 | — | 14 | unknown (legacy: 2026-09-26) |
| `spin` | 160×120 | 24 | 1.37 | — | 0.003 | 0.020 | — | 20 | unknown (legacy: 2026-09-26) |
| `cube` | 240×180 | 36 | 2.33 | — | 0.006 | 0.032 | — | 45 | unknown (legacy: 2026-09-26) |
| `cubes` | 260×200 | 48 | 9.46 | — | 0.012 | 0.035 | — | 51 | unknown (legacy: 2026-09-26) |
| `uv` | 320×200 | 2 | 6.87 | — | 0.002 | 0.016 | — | 16 | unknown (legacy: 2026-09-26) |
| `textured` | 260×200 | 36 | 9.06 | — | 0.007 | 0.032 | — | 53 | unknown (legacy: 2026-09-26) |
| `glass` | 260×200 | 36 | 8.91 | — | 0.010 | 0.035 | — | 53 | unknown (legacy: 2026-09-26) |
| `floor` | 320×200 | 30 | 9.03 | — | 0.008 | 0.029 | — | 42 | unknown (legacy: 2026-09-26) |
| `photo` | 260×200 | 36 | 9.18 | — | 0.007 | 0.034 | — | 53 | unknown (legacy: 2026-09-26) |
| `lamps` | 260×200 | 36 | 8.66 | — | 0.014 | 0.032 | — | 45 | unknown (legacy: 2026-09-26) |
| `first_scene` | 320×240 | 1 | 8.61 | — | 0.002 | 0.015 | — | 17 | unknown (legacy: 2026-09-26) |
| `lit_scene` | 320×240 | 36 | 8.73 | — | 0.009 | 0.032 | — | 70 | unknown (legacy: 2026-09-26) |
| `rotations` | 240×180 | 36 | 8.69 | — | 0.006 | 0.030 | — | 46 | unknown (legacy: 2026-09-26) |
| `ortho` | 240×180 | 36 | 8.69 | — | 0.004 | 0.030 | — | 46 | unknown (legacy: 2026-09-26) |
| `geometry` | 240×180 | 36 | 8.75 | — | 0.035 | 0.030 | — | 46 | unknown (legacy: 2026-09-26) |
| `instances` | 240×180 | 36 | 8.65 | — | 0.012 | 0.031 | — | 47 | unknown (legacy: 2026-09-26) |
| `raycast` | 240×180 | 36 | 9.03 | — | 0.019 | 0.035 | — | 46 | unknown (legacy: 2026-09-26) |
| `curves` | 240×180 | 36 | 8.82 | — | 0.011 | 0.032 | — | 46 | unknown (legacy: 2026-09-26) |
| `keyframes` | 240×180 | 36 | 9.63 | — | 0.007 | 0.030 | — | 46 | unknown (legacy: 2026-09-26) |
| `skinning` | 240×180 | 36 | 8.84 | — | 0.005 | 0.030 | — | 46 | unknown (legacy: 2026-09-26) |
| `phong` | 240×180 | 36 | 8.62 | — | 0.018 | 0.097 | — | 46 | unknown (legacy: 2026-09-26) |
| `fog` | 240×180 | 36 | 8.69 | — | 0.006 | 0.028 | — | 46 | unknown (legacy: 2026-09-26) |
| `culling` | 240×180 | 36 | 8.67 | — | 0.013 | 0.031 | — | 46 | unknown (legacy: 2026-09-26) |
| `clipping` | 240×180 | 36 | 8.74 | — | 0.006 | 0.028 | — | 46 | unknown (legacy: 2026-09-26) |
| `gpu_backend` | 240×180 | 36 | 9.31 | — | 0.013 | 0.033 | — | 46 | unknown (legacy: 2026-09-26) |
| `exposure` | 240×180 | 36 | 8.68 | — | 0.006 | 0.030 | — | 46 | unknown (legacy: 2026-09-26) |
| `model` | 240×180 | 36 | 9.13 | — | 0.006 | 0.032 | — | 46 | unknown (legacy: 2026-09-26) |
| `orbit` | 240×180 | 36 | 8.73 | — | 0.006 | 0.026 | — | 46 | unknown (legacy: 2026-09-26) |
| `clock` | 240×180 | 36 | 8.74 | — | 0.006 | 0.025 | — | 46 | unknown (legacy: 2026-09-26) |
| `chain` | 240×180 | 36 | 8.68 | — | 0.006 | 0.029 | — | 40 | unknown (legacy: 2026-09-26) |
| `additive` | 240×180 | 36 | 8.53 | — | 0.006 | 0.026 | — | 46 | unknown (legacy: 2026-09-26) |
| `normals` | 240×180 | 36 | 8.50 | — | 0.017 | 0.024 | — | 46 | unknown (legacy: 2026-09-26) |
| `fragments` | 240×180 | 36 | 8.60 | — | 0.010 | 0.026 | — | 46 | unknown (legacy: 2026-09-26) |
| `edges` | 240×180 | 48 | 1.30 | — | 0.004 | 0.027 | — | 51 | unknown (legacy: 2026-09-26) |
| `lines` | 240×180 | 36 | 8.80 | — | 0.007 | 0.026 | — | 40 | unknown (legacy: 2026-09-26) |
| `sprites` | 240×180 | 36 | 8.77 | — | 0.010 | 0.028 | — | 47 | unknown (legacy: 2026-09-26) |
| `stereo` | 240×120 | 36 | 8.84 | — | 0.008 | 0.025 | — | 36 | unknown (legacy: 2026-09-26) |
| `television` | 240×180 | 36 | 9.04 | — | 0.006 | 0.025 | — | 50 | unknown (legacy: 2026-09-26) |
| `mirror` | 240×180 | 30 | 9.18 | — | 0.011 | 0.024 | — | 41 | unknown (legacy: 2026-09-26) |
| `split` | 240×180 | 36 | 9.23 | — | 0.011 | 0.026 | — | 46 | unknown (legacy: 2026-09-26) |
| `physical` | 480×220 | 1 | 8.95 | — | 0.003 | 0.085 | — | 76 | unknown (legacy: 2026-09-26) |
| `outlines` | 240×180 | 36 | 8.99 | — | 0.005 | 0.025 | — | 40 | unknown (legacy: 2026-09-26) |
| `shadows` | 240×180 | 36 | 8.79 | — | 0.009 | 0.033 | — | 47 | unknown (legacy: 2026-09-26) |
| `wide` | 240×180 | 36 | 8.99 | — | 0.015 | 0.026 | — | 47 | unknown (legacy: 2026-09-26) |
| `bloom` | 240×180 | 36 | 12.1 | — | 0.027 | 0.032 | — | 43 | unknown (legacy: 2026-09-26) |
| `gizmo` | 240×180 | 36 | 9.24 | — | 0.008 | 0.026 | — | 41 | unknown (legacy: 2026-09-26) |
| `json_scene` | 240×180 | 36 | 19.5 | — | 0.005 | 0.025 | — | 47 | unknown (legacy: 2026-09-26) |
| `reloaded` | 240×180 | 36 | 21.3 | — | 0.028 | 0.025 | — | 47 | unknown (legacy: 2026-09-26) |
| `gem` | 240×180 | 36 | 8.77 | — | 0.015 | 0.049 | — | 52 | unknown (legacy: 2026-09-26) |
| `distance` | 240×180 | 36 | 8.59 | — | 0.019 | 0.024 | — | 46 | unknown (legacy: 2026-09-26) |
| `unfogged` | 240×180 | 36 | 8.64 | — | 0.005 | 0.029 | — | 46 | unknown (legacy: 2026-09-26) |
| `targets` | 240×180 | 36 | 8.44 | — | 0.015 | 0.026 | — | 40 | unknown (legacy: 2026-09-26) |
| `layers` | 320×180 | 36 | 8.70 | — | 0.022 | 0.040 | — | 53 | unknown (legacy: 2026-09-26) |
| `graph` | 240×180 | 36 | 9.25 | — | 0.016 | 0.029 | — | 46 | unknown (legacy: 2026-09-26) |
| `basis` | 320×180 | 36 | 12.4 | — | 0.005 | 0.029 | — | 58 | unknown (legacy: 2026-09-26) |
| `coats` | 320×180 | 36 | 8.94 | — | 0.027 | 0.036 | — | 50 | unknown (legacy: 2026-09-26) |
| `skyjson` | 240×180 | 36 | 19.7 | — | 0.012 | 0.040 | — | 40 | unknown (legacy: 2026-09-26) |
| `daylight` | 240×180 | 36 | 11.7 | — | 0.044 | 0.028 | — | 47 | unknown (legacy: 2026-09-26) |
| `faces` | 240×180 | 36 | 8.61 | — | 0.008 | 0.027 | — | 46 | unknown (legacy: 2026-09-26) |
| `utah` | 240×180 | 36 | 9.13 | — | 0.036 | 0.025 | — | 47 | unknown (legacy: 2026-09-26) |
| `blobs` | 240×180 | 36 | 15.7 | — | 0.051 | 0.024 | — | 46 | unknown (legacy: 2026-09-26) |

A legacy date is from an older aggregate file; its per-row measurement date is unknown.

Draw time is the frame loop inside the process.
A gap under 10% is a tie.
cpu-flat is a flat color fill with a depth test.
WebGL is the three.js draw used for the language comparison.
<!-- /BENCH:EXAMPLES:macos -->

## The pinned Mojo against the previous release

The table lists only programs both compilers run.
The column names give the version of each compiler on that host.
A refused compile is not a faster compile.

### Linux

<!-- BENCH:PREVIOUS:linux -->
| Program | 1.2.0 compile (s) | 1.1.0 compile (s) | Compile winner | 1.2.0 run (s) | 1.1.0 run (s) | Run winner |
|---|---|---|---|---|---|---|
| `probe` | 1.97 | 2.06 | tie | 0.042 | 0.043 | tie |
| `diagram` | 12.0 | 14.0 | 1.2.0 | 0.081 | 0.078 | tie |

Programs in this table: 2.
Refused catalog rows: 75.
A refused compile is not a faster compile.
Those rows stay out of this table.
<!-- /BENCH:PREVIOUS:linux -->

### macOS

<!-- BENCH:PREVIOUS:macos -->
| Program | 1.1.0 compile (s) | 1.0.0 compile (s) | Compile winner | 1.1.0 run (s) | 1.0.0 run (s) | Run winner |
|---|---|---|---|---|---|---|
| `probe` | 0.34 | 3.19 | 1.1.0 | 0.025 | 0.029 | 1.1.0 |
| `triangle` | 1.39 | 6.53 | 1.1.0 | 0.012 | 0.011 | tie |
| `spin` | 1.37 | 6.65 | 1.1.0 | 0.014 | 0.018 | 1.1.0 |
| `cube` | 2.33 | 7.65 | 1.1.0 | 0.026 | 0.034 | 1.1.0 |
| `edges` | 1.30 | 6.25 | 1.1.0 | 0.030 | 0.042 | 1.1.0 |

Programs in this table: 5.
Refused catalog rows: 57.
A refused compile is not a faster compile.
Those rows stay out of this table.
<!-- /BENCH:PREVIOUS:macos -->

## Mojo 1.1.0 against Mojo 1.2.0 on the whole catalog

Mojo 1.2.0 compiles the catalog 10% faster than Mojo 1.1.0.
It draws at the same speed.

The previous-release table above lists only 2 programs, because Mojo 1.1.0 refuses the 1.2 source.
So a second run measures the whole catalog.
That run builds the source of commit `9b910ded`, which is the source before the port to 1.2, with Mojo 1.1.0.
The 1.2.0 numbers come from `make bench-examples` on the port.
To repeat the 1.1.0 run, check out `9b910ded`, link a Mojo 1.1.0 environment as `.venv`, and run `sh tools/tool.sh .venv/bin/mojo bench_examples --skip-mojo10 --no-write-wiki`.
Both runs used the Linux host above, one after the other, and no test or build ran beside them.

| Measure, 76 examples | Mojo 1.1.0 | Mojo 1.2.0 |
|---|---|---|
| Median compile | 29.3 s | 26.4 s |
| Total compile | 2288 s | 2050 s |
| Total draw | 15.67 s | 15.73 s |
| Median whole process | 0.095 s | 0.096 s |
| Median ThreeMojo resident set | 45.0 MiB | 44.6 MiB |
| Median compiler resident set | 826 MiB | 791 MiB |

The next table counts examples. A gap under 10% is a tie.

| Measure | 1.2.0 faster | Tie | 1.1.0 faster |
|---|---|---|---|
| Compile | 35 | 41 | 0 |
| Draw | 11 | 63 | 2 |
| Whole process | 3 | 66 | 7 |

The two draws that are slower on 1.2.0 are `uv` (0.0065 s to 0.0080 s) and `gpu_backend` (0.053 s to 0.061 s).
The gaps are 1.5 ms and 7 ms, so they can be noise.
The largest draw gain is `sapling` (0.045 s to 0.034 s).
The largest compile gains are `first_scene`, `faces`, `lamps`, `bricks`, `ripples` and `utah`, each 16% to 21% faster.
A compile runs once, and a draw is the fastest of three runs.
The seven slower whole-process times are gaps of 12 ms or less.

The source differs between the two columns, so this is a toolchain and port comparison, not a compiler-only one.
The port touches 56 library, example and benchmark files, with 113 lines added and 97 removed.
The changes include `__async def`, `std.hash` and the `Float64(String)` parse.
Mojo 1.2.0 also moves a few `std.math` results in the last bits, and the anatomy reports record the changed floats.

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

## Other CPU benches

The catalog compares ThreeMojo with three.js.
Anatomy, buildings, CARLA towns and the viewer stay outside it.
They have no matching three.js scene, or they need a fetched asset cache.
Every other CPU bench is named here.

| Program | Record | Measures |
|---|---|---|
| `bench/raster_bench.mojo` | This page | CPU and GPU raster time by image size |
| `bench/scene_bench.mojo` | This page | CPU renderer stages, one worker and every core |
| `bench/probe.mojo` | Previous-release table | A triangle fill with no ThreeMojo import |
| `bench/mojo10/probe.mojo` | Mojo 1.0 table | The same fill, built by Mojo 1.0 |
| `bench/noop.mojo` | Host baselines | A program that does nothing |
| `bench/animation_loop_bench.mojo` | [Animation](Animation) | Actions and the mixer |
| `bench/renderer_sort_bench.mojo` | [Renderer](Renderer) | Draw-list sort against the previous sort |
| `bench/image_decode.mojo` | [Image decode queue](Image-decode-queue) | glTF and CARLA image preload |
| `bench/periodic_remainder_bench.mojo` | [Math](Math#periodic-scalar-helpers) | Euclidean remainder and pingpong |
| `bench/exact_predicates_bench.mojo` | [Geometry](Geometry#convex-hull) | Exact orientation predicates |
| `bench/convex_hull_bench.mojo` | [Geometry](Geometry#convex-hull) | Ordinary convex hulls |
| `bench/ray_query_bench.mojo` | [Raycasting](Raycasting#bounds-query-precision-and-cost) | Ray bounds queries |
| `bench/ray_query_consumers.mojo` | [Raycasting](Raycasting#bounds-query-precision-and-cost) | Callers of those queries |
| `bench/physics_static_bench.mojo` | [Physics](Physics#static-primitive-index-design) | Static primitive sweep |
| `bench/physics_static_bvh.mojo` | [Physics](Physics#static-primitive-index-design) | Snapshot BVH experiment |
| `bench/physics_snapshot_bench.mojo` | [Physics query snapshots](Physics-query-snapshots) | Large snapshot capture and query |
| `bench/physics_snapshot_small_bench.mojo` | [Physics query snapshots](Physics-query-snapshots) | Small snapshot capture and query |
| `bench/physics_ccd_bench.mojo` | [Continuous collision](Continuous-collision#performance-and-verification) | Sphere and mesh steps |
| `bench/physics_ccd_index_bench.mojo` | [Continuous collision](Continuous-collision#performance-and-verification) | CCD triangle index |
| `bench/carla_force_restore_bench.mojo` | [Tick force restoration](Tick-force-restoration) | Force restore on a tick |
| `bench/carla_moving_supports_bench.mojo` | [CARLA physics](CARLA-physics#moving-supports) | Tires on moving supports |
| `bench/carla_model_cache_bench.mojo` | [CARLA assets](CARLA-assets) | Vehicle model cache |
| `bench/carla_sensor_cache_bench.mojo` | [CARLA rendering](CARLA-rendering#ground-truth-override-cache) | Semantic and depth capture cache |
| `bench/carla_lane_orientation_bench.mojo` | [CARLA lane orientation](CARLA-lane-orientation) | Lane heading correction |
| `bench/carla_road_fixed_s_bench.mojo` | [CARLA fixed-s nearest](CARLA-fixed-s-nearest) | Fixed-s nearest lane query |
| `bench/carla_segment_numerics_bench.mojo` | [CARLA maps](CARLA-maps) | Segment distance numerics |
| `bench/carla_search_queue_bench.mojo` | [CARLA agents](CARLA-agents) | Search queue operations |
| `bench/carla_route_search_bench.mojo` | [CARLA agents](CARLA-agents) | Complete route search |
| `bench/carla_navigation_budget_bench.mojo` | [CARLA agents](CARLA-agents) | Search budgets and heap bytes |
| `bench/carla_navigation_headroom_bench.mojo` | [CARLA agents](CARLA-agents) | Fixture search headroom |

The catalog comparison is `make bench-examples`.
`make bench` times raster sizes.
`make bench-scene` times renderer stages.
Those two Mac tables below are from the Apple M4 Max.
They are not from the Linux host above.

### On the Mac

`make bench` on the Apple M4 Max, one triangle, best of five runs. The GPU column includes allocation and the copy back:

| Size | CPU | GPU (Metal) |
|---|---|---|
| 320×240 | 0.3 ms | 17.6 ms |
| 640×480 | 1.2 ms | 19.0 ms |
| 1280×720 | 3.4 ms | 22.7 ms |
| 1920×1080 | 8.3 ms | 34.6 ms |
| 3840×2160 | 30.3 ms | 89.8 ms |

`make bench-scene` on the same Mac, the sphere of 12096 triangles at 1280×720:

| Workers | prepare | rasterize | resolve | frame |
|---|---|---|---|---|
| 1 | 1.9 ms | 82.7 ms | 8.9 ms | 96.8 ms |
| 16 | 1.9 ms | 9.1 ms | 1.0 ms | 15.4 ms |
