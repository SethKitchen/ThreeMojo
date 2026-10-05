<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Raw ASTC reference validation

The raw decoder matches the independent Arm astcenc 5.3.0 reference on
all legal 4x4 and 6x6 block modes. The stored expected results are hex
text. They require no external library during the Mojo test run.

## Reference pin

- Repository: https://github.com/ARM-software/astc-encoder
- Version: 5.3.0
- Commit: `30aabb3f42406df45a910d8496f9bee17eeba9bb`
- Source archive: https://github.com/ARM-software/astc-encoder/archive/refs/tags/5.3.0.tar.gz
- Archive SHA-256: `6bd248f460b90576f90a5499c0f6b8d785b3af3837bcab82607d9a3b5bba77e2`
- License: Apache-2.0; see `THIRD-PARTY-NOTICES.md`

The adapter uses the public decoder and block-information API. It does
not use ThreeMojo to generate expected results. It requests UNORM8 for
UNORM and sRGB, and FP16 for SFLOAT. It runs the reference C backend.

## Reproduce the fixtures

Run from the repository root. Use a temporary directory outside the
repository for the downloaded source and compiled reference.

```sh
work=$(mktemp -d)
curl -L --fail https://github.com/ARM-software/astc-encoder/archive/refs/tags/5.3.0.tar.gz -o "$work/source.tar.gz"
echo '6bd248f460b90576f90a5499c0f6b8d785b3af3837bcab82607d9a3b5bba77e2  source.tar.gz' | (cd "$work" && sha256sum -c -)
tar -xzf "$work/source.tar.gz" -C "$work"
src="$work/astc-encoder-5.3.0/Source"
g++ -std=c++14 -O2 -fPIC -shared -DASTCENC_ISA_NONE \
  -DASTCENC_SSE=0 -DASTCENC_AVX=0 -DASTCENC_NEON=0 -I"$src" \
  tools/references/astc_reference.cpp "$src"/astcenc_*.cpp \
  -o "$work/libastc_reference.so"
python3 tools/references/generate_astc.py "$work/libastc_reference.so" \
  "$work/raw_astc_reference.txt"
cmp "$work/raw_astc_reference.txt" assets/ktx2/raw_astc_reference.txt
cmp "$work/raw_astc_reference.json" assets/ktx2/raw_astc_reference.json
cmp "$work/raw_astc_invalid.txt" assets/ktx2/raw_astc_invalid.txt
```

Validation used Python 3.12.14 and GCC 14.2.0. The generator uses a fixed
seed, 617180, and integer random bit streams. The reference source and
adapter determine the expected decoded texels.

## Coverage and tolerances

The generator visits every 11-bit block mode with one luminance
partition. This uses the minimum endpoint budget. Extra partitions or
larger endpoint modes cannot make an invalid weight layout legal. It
then examines 120,000 seeded random blocks for each footprint and keeps
blocks that add mode, endpoint, grid, quantization or dual-plane coverage.

- 4x4: 145 legal block modes, 309 source blocks, 629 profile records
- 6x6: 370 legal block modes, 755 source blocks, 1,523 profile records
- All sixteen endpoint modes and all one-to-four partition counts
- All four dual-plane component selectors
- LDR, HDR and constant blocks, LDR alpha and HDR alpha
- UNORM rounding boundaries, HDR subnormals, negative constants, and 65,504
- 8,192 independently rejected malformed blocks

`raw_astc_reference.json` lists the observed grids, endpoint ranges,
weight ranges and complete block-mode sets. The expected file SHA-256 is
`b25a042bc72e82f58bea9760f6be43a8029ccc0183333312b63688273963d5db`.

The Mojo test requires exact byte and half-bit equality. Its tolerance is
zero. This is a software decode contract, not a claim that every GPU uses
the same allowed decode precision. HDR endpoints in LDR formats,
nonfinite HDR constants and malformed blocks raise errors. The reference
uses error colors for some of these cases.

`tests/test_astc.mojo` checks all six KTX2 formats, cropped edges,
three mip levels, six faces, two layers and Zstandard. It also checks raw
HDR alpha, transfer mismatches, truncation and allocation guards. Existing Basis fixture
hashes and BC/ETC/EAC tests remain unchanged.
