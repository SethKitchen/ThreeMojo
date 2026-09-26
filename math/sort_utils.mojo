# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A radix sort of 32-bit keys, from three.js
`examples/jsm/utils/SortUtils.js`.

`radix_sort` sorts items by a 32-bit unsigned key each: eight bits at a
time from the top, as three.js's `radixSort` does. A run of 32 items or
fewer is finished by insertion. The sort is stable. three.js sorts
`BatchedMesh`'s instances by depth with it, a key of the depth's bits.

three.js's `radixSort` takes the items and a `get` that reads each one's
key. Here the items are indices and the keys a list, so `get` is
`keys[item]`. `radix_sort_keys` sorts the keys themselves.
"""

# three.js's constants: eight bits a pass, four passes of a 32-bit key.
comptime _POWER = 3
comptime _BIN_BITS = 1 << _POWER
comptime _BIN_SIZE = 1 << _BIN_BITS
comptime _BIN_MAX = _BIN_SIZE - 1
comptime _ITERATIONS = 32 // _BIN_BITS


struct _Sorter(Movable):
    """One sort's two buffers and its counts, three.js's `data` and
    `bins`."""

    var data: List[List[Int]]
    var keys: List[UInt32]
    var bins: List[List[Int]]
    var reversed: Bool

    def __init__(
        out self, var items: List[Int], var keys: List[UInt32], reversed: Bool
    ):
        var count = len(items)
        self.data = List[List[Int]]()
        self.data.append(items^)
        self.data.append(List[Int](length=count, fill=0))
        self.keys = keys^
        self.bins = List[List[Int]]()
        for _ in range(_ITERATIONS + 1):  # pragma: no branch
            self.bins.append(List[Int](length=_BIN_SIZE, fill=0))
        self.reversed = reversed

    def _key(self, item: Int) -> UInt32:
        """Return an item's key, three.js's `get( el ) >>> 0`."""
        return self.keys[item]

    def _before(self, a: UInt32, b: UInt32) -> Bool:
        """Return three.js's `compare`: whether `a` goes after `b`."""
        return a < b if self.reversed else a > b

    def insertion(mut self, depth: Int, start: Int, length: Int):
        """Sort a short run in place, three.js's `insertionSortBlock`."""
        var a = depth & 1
        var b = (depth + 1) & 1
        for j in range(start + 1, start + length):
            var p = self.data[a][j]
            var t = self._key(p)
            var i = j
            while i > start:
                if self._before(self._key(self.data[a][i - 1]), t):
                    self.data[a][i] = self.data[a][i - 1]
                    i -= 1
                else:
                    break
            self.data[a][i] = p
        if (depth & 1) == 1:
            for i in range(start, start + length):  # pragma: no branch
                self.data[b][i] = self.data[a][i]

    def radix(mut self, depth: Int, start: Int, length: Int):
        """Sort a run by one byte of its keys, and its bins by the next,
        three.js's `radixSortBlock`."""
        var a = depth & 1
        var b = (depth + 1) & 1
        var shift = UInt32((3 - depth) << _POWER)
        var end = start + length
        for j in range(_BIN_SIZE):  # pragma: no branch
            self.bins[depth + 1][j] = 0
        for j in range(start, end):
            var slot = Int((self._key(self.data[a][j]) >> shift) & _BIN_MAX)
            self.bins[depth + 1][slot] += 1
        if self.reversed:
            for j in range(_BIN_SIZE - 2, -1, -1):  # pragma: no branch
                self.bins[depth + 1][j] += self.bins[depth + 1][j + 1]
        else:
            for j in range(1, _BIN_SIZE):  # pragma: no branch
                self.bins[depth + 1][j] += self.bins[depth + 1][j - 1]
        for j in range(_BIN_SIZE):  # pragma: no branch
            self.bins[depth][j] = self.bins[depth + 1][j]
        for j in range(end - 1, start - 1, -1):
            var item = self.data[a][j]
            var slot = Int((self._key(item) >> shift) & _BIN_MAX)
            self.bins[depth + 1][slot] -= 1
            self.data[b][start + self.bins[depth + 1][slot]] = item
        if depth == _ITERATIONS - 1:
            return
        var previous = 0
        for step in range(_BIN_SIZE):  # pragma: no branch
            var j = _BIN_MAX - step if self.reversed else step
            var current = self.bins[depth][j]
            var run = current - previous
            if run != 0:
                if run > 32:
                    self.radix(depth + 1, start + previous, run)
                else:
                    self.insertion(depth + 1, start + previous, run)
                previous = current


def radix_sort(
    mut items: List[Int], keys: List[UInt32], reversed: Bool = False
) raises:
    """Sort items by their keys, three.js's `radixSort` with a `get`.

    Args:
        items: The items, as indices into `keys`. Sorted in place.
        keys: Each item's 32-bit key.
        reversed: True for the largest key first, three.js's `reversed`.

    Raises:
        Error: If an item names no key.
    """
    for at in range(len(items)):
        if items[at] < 0 or items[at] >= len(keys):
            raise Error("A radix sort's item must name a key")
    var sorter = _Sorter(items^, keys.copy(), reversed)
    sorter.radix(0, 0, len(sorter.data[0]))
    items = sorter.data[0].copy()


def radix_sort_keys(mut keys: List[UInt32], reversed: Bool = False) raises:
    """Sort 32-bit keys, three.js's `radixSort` with no `get`.

    Args:
        keys: The keys. Sorted in place.
        reversed: True for the largest first.

    Raises:
        Error: Never; each key names itself.
    """
    var items = List[Int]()
    for at in range(len(keys)):
        items.append(at)
    radix_sort(items, keys, reversed)
    var sorted = List[UInt32]()
    for at in range(len(items)):
        sorted.append(keys[items[at]])
    keys = sorted^
