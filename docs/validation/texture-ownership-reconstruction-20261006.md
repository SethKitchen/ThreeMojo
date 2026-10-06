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

## Limits

A new elapsed-time benchmark has not run for this reconstruction.
The old checkpoint's timings and payload figures are historical evidence.
They are not presented as results of these builds.

The full repository check, coverage capture and GPU qualification have not run
on this packet. The focused results do not replace those integration gates.
Actor, physics and scene-resource reclamation remains separate issue #306 work.
