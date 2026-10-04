<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Fixture runtime baselines

The accepted sRGB table and all 13 VTK artifacts have an exact, verified
regeneration path. No accepted artifact or sRGB word changed for
[#497](https://github.com/SethKitchen/ThreeMojo/issues/497).
The original generation environments remain partly unknown.

## Verified environment

The verification on October 3, 2026 used Linux x64, Node 24.19.0 and
V8 13.6.233.17-node.51. It reused an existing dependency installation.
The complete observations are in
[`fixtures/runtime-2026-10-03.json`](fixtures/runtime-2026-10-03.json).

| Baseline | Exact dependencies | Node flags | Result |
| --- | --- | --- | --- |
| VTK | three 0.180.0; @xmldom/xmldom 0.9.12 | none | All 13 artifact hashes match |
| sRGB table | three 0.180.0 | `--no-use-std-math-pow` | All 256 Float64 words match |

These pins specify a verified current environment. They do not identify the
original environment. In particular, keep `three_version: null` for the
historical sRGB generator. Its current verified dependency is recorded in
`verified_runtime.dependencies` instead.

## Reproduce the accepted results

Use the exact Node release above on Linux x64. Start at the repository root.
The verifier rejects a different Node version, V8 version, platform or
architecture. It also rejects `NODE_OPTIONS` and a different installed
package version.

```sh
npm ci --ignore-scripts --prefix tools/fixture-runtime
python3 tools/fixture_manifest.py
python3 tools/fixture_runtime.py vtk
python3 tools/fixture_runtime.py js_number
```

`tools/fixture-runtime/package-lock.json` pins the package versions and npm
integrity values. The verifier supplies the recorded Node flags itself.
Use `--node /path/to/node` to select the pinned executable.
Use `--dependencies /path/to/node_modules` to reuse an existing exact install.
The verifier does not install packages.

Both generators run in temporary directories. The verifier compares outputs
with the accepted hashes or table words. It does not overwrite accepted files.

Exit status 0 means the requested accepted baseline matches. Exit status 1
means a comparison differs. Exit status 2 means a prerequisite or command
failed. The JSON report names every result that it checked.

Run these compiler-free regressions after changing the fixture tools:

```sh
python3 -m unittest discover -s tools -p 'test_fixture*.py'
```

The normal `make test-tools` target also discovers these regressions.
They check exact runtime and dependency pins, the lockfile, guarded commands,
the required pow flag, temporary output paths and separate snapshot provenance.
They do not require Node or a network connection. Fresh regeneration is a
separate check and requires the pinned runtime and installed dependencies.

## Why the pow flag matters

The installed Node 24.19.0 reports `--use-std-math-pow` as its default in
`node --v8-options`. The same executable and three.js package reproduce all
256 accepted words when `--no-use-std-math-pow` is supplied.
This controlled comparison establishes a working configuration. It does not
recover the historical Node, V8, three.js or build configuration.

For the recorded default-flag diagnostic, 30 of 256 Float64 words differ.
Each difference is one ULP. The report records each input byte, accepted word,
generated word and signed ULP difference. All 256 outputs narrow to the same
Float32 values for these two tables.

Float64 consumers still observe a compatibility difference. For byte 18, the
accepted word `0x3F78C6A940063D0E` formats as `0.0060488330203860696`.
The default-flag word `0x3F78C6A940063D0D` formats as `0.006048833020386069`.
`tests/test_js_number.mojo` already asserts the accepted text. The USDZ exporter
also serializes this table's Float64 values. Equal Float32 conversions do not
establish equal text output or equal downstream Float64 calculations.

To repeat the diagnostic without accepting a new table:

```sh
python3 tools/fixture_runtime.py js_number --diagnose-default-pow
```

This command reports `mode: diagnostic_only` and exits with status 1. It cannot
report a successful accepted-baseline verification, even if a future observed
configuration happens to produce equal words. Do not replace golden words
with its output. Review bit-level differences and affected compatibility tests
before any deliberate baseline migration.

## The separate V8-number snapshot

`assets/js_number/v8.json` is a number-format snapshot. The header of
`tests/test_js_number.mojo` says Node 22. It does not give an exact Node release
or V8 version. The original generator is not recorded.

Neither `srgb.mjs` nor the new verifier regenerates this snapshot. Its accepted
hash is checked for integrity only. The manifest records the known major
version, the unknown exact runtime and `status: not_regenerated`. A passing
sRGB check does not provide reproduction evidence for this file.

## Verification limits

The October 3 checks cover the two JavaScript generators and the fixture
metadata regressions. They do not claim new Mojo, full-suite, coverage or GPU
validation. The accepted Mojo source and fixture payloads are unchanged.
