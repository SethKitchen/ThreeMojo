# Shared decoded texture payload validation

This reconstruction preserves the recovered copy-on-write implementation.
The baseline is main commit `3b134f2f2c8a56cdc62878d98bd6c5dae1cbeeea`.
The previous local checkpoint was lost when the execution filesystem changed.
The results below come from new builds of the reconstructed source.

## Ownership contract

- `Texture(copy=source)` still makes an independent deep copy
- `Texture(copy=source, share_data=True)` shares byte and float texels and their complete mip chains
- A payload write detaches it when another buffer owns the same allocation
- Sampling state, transform state, lookup ramps and mip offsets remain independent
- `mutable_values()` detaches before exposing a writable List, Span or pointer
- Writable exposure is sticky; later shared copies take independent snapshots
- The direct read pointer is immutable and tied to its owner
- Moving input Lists invalidates lifetime-tracked aliases to those Lists
- Clearing the decoded registry cache leaves live texture-set and material shares valid

CARLA cache hits, all five dressed-map roles and repeated town texture variants
use explicit sharing. The public payload fields now have type `TextureBuffer`.
List consumers use `values()` for reads, `mutable_values()` for writes, or
`copy()` for owned data. The exporter and fixture adapters preserve their
original values and assertions.

## Fresh focused checks

All builds used pinned Mojo 1.1.0, `--Werror`, one compiler thread,
`x86_64-unknown-linux-gnu`, and target CPU `x86-64-v3`.
The original five-second per-test runtime gate was retained.
The process guard enforced at least 3 GiB available memory and 2 GiB free disk.

- 14 new texture-sharing tests passed
- 6 new CARLA texture-ownership tests passed
- 98 original texture tests passed
- 17 original float-texture tests passed
- 10 original texture-copy tests passed
- 4 original image-batch tests passed
- 4 original image-queue tests passed
- 33 original CARLA asset tests passed
- 18 original KTX2 tests passed
- 14 original glTF exporter tests passed
- 39 original object-JSON tests passed
- 14 original CARLA model-cache tests passed

The total is 271 runtime tests. Two compile-fail fixtures also passed with
strict expected diagnostics and a valid compiler control. The moved-input
fixture rejects a retained writable alias. The read-pointer fixture rejects
mutation through an immutable pointer. The existing 442 diagnostic records
were kept unchanged.

The new tests cover byte and float mip chains, source-owner death, move ownership and empty buffers.
They check default deep copies, sampler independence, independent regeneration and indexed writes.
They also check writable aliases before and after sharing, and sticky exposure.

Asset controls cover all five map roles, optional maps and color-space keys.
They check cache clearing, source-file reloads and existing material survival.

A 128-material fixture retains 640 dressed textures from five source maps.
Every retained map resolves to its source allocation after construction.
Each source has 84 bytes, including its mip chain. The five payloads therefore
hold 420 bytes. This count excludes metadata, allocation headers and other
stores. It is a payload-identity check, not a whole-town performance result.

## Fresh Town benchmark

The common benchmark source ran on pristine main and the reconstructed candidate.
One warmup pair preceded eight measured pairs with alternating execution order.
All samples are retained in `texture-ownership-town-20261006.json`.
No outlier was removed.

The synthetic fixture binds one 512-square PNG to four PBR roles across nine
Town surfaces. The registry decodes it in sRGB and linear space before timing.
The pinned map is `assets/carla/town.xodr`.
Procedural textures are 64 square and road mesh spacing is two meters.
Buildings, trees and lamps are disabled.

- Retained texel and mip payload: 54,656,964 to 2,927,264 bytes, a 94.64 percent reduction
- Median Town construction: 19.474 to 4.414 milliseconds, a 77.33 percent reduction
- Unique nonempty byte allocations: 45 to 8
- Every run: two decoded cache textures, 42 stored textures, nine materials and 13 meshes
- Full payload and sampling-state hashes matched between both versions
- Geometry hashes, 44,272 geometry bytes and all object counts matched

Payload accounting compares live allocation addresses across the registry,
texture store and the map retained by Town. It excludes metadata and allocator
headers. Timing covers only the Town constructor. These fixture results do not
measure complete rendering, GPU use, asset downloads or other town workloads.
The old checkpoint's timings and payload figures remain historical evidence.

Generate the inputs with:

```sh
python3 bench/carla_texture_ownership_fixture.py /tmp/town-ownership assets/carla/town.xodr
```

Compile the same benchmark source on each revision. Use the pinned toolchain
and the exact flags in the result JSON. Run each executable with the fixture
folder, its label and a sample number:

```sh
town_payload_bench /tmp/town-ownership candidate 0
```

The published benchmark differs from the measured source only by docstrings.
An executable-token comparison and regenerated input hashes both matched.
The result JSON records both source hashes and the fixture hashes.
The native ELF driver and its Python launcher have separate recorded hashes.

## Limits

The full repository check, coverage capture and GPU qualification have not run
on this packet. The focused results do not replace those integration gates.
Actor, physics and scene-resource reclamation remains separate issue #306 work.
