# Conservative CCD candidate validation for issue 636

Conservative triangle candidates reduce complete warm CCD step costs on the fixed workloads. Cold construction and queries with broad overlap remain expensive.

This change implements the immutable-mesh acceleration in [issue 636](https://github.com/SethKitchen/ThreeMojo/issues/636). It does not extend the supported shapes or precision domain. Read the [public contract](../wiki/Continuous-collision.md) before using this mode.

## Revision and qualification

The integration base is `2c91d60c660d05cf5e0fa093e6774558ba14332f`, tree `6fa77dbdc9575ae79020417eee9c230fbf3347f5`. The [machine-readable record](continuous-collision-636.json) identifies measured source and binary hashes. The original `ccd.mojo` sweep arithmetic and fixed benchmark source are unchanged. Geometry still uses Float64 analytic arithmetic, not exact predicates.

Verification used Linux x86-64 and pinned Mojo 1.1.0 (`8189361e`). Builds used `--Werror`. Mojo telemetry was disabled. Native suites retained the original five-second per-test gate. No workload, tolerance or existing test denominator was reduced.

These are focused local checks. Full changed-module coverage and repository aggregates are deferred to the final all-issue batch, as requested. This report does not claim a full coverage pass, exact-head CI or macOS qualification. The integration pull request remains a draft.

## Implementation and ownership

The world validates every immutable snapshot triangle before building the private tree. Distant triangles and disabled mesh owners are included. Successful geometry validation is retained for that snapshot. `add_body` invalidates the cache when it adds a mesh. A failed geometry check does not publish a valid cache.

Body state, collision flags, materials, sphere radii and solver settings remain live. Both separation passes retain the original domain checks. The second pass includes post-solver velocity, spin and split correction. An added sphere does not invalidate immutable mesh geometry.

Each triangle occurs in one leaf. Median splitting limits depth to `ceil(log2(T))`. The tree contains `2T - 1` nodes. Construction is O(T log² T), with three O(T) scratch arrays. These arrays are released after construction.

A query visits at most `2T - 1` nodes. It uses escape links, without a traversal stack or a full-mesh visited array. Float64 endpoint additions and radius expansions round outward. Stored Float32 triangle bounds widen exactly. Existing sweep predicates decide the hit after candidate selection.

Queries retain all possible candidates. They do not stop at the first hit or discard candidates to meet a budget. Exact-time ties use triangle insertion order. The existing impact limit, unsupported-case refusals and transactional rollback are unchanged.

Meshes of eight triangles or fewer use linear candidate scans. The private `_ccd_brute_force` diagnostic switch also repeats the original full geometry and domain scans. It bypasses a populated index and provides the independent oracle. It is not a new public collision mode.

A validated CCD cache can survive a failed step because its immutable geometry did not change. The contact octree retains its separate dirty-state rollback behavior. Direct mutation of private cache or triangle fields is unsupported.

## Unchanged fixed benchmark

`bench/physics_ccd_bench.mojo` is byte-identical to the integration base. Each scene retains one warmup and twenty measured steps. Every measured step also has the original ray batch. Three original-build runs and three accelerated-build runs used separate retained binaries.

The table reports the median of three run means. The last column is the maximum individual accelerated step across those runs. Complete steps include validation, both separation checks, contacts, response, ordering and transaction work.

| Workload | Triangles / spheres / rays | Original CCD step | Accelerated CCD step | Speedup | Accelerated maximum |
|---|---:|---:|---:|---:|---:|
| Vehicle probe | 2048 / 1 / 64 | 0.133187 ms | 0.004199 ms | 31.7× | 0.006770 ms |
| Separated fleet | 8192 / 32 / 256 | 9.946369 ms | 0.205728 ms | 48.3× | 0.416256 ms |
| Sensor scale | 32768 / 16 / 2048 | 20.393670 ms | 0.328727 ms | 62.0× | 2.033333 ms |

All ray checksums match: 6400, 25600 and 204800. Accelerated-build median ray batches cost 0.089391, 1.404334 and 29.538091 ms. Rays use the unchanged octree. Their timing differences do not establish a ray speedup.

Discrete-control median steps were 0.002193/0.132926/0.223327 ms in the original build. They were 0.002005/0.137332/0.231389 ms in the accelerated build. The small differences include shared-host scheduling noise. [All fixed timing rows](continuous-collision-636-fixed-timings.csv) are retained.

## Same-build profile and adverse workloads

`bench/physics_ccd_index_bench.mojo` compares the forced brute oracle with acceleration in one binary. Step and ray execution order alternate across twenty repetitions. Each mode receives one cold warmup first. Cold samples remain brute-first.

Tables use medians across the three native runs. Amortization is calculated separately for each run before taking the median.

Every successful paired step compares complete stored body state, contact count, event owners, impulses, order and mesh dirty state. Ray batches compare checksums. The three original scene constructors and reset functions are imported without changes.

| Workload | Triangles / spheres / rays | Brute warm step | Indexed warm step | Brute cold step | Indexed cold step |
|---|---:|---:|---:|---:|---:|
| Vehicle probe | 2048 / 1 / 64 | 0.133786 ms | 0.004636 ms | 5.489811 ms | 6.258744 ms |
| Separated fleet | 8192 / 32 / 256 | 10.553935 ms | 0.248699 ms | 31.521135 ms | 30.768557 ms |
| Sensor scale | 32768 / 16 / 2048 | 21.041523 ms | 0.299815 ms | 121.177954 ms | 150.728049 ms |
| Small linear fallback | 8 / 1 / 64 | 0.002739 ms | 0.002562 ms | 0.015169 ms | 0.021518 ms |
| Clustered patches | 2048 / 16 / 256 | 1.369003 ms | 0.069626 ms | 6.822080 ms | 7.517303 ms |
| Worst initial overlap | 2048 / 1 / 256 | 0.514334 ms | 0.583443 ms | 4.644521 ms | 6.405065 ms |

The clustered scene has sixteen dense 8-by-8 patches with 56-meter gaps. Each patch has one sphere. The worst-overlap scene sweeps diagonally across the original 2048-triangle grid. Its initial swept bounds select all 2048 triangles; the harness asserts this count.

The worst-overlap indexed step is about 13.4% slower. Its candidate allocations also increase, as shown below. This is a measured regression, not a real-time capacity claim. Small-scene cold differences are sensitive to cache state and scheduling. The eight-triangle path builds no tree.

Cold steps include both CCD and contact-octree construction. They exceed a 10 ms budget on larger scenes. The separate sensor ray batch adds further cost. These synthetic sphere probes do not establish capacity for a vehicle fleet or a complete simulation.

## Build, retained memory and amortization

A native node occupies 40 bytes on this target. Retained payload is node capacity times that size. It excludes existing triangle snapshots, body storage, the contact octree, allocator metadata and process RSS.

| Triangles | Standalone index build | Retained node payload | Build peak and total requested bytes | Build allocation calls |
|---:|---:|---:|---:|---:|
| 2048 | 1.675434 ms | 163800 B | 245720 B | 4 |
| 8192 | 10.530250 ms | 655320 B | 983000 B | 4 |
| 32768 | 56.534770 ms | 2621400 B | 3932120 B | 4 |
| 8 | 0.000085 ms | 0 B | 0 B | 0 |

The raw profiles include estimated lifetimes of 1, 2, 5, 20, 100 and 1000 steps. Each estimate uses one measured cold step and the measured warm mean for later steps. These are algebraic estimates, not additional timed runs.

| Workload | Brute mean over estimated 20-step life | Indexed mean over estimated 20-step life | Indexed mean over estimated 100-step life |
|---|---:|---:|---:|
| Vehicle probe | 0.394771 ms | 0.317341 ms | 0.067177 ms |
| Separated fleet | 11.547672 ms | 1.772621 ms | 0.553483 ms |
| Sensor scale | 25.888097 ms | 7.818605 ms | 1.801365 ms |
| Small linear fallback | 0.003345 ms | 0.003508 ms | 0.002751 ms |
| Clustered patches | 1.633989 ms | 0.445565 ms | 0.139280 ms |
| Worst initial overlap | 0.718246 ms | 0.874524 ms | 0.641659 ms |

Build cost does not amortize into a benefit for the measured worst-overlap scene. Short-lived small scenes also show a small regression in this estimate. A steady-state speedup alone is insufficient for those uses.

## Requested allocations

A separate run loads `bench/navigation_allocations.c` through `LD_PRELOAD`. Its self-test passes and record overflow remains zero. It counts requested Mojo runtime bytes and allocation calls. Hooked timings are excluded from native speed claims.

Peak bytes include only live allocations created inside the measured phase. They exclude allocations that existed before that phase, including retained indexes. The table reports complete warm-step requested totals and calls. Per-phase peak values remain in the [allocation records](continuous-collision-636-allocations.csv).

| Workload | Brute requested bytes / calls | Indexed requested bytes / calls | Indexed phase-local peak |
|---|---:|---:|---:|
| Vehicle probe | 3512 / 25 | 3584 / 31 | 2904 B |
| Separated fleet | 321056 / 237 | 322448 / 323 | 32456 B |
| Sensor scale | 553632 / 141 | 554384 / 187 | 45000 B |
| Small linear fallback | 1376 / 23 | 1376 / 23 | 936 B |
| Clustered patches | 62432 / 147 | 62864 / 183 | 14856 B |
| Worst initial overlap | 3392 / 21 | 101672 / 57 | 24912 B |

## Complete costs and diagnostic phases

Complete-step timings are authoritative. The following probes overlap and must not be summed. Each probe restores its input state outside the timed interval. The table uses sensor-scale medians of per-run phase means, except the separately named rollback fixture.

| Diagnostic phase | Brute | Indexed |
|---|---:|---:|
| Live validation and cached/full geometry check | 0.840092 ms | 0.001437 ms |
| Transaction snapshot | 0.002862 ms | 0.000438 ms |
| One separation/domain pass | 4.989929 ms | 0.005284 ms |
| Sphere queries, narrow-phase solve and response | 9.289295 ms | 0.016405 ms |
| Existing equal-time event-order replay | 0.000510 ms | 0.000088 ms |
| Synthetic descending-time order probe | 0.000618 ms | 0.000476 ms |
| Positions, second separation, queries and ordering | 14.695848 ms | 0.023311 ms |
| State restore-copy replay | 0.001010 ms | 0.000260 ms |
| Failed 64-triangle step with rollback | 0.009796 ms | 0.003476 ms |

The equal-time order probe performs no swaps. The descending-time probe exercises the opposite ordering pattern at the same record count. Its record preparation is outside timing. The solver still uses its original stable insertion sort.

The restore-copy replay copies lists; production rollback moves saved lists. The failed-step fixture includes the error-string check and assertion. Neither row is a pure rollback-only measurement. Unchanged operations can show different diagnostic times because preceding work changes cache state.

The failed-step fixture has two rebound faces and 62 distant padding faces. It exhausts the impact budget and checks full state, force, report and dirty-state restoration. Successful first warmup and all failed retries use the same supported geometry.

## Focused controls

All 79 tests pass across six focused suites, including 17 new controls. The original twenty-test CCD suite passes unchanged. New controls compare indexed and brute outcomes for faces, edges, vertices, tangency, backfaces, overlap and repeated steps. They also exercise reversed tree traversal at equal impact times, unequal mesh materials and equal-time sphere events.

Other controls cover multiple rebounds, impact-budget rollback, reachable-sphere refusal, ghosts, live material changes, pending forces and shape support checks. Snapshot controls include added meshes, discrete/CCD transitions, public pose and shape edits, and forced brute scans over a populated cache. A private corruption probe explicitly tests oracle revalidation and restores the exact triangle before accelerated reuse.

Numeric controls cover minimum and maximum radii, coordinate and relative-extent boundaries, one-ULP boundary separation, zero signs and outward-rounded query bounds. Distant malformed triangles and disabled-owner malformed triangles must still reject. Tree controls cover empty and tiny indexes, all split axes, equal centroids, overlapping bounds, unique candidates, pruning and escape limits.

The retained 23 independent Decimal reference cases reproduce without changes. Focused world, mode, API-guard and shared-physics suites also pass. The existing typed collision-mode negative fixture produces its expected source rejection. New production modules pass warning-as-error documentation builds.

An independent source review found no defect in conservative bounds, cache lifetime, rollback reuse, tie selection or traversal termination. Full changed-module coverage and aggregate qualification remain required in the deferred final batch. No full-coverage percentage is claimed here.

## Reproduction and retained records

Use the pinned environment and an isolated temporary/cache directory. Disable Mojo telemetry. Do not overlap native timings with compiler work.

```sh
mojo build --Werror -I . bench/physics_ccd_bench.mojo -o /tmp/ccd-fixed
mojo build --Werror -I . bench/physics_ccd_index_bench.mojo -o /tmp/ccd-profile
/tmp/ccd-fixed > /tmp/ccd-fixed.csv
/tmp/ccd-profile > /tmp/ccd-profile.csv
cc -shared -fPIC -O2 bench/navigation_allocations.c -o /tmp/ccd-alloc.so
LD_PRELOAD=/tmp/ccd-alloc.so /tmp/ccd-profile /tmp/ccd-alloc.so > /tmp/ccd-allocations.csv
mojo build --Werror -I . tests/test_physics_ccd_index.mojo -o /tmp/test-ccd-index
python3 tools/run_suite.py --seconds 5 --suite tests/test_physics_ccd_index.mojo -- /tmp/test-ccd-index
python3 tools/physics_ccd_reference.py --check docs/validation/continuous-collision-292-reference.json
```

All native phase rows are retained in [run one](continuous-collision-636-profile-1.csv), [run two](continuous-collision-636-profile-2.csv) and [run three](continuous-collision-636-profile-3.csv). The [machine-readable record](continuous-collision-636.json) contains hashes and summaries. The [allocation records](continuous-collision-636-allocations.csv) retain the separate instrumented run.
