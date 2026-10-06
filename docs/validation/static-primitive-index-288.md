# Static primitive broad-phase design

Keep the current production path. The benchmark shows where a snapshot BVH can help, but a cache needs an explicit lifetime contract. This change measures and tests a prototype. It does not install an implicit world cache.

The production ownership and integration follow-up is [#633](https://github.com/SethKitchen/ThreeMojo/issues/633). It is a separate implementation task.

The issue is [#288](https://github.com/SethKitchen/ThreeMojo/issues/288). The source baseline is `8d9b700b753006b120a66d356228716822e442f4`. The baseline sweep predicate and stable insertion sort are copied from that revision. Rays use its `PhysicsWorld.raycast` directly. Production physics source is unchanged.

## Scope

The matrix has 100, 1,000 and 10,000 static primitives. Each world adds 1, 10 or 100 moving participants. One quarter of that group is kinematic, where the count permits it. Shapes cycle through sphere, box, capsule and convex hull. The contact filter still requires a dynamic participant.

Distributions are a separated grid, separated primitives whose x bounds all overlap, ten clusters, and fully coincident primitives. Moving participants shift by one centimeter between samples. Each 10-participant world also casts 1,024 sensor-style rays. The rays contain hits, misses, equal-distance choices and all four primitive kinds across the matrix.

The native run reports three samples per case. Allocation measurement is a separate run with the pinned Mojo runtime hook in `bench/navigation_allocations.c`. Do not compare hooked time with native time. The hook measures requested Mojo allocation bytes and calls on the query thread. It does not measure RSS or allocator metadata. The hook's self-test must pass and its overflow counter must remain zero.

Bounds creation is a separate phase. Both broad phases consume the same stored bounds and owner mapping. Sweep update starts from the previous stable order. The BVH reports full rebuild, refit, and query separately.

Harness copies of the freshly created bounds and owner arrays occur between timed phases. The tables report phase costs, not complete end-to-end world-step latency.

Contact query cost includes restoring the old pair order. It does not include narrow phase or impulse solving. Ray timings include the actual unchanged primitive narrow phase and result storage. Their BVH time excludes the separately reported snapshot build.

## Measured result

These are prototype phase timings on one shared Linux x86-64 host (AMD EPYC 9V74), with Mojo 1.1.0 (`8189361e`) and MAX 26.6.0 installed. They are not a production speedup claim. Single-phase values are native medians in milliseconds. Composite columns sum their individual phase medians; they are not medians of per-repetition combined latency. The host was not CPU-isolated; absolute times and ratios can vary with shared load. Keep the raw samples rather than selecting the most favorable run.

The following rows have ten moving participants (eight dynamic and two kinematic). “Sweep” is update plus query. “Rebuild BVH” is rebuild plus ordered query. “Refit BVH” is refit plus ordered query. All three exclude the common bounds phase shown separately.

| Statics | Layout | Bounds | Sweep | Rebuild BVH | Refit BVH | Linear 1,024 rays | BVH 1,024 rays |
|---:|---|---:|---:|---:|---:|---:|---:|
| 100 | Grid | 0.019 | 0.001 | 0.032 | 0.004 | 23.542 | 11.554 |
| 100 | Overlapping x | 0.019 | 0.044 | 0.035 | 0.004 | 22.030 | 0.314 |
| 100 | Clusters | 0.019 | 0.004 | 0.034 | 0.004 | 23.235 | 11.832 |
| 100 | Coincident | 0.019 | 0.044 | 0.076 | 0.048 | 24.959 | 20.653 |
| 1,000 | Grid | 0.196 | 0.040 | 0.557 | 0.024 | 208.928 | 11.290 |
| 1,000 | Overlapping x | 0.343 | 5.563 | 0.988 | 0.040 | 226.315 | 0.513 |
| 1,000 | Clusters | 0.176 | 0.283 | 0.553 | 0.033 | 210.126 | 53.751 |
| 1,000 | Coincident | 0.188 | 3.586 | 1.003 | 0.519 | 220.140 | 181.237 |
| 10,000 | Grid | 5.502 | 6.072 | 18.344 | 0.550 | 2094.490 | 11.208 |
| 10,000 | Overlapping x | 2.457 | 367.695 | 10.559 | 0.419 | 2107.281 | 0.891 |
| 10,000 | Clusters | 2.870 | 47.426 | 19.153 | 0.752 | 2118.930 | 288.860 |
| 10,000 | Coincident | 2.649 | 358.891 | 15.147 | 6.435 | 2503.656 | 1948.969 |

A full rebuild regresses the 100-static grid by about 32 times and the 10,000-static grid by about three times before common bounds work. At 10,000 statics, the overlapping-x case benefits strongly. Refit can remove most rebuild cost, but its timing assumes a valid retained snapshot. It does not establish that a current caller can skip mutation validation. These refit samples use the current build topology; long-term refit degradation is not a measured performance claim.

The 10,000-static ray batch ranges from about 1.28 times faster for coincident shapes to over 2,000 times faster for overlapping-x but separated-y/z shapes. The latter rejects most primitives before their allocating narrow-phase shape transforms. It is a batch query result with construction excluded. It must not be applied to a single ray that rebuilds its snapshot first.

### Candidate work and requested memory

At 10,000 statics plus ten moving participants:

| Layout | Sweep pairs visited | BVH nodes visited | Accepted pairs, both | BVH query peak bytes | BVH query allocation calls |
|---|---:|---:|---:|---:|---:|
| Grid | 505,910 | 242 | 8 | 80,192 | 7 |
| Overlapping x | 50,095,045 | 246 | 8 | 80,192 | 7 |
| Clusters | 4,007,509 | 4,178 | 1,278 | 108,752 | 24 |
| Coincident | 50,095,045 | 160,152 | 80,044 | 2,097,152 | 35 |

A rebuild at 10,010 entries requests 1,354,176 bytes in four allocations. Refit requests zero additional bytes and makes zero allocations. This retained storage includes bounds, indices, sort scratch and node capacity. It excludes world shapes and the caller's snapshot/owner lists. Each timed bounds refresh requests 5,092,584 bytes in 40,070 allocations. Sweep update and query allocate nothing in this candidate-count-only comparison.

Fully overlapping 10,000-static plus 100-moving worlds produce 754,650 pairs. The ordered BVH query requests a peak of 16,777,216 bytes in its measurement scope. Restoring deterministic solver order is a real cost; the index's linear storage bound is not a bound on all pair output.

The linear 1,024-ray phase at 10,010 entries requests 4,141,096,960 cumulative bytes in 41,000,960 short-lived allocations, with an 800-byte phase peak. The overlapping-x BVH ray phase reduces this to 412,472 cumulative bytes and 3,849 allocations. Coincident shapes retain 30,750,735 allocation calls. Cumulative requested bytes are not resident memory.

The manifest records retained source, binary and CSV fingerprints after the runs. The timed benchmark and index source stayed unchanged after their measured build. Later test-only additions were rebuilt and covered. No contemporaneous build-source digest was recorded.

Raw samples: [native timing CSV](static-primitive-index-288-native.csv), [allocation CSV](static-primitive-index-288-allocations.csv), and [source/binary/validation manifest](static-primitive-index-288.json). The matrix has 720 native rows and 240 allocation rows. Each broad-phase row includes its accepted-pair count and checksum. Runtime assertions require both algorithms to agree on every repetition; tests additionally compare complete candidate memberships and ordered manifolds.

CSV layout numbers are 0=grid, 1=overlapping x, 2=clusters, 3=coincident. For contact-query rows, `work` means sweep pair visits or BVH node visits; these are different operations. For ray rows, `work` is descriptive (nominal static primitive opportunities or tree node count), not a measured ray node-visit count. Allocation columns are zero in the unhooked run, not a claim that native code allocates nothing.

## Bounded prototype

The binary tree stores each primitive in one leaf. A nonempty tree has exactly `2N - 1` nodes and reserves `2N` node slots. A stable median split limits depth to `ceil(log2(N))`. A node's longest bounds axis selects the split; x, then y, then z resolves equal axis lengths. Stable equal-center partitions retain input order. Wide centroid keys avoid Float32 sum overflow.

Construction takes O(N log² N) work in this deliberately simple prototype. It keeps one sort buffer. Refit takes O(N) work and makes no allocation when entry count is unchanged. Both operations validate all bounds before changing the previous valid snapshot. Bounds must be nonempty and finite. Queries use forward escape links instead of recursive stacks.

Each overlap query visits no more than `2N - 1` nodes and emits no more than N entries. The contact adapter can retain C pair keys to recover the original solver order. Its storage is O(N + C), not O(N) independent of contact density. Fully overlapping worlds are the important counterexample. No implementation can discard actual contact pairs merely to meet a memory target.

## Lifecycle and ownership

The index owns its bounds. It never retains references to a caller's list. A query reads one fixed snapshot and uses caller-owned result scratch. Calls on independent snapshots need no shared scratch or global state.

- Build before the first query
- Refit after transform or shape-bound changes when every entry still names the same owner in the same slot
- Rebuild after insertion, removal or owner-slot remapping
- Rebuild the participant mapping after enable/disable or mode changes; retain dynamic-participant filtering at pair emission
- Clear the tree when the active set becomes empty
- Rebuild after substantial motion if refitted node overlap makes queries slow; refit remains correct, but it does not rebalance the tree

`PhysicsWorld.bodies` is publicly mutable. Position, rotation, shape transforms, shape data, material, collision enablement and motion mode can change between queries. Its current `raycast` borrows the world immutably. An index built during `step` would be stale if a caller changes a body and casts a ray before the next step. A mutation counter updated only by `add_body` cannot fix this.

A future retained query index therefore needs either an explicit immutable query snapshot, or world-owned mutation APIs that invalidate every relevant change. An immutable snapshot must own the narrow-phase shapes and materials too. This prototype owns bounds only and deliberately reads narrow phase from a world held unchanged for each measured batch. It must not be advertised as a self-validating persistent PhysicsWorld cache.

There is no physical body-removal API in this PhysicsWorld revision. Disabling `collides` removes a body from contact and ray participation while keeping its id. Tests cover that lifecycle and empty/shrinking standalone snapshot rebuilds. They do not make direct `bodies.pop()` safe for the existing world's id and mesh-owner tables.

## Exact order and correctness

The contact adapter uses the current stable sweep rank, including the history of equal-x ties. It emits each dynamic-involving pair once, sorts pair keys by those ranks, and inserts mesh contacts at the same place as the old loop. A conservative query uses twice the absolute margin. The final predicate uses the original oriented Float32 expansion and x cutoff. Expanding the other body's box is not substituted for that predicate.

Primitive ray candidates return to body-id order before exact tests. Mesh hits remain first, including a dirty-octree brute-force fallback. Equal-distance primitive hits keep the first body id. An equal-distance mesh hit keeps the production mesh-first result. Ignore ids, disabled owners and maximum distance use the existing rules.

The tests compare every candidate set with a brute-force bounds oracle. They also run narrow phase against every relevant primitive pair, including culled pairs. Ordered manifolds match the production sweep. Contact depth, point and normal match exactly. A multi-step comparison requires identical contact counts, event order, impulses, positions, rotations and velocities through collision disabling and mode changes. The ray matrix compares body, distance, point and normal exactly with the production linear scan.

Negative cases include empty inputs, point bounds, closed tangency, nonfinite bounds and rejected-update atomicity. Lifecycle cases include ownership, insertion/removal, enablement, local/world transforms and mode changes. Adversarial layouts include reversed/equal bounds, all split axes, extreme finite coordinates and large refit motion. Ray cases cover negative directions, inside origins, ignored bodies, mesh ties and reach boundaries. Exact manifold and trajectory checks exercise historical tie order and contact margins. Existing test tolerances and five-second limits stay unchanged.

## BVH versus octree integration

Use the bounded BVH design for a future primitive snapshot. The current octree indexes triangles, duplicates a triangle into every child it overlaps, and deduplicates query results. Substituting box surface triangles would change the representation and inflate both geometry storage and ownership work. A single-leaf-per-primitive BVH gives a direct bound on node and entry storage even for coincident primitives.

This is an architectural comparison, not an octree-versus-BVH timing claim. The benchmark measures the existing sweep and linear ray scan against the BVH prototype. No primitive-aware octree was implemented or measured. CARLA's R-tree also cannot be imported into shared physics without reversing its current dependency boundary.

Before production integration, choose the snapshot ownership API, evaluate a dynamic-only sweep alternative, and set a workload-aware fallback policy. Do not replace the default sweep merely because the most x-overlapping workload wins. Do not apply retained-snapshot ray speedups to single-ray calls that must rebuild every time.

## Acceptance evidence for #288

| Issue requirement | Evidence |
|---|---|
| 100/1,000/10,000 static primitives, moving counts, update/query time, allocation and candidate counts | Complete 36-case matrix; bounds, sweep update/query, BVH rebuild/refit/query and separate allocation phases |
| Clustered, overlapping-x and dense sensor workloads | Four layouts, with 1,024-ray batches for each count/layout at ten moving participants |
| Brute-force contacts/rays for boxes, spheres, capsules and hulls; insertion/removal/transforms/margins | `test_physics_static_bvh`; full primitive-pair narrow-phase checks, bounds oracles, exact ray results, standalone membership rebuilds, collision-enable lifecycle and local/world transforms |
| Retained regressions, dynamic filtering, no missed/duplicate impulses | Existing world/static-regression/mode/shared suites, exact ordered manifolds, and a twelve-step exact event/impulse/trajectory comparison |
| Rebuild/refit lifecycle, deterministic ties, memory/performance tradeoffs and BVH/octree choice | The lifecycle, order, measured-memory and design sections above; no unvalidated production integration |

Ten new focused tests and 42 retained tests pass with `--Werror` and the unchanged five-second per-test gate. The entire experimental BVH module has 105/105 lines, 52/52 branch/condition outcomes and 3/3 MC/DC obligations covered. Four loop annotations document construction invariants that make an empty loop impossible; no existing source exemption or threshold changed. The benchmark driver and tests are harness code, outside production coverage; no production module changed. This is focused verification, not a claim that the whole repository's aggregate checks ran for this patch.

## Deferred implementation

[#633](https://github.com/SethKitchen/ThreeMojo/issues/633) tracks the owned query-snapshot API, complete mutation contract, shared implementation, fallback policy and production performance gates. The overlap check found no existing equivalent task. Related [#306](https://github.com/SethKitchen/ThreeMojo/issues/306) covers resource reclamation, [#550](https://github.com/SethKitchen/ThreeMojo/issues/550) covers numerical ray-kernel throughput, and [#554](https://github.com/SethKitchen/ThreeMojo/issues/554) covers mode/mass API guards. Those are not replaced by the snapshot task.

## Integration checks

The original ten-test packet passed its isolated prototype coverage scope. Full production instrumentation exposed two integration problems. The standard coverage tree omitted benchmark imports, and the combined independent-world test exceeded five seconds. The retained samples were 5.972466 seconds and 5.776226 seconds after caching repeated pure shape transforms.

The coverage tree now copies maintained benchmark helpers through unchanged while preserving explicitly measured modules. Four fixture tests check the copy set, measured-helper preservation, empty measurement and instrumentation failure.

The oracle cache lasts one immutable world check and is rebuilt after each mutation. The four freshly constructed distribution worlds are separate tests. The continuous twelve-body trajectory remains one test with all eight states. The formerly combined scenario retains all 1,529 ordered pair checks and 360 ray comparisons. All 52 assertion call sites remain.

 No benchmark or production code changed, and the five-second per-test gate is unchanged.

The final test hash and exact scenario counts are in the validation JSON. Original source and timing records remain labeled separately.

All fourteen tests pass under full production instrumentation. The slowest takes 2.422 seconds in the retained shared-host sample. This is an integration check, not a full aggregate coverage pass.

## Reproduce

Use the exact pinned toolchain from the README on Linux. Run from the repository root. Telemetry is disabled only in these commands' process environments.

```sh
mkdir -p .cache/static-288
MODULAR_TELEMETRY_ENABLED=false .venv/bin/mojo build --Werror -I . \
  bench/physics_static_bench.mojo -o .cache/static-288/bench
MODULAR_TELEMETRY_ENABLED=false .cache/static-288/bench > .cache/static-288/native.csv
cc -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC \
  bench/navigation_allocations.c -ldl -o .cache/static-288/allocations.so
MODULAR_TELEMETRY_ENABLED=false \
  LD_PRELOAD="$PWD/.cache/static-288/allocations.so" \
  .cache/static-288/bench "$PWD/.cache/static-288/allocations.so" \
  > .cache/static-288/allocations.csv
MODULAR_TELEMETRY_ENABLED=false .venv/bin/mojo build --Werror -I . \
  tests/test_physics_static_bvh.mojo -o .cache/static-288/tests
MODULAR_TELEMETRY_ENABLED=false python3 tools/run_suite.py --seconds 5 \
  --suite tests/test_physics_static_bvh.mojo -- .cache/static-288/tests
```

For whole-prototype coverage, instrument `bench/physics_static_bvh.mojo` with the repository coverage tool. Copy the benchmark driver and tests into that complete instrumented tree. Capture the test binary's stdout and stderr directly with `tools/coverage_io.py`; do not wrap capture around `run_suite.py`, which merges those streams. Check the captured test records with the same five-second limit, capture the prototype's small `main` entry point, then report the combined captures. The validation manifest records the exact counts and source hashes.
