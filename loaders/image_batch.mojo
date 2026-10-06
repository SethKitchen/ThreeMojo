# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Bounded image scheduling and move-owned results shared by preloaders.

`decode_textures` uses persistent workers with one atomic job queue.
It retains final results in source order and bounds active staging by
worker count. The older batch helpers remain available for callers that
need one bounded group of slots. Neither path moves pointer-owned storage
before its tasks join.
"""

from render.texture import Texture
from render.tasks import TaskGroup
from std.atomic import Atomic


def decode_batch_size(remaining: Int, workers: Int) -> Int:
    """Return the number of pending images one decode batch can own.

    Args:
        remaining: The number of images still to decode.
        workers: The requested limit; one or less uses one image.

    Returns:
        No more than `max(0, remaining)` and `max(1, workers)` images.
    """
    return min(max(0, remaining), max(1, workers))


struct TextureDecodeBatch(Movable):
    """Own bounded texture results and errors until all tasks have joined."""

    var textures: List[Texture]
    var errors: List[String]

    def __init__(out self, remaining: Int, workers: Int):
        """Allocate initialized slots for one bounded batch.

        Args:
            remaining: The number of images still to decode.
            workers: The requested limit; one or less uses one image.
        """
        var count = decode_batch_size(remaining, workers)
        self.textures = List[Texture](capacity=count)
        self.errors = List[String](length=count, fill=String(""))
        for _ in range(count):
            self.textures.append(Texture())

    def check(self) raises:
        """Refuse the first failed slot after all tasks have joined.

        Check the completed batch in source order.

        Raises:
            Error: If any task stored an error.
        """
        for error in self.errors:
            if error.byte_length() > 0:
                raise Error(error)


trait TextureDecodeSource:
    """Provide indexed textures to a concurrent decode call.

    `decode` can run concurrently at distinct indices. Keep compressed
    staging and decoder scratch local to each call. Shared inputs must
    stay fixed; synchronize any other shared mutable state explicitly.
    """

    def decode(self, index: Int) raises -> Texture:
        """Return one complete texture, including its mip chain.

        Args:
            index: A source-order job in the caller's fixed input storage.

        Returns:
            An owned texture. The caller moves its buffers into the result.

        Raises:
            Error: If the input cannot be read, decoded, or mipmapped.
        """
        ...


def _claim_decode(next: MutPointer[Int64, MutAnyOrigin]) -> Int:
    """Claim a unique index from storage retained until all workers join."""
    return Int(Atomic[Int64].fetch_add(next, 1))


async def _decode_worker[
    Source: TextureDecodeSource
](
    source: Pointer[Source, ImmutAnyOrigin],
    next: MutPointer[Int64, MutAnyOrigin],
    count: Int,
    results: MutPointer[Optional[Texture], MutAnyOrigin],
    errors: MutPointer[Optional[String], MutAnyOrigin],
):
    """Read one image at a time and claim again without a batch barrier."""
    while True:
        var index = _claim_decode(next)
        if index >= count:
            return
        try:
            # The provider's compressed bytes and decoder scratch die
            # before this worker claims another image. Only its completed
            # texture moves into the distinct source-indexed result slot.
            results[unsafe_offset=index] = source[].decode(index)
        except e:
            errors[unsafe_offset=index] = String(e)


def decode_textures[
    Source: TextureDecodeSource
](source: Source, var count: Int, workers: Int) raises -> List[Texture]:
    """Decode indexed images with a bounded, work-conserving queue.

    One worker reads one image at a time. A free worker claims the next
    image without waiting for slower workers. Inputs must stay fixed for
    this call. Completed textures are retained in source order, without
    extra pixel or mip copies. All tasks join before an error is raised.

    The active image count is bounded, not each image's byte size. Storage
    also includes the source, one result/error slot per image, and all
    completed textures. Empty slots allocate no texture payload.

    Args:
        source: Immutable image inputs and the per-image decoder.
        count: Number of jobs. A nonpositive count produces no textures.
        workers: Active worker limit. One or less uses the calling thread.

    Returns:
        Owned textures in source order, with their pixel and mip buffers.

    Raises:
        Error: The first source-order failure, independent of completion
            order. No partial result is returned.
    """
    count = max(0, count)
    var textures = List[Texture](capacity=count)
    if workers <= 1:
        for index in range(count):
            textures.append(source.decode(index))
        return textures^
    var results = List[Optional[Texture]](capacity=count)
    var errors = List[Optional[String]](length=count, fill=None)
    for _ in range(count):
        results.append(None)
    var next: Int64 = 0
    var group = TaskGroup()
    for _ in range(decode_batch_size(count, workers)):
        group.create_task(
            _decode_worker(
                Pointer(to=source).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=next).unsafe_origin_cast[MutAnyOrigin](),
                count,
                results.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
            )
        )
    group.wait()
    # Retain erased-pointer owners through the join, including the error
    # path. No result list grows or moves while a task can access it.
    _ = next
    _ = Pointer(to=source)
    _ = len(results)
    for error in errors:
        if error:
            raise Error(error.value())
    for index in range(count):
        textures.append(results[index].take())
    return textures^
