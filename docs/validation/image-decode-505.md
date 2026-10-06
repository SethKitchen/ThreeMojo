# Bounded image decode scheduling: #505 evidence

The shared queue improves the measured mixed-image cases at four workers, with higher peak RSS in those cases.
This report documents the design, complete benchmark matrix, and focused correctness evidence for [#505](https://github.com/SethKitchen/ThreeMojo/issues/505).
The implementation and focused checks are complete.
Broad batch qualification is deferred until all in-scope issues are implemented.

The baseline is `51b4424ceef57fef1f8a5e787c583126f999baf5`.
The candidate is an uncommitted source snapshot, identified by its recorded source hashes.
The benchmark uses the same public APIs and unchanged driver for all three variants.
Both completed runs use the full original matrix; no cases or outliers are removed.

## Decision and limits

Use the shared queue as the candidate design for bounded, dynamically assigned image jobs.
Do not infer a universal speedup or a reduction in total memory.
The nine-repetition run shows 1.985–2.185× paired median speedups against batches for the four mixed-image cases at four workers.
Their paired median RSS ratios are 1.322–1.379, or about 32–38% higher.
The high-worker and uniform controls include regressions and substantial variation.

The queue limits concurrent image reads and decodes.
It does not impose a constant byte limit or discard completed outputs.
This report proposes no workload heuristic, worker cap, or automatic scheduler switch.
Performance results remain descriptive measurements from one shared host, without a claim of statistical significance.

## Scheduler and ownership

One atomic counter assigns source-order indices to persistent workers.
Each worker reads and decodes one image before it claims another.
The parallel path creates `min(max(workers, 1), N)` tasks for `N` jobs.
It creates no task per additional image and has no barrier between image groups.
The serial path uses the calling thread; empty input creates no tasks.

The source, counter, and fixed-size result and error storage remain alive until every task joins.
A worker writes only its claimed index.
The result and error lists do not grow or move during concurrent access.
After the join, the caller checks errors in source order and moves successful textures into their destination.
Empty `Optional[Texture]` slots allocate no pixels, mip chains, or color ramps.

The queue retains at most `W` active compressed-input and decoder working sets, where `W = min(max(workers, 1), N)`.
Each active image can have a different size and decoder allocation pattern.
Total storage also includes resident sources, retained final textures and mip chains, and O(N) job, result, and error metadata.
Resident glTF sources include parsed JSON, data URI text, and binary buffers.
Those sources are outside the active-job bound.

The queue reads compressed data after a worker claims a job.
It does not eagerly duplicate every image into a second compressed-input list.
The provider releases its input and scratch before the next claim.
Completed pixel and mip buffers move without another queue-owned copy.
Image decoders can still allocate their own working copies.

RSS measures the entire native process, including runtime, allocator retention, sources, outputs, and work outside the timer.
It cannot isolate decoder scratch or count allocations.
More overlap between large image jobs can increase peak RSS even when the active-job bound holds.
The measured mixed-image increase is consistent with that tradeoff; this experiment does not attribute individual allocations.

See [Image decode queue](../wiki/Image-decode-queue.md) for the API contract.

## Order, deduplication, and failure

Successful completion order does not change the published texture order.
CARLA uses binding and file traversal order, deduplicated by image path and color space.
glTF uses first material/core-map traversal order, deduplicated by texture index and color space.
One image used in two color spaces remains two jobs.
Existing CARLA cache entries are excluded from new work.

Parallel workers finish before the first source-order error is raised.
An empty error message remains a failure.
Failed CARLA preload publishes no new cache entries and preserves existing keys and buffers.
A retry owns fresh queue state and inserts each missing key once.
The registry still records the requested worker count before decoding.

Failed glTF predecode publishes no textures.
This guarantee covers predecode, not the entire glTF load.
Later material, mesh, or node failures can still change stores.
One-worker glTF loading retains its lazy path.
Extension-only maps remain lazy at every worker count.

The previous glTF batch read every image in a group before starting its decodes.
A later read error could therefore hide an earlier decode error.
The queue consistently reports the first failing job in source order.
Tests cover both acquisition-first and decode-first failures.
Existing read-error text, decoder `glTF:` prefixes, and CARLA serial/parallel error formatting are retained.

## Experiment

The matrix contains 16 images, four datasets, two APIs, four requested worker counts, and three variants.
Requested workers are 1, 2, 4, and 17.
The last value exceeds the image count; the candidate uses 16 tasks for that case.
The runtime reports parallelism 9 for every native sample.

| Variant | Source and scheduling |
|---|---|
| Batch (`baseline`) | Exact baseline revision; bounded groups wait before the next group |
| Dynamic (`dynamic`) | Candidate production queue, shared by CARLA preload and parallel glTF predecode |
| Stride (`stride`) | Experimental candidate copy; persistent workers receive every Wth source index |

The stride copy changes only `loaders/image_batch.mojo` relative to the candidate.
It retains the candidate's providers, result storage, moves, and error handling.
It is a benchmark control, not a proposed production fallback.
The batch comparison measures the integrated change; the stride comparison narrows the difference to scheduling.

| Dataset | Dimensions in source order | Large indices, zero-based | Compressed PNG bytes | Retained pixel/mip bytes |
|---|---|---|---:|---:|
| `uniform_tiny` | Sixteen 16×16 images | None | 15,372 | 21,824 |
| `uniform_medium` | Sixteen 256×256 images | None | 3,251,704 | 5,592,384 |
| `stride_skew` | Four 768×768 images, twelve 64×64 images | 0, 4, 8, 12 | 2,920,811 | 12,845,008 |
| `batch_boundary` | Four 768×768 images, twelve 64×64 images | 3, 4, 11, 12 | 2,920,626 | 12,845,008 |

Fixtures use deterministic opaque RGBA8 pixels, PNG filter zero, and zlib level six.
The generator records zlib 1.3.2 and SHA-256 hashes for every input.
Each glTF material is used by a real triangle.
These inputs test scheduling alignment, not the distribution of production assets.
They do not benchmark JPEG, HDR, WebP, KTX2, network I/O, or cold storage.

### Timing and pairing

Each sample launches one fresh native process, and samples run serially.
The runner reads case inputs into the OS page cache before each three-variant trial.
Case order is shuffled by the recorded seed.
Variant order rotates so each variant leads equally often.
No decode or task warm-up occurs; the driver queries runtime parallelism before timing.

The glTF timer covers `read_gltf`, including JSON and geometry loading.
The registry timer covers `AssetRegistry.preload`; `AssetRegistry.open` occurs before timing.
Post-timer checksums visit every pixel and mip byte and record shape, dimensions, mip offsets, and counts.
RSS includes setup and these post-timer checksums.
Reported speed uses native `load_ns`, not wrapper wall time.

| Run | UTC interval on 2026-10-04 | Seed | Repetitions per variant/case | Native rows |
|---|---|---:|---:|---:|
| Initial | 19:10:25–19:11:27 | 505 | 3 | 288 |
| Confirmation | 19:12:36–19:15:48 | 1505 | 9 | 864 |

The confirmation run repeats the predeclared whole matrix without changing inputs, variants, workers, or measurement implementation.
All 1,152 rows pass the fixture oracle and output parity checks.
Those checks compare variants, workers, repetitions, and both APIs.
The fixture independently supplies expected base pixels, byte counts, mip counts, and texture counts.
Full-mip and shape hashes establish parity, not an independent reference for the mip-generation algorithm.

The measurements use Linux x86-64, and the runtime reports capacity for nine workers.
Mojo is 1.1.0 (`8189361e`), and benchmark builds use `--Werror -O3`.
The RSS helper uses GCC 14.2.0 with `-O2 -std=c11 -Wall -Wextra -Werror`.
The host is shared, without CPU isolation or controlled frequency.
Cgroup limit and governor reads are unavailable; they are not evidence of unlimited resources.

Before each build or sample, the harness requires at least 3 GiB available memory and 2 GiB workspace space.
Machine-specific host and resource details are omitted from the public record.
These checks prevent unsafe launches; they do not remove scheduling noise.

### Corrected RSS measurement

Only the two complete runs above provide valid RSS evidence.
An earlier smoke run measured a direct child of the Python runner.
Its `wait4` high-water value retained the Python parent's pre-exec resident-memory floor.
A minimal successful-process control reproduced the inherited floor.
The smoke RSS values are discarded, not corrected by subtraction.

The retained harness first executes a small C supervisor, then forks and executes the measured native child.
The supervisor reports that child's `wait4` result, not Python's cumulative child usage or the supervisor's own peak.
Linux KiB values are converted to bytes.
The marker carries exit status, signal, execution error, CPU time, faults, and context switches.
The runner rejects missing, duplicate, malformed, or inconsistent measurement records.

The original 13 harness checks pass.
Six later rejection checks expand the final suite to 19 passing tests without changing the measurement implementation.
Controls cover a 128 MiB live Python parent, independent large/small children, failed execution, signals, units, and timeout cleanup.
Tampered inputs and binaries, incorrect output hashes, and supervisor status mismatches are rejected.
The final timeout test verifies termination of both the native child and its descendant without relying on reusable PIDs.

## Results

All table ratios are medians of paired ratios, not ratios of separately computed medians.
For repetition `i`, speedup is `reference_load_ns[i] / dynamic_load_ns[i]`.
RSS ratio is `dynamic_peak_rss_bytes[i] / reference_peak_rss_bytes[i]`.
Speed above 1 favors the queue; RSS above 1 means the queue uses more whole-process memory.
MiB means 1,048,576 bytes.

The JSON and CSV summaries retain minimum, maximum, median, and unscaled median absolute deviation for every distribution.
MAD is `median(abs(sample - median(samples)))`.
They include all three variants' latency, RSS, image throughput, and base-megapixel throughput.
Both paired comparisons include full distributions, without trimming outliers.
The tables round values for readability; the artifacts preserve source precision.

### Nine-repetition confirmation: all 32 cases

| Dataset | API | Workers | Dynamic ms | Dynamic MiB | Speed vs batch | Speed vs stride | RSS vs batch | RSS vs stride |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `batch_boundary` | gltf | 1 | 312.066 | 32.59 | 0.988 | 0.997 | 1.000 | 0.999 |
| `batch_boundary` | gltf | 2 | 163.560 | 39.77 | 1.876 | 1.239 | 1.133 | 0.995 |
| `batch_boundary` | gltf | 4 | 143.333 | 47.18 | 2.185 | 1.274 | 1.379 | 1.169 |
| `batch_boundary` | gltf | 17 | 140.134 | 48.39 | 0.996 | 1.147 | 0.943 | 0.972 |
| `batch_boundary` | registry | 1 | 311.704 | 32.54 | 1.051 | 0.948 | 1.002 | 1.000 |
| `batch_boundary` | registry | 2 | 168.458 | 40.82 | 1.813 | 0.935 | 1.178 | 0.993 |
| `batch_boundary` | registry | 4 | 156.954 | 47.86 | 1.985 | 1.085 | 1.331 | 1.128 |
| `batch_boundary` | registry | 17 | 155.034 | 48.86 | 0.697 | 1.002 | 0.969 | 1.016 |
| `stride_skew` | gltf | 1 | 319.289 | 32.69 | 0.971 | 1.029 | 0.999 | 1.000 |
| `stride_skew` | gltf | 2 | 173.111 | 40.71 | 1.876 | 2.006 | 1.186 | 1.189 |
| `stride_skew` | gltf | 4 | 153.478 | 46.65 | 2.022 | 2.285 | 1.362 | 1.400 |
| `stride_skew` | gltf | 17 | 97.586 | 49.52 | 1.041 | 1.389 | 0.973 | 1.008 |
| `stride_skew` | registry | 1 | 323.498 | 32.69 | 0.993 | 0.978 | 1.003 | 1.000 |
| `stride_skew` | registry | 2 | 164.035 | 41.93 | 1.938 | 1.886 | 1.218 | 1.248 |
| `stride_skew` | registry | 4 | 152.977 | 45.61 | 2.054 | 2.009 | 1.322 | 1.379 |
| `stride_skew` | registry | 17 | 154.124 | 49.54 | 1.026 | 0.812 | 1.026 | 0.989 |
| `uniform_medium` | gltf | 1 | 202.260 | 16.75 | 1.066 | 1.023 | 1.001 | 1.002 |
| `uniform_medium` | gltf | 2 | 112.249 | 18.48 | 1.038 | 1.177 | 0.967 | 1.010 |
| `uniform_medium` | gltf | 4 | 63.836 | 21.99 | 1.330 | 1.702 | 0.957 | 1.017 |
| `uniform_medium` | gltf | 17 | 55.089 | 26.75 | 1.045 | 1.230 | 0.902 | 0.995 |
| `uniform_medium` | registry | 1 | 206.116 | 16.69 | 1.030 | 1.049 | 1.002 | 0.999 |
| `uniform_medium` | registry | 2 | 112.654 | 18.45 | 1.195 | 1.002 | 0.939 | 0.993 |
| `uniform_medium` | registry | 4 | 73.727 | 21.52 | 1.361 | 1.310 | 0.965 | 0.991 |
| `uniform_medium` | registry | 17 | 55.448 | 27.10 | 1.038 | 0.953 | 0.985 | 0.999 |
| `uniform_tiny` | gltf | 1 | 2.369 | 9.30 | 0.979 | 0.853 | 1.001 | 1.013 |
| `uniform_tiny` | gltf | 2 | 1.788 | 9.04 | 1.563 | 1.099 | 0.995 | 1.008 |
| `uniform_tiny` | gltf | 4 | 1.575 | 9.07 | 1.435 | 1.086 | 1.018 | 0.997 |
| `uniform_tiny` | gltf | 17 | 1.604 | 8.97 | 1.057 | 0.946 | 0.976 | 0.991 |
| `uniform_tiny` | registry | 1 | 1.770 | 9.16 | 0.980 | 1.016 | 1.013 | 1.007 |
| `uniform_tiny` | registry | 2 | 1.265 | 9.19 | 1.700 | 1.082 | 0.989 | 0.997 |
| `uniform_tiny` | registry | 4 | 0.967 | 9.07 | 1.611 | 1.049 | 1.006 | 1.016 |
| `uniform_tiny` | registry | 17 | 1.048 | 9.19 | 0.844 | 0.936 | 1.014 | 1.032 |

### Three-repetition initial run: all 32 cases

| Dataset | API | Workers | Dynamic ms | Dynamic MiB | Speed vs batch | Speed vs stride | RSS vs batch | RSS vs stride |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `batch_boundary` | gltf | 1 | 306.311 | 32.65 | 1.011 | 1.023 | 1.001 | 1.005 |
| `batch_boundary` | gltf | 2 | 167.585 | 43.19 | 1.928 | 2.109 | 1.226 | 1.030 |
| `batch_boundary` | gltf | 4 | 146.410 | 48.37 | 2.159 | 2.198 | 1.409 | 1.297 |
| `batch_boundary` | gltf | 17 | 95.220 | 50.45 | 1.026 | 1.049 | 1.033 | 1.016 |
| `batch_boundary` | registry | 1 | 332.066 | 32.70 | 1.044 | 0.957 | 1.001 | 1.003 |
| `batch_boundary` | registry | 2 | 164.323 | 43.85 | 2.001 | 1.004 | 1.230 | 1.089 |
| `batch_boundary` | registry | 4 | 160.953 | 46.25 | 2.747 | 0.997 | 1.328 | 1.109 |
| `batch_boundary` | registry | 17 | 154.851 | 50.47 | 1.010 | 0.603 | 1.062 | 0.979 |
| `stride_skew` | gltf | 1 | 316.528 | 32.73 | 1.126 | 1.059 | 0.997 | 0.998 |
| `stride_skew` | gltf | 2 | 209.420 | 38.52 | 1.651 | 1.627 | 1.135 | 1.108 |
| `stride_skew` | gltf | 4 | 153.937 | 45.39 | 2.074 | 2.236 | 1.320 | 1.363 |
| `stride_skew` | gltf | 17 | 146.849 | 50.80 | 0.731 | 1.148 | 0.947 | 0.999 |
| `stride_skew` | registry | 1 | 324.861 | 32.69 | 0.929 | 0.905 | 1.005 | 1.001 |
| `stride_skew` | registry | 2 | 224.400 | 41.35 | 1.420 | 1.506 | 1.209 | 1.192 |
| `stride_skew` | registry | 4 | 154.714 | 47.29 | 2.568 | 1.861 | 1.354 | 1.423 |
| `stride_skew` | registry | 17 | 95.851 | 51.23 | 1.595 | 1.033 | 1.081 | 0.983 |
| `uniform_medium` | gltf | 1 | 204.238 | 16.75 | 1.018 | 1.000 | 1.000 | 1.003 |
| `uniform_medium` | gltf | 2 | 112.593 | 18.74 | 1.200 | 1.181 | 0.980 | 1.011 |
| `uniform_medium` | gltf | 4 | 94.282 | 22.17 | 1.052 | 1.117 | 0.969 | 1.008 |
| `uniform_medium` | gltf | 17 | 52.841 | 27.50 | 1.093 | 1.270 | 0.897 | 0.994 |
| `uniform_medium` | registry | 1 | 234.125 | 16.80 | 1.232 | 0.856 | 1.015 | 1.013 |
| `uniform_medium` | registry | 2 | 105.120 | 18.58 | 1.774 | 0.980 | 0.975 | 1.018 |
| `uniform_medium` | registry | 4 | 79.319 | 21.80 | 1.287 | 1.247 | 0.982 | 0.991 |
| `uniform_medium` | registry | 17 | 59.000 | 27.62 | 1.138 | 0.866 | 1.012 | 0.995 |
| `uniform_tiny` | gltf | 1 | 2.459 | 9.11 | 0.821 | 0.889 | 1.003 | 0.991 |
| `uniform_tiny` | gltf | 2 | 1.785 | 8.96 | 1.431 | 1.104 | 0.994 | 1.000 |
| `uniform_tiny` | gltf | 4 | 2.181 | 9.31 | 1.251 | 1.092 | 0.986 | 1.009 |
| `uniform_tiny` | gltf | 17 | 1.332 | 8.89 | 1.450 | 1.441 | 0.957 | 0.961 |
| `uniform_tiny` | registry | 1 | 1.679 | 9.23 | 0.959 | 1.094 | 1.009 | 1.013 |
| `uniform_tiny` | registry | 2 | 1.147 | 8.89 | 1.919 | 0.995 | 0.962 | 0.987 |
| `uniform_tiny` | registry | 4 | 0.908 | 8.88 | 1.547 | 2.208 | 0.999 | 0.966 |
| `uniform_tiny` | registry | 17 | 1.105 | 8.96 | 0.711 | 0.979 | 0.986 | 1.004 |

### Mixed-image gains and their costs

The four-worker mixed cases show the queue's intended scheduling benefit alongside its memory cost.
Their nine-repetition paired distributions are below.
Ranges include every sample, including unfavorable outliers.

| Dataset | API | Batch speed median / MAD / range | Stride speed median / MAD / range | RSS ratio vs batch median / MAD / range |
|---|---|---:|---:|---:|
| `batch_boundary` | gltf | 2.185 / 0.179 / 1.987–3.582 | 1.274 / 0.239 / 1.036–2.032 | 1.379 / 0.039 / 1.279–1.499 |
| `batch_boundary` | registry | 1.985 / 0.159 / 1.379–3.465 | 1.085 / 0.477 / 0.607–3.010 | 1.331 / 0.067 / 1.229–1.414 |
| `stride_skew` | gltf | 2.022 / 0.202 / 0.347–4.049 | 2.285 / 0.300 / 0.626–3.491 | 1.362 / 0.076 / 1.286–1.604 |
| `stride_skew` | registry | 2.054 / 0.350 / 1.704–3.443 | 2.009 / 0.309 / 1.699–3.730 | 1.322 / 0.062 / 1.260–1.453 |

With four workers, `stride_skew` assigns all four large jobs to stride worker zero.
The other three workers cannot take those jobs after finishing their small images.
Dynamic claims distribute remaining work to free workers.
The confirmation paired median speedups against stride are 2.285× for glTF and 2.009× for registry preload.
At two workers, the same large indices also align on one stride worker.

`batch_boundary` places large images around the four-worker batch boundaries.
Fixed groups wait for each group's largest image before admitting the next group.
Stride splits its large jobs between two workers at four workers, so it avoids part of the batch penalty.
The queue's corresponding median gains against stride are smaller: 1.274× for glTF and 1.085× for registry preload.
The registry stride comparison has a 0.477 MAD and a 0.607–3.010 range.
This control shows why the result depends on workload alignment.

### High-worker regressions and uniform controls

At 17 requested workers, the queue has 16 tasks for 16 images, while runtime parallelism remains 9.
The baseline can already put all images into one batch.
Stride assigns at most one image to each task, leaving no repeated-stride imbalance to correct.
This setting does not offer the same scheduling opportunity as the four-worker mixed cases.

Confirmation registry preload on `batch_boundary` has a 0.697× speed median against batch: about 43% longer paired latency.
Its paired speed range is 0.532–1.290, with MAD 0.165.
Registry `uniform_tiny` at 17 workers has a 0.844× batch speed median: about 18% longer paired latency.
Registry `stride_skew` at 17 workers has a 0.812× median against stride: about 23% longer paired latency.
These regressions are part of the result, not discarded cases.

The high-worker results also change across runs.
Initial glTF `stride_skew` at 17 workers gives 0.731× against batch; confirmation gives 1.041×.
Registry `batch_boundary` changes from 1.010× to 0.697×.
The samples establish variation and case-dependent overhead, not the cause of every difference.
No instrumentation here separates queue claims, task startup, runtime contention, or host interference.

Both uniform datasets appear at every worker count in both tables.
At one worker, ordinary timing variation already produces paired medians on either side of 1.
Confirmation four-worker uniform cases improve against batch, but this does not predict all small-image workloads.
Tiny-case load times are around one to three milliseconds, where small absolute changes produce large ratios.
Retain all controls when evaluating the mixed-case gains.

## Focused correctness evidence

The production scheduler and real loader tests pass for the measured source snapshot.
Tests inspect exact pixels and metadata rather than relying only on elapsed time.
The retained logs and source hashes are in the provenance artifact.

| Evidence | What the passing tests establish |
|---|---|
| `tests/test_image_queue.mojo`: 4 tests | Unique claims; count/worker boundaries; bounded provider-owned active jobs and staged bytes; unchanged pixel/mip buffer addresses; deterministic errors; clean retries |
| Queue slow-first handshake | With parallelism above one, job 2 finishes while job 0 is active; two workers can advance beyond a stalled first job |
| `tests/test_gltf_loader_additions.mojo`: 18 tests | Core-map and color-space parity; ordered texture IDs; file/data-URI/buffer-view parity; sampler and mip metadata; source-order failures; predecode publication atomicity |
| `tests/test_carla_assets.mojo`: 33 tests | First-use order; one decode per path/color-space key; repeat-preload deduplication; exact pixels and complete mip chains; preserved existing cache buffers on failure and retry |
| Shared-module instrumented tests | `test_image_batch` and `test_image_queue` cover 41/41 lines and 22/22 branch outcomes in `loaders/image_batch` |
| Python fixture/measurement tests | Final 19/19 pass, including rejection controls and corrected RSS measurement |

The scheduler counter test uses counts −1, 0, 1, and 5 and workers −1, 0, 1, 2, and 8.
Its staging counter covers provider-owned allocations, not all process allocations.
Pointer equality checks show that the scheduler moves completed mip buffers without copying them.
The bounded handshake has a deadline and fails if expected progress is absent.
A one-thread runtime cannot prove simultaneous execution; this measured runtime reports nine threads.

The glTF source tests compare external files, data URIs, and buffer views at two and eight workers.
They verify six texture/color-space jobs from three reused images and preserve texture IDs, sampler modes, alpha, and complete pixel/mip data.
Failure tests reverse acquisition and decode error order and check the reported first source error.
They also keep a preexisting texture while rejecting new predecode results.

CARLA tests preserve first-use order across five images and workers 1, 2, 3, and 8.
Failure/retry tests retain preexisting keys and buffer addresses and verify a later retry inserts each missing key once.
Other tests cover serial/parallel error text, both color spaces, and complete mip chains.
These tests complement the benchmark's opaque PNG fixtures.

Shared-queue coverage is focused evidence only.
The module has zero condition and MC/DC obligations in that instrumented run.
It is not a 100% coverage claim for the glTF loader, CARLA registry, or complete repository.

## Qualification status

The implementation is complete; full batch validation remains deferred by user direction.
Do not describe the deferred checks as passed.
The affected scope includes 68 CPU test suites and 10 other CPU entry points, for 78 native CPU consumers.
Two affected GPU suites require a separate disposition.
The queue-only coverage result does not close the three-module coverage requirement.

| Gate | Status when this report was prepared |
|---|---|
| Both full benchmark matrices and output checks | Passed: 288 + 864 rows |
| Focused queue, glTF, and CARLA tests | Passed |
| Fixture and RSS harness tests | Passed: 19 tests |
| Shared queue coverage | Passed: 41 lines, 22 branch outcomes |
| Changed production-module lint | Passed for `image_batch`, `gltf`, and CARLA `assets` |
| Format and documentation checks | Passed after report/wiki integration: seven changed Mojo files and 121 documentation files |
| All 68 affected CPU test suites | Passed with warnings as errors and the original five-second per-test gate |
| Ten non-test CPU entry points | New benchmark driver compiled in all three variants; nine other entry points deferred |
| Full coverage of all three changed production modules | Deferred to final batch validation by user direction |
| Two affected GPU suites | Deferred to final batch validation |
| Whole-repository aggregate checks | Deferred until all in-scope issues are implemented; base remains draft |
| Fresh source-bound anatomy report | Deferred to final batch validation; prior report remains unchanged |

The existing five-second per-test limit, coverage thresholds, and workloads remain unchanged.
The exact [consumer inventory and receipts](image-decode-505-consumers.json) distinguish the 68 test suites from ten other entry points and two GPU suites.
The latest user direction defers broad checks until the implementation batch is complete.
The deferred gates must still be reported separately; no full-repository pass is claimed.

## Retained artifacts and provenance

The checked-in packet preserves all samples in normalized UTF-8 form.
It avoids repeated command strings, duplicate stdout records, and repeated source inventories.
No timing or memory sample is dropped.
Hashes identify the original privately retained evidence.
The public record removes absolute machine paths, resource identifiers, installed-environment details, and unnecessary host metadata.
All measurements, source inventories, and validation outcomes are retained.
Those hashes identify the original files; the compact packet does not reproduce omitted stderr bytes.

- [Artifact checksums](image-decode-505-SHA256SUMS): SHA-256 for each packet file
- [Complete JSON summaries](image-decode-505-summary.json): 64 cases, including both runs and both comparisons
- [Complete CSV summaries](image-decode-505-summary.csv): the same distributions in flat columns
- [Normalized trials](image-decode-505-trials.csv): all 1,152 native rows, pair/order keys, output hashes, and measurement diagnostics
- [Provenance](image-decode-505-provenance.json): input hashes, complete source inventories, generic build commands, artifact hashes, and sanitized focused logs
- [Independent recomputation](image-decode-505-recompute.py): standard-library Python; no compiler, decoder, or native child execution

The provenance record expands each source inventory from a baseline map plus variant-specific changes.
The recomputation script verifies each expanded tree digest, every trial's output oracle, complete matrix coverage, and balanced variant order.
It independently recomputes every summary and checks the checked-in JSON and CSV.
The recomputed original distributions match both original `summary.json` files exactly.

Build metadata records the toolchain version at compilation.
Only the necessary pinned toolchain versions and flags are published.
Installed toolchain locations and machine-specific installation details are omitted.
Driver, fixture, helper, binary, and run-source hashes bind the measured artifacts separately.

The build-stage runner hash differs from the final measurement-runner hash because the RSS harness was corrected after native compilation.
Both valid runs record the same final runner hash.
The native driver and all three native binaries remain unchanged across those runs.
The final Python test-only expansion also leaves that measurement implementation unchanged.

## Reproduce

Use Linux, Mojo 1.1.0 (`8189361e`), GCC 14.2.0, Python 3.12.14, and zlib 1.3.2 for the recorded environment.
Other environments can reproduce the workload but cannot promise identical compressed input hashes or timings.
Start from the exact candidate source snapshot and exact baseline commit.
Check source hashes against the provenance record before interpreting a rerun as the same comparison.
Use new output directories to retain earlier evidence.

The commands below create fixtures and the stride control, then build the three variants serially.
Ensure the commands resolve to the pinned toolchain versions.
Disable telemetry for these checks with `export MODULAR_TELEMETRY_ENABLED=false`.
Run from the candidate repository root.

```sh
SOURCE="$PWD"
BASE=51b4424ceef57fef1f8a5e787c583126f999baf5
WORK="$PWD/.cache/image-decode-505-repro"
MOJO=$(command -v mojo)
CC=$(command -v cc)
mkdir -p "$WORK"
git worktree add --detach "$WORK/baseline" "$BASE"
python3 bench/image_decode_fixture.py "$WORK/fixtures" --count 16 --alignment 4
python3 bench/image_decode_bench.py stride   --source "$SOURCE" --destination "$WORK/stride"
python3 bench/image_decode_bench.py build   --mojo "$MOJO" --cc "$CC" --flag=-O3   --source "baseline=$WORK/baseline" --source "dynamic=$SOURCE"   --source "stride=$WORK/stride" --revision "baseline=$BASE"   --destination "$WORK/build"
THREEMOJO_RUSAGE_HELPER="$WORK/build/image_decode_rusage"   python3 bench/test_image_decode_bench.py
python3 bench/image_decode_bench.py run   --build "$WORK/build/build.json" --fixtures "$WORK/fixtures"   --destination "$WORK/initial" --repetitions 3 --seed 505   --workers 1 2 4 17 --apis gltf registry
python3 bench/image_decode_bench.py run   --build "$WORK/build/build.json" --fixtures "$WORK/fixtures"   --destination "$WORK/confirmation" --repetitions 9 --seed 1505   --workers 1 2 4 17 --apis gltf registry
```

Run the recorded full matrix without simultaneous native benchmarks or compilers.
Retain `raw.jsonl`, `validated.jsonl`, `metadata.json`, and `summary.json` from each run.
The build record retains exact compilation commands and source/binary hashes.
Keep run order, worker counts, and both uniform controls unchanged when comparing scheduling choices.

Use the following command to verify the checked-in data without rerunning native code.

```sh
python3 docs/validation/image-decode-505-recompute.py
```

The script reports 1,152 trials and 64 summaries after successful verification.
Use `--write` only to regenerate the JSON and CSV from the retained normalized trials.
This operation verifies data consistency; it does not rerun loaders or establish a new performance result.

The following example rebuilds and runs the focused native suites with the unchanged five-second per-test gate.
It does not replace the remaining full-consumer and coverage checks.

```sh
for SUITE in test_image_batch test_image_queue test_gltf_loader_additions test_carla_assets; do
  "$MOJO" build --Werror -I "$SOURCE" "tests/$SUITE.mojo" -o "$WORK/$SUITE"
  python3 tools/run_suite.py --seconds 5 --suite "tests/$SUITE.mojo" -- "$WORK/$SUITE"
done
```
