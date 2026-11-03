# Streamline

`extensions/streamline/` runs NVIDIA's DLSS 4.5 Super Resolution and Ray Reconstruction on ThreeMojo's frames. A Mojo program writes the frames, and a small Windows program, the native host, runs them through `sl.interposer` on an RTX GPU. In WSL 2 the Mojo program starts the host directly. See [The native host](#the-native-host).

The package types and checks everything that Streamline reads, builds the per-frame constants from a ThreeMojo camera, and checks the buffers of a frame. It also has an upscaler trait with a CPU fallback for every other machine. See [Extensions](Extensions).

The values follow the Streamline 2.14.16 headers `sl_dlss.h`, `sl_dlss_d.h` and `sl_consts.h`, and its programming guides for [DLSS Super Resolution](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS.md) and [DLSS Ray Reconstruction](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_RR.md).

## What is here and what is not

| Part | State |
|---|---|
| Modes, presets and buffer kinds as types | Done |
| Options of both features, with checks | Done |
| Render size, jitter and the check of Streamline's reply | Done |
| Per-frame constants from two cameras | Done |
| Check of the tagged buffers of a frame | Done |
| `Upscaler` trait and the `SpatialUpscaler` fallback | Done |
| The frames for the native host, and its result | Done |
| Loading `sl.interposer` and calling `slEvaluateFeature` | Done, on Windows with Direct3D 12, see [the native host](#the-native-host) |

## Call it

This example plans a Balanced 4K frame with the DLSS 4.5 model, checks its buffers, and builds the constants.

```mojo
from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from extensions.streamline.constants import CameraSnapshot, frame_constants
from extensions.streamline.jitter import jitter_offset, jitter_phase_count
from extensions.streamline.kinds import (
    BUFFER_DEPTH,
    BUFFER_INPUT_COLOR,
    BUFFER_MOTION_VECTORS,
    BUFFER_OUTPUT_COLOR,
    MODE_BALANCED,
    MOTION_PIXELS,
    SR_PRESET_M,
)
from extensions.streamline.options import SuperResolutionOptions
from extensions.streamline.sizing import FrameSize, estimated_render_size
from extensions.streamline.tags import TaggedBuffer, check_super_resolution_tags
from math.vector3 import Vector3
from units.si import DEGREE, METER, Angle, Length

var output = FrameSize(3840, 2160)
var options = SuperResolutionOptions(MODE_BALANCED, output.width, output.height)
options.use_dlss_4_5(SR_PRESET_M)
var render = estimated_render_size(options.mode, output)

var tags = List[TaggedBuffer]()
tags.append(TaggedBuffer(BUFFER_DEPTH, render.width, render.height, 1, False))
tags.append(TaggedBuffer(BUFFER_MOTION_VECTORS, render.width, render.height, 2, False))
tags.append(TaggedBuffer(BUFFER_INPUT_COLOR, render.width, render.height, 4, False))
tags.append(TaggedBuffer(BUFFER_OUTPUT_COLOR, output.width, output.height, 4, False))
check_super_resolution_tags(options, render, tags)

var camera = PerspectiveCamera(
    Angle(50.0, DEGREE), 16.0 / 9.0, Length(0.1, METER), Length(100.0, METER)
)
camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
var now = CameraSnapshot(camera, Scene())
camera.place(Vector3(0.1, 0, 5), Vector3(0.1, 0, 0))
var before = CameraSnapshot(camera, Scene())
var phases = jitter_phase_count(render, output)
var constants = frame_constants(
    now, before, render, jitter_offset(7, phases), MOTION_PIXELS, False
)
```

Every check raises an `Error` that names the field. The example runs on the pinned toolchain.

## Modes and presets

`UpscaleMode`, `SuperResolutionPreset`, `DenoiserPreset` and `NormalRoughnessMode` carry the numbers of `sl::DLSSMode`, `sl::DLSSPreset`, `sl::DLSSDPreset` and `sl::DLSSDNormalRoughnessMode`. Each has `is_valid`. A binding can pass the number on as it is.

| Feature | Type | Valid values | DLSS 4.5 model |
|---|---|---|---|
| Both | `UpscaleMode` | 0 to 6: off, performance, balanced, quality, ultra performance, ultra quality, DLAA | |
| Super Resolution | `SuperResolutionPreset` | default, and E to O | `SR_PRESET_L` and `SR_PRESET_M` |
| Ray Reconstruction | `DenoiserPreset` | default, and D to O | `RR_PRESET_F` |

Streamline removed the presets A to D of Super Resolution and A to C of Ray Reconstruction. Their numbers are not valid. Streamline replaces some presets by the default model. `reverts_to_default` says which.

DLSS 4.5 is the second-generation transformer model. NVIDIA names its Super Resolution presets M and L. Streamline's header calls Ray Reconstruction preset F "the latest and default transformer model". The headers do not name a DLSS version, so `is_dlss_4_5` records that mapping and nothing more.

`use_dlss_4_5` on either options type sets the preset of every mode at once. Super Resolution takes L, which is sharper, or M, which is closer in speed to the first-generation model.

## Options

`SuperResolutionOptions` is `sl::DLSSOptions`, and `RayReconstructionOptions` is `sl::DLSSDOptions`. The fields keep Streamline's order and defaults. `check_super_resolution` and `check_ray_reconstruction` refuse what no Streamline call can use:

- A mode, a preset or a normal and roughness mode that is not valid.
- An output side of zero, or one that does not fit the `uint32_t` field.
- A pre-exposure or an exposure scale that is not finite and positive.
- For Ray Reconstruction, a view matrix that is not finite, or two view matrices that are not inverses.

## Render size

`estimated_render_size` gives the size to plan an allocation with before a device exists. It uses NVIDIA's published ratios, rounded to the nearest pixel. A 4K output gives 2560 by 1440 in Quality, 2227 by 1253 in Balanced and 1920 by 1080 in Performance. A scale of one keeps the side, including one past 2^53.

`estimated_optimal_settings` also gives the range that dynamic resolution can use. The smallest size is half the output in Quality, Balanced and Performance, and 0.99 of it in DLAA. The largest size is the output. Ultra Performance has one size.

Streamline answers for five modes. For Off and for Ultra Quality it returns `eErrorInvalidParameter`, although `sl_dlss.h` lists both. `UpscaleMode.has_optimal_settings` says which modes answer. `render_scale` and `estimated_optimal_settings` refuse Ultra Quality.

The size that `slDLSSGetOptimalSettings` returns is the size to render at. `OptimalSettings` holds that reply. `check_optimal_settings` refuses a reply that cannot be right. `check_render_size` says whether the size of a dynamic-resolution frame lies in the range that DLSS accepts.

## Jitter

DLSS needs a camera moved by a fraction of a pixel each frame. `jitter_offset` gives the Halton offsets in bases two and three, less a half, in render pixels. They are the offsets that `JitteredCamera` takes.

`jitter_phase_count` gives eight samples for every output pixel that one render pixel covers. That is this port's rule. Streamline requires no count. A count that does not fit in an integer is refused.

Streamline does not say which way its `jitterOffset` points. A running `sl.dlss` answered. The `jitterOffset` is the negative of the offset that `JitteredCamera` takes, in render pixels, with x across and y down. `frame_constants` negates the offset that it gets.

## Constants

`frame_constants` builds `sl::Constants` from two `CameraSnapshot` values: this frame's camera and the last frame's. It follows `sl_consts.h`:

- `clip_to_prev_clip` takes a point from this frame's clip space to the last frame's. Only the camera moves. `prev_clip_to_clip` is its inverse.
- None of the four matrices carries the jitter. Take the snapshot before the camera is jittered.
- The camera's position and axes are in world space. The field of view is vertical. `reset` says that the last frame is unrelated, and then the last camera is ignored.
- `mvec_scale` is one and one for `MOTION_NORMALIZED`, and one over the render size for `MOTION_PIXELS`.
- The matrices have Streamline's layout. `sl::float4x4` is row-major and multiplies a row vector. A `Matrix4` is column-major and multiplies a column vector. Both hold the same sixteen floats in memory. A binding copies `Matrix4.elements` with no transpose. A test checks this against the order of `matrixMul` in `sl_matrix_helpers.h`.

ThreeMojo's velocity buffer holds the clip position of this frame less the last, in normalized device coordinates, with y up. DLSS reads the way back to the last position, in render pixels, with y down. `streamline_motion_vector` converts one to the other. Tag such vectors with `mvec_scale` of one over the render size.

## Tagged buffers

`check_super_resolution_tags` and `check_ray_reconstruction_tags` ask what the programming guides ask of a frame, and name the buffer that fails.

| Feature | Needs |
|---|---|
| Super Resolution | Depth, motion vectors and input color at the render size. Output color at the output size. |
| Ray Reconstruction | Noisy input color, motion vectors, diffuse albedo, specular albedo and output color. Depth or linear depth. Normals and roughness. Specular motion vectors or specular hit distance. |

The exposure is optional for both. Ray Reconstruction takes two buffers for the normals and the roughness in the unpacked mode, and one `BUFFER_NORMAL_ROUGHNESS` in the packed mode.

Each buffer must have the size of its kind, the number of channels that the guides give, and, for an albedo, a linear encoding. A kind that the feature does not read is accepted. Integrations tag one set of buffers for every feature.

## The fallback upscaler

`Upscaler` is the trait a program draws through. `SpatialUpscaler` implements it on the CPU with the EASU and RCAS passes of [FSR1](Post-processing). It runs where DLSS cannot.

It is not DLSS. It reads the color only, so it adds no detail that the render lacks. It does not denoise, so `supports` is false for Ray Reconstruction. A program that wants a denoised path-traced frame without DLSS must denoise it first with the passes in [Post-processing](Post-processing). A render or an output whose pixel count does not fit in an integer is refused.

`examples/streamline.mojo` shows the fallback. It renders a scene at the Balanced render size. It puts three images side by side. The first is the render, stretched with the nearest texel. The second is the same render through `SpatialUpscaler`. The third is the scene rendered at the output size.

A row of magnified crops sits below. Run it with `mojo run -I . examples/streamline.mojo out/streamline.png`. The gallery list names it, but no image of it is tracked.

## The native host

Streamline runs on Windows with Direct3D or Vulkan. ThreeMojo's GPU backend is MAX, which opens neither. So the binding is a separate Windows program, `extensions/streamline/native/host.cpp`. It reads a bundle of frames, opens a Direct3D 12 device on the first NVIDIA adapter, loads `sl.interposer` with manual hooking, and plays the frames. For each frame it uploads the buffers, tags them, sets the constants and calls `slEvaluateFeature`. It writes the last output frame back.

### Build the host

You need Windows, Visual Studio 2022 and an RTX GPU.

1. Run `extensions\streamline\native\build.bat` from the repository root.
2. The script downloads the Streamline SDK 2.14.16 from NVIDIA's GitHub release into `.cache\streamline`, and checks its SHA-256. To use an SDK that you unpacked yourself, set `STREAMLINE_SDK` to its folder first.
3. The script puts `threemojo_streamline.exe` and NVIDIA's signed DLLs in `.cache\streamline\bin`.

NVIDIA's license covers the SDK and the DLLs. This repository does not hold them.

### Write the frames

`FrameBundle` in `extensions/streamline/bundle.mojo` holds the options of one feature and its frames. Start it with `SuperResolutionOptions` or `RayReconstructionOptions` and the render size. Then call `add` once for each frame, with the `FrameConstants` of `frame_constants` and a `BufferData` for each buffer that the frame tags. `add` runs the checks of the options, the constants and the tags, so the host gets nothing that Streamline refuses. Do not pass the output color. The host makes it.

`passes` plays the frames more than once, so the history fills. The frame that comes back is the last frame of the last pass.

The host reads `encode()` and writes a result that `decode_result` reads:

```sh
threemojo_streamline.exe FRAMES RESULT
```

A path of `-` is the standard input or the standard output. Use the pipes from WSL 2. A file on the other side of the WSL 2 file bridge reads at about 16 MB/s, and a pipe is ten times faster. The host writes a report of its stages to the standard error. The exit status is 0 on success, 1 for a wrong command line, 2 for a bundle that cannot be read, 3 when Streamline refuses, and 4 for a Direct3D error.

The file is little-endian, with four bytes for each field. The docstring of `bundle.mojo` gives the layout.

### Compare it with the fallback

`tests/test_streamline_native.mojo` runs both features through the host on an analytic scene: a floor of 0.25 meter tiles under a sky. One render cannot hold the distant tiles. The true image is the mean of 16 samples in each output pixel. Set `THREEMOJO_STREAMLINE_HOST` to the host's path to run the tests. On a machine without the host, they return at once.

The scene is rendered at 186 by 104, the Balanced size for 320 by 180, with 24 jitter phases.

| Feature | Input | DLSS error (MSE) | `SpatialUpscaler` error (MSE) |
|---|---|---|---|
| Super Resolution, preset M | 24 clean renders, played 3 times | 0.0063 | 0.0283 |
| Ray Reconstruction, preset F | 24 renders with noise from 0 to 2 in the light, with the albedo, the normals and the roughness, played 2 times | 0.0041 | 0.1105 |

The run was on an NVIDIA TITAN RTX with driver 610.88, on Windows 11. A run of the host takes about 3.4 seconds. Of that, `slInit` takes 1.3 seconds and `slSetD3DDevice` 1.3 seconds. The 72 frames take 0.13 seconds.

NGX starts `nvngx_update.exe`. A child process inherits the standard handles unless they are marked otherwise. Then it holds the caller's pipes open for seconds after the host ends. The host marks its standard handles as not inheritable before it loads Streamline.

## Checked against DLSS

The [Streamline harness](https://github.com/SethKitchen/ThreeMojo/tree/d58766390fa97aadc6addf7782a2378373fcb080/docs/validation/streamline) runs `sl.dlss` and `sl.dlss_d` of Streamline 2.14.16 through Direct3D 12. It ran on an NVIDIA TITAN RTX with driver 610.88. Its README says how to run it again.

| Claim | Result |
|---|---|
| Both features run on a Turing GPU | Yes, `slIsFeatureSupported` returned `eOk` |
| The buffers each feature requires | Depth, motion vectors, input color and output color |
| The render size of each mode | The estimates match at five output sizes |
| The range of the render size | Matches `estimated_optimal_settings` |
| Off and Ultra Quality | `eErrorInvalidParameter` |
| The sign of the jitter | `jitterOffset` is the negative of the `JitteredCamera` offset |
| The direction of a motion vector | It points to where the content was in the last frame |
| The depth that DLSS reads | Nearer is smaller when `depthInverted` is false. A range of -1 to 1 gives the same result as 0 to 1 |
| ThreeMojo's frames through DLSS | Error 0.0021, against 0.0037 for the fallback |
| The layout of an options struct | Members lie in the order of the headers |

Three more programs call `slEvaluateFeature`. One uses a synthetic scene to settle the signs. One feeds the frames of `examples/streamline.mojo --frames` to DLSS. One tests five encodings of the depth. The README in that folder has the numbers.

The tests keep the answers of the plugin. `test_the_estimate_matches_the_running_plugin` holds twenty-five of them.

## Differences from Streamline

- The mode and the output size have no default. Streamline's defaults, `eOff` and an invalid size, cannot run.
- The `sharpness` field and the axes of the on-screen indicator are not carried. Super Resolution deprecates the sharpness. Ray Reconstruction ignores it.
- A `Bool` is always true or false. Streamline's `Boolean` has a third value, `eInvalid`.
- An exposure that is not positive is refused. The headers do not say so.
- `Feature`, `BufferKind` and `MotionVectorSpace` are this port's numbering. `Feature.streamline_id` and `BufferKind.streamline_type` give the number of `sl::Feature` and of `sl::BufferType`.
