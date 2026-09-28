# Compute nodes

`materials/compute_nodes.mojo` runs compute programs over storage buffers, on the host and on the GPU. It ports three.js's compute nodes from `src/nodes/gpgpu/`: `ComputeNode`, `AtomicFunctionNode`, `BarrierNode`, `WorkgroupInfoNode` and `SubgroupFunctionNode`. It also ports the storage buffers and textures that they read and write. `render/gpgpu_sort.mojo` ports `BitonicSort` and `CountingSort` from `examples/jsm/gpgpu/`.

![A compute kernel walks points around a sphere](out/computenodes.png)

`examples/particles.mojo` draws this picture.

```mojo
var store = StorageBufferStore()
var positions = store.instanced_array(count, NODE_VEC3)
var velocities = store.instanced_array(count, NODE_VEC3)

var kernel = ComputeKernel()
var i = kernel.instance_index()
kernel.add_assign(positions, i, kernel.element(velocities, i))
var update = kernel.compute(count)

var host = HostCompute()
host.compute(store, update)   # or GpuCompute().compute(store, update)
var moved = store.array(positions)
```

This is three.js's `Fn( () => { position.addAssign( velocity ) } )().compute( count )` and `renderer.compute( update )`.

## Storage buffers

A `StorageBufferStore` owns the buffers. A `StorageBufferNode` names one buffer, its element type and its count.

| Call | three.js |
|---|---|
| `store.instanced_array(count, type)` | `instancedArray( count, type )` |
| `store.instanced_array(floats, type)` | `instancedArray( typedArray, type )` |
| `store.storage(StorageBuffer(...))` | `storage( attribute, type, count )` |
| `store.storage_texture(width, height)` | `new StorageTexture( width, height )` |
| `store.array(node)` | `attribute.array` |
| `store.set_array(node, floats)` | `attribute.array.set( floats )` |
| `store.texture(storage_texture)` | The storage texture as a material reads it |

An element is a `float` or a vector of two, three or four floats. A `uint` element holds a whole number as a float. It is exact up to 2 ** 24.

A material reads a buffer after a run. Copy `store.array(node)` into a geometry attribute, or read `store.texture(texture)` as a float texture.

## A kernel

A `ComputeKernel` holds a `NodeGraph`, `kernel.graph`, and the statements built on it. Build values with the graph's nodes. Read the invocation and the buffers through the kernel.

| Call | three.js |
|---|---|
| `instance_index()` | `instanceIndex` |
| `invocation_local_index()` | `invocationLocalIndex` |
| `global_id()`, `local_id()` | `globalId`, `localId` |
| `workgroup_id()`, `num_workgroups()` | `workgroupId`, `numWorkgroups` |
| `subgroup_size()`, `subgroup_index()`, `invocation_subgroup_index()` | `subgroupSize`, `subgroupIndex`, `invocationSubgroupIndex` |
| `element(buffer, index)` | `buffer.element( index )` |
| `assign(buffer, index, value)` | `buffer.element( index ).assign( value )` |
| `add_assign(buffer, index, value)` | `buffer.element( index ).addAssign( value )` |
| `texture_store(texture, coord, value)` | `textureStore( texture, coord, value )` |
| `texture_load(texture, coord)` | `textureLoad( texture, coord )` |
| `to_const(value)` | `value.toConst()` |
| `workgroup_array(type, count)` | `workgroupArray( type, count )` |
| `workgroup_barrier()`, `storage_barrier()`, `texture_barrier()` | The three barriers |
| `compute(count, workgroup_size)` | `.compute( count, [ workgroupSize ] )` |

`compute` compiles the kernel to a `ComputeNode`. The workgroup size is 64 unless you set it. A node runs `count` invocations in workgroups along x. Change the count with `set_count`. Set a uniform with `node.program.set_uniform`.

## Statements

A statement is a store, an atomic function or a held value. The invocation runs its statements in order. Each statement's index and value are roots of the graph, and `NodeGraph.compile_roots` lays them out.

A statement inside a `graph.If` is kept only where its branch runs. A statement cannot be made inside a `graph.Loop`, because `End` copies the loop body and not the statements. Use a Mojo loop to repeat a statement. The loop count is fixed in both cases.

`to_const(value)` computes a value once and keeps it for the invocation. Later statements read the kept value, also after a barrier.

## Steps and barriers

A barrier ends a step. Every invocation runs a step before any invocation runs the next step.

In a step, a read sees the buffer as the step began. It also sees the stores of the same invocation that come before it. A read never sees the store of another invocation in the same step. So the host and the device agree.

Two invocations that store to one element in one step race, as on a GPU. The host keeps the store of the last invocation.

## Atomic functions

An atomic function changes one element of a `float` buffer at once, and returns the value that the element held before.

| Call | three.js |
|---|---|
| `atomic_load(buffer, index)` | `atomicLoad` |
| `atomic_store(buffer, index, value)` | `atomicStore` |
| `atomic_add`, `atomic_sub` | `atomicAdd`, `atomicSub` |
| `atomic_max`, `atomic_min` | `atomicMax`, `atomicMin` |
| `atomic_and`, `atomic_or`, `atomic_xor` | `atomicAnd`, `atomicOr`, `atomicXor` |
| `atomic_func(op, buffer, index, value)` | `atomicFunc( method, pointer, value )` |

The host runs the invocations in order. The device runs them at the same time. So the old values can come in a different order on the device, but the sums agree. The bit functions read whole numbers of 32 bits, as the node bit operations do.

## Workgroups and subgroups

A workgroup array has one copy for each workgroup. Each copy starts as zeros at the start of a run. An invocation reads and writes the copy of its own workgroup.

A subgroup is one invocation. `subgroup_size()` is one. Each subgroup function gives what one invocation gives it: `subgroup_add(x)` is `x`, `subgroup_exclusive_add(x)` is zero, and `subgroup_ballot(p)` sets one bit.

## Sorts

`BitonicSort(store, data, workgroup_size)` sorts a buffer of floats in place, the smallest value first. The count must be a power of two. `sort.compute(runner, store)` runs every step. `sort.compute_step(runner, store)` runs one step.

`CountingSort(store, count, bin_count, workgroup_size)` orders the places `0` to `count - 1` by a bin. Set the bin with `set_bin_node(bin_node)`. The bin node is a function that builds the bin from the kernel. `sort.order` holds the sorted places after `compute`. `compute_cpu(store, bins)` gives the same order without a compute program.

The prefix pass of a counting sort is one invocation with two statements for each bin. The default of 4096 bins takes a few seconds to build.

## On the GPU

`GpuCompute` in `render/gpu.mojo` runs a node on the device. Each step is one launch, with one block for each workgroup. Both backends call `run_statements` on a `ComputeSource`, so the buffers agree to the float. `tests/test_gpu.mojo` checks a kernel and both sorts.

## Where this port differs

- A barrier ends a step for every invocation of the dispatch. In WebGPU, `workgroupBarrier` waits only for the workgroup.
- A dispatch is along x only. `globalId.y` and `globalId.z` are zero.
- Every value is a float. A `uint` or `int` element is a float that holds a whole number.
- An atomic function works on a buffer of floats. WebGPU atomics work on `u32` and `i32`.
- A read of an element that is not in the buffer returns zeros. A store to such an element does nothing.

## What is not ported

- The quad functions `quadSwapX`, `quadSwapY`, `quadSwapDiagonal` and `quadBroadcast`. They need a quad of four invocations, and a subgroup here is one invocation.
- A material that reads a storage buffer or a storage texture directly, such as `positionBuffer.toAttribute()`.
- A 3D storage texture, `StorageTexture3DNode`.
- A dispatch size in two or three dimensions, and `computeKernel` with a workgroup size in more than one dimension.
- Struct elements, `struct` types in `instancedArray`.
