<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Converted face and hair assets

`FaceModel` reads ICTF version 6. `HairStyleFile` reads THRS version 1.
Both formats use little-endian numbers. These readers check external converted
input before they expose its arrays. A converter name or a file extension does
not make input trusted. This contract covers file construction, not later
changes to the public model storage.

## Read and allocation limits

ICTF has a 64-byte header. The complete layout declared by that header must fit
in 64 MiB, including the header. Every count except the expression-byte count
must be at most 1,048,576. The limits below also apply:

- Model vertices, drawn vertices, kept vertices and followers: 65,536 each
- Identity modes and expressions: 1,024 each
- Moved vertices in one expression: 65,536
- Expression bytes: 64 MiB minus 64 bytes

The reader checks all header limits before it multiplies counts or requests a
body read. These bounds keep all offset arithmetic in range. The byte limit
also bounds the sum of the sections. Decoded arrays use more memory than their
packed input. The limit is a per-model input bound, not a process memory quota.

THRS has a 20-byte header. It permits 1 through 65,536 strands and 2 through
256 points per strand. Their product must be at most 1,048,576. The reader
checks these counts before multiplication and reads only the declared body
plus one byte. It refuses both truncation and trailing bytes.

The largest
supported packed file is 6,684,692 bytes. The root and offset arrays contain at
most 1,114,112 vectors in total.

Both readers refuse unknown versions before a body read. No malformed count
can request an unbounded read or an unbounded array allocation.

## Values and index domains

ICTF requires finite positions, texture coordinates and follower weights.
Both formats require finite quantization scales in the inclusive range from
zero through the Float32 representation of 1e30. Zero permits a constant
shape or strand. This bound keeps every decoded signed-byte or signed-short
product finite. THRS root components are signed shorts divided by 32,767;
they cannot encode NaN or infinity. Degenerate roots remain supported.

ICTF checks these index domains:

- Drawn-position indices and expression vertices name model vertices
- Drawn triangles name drawn vertices
- Skin triangles, skin edges, hole corners, coarse triangles and kept
  vertices name the first 11,248 model vertices, or all vertices in a smaller
  model
- Coarse edges and follower corners name entries in the kept-vertex array

Kept vertices must be unique. Every coarse-triangle and hole-corner vertex
must occur in the kept array. This prevents a downstream coarse remap from
producing a missing-index sentinel. Kept and follower counts cannot exceed
the skin vertex count. Each hole needs at least three corners. Hole lengths must sum to the declared
corner count.

The file provides two weights for every follower and three corners for it.

Expression records must occupy exactly their declared section. The reader
checks each record's aligned byte spans, moved-vertex count, index domain and
scale. Identity records have one scale and three signed bytes per model
vertex, with four-byte padding. These checks do not certify manifold topology
or the result of arbitrary later morph weights and geometry operations.

## Partial ICTF reads

`FaceModel(path, identities, expressions)` retains its partial-read API.
A neutral model can omit all expressions and identity modes. All header
counts and the complete declared layout are still bounded. Every loaded
geometry section is checked. Expressions crossed to reach identity data are
checked even when the caller does not request expression arrays.

An unrequested tail is not read or certified. A prefix-only load can succeed
when that tail is truncated or contains invalid values. ICTF ignores bytes
after the complete declared layout. Use a full load to check all declared
sections. Do not use a successful prefix load as proof of a valid whole file.

## Asset evidence and reproduction

`assets/converted-asset-manifest.json` pins a recipe that reproduces all three
bundled production assets byte for byte. It records each upstream filename,
immutable commit, Git blob checksum, SHA-256 and byte count. It also records
the converter source hashes, format versions, transformation parameters and
license evidence. This proves an exact recipe. It does not establish the
original historical command log. The
[verification record](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/converted-assets-303.json)
records output hashes, source counts and focused checks.

The production inputs are:

- ICT FaceKit Light at `da5f95a607f5e6b37755b38d3385d7f2853732e5`:
  the neutral OBJ, 57 expression OBJs and identity OBJs 000 through 059
- Frostbitten Hair WebGPU at `4478dd129525ff7db92978178b55f760716cbd72`:
  `static/models/SintelHairOriginal-sintel_hair.16points.tfx`
- AMD TressFX 4.1 at `6957058e29dceb25a0c2a82849bb892f3d9fbce5`:
  `bin/Objects/HairAsset/Ratboy/Ratboy_mohawk.tfx`

The manifest lists all 120 converter inputs individually. It also pins five
upstream license or context files. Only the listed input files reach the
converters. Extra files in a cache cannot add expressions to the face model.

The ICT Light inputs use MIT. Sintel's model uses CC-BY-3.0; the repository's
MIT software license does not replace the model license. Ratboy uses MIT.
See `THIRD-PARTY-NOTICES.md` for attribution and source links.

### Run the small offline check

```sh
python3 tools/check_converted_asset_manifest.py
```

This checks local hashes and the complete provenance metadata. It also
regenerates three small original fixtures from `assets/converted-fixtures/`.
The check never accesses the network. It does not read or regenerate the
large production inputs. `--require-source-pins` remains an accepted option;
complete source pins are now required in the default check too.

### Reproduce all production outputs

Choose a cache directory outside the repository. The first command downloads
only missing pinned files. The input data uses about 306 MB of storage.
The scratch copy needs at least that much additional space. Conversion can
take several minutes. Ordinary tests do not perform this download or run.

```sh
python3 tools/check_converted_asset_manifest.py --source-cache /path/to/converted-sources --fetch-sources
```

To reuse an existing cache without network access, omit `--fetch-sources`:

```sh
python3 tools/check_converted_asset_manifest.py --source-cache /path/to/converted-sources
```

You can also populate the cache from your own upstream checkouts. Use
`CACHE/SOURCE_ID/COMMIT/UPSTREAM_PATH` for each manifest entry. The source IDs
are `ict`, `sintel` and `ratboy`. Copy the input, license and context files
without changing their bytes. Git metadata is not required. The checker
verifies both checksums and the byte count, then stages the same checked
bytes in a private temporary directory.

Missing files fail in offline mode. Wrong revisions, changed sources and
truncated inputs fail before conversion. The download option does not repair
or overwrite altered cache files. Restore those files from the pinned source
before retrying. A source or output mismatch is an error. The checker never
updates accepted assets or their expected hashes.

### Arithmetic and verification limits

The reference run used CPython 3.12.14 on Linux x86-64, with only the Python
standard library. The output comparison is exact; another runtime must pass
the same hashes before its result is accepted.

THRS fitting adds floating-point values explicitly from left to right. This
keeps one binary64 rounding per addition. Python 3.12 changed built-in `sum`
to use more accurate floating-point addition. With the unmodified converter,
that change moved four Sintel offset components by one quantization step.

Explicit ordered addition reproduces the existing layered asset exactly.
It does not patch or replace any asset bytes. The mohawk and the three
synthetic output hashes also remain unchanged.

Full ICTF loading and the THRS readers validate the generated format at the
boundary described above. Provenance and format validation do not establish
anatomical or canonical-to-visual fidelity. That work remains separate in
issue [#297](https://github.com/SethKitchen/ThreeMojo/issues/297).
