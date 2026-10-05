<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Ray-query throughput: exact regularity classification

Unprepared box queries can validate stored ray components without wide sums.
This removes work from both point and Boolean queries.
It preserves the existing query results.
The measured gain does not establish full historical speed recovery.

## Scope and status

[Issue #550](https://github.com/SethKitchen/ThreeMojo/issues/550) follows the wide-range ray correction.
The baseline here is the current correct implementation at `747f4987ef637ff5b6e6756847a90c23d193da93`.
Its tree is `5e1668ca3d824d8b0def8f200f2555ae099dc660`.
The candidate changes only the unprepared box regularity calculation in production code.

Sphere arithmetic, slab comparisons, endpoint selection, point reconstruction, and Gaussian logic stay unchanged.
Prepared Octree and Gaussian ray products also stay unchanged.
No coordinate cutoff, tolerance, or approximate path is added.

Focused verification and the complete benchmark matrix are recorded below.
Full changed-module coverage and repository aggregate checks remain deferred to final batch validation.
This report does not claim those checks passed.
It does not claim the historical 3% target was met.

The owner accepted the documented current performance for implementation completion.
That acceptance does not establish the historical 3% target.
Final batch validation remains pending.

## Exact classification proof

Both inputs are four-lane Float32 vectors with a zero padding lane.
Clearing each sign bit gives the following encoding classes:

- Zero, including negative zero: bits equal zero.
- Finite nonzero values, including subnormals: bits below `0x7F800000` and above zero.
- Infinity or NaN: bits at or above `0x7F800000`.

The new helper requires every component to be finite and some direction component to be nonzero.
These tests use integers.
They do not introduce floating subnormal comparisons.

The old regularity check widens each stored Float32 component to Float64.
For finite inputs, the sum of absolute direction components is positive exactly when the direction is nonzero.
All finite component sums remain far below Float64 overflow.
Any nonfinite component makes the old final finite comparison false.
This includes opposite infinities whose sum is NaN.
Thus the two predicates agree under the existing IEEE-value contract.

The padding lane cannot reject a finite ray or create a nonzero direction.
Empty and NaN bounds are still rejected before invalid-ray compatibility behavior.
No claim is made about whole-query support for non-default denormal modes.

## Arithmetic and inlining investigation

The compiler already inlines the box helpers in the complete query loops.
The baseline and candidate contain no out-of-line box-query calls there.
The compiler also removes unused parts of the requested ray-product value.
The remaining wide conversions and sums still cost time.
The new classification removes that work directly.

The Boolean box loop remains division-free.
The point loop retains its selected-face reciprocal and the same coordinate reconstruction.
The sphere loops retain their instruction counts and arithmetic source.
The consumer loops retain the common Gaussian and Octree implementations.

[Static instruction counts](ray-query-550-profile.json) include each full loop and its checksum.
They are not dynamic instruction counts or hardware-counter measurements.

| Complete native loop | Baseline instruction records | Candidate instruction records |
| --- | ---: | ---: |
| Sphere point | 157 | 157 |
| Sphere Boolean | 194 | 194 |
| Box point | 399 | 347 |
| Box Boolean | 105 | 94 |

Exploratory builds also tested forced inlining, lazy far-face selection, shared pairwise endpoint products, scalar pair evaluation, and paired coordinate reconstruction.
None beat the smaller classification-only candidate consistently.
They were not retained.
The shared-product candidate preserved comparisons, but extra selection work outweighed the saved arithmetic.
No duplicated slab implementation was added.

## Workloads and method

The original benchmark source and binaries were unavailable.
The query and Gaussian drivers are reconstructions from the issue's recorded specification.
The physics mesh is a new, fully specified consumer workload.
No result is presented as an identical rerun of a historical binary.

Both variants use the same new benchmark drivers.
Only their source import roots differ.
Each run uses Mojo `1.1.0` (`8189361e`), `--Werror`, and disabled telemetry.
Measurements run serially on one fixed logical CPU of a shared Linux x86-64 host.

Each matrix has eight paired rounds and five samples per binary per round.
The binary order alternates between baseline/candidate and candidate/baseline.
This gives 40 samples per variant and workload.
Every sample is retained.
A paired ratio compares the two medians within one round.

The runner verifies source inventories and binary hashes before and after measurement.
It rejects missing workloads, wrong counts, nonfinite checksums, and unequal result checksums.
It refuses Python's optimized mode, which would disable its assertions.
Machine paths and host details are retained privately.
Public evidence retains pinned versions, source and binary hashes, flags, values, and generic reproduction commands.

### Primitive queries

The driver constructs 256 rays once.
Their origins are `(-5, (i%32)*0.15-2, (i//32)*0.2-0.5)`.
Their input direction is `(1,0.01,0.02)`.
The Ray constructor normalizes it once.
The sphere is centered at zero with radius `1.5`.
The box is `[-1,1]^3`.

The primary run repeats each complete set 4000 times: 1,024,000 calls per row.
The longer confirmation uses 36000 repeats: 9,216,000 calls per row.
It does not remove or simplify queries.
Every returned point coordinate contributes to a Float64 checksum.

### Gaussian consumer

The object contains a 64 by 64 grid at `z=-10`, with 0.5 spacing.
Centers use `((x-32)*0.5,(y-32)*0.5,-10)`.
Every covariance is `[0.04,0.01,0,0.06,0,0.03]`, and every color is opaque.
The 1000 rays start at `((i%10)*0.1,(i%7)*0.1,0)` and point along negative z.

One row contains 1000 public raycasts and 4,096,000 splat-candidate visits.
The recorded work count denotes candidate visits, not public calls.
Every returned index, distance, and point coordinate is consumed.
Geometry construction and initial bounds construction are outside the timer.

### Physics consumer

The world contains a static 32 by 32 grid of four-meter squares, split into 2048 triangles.
It builds the Octree before timing.
Each row makes 5600 complete `PhysicsWorld.raycast` calls from height five, with a ten-meter reach.

Ray x is `((i*17)%128)+0.25`.
Ray y is `((i*29+(i//128)*13)%128)+0.5`.
The unequal fractional offsets avoid an all-diagonal shared-edge workload.
The additional row term avoids a 128-origin repetition.
Every hit field is consumed, including the normal, body, and material.

## Results

The machine-readable record contains the primary and longer matrices, compilation data, and earlier complete exploratory qualification runs.
Use the latest final-source matrices for the final comparison.
Shared-host variation remains visible in the raw samples and interquartile ranges.
No outlier filter is used.

### Primary matrix

| Workload | Baseline median (ms) | Candidate median (ms) | Candidate / baseline | Paired-round median ratio |
| --- | ---: | ---: | ---: | ---: |
| sphere point | 7.529 | 7.626 | 1.0129 | 1.0103 |
| sphere bool | 6.045 | 5.992 | 0.9912 | 0.9997 |
| box point | 12.567 | 10.485 | 0.8344 | 0.8292 |
| box bool | 6.409 | 5.501 | 0.8583 | 0.8564 |
| gaussian | 111.046 | 108.353 | 0.9757 | 0.9724 |
| physics mesh | 8.488 | 8.583 | 1.0111 | 1.0194 |

### Longer confirmation

| Workload | Baseline median (ms) | Candidate median (ms) | Candidate / baseline | Paired-round median ratio |
| --- | ---: | ---: | ---: | ---: |
| sphere point | 67.253 | 67.231 | 0.9997 | 0.9724 |
| sphere bool | 56.009 | 56.067 | 1.0010 | 0.9668 |
| box point | 112.992 | 99.186 | 0.8778 | 0.8554 |
| box bool | 59.363 | 51.639 | 0.8699 | 0.8765 |
| gaussian | 110.631 | 113.384 | 1.0249 | 1.0148 |
| physics mesh | 8.350 | 8.605 | 1.0305 | 1.0098 |


The box gain is present in both complete matrices.
Sphere and consumer results do not establish a general speed gain.
Their smaller changes must be read with the paired ratios and spread.
Keep the observed physics tradeoff; do not dismiss it as zero cost.
These workloads do not establish universal LiDAR throughput or frame-time guarantees.

## Compilation and code size

The query binary's text section changes from 49,271 to 48,834 bytes.
The consumer binary's text section changes from 103,633 to 103,489 bytes.
The full query files remain 73,856 bytes because executable layout includes alignment and other sections.

Build wall times are recorded per binary.
They are diagnostic single builds with compiler caches already populated.
They do not establish a general compile-time improvement.

The MAX `26.6.0` validation driver compiles public sphere and box queries plus prepared box queries for SM80.
It compiles both revisions with contraction enabled and disabled.
All four checks pass without device execution.

The default-contraction PTX changes from 82,165 to 80,524 bytes.
The contraction-disabled PTX changes from 83,685 to 82,007 bytes.
Neither output contains `.ftz` instructions.
Explicit FMA operations in the existing exact arithmetic remain when implicit contraction is disabled.
Compilation does not establish physical GPU correctness or performance.

## Correctness verification

Ten focused native suites pass with the unchanged five-second per-test gate.
They contain 222 tests.
The ray, throughput, and Gaussian-precision suites also pass with contraction disabled: 77 additional executions.

The controls cover ordinary results, extreme and tiny scales, distant diagonals, translated centers, tangency, behind-origin rays, and empty bounds.
They also cover near/far clipping, analytic ellipsoids, invalid mutable rays, infinite bounds, and finite points with parameters beyond Float32 range.

New tests compare stored-component classification with the unchanged wide snapshot predicate.
They cover signed zeros, minimum and maximum subnormals, minimum normal values, maximum finite values, infinities, and NaN signs.
They also check 10,000 deterministic sets of arbitrary storage bits.
Minimum-subnormal-only directions exercise hits and both box rejection routes.

The production patch, benchmark harness, and final evidence received independent source review.
The review verified all 1920 published rows, identities, test logs, and PTX records.
It found no blocking correctness, evidence, or wording defect.
Full coverage, complete CPU/GPU gates, and aggregate CI remain pending for the final batch.

## Reproduction

Create separate baseline and candidate source roots.
Use the pinned CPU environment and a unique temporary/cache root.
Keep the output directory outside both source roots.

```sh
export MODULAR_TELEMETRY_ENABLED=false
python3 CANDIDATE/bench/run_ray_query_bench.py \
  --baseline BASELINE --candidate CANDIDATE --output RESULTS \
  --mojo mojo --cpu CPU --pairs 8 --samples 5 --repeats 4000
```

Repeat with `--repeats 36000` and a new output directory for the longer matrix.
Use the pinned MAX environment for compilation-only checks:

```sh
mojo build --Werror --fp-mode=contract=fast -I SOURCE \
  CANDIDATE/docs/validation/ray-query-550-gpu.mojo -o gpu-compile
./gpu-compile > ray-query.ptx
```

Repeat for each source root and `--fp-mode=contract=off`.
The executable emits compiled PTX; it does not launch a device kernel.

## Evidence

- [Summary, identities, and compilation records](ray-query-550.json)
- [Primary raw trials](ray-query-550-primary-trials.csv)
- [Longer raw trials](ray-query-550-long-trials.csv)
- [Earlier primary raw trials](ray-query-550-earlier-primary-trials.csv)
- [Earlier longer raw trials](ray-query-550-earlier-long-trials.csv)
- [Static native loop profile](ray-query-550-profile.json)
- [Query driver](../../bench/ray_query_bench.mojo)
- [Consumer driver](../../bench/ray_query_consumers.mojo)
- [Paired runner](../../bench/run_ray_query_bench.py)
- [GPU compilation driver](ray-query-550-gpu.mojo)
