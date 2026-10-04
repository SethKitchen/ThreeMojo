<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Tick force restoration

Keep the current all-body force snapshot in `CarlaPhysics.tick`.
The dynamic-only candidate does not meet the adoption rule below.
This completes the measurement decision for [#287](https://github.com/SethKitchen/ThreeMojo/issues/287).
It does not change the public force lifetime or the production solver.

## Decision

Before measurement, the adoption rule required a repeatable 5% complete-tick CPU gain.
The target was 1,000 bodies, 10% dynamic bodies, and both five and ten substeps.
An all-dynamic regression above 5% would also reject the candidate.

The packed candidate reduces median CPU time by 4.9% with five substeps.
With ten substeps, the reduction is 2.0%.
The corresponding median paired ratios are 0.942 and 1.001.
A ratio below one favors the candidate.
Individual paired samples cross one in both cases.
The branch-filtered candidate also fails the gain rule.

Some larger sparse worlds benefit from packed snapshots.
For 10,000 bodies with 10% dynamic, median CPU reductions reach 8.2%.
These conditional gains do not establish a general replacement.
Packed snapshots also request more bytes when every body is dynamic.
Retain the simpler production code without a new mode switch or index cache.

## What the benchmark measures

`bench/carla_force_restore_bench.mojo` compares three complete tick paths:

- `all` calls the unchanged production `CarlaPhysics.tick`.
- `indexed` stores each dynamic body's index, force and torque in one packed list.
- `branch` snapshots all forces and torques, then restores only dynamic bodies.

Each tick applies the same external force and torque to every body.
Each path updates vehicles and walkers, steps the physics world, and collects events.
These fixtures contain separated spheres, with no vehicle or walker controllers.
They isolate mixed-body tick costs without contact impulses or suspension queries.
The native timing includes input application and the complete tick.
It excludes world creation, three warm-up ticks, parity checks and output.

The worlds have 100, 1,000 or 10,000 bodies.
The dynamic shares are 0%, 10% and 100%.
The substep counts are one, five and ten.
Body kinds are interleaved by a fixed permutation, with four-meter shape spacing.

Each measured tick lasts 0.01 seconds of simulation time.
Each sample runs `100000 / bodies` ticks.
Nine samples rotate the three strategy orders.

Measurements ran on October 3, 2026, in a Linux x86-64 container.
The host reports an AMD EPYC 9V74 processor, with nine available logical CPUs.
Mojo is pinned to `1.1.0 (8189361e)`; builds use `--Werror`.
All Mojo processes set `MODULAR_TELEMETRY_ENABLED=false`.

No other project compiler or benchmark ran during the timing window.
The shared host still introduces visible sample variation.
CPU time uses Linux process `clock()`, with one-microsecond resolution.
Wall time is also retained in the raw results.

The exact source base is `f72d5e7a5c363981d0a254e471fb042045832fd0`.
Its tree is `06217239bc6b961c6b214f0543958da63fb2f03c`.
The [raw results](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/benchmarks/force-restoration-linux.json) contain source hashes, all 729 timing samples and all 81 allocation captures.

## CPU results

Values are median process CPU microseconds per complete tick.
These medians describe this host and workload; they are not timing guarantees.

| Bodies | Dynamic % | Substeps | All | Indexed | Branch |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 0 | 1 | 11.14 | 9.79 | 11.12 |
| 100 | 0 | 5 | 52.73 | 50.43 | 50.03 |
| 100 | 0 | 10 | 102.05 | 98.01 | 98.15 |
| 100 | 10 | 1 | 13.64 | 13.52 | 12.76 |
| 100 | 10 | 5 | 66.36 | 59.88 | 64.73 |
| 100 | 10 | 10 | 131.94 | 121.87 | 123.91 |
| 100 | 100 | 1 | 38.44 | 36.72 | 33.96 |
| 100 | 100 | 5 | 174.74 | 171.19 | 169.10 |
| 100 | 100 | 10 | 347.02 | 348.45 | 347.91 |
| 1000 | 0 | 1 | 103.28 | 103.78 | 101.21 |
| 1000 | 0 | 5 | 525.24 | 484.32 | 486.89 |
| 1000 | 0 | 10 | 1004.54 | 918.91 | 996.63 |
| 1000 | 10 | 1 | 128.58 | 130.58 | 124.73 |
| 1000 | 10 | 5 | 648.14 | 616.13 | 625.18 |
| 1000 | 10 | 10 | 1236.43 | 1211.41 | 1220.47 |
| 1000 | 100 | 1 | 357.96 | 338.67 | 347.64 |
| 1000 | 100 | 5 | 1661.45 | 1669.01 | 1712.45 |
| 1000 | 100 | 10 | 3384.17 | 3411.41 | 3284.49 |
| 10000 | 0 | 1 | 1288.50 | 1160.80 | 1200.00 |
| 10000 | 0 | 5 | 6257.90 | 5504.80 | 5562.30 |
| 10000 | 0 | 10 | 11748.10 | 10741.90 | 11930.20 |
| 10000 | 10 | 1 | 1503.70 | 1430.20 | 1442.50 |
| 10000 | 10 | 5 | 7146.20 | 6641.20 | 6953.10 |
| 10000 | 10 | 10 | 14229.30 | 13055.60 | 13643.00 |
| 10000 | 100 | 1 | 3602.80 | 3631.40 | 3639.90 |
| 10000 | 100 | 5 | 18036.40 | 17538.10 | 18146.40 |
| 10000 | 100 | 10 | 34551.80 | 35114.70 | 35633.30 |

## Allocation results

Allocation captures run separately from native timings.
They use the existing `bench/navigation_allocations.c` runtime hook on Linux.
The hook checks itself before each capture and rejects tracking overflow.
It measures one warmed tick, including force input application.

It counts Mojo runtime requests on the calling thread.
It excludes world construction, allocator metadata, RSS and other threads.
No timing claim uses hook-instrumented runs.

The table gives requested bytes and allocation calls for 1,000 bodies.
`branch` has the same allocation results as `all` in every measured case.
The raw results also contain both other world sizes.

| Dynamic % | Substeps | All total bytes | Indexed total bytes | All peak bytes | Indexed peak bytes | All calls | Indexed calls |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 1 | 548408 | 499280 | 360456 | 335880 | 1055 | 1033 |
| 0 | 5 | 2545528 | 2496400 | 368648 | 344072 | 5187 | 5165 |
| 0 | 10 | 5041928 | 4992800 | 368648 | 344072 | 10352 | 10330 |
| 10 | 1 | 548408 | 507440 | 360456 | 339976 | 1055 | 1041 |
| 10 | 5 | 2545528 | 2504560 | 368648 | 348168 | 5187 | 5173 |
| 10 | 10 | 5041928 | 5000960 | 368648 | 348168 | 10352 | 10338 |
| 100 | 1 | 548408 | 564784 | 360456 | 368648 | 1055 | 1044 |
| 100 | 5 | 2545528 | 2561904 | 368648 | 376840 | 5187 | 5176 |
| 100 | 10 | 5041928 | 5058304 | 368648 | 376840 | 10352 | 10341 |

At 10% dynamic, packed snapshots save 40,968 requested bytes per 1,000-body tick.
They save 14 allocation calls and 20,480 peak requested bytes.
At 100% dynamic, they add 16,376 requested bytes and 8,192 peak bytes.
The packed record needs an index in addition to both vectors.
Fewer list allocations alone do not prove a complete-tick CPU improvement.

## Correctness controls

The benchmark compares both candidates with production before each measurement.
It checks exact positions, rotations, velocities, force and torque accumulators.
It also checks event counts and contact counts in the separated-body fixtures.
Controls include static, kinematic, dynamic and ghost bodies.
They change body kinds between ticks and leave alternate ticks unforced.

Every measured strategy produces the same final velocity checksum.
These controls do not qualify a production optimization for arbitrary controller errors.
The decision keeps production unchanged, including its failure behavior.

`tests/test_carla_physics_regressions.mojo` retains the original contact regressions.
It retains the one- and five-substep analytic impulse checks and adds ten substeps.
For a two-kilogram, one-meter sphere, a 20-newton force acts for 0.05 seconds.
The linear velocity change is 0.5 meters per second.
An eight-newton-meter torque changes angular velocity by 0.5 radians per second.
The following unforced tick must retain both velocities.

Additional cases check consumption for all body kinds and ghosts.
Ignored static and kinematic forces must not revive after a later dynamic transition.
Mode changes before the tick must retain pending forces until that tick consumes them.
Entering static still stops velocity, as the existing body API specifies.
The five-second suite gate, tolerances and coverage rules remain unchanged.

## Reproduce

Build the benchmark with the pinned toolchain from the repository root:

```sh
export MODULAR_TELEMETRY_ENABLED=false
.venv/bin/mojo build --Werror -I . bench/carla_force_restore_bench.mojo -o /tmp/force-bench
```

Run nine repetitions for each body count, dynamic share and substep count above.
Use `100000 / bodies` as the tick count.
Rotate `all indexed branch`, `indexed branch all`, and `branch all indexed`.
For example, the first 1,000-body, 10%-dynamic, five-substep sample is:

```sh
/tmp/force-bench 1000 10 5 100 all
/tmp/force-bench 1000 10 5 100 indexed
/tmp/force-bench 1000 10 5 100 branch
```

Keep compiler jobs and other local benchmarks idle during timing.
For allocation captures, build and preload the existing hook:

```sh
cc -shared -fPIC -O2 -Wall -Wextra -Werror bench/navigation_allocations.c -o /tmp/force-alloc.so -ldl
LD_PRELOAD=/tmp/force-alloc.so /tmp/force-bench 1000 10 5 1 indexed /tmp/force-alloc.so
```

Repeat that allocation command for all 81 cases and strategies.
The final fields give peak bytes, total bytes and allocation calls for one tick.
Do not use the printed time from a preloaded process for native comparisons.
