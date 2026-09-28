# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.compute_nodes` and `materials.compute_ids`, on the
host.

three.js's compute nodes need WebGPU, which Node has not, so the expected
buffers are worked out by hand from the WGSL three.js writes: a particle
moved by its velocity, an invocation's numbers in workgroups of two, a
histogram by `atomicAdd`, a workgroup array read back to front after a
barrier, and a storage texture written texel by texel.
`tests/test_gpu.mojo` holds the device to the host.
"""

from materials.compute_ids import (
    ATOMIC_ADD,
    ATOMIC_AND,
    ATOMIC_LOAD,
    ATOMIC_MAX,
    ATOMIC_MIN,
    ATOMIC_OR,
    ATOMIC_STORE,
    ATOMIC_SUB,
    ATOMIC_XOR,
    INSTANCE_INDEX,
    INVOCATION_LOCAL_INDEX,
    INVOCATION_SUBGROUP_INDEX,
    NUM_WORKGROUPS,
    SUBGROUP_INDEX,
    SUBGROUP_SIZE,
    WORKGROUP_ID,
    AtomicOp,
    ComputeBuiltin,
    ComputeStatementId,
    StorageBufferId,
    WorkgroupArrayId,
)
from materials.compute_nodes import (
    ComputeKernel,
    ComputeNode,
    ComputeSource,
    HostCompute,
    HostMemory,
    MutUntracked,
    StorageBuffer,
    StorageBufferNode,
    StorageBufferStore,
    StorageTexture,
    WorkgroupArrayNode,
    atomic_result,
    pack_storage,
    run_compute,
)
from materials.nodes import (
    AT_FRAGMENT,
    COLOR_NODE,
    NODE_FLOAT,
    NODE_MAT3,
    NODE_VEC2,
    NODE_VEC3,
    NODE_VEC4,
    NodeGraph,
    NodeProgram,
    NodeRef,
    OPACITY_NODE,
    ProgramSource,
    ValueType,
)
from math.matrix3 import Matrix3
from postprocessing.sampling import Untracked
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _floats(store: StorageBufferStore, node: StorageBufferNode) raises -> List[Float32]:
    """Return a buffer's floats."""
    return store.array(node)


def _run(mut store: StorageBufferStore, node: ComputeNode) raises:
    """Run a node on the host through the runner."""
    var runner = HostCompute()
    runner.compute(store, node)


# --- ids ---------------------------------------------------------------------


def test_ids_are_valid_only_in_range() raises:
    assert_true(StorageBufferId(0).is_valid())
    assert_false(StorageBufferId(-1).is_valid())
    assert_true(WorkgroupArrayId(3).is_valid())
    assert_false(WorkgroupArrayId(-2).is_valid())
    assert_true(ComputeStatementId(0).is_valid())
    assert_false(ComputeStatementId(-1).is_valid())
    assert_true(INSTANCE_INDEX.is_valid())
    assert_true(INVOCATION_SUBGROUP_INDEX.is_valid())
    assert_false(ComputeBuiltin(-1).is_valid())
    assert_false(ComputeBuiltin(7).is_valid())
    assert_true(ATOMIC_LOAD.is_valid())
    assert_true(ATOMIC_XOR.is_valid())
    assert_false(AtomicOp(-1).is_valid())
    assert_false(AtomicOp(9).is_valid())


# --- buffers -----------------------------------------------------------------


def test_a_storage_buffer_holds_whole_elements() raises:
    var zeros = StorageBuffer(3, NODE_VEC3)
    assert_equal(zeros.count, 3)
    assert_equal(len(zeros.array), 9)
    var held = StorageBuffer([1, 2, 3, 4], NODE_VEC2)
    assert_equal(held.count, 2)
    with assert_raises(contains="one element or more"):
        _ = StorageBuffer(0, NODE_FLOAT)
    with assert_raises(contains="float or a vector"):
        _ = StorageBuffer(2, NODE_MAT3)
    with assert_raises(contains="whole number"):
        _ = StorageBuffer([1, 2, 3], NODE_VEC2)
    with assert_raises(contains="whole number"):
        _ = StorageBuffer(List[Float32](), NODE_FLOAT)


def test_a_store_names_its_buffers() raises:
    var store = StorageBufferStore()
    var a = store.instanced_array(4, NODE_FLOAT)
    var b = store.instanced_array([5, 6], NODE_FLOAT)
    assert_equal(store.count(), 2)
    assert_equal(a.buffer, StorageBufferId(0))
    assert_equal(b.count, 2)
    assert_equal(_floats(store, b)[1], 6)
    store.set_array(a, [1, 2, 3, 4])
    assert_equal(_floats(store, a)[3], 4)
    with assert_raises(contains="keeps its size"):
        store.set_array(a, [1])
    with assert_raises(contains="no buffer 7"):
        _ = store.array(StorageBufferNode(StorageBufferId(7), NODE_FLOAT, 1))
    with assert_raises(contains="no buffer -1"):
        _ = store.array(StorageBufferNode(StorageBufferId(-1), NODE_FLOAT, 1))
    with assert_raises(contains="named as one of vec2"):
        _ = store.array(StorageBufferNode(StorageBufferId(0), NODE_VEC2, 2))


def test_a_storage_texture_is_a_buffer_of_texels() raises:
    var store = StorageBufferStore()
    var texture = store.storage_texture(3, 2)
    assert_equal(texture.texels.type, NODE_VEC4)
    assert_equal(texture.texels.count, 6)
    with assert_raises(contains="needs a size"):
        _ = store.storage_texture(0, 2)
    with assert_raises(contains="needs a size"):
        _ = store.storage_texture(2, 0)
    var bent = StorageTexture(texture.texels, 2, 2)
    with assert_raises(contains="not its size"):
        _ = store.texture(bent)


# --- a first program ---------------------------------------------------------


def test_a_particle_moves_by_its_velocity() raises:
    # three.js's compute example: `position.addAssign( velocity )`.
    var store = StorageBufferStore()
    var positions = store.instanced_array([0, 0, 0, 1, 1, 1, 2, 2, 2], NODE_VEC3)
    var velocities = store.instanced_array(
        [1, 0, 0, 0, 2, 0, 0, 0, 3], NODE_VEC3
    )
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    kernel.add_assign(positions, i, kernel.element(velocities, i))
    var update = kernel.compute(3)
    assert_equal(update.workgroups(), 1)
    assert_equal(update.stages(), 1)
    run_compute(store, update)
    run_compute(store, update)
    var moved = _floats(store, positions)
    var want: List[Float32] = [2, 0, 0, 1, 5, 1, 2, 2, 8]
    for at in range(9):
        assert_equal(moved[at], want[at])


def test_a_float_fills_every_component_of_a_store() raises:
    var store = StorageBufferStore()
    var colors = store.instanced_array(2, NODE_VEC4)
    var kernel = ComputeKernel()
    kernel.assign(colors, kernel.instance_index(), kernel.graph.float(0.5))
    _run(store, kernel.compute(2))
    var got = _floats(store, colors)
    for at in range(8):
        assert_equal(got[at], 0.5)


def test_the_invocation_knows_its_numbers() raises:
    # Five invocations in workgroups of two: three workgroups, the last
    # with one invocation, as `dispatchWorkgroups( ceil( 5 / 2 ) )`.
    var store = StorageBufferStore()
    var out = store.instanced_array(5 * 7, NODE_FLOAT)
    var wide = store.instanced_array(5 * 4, NODE_VEC3)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var seven = kernel.graph.float(7)
    var four = kernel.graph.float(4)
    var numbers = [
        i,
        kernel.invocation_local_index(),
        kernel.builtin(WORKGROUP_ID),
        kernel.builtin(NUM_WORKGROUPS),
        kernel.subgroup_size(),
        kernel.subgroup_index(),
        kernel.invocation_subgroup_index(),
    ]
    for at in range(7):
        var place = kernel.graph.add(
            kernel.graph.mul(i, seven), kernel.graph.float(Float32(at))
        )
        kernel.assign(out, place, numbers[at])
    var vectors = [
        kernel.global_id(),
        kernel.local_id(),
        kernel.workgroup_id(),
        kernel.num_workgroups(),
    ]
    for at in range(4):
        var place = kernel.graph.add(
            kernel.graph.mul(i, four), kernel.graph.float(Float32(at))
        )
        kernel.assign(wide, place, vectors[at])
    var node = kernel.compute(5, 2)
    assert_equal(node.workgroups(), 3)
    run_compute(store, node)
    var got = _floats(store, out)
    for index in range(5):
        var row = index * 7
        assert_equal(got[row], Float32(index))
        assert_equal(got[row + 1], Float32(index % 2))
        assert_equal(got[row + 2], Float32(index // 2))
        assert_equal(got[row + 3], 3)
        assert_equal(got[row + 4], 1)
        assert_equal(got[row + 5], Float32(index % 2))
        assert_equal(got[row + 6], 0)
    var vec = _floats(store, wide)
    var last = 4 * 12
    assert_equal(vec[last], 4)
    assert_equal(vec[last + 1], 0)
    assert_equal(vec[last + 3], 0)
    assert_equal(vec[last + 6], 2)
    assert_equal(vec[last + 9], 3)
    assert_equal(vec[last + 10], 1)
    assert_equal(vec[last + 11], 1)


# --- steps -------------------------------------------------------------------


def test_a_read_sees_the_invocations_own_store_and_not_anothers() raises:
    # Each invocation writes its own element, then reads it and its
    # neighbor's in the same step: its own store, and the neighbor's
    # element as the step began. After a barrier it sees the neighbor's.
    var store = StorageBufferStore()
    var data = store.instanced_array([10, 20, 30], NODE_FLOAT)
    var own = store.instanced_array(3, NODE_FLOAT)
    var neighbor = store.instanced_array(3, NODE_FLOAT)
    var later = store.instanced_array(3, NODE_FLOAT)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var next = kernel.graph.mod(
        kernel.graph.add(i, kernel.graph.float(1)), kernel.graph.float(3)
    )
    kernel.assign(data, i, kernel.graph.add(i, kernel.graph.float(100)))
    kernel.assign(own, i, kernel.element(data, i))
    kernel.assign(neighbor, i, kernel.element(data, next))
    kernel.storage_barrier()
    kernel.assign(later, i, kernel.element(data, next))
    var node = kernel.compute(3)
    assert_equal(node.stages(), 2)
    run_compute(store, node)
    var want_own: List[Float32] = [100, 101, 102]
    var want_neighbor: List[Float32] = [20, 30, 10]
    var want_later: List[Float32] = [101, 102, 100]
    for at in range(3):
        assert_equal(_floats(store, own)[at], want_own[at])
        assert_equal(_floats(store, neighbor)[at], want_neighbor[at])
        assert_equal(_floats(store, later)[at], want_later[at])


def test_the_latest_store_wins_and_a_barrier_starts_no_empty_step() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array(2, NODE_FLOAT)
    var echo = store.instanced_array(2, NODE_FLOAT)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    kernel.workgroup_barrier()
    kernel.assign(data, i, kernel.graph.float(1))
    kernel.assign(data, i, kernel.graph.float(2))
    kernel.texture_barrier()
    kernel.workgroup_barrier()
    kernel.assign(echo, i, kernel.element(data, i))
    kernel.workgroup_barrier()
    var node = kernel.compute(2)
    assert_equal(node.stages(), 2)
    run_compute(store, node)
    assert_equal(_floats(store, data)[1], 2)
    assert_equal(_floats(store, echo)[0], 2)


def test_a_store_in_a_branch_is_kept_where_the_branch_runs() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array([5, 5, 5, 5], NODE_FLOAT)
    var seen = store.instanced_array(4, NODE_FLOAT)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var odd = kernel.graph.equal(
        kernel.graph.mod(i, kernel.graph.float(2)), kernel.graph.float(1)
    )
    kernel.graph.If(odd)
    kernel.assign(data, i, kernel.graph.float(9))
    kernel.graph.End()
    kernel.assign(seen, i, kernel.element(data, i))
    run_compute(store, kernel.compute(4))
    var want: List[Float32] = [5, 9, 5, 9]
    for at in range(4):
        assert_equal(_floats(store, data)[at], want[at])
        assert_equal(_floats(store, seen)[at], want[at])


def test_a_read_off_the_buffer_is_zero_and_a_store_off_it_is_lost() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array([1, 2], NODE_VEC2)
    var out = store.instanced_array(3, NODE_VEC2)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    # Invocation 0 reads element -1, 1 reads element 0 and 2 reads 1.
    var back = kernel.graph.sub(i, kernel.graph.float(1))
    kernel.assign(out, i, kernel.element(data, back))
    # Only invocation one stores on the buffer.
    kernel.assign(data, back, i)
    run_compute(store, kernel.compute(3))
    var got = _floats(store, out)
    var want: List[Float32] = [0, 0, 1, 2, 0, 0]
    for at in range(6):
        assert_equal(got[at], want[at])
    assert_equal(_floats(store, data)[0], 1)
    assert_equal(_floats(store, data)[1], 1)


def test_a_statement_cannot_be_made_in_a_loop() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array(2, NODE_FLOAT)
    var kernel = ComputeKernel()
    _ = kernel.graph.Loop(2)
    with assert_raises(contains="in a Loop"):
        kernel.assign(data, kernel.graph.float(0), kernel.graph.float(1))
    kernel.graph.End()
    assert_equal(kernel.statement_count(), 0)


# --- workgroup arrays --------------------------------------------------------


def test_a_workgroup_array_is_its_workgroups_own() raises:
    # Each workgroup of four reverses its span through its array, as a
    # bitonic sort's local pass reads the array after a barrier.
    var store = StorageBufferStore()
    var values = List[Float32]()
    for at in range(8):
        values.append(Float32(at * 10))
    var data = store.instanced_array(values^, NODE_FLOAT)
    var kernel = ComputeKernel()
    var local = kernel.workgroup_array(NODE_FLOAT, 4)
    var i = kernel.instance_index()
    var here = kernel.invocation_local_index()
    kernel.assign(local, here, kernel.element(data, i))
    kernel.workgroup_barrier()
    var mirror = kernel.graph.sub(kernel.graph.float(3), here)
    kernel.assign(data, i, kernel.element(local, mirror))
    var node = kernel.compute(8, 4)
    assert_equal(len(node.array_types), 1)
    run_compute(store, node)
    var want: List[Float32] = [30, 20, 10, 0, 70, 60, 50, 40]
    for at in range(8):
        assert_equal(_floats(store, data)[at], want[at])


def test_a_workgroup_array_refuses_what_it_is_not() raises:
    var kernel = ComputeKernel()
    with assert_raises(contains="one element or more"):
        _ = kernel.workgroup_array(NODE_FLOAT, 0)
    with assert_raises(contains="float or a vector"):
        _ = kernel.workgroup_array(NODE_MAT3, 4)
    var local = kernel.workgroup_array(NODE_VEC2, 4)
    var zero = kernel.graph.float(0)
    with assert_raises(contains="no such workgroup array"):
        _ = kernel.element(WorkgroupArrayNode(WorkgroupArrayId(-1), NODE_VEC2, 4), zero)
    with assert_raises(contains="no such workgroup array"):
        _ = kernel.element(WorkgroupArrayNode(WorkgroupArrayId(1), NODE_VEC2, 4), zero)
    with assert_raises(contains="no such workgroup array"):
        kernel.assign(WorkgroupArrayNode(local.array, NODE_FLOAT, 4), zero, zero)
    with assert_raises(contains="no such workgroup array"):
        _ = kernel.element(WorkgroupArrayNode(local.array, NODE_VEC2, 5), zero)


# --- atomics -----------------------------------------------------------------


def test_atomic_add_counts_a_histogram() raises:
    # Each of six places adds one to its bin, and keeps what the bin held:
    # on the host the invocations run in order, so a bin's places get
    # zero, one, two.
    var store = StorageBufferStore()
    var bins = store.instanced_array([2, 0, 2, 1, 2, 0], NODE_FLOAT)
    var counts = store.instanced_array(3, NODE_FLOAT)
    var ranks = store.instanced_array(6, NODE_FLOAT)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var bin = kernel.element(bins, i)
    var rank = kernel.atomic_add(counts, bin, kernel.graph.float(1))
    kernel.assign(ranks, i, rank)
    var node = kernel.compute(6, 4)
    assert_equal(node.results, 1)
    run_compute(store, node)
    var want_counts: List[Float32] = [2, 1, 3]
    var want_ranks: List[Float32] = [0, 0, 1, 0, 2, 1]
    for at in range(3):
        assert_equal(_floats(store, counts)[at], want_counts[at])
    for at in range(6):
        assert_equal(_floats(store, ranks)[at], want_ranks[at])


def test_every_atomic_function_leaves_what_wgsl_leaves() raises:
    assert_equal(atomic_result(ATOMIC_LOAD.value, 5, 9), 5)
    assert_equal(atomic_result(ATOMIC_STORE.value, 5, 9), 9)
    assert_equal(atomic_result(ATOMIC_ADD.value, 5, 9), 14)
    assert_equal(atomic_result(ATOMIC_SUB.value, 5, 9), -4)
    assert_equal(atomic_result(ATOMIC_MAX.value, 5, 9), 9)
    assert_equal(atomic_result(ATOMIC_MIN.value, 5, 9), 5)
    assert_equal(atomic_result(ATOMIC_AND.value, 12, 10), 8)
    assert_equal(atomic_result(ATOMIC_OR.value, 12, 10), 14)
    assert_equal(atomic_result(ATOMIC_XOR.value, 12, 10), 6)
    # NaN reads as zero, and infinity as the largest whole number held.
    assert_equal(atomic_result(ATOMIC_OR.value, nan[DType.float32](), 3), 3)
    assert_equal(
        atomic_result(ATOMIC_AND.value, inf[DType.float32](), 7), 0
    )


def test_each_atomic_function_runs_on_an_element() raises:
    var store = StorageBufferStore()
    var cells = store.instanced_array([12, 12, 12, 12, 12, 12, 12, 12], NODE_FLOAT)
    var olds = store.instanced_array(9, NODE_FLOAT)
    var kernel = ComputeKernel()
    var ten = kernel.graph.float(10)
    var results = List[NodeRef]()
    results.append(kernel.atomic_load(cells, kernel.graph.float(0)))
    kernel.atomic_store(cells, kernel.graph.float(0), ten)
    results.append(kernel.atomic_load(cells, kernel.graph.float(0)))
    results.append(kernel.atomic_add(cells, kernel.graph.float(1), ten))
    results.append(kernel.atomic_sub(cells, kernel.graph.float(2), ten))
    results.append(kernel.atomic_max(cells, kernel.graph.float(3), ten))
    results.append(kernel.atomic_min(cells, kernel.graph.float(4), ten))
    results.append(kernel.atomic_and(cells, kernel.graph.float(5), ten))
    results.append(kernel.atomic_or(cells, kernel.graph.float(6), ten))
    results.append(kernel.atomic_xor(cells, kernel.graph.float(7), ten))
    for at in range(9):
        kernel.assign(olds, kernel.graph.float(Float32(at)), results[at])
    run_compute(store, kernel.compute(1))
    var want: List[Float32] = [10, 22, 2, 12, 10, 8, 14, 6]
    for at in range(8):
        assert_equal(_floats(store, cells)[at], want[at])
    var old: List[Float32] = [12, 10, 12, 12, 12, 12, 12, 12, 12]
    for at in range(9):
        assert_equal(_floats(store, olds)[at], old[at])


def test_an_atomic_off_the_buffer_returns_zero() raises:
    var store = StorageBufferStore()
    var cells = store.instanced_array([4], NODE_FLOAT)
    var olds = store.instanced_array(1, NODE_FLOAT)
    var kernel = ComputeKernel()
    var zero = kernel.graph.float(0)
    var old = kernel.atomic_add(cells, kernel.graph.float(5), kernel.graph.float(1))
    kernel.assign(olds, zero, kernel.graph.add(old, kernel.graph.float(3)))
    # A read after an atomic function of its step is not laid over it.
    kernel.assign(olds, zero, kernel.graph.add(kernel.element(olds, zero), kernel.element(cells, zero)))
    run_compute(store, kernel.compute(1))
    assert_equal(_floats(store, cells)[0], 4)
    assert_equal(_floats(store, olds)[0], 7)


def test_an_atomic_function_refuses_what_wgsl_refuses() raises:
    var store = StorageBufferStore()
    var cells = store.instanced_array(2, NODE_FLOAT)
    var wide = store.instanced_array(2, NODE_VEC2)
    var kernel = ComputeKernel()
    var zero = kernel.graph.float(0)
    var pair = kernel.graph.vec2(0, 0)
    with assert_raises(contains="no function there is"):
        _ = kernel.atomic_func(AtomicOp(12), cells, zero, zero)
    with assert_raises(contains="buffer of floats"):
        _ = kernel.atomic_add(wide, zero, zero)
    with assert_raises(contains="float index and value"):
        _ = kernel.atomic_add(cells, pair, zero)
    with assert_raises(contains="float index and value"):
        _ = kernel.atomic_add(cells, zero, pair)


# --- held values -------------------------------------------------------------


def test_a_held_value_lasts_across_a_barrier() raises:
    # The value is read before a neighbor overwrites it, and still read
    # after the barrier.
    var store = StorageBufferStore()
    var data = store.instanced_array([1, 2], NODE_FLOAT)
    var out = store.instanced_array(2, NODE_VEC2)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var other = kernel.graph.sub(kernel.graph.float(1), i)
    var held = kernel.to_const(kernel.element(data, other))
    kernel.assign(data, other, kernel.graph.float(0))
    kernel.workgroup_barrier()
    var pair = kernel.to_const(kernel.graph.join([held, kernel.element(data, other)]))
    kernel.assign(out, i, pair)
    var node = kernel.compute(2)
    assert_equal(node.results, 2)
    run_compute(store, node)
    var got = _floats(store, out)
    var want: List[Float32] = [2, 0, 1, 0]
    for at in range(4):
        assert_equal(got[at], want[at])
    with assert_raises(contains="float or a vector"):
        _ = kernel.to_const(kernel.graph.uniform("m", Matrix3()))


def test_a_kernel_of_held_values_alone_runs_on_an_empty_store() raises:
    var store = StorageBufferStore()
    var kernel = ComputeKernel()
    _ = kernel.to_const(kernel.instance_index())
    run_compute(store, kernel.compute(2))
    assert_equal(store.count(), 0)


# --- subgroups ---------------------------------------------------------------


def test_a_subgroup_is_one_invocation() raises:
    var store = StorageBufferStore()
    var out = store.instanced_array(20, NODE_FLOAT)
    var ballots = store.instanced_array(1, NODE_VEC4)
    var pairs = store.instanced_array(2, NODE_VEC2)
    var kernel = ComputeKernel()
    var x = kernel.graph.float(3)
    var id = kernel.graph.float(0)
    var values = [
        kernel.subgroup_add(x),
        kernel.subgroup_inclusive_add(x),
        kernel.subgroup_exclusive_add(x),
        kernel.subgroup_mul(x),
        kernel.subgroup_inclusive_mul(x),
        kernel.subgroup_exclusive_mul(x),
        kernel.subgroup_and(x),
        kernel.subgroup_or(x),
        kernel.subgroup_xor(x),
        kernel.subgroup_min(x),
        kernel.subgroup_max(x),
        kernel.subgroup_all(x),
        kernel.subgroup_any(kernel.graph.float(0)),
        kernel.subgroup_elect(),
        kernel.subgroup_broadcast(x, id),
        kernel.subgroup_broadcast_first(x),
        kernel.subgroup_shuffle(x, id),
        kernel.subgroup_shuffle_xor(x, id),
        kernel.subgroup_shuffle_up(x, id),
        kernel.subgroup_shuffle_down(x, id),
    ]
    for at in range(20):
        kernel.assign(out, kernel.graph.float(Float32(at)), values[at])
    kernel.assign(ballots, id, kernel.subgroup_ballot(x))
    var v2 = kernel.graph.vec2(2, 5)
    kernel.assign(pairs, id, kernel.subgroup_exclusive_add(v2))
    kernel.assign(pairs, kernel.graph.float(1), kernel.subgroup_exclusive_mul(v2))
    run_compute(store, kernel.compute(1))
    var want: List[Float32] = [3, 3, 0, 3, 3, 1, 3, 3, 3, 3, 3, 1, 0, 1, 3, 3, 3, 3, 3, 3]
    for at in range(20):
        assert_equal(_floats(store, out)[at], want[at])
    assert_equal(_floats(store, ballots)[0], 1)
    assert_equal(_floats(store, ballots)[1], 0)
    var got = _floats(store, pairs)
    assert_equal(got[0], 0)
    assert_equal(got[1], 0)
    assert_equal(got[2], 1)
    assert_equal(got[3], 1)
    var v3 = kernel.graph.vec3(1, 2, 3)
    var v4 = kernel.graph.vec4(1, 2, 3, 4)
    assert_equal(kernel.graph.type_of(kernel.subgroup_exclusive_add(v3)), NODE_VEC3)
    assert_equal(kernel.graph.type_of(kernel.subgroup_exclusive_mul(v4)), NODE_VEC4)
    var m = kernel.graph.uniform("m", Matrix3())
    with assert_raises(contains="float or a vector"):
        _ = kernel.subgroup_add(m)


# --- storage textures --------------------------------------------------------


def test_a_storage_texture_is_written_texel_by_texel() raises:
    # textureStore( texture, uvec2( x, y ), vec4( x, y, 0, 1 ) ) at each
    # texel of a three by two texture, and one write off it.
    var store = StorageBufferStore()
    var texture = store.storage_texture(3, 2)
    var echo = store.instanced_array(7, NODE_VEC4)
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var x = kernel.graph.mod(i, kernel.graph.float(3))
    var y = kernel.graph.floor(kernel.graph.div(i, kernel.graph.float(3)))
    var coord = kernel.graph.join([x, y])
    var texel = kernel.graph.join([x, y, kernel.graph.float(0), kernel.graph.float(1)])
    kernel.texture_store(texture, coord, texel)
    kernel.storage_barrier()
    kernel.assign(echo, i, kernel.texture_load(texture, coord))
    run_compute(store, kernel.compute(7))
    var texels = _floats(store, texture.texels)
    for at in range(6):
        assert_equal(texels[at * 4], Float32(at % 3))
        assert_equal(texels[at * 4 + 1], Float32(at // 3))
        assert_equal(texels[at * 4 + 3], 1)
    var got = _floats(store, echo)
    assert_equal(got[5 * 4], 2)
    # Invocation six is at (0, 2), one row below the texture.
    assert_equal(got[6 * 4 + 3], 0)
    var map = store.texture(texture)
    assert_equal(map.width, 3)
    assert_equal(map.height, 2)
    with assert_raises(contains="read at a vec2"):
        kernel.texture_store(texture, x, texel)


def test_a_storage_texture_refuses_a_column_off_it() raises:
    var store = StorageBufferStore()
    var texture = store.storage_texture(2, 2)
    var kernel = ComputeKernel()
    var one = kernel.graph.vec4(1, 1, 1, 1)
    kernel.texture_store(texture, kernel.graph.vec2(-1, 0), one)
    kernel.texture_store(texture, kernel.graph.vec2(2, 0), one)
    kernel.texture_store(texture, kernel.graph.vec2(0, -1), one)
    run_compute(store, kernel.compute(1))
    var texels = _floats(store, texture.texels)
    for at in range(16):
        assert_equal(texels[at], 0)


# --- what a kernel refuses ---------------------------------------------------


def test_a_kernel_refuses_what_it_cannot_run() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array(2, NODE_FLOAT)
    var wide = store.instanced_array(2, NODE_VEC3)
    var kernel = ComputeKernel()
    with assert_raises(contains="needs a statement"):
        _ = kernel.compute(1)
    var zero = kernel.graph.float(0)
    var pair = kernel.graph.vec2(1, 2)
    with assert_raises(contains="float index"):
        kernel.assign(data, pair, zero)
    with assert_raises(contains="cannot hold a vec2"):
        kernel.assign(wide, zero, pair)
    with assert_raises(contains="no buffer there can be"):
        kernel.assign(StorageBufferNode(StorageBufferId(-1), NODE_FLOAT, 2), zero, zero)
    with assert_raises(contains="float or a vector"):
        kernel.assign(StorageBufferNode(StorageBufferId(5), NODE_MAT3, 2), zero, zero)
    kernel.assign(data, zero, zero)
    with assert_raises(contains="one storage buffer as two types"):
        _ = kernel.element(StorageBufferNode(data.buffer, NODE_VEC2, 1), zero)
    with assert_raises(contains="one invocation or more"):
        _ = kernel.compute(0)
    with assert_raises(contains="1024 invocations"):
        _ = kernel.compute(4, 0)
    with assert_raises(contains="1024 invocations"):
        _ = kernel.compute(4, 2048)
    var node = kernel.compute(4, 1024)
    node.set_name("Zero")
    assert_equal(node.name, "Zero")
    node.set_count(9)
    assert_equal(node.count, 9)
    with assert_raises(contains="one invocation or more"):
        node.set_count(0)


def test_a_run_refuses_a_store_without_the_kernels_buffer() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array(2, NODE_FLOAT)
    var kernel = ComputeKernel()
    kernel.assign(data, kernel.graph.float(0), kernel.graph.float(1))
    var node = kernel.compute(1)
    var empty = StorageBufferStore()
    with assert_raises(contains="no buffer 0"):
        run_compute(empty, node)
    var other = StorageBufferStore()
    _ = other.instanced_array(2, NODE_VEC2)
    with assert_raises(contains="named as one of float"):
        _ = pack_storage(other, node)


def test_a_compute_program_reads_no_surface() raises:
    var store = StorageBufferStore()
    var data = store.instanced_array(2, NODE_VEC2)
    var kernel = ComputeKernel()
    kernel.assign(data, kernel.graph.float(0), kernel.graph.uv())
    with assert_raises(contains="runs on no surface"):
        _ = kernel.compute(1)
    var textured = ComputeKernel()
    var sampler = textured.graph.texture_uniform("map")
    var texel = textured.graph.texture(sampler, textured.graph.vec2(0, 0))
    textured.assign(data, textured.graph.float(0), textured.graph.swizzle(texel, "xy"))
    with assert_raises(contains="runs on no surface"):
        _ = textured.compute(1)
    var discarded = ComputeKernel()
    discarded.assign(data, discarded.graph.float(0), discarded.graph.vec2(0, 0))
    discarded.graph.Discard()
    with assert_raises(contains="no fragment to Discard"):
        _ = discarded.compute(1)
    var open = ComputeKernel()
    open.graph.If(open.graph.float(1))
    open.assign(data, open.graph.float(0), open.graph.vec2(0, 0))
    with assert_raises(contains="never closed"):
        _ = open.compute(1)


def test_a_material_reads_no_compute_leaf() raises:
    var graph = NodeGraph()
    graph.set_output(OPACITY_NODE, graph.compute_builtin(INSTANCE_INDEX))
    with assert_raises(contains="Only a compute program"):
        _ = graph.compile()
    var stored = NodeGraph()
    stored.set_output(
        OPACITY_NODE,
        stored.storage_element(StorageBufferId(0), stored.float(0), NODE_FLOAT),
    )
    with assert_raises(contains="Only a compute program"):
        _ = stored.compile()
    var result = NodeGraph()
    result.set_output(
        OPACITY_NODE, result.compute_result(ComputeStatementId(0), NODE_FLOAT)
    )
    with assert_raises(contains="Only a compute program"):
        _ = result.compile()


def test_the_graph_refuses_a_compute_leaf_there_cannot_be() raises:
    var graph = NodeGraph()
    var zero = graph.float(0)
    with assert_raises(contains="no number there is"):
        _ = graph.compute_builtin(ComputeBuiltin(9))
    with assert_raises(contains="no buffer there can be"):
        _ = graph.storage_element(StorageBufferId(-1), zero, NODE_FLOAT)
    with assert_raises(contains="no array there can be"):
        _ = graph.storage_element(WorkgroupArrayId(-1), zero, NODE_FLOAT)
    with assert_raises(contains="float index"):
        _ = graph.storage_element(StorageBufferId(0), graph.vec2(0, 0), NODE_FLOAT)
    with assert_raises(contains="float or a vector"):
        _ = graph.storage_element(StorageBufferId(0), zero, NODE_MAT3)
    with assert_raises(contains="no statement there can be"):
        _ = graph.compute_result(ComputeStatementId(-1), NODE_FLOAT)
    with assert_raises(contains="float or a vector"):
        _ = graph.compute_result(ComputeStatementId(0), NODE_MAT3)


def test_the_graph_says_where_code_runs() raises:
    var graph = NodeGraph()
    assert_false(graph.in_loop())
    graph.If(graph.float(1))
    assert_false(graph.in_loop())
    _ = graph.Loop(1)
    assert_true(graph.in_loop())
    _ = graph.running()
    graph.End()
    graph.End()
    var starts: List[Int] = [7]
    var program = graph.compile_roots(List[NodeRef](), starts)
    assert_equal(len(starts), 0)
    assert_true(len(program.code) > 0)


def test_a_source_that_runs_no_compute_program_reads_zeros() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    var program = graph.compile()
    var source = ProgramSource(Pointer(to=program))
    assert_equal(source.compute_builtin(0), 0)
    assert_equal(source.storage_element(0, 0)[0], 0)
    assert_equal(source.statement_result(0)[0], 0)


def test_a_compute_source_reads_no_surface() raises:
    var code: List[Float32] = [0]
    var memory: List[Float32] = [0]
    var regions: List[Int32] = [0, 1, 1]
    var kept: List[Float32] = [0, 0, 0, 0]
    var source = ComputeSource(
        code.unsafe_ptr().unsafe_mut_cast[False]().unsafe_origin_cast[Untracked](),
        memory.unsafe_ptr().unsafe_mut_cast[False]().unsafe_origin_cast[Untracked](),
        regions.unsafe_ptr().unsafe_mut_cast[False]().unsafe_origin_cast[Untracked](),
        kept.unsafe_ptr().unsafe_origin_cast[MutUntracked](),
        1,
        0,
        0,
        1,
        1,
    )
    assert_equal(source.sample(0, 0, 0).a, 1)
    assert_equal(source.sample_level(0, 0, 0, 0).r, 1)
    assert_equal(source.fetch(0, 0, 0, 0).g, 1)
    assert_equal(source.size(0, 0)[0], 1)
    assert_equal(source.shares(AT_FRAGMENT)[0], 1)
    assert_equal(source.frag_coord(AT_FRAGMENT)[3], 1)
    assert_equal(source.corner(AT_FRAGMENT).u, 0)
    # NaN is off every buffer.
    assert_equal(source.address(0, nan[DType.float32]()), -1)
    assert_equal(source.address(0, 0), 0)
    var memory_at = HostMemory(kept.unsafe_ptr().unsafe_origin_cast[MutUntracked]())
    memory_at.store(1, 4)
    assert_equal(memory_at.atomic(ATOMIC_ADD.value, 1, 2), 4)
    assert_equal(kept[1], 6)
    _ = code
    _ = memory
    _ = regions


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
