# Benchmarks

This page records CPU compile time, draw time and peak memory for `bench/catalog.json`.
The same size and frame count run in three.js.
Mojo 1.0 is compared when that compiler is installed.

The draw column names the faster frame loop.
Whole-process time is summarized, because startup can hide the draw.
Displayed times are rounded.
The results file keeps the full sample.

## Who wins

Draw time is the frame loop inside the process.
A gap under 10% is a tie.
A gap of 30% or more is a large win.

cpu-flat fills triangles with a flat color and a depth test.
It does no lighting, no textures and no file write, so it is not the language comparison.

WebGL is three.js drawing with WebGL 2.
That draw is the language comparison.

<!-- BENCH:SCORE:linux -->
### Linux

This file has no ThreeMojo draw times.
The draw winner stays blank until the next measurement.

ThreeMojo uses less memory on 61 of 61 examples.
The median resident set is 46 MiB for ThreeMojo and 150 MiB for WebGL.

Whole-process time includes startup and writing the image.
The median ThreeMojo process takes 0.19 s.
The median WebGL process takes 0.28 s.
A Mojo program that does nothing takes 0.022 s.
A Node process that does nothing takes 0.019 s.
The median Mojo 1.1 compile takes 17.8 s.

Mojo 1.0 runs 5 programs.
Refused programs: 57.
A refused compile is not a faster compile.
On those programs, Mojo 1.1 compiles faster on 4 of 5.
Mojo 1.0 compiles faster on 1 of 5.

Mojo 1.0 runs faster on 3 of 5.
2 runs are within 10%.

The catalog lists 76 examples.
This host measures 61 of them.
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
The median Mojo 1.1 compile takes 8.79 s.

Mojo 1.0 runs 5 programs.
Refused programs: 57.
A refused compile is not a faster compile.
On those programs, Mojo 1.1 compiles faster on 5 of 5.

Mojo 1.1 runs faster on 4 of 5.
1 run is within 10%.

The catalog lists 76 examples.
This host measures 61 of them.
<!-- /BENCH:SCORE:macos -->

## Linux against macOS

<!-- BENCH:CROSS -->
The macOS host runs the shared examples a median of 3.0 times faster than the Linux host.
It compiles them a median of 2.0 times faster.
The Linux date is 2026-09-24. The macOS date is 2026-09-26.
The source can differ between those dates.
The comparison uses 61 shared examples.
<!-- /BENCH:CROSS -->

## Machines

### Linux

<!-- BENCH:HOST:linux -->
- Latest refresh: `2026-09-24`
- OS: Linux 6.18.33.1-microsoft-standard-WSL2
- CPU: AMD Ryzen 9 5900X 12-Core Processor
- Mojo 1.1: `Mojo 1.1.0 (8189361e)`
- Mojo 1.0: `Mojo 1.0.0 (ed45d567)`
- Node: `v22.14.0`
- three.js backends: `cpu-flat` and `webgl`
- A Mojo program that does nothing: `0.022` s
- A Node process that does nothing: `0.019` s
<!-- /BENCH:HOST:linux -->

### macOS

<!-- BENCH:HOST:macos -->
- Latest refresh: `2026-09-26`
- OS: macOS 26.7 (arm64)
- CPU: Apple M4 Max, 16 cores
- Mojo 1.1: `Mojo 1.1.0 (8189361e)`
- Mojo 1.0: `Mojo 1.0.0 (ed45d567)`
- Node: `v24.20.0`
- three.js backends: `cpu-flat` and `webgl`
- A Mojo program that does nothing: `0.010` s
- A Node process that does nothing: `0.023` s
<!-- /BENCH:HOST:macos -->

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
| `triangle` | 320×240 | 1 | 4.67 | — | 0.007 | 0.018 | — | 13 | unknown (legacy: 2026-09-24) |
| `spin` | 160×120 | 24 | 4.67 | — | 0.007 | 0.035 | — | 21 | unknown (legacy: 2026-09-24) |
| `cube` | 240×180 | 36 | 6.34 | — | 0.018 | 0.045 | — | 44 | unknown (legacy: 2026-09-24) |
| `cubes` | 260×200 | 48 | 17.6 | — | 0.030 | 0.057 | — | 57 | unknown (legacy: 2026-09-24) |
| `uv` | 320×200 | 2 | 13.9 | — | 0.010 | 0.021 | — | 15 | unknown (legacy: 2026-09-24) |
| `textured` | 260×200 | 36 | 17.8 | — | 0.019 | 0.048 | — | 53 | unknown (legacy: 2026-09-24) |
| `glass` | 260×200 | 36 | 18.2 | — | 0.024 | 0.053 | — | 50 | unknown (legacy: 2026-09-24) |
| `floor` | 320×200 | 30 | 17.7 | — | 0.023 | 0.047 | — | 45 | unknown (legacy: 2026-09-24) |
| `photo` | 260×200 | 36 | 19.1 | — | 0.020 | 0.049 | — | 50 | unknown (legacy: 2026-09-24) |
| `lamps` | 260×200 | 36 | 17.7 | — | 0.039 | 0.047 | — | 49 | unknown (legacy: 2026-09-24) |
| `first_scene` | 320×240 | 1 | 17.8 | — | 0.009 | 0.020 | — | 15 | unknown (legacy: 2026-09-24) |
| `lit_scene` | 320×240 | 36 | 17.7 | — | 0.023 | 0.052 | — | 67 | unknown (legacy: 2026-09-24) |
| `rotations` | 240×180 | 36 | 17.6 | — | 0.018 | 0.046 | — | 45 | unknown (legacy: 2026-09-24) |
| `ortho` | 240×180 | 36 | 17.6 | — | 0.013 | 0.046 | — | 47 | unknown (legacy: 2026-09-24) |
| `geometry` | 240×180 | 36 | 17.5 | — | 0.071 | 0.053 | — | 47 | unknown (legacy: 2026-09-24) |
| `instances` | 240×180 | 36 | 17.6 | — | 0.032 | 0.048 | — | 45 | unknown (legacy: 2026-09-24) |
| `raycast` | 240×180 | 36 | 18.0 | — | 0.051 | 0.059 | — | 46 | unknown (legacy: 2026-09-24) |
| `curves` | 240×180 | 36 | 18.1 | — | 0.027 | 0.047 | — | 46 | unknown (legacy: 2026-09-24) |
| `keyframes` | 240×180 | 36 | 19.1 | — | 0.018 | 0.047 | — | 45 | unknown (legacy: 2026-09-24) |
| `skinning` | 240×180 | 36 | 18.0 | — | 0.016 | 0.051 | — | 45 | unknown (legacy: 2026-09-24) |
| `phong` | 240×180 | 36 | 17.7 | — | 0.046 | 0.049 | — | 45 | unknown (legacy: 2026-09-24) |
| `fog` | 240×180 | 36 | 17.5 | — | 0.018 | 0.047 | — | 46 | unknown (legacy: 2026-09-24) |
| `culling` | 240×180 | 36 | 17.5 | — | 0.031 | 0.047 | — | 45 | unknown (legacy: 2026-09-24) |
| `clipping` | 240×180 | 36 | 17.8 | — | 0.018 | 0.046 | — | 46 | unknown (legacy: 2026-09-24) |
| `gpu_backend` | 240×180 | 36 | 17.9 | — | 0.032 | 0.046 | — | 46 | unknown (legacy: 2026-09-24) |
| `exposure` | 240×180 | 36 | 17.5 | — | 0.017 | 0.047 | — | 46 | unknown (legacy: 2026-09-24) |
| `model` | 240×180 | 36 | 19.0 | — | 0.018 | 0.047 | — | 46 | unknown (legacy: 2026-09-24) |
| `orbit` | 240×180 | 36 | 17.5 | — | 0.019 | 0.047 | — | 47 | unknown (legacy: 2026-09-24) |
| `clock` | 240×180 | 36 | 17.7 | — | 0.017 | 0.046 | — | 45 | unknown (legacy: 2026-09-24) |
| `chain` | 240×180 | 36 | 17.7 | — | 0.017 | 0.050 | — | 45 | unknown (legacy: 2026-09-24) |
| `additive` | 240×180 | 36 | 17.5 | — | 0.017 | 0.047 | — | 46 | unknown (legacy: 2026-09-24) |
| `normals` | 240×180 | 36 | 17.5 | — | 0.042 | 0.045 | — | 46 | unknown (legacy: 2026-09-24) |
| `fragments` | 240×180 | 36 | 17.6 | — | 0.026 | 0.047 | — | 45 | unknown (legacy: 2026-09-24) |
| `edges` | 240×180 | 48 | 4.72 | — | 0.012 | 0.051 | — | 50 | unknown (legacy: 2026-09-24) |
| `lines` | 240×180 | 36 | 17.9 | — | 0.020 | 0.051 | — | 46 | unknown (legacy: 2026-09-24) |
| `sprites` | 240×180 | 36 | 17.9 | — | 0.028 | 0.054 | — | 45 | unknown (legacy: 2026-09-24) |
| `stereo` | 240×120 | 36 | 18.0 | — | 0.023 | 0.048 | — | 34 | unknown (legacy: 2026-09-24) |
| `television` | 240×180 | 36 | 18.5 | — | 0.016 | 0.047 | — | 49 | unknown (legacy: 2026-09-24) |
| `mirror` | 240×180 | 30 | 18.4 | — | 0.033 | 0.043 | — | 41 | unknown (legacy: 2026-09-24) |
| `split` | 240×180 | 36 | 18.2 | — | 0.031 | 0.048 | — | 46 | unknown (legacy: 2026-09-24) |
| `physical` | 480×220 | 1 | 17.7 | — | 0.011 | 0.030 | — | 56 | unknown (legacy: 2026-09-24) |
| `outlines` | 240×180 | 36 | 18.5 | — | 0.015 | 0.046 | — | 45 | unknown (legacy: 2026-09-24) |
| `shadows` | 240×180 | 36 | 18.0 | — | 0.025 | 0.098 | — | 49 | unknown (legacy: 2026-09-24) |
| `wide` | 240×180 | 36 | 17.8 | — | 0.035 | 0.054 | — | 48 | unknown (legacy: 2026-09-24) |
| `bloom` | 240×180 | 36 | 22.5 | — | 0.057 | 0.061 | — | 48 | unknown (legacy: 2026-09-24) |
| `gizmo` | 240×180 | 36 | 19.1 | — | 0.024 | 0.049 | — | 47 | unknown (legacy: 2026-09-24) |
| `json_scene` | 240×180 | 36 | 26.9 | — | 0.016 | 0.047 | — | 45 | unknown (legacy: 2026-09-24) |
| `reloaded` | 240×180 | 36 | 26.7 | — | 0.058 | 0.051 | — | 47 | unknown (legacy: 2026-09-24) |
| `gem` | 240×180 | 36 | 18.2 | — | 0.041 | 0.27 | — | 51 | unknown (legacy: 2026-09-24) |
| `distance` | 240×180 | 36 | 17.3 | — | 0.045 | 0.046 | — | 46 | unknown (legacy: 2026-09-24) |
| `unfogged` | 240×180 | 36 | 17.6 | — | 0.016 | 0.055 | — | 45 | unknown (legacy: 2026-09-24) |
| `targets` | 240×180 | 36 | 17.6 | — | 0.040 | 0.049 | — | 46 | unknown (legacy: 2026-09-24) |
| `layers` | 320×180 | 36 | 19.2 | — | 0.057 | 0.072 | — | 59 | unknown (legacy: 2026-09-24) |
| `graph` | 240×180 | 36 | 19.2 | — | 0.043 | 0.050 | — | 46 | unknown (legacy: 2026-09-24) |
| `basis` | 320×180 | 36 | 26.2 | — | 0.014 | 0.053 | — | 54 | unknown (legacy: 2026-09-24) |
| `coats` | 320×180 | 36 | 19.2 | — | 0.058 | 0.067 | — | 53 | unknown (legacy: 2026-09-24) |
| `skyjson` | 240×180 | 36 | 33.2 | — | 0.036 | 0.12 | — | 52 | unknown (legacy: 2026-09-24) |
| `daylight` | 240×180 | 36 | 31.5 | — | 0.11 | 0.055 | — | 47 | unknown (legacy: 2026-09-24) |
| `faces` | 240×180 | 36 | 23.7 | — | 0.022 | 0.051 | — | 46 | unknown (legacy: 2026-09-24) |
| `utah` | 240×180 | 36 | 25.5 | — | 0.074 | 0.053 | — | 48 | unknown (legacy: 2026-09-24) |
| `blobs` | 240×180 | 36 | 39.9 | — | 0.11 | 0.073 | — | 46 | unknown (legacy: 2026-09-24) |

A legacy date is from an older aggregate file; its per-row measurement date is unknown.

Draw time is the frame loop inside the process.
A gap under 10% is a tie.
cpu-flat is a flat color fill with a depth test.
WebGL is the three.js draw used for the language comparison.
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

## Mojo 1.1 against Mojo 1.0

The table lists only programs both compilers run.
A refused compile is not a faster compile.

### Linux

<!-- BENCH:MOJO10:linux -->
| Program | 1.1 compile (s) | 1.0 compile (s) | Compile winner | 1.1 run (s) | 1.0 run (s) | Run winner |
|---|---|---|---|---|---|---|
| `probe` | 3.31 | 2.74 | 1.0 | 0.055 | 0.048 | 1.0 |
| `triangle` | 4.67 | 7.80 | 1.1 | 0.029 | 0.020 | 1.0 |
| `spin` | 4.67 | 8.35 | 1.1 | 0.043 | 0.039 | tie |
| `cube` | 6.34 | 9.14 | 1.1 | 0.095 | 0.10 | tie |
| `edges` | 4.72 | 8.30 | 1.1 | 0.14 | 0.12 | 1.0 |

Programs in this table: 5.
Refused catalog rows: 57.
A refused compile is not a faster compile.
Those rows stay out of this table.
<!-- /BENCH:MOJO10:linux -->

### macOS

<!-- BENCH:MOJO10:macos -->
| Program | 1.1 compile (s) | 1.0 compile (s) | Compile winner | 1.1 run (s) | 1.0 run (s) | Run winner |
|---|---|---|---|---|---|---|
| `probe` | 0.34 | 3.19 | 1.1 | 0.025 | 0.029 | 1.1 |
| `triangle` | 1.39 | 6.53 | 1.1 | 0.012 | 0.011 | tie |
| `spin` | 1.37 | 6.65 | 1.1 | 0.014 | 0.018 | 1.1 |
| `cube` | 2.33 | 7.65 | 1.1 | 0.026 | 0.034 | 1.1 |
| `edges` | 1.30 | 6.25 | 1.1 | 0.030 | 0.042 | 1.1 |

Programs in this table: 5.
Refused catalog rows: 57.
A refused compile is not a faster compile.
Those rows stay out of this table.
<!-- /BENCH:MOJO10:macos -->

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
| `bench/probe.mojo` | Mojo 1.1 table | A triangle fill with no ThreeMojo import |
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
