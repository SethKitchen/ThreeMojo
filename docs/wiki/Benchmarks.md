# Benchmarks

This page records compile time, run time and peak memory for every example. The same scene, size and frame count run in three.js. A standalone probe compares Mojo 1.1 to Mojo 1.0.

The numbers come from one machine. Other machines differ. The refresh command is in [How to measure examples](How-to-measure-examples).

## Machine

<!-- BENCH:HOST -->
- Date: `2026-09-24`
- OS: Linux 6.18.33.1-microsoft-standard-WSL2
- CPU: AMD Ryzen 9 5900X 12-Core Processor
- Mojo 1.1: `Mojo 1.1.0 (8189361e)`
- Mojo 1.0: `Mojo 1.0.0 (ed45d567)`
- Node: `v22.14.0`
- three.js backends: `cpu-flat` and `webgl`
- A Mojo program that does nothing: `0.022` s
- A Node process that does nothing: `0.019` s
<!-- /BENCH:HOST -->

## What the columns measure

| Column | Meaning |
|---|---|
| compile | `mojo build`, in seconds. Paired in the 1.0 table. |
| run | The built binary or the Node process, whole, in seconds |
| frames | The draw loop alone, timed inside the Node process |
| RSS | Peak resident set of that run, in MiB |

Paired columns sit next to each other. Dark green is faster by 30% or more. Light green is faster by 10% to 30%. Yellow is within 10%. A cell with no color is the slower side, or a value with no pair.

ThreeMojo transforms, clips, lights, textures and composites every frame in linear light on the CPU. It encodes every frame into an APNG and writes the file.

`cpu-flat` fills the same triangles with each material's flat color and a depth test. It does no lighting, no textures, no sRGB and no transparency, and it writes no file. Most of that run is Node starting and importing three.js.

`webgl` is three.js drawing with WebGL 2. The context comes from `webgl-node`. It needs `libGLESv2` on the library path. See [How to measure examples](How-to-measure-examples).

Read a frames column against the ThreeMojo `run` column minus the Mojo baseline. The baselines under [Machine](#machine) say what each process costs before it draws.

The pin is Mojo 1.1. The 1.0 column is the same source built by Mojo 1.0.0. The probe is a standalone triangle fill that imports nothing from ThreeMojo.

## Example vs three.js

<!-- BENCH:EXAMPLES -->
| Example | Size | Frames | ThreeMojo compile (s) | ThreeMojo run (s) | cpu-flat run (s) | cpu-flat frames (s) | webgl run (s) | webgl frames (s) | ThreeMojo RSS (MiB) | cpu-flat RSS (MiB) | webgl RSS (MiB) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `triangle` | 320×240 | 1 | 4.674 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.029</strong></span> | 0.106 | 0.007 | 0.256 | 0.018 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>13.1</strong></span> | 62.9 | 148.3 |
| `spin` | 160×120 | 24 | 4.668 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.043</strong></span> | 0.105 | 0.007 | 0.265 | 0.035 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>20.6</strong></span> | 63.3 | 148.0 |
| `cube` | 240×180 | 36 | 6.339 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.095</strong></span> | 0.121 | 0.018 | 0.279 | 0.045 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>43.9</strong></span> | 63.3 | 150.4 |
| `cubes` | 260×200 | 48 | 17.646 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.204</strong></span> | 0.133 | 0.030 | 0.293 | 0.057 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>57.0</strong></span> | 64.8 | 150.5 |
| `uv` | 320×200 | 2 | 13.931 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.045</strong></span> | 0.113 | 0.010 | 0.253 | 0.021 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>15.4</strong></span> | 63.3 | 148.6 |
| `textured` | 260×200 | 36 | 17.842 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.216</strong></span> | 0.123 | 0.019 | 0.284 | 0.048 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>53.0</strong></span> | 63.2 | 150.2 |
| `glass` | 260×200 | 36 | 18.179 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.185</strong></span> | 0.128 | 0.024 | 0.286 | 0.053 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>49.9</strong></span> | 64.2 | 150.9 |
| `floor` | 320×200 | 30 | 17.750 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.235</strong></span> | 0.131 | 0.023 | 0.298 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.0</strong></span> | 63.7 | 150.1 |
| `photo` | 260×200 | 36 | 19.082 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.195</strong></span> | 0.123 | 0.020 | 0.279 | 0.049 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>50.2</strong></span> | 64.1 | 150.4 |
| `lamps` | 260×200 | 36 | 17.701 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.189</strong></span> | 0.142 | 0.039 | 0.288 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>49.4</strong></span> | 66.0 | 150.1 |
| `first_scene` | 320×240 | 1 | 17.796 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.033</strong></span> | 0.107 | 0.009 | 0.258 | 0.020 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>15.2</strong></span> | 63.7 | 148.8 |
| `lit_scene` | 320×240 | 36 | 17.718 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.240</strong></span> | 0.128 | 0.023 | 0.286 | 0.052 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>66.5</strong></span> | 63.4 | 150.5 |
| `rotations` | 240×180 | 36 | 17.615 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.159</strong></span> | 0.120 | 0.018 | 0.282 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.0</strong></span> | 64.2 | 150.3 |
| `ortho` | 240×180 | 36 | 17.573 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.164</strong></span> | 0.117 | 0.013 | 0.284 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.5</strong></span> | 64.0 | 150.5 |
| `geometry` | 240×180 | 36 | 17.523 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.190</strong></span> | 0.175 | 0.071 | 0.287 | 0.053 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.0</strong></span> | 66.1 | 149.9 |
| `instances` | 240×180 | 36 | 17.598 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.165</strong></span> | 0.135 | 0.032 | 0.280 | 0.048 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.8</strong></span> | 65.9 | 149.9 |
| `raycast` | 240×180 | 36 | 17.991 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.195</strong></span> | 0.153 | 0.051 | 0.295 | 0.059 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 67.8 | 160.2 |
| `curves` | 240×180 | 36 | 18.118 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.166</strong></span> | 0.133 | 0.027 | 0.285 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.9</strong></span> | 66.3 | 150.5 |
| `keyframes` | 240×180 | 36 | 19.094 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.157</strong></span> | 0.122 | 0.018 | 0.284 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.2</strong></span> | 63.6 | 150.4 |
| `skinning` | 240×180 | 36 | 18.010 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.164</strong></span> | 0.125 | 0.016 | 0.287 | 0.051 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.4</strong></span> | 63.9 | 150.7 |
| `phong` | 240×180 | 36 | 17.660 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.198</strong></span> | 0.152 | 0.046 | 0.281 | 0.049 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.3</strong></span> | 65.8 | 150.4 |
| `fog` | 240×180 | 36 | 17.540 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.157</strong></span> | 0.121 | 0.018 | 0.283 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 63.2 | 150.0 |
| `culling` | 240×180 | 36 | 17.540 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.155</strong></span> | 0.135 | 0.031 | 0.281 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.8</strong></span> | 64.6 | 150.4 |
| `clipping` | 240×180 | 36 | 17.751 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.164</strong></span> | 0.121 | 0.018 | 0.281 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.3</strong></span> | 62.9 | 150.2 |
| `gpu_backend` | 240×180 | 36 | 17.860 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.169</strong></span> | 0.135 | 0.032 | 0.281 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.9</strong></span> | 64.4 | 150.6 |
| `exposure` | 240×180 | 36 | 17.508 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.185</strong></span> | 0.118 | 0.017 | 0.280 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.7</strong></span> | 63.5 | 150.2 |
| `model` | 240×180 | 36 | 19.028 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.164</strong></span> | 0.123 | 0.018 | 0.277 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.1</strong></span> | 63.3 | 150.2 |
| `orbit` | 240×180 | 36 | 17.500 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.165</strong></span> | 0.123 | 0.019 | 0.280 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.1</strong></span> | 66.0 | 150.3 |
| `clock` | 240×180 | 36 | 17.652 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.164</strong></span> | 0.120 | 0.017 | 0.281 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.8</strong></span> | 63.2 | 150.2 |
| `chain` | 240×180 | 36 | 17.712 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.157</strong></span> | 0.121 | 0.017 | 0.287 | 0.050 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.8</strong></span> | 63.9 | 150.2 |
| `additive` | 240×180 | 36 | 17.469 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.182</strong></span> | 0.121 | 0.017 | 0.284 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.8</strong></span> | 63.4 | 150.4 |
| `normals` | 240×180 | 36 | 17.463 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.189</strong></span> | 0.145 | 0.042 | 0.283 | 0.045 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.6</strong></span> | 65.8 | 149.8 |
| `fragments` | 240×180 | 36 | 17.625 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.198</strong></span> | 0.129 | 0.026 | 0.281 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.9</strong></span> | 63.8 | 150.2 |
| `edges` | 240×180 | 48 | 4.717 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.135</strong></span> | 0.120 | 0.012 | 0.287 | 0.051 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>49.8</strong></span> | 63.8 | 149.4 |
| `lines` | 240×180 | 36 | 17.917 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.163</strong></span> | 0.128 | 0.020 | 0.285 | 0.051 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.3</strong></span> | 66.1 | 150.6 |
| `sprites` | 240×180 | 36 | 17.870 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.171</strong></span> | 0.133 | 0.028 | 0.290 | 0.054 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.8</strong></span> | 66.2 | 151.8 |
| `stereo` | 240×120 | 36 | 17.989 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.157</strong></span> | 0.126 | 0.023 | 0.282 | 0.048 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>34.0</strong></span> | 65.9 | 150.0 |
| `television` | 240×180 | 36 | 18.520 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.212</strong></span> | 0.121 | 0.016 | 0.282 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>49.1</strong></span> | 63.1 | 150.1 |
| `mirror` | 240×180 | 30 | 18.411 | 0.896 | 0.137 | 0.033 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.279</strong></span> | 0.043 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>41.2</strong></span> | 65.7 | 149.9 |
| `split` | 240×180 | 36 | 18.230 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.209</strong></span> | 0.135 | 0.031 | 0.285 | 0.048 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.9</strong></span> | 66.3 | 150.2 |
| `physical` | 480×220 | 1 | 17.700 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.142</strong></span> | 0.118 | 0.011 | 0.273 | 0.030 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>55.6</strong></span> | 64.1 | 157.5 |
| `outlines` | 240×180 | 36 | 18.461 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.161</strong></span> | 0.115 | 0.015 | 0.284 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>44.7</strong></span> | 63.6 | 149.8 |
| `shadows` | 240×180 | 36 | 18.023 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.216</strong></span> | 0.130 | 0.025 | 0.335 | 0.098 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>48.6</strong></span> | 63.6 | 154.0 |
| `wide` | 240×180 | 36 | 17.836 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.193</strong></span> | 0.137 | 0.035 | 0.290 | 0.054 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.6</strong></span> | 66.2 | 151.4 |
| `bloom` | 240×180 | 36 | 22.523 | 0.400 | 0.163 | 0.057 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.306</strong></span> | 0.061 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.6</strong></span> | 65.4 | 157.0 |
| `gizmo` | 240×180 | 36 | 19.128 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.187</strong></span> | 0.129 | 0.024 | 0.288 | 0.049 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.4</strong></span> | 65.7 | 150.6 |
| `json_scene` | 240×180 | 36 | 26.939 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.169</strong></span> | 0.118 | 0.016 | 0.279 | 0.047 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.1</strong></span> | 63.5 | 150.3 |
| `reloaded` | 240×180 | 36 | 26.673 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.217</strong></span> | 0.164 | 0.058 | 0.285 | 0.051 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.0</strong></span> | 66.1 | 150.3 |
| `gem` | 240×180 | 36 | 18.210 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.407</strong></span> | 0.146 | 0.041 | 0.511 | 0.273 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>51.3</strong></span> | 66.2 | 167.4 |
| `distance` | 240×180 | 36 | 17.264 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.196</strong></span> | 0.149 | 0.045 | 0.278 | 0.046 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.1</strong></span> | 66.2 | 150.2 |
| `unfogged` | 240×180 | 36 | 17.598 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.157</strong></span> | 0.121 | 0.016 | 0.289 | 0.055 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.1</strong></span> | 64.0 | 151.2 |
| `targets` | 240×180 | 36 | 17.570 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.266</span> | 0.146 | 0.040 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.283</span> | 0.049 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.3</strong></span> | 66.0 | 150.8 |
| `layers` | 320×180 | 36 | 19.164 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.327</span> | 0.162 | 0.057 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.319</span> | 0.072 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>59.5</strong></span> | 65.8 | 160.9 |
| `graph` | 240×180 | 36 | 19.204 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.231</strong></span> | 0.148 | 0.043 | 0.285 | 0.050 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>45.6</strong></span> | 66.3 | 150.8 |
| `basis` | 320×180 | 36 | 26.164 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.220</strong></span> | 0.121 | 0.014 | 0.289 | 0.053 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>53.9</strong></span> | 63.8 | 156.4 |
| `coats` | 320×180 | 36 | 19.188 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.324</span> | 0.168 | 0.058 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.307</span> | 0.067 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>53.5</strong></span> | 67.4 | 157.8 |
| `skyjson` | 240×180 | 36 | 33.182 | 0.772 | 0.140 | 0.036 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.357</strong></span> | 0.115 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>52.1</strong></span> | 65.9 | 158.7 |
| `daylight` | 240×180 | 36 | 31.520 | 1.880 | 0.215 | 0.111 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.291</strong></span> | 0.055 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.7</strong></span> | 65.9 | 150.9 |
| `faces` | 240×180 | 36 | 23.667 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.174</strong></span> | 0.128 | 0.022 | 0.293 | 0.051 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.1</strong></span> | 63.9 | 156.0 |
| `utah` | 240×180 | 36 | 25.512 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.265</strong></span> | 0.229 | 0.074 | 0.348 | 0.053 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>47.8</strong></span> | 67.4 | 156.6 |
| `blobs` | 240×180 | 36 | 39.910 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.172</strong></span> | 0.262 | 0.114 | 0.362 | 0.073 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>46.3</strong></span> | 68.4 | 153.2 |

The `cpu-flat` columns fill the same triangles with each material's flat color and a depth test.
That fill does no lighting, no textures, no sRGB and no transparency, and it writes no file.
The `webgl` columns are three.js drawing with WebGL 2 through `webgl-node`.
Read a frames column against the ThreeMojo `run` column minus the Mojo baseline.
<!-- /BENCH:EXAMPLES -->

## Mojo 1.1 against Mojo 1.0

<!-- BENCH:MOJO10 -->
| Program | 1.1 compile (s) | 1.0 compile (s) | 1.1 run (s) | 1.0 run (s) | 1.1 RSS (MiB) | 1.0 RSS (MiB) |
|---|---|---|---|---|---|---|
| `probe` | 3.312 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>2.743</strong></span> | 0.055 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.048</strong></span> | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>12.8</strong></span> | 14.4 |
| `triangle` | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>4.674</strong></span> | 7.797 | 0.029 | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>0.020</strong></span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">13.1</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">13.4</span> |
| `spin` | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>4.668</strong></span> | 8.349 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.043</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.039</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">20.6</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">21.0</span> |
| `cube` | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>6.339</strong></span> | 9.144 | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.095</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">0.102</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">43.9</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">44.0</span> |
| `cubes` | 17.646 | 5.676 | 0.204 | refused | 57.0 | — |
| `uv` | 13.931 | 4.967 | 0.045 | refused | 15.4 | — |
| `textured` | 17.842 | 5.638 | 0.216 | refused | 53.0 | — |
| `glass` | 18.179 | 5.625 | 0.185 | refused | 49.9 | — |
| `floor` | 17.750 | 5.837 | 0.235 | refused | 45.0 | — |
| `photo` | 19.082 | 5.992 | 0.195 | refused | 50.2 | — |
| `lamps` | 17.701 | 5.589 | 0.189 | refused | 49.4 | — |
| `first_scene` | 17.796 | 5.567 | 0.033 | refused | 15.2 | — |
| `lit_scene` | 17.718 | 5.598 | 0.240 | refused | 66.5 | — |
| `rotations` | 17.615 | 5.604 | 0.159 | refused | 45.0 | — |
| `ortho` | 17.573 | 5.656 | 0.164 | refused | 46.5 | — |
| `geometry` | 17.523 | 5.522 | 0.190 | refused | 47.0 | — |
| `instances` | 17.598 | 5.589 | 0.165 | refused | 44.8 | — |
| `raycast` | 17.991 | 5.710 | 0.195 | refused | 45.8 | — |
| `curves` | 18.118 | 5.870 | 0.166 | refused | 45.9 | — |
| `keyframes` | 19.094 | 5.999 | 0.157 | refused | 45.2 | — |
| `skinning` | 18.010 | 5.654 | 0.164 | refused | 45.4 | — |
| `phong` | 17.660 | 5.551 | 0.198 | refused | 45.3 | — |
| `fog` | 17.540 | 5.585 | 0.157 | refused | 45.7 | — |
| `culling` | 17.540 | 5.568 | 0.155 | refused | 44.8 | — |
| `clipping` | 17.751 | 5.616 | 0.164 | refused | 46.3 | — |
| `gpu_backend` | 17.860 | 5.647 | 0.169 | refused | 45.9 | — |
| `exposure` | 17.508 | 5.550 | 0.185 | refused | 45.7 | — |
| `model` | 19.028 | 5.768 | 0.164 | refused | 46.1 | — |
| `orbit` | 17.500 | 5.572 | 0.165 | refused | 47.1 | — |
| `clock` | 17.652 | 5.591 | 0.164 | refused | 44.8 | — |
| `chain` | 17.712 | 5.620 | 0.157 | refused | 44.8 | — |
| `additive` | 17.469 | 5.607 | 0.182 | refused | 45.8 | — |
| `normals` | 17.463 | 5.577 | 0.189 | refused | 45.6 | — |
| `fragments` | 17.625 | 5.516 | 0.198 | refused | 44.9 | — |
| `edges` | <span style="background-color:#14532d;color:#ffffff;padding:0 0.4em"><strong>4.717</strong></span> | 8.302 | 0.135 | <span style="background-color:#86efac;color:#14532d;padding:0 0.4em"><strong>0.122</strong></span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">49.8</span> | <span style="background-color:#fde047;color:#422006;padding:0 0.4em">50.2</span> |
| `lines` | 17.917 | 5.599 | 0.163 | refused | 46.3 | — |
| `sprites` | 17.870 | 5.542 | 0.171 | refused | 44.8 | — |
| `stereo` | 17.989 | 5.660 | 0.157 | refused | 34.0 | — |
| `television` | 18.520 | 5.673 | 0.212 | refused | 49.1 | — |
| `mirror` | 18.411 | 5.704 | 0.896 | refused | 41.2 | — |
| `split` | 18.230 | 5.707 | 0.209 | refused | 45.9 | — |
| `physical` | 17.700 | 5.479 | 0.142 | refused | 55.6 | — |
| `outlines` | 18.461 | 5.915 | 0.161 | refused | 44.7 | — |
| `shadows` | 18.023 | 5.675 | 0.216 | refused | 48.6 | — |
| `wide` | 17.836 | 5.638 | 0.193 | refused | 47.6 | — |
| `bloom` | 22.523 | 6.964 | 0.400 | refused | 47.6 | — |
| `gizmo` | 19.128 | 6.041 | 0.187 | refused | 47.4 | — |
| `json_scene` | 26.939 | 7.952 | 0.169 | refused | 45.1 | — |
| `reloaded` | 26.673 | 8.252 | 0.217 | refused | 47.0 | — |
| `gem` | 18.210 | 5.613 | 0.407 | refused | 51.3 | — |
| `distance` | 17.264 | 5.544 | 0.196 | refused | 46.1 | — |
| `unfogged` | 17.598 | 5.629 | 0.157 | refused | 45.1 | — |
| `targets` | 17.570 | 5.592 | 0.266 | refused | 46.3 | — |
| `layers` | 19.164 | 6.071 | 0.327 | refused | 59.5 | — |
| `graph` | 19.204 | 6.240 | 0.231 | refused | 45.6 | — |
| `basis` | 26.164 | 9.989 | 0.220 | refused | 53.9 | — |
| `coats` | 19.188 | 6.228 | 0.324 | refused | 53.5 | — |
| `skyjson` | 33.182 | 9.511 | 0.772 | refused | 52.1 | — |
| `daylight` | 31.520 | 9.457 | 1.880 | refused | 46.7 | — |
| `faces` | 23.667 | 7.707 | 0.174 | refused | 46.1 | — |
| `utah` | 25.512 | 8.843 | 0.265 | refused | 47.8 | — |
| `blobs` | 39.910 | 12.346 | 0.172 | refused | 46.3 | — |
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
