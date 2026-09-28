# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.gpgpu_sort`, on the host.

The index pairs are three.js's `getBitonicFlipIndices` and
`getBitonicDisperseIndices` worked out by hand, the step count is its
`_getStepCount`, and a counting sort must give what its `computeCPU` gives.
`tests/test_gpu.mojo` holds the device to the host.
"""

from materials.compute_ids import StorageBufferId
from materials.compute_nodes import (
    ComputeKernel,
    HostCompute,
    StorageBufferNode,
    StorageBufferStore,
    run_compute,
)
from materials.nodes import NODE_FLOAT, NODE_VEC2, NodeRef
from render.gpgpu_sort import (
    BitonicSort,
    CountingSort,
    bitonic_disperse_indices,
    bitonic_flip_indices,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

# Sixteen floats out of order, with a repeat and a negative.
comptime UNSORTED: List[Float32] = [
    5,
    -2,
    9,
    3,
    3,
    12,
    0.5,
    7,
    1,
    8,
    15,
    -7,
    4,
    11,
    6,
    2,
]


def _pairs(flip: Bool, height: Float32) raises -> List[Float32]:
    """Return the index pairs of invocations zero to three."""
    var store = StorageBufferStore()
    var out = store.instanced_array(4, NODE_VEC2)
    var kernel = ComputeKernel()
    var index = kernel.instance_index()
    var span = kernel.graph.float(height)
    var pair = bitonic_flip_indices(
        kernel.graph, index, span
    ) if flip else bitonic_disperse_indices(kernel.graph, index, span)
    kernel.assign(out, index, pair)
    run_compute(store, kernel.compute(4))
    return store.array(out)


def test_the_index_pairs_are_three_js_pairs() raises:
    # Flip: offset = floor( 2i / h ) * h, and ( i % (h/2) + offset,
    # h - i % (h/2) - 1 + offset ). Disperse: ( i % (h/2) + offset,
    # i % (h/2) + h/2 + offset ).
    var flips = _pairs(True, 4)
    var want_flips: List[Float32] = [0, 3, 1, 2, 4, 7, 5, 6]
    var disperses = _pairs(False, 4)
    var want_disperses: List[Float32] = [0, 2, 1, 3, 4, 6, 5, 7]
    for at in range(8):
        assert_equal(flips[at], want_flips[at])
        assert_equal(disperses[at], want_disperses[at])


def _sorted(values: List[Float32]) -> List[Float32]:
    """Return a copy of the values, smallest first."""
    var out = values.copy()
    for i in range(len(out)):
        for j in range(len(out) - 1 - i):
            if out[j] > out[j + 1]:
                var held = out[j]
                out[j] = out[j + 1]
                out[j + 1] = held
    return out^


def test_a_bitonic_sort_sorts_across_workgroups() raises:
    # Sixteen elements in workgroups of two: a local swap, two global
    # flips with their disperses, and an align at the end, as three.js's
    # `_getStepCount` counts six steps.
    var store = StorageBufferStore()
    var data = store.instanced_array(materialize[UNSORTED](), NODE_FLOAT)
    var sort = BitonicSort(store, data, 2)
    assert_equal(sort.workgroup_size, 2)
    assert_equal(sort.step_count, 6)
    assert_equal(sort.swap_op_count, 10)
    var runner = HostCompute()
    sort.compute(runner, store)
    var got = store.array(data)
    var want = _sorted(materialize[UNSORTED]())
    for at in range(16):
        assert_equal(got[at], want[at])
    assert_true(sort.reads_data)
    assert_equal(sort.current_dispatch, 0)
    # The info buffer is reset for the next sort.
    var info = store.array(sort.info)
    assert_equal(info[0], 1)
    assert_equal(info[1], 2)
    assert_equal(info[2], 2)
    # A second sort of sorted data leaves it sorted.
    sort.compute(runner, store)
    got = store.array(data)
    for at in range(16):
        assert_equal(got[at], want[at])


def test_a_bitonic_sort_in_one_workgroup_takes_one_step() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array([4, 3, 2, 1, 8, 7, 6, 5], NODE_FLOAT)
    var sort = BitonicSort(store, data)
    assert_equal(sort.workgroup_size, 4)
    assert_equal(sort.step_count, 1)
    var runner = HostCompute()
    sort.compute(runner, store)
    var got = store.array(data)
    for at in range(8):
        assert_equal(got[at], Float32(at + 1))


def test_a_bitonic_sort_refuses_what_it_cannot_sort() raises:
    var store = StorageBufferStore()
    var pairs = store.instanced_array(4, NODE_VEC2)
    var odd = store.instanced_array(6, NODE_FLOAT)
    var one = store.instanced_array(1, NODE_FLOAT)
    var four = store.instanced_array(4, NODE_FLOAT)
    with assert_raises(contains="buffer of floats"):
        _ = BitonicSort(store, pairs)
    with assert_raises(contains="power of two of elements"):
        _ = BitonicSort(store, odd)
    with assert_raises(contains="power of two of elements"):
        _ = BitonicSort(store, one)
    with assert_raises(contains="workgroup is a power of two"):
        _ = BitonicSort(store, four, 3)
    with assert_raises(contains="workgroup is a power of two"):
        _ = BitonicSort(store, four, 0)


# The keys a counting sort bins, at buffer zero of the store.
comptime KEYS: List[Float32] = [3, 1, 0, 3, 2, 1, 3, 0, 2, 1]


def _key_bin(mut kernel: ComputeKernel) raises -> NodeRef:
    """Return the key of the invocation's place as its bin."""
    var keys = StorageBufferNode(StorageBufferId(0), NODE_FLOAT, 10)
    return kernel.element(keys, kernel.instance_index())


def _bins() -> List[Int]:
    """Return the keys as bins."""
    var out = List[Int]()
    for at in range(10):
        out.append(Int(materialize[KEYS]()[at]))
    return out^


def test_a_counting_sort_orders_places_as_compute_cpu_does() raises:
    var store = StorageBufferStore()
    _ = store.instanced_array(materialize[KEYS](), NODE_FLOAT)
    var sort = CountingSort(store, 10, 4, 4)
    var initial = store.array(sort.order)
    for at in range(10):
        assert_equal(initial[at], Float32(at))
    sort.set_bin_node(_key_bin)
    assert_equal(len(sort.nodes), 4)
    assert_equal(sort.nodes[2].name, "CountingSortPrefix")
    var runner = HostCompute()
    sort.compute(runner, store)
    var got = store.array(sort.order)
    var counts = store.array(sort.histogram)
    var want_counts: List[Float32] = [2, 3, 2, 3]
    for at in range(4):
        assert_equal(counts[at], want_counts[at])
    # Each bin's cursor ends at the next bin's first place.
    var cursors = store.array(sort.offsets)
    var want_cursors: List[Float32] = [2, 5, 7, 10]
    for at in range(4):
        assert_equal(cursors[at], want_cursors[at])
    sort.compute_cpu(store, _bins())
    var cpu = store.array(sort.order)
    var want: List[Float32] = [2, 7, 1, 5, 9, 4, 8, 0, 3, 6]
    for at in range(10):
        assert_equal(got[at], want[at])
        assert_equal(cpu[at], want[at])


def test_a_counting_sort_refuses_what_it_cannot_sort() raises:
    var store = StorageBufferStore()
    with assert_raises(contains="places, bins and a workgroup"):
        _ = CountingSort(store, 0)
    with assert_raises(contains="places, bins and a workgroup"):
        _ = CountingSort(store, 4, 0)
    with assert_raises(contains="places, bins and a workgroup"):
        _ = CountingSort(store, 4, 4, 0)
    var sort = CountingSort(store, 3, 2, 2)
    var runner = HostCompute()
    with assert_raises(contains="needs a bin node"):
        sort.compute(runner, store)
    with assert_raises(contains="one bin a place"):
        sort.compute_cpu(store, [0, 1])
    with assert_raises(contains="out of range"):
        sort.compute_cpu(store, [0, 2, 1])
    with assert_raises(contains="out of range"):
        sort.compute_cpu(store, [0, -1, 1])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
