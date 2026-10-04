# Image decode queue

CARLA preload and parallel glTF loading use a shared queue.
A free worker takes the next image without waiting for slower images.
The queue limits active image reads and decodes to the requested worker count.
It preserves the order of completed textures and errors.

## Worker and memory limits

`loaders.image_batch.decode_textures` runs at most
`min(max(workers, 1), image_count)` image jobs at once.
One worker uses the calling thread.
A parallel call creates one persistent task per effective worker.
An empty input creates no tasks.

Each worker reads compressed bytes only after it claims an image.
Its read buffers and decoder scratch are released before its next claim.
The limit counts images, not bytes.
One large image can still need substantial memory.

The call retains completed textures until every job has finished.
It also holds one empty result slot and one error slot per image.
An empty result slot allocates no texture pixels, mip chain, or color ramp.
The final pixel and mip buffers move into their destination without another copy.
The image decoders can still make their own working copies.

Source storage is separate from these limits.
A glTF loader already holds its parsed JSON, data URI text, and binary buffers.
The queue does not preload every compressed image into another list.
Total memory includes those sources, all final textures, job metadata,
and the active workers' read buffers and decoder scratch.

## Ordering and failure

Jobs keep the loader's first-use order.
For glTF, this is material and core-map traversal order.
The key is the texture index and color space.
For CARLA, this is binding and file traversal order.
The key is the image path and color space.
A shared image used in two color spaces has two jobs.

Workers finish in any order.
Each worker owns the result and error slot for its claimed index.
After all workers join, the first failed job in source order is reported.
Even an error with an empty message remains a failure.

A failed CARLA preload adds no new cache entries.
Existing keys and texture buffers remain unchanged.
A retry uses fresh queue state and adds each missing key once.
The registry still records the requested worker count before decoding.

A failed glTF predecode adds no textures.
This guarantee applies to predecode, not the whole glTF load.
Later material, mesh, or node failures can still leave changes in the stores.
One-worker glTF loading keeps its existing lazy decoding behavior.
Extension-only maps remain lazy for every worker count.

The previous glTF implementation read all images in one batch before decoding.
A later read failure could therefore hide an earlier decode failure in that batch.
The queue reports the first failing job consistently.
It preserves each read error's text and the decoder's `glTF:` prefix.
CARLA preserves raw serial errors and path-prefixed parallel errors.

## Why a queue

Fixed-stride workers assign every Wth image to one worker.
If large images share that stride, one worker can receive most of the work.
A queue lets free workers take those images instead.
The queue adds one atomic index claim per job and one final claim per worker.
It does not add a task per image or a barrier between image groups.

## Verification

`tests/test_image_queue.mojo` exercises the production scheduler with
active-job and staged-byte counters, failures, retries, and buffer addresses.
These counters measure provider-owned allocations, not total process memory.
A bounded handshake proves that a later job can finish while the first job waits.
The loader suites compare pixels, mip chains, color spaces, source order,
and cache state across worker counts.


## Measurements

The [complete benchmark report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/image-decode-505.md)
compares batches, fixed-stride workers, and the queue.
It records both loading APIs, throughput, peak process RSS, and exact output checks.
The four-worker mixed-image cases improve in these measurements.
Their peak RSS increases because more large jobs can overlap.
High-worker and uniform cases include regressions and variation.
The report retains every case and the reproducible input and result records.
