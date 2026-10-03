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

`assets/converted-asset-manifest.json` records exact hashes for the current
converter files and the three bundled production outputs. It records the
recipes and license declarations in the existing converter source and
`THIRD-PARTY-NOTICES.md`. These facts do not establish which converter revision
or upstream input bytes produced those historical outputs.

The historical source revisions and checksums remain unverified. The manifest
uses null for those pins and false for production regeneration verification.
Issue [#303](https://github.com/SethKitchen/ThreeMojo/issues/303) remains open
for that evidence. Do not describe the production conversion as reproducible
until pinned upstream inputs regenerate the recorded output hashes.

The manifest also pins small original OBJ and TressFX test inputs under
`assets/converted-fixtures/`. The TressFX bytes use hexadecimal text for review.
The check decodes them locally, runs both converters in a temporary directory,
and compares all three generated output hashes. It never downloads assets or
replaces accepted output files.

Run the local check from the repository:

```sh
python3 tools/check_converted_asset_manifest.py
```

To require complete production provenance, add `--require-source-pins`.
This mode fails while any historical source pin is unverified. Synthetic
reproduction does not remove that production evidence gap.
