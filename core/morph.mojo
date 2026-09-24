# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How much of each morph target a mesh wears: three.js's
`morphTargetInfluences`.

A mesh holds one weight per target of its geometry. three.js holds them in
an array as long as the geometry has targets, and on WebGL2 it passes the
targets in a texture, so the count has no fixed cap. This port had a cap
of eight: a mesh held its weights in a fixed row. The row is now a list,
so a mesh can wear as many targets as its geometry carries.

A weight past the end of the list reads as zero. That is what an unset
weight means, and it lets a mesh built before its geometry was filled in
wear the targets added later at zero. `set` grows the list, so a weight
can be given for any target from zero upward.

`MorphInfluences` is implicitly copyable, as the row was, so that a `Mesh`
stays implicitly copyable: a scene adds one by value.
"""

from std.math import isfinite


struct MorphInfluences(ImplicitlyCopyable, Sized):
    """One weight per morph target, zero past the last one set."""

    var weights: List[Float32]

    def __init__(out self):
        """Start with no weights: every target is worn at zero."""
        self.weights = List[Float32]()

    def __init__(out self, *, count: Int) raises:
        """Start with `count` weights, all zero: three.js's
        `updateMorphTargets`, which fills the array with zeros.

        Args:
            count: How many targets the geometry carries.

        Raises:
            Error: If the count is negative.
        """
        if count < 0:
            raise Error("A mesh cannot wear a negative number of targets")
        self.weights = List[Float32](length=count, fill=0)

    def __init__(out self, *, copy: Self):
        """Copy the weights.

        Args:
            copy: The weights to copy.
        """
        self.weights = copy.weights.copy()

    def __len__(self) -> Int:
        """Return how many weights are held.

        Returns:
            The length of the list. Targets past it are worn at zero.
        """
        return len(self.weights)

    def __getitem__(self, target: Int) -> Float32:
        """Return the weight of one target, zero when none is held.

        Args:
            target: Which target, from zero.

        Returns:
            Its weight, or zero for a target past the end of the list or
            below zero. `get` is the checked read.
        """
        if target < 0 or target >= len(self.weights):
            return 0
        return self.weights[target]

    def get(self, target: Int) raises -> Float32:
        """Return the weight of one target.

        Args:
            target: Which target, from zero.

        Returns:
            Its weight, zero past the end of the list.

        Raises:
            Error: If the target is negative.
        """
        if target < 0:
            raise Error("A morph target index cannot be negative")
        return self[target]

    def set(mut self, target: Int, weight: Float32) raises:
        """Set the weight of one target, growing the list with zeros to
        reach it.

        Args:
            target: Which target, from zero.
            weight: How much of it. Values outside zero to one are allowed,
                as three.js allows them.

        Raises:
            Error: If the target is negative or the weight is not a number.
        """
        if target < 0:
            raise Error("A morph target index cannot be negative")
        if not isfinite(weight):
            raise Error("A morph influence must be a number")
        while len(self.weights) <= target:
            self.weights.append(0)
        self.weights[target] = weight

    def is_worn(self) -> Bool:
        """Return True if any weight is not zero.

        Returns:
            Whether any target moves a vertex.
        """
        for weight in self.weights:
            if weight != 0:
                return True
        return False
