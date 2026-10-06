# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Texture texels with shared reads and isolated writes.

A texture's byte or float list includes its mip levels. A shared buffer
keeps that complete list alive. A write first takes a private copy when
another buffer owns the same list. Sampling does not copy or change it.

`values` borrows the list for reading. `mutable_values` is the explicit
compatibility path for APIs that take a mutable List, including writable
pointers and spans. It detaches before returning the borrow. Do not cast
an immutable pointer to a mutable pointer to bypass this boundary.
"""

from std.memory import ArcPointer, Pointer


struct TextureBuffer[T: ImplicitlyCopyable & Deinitable & Equatable & Writable](
    Equatable, Movable, Sized, Writable
):
    """A list of texels that copies on write after explicit sharing.

    Parameters:
        T: A byte or floating-point channel type.
    """

    var _storage: ArcPointer[List[Self.T]]
    # A raw writable alias can have an erased lifetime. Once one is exposed,
    # later shares take a snapshot instead of trusting its borrow has ended.
    var _mutable_exposed: Bool

    @implicit
    def __init__(out self, var values: List[Self.T]):
        """Move a list into an independently owned buffer.

        Args:
            values: The texels and any mip levels. No elements are copied.
        """
        self._storage = ArcPointer(values^)
        self._mutable_exposed = False

    def __init__(out self, *, shared: Self):
        """Copy a buffer's values and share its unexposed allocation.

        A buffer that exposed a writable List gets an independent snapshot.
        This prevents retained writable aliases from changing the new buffer.

        Args:
            shared: The buffer whose texels must remain alive.
        """
        if shared._mutable_exposed:
            self._storage = ArcPointer(shared._storage[].copy())
        else:
            self._storage = shared._storage
        self._mutable_exposed = False

    def __len__(self) -> Int:
        """Return the number of channels, including mip levels.

        Returns:
            The list's length.
        """
        return len(self._storage[])

    def __eq__(self, other: Self) -> Bool:
        """Compare channel values, independent of ownership.

        Args:
            other: The buffer to compare.

        Returns:
            True if both lists have the same values.
        """
        return self._storage[] == other._storage[]

    def write_to(self, mut writer: Some[Writer]):
        """Write the channel list.

        Args:
            writer: The output writer.
        """
        writer.write(self._storage[])

    def __getitem__(self, at: Int) -> Self.T:
        """Read one channel without detaching the buffer.

        Args:
            at: The list index. It must be in range.

        Returns:
            The channel value.
        """
        return self._storage[][at]

    def __setitem__(mut self, at: Int, value: Self.T):
        """Write one channel without changing any shared buffer.

        Args:
            at: The list index. It must be in range.
            value: The new channel value.
        """
        self._detach()
        self._storage[][at] = value

    def unsafe_get(self, at: Int) -> Self.T:
        """Read one channel without a bounds check or a copy.

        Args:
            at: An index that the caller has checked.

        Returns:
            The channel value.
        """
        return self._storage[].unsafe_get(at)

    def values(self) -> ref[self] List[Self.T]:
        """Borrow the channel list for reading without a copy.

        Returns:
            An immutable list borrow tied to this buffer's lifetime.
        """
        return self._storage.ptr().unsafe_origin_cast[origin_of(self)]()[]

    def _detach(mut self):
        """Take private ownership before an ordinary indexed/list write."""
        if self._storage.count() != 1:
            self._storage = ArcPointer(self._storage[].copy())

    def mutable_values(mut self) -> ref[self] List[Self.T]:
        """Borrow a private list for writes, copying only when shared.

        Later shares of this buffer make independent snapshots because
        a writable pointer can have an erased lifetime. Indexed writes,
        `append` and `resize` do not expose a raw alias and keep sharing.

        Returns:
            A mutable list borrow tied to this buffer's lifetime.
        """
        self._detach()
        self._mutable_exposed = True
        # The count check excludes other buffer owners. Tie this mutable
        # borrow to self so safe aliases cannot outlive this owner.
        return (
            self._storage.ptr()
            .unsafe_mut_cast[True]()
            .unsafe_origin_cast[origin_of(self)]()[]
        )

    def unsafe_ptr(self) -> Pointer[Self.T, origin_of(self)]:
        """Borrow an immutable pointer to the channels without a copy.

        For a writable pointer, call `mutable_values().unsafe_ptr()`.
        A writable pointer must not outlive its mutable list borrow.

        Returns:
            A read-only pointer tied to this buffer's lifetime.
        """
        return self.values().unsafe_ptr()

    def copy(self) -> List[Self.T]:
        """Return an independent List of the channels and mip levels.

        Returns:
            A deep copy, compatible with APIs that take an owned List.
        """
        return self._storage[].copy()

    def shares_with(self, other: Self) -> Bool:
        """Return whether two buffers retain the same allocation.

        Args:
            other: The other buffer.

        Returns:
            True if neither has detached since they shared the allocation.
        """
        return self._storage.ptr() == other._storage.ptr()

    def append(mut self, value: Self.T):
        """Append one channel to this buffer only.

        Args:
            value: The channel to append.
        """
        self._detach()
        self._storage[].append(value)

    def resize(mut self, length: Int, fill: Self.T):
        """Resize this buffer without changing its shared copies.

        Args:
            length: The new nonnegative channel count.
            fill: The value of each new channel when the list grows.
        """
        self._detach()
        self._storage[].resize(length, fill)
