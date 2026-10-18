# Streamline probe

`probe.cpp`, `evaluate.cpp` and `evaluate_frames.cpp` run the DLSS Super Resolution and DLSS Ray Reconstruction plugins of NVIDIA Streamline on a real GPU. They check what `extensions/streamline/` claims. [Streamline](../../wiki/Streamline.md) says where each claim is used.

## What it ran on

| Item | Value |
|---|---|
| Streamline | 2.14.16 (`sl.interposer`, `sl.dlss`, `sl.dlss_d`, development build) |
| GPU | NVIDIA TITAN RTX (Turing) |
| Driver | 610.88 |
| OS | Windows 11, build 26200 |
| API | Direct3D 12, manual hooking |

## What it showed

- `slIsFeatureSupported` returned `eOk` for both features. `slGetFeatureRequirements` listed the buffer types 0, 1, 3 and 4 for both: the depth, the motion vectors, the scaling input color and the scaling output color.
- `slDLSSGetOptimalSettings` and `slDLSSDGetOptimalSettings` gave the same answer in every case. They answer for Performance, Balanced, Quality, Ultra Performance and DLAA. For Off and for Ultra Quality they return `eErrorInvalidParameter` (25).
- The Quality, Balanced, Performance and Ultra Performance ratios are 2/3, 0.58, 1/2 and 1/3 of each side, rounded to the nearest pixel. The smallest size is half the output side for Quality, Balanced and Performance, and 0.99 of it for DLAA. The largest size is the output. For Ultra Performance, the smallest and the largest size are the optimal size.
- `slDLSSSetOptions` and `slDLSSDSetOptions` accept every mode and preset number. They check nothing.
- `sizeof(sl::DLSSOptions)` is 88 and `sizeof(sl::DLSSDOptions)` is 224. Their members lie in the order of the headers.

`result.tsv` holds the sizes, `result.txt` the whole output.

## What it did not show

No program moves the camera. The depth run tests the content that moves, not the camera.

## The evaluate runs

`evaluate.cpp` calls `slEvaluateFeature` on a synthetic scene. The scene is a sum of sinusoids that the render grid cannot hold without jitter. Each frame samples it at the render pixel centers plus a known Halton offset. The program passes the offset to DLSS with each of four sign choices, and measures the error against the true image after 48 frames. Then it moves the scene, and passes the motion vectors with each of two signs.

| Choice | Error (MSE) |
|---|---|
| `jitterOffset` is the negative of the applied offset | 0.023 |
| The three other sign choices | 0.052 to 0.082 |
| No `jitterOffset` | 0.046 |
| Bilinear upscale of one render | 0.044 |
| Motion vector points to the last position | 0.040 |
| The opposite motion vector | 0.060 |
| No motion vectors | 0.061 |

The offset is in render pixels, with x across and y down. The motion vector is in render pixels with `mvecScale` of one over the render size.

`evaluate_frames.cpp` closes the loop with ThreeMojo's code. `mojo run -I . examples/streamline.mojo --frames DIR` renders 24 jittered frames with `JitteredCamera`. It takes the jitter for Streamline from `frame_constants`. The program feeds the frames to DLSS Balanced, 278 by 157 to 480 by 270, for 72 frames. The error is against the full-size render.

| Source | Error (MSE) |
|---|---|
| DLSS, jitter as `frame_constants` gives it | 0.0021 |
| The CPU fallback, `SpatialUpscaler` | 0.0037 |
| DLSS, no jitter given | 0.0039 |
| DLSS, the opposite sign | 0.0061 |

The results are in `evaluate_result.txt` and `evaluate_frames_result.txt`.

`evaluate_depth.cpp` tests the depth. A disc with its own texture circles in front of a static background, and DLSS gets the same frames with five depths. The error is near the disc's edge, where the disc uncovers the background.

| Depth | Error, whole frame | Error near the edge |
|---|---|---|
| 0 to 1, nearer smaller | 0.00406 | 0.0227 |
| -1 to 1, nearer smaller | 0.00406 | 0.0227 |
| One value everywhere | 0.00428 | 0.0225 |
| Nearer larger, `depthInverted` false | 0.00454 | 0.0266 |
| 0 to 1, nearer smaller, `depthInverted` true | 0.00454 | 0.0266 |

The range does not matter: a depth of -1 to 1 gave the same result as 0 to 1. The sense does. With `depthInverted` false, nearer must be smaller. The effect is small in this scene, and the edge error of the correct depth equals that of a flat depth. The whole-frame error orders the three cases.

## Run it again

1. Unpack `streamline-sdk-v2.14.16.zip` from the [Streamline release](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16) into an empty folder.
2. Set `STREAMLINE_SDK` to that folder.
3. Run `build.bat` in this folder, from a developer prompt.
4. Run `out\probe.exe`, `out\evaluate.exe` and `out\evaluate_depth.exe`.
5. Write the frames with the Mojo example, then run `out\evaluate_frames.exe FRAMES OUTDIR`.

The programs load the NVIDIA DLLs that the SDK ships. This repository does not hold them.
