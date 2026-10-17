# Streamline probe

`probe.cpp` runs the DLSS Super Resolution and DLSS Ray Reconstruction plugins of NVIDIA Streamline on a real GPU. It checks what `extensions/streamline/` claims. [Streamline](../../wiki/Streamline.md) says where each claim is used.

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

The probe does not call `slEvaluateFeature`. It does not tag a buffer or set the constants. It says nothing about image quality, about the sign of the jitter, or about the range of the clip depth.

## Run it again

1. Unpack `streamline-sdk-v2.14.16.zip` from the [Streamline release](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16) into an empty folder.
2. Set `STREAMLINE_SDK` to that folder.
3. Run `build.bat` in this folder, from a developer prompt.
4. Run `out\probe.exe`.

The probe loads the NVIDIA DLLs that the SDK ships. This repository does not hold them.
