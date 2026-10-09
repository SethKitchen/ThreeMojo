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


## Supplemental source-owner qualification: 2026-10-09

PR #693 records the completed #668 qualification on main above.
This supplement adds one source-owner destruction control and fresh focused
Linux evidence. It changes no production module, existing test, shared build
input, or coverage threshold. The completed README remains unchanged.

The new control owns a pixel buffer and uses the public `decode_textures`
call as the source's last use. Failure unwinds the caller. The destructor
records exactly one destruction, zero active callback bodies, and two finished
callback bodies. A concurrent callback reads the owned pixel before destruction.
Its failure announcement occurs before the second callback throws. It does
not independently observe the production stop or `TaskGroup.wait`.
The unchanged real-catch controls separately establish that stop ordering.

The fresh runs use the retained official Mojo 1.1.0 (`8189361e`) SDK.
Its complete 44-payload identity is unchanged before and after each phase.
Native builds use warnings-as-errors, one compiler thread, and the portable
x86-64-v3 Linux target. The stop suite reports four runtime threads.
The five-second per-test limit remains active. Each owned phase has a
600-second limit, and every owned descendant is reaped.

- Eight queue-stop tests pass, retaining all seven previous controls
- Four queue tests and four batch-storage tests pass
- Eighteen glTF loader-addition tests and 33 CARLA asset tests pass
- Ten more runs of the eight-test stop suite pass with four runtime threads
- Fresh queue, batch, and queue-stop captures pass through the maintained
  `aot-hits` tooling. `loaders/image_batch` reaches 44/44 lines and 22/22
  branches, for 66/66 required outcomes. There are no condition or MC/DC
  obligations in this module. The coverage thresholds are unchanged
- Thirty selector tests pass. The additive stop test selects one CPU suite
  and tooling. The documentation changes also select documentation checks.
  No production coverage or GPU job is selected by this supplemental change

The existing deterministic real-catch control has 12 inputs and exactly two
completed callbacks. The other ten callbacks are never called. This is
evidence of ten avoided callbacks on that input, without an elapsed-time
speedup claim. The public all-failure and exact-retry matrix is unchanged.

These native and capture runs start from PR #686 head
`699d00bcc9e9bb7144d0bb6b128419705f97389d`, tree
`6813d4a769fbd1b2acc0d0116961e989ea36f2f9`, plus the new test.
The composition base is main `01c7c8e85471b16d0f4dfd4f109bde5f3f99891d`,
tree `6c9808775c225638362ea82fe7d4a7c84e07ccdb`.
The base comparison changes only README and this report through #693.
All production sources, imports, original tests, and capture tools are
byte-identical across those bases. The #693 text is retained above.

The earlier run 37773325369 remains historical evidence for its original
revision. Its aggregate failed elsewhere at 247514/247749. Fresh focused
success does not establish a whole-repository or new full-platform pass.
The hosted checks for this supplemental commit remain the publication gate.
