# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Bounded result storage shared by image preloaders.

A batch owns at most the requested number of decode slots. Callers keep
its storage and their inputs alive until their task group has joined.
They then check every error before moving results into their destination.
No list can grow or move while a task holds a pointer into it.
"""

from render.texture import Texture


def decode_batch_size(remaining: Int, workers: Int) -> Int:
    """Return the number of pending images one decode batch can own.

    Args:
        remaining: The number of images still to decode.
        workers: The requested limit; one or less uses one image.

    Returns:
        No more than `max(0, remaining)` and `max(1, workers)` images.

    Raises:
        None.
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

        Returns:
            None.

        Raises:
            None.
        """
        var count = decode_batch_size(remaining, workers)
        self.textures = List[Texture](capacity=count)
        self.errors = List[String](length=count, fill=String(""))
        for _ in range(count):
            self.textures.append(Texture())

    def check(self) raises:
        """Refuse the first failed slot after all tasks have joined.

        Args:
            self: The completed batch, in source order.

        Returns:
            None.

        Raises:
            Error: If any task stored an error.
        """
        for error in self.errors:
            if error.byte_length() > 0:
                raise Error(error)
