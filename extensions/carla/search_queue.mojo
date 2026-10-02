# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared private min-heap for CARLA's graph searches.

The caller supplies a search score and a deterministic tie key. A smaller
key wins equal scores. Repeated keys are allowed: each search owns its
stale-entry and reopen rules. The queue stores ordering keys. The caller owns the graph state.
"""

from std.math import isnan


struct _MinCostQueue(Movable, Sized):
    """A binary heap of (score, tie key) pairs."""

    var entries: List[Tuple[Float64, Int]]

    def __init__(out self):
        self.entries = List[Tuple[Float64, Int]]()

    def __len__(self) -> Int:
        return len(self.entries)

    @staticmethod
    def _before(a: Tuple[Float64, Int], b: Tuple[Float64, Int]) -> Bool:
        return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

    def push(mut self, score: Float64, key: Int) raises:
        if isnan(score):
            raise Error("A navigation search score must not be NaN")
        self.entries.append((score, key))
        var child = len(self.entries) - 1
        while child > 0:
            var parent = (child - 1) // 2
            if not Self._before(self.entries[child], self.entries[parent]):
                break
            self.entries.swap_elements(child, parent)
            child = parent

    def pop(mut self) -> Tuple[Float64, Int]:
        """Remove the least entry. The caller must check that one exists."""
        var top = self.entries[0]
        var last = self.entries.pop()
        if len(self.entries) == 0:
            return top
        self.entries[0] = last
        var parent = 0
        while True:
            var best = parent
            var left = 2 * parent + 1
            var right = left + 1
            if left < len(self.entries) and Self._before(
                self.entries[left], self.entries[best]
            ):
                best = left
            if right < len(self.entries) and Self._before(
                self.entries[right], self.entries[best]
            ):
                best = right
            if best == parent:
                return top
            self.entries.swap_elements(parent, best)
            parent = best
