<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Owned physics query snapshots

Use an owned frozen snapshot for repeated rays through the same captured state. Keep `PhysicsWorld.raycast` for live queries. The snapshot preserves exact existing narrow-phase answers and never combines stored bounds with changed world geometry.

This report measures [#633](https://github.com/SethKitchen/ThreeMojo/issues/633). The source baseline is `84038a2e06b0945fb1586b712298ab9268741b81`. The benchmark imports the [#288](static-primitive-index-288.md) world and ray distribution builders. It adds owned geometry, capture lifetime, a dynamic-participant sweep control, and refit degradation probes.

## Measurement contract

The full matrix contains 100, 1,000 and 10,000 static primitives. Each world adds 1, 10 or 100 moving participants, with the same one-quarter kinematic rule as #288. Shapes cycle through sphere, box, capsule and convex hull. The four layouts are the separated grid, separated shapes with overlapping x bounds, ten clusters, and fully coincident shapes. Moving poses alternate by one centimeter exactly as in #288.

Each ten-participant case casts the same 1,024 rays as #288. The harness measures four query paths:

- The unchanged live `PhysicsWorld.raycast`
- A frozen linear control that uses the production narrow-phase helpers
- The public owned, frozen `PhysicsQuerySnapshot.raycast` with safe selective indexing
- A benchmark-only forced primitive index over the same frozen geometry

The forced index uses the same finite checks, normalized ray construction, mesh-first rule, body-id tie order, narrow-phase helpers, and capture-scoped result ownership. Only primitive candidate selection changes. It is an experiment, not a production query mode.

Each native case has three samples. Query path order rotates through all four paths. World generation, ray generation, warmups, independent answer storage and exact checks are outside timing. Timed queries consume a checksum rather than store result arrays. Exact checks compare presence, historical body slot, distance, point, normal and both material fields for every ray. The final capture also answers the same rays after all source poses, materials and enable bits change, and again after the source world is destroyed.

Capture build and index build are separate measured phases. Build amortization uses their native medians and native batch medians. It is an estimate, not an observed end-to-end latency. A break-even ray count is the first integer count where estimated savings exceed capture cost. A missing count means the measured query path did not save time.

Native timing and allocation runs are separate. The allocation hook extends the existing pinned Mojo runtime interposer with its live-byte counter. Its self-test must pass and its overflow flag must remain zero. Requested bytes exclude allocator overhead and RSS.

A phase's live-byte counter includes only allocations made in that phase that survive its end. It measures capture retention without counting the preexisting source world. Query peak bytes measure temporary query storage independently.

The capacity breakdown includes all `WorldShape` records and nested polyhedron arrays; primitive bounds and copied mesh-octree nodes; triangle arrays; owner mappings; materials; and enable bits. The capture token's allocation header and inline container headers are excluded from this payload breakdown. The live-byte count is the complete measured retained runtime allocation total. The production selective index and its mapping, mask and per-axis fallback lists are included. The forced mathematical primitive index is reported separately and is not part of the production snapshot's memory.

## Measured results

These are native medians on a shared Linux x86-64 Intel Xeon Platinum 8573C host with Mojo 1.1.0 (`8189361e`). The serial lane prevents overlap with our other native builds and tests. It does not isolate the CPU from other tenants. All original samples are retained.

Each row has ten moving participants. Times are milliseconds. The forced index column is an unsafe mathematical-BVH experiment and is not adopted. Break-even includes the entire production capture build and is an estimate against the live world query.

| Statics | Layout | Capture build | World 1,024 rays | Frozen linear | Safe snapshot | Forced index | Break-even rays |
|---:|---|---:|---:|---:|---:|---:|---:|
| 100 | grid | 0.102 | 28.293 | 7.208 | 7.004 | 5.893 | 5 |
| 100 | overlapping x | 0.098 | 26.517 | 5.109 | 1.466 | 0.238 | 5 |
| 100 | clusters | 0.103 | 28.371 | 7.702 | 7.428 | 6.891 | 6 |
| 100 | coincident | 0.057 | 28.216 | 8.815 | 9.000 | 9.157 | 4 |
| 1,000 | grid | 1.454 | 242.325 | 54.009 | 32.482 | 7.586 | 8 |
| 1,000 | overlapping x | 1.664 | 241.518 | 48.244 | 11.425 | 0.425 | 8 |
| 1,000 | clusters | 1.192 | 270.384 | 60.765 | 57.338 | 40.072 | 6 |
| 1,000 | coincident | 0.415 | 266.468 | 79.079 | 79.953 | 84.321 | 3 |
| 10,000 | grid | 23.790 | 2547.496 | 553.739 | 126.134 | 7.722 | 11 |
| 10,000 | overlapping x | 24.633 | 2600.680 | 529.701 | 117.197 | 0.858 | 11 |
| 10,000 | clusters | 20.962 | 2530.498 | 594.480 | 455.143 | 189.454 | 11 |
| 10,000 | coincident | 5.869 | 2772.278 | 836.566 | 871.189 | 865.151 | 4 |

At 10,000 statics, the safe snapshot improves the repeated batch by 3.18 to 22.19 times against the live world. In the three indexed layouts, it is 1.31 to 4.52 times faster than frozen linear geometry.

The coincident case selects the frozen fallback. Its public query was 4.1 percent slower than the direct frozen-linear control in this sample, while still 3.18 times faster than the live world. This is a real measured cost; the public path includes dispatch and shared-host variation remains. This experiment does not isolate their contributions. The tables do not treat the forced index's larger geometric speedups as safe production behavior.

### Retained bytes and query scratch

At 10,000 statics plus ten moving participants:

| Layout | Retained runtime bytes | Owned geometry payload | Bounds and index payload | Owner/material/routing payload | Query peak scratch | Query total requested bytes | Query allocations |
|---|---:|---:|---:|---:|---:|---:|---:|
| grid | 9,805,704 | 7,451,912 | 1,747,464 | 606,304 | 2,048 | 1,664,000 | 6,239 |
| overlapping x | 9,805,704 | 7,451,912 | 1,747,464 | 606,304 | 24 | 6,160 | 769 |
| clusters | 9,805,704 | 7,451,912 | 1,747,464 | 606,304 | 65,536 | 53,003,872 | 10,796 |
| coincident | 8,123,752 | 7,451,912 | 393,288 | 278,528 | 0 | 0 | 0 |

The three payload columns sum to the retained counter minus the 24-byte capture token. The separately built forced index retains 1,201,200 bytes. It is excluded from the production retained total. All primitive frozen-linear control batches request zero bytes.

The live-world 10,010-body batch requests 4,141,096,960 bytes in 41,000,960 allocation calls from repeated shape construction. These are cumulative requested bytes, not peak memory or RSS. Safe snapshot query scratch is released before each measured batch ends.

### Dynamic control and refit degradation

At 10,000 statics plus ten moving participants:

| Layout | Historical sweep ms | Dynamic preparation ms | Ordered dynamic query ms | Historical visits | Dynamic visits | Exact pairs | Pair-scratch peak bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| grid | 4.785 | 0.352 | 0.013 | 505,910 | 808 | 8 | 96 |
| overlapping x | 435.235 | 0.308 | 0.939 | 50,095,045 | 80,080 | 8 | 96 |
| clusters | 35.985 | 0.339 | 0.069 | 4,007,509 | 2,408 | 1,278 | 24,576 |
| coincident | 412.173 | 0.283 | 10.548 | 50,095,045 | 80,080 | 80,044 | 2,097,152 |

This control can greatly reduce static-only visits. It does not replace production contacts: its measured work boundaries differ from the counting-only historical sweep and omit contact generation and solving.

With every entry permuted, refitted versus rebuilt 1,024-ray batches cost 1.120/0.909 ms at 100 entries, 10.607/2.376 ms at 1,000, and 86.131/2.850 ms at 10,000. The 10,000-entry refit visits 8,937,740 nodes; a rebuild visits 311,018 for exactly the same 40,034 candidates. Rebuilding costs 17.087 ms versus a 0.204 ms refit. One subsequent batch recovers that difference in this severe-degradation probe. The probe uses the shared index's mathematical half-ray traversal; it is not a new public snapshot refit feature.

## Adoption and fallback policy

Production uses a selective index only for cases whose bounds preserve the current Float32 narrow-phase answers. It does not install a retained cache in `PhysicsWorld`.

A normalized coordinate-axis ray can use the selective index when its origin coordinates stay within 10^12 meters. Spheres require bounded centers and radii from 2^-16 through 2^16 meters. Their bounds are expanded and rounded outward.

Capsules use the sphere proof only for rays parallel to an exact capsule axis, where the cylinder coefficient is exactly zero. Solids require exact unit coordinate-axis face normals, both signs on every axis, and bounded transformed vertices. Transformed face offsets come from those vertices. Every other shape remains on the linear path.

The index tests the entire axis line's two transverse coordinates. It does not cull by longitudinal position or reach. Candidates merge with the required linear entries in original body order. Mesh queries keep the existing captured mesh path. These rules preserve mesh-first and body-id ties.

Captures with fewer than 32 shapes or fewer than 32 admitted shapes use the frozen linear path. An admitted set whose bounds all share a point also stays linear. Non-axis rays and out-of-range origins stay linear. An indexed query that retains at least one quarter of all shapes falls back before sorting and merging. The 0, 1, 4, 8, 16, 32 and 64-body controls measure both construction and repeated queries across all four layouts. These limits are explicit performance choices, not changes to accepted query results.

Use the unchanged world query for a one-off live ray or whenever the latest world edits must be visible. Build a new snapshot only when the caller wants another captured view. Use the measured construction break-even estimates to decide whether a short query batch can recover its capture cost.

The existing Float32 narrow kernels can return answers outside exact mathematical bounds at extreme finite scales. Passing the ordinary benchmark corpus does not prove that the unrestricted forced index preserves all accepted answers. That index is not adopted. The [selective production proof](physics-query-snapshot-633-proof.md) and independent extreme-scale regression are separate from its ordinary-corpus timing result.

### Small-world confirmation

The original three-sample matrix contains a timing outlier at four coincident bodies: public batches took 0.360, 4.326 and 1.297 ms. None of those samples is discarded. A separate driver repeats all 28 small-world cases with nine samples each, using the unchanged measured helpers. All 1,512 repeat rows pass the exact checks.

The repeated four-body coincident median is 0.381 ms, with a 0.358 to 3.364 ms range. Its frozen-linear control median is 0.335 ms and its live-world median is 1.065 ms. The repeated matrix estimates capture break-even at 4 to 8 rays for counts 4 through 64. Empty and single-body captures do not amortize in these samples.

At 32 and 64 bodies, the overlapping-x layout improves by 3.01 and 3.17 times against the frozen-linear control. The other small layouts do not show a consistent additional index benefit. The public API and candidate fallback can be slower than the direct frozen-linear control. The 32-entry threshold is a conservative build policy, not a guarantee that every indexed direction is faster. Keep the live-world API for one-off and very small queries, and keep both the original matrix and separate repeat when comparing future changes.

## Dynamic-participant sweep control

The control retains the historical stable x order. It builds a prefix maximum of the original Float32 `max.x + margin` values and a list of dynamic ranks. Each dynamic rank searches only the prefix that can reach it and the following ranks up to its original cutoff. Kinematic/static-only pairs are excluded. Dynamic pairs are emitted once. The exact oriented box predicate is unchanged.

The control produces and sorts pair keys into historical sweep order. Every complete key list must equal the historical sweep's key list, including duplicate exclusion. This is stronger than a count or checksum match.

The historical `sweep_query` row only counts accepted pairs. The dynamic control includes pair-output allocation and ordering. Its preparation row is separate. Neither path includes narrow phase, impulses, world-step integration, or the common bound construction and sweep sort. These phase results cannot establish a complete step speedup. Production contact code remains unchanged.

## Refit and rebuild criteria

A public snapshot never refits. Its source mutations leave it deliberately frozen. Build a new capture to observe membership, pose or shape changes.

The shared primitive-index experiment keeps entry count and identity slots fixed. It permutes 0, 25, 50 or 100 percent of the 100, 1,000 and 10,000 bounds. Each case compares a refit of the original topology against a fresh rebuild of the changed bounds. Every ray must return an identical full candidate list after sorting. Node visits and exact candidate counts are reported separately from native query times.

A future mutable index must rebuild after membership or owner-map changes. Refit can preserve correctness for fixed membership, but it cannot restore topology quality. For fixed membership, compare a representative probe with a fresh rebuild. Rebuild when the remaining expected query savings exceed `rebuild_cost - refit_cost`. The reported integer break-even batch counts apply only to this probe workload.

A node-visit increase is an early warning, not proof of a time threshold. Do not use a fixed motion distance or a fixed number of refits as a universal performance rule.

## Reproduce

Use the exact pinned Mojo 1.1.0 toolchain on Linux. Keep timing and allocation runs serial. Run from the repository root:

```sh
mkdir -p .cache/snapshot-633
MODULAR_TELEMETRY_ENABLED=false .venv/bin/mojo build --Werror -I . \
  bench/physics_snapshot_bench.mojo -o .cache/snapshot-633/bench
MODULAR_TELEMETRY_ENABLED=false .cache/snapshot-633/bench \
  > .cache/snapshot-633/native.csv
cc -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC \
  bench/physics_snapshot_allocations.c -ldl -o .cache/snapshot-633/allocations.so
MODULAR_TELEMETRY_ENABLED=false \
  LD_PRELOAD="$PWD/.cache/snapshot-633/allocations.so" \
  .cache/snapshot-633/bench "$PWD/.cache/snapshot-633/allocations.so" \
  > .cache/snapshot-633/allocations.csv
python3 bench/physics_snapshot_report.py \
  .cache/snapshot-633/native.csv .cache/snapshot-633/allocations.csv \
  .cache/snapshot-633/report.json
```

The report generator refuses missing cases, repeated sample ids, inconsistent counters and query checksum differences. To reproduce the separate small-world confirmation and include its retained samples, use:

```sh
MODULAR_TELEMETRY_ENABLED=false .venv/bin/mojo build --Werror -I . \
  bench/physics_snapshot_small_bench.mojo -o .cache/snapshot-633/small-recheck
MODULAR_TELEMETRY_ENABLED=false .cache/snapshot-633/small-recheck \
  > .cache/snapshot-633/small-recheck.csv
python3 bench/physics_snapshot_report.py \
  .cache/snapshot-633/native.csv .cache/snapshot-633/allocations.csv \
  .cache/snapshot-633/report.json \
  --small-recheck .cache/snapshot-633/small-recheck.csv
```

Exact per-ray and per-pair comparisons run inside the Mojo harness outside timed regions. The focused test record reports production checks. Full changed-module coverage remains a separate batch gate; this benchmark does not replace it.

## Retained evidence

- [Native samples](owned-physics-snapshots-633-native.csv): 1,344 complete rows, three native repetitions
- [Allocation samples](owned-physics-snapshots-633-allocations.csv): 456 complete rows, one separate hooked repetition
- [Small-world repeat](owned-physics-snapshots-633-small-repeat.csv): 1,512 rows, nine separate native repetitions
- [Validated summary](owned-physics-snapshots-633.json): native medians, allocation counters, amortization estimates, and original/repeated small-world cases
- [Measured source hashes](owned-physics-snapshots-633-measured-source.json): exact pre-build source hashes, toolchain and host
- [Artifact hashes](owned-physics-snapshots-633-artifacts.json): measured binary and final benchmark deliverable hashes
- [Numerical admission proof](physics-query-snapshot-633-proof.md): ownership, stale-owner behavior, safe admission and extreme-scale witnesses

Both benchmark drivers compile with `--Werror`. The allocation hook compiles with `-std=c11 -Wall -Wextra -Werror`. Both full runs and the small repeat exit zero. The report generator's positive complete-corpus check passes; its negative missing-row, duplicate-sample and changed-checksum probes are rejected. These are benchmark checks, not a claim that the repository's aggregate checks or full production coverage have passed.

After these measurements, production received a documentation-only correction: negative reach excludes ordinary finite-distance hits, but a preserved legacy NaN hit can survive any reach. The measured source hash remains the pre-correction hash. Public field docstrings were also added after measurement. These documentation changes alter no executable query behavior. The final production verification record tracks its own source hashes.

## Focused production checks

The final focused run passes 39 tests with warnings as errors and the unchanged five-second per-test gate:

- 12 frozen snapshot, primitive, mesh, owner, mutation and selective-query tests
- 13 validation, extreme-scale, unsafe-ordering and numerical-admission tests
- 14 retained primitive-index, contact-oracle and trajectory tests

Two selected compile-fail fixtures reject a bare integer as a snapshot owner and reject a historical owner as a live body id. Their generated diagnostics pass the strict check. Unselected diagnostic records remain unchanged.

Both new production modules pass strict public-docstring checks. The changed documentation passes the writing checks. The primitive index has one implementation; the old benchmark imports an alias. The existing world module is byte-identical to the baseline.

Full changed-module coverage, repository aggregate checks, other platforms and final draft CI remain deferred to the final batch. No coverage percentage or full CI pass is claimed here. [Focused verification hashes](owned-physics-snapshots-633-verification.json) identify the final sources and test outcomes.
