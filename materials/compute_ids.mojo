# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids and kinds of a compute program, each a type rather than a bare
int: which storage buffer, which workgroup array, which of the invocation's
numbers, which statement, and which atomic operation.

`materials.nodes` builds its compute leaves from them and
`materials.compute_nodes` builds its programs from them. They live apart
so that neither module imports the other.
"""


@fieldwise_init
struct StorageBufferId(Equatable, ImplicitlyCopyable, Writable):
    """Which buffer in a `StorageBufferStore`, as a type rather than a bare
    int. See `core.object3d.NodeId` for why these are wrapped."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a buffer: it is not negative.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct WorkgroupArrayId(Equatable, ImplicitlyCopyable, Writable):
    """Which workgroup array of a `ComputeKernel`, three.js's
    `workgroupArray`, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name an array: it is not negative.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct ComputeStatementId(Equatable, ImplicitlyCopyable, Writable):
    """Which statement of a `ComputeKernel`, as a type rather than a bare
    int: a statement's result node reads what that statement left."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a statement: it is not negative.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct ComputeBuiltin(Equatable, ImplicitlyCopyable, Writable):
    """Which of an invocation's numbers a node reads, as a type rather than
    a bare int: three.js's `instanceIndex`, `invocationLocalIndex`,
    `workgroupId`, `numWorkgroups`, `subgroupSize`, `subgroupIndex` and
    `invocationSubgroupIndex`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven numbers.

        Returns:
            Whether the value is zero to six.
        """
        return self.value >= 0 and self.value <= 6


# The invocation's place among all of them, three.js's `instanceIndex` and
# `globalId.x`.
comptime INSTANCE_INDEX = ComputeBuiltin(0)
# Its place in its workgroup, `invocationLocalIndex` and `localId.x`.
comptime INVOCATION_LOCAL_INDEX = ComputeBuiltin(1)
# Its workgroup's place, `workgroupId.x`, and how many workgroups the
# dispatch has, `numWorkgroups.x`.
comptime WORKGROUP_ID = ComputeBuiltin(2)
comptime NUM_WORKGROUPS = ComputeBuiltin(3)
# How many invocations a subgroup has, its place in the workgroup, and the
# invocation's place in its subgroup: `subgroupSize`, `subgroupIndex` and
# `invocationSubgroupIndex`.
comptime SUBGROUP_SIZE = ComputeBuiltin(4)
comptime SUBGROUP_INDEX = ComputeBuiltin(5)
comptime INVOCATION_SUBGROUP_INDEX = ComputeBuiltin(6)


@fieldwise_init
struct AtomicOp(Equatable, ImplicitlyCopyable, Writable):
    """Which atomic function a statement runs, three.js's
    `AtomicFunctionNode` methods, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the nine functions.

        Returns:
            Whether the value is zero to eight.
        """
        return self.value >= 0 and self.value <= 8


comptime ATOMIC_LOAD = AtomicOp(0)
comptime ATOMIC_STORE = AtomicOp(1)
comptime ATOMIC_ADD = AtomicOp(2)
comptime ATOMIC_SUB = AtomicOp(3)
comptime ATOMIC_MAX = AtomicOp(4)
comptime ATOMIC_MIN = AtomicOp(5)
comptime ATOMIC_AND = AtomicOp(6)
comptime ATOMIC_OR = AtomicOp(7)
comptime ATOMIC_XOR = AtomicOp(8)
