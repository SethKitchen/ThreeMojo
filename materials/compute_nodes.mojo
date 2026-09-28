# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compute programs over storage buffers, from three.js's
`src/nodes/gpgpu/`: `ComputeNode`, `AtomicFunctionNode`, `BarrierNode`,
`WorkgroupInfoNode` and `SubgroupFunctionNode`, with the storage buffers
and textures they read and write (`StorageBufferNode`,
`StorageTextureNode`, `instancedArray`).

three.js writes a compute shader as a TSL function of statements:

```js
const update = Fn( () => {
    const position = positions.element( instanceIndex );
    position.addAssign( velocities.element( instanceIndex ) );
} )().compute( count );
renderer.compute( update );
```

Here a `ComputeKernel` holds a `NodeGraph` and the statements built on it,
and `compute` compiles them to a `ComputeNode`:

```mojo
var kernel = ComputeKernel()
var i = kernel.instance_index()
var moved = kernel.graph.add(
    kernel.element(positions, i), kernel.element(velocities, i)
)
kernel.assign(positions, i, moved)
var update = kernel.compute(count)
HostCompute().compute(store, update)
```

**Statements.** The node bytecode has no side effects, so a statement is
kept beside the graph: a store to a storage element, an atomic function, or
a value held for later statements, three.js's `toConst`. Each statement's
index and value are roots of the graph, which `NodeGraph.compile_roots`
lays out as `compile` lays out outputs. An invocation runs its statements
in order. A statement built inside an `If` is kept where its branch runs:
its index becomes -1 elsewhere, and an index outside the buffer writes
nothing.

**Steps and barriers.** A barrier ends a step. Every invocation runs a step
before any runs the next, so a barrier makes what every invocation stored
visible to all, not only to its workgroup. In a step, a storage read sees
the buffer as the step began, and the invocation's own stores of the step
before it: a later read of an element the invocation stored is a `select`
of the stored value. So a read never sees another invocation's store of the
same step, and both backends agree. A value held with `to_const`, and an
atomic's old value, are kept for each invocation across steps.

**Atomics.** An atomic function changes a `float` buffer's element at once,
and returns what it held. The host runs the invocations in order. The
device runs them at once, so the old values an atomic returns can come in
another order, as on any GPU; the sums they leave agree.

**Workgroups and subgroups.** A dispatch runs `count` invocations in
workgroups of `workgroup_size`, one after another along x. A workgroup
array has one copy for each workgroup, zeros at the start of a dispatch.
A subgroup is one invocation: `subgroupSize` is one, and each subgroup
function returns what one invocation gives it.

**Numbers.** Every value is a float, as in the rest of the bytecode. A
`uint` element holds a whole number, exact up to 2 ** 24, and an index is
the number truncated.

**The GPU.** `render.gpu.GpuCompute` runs a `ComputeNode` on the device,
one launch a step. Both backends call `run_statements` on a
`ComputeSource`, so the two agree to the float.
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
from materials.nodes import (
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC3,
    NODE_VEC4,
    NodeContext,
    NodeGraph,
    NodeInputs,
    NodeProgram,
    NodeRef,
    NodeSource,
    ValueType,
    run_code,
)
from math.vector3 import Vector3
from postprocessing.sampling import Untracked
from render.framebuffer import FloatColor
from render.texture import NEAREST, Texture, float_texture
from std.memory import bitcast

comptime Lanes = SIMD[DType.float32, 4]
# A pointer the kernel and the host write through, which the compiler does
# not track: whoever builds one keeps the floats alive.
comptime MutUntracked = UntrackedOrigin[mut=True]

# How a statement is laid out after a program's instructions: what it does,
# the buffer or array it names, where its index root and its value root
# start and how many instructions each holds, where it keeps what it
# leaves, and its step.
comptime STATEMENT_OP = 0
comptime STATEMENT_SLOT = 1
comptime STATEMENT_INDEX = 2
comptime STATEMENT_INDEX_COUNT = 3
comptime STATEMENT_VALUE = 4
comptime STATEMENT_VALUE_COUNT = 5
comptime STATEMENT_RESULT = 6
comptime STATEMENT_STAGE = 7
comptime STATEMENT_FLOATS = 8
# What a statement does, besides the nine atomic functions, which are their
# `AtomicOp` values: a store of a value, and a value held for later.
comptime STATEMENT_STORE = 9
comptime STATEMENT_HOLD = 10
# How a buffer or an array is laid out in a run's memory: where its first
# float is, how many elements it has (a workgroup's copy, for an array),
# and how many floats an element has.
comptime REGION_START = 0
comptime REGION_COUNT = 1
comptime REGION_SIZE = 2
comptime REGION_INTS = 3
# The most invocations a workgroup can have, as a GPU launch allows.
comptime MAX_WORKGROUP_SIZE = 1024


def _width(type: ValueType) raises -> Int:
    """Return how many floats an element of a type has.

    Raises:
        Error: If the type is not a `float` or a vector.
    """
    if not type.is_vector():
        raise Error(
            "A storage element is a float or a vector, not a " + type.name()
        )
    return type.value


struct StorageBuffer(Copyable, Movable):
    """A buffer of elements a compute program reads and writes, three.js's
    `StorageBufferAttribute`: `count` elements of one type, one to four
    floats each, one after another in `array`."""

    var type: ValueType
    var count: Int
    var array: List[Float32]

    def __init__(out self, count: Int, type: ValueType) raises:
        """Create a buffer of zeros, three.js's `new
        StorageBufferAttribute( count, itemSize )`.

        Args:
            count: How many elements, one or more.
            type: What an element is: a `float` or a vector.

        Raises:
            Error: If `count` is not positive or `type` is not a `float` or
                a vector.
        """
        if count <= 0:
            raise Error("A storage buffer needs one element or more")
        self.type = type
        self.count = count
        self.array = List[Float32](length=count * _width(type), fill=0)

    def __init__(out self, var array: List[Float32], type: ValueType) raises:
        """Hold floats as a buffer, three.js's `new StorageBufferAttribute(
        array, itemSize )`.

        Args:
            array: The elements' floats, one element after another.
            type: What an element is: a `float` or a vector.

        Raises:
            Error: If `type` is not a `float` or a vector, or the floats
                are not a whole number of elements, one or more.
        """
        var width = _width(type)
        if len(array) == 0 or len(array) % width != 0:
            raise Error(
                "A storage buffer holds a whole number of "
                + type.name()
                + " elements"
            )
        self.type = type
        self.count = len(array) // width
        self.array = array^


@fieldwise_init
struct StorageBufferNode(Equatable, ImplicitlyCopyable, Writable):
    """A storage buffer as a compute program names it, three.js's
    `StorageBufferNode`: the buffer, its elements' type and their count."""

    var buffer: StorageBufferId
    var type: ValueType
    var count: Int


@fieldwise_init
struct StorageTexture(ImplicitlyCopyable, Writable):
    """A texture a compute program writes texel by texel, three.js's
    `StorageTexture`: a buffer of `vec4` texels, row by row from the top,
    `width` by `height`."""

    var texels: StorageBufferNode
    var width: Int
    var height: Int


@fieldwise_init
struct WorkgroupArrayNode(Equatable, ImplicitlyCopyable, Writable):
    """An array each workgroup holds its own copy of, three.js's
    `workgroupArray( type, count )`: the array, its elements' type and
    their count."""

    var array: WorkgroupArrayId
    var type: ValueType
    var count: Int


struct StorageBufferStore(Movable):
    """Owns the storage buffers every compute program reads, and hands out
    the nodes that name them."""

    var buffers: List[StorageBuffer]

    def __init__(out self):
        """Create an empty store."""
        self.buffers = List[StorageBuffer]()

    def count(self) -> Int:
        """Return how many buffers the store holds.

        Returns:
            The count.
        """
        return len(self.buffers)

    def storage(mut self, var buffer: StorageBuffer) -> StorageBufferNode:
        """Take a buffer and return the node that names it, three.js's
        `storage( attribute, type, count )`.

        Args:
            buffer: The buffer.

        Returns:
            The node.
        """
        var node = StorageBufferNode(
            StorageBufferId(len(self.buffers)), buffer.type, buffer.count
        )
        self.buffers.append(buffer^)
        return node

    def instanced_array(
        mut self, count: Int, type: ValueType
    ) raises -> StorageBufferNode:
        """Add a buffer of zeros, three.js's `instancedArray( count, type
        )`.

        Args:
            count: How many elements, one or more.
            type: What an element is: a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `count` is not positive or `type` is not a `float` or
                a vector.
        """
        return self.storage(StorageBuffer(count, type))

    def instanced_array(
        mut self, var array: List[Float32], type: ValueType
    ) raises -> StorageBufferNode:
        """Add a buffer of floats, three.js's `instancedArray( array, type
        )`.

        Args:
            array: The elements' floats, one element after another.
            type: What an element is: a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `type` is not a `float` or a vector, or the floats are
                not a whole number of elements, one or more.
        """
        return self.storage(StorageBuffer(array^, type))

    def storage_texture(
        mut self, width: Int, height: Int
    ) raises -> StorageTexture:
        """Add a texture of transparent black texels that a compute program
        writes, three.js's `new StorageTexture( width, height )`.

        Args:
            width: How many texels across, one or more.
            height: How many texels down, one or more.

        Returns:
            The texture.

        Raises:
            Error: If a size is not positive.
        """
        if width <= 0 or height <= 0:
            raise Error("A storage texture needs a size")
        var texels = self.instanced_array(width * height, NODE_VEC4)
        return StorageTexture(texels, width, height)

    def _check(self, node: StorageBufferNode) raises:
        """Refuse a node that names no buffer of this store, or names one as
        another type."""
        var id = node.buffer.value
        if id < 0 or id >= len(self.buffers):
            raise Error("A storage buffer store has no buffer " + String(id))
        if self.buffers[id].type != node.type:
            raise Error(
                "A storage buffer of "
                + self.buffers[id].type.name()
                + " elements is named as one of "
                + node.type.name()
            )

    def array(self, node: StorageBufferNode) raises -> List[Float32]:
        """Return a copy of a buffer's floats, three.js's `attribute.array`
        after a compute program ran.

        Args:
            node: The buffer.

        Returns:
            Its floats, one element after another.

        Raises:
            Error: If the store has no such buffer of that type.
        """
        self._check(node)
        return self.buffers[node.buffer.value].array.copy()

    def set_array(
        mut self, node: StorageBufferNode, var array: List[Float32]
    ) raises:
        """Replace a buffer's floats, three.js's `attribute.array.set` and
        `needsUpdate`.

        Args:
            node: The buffer.
            array: The new floats, as many as it holds.

        Raises:
            Error: If the store has no such buffer of that type, or the
                count of floats differs.
        """
        self._check(node)
        if len(array) != len(self.buffers[node.buffer.value].array):
            raise Error("A storage buffer keeps its size")
        self.buffers[node.buffer.value].array = array^

    def texture(self, texture: StorageTexture) raises -> Texture:
        """Return a storage texture as a float texture for a material to
        read at its nearest texel, as three.js samples a `StorageTexture`.

        Args:
            texture: The storage texture.

        Returns:
            The texture, rows from the top.

        Raises:
            Error: If the store has no such buffer, or it is not the
                texture's size.
        """
        var texels = self.array(texture.texels)
        if len(texels) != texture.width * texture.height * 4:
            raise Error("A storage texture's buffer is not its size")
        return float_texture(
            texture.width, texture.height, texels^, filter=NEAREST
        )


@fieldwise_init
struct _Statement(Copyable, Movable):
    """One statement of a kernel: what it does, the slot it names, its
    index and value nodes (-1 for none), its step, and the type it
    leaves."""

    var op: Int
    var slot: Int
    var index: Int
    var value: Int
    var stage: Int
    var leaves: ValueType


def _zero_of(mut graph: NodeGraph, type: ValueType, x: Float32) -> NodeRef:
    """Return a constant of a type with every component `x`."""
    if type == NODE_VEC2:
        return graph.vec2(x, x)
    if type == NODE_VEC3:
        return graph.vec3(x, x, x)
    if type == NODE_VEC4:
        return graph.vec4(x, x, x, x)
    return graph.float(x)


struct ComputeKernel(Movable):
    """A compute program being built, three.js's `Fn( () => { ... } )`
    before `.compute( count )`: a `NodeGraph` for the values and the
    statements built on it.

    Build values on `graph` and read the invocation, the buffers and the
    statements' results through the kernel. Open branches with
    `graph.If`; a statement made in one is kept where the branch runs. A
    statement cannot be made inside a `graph.Loop`: repeat it with a Mojo
    loop instead, as the loop's count is fixed.
    """

    var graph: NodeGraph
    var _statements: List[_Statement]
    var _stage: Int
    var _array_types: List[ValueType]
    var _array_counts: List[Int]
    # Every buffer the kernel names, once.
    var _buffers: List[StorageBufferNode]

    def __init__(out self):
        """Create a kernel with no statements."""
        self.graph = NodeGraph()
        self._statements = List[_Statement]()
        self._stage = 0
        self._array_types = List[ValueType]()
        self._array_counts = List[Int]()
        self._buffers = List[StorageBufferNode]()

    def statement_count(self) -> Int:
        """Return how many statements the kernel holds.

        Returns:
            The count.
        """
        return len(self._statements)

    # --- the invocation's numbers ------------------------------------------

    def builtin(mut self, which: ComputeBuiltin) raises -> NodeRef:
        """Return one of the invocation's numbers, a `float`.

        Args:
            which: The number, such as `INSTANCE_INDEX`.

        Returns:
            The node.

        Raises:
            Error: If `which` is not one of the numbers.
        """
        return self.graph.compute_builtin(which)

    def instance_index(mut self) raises -> NodeRef:
        """Return the invocation's place among all of them, three.js's
        `instanceIndex`.

        Returns:
            The node, a `float`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self.builtin(INSTANCE_INDEX)

    def invocation_local_index(mut self) raises -> NodeRef:
        """Return the invocation's place in its workgroup, three.js's
        `invocationLocalIndex`.

        Returns:
            The node, a `float`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self.builtin(INVOCATION_LOCAL_INDEX)

    def subgroup_size(mut self) raises -> NodeRef:
        """Return how many invocations a subgroup has, three.js's
        `subgroupSize`: one.

        Returns:
            The node, a `float`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self.builtin(SUBGROUP_SIZE)

    def subgroup_index(mut self) raises -> NodeRef:
        """Return the subgroup's place in its workgroup, three.js's
        `subgroupIndex`: the invocation's own, as a subgroup is one.

        Returns:
            The node, a `float`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self.builtin(SUBGROUP_INDEX)

    def invocation_subgroup_index(mut self) raises -> NodeRef:
        """Return the invocation's place in its subgroup, three.js's
        `invocationSubgroupIndex`: zero.

        Returns:
            The node, a `float`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self.builtin(INVOCATION_SUBGROUP_INDEX)

    def _along_x(
        mut self, which: ComputeBuiltin, rest: Float32
    ) raises -> NodeRef:
        """Return a builtin as a `vec3`, with the other two axes `rest`."""
        var x = self.builtin(which)
        var others = self.graph.float(rest)
        return self.graph.join([x, others, others])

    def global_id(mut self) raises -> NodeRef:
        """Return three.js's `globalId`: the instance index across, and
        zero on the other two axes of a dispatch along x.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self._along_x(INSTANCE_INDEX, 0)

    def local_id(mut self) raises -> NodeRef:
        """Return three.js's `localId`, the place in the workgroup.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self._along_x(INVOCATION_LOCAL_INDEX, 0)

    def workgroup_id(mut self) raises -> NodeRef:
        """Return three.js's `workgroupId`, the workgroup's place.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self._along_x(WORKGROUP_ID, 0)

    def num_workgroups(mut self) raises -> NodeRef:
        """Return three.js's `numWorkgroups`: how many workgroups across,
        and one on the other two axes.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: Never; the graph's builders raise for other callers.
        """
        return self._along_x(NUM_WORKGROUPS, 1)

    # --- storage -----------------------------------------------------------

    def workgroup_array(
        mut self, type: ValueType, count: Int
    ) raises -> WorkgroupArrayNode:
        """Add an array each workgroup holds its own copy of, three.js's
        `workgroupArray( type, count )`.

        Args:
            type: What an element is: a `float` or a vector.
            count: How many elements, one or more.

        Returns:
            The array.

        Raises:
            Error: If `count` is not positive or `type` is not a `float` or
                a vector.
        """
        _ = _width(type)
        if count <= 0:
            raise Error("A workgroup array needs one element or more")
        self._array_types.append(type)
        self._array_counts.append(count)
        return WorkgroupArrayNode(
            WorkgroupArrayId(len(self._array_types) - 1), type, count
        )

    def _note(mut self, buffer: StorageBufferNode) raises:
        """Keep a buffer the kernel names, once.

        Raises:
            Error: If the node names a buffer there cannot be, or names a
                buffer the kernel names as another type.
        """
        if not buffer.buffer.is_valid():
            raise Error("A storage node names no buffer there can be")
        _ = _width(buffer.type)
        for index in range(len(self._buffers)):
            if self._buffers[index].buffer == buffer.buffer:
                if self._buffers[index] != buffer:
                    raise Error(
                        "A kernel names one storage buffer as two types"
                    )
                return
        self._buffers.append(buffer)

    def _check_array(self, array: WorkgroupArrayNode) raises:
        """Refuse an array this kernel did not make."""
        var id = array.array.value
        if (
            id < 0
            or id >= len(self._array_types)
            or self._array_types[id] != array.type
            or self._array_counts[id] != array.count
        ):
            raise Error("A kernel has no such workgroup array")

    def _forwarded(
        mut self, slot: Int, index: NodeRef, loaded: NodeRef
    ) raises -> NodeRef:
        """Return a read with the stores of this step to the same slot laid
        over it, the latest last: what the invocation reads of its own
        stores."""
        var value = loaded
        for at in range(len(self._statements)):
            ref statement = self._statements[at]
            if (
                statement.stage != self._stage
                or statement.op != STATEMENT_STORE
                or statement.slot != slot
            ):
                continue
            var same = self.graph.equal(index, NodeRef(statement.index))
            value = self.graph.select(same, NodeRef(statement.value), value)
        return value

    def element(
        mut self, buffer: StorageBufferNode, index: NodeRef
    ) raises -> NodeRef:
        """Return a storage buffer's element, three.js's
        `buffer.element( index )`: as the step began, or as this invocation
        last stored it in the step.

        Args:
            buffer: The buffer.
            index: The element's place, a `float`.

        Returns:
            The node, of the buffer's type. It reads zeros past either end.

        Raises:
            Error: If the buffer cannot be, or `index` is not a `float` of
                the graph.
        """
        self._note(buffer)
        var loaded = self.graph.storage_element(
            buffer.buffer, index, buffer.type
        )
        return self._forwarded(buffer.buffer.value, index, loaded)

    def element(
        mut self, array: WorkgroupArrayNode, index: NodeRef
    ) raises -> NodeRef:
        """Return a workgroup array's element in the invocation's
        workgroup, three.js's `array.element( index )`.

        Args:
            array: The array.
            index: The element's place, a `float`.

        Returns:
            The node, of the array's type. It reads zeros past either end.

        Raises:
            Error: If the kernel did not make the array, or `index` is not
                a `float` of the graph.
        """
        self._check_array(array)
        var loaded = self.graph.storage_element(array.array, index, array.type)
        return self._forwarded(-1 - array.array.value, index, loaded)

    def _statement(
        mut self,
        op: Int,
        slot: Int,
        index: NodeRef,
        value: NodeRef,
        leaves: ValueType,
    ) raises -> ComputeStatementId:
        """Add a statement where the builder is: its index kept where the
        code runs, and -1 elsewhere.

        Raises:
            Error: If a `graph.Loop` is open, or a node is not the graph's.
        """
        if self.graph.in_loop():
            raise Error(
                "A compute statement cannot be made in a Loop: repeat it"
                " with a Mojo loop"
            )
        var kept = index
        if index.value >= 0:
            kept = self.graph.select(
                self.graph.running(), index, self.graph.float(-1)
            )
        self._statements.append(
            _Statement(op, slot, kept.value, value.value, self._stage, leaves)
        )
        return ComputeStatementId(len(self._statements) - 1)

    def _stored(
        mut self, slot: Int, type: ValueType, index: NodeRef, value: NodeRef
    ) raises:
        """Add a store of a value, made the slot's type, at an index.

        Raises:
            Error: If `index` is not a `float`, or `value` cannot be the
                slot's type.
        """
        if self.graph.type_of(index) != NODE_FLOAT:
            raise Error(
                "A storage element is written at a float index, not a "
                + self.graph.type_of(index).name()
            )
        var given = self.graph.type_of(value)
        var made = value
        if given != type:
            if given != NODE_FLOAT:
                raise Error(
                    "A storage element of "
                    + type.name()
                    + " cannot hold a "
                    + given.name()
                )
            # A vector, as the float is not the slot's type.
            made = self.graph.join(List[NodeRef](length=type.value, fill=value))
        _ = self._statement(STATEMENT_STORE, slot, index, made, type)

    def assign(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises:
        """Store a value in a storage buffer's element, three.js's
        `buffer.element( index ).assign( value )`.

        Args:
            buffer: The buffer.
            index: The element's place, a `float`.
            value: The value, of the buffer's type or a `float` repeated
                into each component.

        Raises:
            Error: If the buffer cannot be, a node is not the graph's, the
                types differ, or a `graph.Loop` is open.
        """
        self._note(buffer)
        self._stored(buffer.buffer.value, buffer.type, index, value)

    def assign(
        mut self, array: WorkgroupArrayNode, index: NodeRef, value: NodeRef
    ) raises:
        """Store a value in the invocation's workgroup's copy of an array.

        Args:
            array: The array.
            index: The element's place, a `float`.
            value: The value, of the array's type or a `float`.

        Raises:
            Error: If the kernel did not make the array, a node is not the
                graph's, the types differ, or a `graph.Loop` is open.
        """
        self._check_array(array)
        self._stored(-1 - array.array.value, array.type, index, value)

    def add_assign(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises:
        """Add a value to a storage buffer's element, three.js's
        `buffer.element( index ).addAssign( value )`.

        Args:
            buffer: The buffer.
            index: The element's place, a `float`.
            value: What to add, of the buffer's type or a `float`.

        Raises:
            Error: If the buffer cannot be, a node is not the graph's, the
                types differ, or a `graph.Loop` is open.
        """
        var sum = self.graph.add(self.element(buffer, index), value)
        self.assign(buffer, index, sum)

    def _texel(
        mut self, texture: StorageTexture, coord: NodeRef
    ) raises -> NodeRef:
        """Return where a texel is in its texture's buffer, or -1 for a
        coordinate off the texture.

        Raises:
            Error: If `coord` is not a `vec2` of the graph.
        """
        if self.graph.type_of(coord) != NODE_VEC2:
            raise Error(
                "A storage texture is read at a vec2, not a "
                + self.graph.type_of(coord).name()
            )
        ref g = self.graph
        var at = g.floor(coord)
        var x = g.swizzle(at, "x")
        var y = g.swizzle(at, "y")
        var inside = g.logical_and(
            g.logical_and(
                g.greater_than_equal(x, g.float(0)),
                g.less_than(x, g.float(Float32(texture.width))),
            ),
            g.logical_and(
                g.greater_than_equal(y, g.float(0)),
                g.less_than(y, g.float(Float32(texture.height))),
            ),
        )
        var place = g.add(g.mul(y, g.float(Float32(texture.width))), x)
        return g.select(inside, place, g.float(-1))

    def texture_store(
        mut self, texture: StorageTexture, coord: NodeRef, value: NodeRef
    ) raises:
        """Write a texel of a storage texture, three.js's `textureStore(
        texture, uv, value )`. A coordinate off the texture writes nothing.

        Args:
            texture: The texture.
            coord: The texel's column and row from the top, a `vec2`.
            value: The texel, a `vec4`.

        Raises:
            Error: If `coord` is not a `vec2` or `value` not a `vec4` of the
                graph, or a `graph.Loop` is open.
        """
        self.assign(texture.texels, self._texel(texture, coord), value)

    def texture_load(
        mut self, texture: StorageTexture, coord: NodeRef
    ) raises -> NodeRef:
        """Read a texel of a storage texture, three.js's `textureLoad` of
        one: zeros off the texture.

        Args:
            texture: The texture.
            coord: The texel's column and row from the top, a `vec2`.

        Returns:
            The node, a `vec4`.

        Raises:
            Error: If `coord` is not a `vec2` of the graph.
        """
        return self.element(texture.texels, self._texel(texture, coord))

    # --- atomics -----------------------------------------------------------

    def atomic_func(
        mut self,
        op: AtomicOp,
        buffer: StorageBufferNode,
        index: NodeRef,
        value: NodeRef,
    ) raises -> NodeRef:
        """Run an atomic function on a `float` buffer's element, three.js's
        `atomicFunc( method, pointer, value )`.

        Args:
            op: The function, such as `ATOMIC_ADD`.
            buffer: The buffer. Its elements must be `float`s.
            index: The element's place, a `float`.
            value: The function's operand, a `float`. `ATOMIC_LOAD` does
                not read it.

        Returns:
            What the element held before, a `float`: zeros for an index
            off the buffer.

        Raises:
            Error: If `op` is not a function, the buffer is not of
                `float`s, a node is not a `float` of the graph, or a
                `graph.Loop` is open.
        """
        if not op.is_valid():
            raise Error("An atomic function names no function there is")
        self._note(buffer)
        if buffer.type != NODE_FLOAT:
            raise Error("An atomic function reads a buffer of floats")
        if (
            self.graph.type_of(index) != NODE_FLOAT
            or self.graph.type_of(value) != NODE_FLOAT
        ):
            raise Error("An atomic function takes a float index and value")
        var statement = self._statement(
            op.value, buffer.buffer.value, index, value, NODE_FLOAT
        )
        return self.graph.compute_result(statement, NODE_FLOAT)

    def atomic_load(
        mut self, buffer: StorageBufferNode, index: NodeRef
    ) raises -> NodeRef:
        """Return an element as it is now, three.js's `atomicLoad`.

        Args:
            buffer: The buffer, of `float`s.
            index: The element's place, a `float`.

        Returns:
            The node.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_LOAD, buffer, index, self.graph.float(0))

    def atomic_store(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises:
        """Replace an element at once, three.js's `atomicStore`.

        Args:
            buffer: The buffer, of `float`s.
            index: The element's place, a `float`.
            value: The new value, a `float`.

        Raises:
            Error: As `atomic_func` does.
        """
        _ = self.atomic_func(ATOMIC_STORE, buffer, index, value)

    def atomic_add(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Add to an element at once, three.js's `atomicAdd`.

        Args:
            buffer: The buffer, of `float`s.
            index: The element's place, a `float`.
            value: What to add, a `float`.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_ADD, buffer, index, value)

    def atomic_sub(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Subtract from an element at once, three.js's `atomicSub`.

        Args:
            buffer: The buffer, of `float`s.
            index: The element's place, a `float`.
            value: What to subtract, a `float`.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_SUB, buffer, index, value)

    def atomic_max(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Keep the larger of an element and a value, three.js's
        `atomicMax`.

        Args:
            buffer: The buffer, of `float`s.
            index: The element's place, a `float`.
            value: The value, a `float`.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_MAX, buffer, index, value)

    def atomic_min(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Keep the smaller of an element and a value, three.js's
        `atomicMin`.

        Args:
            buffer: The buffer, of `float`s.
            index: The element's place, a `float`.
            value: The value, a `float`.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_MIN, buffer, index, value)

    def atomic_and(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Keep the bits an element and a value share, three.js's
        `atomicAnd`.

        Args:
            buffer: The buffer, of `float`s holding whole numbers.
            index: The element's place, a `float`.
            value: The value, a whole number.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_AND, buffer, index, value)

    def atomic_or(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Set the bits of a value in an element, three.js's `atomicOr`.

        Args:
            buffer: The buffer, of `float`s holding whole numbers.
            index: The element's place, a `float`.
            value: The value, a whole number.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_OR, buffer, index, value)

    def atomic_xor(
        mut self, buffer: StorageBufferNode, index: NodeRef, value: NodeRef
    ) raises -> NodeRef:
        """Flip the bits of a value in an element, three.js's `atomicXor`.

        Args:
            buffer: The buffer, of `float`s holding whole numbers.
            index: The element's place, a `float`.
            value: The value, a whole number.

        Returns:
            What the element held before.

        Raises:
            Error: As `atomic_func` does.
        """
        return self.atomic_func(ATOMIC_XOR, buffer, index, value)

    # --- held values and barriers -------------------------------------------

    def to_const(mut self, value: NodeRef) raises -> NodeRef:
        """Compute a value once, where the builder is, and read it after,
        three.js's `toConst`. Later statements read what it held then,
        across a barrier too, and do not compute it again.

        Args:
            value: The value, a `float` or a vector.

        Returns:
            The node that reads it.

        Raises:
            Error: If `value` is not a `float` or a vector of the graph, or
                a `graph.Loop` is open.
        """
        var type = self.graph.type_of(value)
        _ = _width(type)
        var statement = self._statement(
            STATEMENT_HOLD, 0, NodeRef(-1), value, type
        )
        return self.graph.compute_result(statement, type)

    def workgroup_barrier(mut self):
        """End the step, three.js's `workgroupBarrier`: every invocation
        runs what came before it before any runs what comes after."""
        self._stage += 1

    def storage_barrier(mut self):
        """End the step, three.js's `storageBarrier`; see
        `workgroup_barrier`."""
        self._stage += 1

    def texture_barrier(mut self):
        """End the step, three.js's `textureBarrier`; see
        `workgroup_barrier`."""
        self._stage += 1

    # --- subgroup functions -------------------------------------------------
    # A subgroup is one invocation, so each function gives what that one
    # invocation's value makes on its own.

    def _vector(self, x: NodeRef) raises -> ValueType:
        """Return a node's type, refusing one that is not a `float` or a
        vector."""
        var type = self.graph.type_of(x)
        _ = _width(type)
        return type

    def subgroup_add(mut self, x: NodeRef) raises -> NodeRef:
        """Return the sum over the subgroup, three.js's `subgroupAdd`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_inclusive_add(mut self, x: NodeRef) raises -> NodeRef:
        """Return the sum up to and with this invocation, three.js's
        `subgroupInclusiveAdd`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_exclusive_add(mut self, x: NodeRef) raises -> NodeRef:
        """Return the sum before this invocation, three.js's
        `subgroupExclusiveAdd`: zero.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node, of the type of `x`.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        var type = self._vector(x)
        return _zero_of(self.graph, type, 0)

    def subgroup_mul(mut self, x: NodeRef) raises -> NodeRef:
        """Return the product over the subgroup, three.js's `subgroupMul`:
        `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_inclusive_mul(mut self, x: NodeRef) raises -> NodeRef:
        """Return the product up to and with this invocation, three.js's
        `subgroupInclusiveMul`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_exclusive_mul(mut self, x: NodeRef) raises -> NodeRef:
        """Return the product before this invocation, three.js's
        `subgroupExclusiveMul`: one.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node, of the type of `x`.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        var type = self._vector(x)
        return _zero_of(self.graph, type, 1)

    def subgroup_and(mut self, x: NodeRef) raises -> NodeRef:
        """Return the bits every invocation's value has, three.js's
        `subgroupAnd`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_or(mut self, x: NodeRef) raises -> NodeRef:
        """Return the bits any invocation's value has, three.js's
        `subgroupOr`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_xor(mut self, x: NodeRef) raises -> NodeRef:
        """Return the bits an odd count of values have, three.js's
        `subgroupXor`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_min(mut self, x: NodeRef) raises -> NodeRef:
        """Return the smallest value, three.js's `subgroupMin`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_max(mut self, x: NodeRef) raises -> NodeRef:
        """Return the largest value, three.js's `subgroupMax`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_all(mut self, x: NodeRef) raises -> NodeRef:
        """Return one where every invocation's condition holds, three.js's
        `subgroupAll`: the condition.

        Args:
            x: The condition, a `float`.

        Returns:
            The node, one or zero.

        Raises:
            Error: If `x` is not a `float` of the graph.
        """
        return self.graph.not_equal(x, self.graph.float(0))

    def subgroup_any(mut self, x: NodeRef) raises -> NodeRef:
        """Return one where any invocation's condition holds, three.js's
        `subgroupAny`: the condition.

        Args:
            x: The condition, a `float`.

        Returns:
            The node, one or zero.

        Raises:
            Error: If `x` is not a `float` of the graph.
        """
        return self.graph.not_equal(x, self.graph.float(0))

    def subgroup_elect(mut self) -> NodeRef:
        """Return one for the subgroup's first active invocation, three.js's
        `subgroupElect`: one, as each invocation is its subgroup's first.

        Returns:
            The node.
        """
        return self.graph.float(1)

    def subgroup_ballot(mut self, x: NodeRef) raises -> NodeRef:
        """Return a bit for each invocation whose condition holds, three.js's
        `subgroupBallot`: the first bit of the first component.

        Args:
            x: The condition, a `float`.

        Returns:
            The node, a `vec4`.

        Raises:
            Error: If `x` is not a `float` of the graph.
        """
        var bit = self.graph.not_equal(x, self.graph.float(0))
        var zero = self.graph.float(0)
        return self.graph.join([bit, zero, zero, zero])

    def subgroup_broadcast(mut self, x: NodeRef, id: NodeRef) raises -> NodeRef:
        """Return one invocation's value to the subgroup, three.js's
        `subgroupBroadcast`: `x`, the only invocation's.

        Args:
            x: The invocation's value, a `float` or a vector.
            id: Which invocation's, a `float`.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        _ = self._vector(id)
        return x

    def subgroup_broadcast_first(mut self, x: NodeRef) raises -> NodeRef:
        """Return the first invocation's value, three.js's
        `subgroupBroadcastFirst`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        return x

    def subgroup_shuffle(mut self, x: NodeRef, id: NodeRef) raises -> NodeRef:
        """Return another invocation's value, three.js's
        `subgroupShuffle`: `x`, the only invocation's.

        Args:
            x: The invocation's value, a `float` or a vector.
            id: Which invocation's, a `float`.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        _ = self._vector(id)
        return x

    def subgroup_shuffle_xor(
        mut self, x: NodeRef, mask: NodeRef
    ) raises -> NodeRef:
        """Return the value of the invocation whose place differs by a
        mask, three.js's `subgroupShuffleXor`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.
            mask: The mask, a `float`.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        _ = self._vector(mask)
        return x

    def subgroup_shuffle_up(
        mut self, x: NodeRef, delta: NodeRef
    ) raises -> NodeRef:
        """Return the value of the invocation `delta` places before,
        three.js's `subgroupShuffleUp`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.
            delta: How many places, a `float`.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        _ = self._vector(delta)
        return x

    def subgroup_shuffle_down(
        mut self, x: NodeRef, delta: NodeRef
    ) raises -> NodeRef:
        """Return the value of the invocation `delta` places after,
        three.js's `subgroupShuffleDown`: `x`.

        Args:
            x: The invocation's value, a `float` or a vector.
            delta: How many places, a `float`.

        Returns:
            The node.

        Raises:
            Error: If `x` is not a `float` or a vector of the graph.
        """
        _ = self._vector(x)
        _ = self._vector(delta)
        return x

    # --- compiling ----------------------------------------------------------

    def compute(
        self, count: Int, workgroup_size: Int = 64
    ) raises -> ComputeNode:
        """Compile the statements, three.js's `.compute( count, [
        workgroupSize ] )`.

        Args:
            count: How many invocations run, one or more.
            workgroup_size: How many invocations a workgroup has, one to
                `MAX_WORKGROUP_SIZE`; 64 as in three.js.

        Returns:
            The node to run.

        Raises:
            Error: If a count is out of range, the kernel has no statement,
                or the graph is refused (see `NodeGraph.compile_roots`).
        """
        if count <= 0:
            raise Error("A compute node runs one invocation or more")
        if workgroup_size <= 0 or workgroup_size > MAX_WORKGROUP_SIZE:
            raise Error(
                "A workgroup has one to "
                + String(MAX_WORKGROUP_SIZE)
                + " invocations"
            )
        if len(self._statements) == 0:
            raise Error("A compute kernel needs a statement")
        var roots = List[NodeRef]()
        for at in range(len(self._statements)):  # pragma: no branch
            ref statement = self._statements[at]
            if statement.index >= 0:
                roots.append(NodeRef(statement.index))
            # Every statement has a value.
            roots.append(NodeRef(statement.value))
        var starts = List[Int]()
        var program = self.graph.compile_roots(roots, starts)
        var table_at = len(program.code)
        var root = 0
        var results = 0
        var stage_starts = List[Int]()
        for at in range(len(self._statements)):  # pragma: no branch
            ref statement = self._statements[at]
            if at == 0 or statement.stage != self._statements[at - 1].stage:
                stage_starts.append(at)
            program.code.append(Float32(statement.op))
            program.code.append(Float32(statement.slot))
            for part in range(2):  # pragma: no branch
                var node = statement.index if part == 0 else statement.value
                if node >= 0:
                    program.code.append(Float32(starts[root * 2]))
                    program.code.append(Float32(starts[root * 2 + 1]))
                    root += 1
                else:
                    program.code.append(0)
                    program.code.append(0)
            var leaves = statement.op != STATEMENT_STORE
            program.code.append(Float32(results if leaves else -1))
            if leaves:
                results += 1
            program.code.append(Float32(statement.stage))
        stage_starts.append(len(self._statements))
        return ComputeNode(
            program^,
            count,
            workgroup_size,
            table_at,
            results,
            stage_starts^,
            self._buffers.copy(),
            self._array_types.copy(),
            self._array_counts.copy(),
        )


struct ComputeNode(Copyable, Movable):
    """A compiled compute program, three.js's `ComputeNode`: the bytecode,
    how many invocations run it in workgroups of what size, and what a run
    lays out.

    `program.code` holds the instructions and the pool, then a table of
    `STATEMENT_FLOATS` floats a statement from `table_at`. Set its
    uniforms with `program.set_uniform`, and its time with
    `program.set_frame`.
    """

    var name: String
    var program: NodeProgram
    var count: Int
    var workgroup_size: Int
    var table_at: Int
    # How many values each invocation keeps: one for each held value and
    # each atomic function.
    var results: Int
    # The first statement of each step, then the count of statements.
    var stage_starts: List[Int]
    var buffers: List[StorageBufferNode]
    var array_types: List[ValueType]
    var array_counts: List[Int]

    def __init__(
        out self,
        var program: NodeProgram,
        count: Int,
        workgroup_size: Int,
        table_at: Int,
        results: Int,
        var stage_starts: List[Int],
        var buffers: List[StorageBufferNode],
        var array_types: List[ValueType],
        var array_counts: List[Int],
    ):
        """Hold a compiled program; `ComputeKernel.compute` makes one.

        Args:
            program: The bytecode and its statement table.
            count: How many invocations run.
            workgroup_size: How many invocations a workgroup has.
            table_at: Where the statement table starts in the code.
            results: How many values each invocation keeps.
            stage_starts: Each step's first statement, then the count.
            buffers: The buffers the program names.
            array_types: Each workgroup array's element type.
            array_counts: Each workgroup array's element count.
        """
        self.name = ""
        self.program = program^
        self.count = count
        self.workgroup_size = workgroup_size
        self.table_at = table_at
        self.results = results
        self.stage_starts = stage_starts^
        self.buffers = buffers^
        self.array_types = array_types^
        self.array_counts = array_counts^

    def set_name(mut self, name: String):
        """Name the node, three.js's `setName`, for a reader.

        Args:
            name: The name.
        """
        self.name = name

    def set_count(mut self, count: Int) raises:
        """Change how many invocations run, three.js's `computeNode.count`.

        Args:
            count: The count, one or more.

        Raises:
            Error: If `count` is not positive.
        """
        if count <= 0:
            raise Error("A compute node runs one invocation or more")
        self.count = count

    def workgroups(self) -> Int:
        """Return how many workgroups a run dispatches: enough to hold
        every invocation.

        Returns:
            The count divided by the workgroup size, rounded up.
        """
        return (self.count + self.workgroup_size - 1) // self.workgroup_size

    def stages(self) -> Int:
        """Return how many steps the barriers make.

        Returns:
            One more than the barriers between statements.
        """
        return len(self.stage_starts) - 1


struct ComputeSource(ImplicitlyCopyable, NodeSource):
    """The `NodeSource` of one invocation of a step: the program's floats,
    the memory as the step began, where each buffer and array is in it,
    and the invocation's kept values. Both backends build one.

    The memory holds every buffer of the store in turn, then each
    workgroup array, one copy a workgroup. `regions` has `REGION_INTS`
    numbers for each.
    """

    var code: Pointer[Float32, Untracked]
    var memory: Pointer[Float32, Untracked]
    var regions: Pointer[Int32, Untracked]
    # The invocation's kept values, four floats each.
    var kept: Pointer[Float32, MutUntracked]
    var buffers: Int
    var table_at: Int
    var index: Int
    var workgroup_size: Int
    var workgroups: Int

    def __init__(
        out self,
        code: Pointer[Float32, Untracked],
        memory: Pointer[Float32, Untracked],
        regions: Pointer[Int32, Untracked],
        kept: Pointer[Float32, MutUntracked],
        buffers: Int,
        table_at: Int,
        index: Int,
        workgroup_size: Int,
        workgroups: Int,
    ):
        """Point at a program, the memory and an invocation.

        Args:
            code: The program's floats.
            memory: Every buffer and array as the step began.
            regions: Where each is, `REGION_INTS` numbers each.
            kept: The invocation's kept values.
            buffers: How many of the regions are buffers; arrays follow.
            table_at: Where the statement table starts in the code.
            index: The invocation's place, three.js's `instanceIndex`.
            workgroup_size: How many invocations a workgroup has.
            workgroups: How many workgroups the dispatch has.
        """
        self.code = code
        self.memory = memory
        self.regions = regions
        self.kept = kept
        self.buffers = buffers
        self.table_at = table_at
        self.index = index
        self.workgroup_size = workgroup_size
        self.workgroups = workgroups

    def word(self, at: Int) -> Float32:
        """Return one float of the program.

        Args:
            at: Which float.

        Returns:
            The float.
        """
        return self.code[unsafe_offset=at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return opaque white: a compute program reads no texture.

        Args:
            slot: Not read.
            u: Not read.
            v: Not read.

        Returns:
            White.
        """
        return FloatColor(1.0, 1.0, 1.0, 1.0)

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return opaque white: a compute program reads no texture.

        Args:
            slot: Not read.
            u: Not read.
            v: Not read.
            level: Not read.

        Returns:
            White.
        """
        return FloatColor(1.0, 1.0, 1.0, 1.0)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return opaque white: a compute program reads no texture.

        Args:
            slot: Not read.
            x: Not read.
            y: Not read.
            level: Not read.

        Returns:
            White.
        """
        return FloatColor(1.0, 1.0, 1.0, 1.0)

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return ones: a compute program reads no texture.

        Args:
            slot: Not read.
            level: Not read.

        Returns:
            One by one.
        """
        return Lanes(1, 1, 0, 0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the first corner's whole weight: an invocation has no
        triangle.

        Args:
            context: Not read.

        Returns:
            One, zero and zero.
        """
        return Lanes(1, 0, 0, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return zeros and one: an invocation has no pixel.

        Args:
            context: Not read.

        Returns:
            The four numbers.
        """
        return Lanes(0, 0, 0, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return a corner of zeros: an invocation has no triangle.

        Args:
            context: Not read.

        Returns:
            The corner.
        """
        var none = Vector3(0, 0, 0)
        return NodeInputs(0, 0, none, none, none, none, False)

    def compute_builtin(self, which: Int) -> Float32:
        """Return one of the invocation's numbers.

        Args:
            which: The number, a `ComputeBuiltin`'s value.

        Returns:
            The number.
        """
        if which == INSTANCE_INDEX.value:
            return Float32(self.index)
        if (
            which == INVOCATION_LOCAL_INDEX.value
            or which == SUBGROUP_INDEX.value
        ):
            return Float32(self.index % self.workgroup_size)
        if which == WORKGROUP_ID.value:
            return Float32(self.index // self.workgroup_size)
        if which == NUM_WORKGROUPS.value:
            return Float32(self.workgroups)
        if which == SUBGROUP_SIZE.value:
            return 1
        # `INVOCATION_SUBGROUP_INDEX`, the one number left: a subgroup is
        # one invocation.
        return 0

    def region(self, slot: Int) -> Int:
        """Return which region a slot names: a buffer's id, or minus one
        less a workgroup array's.

        Args:
            slot: The slot.

        Returns:
            The region's place in `regions`.
        """
        return slot if slot >= 0 else self.buffers - 1 - slot

    def item_size(self, slot: Int) -> Int:
        """Return how many floats an element of a slot has.

        Args:
            slot: A buffer's id, or minus one less a workgroup array's.

        Returns:
            One to four.
        """
        return Int(
            self.regions[
                unsafe_offset=self.region(slot) * REGION_INTS + REGION_SIZE
            ]
        )

    def address(self, slot: Int, index: Float32) -> Int:
        """Return where an element's first float is in the memory, or -1
        for an index off the buffer or the array.

        Args:
            slot: A buffer's id, or minus one less a workgroup array's.
            index: The element's place, truncated to a whole number.

        Returns:
            The float's place, or -1.
        """
        var row = self.region(slot) * REGION_INTS
        var count = Int(self.regions[unsafe_offset=row + REGION_COUNT])
        # NaN is neither, and so is off the buffer.
        if not (index >= 0 and index < Float32(count)):
            return -1
        var element = Int(index)
        if slot < 0:
            element += (self.index // self.workgroup_size) * count
        return Int(
            self.regions[unsafe_offset=row + REGION_START]
        ) + element * Int(self.regions[unsafe_offset=row + REGION_SIZE])

    def storage_element(self, slot: Int, index: Float32) -> Lanes:
        """Return an element as the step began, zeros off the buffer.

        Args:
            slot: A buffer's id, or minus one less a workgroup array's.
            index: The element's place.

        Returns:
            Its floats, then zeros.
        """
        var at = self.address(slot, index)
        var out = Lanes(0)
        if at < 0:
            return out
        for lane in range(self.item_size(slot)):  # pragma: no branch
            out[lane] = self.memory[unsafe_offset=at + lane]
        return out

    def statement_result(self, statement: Int) -> Lanes:
        """Return what an earlier statement left the invocation.

        Args:
            statement: The statement.

        Returns:
            The value, then zeros.
        """
        var at = Int(
            self.word(
                self.table_at + statement * STATEMENT_FLOATS + STATEMENT_RESULT
            )
        )
        return Lanes(
            self.kept[unsafe_offset=at * 4],
            self.kept[unsafe_offset=at * 4 + 1],
            self.kept[unsafe_offset=at * 4 + 2],
            self.kept[unsafe_offset=at * 4 + 3],
        )

    def keep(self, at: Int, value: Lanes):
        """Keep a value for the invocation's later statements.

        Args:
            at: Which of its kept values.
            value: The value.
        """
        for lane in range(4):  # pragma: no branch
            self.kept[unsafe_offset=at * 4 + lane] = value[lane]


def _whole(x: Float32) -> Int32:
    """Return a float truncated to a 32-bit integer: held at the ends of
    the range, and zero for NaN, as the node bit operations read it."""
    var bits = bitcast[DType.uint32](x)
    if (bits & 0x7F800000) == 0x7F800000 and (bits & 0x007FFFFF) != 0:
        return 0
    return Int32(min(max(x, Float32(-2147483648.0)), Float32(2147483520.0)))


def atomic_result(op: Int, old: Float32, value: Float32) -> Float32:
    """Return what an atomic function leaves in an element: the arithmetic
    both backends share.

    Args:
        op: The function, an `AtomicOp`'s value.
        old: What the element held.
        value: The operand.

    Returns:
        The element's new value; `old` for `ATOMIC_LOAD`.
    """
    if op == ATOMIC_LOAD.value:
        return old
    if op == ATOMIC_STORE.value:
        return value
    if op == ATOMIC_ADD.value:
        return old + value
    if op == ATOMIC_SUB.value:
        return old - value
    if op == ATOMIC_MAX.value:
        return max(old, value)
    if op == ATOMIC_MIN.value:
        return min(old, value)
    var a = _whole(old)
    var b = _whole(value)
    if op == ATOMIC_AND.value:
        return Float32(a & b)
    if op == ATOMIC_OR.value:
        return Float32(a | b)
    # `ATOMIC_XOR`, the one function left.
    return Float32(a ^ b)


trait StorageMemory:
    """Where a step's stores and atomic functions land: the host's list, or
    the device's buffer, whose atomics are the hardware's."""

    def store(self, at: Int, value: Float32):
        """Write one float.

        Args:
            at: Its place in the memory.
            value: The float.
        """
        ...

    def atomic(self, op: Int, at: Int, value: Float32) -> Float32:
        """Run an atomic function on one float, at once.

        Args:
            op: The function, an `AtomicOp`'s value.
            at: The float's place in the memory.
            value: The operand.

        Returns:
            What the float held before.
        """
        ...


struct HostMemory(ImplicitlyCopyable, StorageMemory):
    """The host's `StorageMemory`: the invocations run one at a time, so an
    atomic function is a read and a write."""

    var live: Pointer[Float32, MutUntracked]

    def __init__(out self, live: Pointer[Float32, MutUntracked]):
        """Point at the memory the step writes.

        Args:
            live: The memory.
        """
        self.live = live

    def store(self, at: Int, value: Float32):
        """Write one float.

        Args:
            at: Its place in the memory.
            value: The float.
        """
        self.live[unsafe_offset=at] = value

    def atomic(self, op: Int, at: Int, value: Float32) -> Float32:
        """Run an atomic function on one float.

        Args:
            op: The function, an `AtomicOp`'s value.
            at: The float's place in the memory.
            value: The operand.

        Returns:
            What the float held before.
        """
        var old = self.live[unsafe_offset=at]
        self.live[unsafe_offset=at] = atomic_result(op, old, value)
        return old


def run_statements[
    M: StorageMemory
](source: ComputeSource, memory: M, first: Int, last: Int):
    """Run one invocation's statements of one step, in order: what both
    backends run.

    Args:
        source: The invocation.
        memory: Where its stores and atomic functions land.
        first: The step's first statement.
        last: One past its last, after `first`.
    """
    var none = Vector3(0, 0, 0)
    var inputs = NodeInputs(0, 0, none, none, none, none, False)
    for statement in range(first, last):  # pragma: no branch
        var entry = source.table_at + statement * STATEMENT_FLOATS
        var op = Int(source.word(entry + STATEMENT_OP))
        var slot = Int(source.word(entry + STATEMENT_SLOT))
        var kept = Int(source.word(entry + STATEMENT_RESULT))
        var value = run_code(
            source,
            Int(source.word(entry + STATEMENT_VALUE)),
            Int(source.word(entry + STATEMENT_VALUE_COUNT)),
            inputs,
        )
        if op == STATEMENT_HOLD:
            source.keep(kept, value)
            continue
        var index = run_code(
            source,
            Int(source.word(entry + STATEMENT_INDEX)),
            Int(source.word(entry + STATEMENT_INDEX_COUNT)),
            inputs,
        )
        var at = source.address(slot, index[0])
        if op == STATEMENT_STORE:
            if at >= 0:
                for lane in range(source.item_size(slot)):  # pragma: no branch
                    memory.store(at + lane, value[lane])
            continue
        var old = Float32(0)
        if at >= 0:
            old = memory.atomic(op, at, value[0])
        source.keep(kept, Lanes(old, 0, 0, 0))


def pack_storage(
    store: StorageBufferStore, node: ComputeNode
) raises -> Tuple[List[Float32], List[Int32]]:
    """Return the memory a run reads and writes, and where each buffer and
    array is in it: every buffer of the store in turn, then each of the
    node's workgroup arrays, zeros, one copy a workgroup.

    Args:
        store: The buffers.
        node: The node to run.

    Returns:
        The floats, and `REGION_INTS` numbers a buffer and an array.

    Raises:
        Error: If the store has no buffer the node names, or holds it as
            another type.
    """
    for at in range(len(node.buffers)):
        store._check(node.buffers[at])
    var memory = List[Float32]()
    var regions = List[Int32]()
    for at in range(store.count()):
        ref buffer = store.buffers[at]
        regions.append(Int32(len(memory)))
        regions.append(Int32(buffer.count))
        regions.append(Int32(buffer.type.value))
        memory.extend(buffer.array.copy())
    for at in range(len(node.array_types)):
        var width = node.array_types[at].value
        regions.append(Int32(len(memory)))
        regions.append(Int32(node.array_counts[at]))
        regions.append(Int32(width))
        memory.extend(
            List[Float32](
                length=node.array_counts[at] * width * node.workgroups(),
                fill=0,
            )
        )
    return (memory^, regions^)


def unpack_storage(mut store: StorageBufferStore, memory: List[Float32]):
    """Copy a run's memory back into the store's buffers.

    Args:
        store: The buffers, as `pack_storage` laid them out.
        memory: The memory after the run.
    """
    var at = 0
    for index in range(store.count()):
        var size = len(store.buffers[index].array)
        var part = List[Float32](capacity=size)
        part.extend(memory[at : at + size])
        store.buffers[index].array = part^
        at += size


def _run_step(
    node: ComputeNode,
    before: List[Float32],
    regions: List[Int32],
    mut memory: List[Float32],
    mut kept: List[Float32],
    buffers: Int,
    first: Int,
    last: Int,
):
    """Run one step of every invocation on the host, in order."""
    var code_at = (
        node.program.code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var before_at = (
        before.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var regions_at = (
        regions.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var memory_at = memory.unsafe_ptr().unsafe_origin_cast[MutUntracked]()
    var kept_at = kept.unsafe_ptr().unsafe_origin_cast[MutUntracked]()
    var workgroups = node.workgroups()
    for index in range(node.count):  # pragma: no branch
        var source = ComputeSource(
            code_at,
            before_at,
            regions_at,
            kept_at.unsafe_offset(index * node.results * 4),
            buffers,
            node.table_at,
            index,
            node.workgroup_size,
            workgroups,
        )
        run_statements(source, HostMemory(memory_at), first, last)
    # The pointers do not keep their lists alive; this does.
    _ = before
    _ = regions


def run_compute(mut store: StorageBufferStore, node: ComputeNode) raises:
    """Run a compute node over a store's buffers on the host, three.js's
    `renderer.compute( node )`: each step at every invocation, in order.

    Args:
        store: The buffers. What the node stores lands in them.
        node: The node.

    Raises:
        Error: If the store has no buffer the node names, or holds it as
            another type.
    """
    var packed = pack_storage(store, node)
    var memory = packed[0].copy()
    var kept = List[Float32](
        length=max(node.count * node.results * 4, 4), fill=0
    )
    for stage in range(node.stages()):  # pragma: no branch
        var before = memory.copy()
        _run_step(
            node,
            before,
            packed[1],
            memory,
            kept,
            store.count(),
            node.stage_starts[stage],
            node.stage_starts[stage + 1],
        )
    unpack_storage(store, memory)


trait ComputeRunner:
    """What runs a compute node: the host, or the device. three.js's
    `renderer.compute`."""

    def compute(
        mut self, mut store: StorageBufferStore, node: ComputeNode
    ) raises:
        """Run a compute node over a store's buffers.

        Args:
            store: The buffers.
            node: The node.

        Raises:
            Error: If the store has no buffer the node names, or the runner
                cannot run it.
        """
        ...


struct HostCompute(ComputeRunner, Movable):
    """Runs compute nodes on the host with `run_compute`."""

    def __init__(out self):
        """Create a runner."""
        pass

    def compute(
        mut self, mut store: StorageBufferStore, node: ComputeNode
    ) raises:
        """Run a compute node over a store's buffers on the host.

        Args:
            store: The buffers.
            node: The node.

        Raises:
            Error: If the store has no buffer the node names, or holds it
                as another type.
        """
        run_compute(store, node)
