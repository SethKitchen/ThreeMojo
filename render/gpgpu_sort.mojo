# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sorts that run as compute programs, from three.js's
`examples/jsm/gpgpu/`: `BitonicSort` and `CountingSort`.

Both are built of `materials.compute_nodes` kernels and run on any
`ComputeRunner`: `HostCompute` on the host, and `render.gpu.GpuCompute` on
the device.

**BitonicSort** sorts a buffer of `float`s in place, smallest first. Its
count must be a power of two. It swaps within each workgroup's copy of a
workgroup array first, then flips and disperses across the whole buffer,
ping-ponging a second buffer, as three.js's does. A third buffer holds the
step and the swap span, so each kernel reads them as the last one left
them.

**CountingSort** orders the places `0` to `count - 1` by a bin that a
node computes for each, from zero to `bin_count - 1`. It counts the bins
with `atomicAdd`, sums them in one invocation, and scatters each place to
its bin with `atomicAdd` again. Places in one bin keep their order on the
host, which runs the invocations in order, and can come in any order on
the device, as three.js says of its own.
"""

from materials.compute_ids import WORKGROUP_ID
from materials.compute_nodes import (
    ComputeKernel,
    ComputeNode,
    ComputeRunner,
    StorageBufferNode,
    StorageBufferStore,
    WorkgroupArrayNode,
)
from materials.nodes import NODE_FLOAT, NodeGraph, NodeRef

# What the next bitonic dispatch does, three.js's `StepType`, as the
# floats the info buffer holds.
comptime _SWAP_LOCAL = Float32(1)
comptime _DISPERSE_LOCAL = Float32(2)
comptime _FLIP_GLOBAL = Float32(3)
comptime _DISPERSE_GLOBAL = Float32(4)


def _is_power_of_two(n: Int) -> Bool:
    """Return True for one, two, four and so on."""
    return n > 0 and (n & (n - 1)) == 0


def _log2(n: Int) -> Int:
    """Return the base-two logarithm of a power of two."""
    var out = 0
    var left = n
    while left > 1:
        left >>= 1
        out += 1
    return out


def _quotient(mut graph: NodeGraph, a: NodeRef, b: NodeRef) raises -> NodeRef:
    """Return a whole number divided by another, rounded down: WGSL's
    `uint` division."""
    return graph.floor(graph.div(a, b))


def bitonic_flip_indices(
    mut graph: NodeGraph, index: NodeRef, block_height: NodeRef
) raises -> NodeRef:
    """Return the two places a bitonic flip compares, three.js's
    `getBitonicFlipIndices`: mirrored in each block of `block_height`.

    Args:
        graph: The graph to build into.
        index: The invocation's place, a `float`.
        block_height: The block's height, a power of two, a `float`.

    Returns:
        The two places, a `vec2`.

    Raises:
        Error: If a node is not a `float` of the graph.
    """
    var two = graph.float(2)
    var offset = graph.mul(
        _quotient(graph, graph.mul(index, two), block_height), block_height
    )
    var half = _quotient(graph, block_height, two)
    var within = graph.mod(index, half)
    var first = graph.add(within, offset)
    var second = graph.add(
        graph.sub(graph.sub(block_height, within), graph.float(1)), offset
    )
    return graph.join([first, second])


def bitonic_disperse_indices(
    mut graph: NodeGraph, index: NodeRef, swap_span: NodeRef
) raises -> NodeRef:
    """Return the two places a bitonic disperse compares, three.js's
    `getBitonicDisperseIndices`: half a span apart.

    Args:
        graph: The graph to build into.
        index: The invocation's place, a `float`.
        swap_span: The span, a power of two, a `float`.

    Returns:
        The two places, a `vec2`.

    Raises:
        Error: If a node is not a `float` of the graph.
    """
    var two = graph.float(2)
    var offset = graph.mul(
        _quotient(graph, graph.mul(index, two), swap_span), swap_span
    )
    var half = _quotient(graph, swap_span, two)
    var within = graph.mod(index, half)
    var first = graph.add(within, offset)
    var second = graph.add(graph.add(within, half), offset)
    return graph.join([first, second])


def _global_compare_and_swap(
    mut kernel: ComputeKernel,
    places: NodeRef,
    source: StorageBufferNode,
    write: StorageBufferNode,
) raises:
    """Write the smaller of two elements to the first place and the larger
    to the second, from one buffer to the other."""
    var x = kernel.graph.swizzle(places, "x")
    var y = kernel.graph.swizzle(places, "y")
    var a = kernel.element(source, x)
    var b = kernel.element(source, y)
    kernel.assign(write, x, kernel.graph.min(a, b))
    kernel.assign(write, y, kernel.graph.max(a, b))


def _local_compare_and_swap(
    mut kernel: ComputeKernel, local: WorkgroupArrayNode, places: NodeRef
) raises:
    """Order two elements of the workgroup's array in place."""
    var x = kernel.graph.swizzle(places, "x")
    var y = kernel.graph.swizzle(places, "y")
    var a = kernel.element(local, x)
    var b = kernel.element(local, y)
    kernel.assign(local, x, kernel.graph.min(a, b))
    kernel.assign(local, y, kernel.graph.max(a, b))


def _bitonic_global(
    info: StorageBufferNode,
    source: StorageBufferNode,
    write: StorageBufferNode,
    flip: Bool,
    dispatch_size: Int,
    workgroup_size: Int,
) raises -> ComputeNode:
    """Return a flip or a disperse across the whole buffer at the info
    buffer's span, three.js's `_getFlipGlobal` and `_getDisperseGlobal`."""
    var kernel = ComputeKernel()
    var span = kernel.element(info, kernel.graph.float(1))
    var index = kernel.instance_index()
    var places = bitonic_flip_indices(
        kernel.graph, index, span
    ) if flip else bitonic_disperse_indices(kernel.graph, index, span)
    _global_compare_and_swap(kernel, places, source, write)
    return kernel.compute(dispatch_size, workgroup_size)


def _disperses(
    mut kernel: ComputeKernel,
    local: WorkgroupArrayNode,
    here: NodeRef,
    from_height: Int,
) raises:
    """Build the local disperses from a block height down to two, a
    barrier before each."""
    var height = from_height
    while height > 1:
        kernel.workgroup_barrier()
        var places = bitonic_disperse_indices(
            kernel.graph, here, kernel.graph.float(Float32(height))
        )
        _local_compare_and_swap(kernel, local, places)
        height //= 2


def _bitonic_local(
    buffer: StorageBufferNode,
    swap: Bool,
    dispatch_size: Int,
    workgroup_size: Int,
) raises -> ComputeNode:
    """Return a sort of each workgroup's span in its workgroup array: every
    flip up to the span, each with its disperses, for the first dispatch,
    three.js's `_getSwapLocal`; or the span's disperses alone,
    `_getDisperseLocal`."""
    var kernel = ComputeKernel()
    var span = workgroup_size * 2
    var local = kernel.workgroup_array(NODE_FLOAT, span)
    var offset = kernel.to_const(
        kernel.graph.mul(
            kernel.graph.float(Float32(span)), kernel.builtin(WORKGROUP_ID)
        )
    )
    var here = kernel.invocation_local_index()
    var first = kernel.graph.mul(here, kernel.graph.float(2))
    var second = kernel.graph.add(first, kernel.graph.float(1))
    var first_read = kernel.element(buffer, kernel.graph.add(offset, first))
    kernel.assign(local, first, first_read)
    var second_read = kernel.element(buffer, kernel.graph.add(offset, second))
    kernel.assign(local, second, second_read)
    kernel.workgroup_barrier()
    if swap:
        var flip = 2
        while flip <= span:
            kernel.workgroup_barrier()
            var places = bitonic_flip_indices(
                kernel.graph, here, kernel.graph.float(Float32(flip))
            )
            _local_compare_and_swap(kernel, local, places)
            _disperses(kernel, local, here, flip // 2)
            flip *= 2
    else:
        _disperses(kernel, local, here, span)
    kernel.workgroup_barrier()
    var first_back = kernel.element(local, first)
    kernel.assign(buffer, kernel.graph.add(offset, first), first_back)
    var second_back = kernel.element(local, second)
    kernel.assign(buffer, kernel.graph.add(offset, second), second_back)
    return kernel.compute(dispatch_size, workgroup_size)


def _bitonic_reset(info: StorageBufferNode) raises -> ComputeNode:
    """Return the kernel that starts the info buffer again, three.js's
    `_getResetFn`."""
    var kernel = ComputeKernel()
    var zero = kernel.graph.float(0)
    var one = kernel.graph.float(1)
    var two = kernel.graph.float(2)
    kernel.assign(info, zero, kernel.graph.float(_SWAP_LOCAL))
    kernel.assign(info, one, two)
    kernel.assign(info, two, two)
    return kernel.compute(1)


def _bitonic_align(
    data: StorageBufferNode,
    temp: StorageBufferNode,
    count: Int,
    workgroup_size: Int,
) raises -> ComputeNode:
    """Return the kernel that copies the second buffer to the data,
    three.js's `_getAlignFn`."""
    var kernel = ComputeKernel()
    var index = kernel.instance_index()
    var copied = kernel.element(temp, index)
    kernel.assign(data, index, copied)
    return kernel.compute(count, workgroup_size)


def _bitonic_set_algo(
    info: StorageBufferNode, workgroup_size: Int
) raises -> ComputeNode:
    """Return the kernel that picks the next step and span, three.js's
    `_getSetAlgoFn`."""
    var kernel = ComputeKernel()
    var zero = kernel.graph.float(0)
    var one = kernel.graph.float(1)
    var two = kernel.graph.float(2)
    var algo = kernel.element(info, zero)
    var span = kernel.element(info, one)
    var widest = kernel.element(info, two)
    var flip_global = kernel.graph.float(_FLIP_GLOBAL)
    kernel.graph.If(kernel.graph.equal(algo, kernel.graph.float(_SWAP_LOCAL)))
    var next_span = kernel.graph.float(Float32(workgroup_size * 4))
    kernel.assign(info, zero, flip_global)
    kernel.assign(info, one, next_span)
    kernel.assign(info, two, next_span)
    kernel.graph.ElseIf(
        kernel.graph.equal(algo, kernel.graph.float(_DISPERSE_LOCAL))
    )
    kernel.assign(info, zero, flip_global)
    var doubled = kernel.graph.mul(widest, two)
    kernel.assign(info, one, doubled)
    kernel.assign(info, two, doubled)
    kernel.graph.Else()
    var halved = _quotient(kernel.graph, span, two)
    var local = kernel.graph.less_than_equal(
        halved, kernel.graph.float(Float32(workgroup_size * 2))
    )
    var next = kernel.graph.select(
        local,
        kernel.graph.float(_DISPERSE_LOCAL),
        kernel.graph.float(_DISPERSE_GLOBAL),
    )
    kernel.assign(info, zero, next)
    kernel.assign(info, one, halved)
    kernel.graph.End()
    return kernel.compute(1)


struct BitonicSort(Movable):
    """A bitonic sort of a buffer of `float`s, three.js's `BitonicSort`."""

    var data: StorageBufferNode
    var temp: StorageBufferNode
    var info: StorageBufferNode
    var count: Int
    var dispatch_size: Int
    var workgroup_size: Int
    var swap_op_count: Int
    var step_count: Int
    # Which buffer the next global swap reads, three.js's
    # `readBufferName`: the data, or the second buffer.
    var reads_data: Bool
    # Each pair holds the kernel that reads the data, then the one that
    # reads the second buffer.
    var flip_global: List[ComputeNode]
    var disperse_global: List[ComputeNode]
    var disperse_local: List[ComputeNode]
    var swap_local: ComputeNode
    var set_algo: ComputeNode
    var align: ComputeNode
    var reset: ComputeNode
    var current_dispatch: Int
    var global_ops_remaining: Int
    var global_ops_in_span: Int

    def __init__(
        out self,
        mut store: StorageBufferStore,
        data: StorageBufferNode,
        workgroup_size: Int = 64,
    ) raises:
        """Build the kernels that sort a buffer, three.js's `new
        BitonicSort( renderer, dataBuffer, { workgroupSize } )`. It adds
        its second buffer and its info buffer to the store.

        Args:
            store: The buffers.
            data: The buffer to sort: `float`s, a power of two of them, two
                or more.
            workgroup_size: The largest workgroup, a power of two; held to
                half the count.

        Raises:
            Error: If the buffer is not of `float`s, its count is not a
                power of two past one, or the workgroup size is not a power
                of two.
        """
        if data.type != NODE_FLOAT:
            raise Error("A bitonic sort sorts a buffer of floats")
        if data.count < 2 or not _is_power_of_two(data.count):
            raise Error("A bitonic sort needs a power of two of elements")
        if not _is_power_of_two(workgroup_size):
            raise Error("A bitonic sort's workgroup is a power of two")
        var count = data.count
        var dispatch = count // 2
        var size = min(dispatch, workgroup_size)
        var temp = store.instanced_array(count, NODE_FLOAT)
        var info = store.instanced_array([1, 2, 2], NODE_FLOAT)
        var n = _log2(count)
        var steps = 1
        var disperses = 0
        for _ in range(n - _log2(size * 2)):
            steps += 2 + disperses
            disperses += 1
        self.flip_global = [
            _bitonic_global(info, data, temp, True, dispatch, size),
            _bitonic_global(info, temp, data, True, dispatch, size),
        ]
        self.disperse_global = [
            _bitonic_global(info, data, temp, False, dispatch, size),
            _bitonic_global(info, temp, data, False, dispatch, size),
        ]
        self.disperse_local = [
            _bitonic_local(data, False, dispatch, size),
            _bitonic_local(temp, False, dispatch, size),
        ]
        self.swap_local = _bitonic_local(data, True, dispatch, size)
        self.set_algo = _bitonic_set_algo(info, size)
        self.align = _bitonic_align(data, temp, count, size)
        self.reset = _bitonic_reset(info)
        self.data = data
        self.temp = temp
        self.info = info
        self.count = count
        self.dispatch_size = dispatch
        self.workgroup_size = size
        self.swap_op_count = n * (n + 1) // 2
        self.step_count = steps
        self.reads_data = True
        self.current_dispatch = 0
        self.global_ops_remaining = 0
        self.global_ops_in_span = 0

    def compute_step[
        R: ComputeRunner
    ](mut self, mut runner: R, mut store: StorageBufferStore) raises:
        """Run the sort's next dispatch, three.js's `computeStep`.

        Args:
            runner: What runs the kernels.
            store: The buffers.

        Raises:
            Error: If the runner refuses a kernel.
        """
        if self.current_dispatch == 0:
            runner.compute(store, self.swap_local)
            self.global_ops_remaining = 1
            self.global_ops_in_span = 1
        elif self.global_ops_remaining > 0:
            var which = 0 if self.reads_data else 1
            if self.global_ops_remaining == self.global_ops_in_span:
                runner.compute(store, self.flip_global[which])
            else:
                runner.compute(store, self.disperse_global[which])
            self.reads_data = not self.reads_data
            self.global_ops_remaining -= 1
        else:
            var which = 0 if self.reads_data else 1
            runner.compute(store, self.disperse_local[which])
            self.global_ops_in_span += 1
            self.global_ops_remaining = self.global_ops_in_span
        self.current_dispatch += 1
        if self.current_dispatch == self.step_count:
            if not self.reads_data:
                runner.compute(store, self.align)
                self.reads_data = True
            runner.compute(store, self.reset)
            self.current_dispatch = 0
            self.global_ops_remaining = 0
            self.global_ops_in_span = 0
        else:
            runner.compute(store, self.set_algo)

    def compute[
        R: ComputeRunner
    ](mut self, mut runner: R, mut store: StorageBufferStore) raises:
        """Sort the buffer, three.js's `compute`: every step in turn.

        Args:
            runner: What runs the kernels.
            store: The buffers.

        Raises:
            Error: If the runner refuses a kernel.
        """
        self.global_ops_remaining = 0
        self.global_ops_in_span = 0
        self.current_dispatch = 0
        for _ in range(self.step_count):  # pragma: no branch
            self.compute_step(runner, store)


comptime BinNode = def(mut ComputeKernel) raises thin -> NodeRef
"""What builds a counting sort's bin for the invocation's place, three.js's
`binNode`: a `float` from zero to `bin_count - 1`."""


struct CountingSort(Movable):
    """A counting sort of the places `0` to `count - 1` by a bin each,
    three.js's `CountingSort`."""

    var count: Int
    var bin_count: Int
    var workgroup_size: Int
    # The sorted places, three.js's `orderAttribute`; each place's bin; how
    # many places each bin holds; and each bin's first place, then its
    # write cursor.
    var order: StorageBufferNode
    var bins: StorageBufferNode
    var histogram: StorageBufferNode
    var offsets: StorageBufferNode
    # The reset, histogram, prefix and scatter kernels, once a bin node is
    # set.
    var nodes: List[ComputeNode]

    def __init__(
        out self,
        mut store: StorageBufferStore,
        count: Int,
        bin_count: Int = 4096,
        workgroup_size: Int = 256,
    ) raises:
        """Add a sort's buffers to a store, three.js's `new CountingSort(
        count, { binCount, workgroupSize } )`. The order starts as the
        places in turn.

        Args:
            store: The buffers.
            count: How many places, one or more.
            bin_count: How many bins, one or more.
            workgroup_size: How many invocations a workgroup has.

        Raises:
            Error: If a count is not positive.
        """
        if count <= 0 or bin_count <= 0 or workgroup_size <= 0:
            raise Error("A counting sort needs places, bins and a workgroup")
        self.count = count
        self.bin_count = bin_count
        self.workgroup_size = workgroup_size
        var order = List[Float32](capacity=count)
        for place in range(count):  # pragma: no branch
            order.append(Float32(place))
        self.order = store.instanced_array(order^, NODE_FLOAT)
        self.bins = store.instanced_array(count, NODE_FLOAT)
        self.histogram = store.instanced_array(bin_count, NODE_FLOAT)
        self.offsets = store.instanced_array(bin_count, NODE_FLOAT)
        self.nodes = List[ComputeNode]()

    def set_bin_node(mut self, bin_node: BinNode) raises:
        """Build the four kernels around a bin node, three.js's
        `setBinNode`.

        Args:
            bin_node: What builds the bin of the invocation's place.

        Raises:
            Error: If the bin node raises or builds what a kernel refuses.
        """
        self.nodes = List[ComputeNode]()
        var reset = ComputeKernel()
        var slot = reset.instance_index()
        reset.atomic_store(self.histogram, slot, reset.graph.float(0))
        reset.atomic_store(self.offsets, slot, reset.graph.float(0))
        var reset_node = reset.compute(self.bin_count, self.workgroup_size)
        reset_node.set_name("CountingSortReset")
        self.nodes.append(reset_node^)

        var histogram = ComputeKernel()
        var bin = histogram.to_const(bin_node(histogram))
        var place = histogram.instance_index()
        histogram.assign(self.bins, place, bin)
        _ = histogram.atomic_add(self.histogram, bin, histogram.graph.float(1))
        var histogram_node = histogram.compute(self.count, self.workgroup_size)
        histogram_node.set_name("CountingSortHistogram")
        self.nodes.append(histogram_node^)

        var prefix = ComputeKernel()
        var sum = prefix.graph.float(0)
        for at in range(self.bin_count):  # pragma: no branch
            var index = prefix.graph.float(Float32(at))
            var held = prefix.atomic_load(self.histogram, index)
            prefix.atomic_store(self.offsets, index, sum)
            sum = prefix.to_const(prefix.graph.add(sum, held))
        var prefix_node = prefix.compute(1)
        prefix_node.set_name("CountingSortPrefix")
        self.nodes.append(prefix_node^)

        var scatter = ComputeKernel()
        var here = scatter.instance_index()
        var own = scatter.to_const(scatter.element(self.bins, here))
        var target = scatter.atomic_add(
            self.offsets, own, scatter.graph.float(1)
        )
        scatter.assign(self.order, target, here)
        var scatter_node = scatter.compute(self.count, self.workgroup_size)
        scatter_node.set_name("CountingSortScatter")
        self.nodes.append(scatter_node^)

    def compute[
        R: ComputeRunner
    ](self, mut runner: R, mut store: StorageBufferStore) raises:
        """Sort, three.js's `compute`: reset, count, sum and scatter.

        Args:
            runner: What runs the kernels.
            store: The buffers.

        Raises:
            Error: If no bin node is set, or the runner refuses a kernel.
        """
        if len(self.nodes) == 0:
            raise Error("A counting sort needs a bin node")
        for at in range(len(self.nodes)):  # pragma: no branch
            runner.compute(store, self.nodes[at])

    def compute_cpu(
        self, mut store: StorageBufferStore, bins: List[Int]
    ) raises:
        """Sort on the host without a compute program, three.js's
        `computeCPU`, from each place's bin.

        Args:
            store: The buffers. The order lands in it.
            bins: Each place's bin, from zero to `bin_count - 1`.

        Raises:
            Error: If there is not one bin a place, or a bin is out of
                range.
        """
        if len(bins) != self.count:
            raise Error("A counting sort needs one bin a place")
        var counts = List[Int](length=self.bin_count, fill=0)
        for place in range(self.count):  # pragma: no branch
            var bin = bins[place]
            if bin < 0 or bin >= self.bin_count:
                raise Error("A counting sort's bin is out of range")
            counts[bin] += 1
        var offsets = List[Int](length=self.bin_count, fill=0)
        var sum = 0
        for at in range(self.bin_count):  # pragma: no branch
            offsets[at] = sum
            sum += counts[at]
        var order = List[Float32](length=self.count, fill=0)
        for place in range(self.count):  # pragma: no branch
            order[offsets[bins[place]]] = Float32(place)
            offsets[bins[place]] += 1
        store.set_array(self.order, order^)
