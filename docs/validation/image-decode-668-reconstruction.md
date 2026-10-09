# Decode failure early stop

## Scope

The shared image queue stops new decode claims after a worker fails.
This change addresses issue #668 on the draft integration branch.
Full aggregate checks and complete coverage remain final batch gates.
No throughput speedup, GPU result or full-platform pass is claimed.

## Queue contract

The cursor is UInt64. A claim uses one atomic fetch-add operation.
A failure uses atomic max to advance that cursor to the input count.

The worker applies the stop before it converts and stores the error text.
Every later claim is terminal. A concurrent terminal claim is never rewound.
The worker checks the unsigned terminal range before conversion to Int.

Jobs claimed before the stop still finish. Their source and slot owners stay
alive until all workers join. Claimed jobs form a prefix, so every earlier
source index is included.

The first source-order error is returned after
the join, even when a later error finishes first. Empty errors remain errors.
No partially filled result list is returned. A retry uses a new cursor.

Each worker makes at most one terminal claim. The input count and effective
worker count are each at most Int.MAX. Their sum fits in UInt64, including
the terminal claims. A direct boundary test covers the signed-limit case
without allocating an Int.MAX-sized batch.

The serial path, successful texture order and moved pixel buffers are
unchanged. Image count remains a concurrency bound, not a byte-memory cap.

## Focused checks

The fresh checks use Mojo 1.1.0, warnings-as-errors, one compiler thread and
the portable x86-64-v3 Linux target. The original five-second test limits
are unchanged. The runtime reports nine threads for the new race controls.

- Seven new tests cover monotonic stop, stale observations and signed-limit
  claims. They also cover worker races, joined successes and failures,
  bounded work and retries
- Four existing queue tests retain progress, move ownership, source-order
  error selection and worker bounds. Their failure expectation now checks
  a completed prefix rather than requiring every unclaimed job to run
- Four original batch-storage tests pass
- Eighteen original glTF loader-addition tests pass, including exact error
  selection and refusal to publish partial textures
- Thirty-three original CARLA asset tests pass, including cache atomicity,
  existing entries, retry behavior, color spaces and complete mip chains

When every callback fails, the public API test observes at most the effective
worker count in decode attempts. It checks worker settings -1, 0, 1, 2 and 8,
input counts 1, 17 and 64, an exact visited prefix and exact retry counts.
A separate single-failure test does not impose that bound: other workers
can finish further jobs before the failing worker publishes its stop.

The first new-test build exposed an invalid mutable-to-immutable pointer
origin cast. A readonly source helper corrected that test harness. Production
code was unchanged by this repair. The failed attempt is retained separately.

Only the new stop test needed canonical whitespace formatting. It is rerun
on the final formatted source. Production and all original consumer test
bytes remain identical to their successful focused captures.

## Qualification on main

The change merged with #594 at `7c4f5c0e`. The full main run 37773325369
on that commit passed lint, the three Linux CPU shards and both macOS
suites. All eight coverage captures completed.

`loaders/image_batch` reached 100% lines, branches and MC/DC in that run's
aggregate report. The aggregate coverage job failed only in CARLA and hair
modules that this change does not touch.

The bounded-work test is the failed-batch work measurement. When every
callback fails, it observes at most the effective worker count in decode
attempts, for each tested worker setting and input count.

## Earlier gates

The draft batch must still pass complete checks, coverage and platform CI.
The separate texture-ownership change needs its pointer adapters composed
and its queue controls checked on the combined source. Earlier lost-source
measurements and native results are not evidence for this reconstruction.
