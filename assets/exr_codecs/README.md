# OpenEXR codec reference fixtures

These fixtures check issue #615 against OpenEXR 3.1.5 and Imath 3.1.5.
They target three.js r180 for PXR24 and DWA, and r186 for B44 and B44A.
The library decoder has no OpenEXR, Python, C++ or JavaScript runtime dependency.
These tools are only for fixture generation and independent checks.

## Contents

- `reference.cpp` generates 45 scanline images and decodes their RGBA samples with OpenEXR.
- `variants.py` constructs 20 DWA variants and requires the native OpenEXR decoder to accept each one.
- `package_fixtures.py` converts the native files and decoded samples to UTF-8 hex.
- `manifest.json` records dimensions, channels, `pLinear`, chunk sizes, raw fallbacks, hashes and compression loss.
- Each `.exr.hex` is one complete file. Its `.exr.rgba.hex` contains little-endian Float32 RGBA samples, from the top row.
- `compare_three.mjs` runs the unmodified loader and records both successful results and upstream counterexamples.
- `three180-results.json` and `three186-results.json` contain those independent results.

## Image matrix

The name `cN_sM` identifies compression code N and shape M.
Every compression code from 5 through 9 has every shape.

| Shape | Channels and dimensions | Purpose |
|---|---|---|
| 0 | Half RGBA, 9 by 35; DWAB is 9 by 257 | DCT/block edges and final strips |
| 1 | Float RGBA, same dimensions | Float paths and lossless DWA alpha |
| 2 | Half A/Y, 11 by 17, pLinear true | Linear grayscale and ignored alpha |
| 3 | Float A/Y, 11 by 17 | Nonlinear grayscale |
| 4 | Half RGBA, 16 by 32, constant | DC-only DWA and B44A three-byte flat blocks |
| 5 | Half RGBA, 17 by 17, pLinear true | Perceptual transfer flags and partial blocks |
| 6 | Half RGBA, 1 by 1 | Raw fallback |
| 7 | Mixed types, 8 by 8 | Float alpha/red, half green/blue, UINT id, float depth, another RGB layer |
| 8 | Half RGBA, shape 0 dimensions, sharp pattern | Lossy stress and DCT rounding |

Every non-fallback DWA feature case has a compressed first chunk.
Shape 8 DWAA can fall back to raw storage; its DWAB counterpart exercises compressed high-frequency data.
B44 and B44A preserve float channels without compression.
The manifest distinguishes these valid raw cases from compressed fixtures.

The DWA variants cover DEFLATE AC, versions zero and one, case-insensitive rules, repeated CSC assignments, pure UNKNOWN, and pure RLE.
An uppercase serialized insensitive rule tests native suffix matching.
Incomplete CSC candidates retain their independent UNKNOWN or RLE scheme.
The ordinary files contain version-two rules and static-Huffman AC.
The version-zero variant replaces end-of-block markers with explicit zero runs.
All variants are independently decoded before packaging.

## Error bounds

The Mojo tests compare every decoded sample with the independent OpenEXR output.
PXR24, B44 and B44A must be exact.
DWA color allows `abs(actual-reference) <= 0.003 * max(1, abs(reference))`.
DWA alpha and the pure UNKNOWN/RLE variants must be exact.
The largest observed DWA scaled difference is 0.002521009.

The threshold was selected before the first decoder comparison.
It is an absolute limit of 0.003 at reference magnitudes up to one.
Above one, it is a relative limit of 0.3 percent.
It is a fixture regression budget, not a universal arithmetic error bound.

The test also records the distance between ordered half representations.
That distance counts representable half steps, with positive and negative zero treated as the same value.
The maximum observed distance is three steps, in `c9_s8`.
Every other current fixture is exact against its native decoded oracle.
The scaled budget is not equivalent to a fixed half-ULP budget.

OpenEXR's scalar and SIMD inverse DCT paths use different Float32 operation orders.
Small differences can cross a half-rounding boundary before the nonlinear lookup.
The lookup can amplify a one-step difference, followed by another half rounding.

For nonlinear magnitudes from two to four, one half step is `1/512`.
The exponential branch changes relatively by approximately `exp(2.2/512)-1 = 0.004306` for that step.
Thus even one intermediate half step can exceed the fixture budget at other magnitudes.
The decoder does not clamp those differences to satisfy the test.

The optional `dct-precision.json` probe compares OpenEXR's own scalar, SSE2 and AVX helpers on 20,000 deterministic coefficient blocks.
It also applies the native half-to-half transfer table.
The largest measured post-transfer differences are 0.004480 for SSE2 and 0.004910 for AVX.
These are sampled official-helper differences, not full EXR results or worst-case bounds.
The exact coefficient counterexample and both intermediate outputs are recorded.

Compression loss is different from decoder error.
The generator records original sample values before writing each image.
The manifest compares those values with OpenEXR's decoded output.
These fixture maxima are measurements, not general quality guarantees:

| Codec | Maximum source error divided by max(1, abs(source)) |
|---|---|
| PXR24 | 0.000014429 |
| B44 | 0.331243 |
| B44A | 0.331243 |
| DWAA, default level 45 | 0.013749 |
| DWAB, default level 45 | 0.021678 |

## three.js differences

The comparison uses `FloatType` and reverses three.js's output rows.
Its comparison threshold is `0.004 * max(1, abs(reference))` for rounding differences.
Upstream mismatches and exceptions remain in the JSON results.
They do not replace the OpenEXR reference.

The uniform-type RGB fixtures pass for their target revisions.
Reproducible counterexamples include mixed sample widths and ignored UINT channels.
DWA also differs on linear grayscale, float grayscale, unknown-channel streams and legacy block versions.
The DEFLATE AC path uses an incorrect compressed length in both pinned JavaScript revisions.
The Mojo implementation uses the native reference layout and validates those lengths.
The repeated-rule variant verifies that all CSC assignments survive subsequent matching rules.

## Regeneration

Use Linux, a C++14 compiler, CMake, zlib development files, Python 3 and Node.js.
Run these commands from the repository root.
Use a temporary directory outside the checkout for all downloaded and binary files.

```sh
REF=/absolute/temporary/exr-reference
mkdir -p "$REF"
curl -L https://codeload.github.com/AcademySoftwareFoundation/openexr/tar.gz/refs/tags/v3.1.5 -o "$REF/openexr-3.1.5.tar.gz"
curl -L https://codeload.github.com/AcademySoftwareFoundation/Imath/tar.gz/refs/tags/v3.1.5 -o "$REF/Imath-3.1.5.tar.gz"
(cd "$REF" && printf '%s\n' \
  '93925805c1fc4f8162b35f0ae109c4a75344e6decae5a240afdfce25f8a433ec  openexr-3.1.5.tar.gz' \
  '1e9c7c94797cf7b7e61908aed1f80a331088cc7d8873318f70376e4aed5f25fb  Imath-3.1.5.tar.gz' | sha256sum -c -)
tar -xzf "$REF/openexr-3.1.5.tar.gz" -C "$REF"
tar -xzf "$REF/Imath-3.1.5.tar.gz" -C "$REF"
cmake -S "$REF/Imath-3.1.5" -B "$REF/imath-build" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DPYTHON=OFF \
  -DCMAKE_INSTALL_PREFIX="$REF/install"
cmake --build "$REF/imath-build" -j2
cmake --install "$REF/imath-build"
cmake -S "$REF/openexr-3.1.5" -B "$REF/openexr-build" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DOPENEXR_BUILD_TOOLS=OFF \
  -DCMAKE_PREFIX_PATH="$REF/install" -DCMAKE_INSTALL_PREFIX="$REF/install" \
  '-DCMAKE_CXX_FLAGS=-include cstdint'
cmake --build "$REF/openexr-build" -j2
cmake --install "$REF/openexr-build"
g++ -std=c++14 -O2 -include cstdint \
  -I"$REF/install/include" -I"$REF/install/include/Imath" \
  -L"$REF/install/lib" -Wl,-rpath,"$REF/install/lib" \
  assets/exr_codecs/reference.cpp -lOpenEXR-3_1 -lImath-3_1 -o "$REF/reference"
mkdir -p "$REF/fixtures"
export LD_LIBRARY_PATH="$REF/install/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$REF/reference" generate "$REF/fixtures"
python3 assets/exr_codecs/variants.py "$REF/reference" \
  "$REF/install/lib/libOpenEXR-3_1.so" "$REF/fixtures"
python3 assets/exr_codecs/package_fixtures.py "$REF/fixtures"
npm install --prefix "$REF/js180" --save-exact three@0.180.0
npm install --prefix "$REF/js186" --save-exact three@0.186.0
node assets/exr_codecs/compare_three.mjs "$REF/js180/node_modules/three" \
  180 assets/exr_codecs/three180-results.json
node assets/exr_codecs/compare_three.mjs "$REF/js186/node_modules/three" \
  186 assets/exr_codecs/three186-results.json
mojo build --Werror -I . tests/test_exr_codecs.mojo -o "$REF/test_exr_codecs"
python3 tools/run_suite.py --seconds 5 --suite tests/test_exr_codecs.mojo \
  -- "$REF/test_exr_codecs"
```

The forced `cstdint` include supports newer C++ standard libraries without modifying the pinned OpenEXR source.
The reference executable has a compile-time exact-version check.
The variants tool uses the pinned library's native Huffman decoder on trusted generated input only.
The Mojo tests never call it.

The focused checks do not replace the final full coverage and aggregate gates.

## Optional DCT precision probe

Use an x86-64 Linux CPU with AVX support.
This probe calls the official SIMD helpers directly.
It does not invoke or replace the Mojo fixture tests.
Run it after the reference build above.

```sh
g++ -std=c++14 -O3 -DNDEBUG -fPIC -shared \
  assets/exr_codecs/dct_helpers.cpp -o "$REF/dct_helpers.so" \
  -I"$REF/openexr-3.1.5/src/lib/OpenEXR" \
  -I"$REF/openexr-build/src/lib/OpenEXR" -I"$REF/openexr-build/cmake" \
  -I"$REF/install/include/OpenEXR" -I"$REF/install/include/Imath" \
  -L"$REF/install/lib" -lImath-3_1 -Wl,-rpath,"$REF/install/lib"
python3 assets/exr_codecs/check_dct_precision.py "$REF/dct_helpers.so" \
  "$REF/openexr-3.1.5" assets/exr_codecs/dct-precision.json
```

The deterministic generator uses seed 615 and 64 half-rounded coefficients per block.
Each coefficient comes from a uniform distribution on `[-2, 2]`.
The pre-half metric uses the same scaled denominator as the fixture tests.
The results are sensitive to compiler and CPU arithmetic paths.
