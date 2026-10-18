<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Threat model

The scanner reads this file before it starts. It is for Anthropic's OSS Scanner.

## What this project does and where untrusted input enters

- ThreeMojo is a 3D graphics library written in Mojo. It ports three.js. It renders scenes on the CPU and writes PNG files.
- Untrusted input enters through the file loaders in `loaders/`. A loader reads bytes or text and builds geometry, materials, images, animations or fonts. Assume that an attacker controls every byte.
- The loaders read these formats: OBJ, MTL, STL, PLY, glTF and GLB, FBX, COLLADA, 3DS, LWO, LDraw, AMF, 3MF, KMZ, Draco, meshopt, SVG, TTF, BVH, MDD, MD2, PCD, PDB, NRRD, IES, LUT files, G-code, Gaussian-splat formats, HDR and other image formats, and JSON.
- KMZ and 3MF are zip containers. Compressed input can be a decompression bomb.
- A hostile mesh can also reach the rasterizers in `render/` and `renderers/` after a loader builds it. Examples are indices that point outside a vertex buffer, huge counts, and NaN or infinite values.
- The caller of the library is trusted. The caller supplies scene code, sizes and typed parameters.

## Components that matter most / least

- Most important: everything in `loaders/`, the decoders it uses, and the buffer and geometry types in `core/` and `geometries/` that a loader fills.
- Most important: any code that uses `UnsafePointer`, `bitcast` or `external_call`. Safe Mojo code cannot read outside a buffer without a bounds error. Unsafe code can.
- Less important: `exporters/`. They write files from objects that the program built. They do not parse untrusted bytes.
- Less important: `extensions/` (CARLA, humanoid, anatomy, water, physics and others). They take typed parameters from the caller and data files from `assets/`. The repository ships the data files, so they are trusted. An extension that parses a file or a network message is in scope.
- Out of scope: `tests/`, `bench/`, `examples/`, `docs/`, `out/`, `coverage/` (the coverage tool) and `tools/` (developer tools, including the Python helpers). The files in `tests/compile_fail/` must not compile. That is their purpose.
- The GPU backend (`render/gpu.mojo` and MAX) cannot run in a scan: there is no GPU, and the image does not install MAX. The CPU and GPU rasterizers share their arithmetic, so a bug in that arithmetic is still in scope.
- The project supports Linux, macOS on Apple Silicon, and Windows through WSL 2. WSL 2 runs the Linux code. The scan runs on Linux (x86-64 or aarch64). The library code is the same on every platform. The macOS-only branches are in `bench/` and `tools/`, which are out of scope, and in the Metal path of the GPU backend, which cannot run in a scan.

## How to exercise it

- The toolchain is `/src/.venv/bin/mojo`. It is Mojo 1.1.0. The pin is exact. Do not install another version.
- Run one suite from `/src` with `.venv/bin/mojo run -I . tests/test_obj.mojo`. The `-I .` flag is required. The suites for the loaders are `tests/test_obj.mojo`, `tests/test_stl.mojo`, `tests/test_ply.mojo` and `tests/test_json.mojo`. Read them to see how to call a loader.
- To test a loader, write a small program with a `main()` that passes hostile bytes to it. Build it with `.venv/bin/mojo build -I . --sanitize address`.
- Do not run `make check`. It takes hours. Each single test must finish in 5 seconds or less.
- The scan has no network. All the toolchain files are in the image.

## How you rate severity

- Critical: a write outside a buffer that the attacker controls, reachable from a crafted file or buffer in a loader or decoder.
- High: any other memory-safety violation reachable from a crafted file or buffer. This includes an out-of-bounds read, a use after free, an uninitialized read, and an integer overflow that leads to one of them.
- Medium: a denial of service from a small input. This includes unbounded memory use, a decompression bomb, an infinite loop, and a crash or abort where the loader should raise an error.
- Low: wrong output for a valid input that has no security effect.
- A loader must raise an error on malformed input. It must not crash, hang or read outside its input.

## Anything to leave alone

- Do not report a loader that raises an error on malformed input. That is the correct behavior.
- Do not report differences from three.js, or differences of one unit in a pixel value between platforms.
- Do not report slow rendering of a huge but valid scene. The caller chooses the scene size.
- Do not report code style, missing docstrings or formatting. The project's own checks cover them.
- Do not report a bug that exists only in the Mojo compiler or standard library. Report the ThreeMojo input that triggers it.
- A patch must follow `CLAUDE.md`. Write American English. Give each public symbol a docstring with `Args`, `Returns` and `Raises`. Use unit types such as `Length` and `Angle`, not bare numbers. Add a regression test in `tests/` that runs in 5 seconds or less and covers each new branch.
