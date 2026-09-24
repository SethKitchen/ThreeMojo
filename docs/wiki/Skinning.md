# Skinning

`objects/skeleton.mojo` and `objects/skinned_mesh.mojo`. A skinned mesh is a mesh whose vertices are attached to bones. Move a bone and the vertices it holds move with it. That is how an arm bends.

![A cylinder bends where its upper bone turns](out/skinning.png)

three.js: `Bone`, `Skeleton`, `SkinnedMesh`, `skinIndex`, `skinWeight`, `bindMatrix`.

## A bone is a scene node

three.js says the same: its `Bone` adds nothing to `Object3D` but a name. It matters here, because posing a skeleton is moving nodes, and the [scene graph](Scene-graph) and the [animation mixer](Animation) already do that. Nothing new drives a rig. A `KeyframeTrack` on a bone's node animates it, and that already works.

What a bone needs besides a node is where it stood when the mesh was attached to it: the inverse bind matrix. three.js keeps the bones and their inverses in two arrays. Here one `Bone` holds both: a bone without its inverse cannot be used, and two arrays can fall out of step.

```mojo
from objects.skeleton import Bone, Skeleton, bind_skeleton

var placed = List[Matrix4]()
for index in range(len(bones)):
    placed.append(scene.world_matrix(bones[index]))
var skeleton = bind_skeleton(bones, placed)   # bound where they stand now
```

| Member | Meaning |
|---|---|
| `Bone(node, inverse_bind)` | One bone: a node, and where it was bound. |
| `Skeleton(bones)` | The bones a mesh is carried by. |
| `skeleton.bone_count() -> Int` | How many bones there are. |
| `skeleton.node(index) -> NodeId` | Which node one bone is. |
| `skeleton.pose(placed) -> List[Matrix4]` | How far each bone has moved since the bind. |
| `skeleton.calculate_inverses(placed)` | Bind every bone where it stands now, three.js's `calculateInverses`. |
| `bind_skeleton(nodes, placed)` | Make a skeleton and bind it where the nodes stand. |

`pose` is three.js's `Skeleton.update`: each bone's world matrix times its inverse bind. A bone standing where it was bound gives the identity, and a mesh bound to it is left alone. That is the property worth testing first.

`pose` takes the bones' world matrices rather than the scene. A skeleton is an object, `core.scene` imports the objects, and a skeleton reaching back for the scene would be a circle. The renderer has both and does the looking up.

## SkinnedMesh

```mojo
from objects.skinned_mesh import SkinnedMesh

var body = SkinnedMesh(geometry, material, node, skeleton^)
scene.add_skinned_mesh(body^)
```

The geometry must carry two attributes, named as three.js and glTF name them:

| Attribute | Meaning |
|---|---|
| `skinIndex` | Four bone numbers per vertex. |
| `skinWeight` | Four weights per vertex, usually summing to one. |

Four is this port's limit and the common one: glTF's first `JOINTS_0` and `WEIGHTS_0` pair holds four. It is not a limit of skinning — glTF allows further sets for vertices that need more, and those are simply not read yet. The attribute names here are three.js's.

A skinned mesh owns its skeleton and is moved into the scene, exactly as an `InstancedMesh` is moved in with its matrices. three.js lets several meshes share one skeleton; here each carries its own, and two meshes on one rig name the same nodes. The nodes are shared, so the pose is shared.

### Attached or detached

A bone's matrix carries a vertex in world space, and the mesh's own node then carries it again. Something must undo the second carry, or a character whose mesh and bones hang from one moving root is moved twice.

| Mode | What it undoes | For |
|---|---|---|
| `ATTACHED` | The mesh node's world matrix **this frame**. | A rig that follows whatever carries it. The default, here and in three.js. |
| `DETACHED` | The fixed bind matrix. | A mesh bound to a skeleton elsewhere in the graph. |

The difference shows only once something moves the mesh's node after the bind. Translate a shared root three meters with `ATTACHED` and the character moves three. With `DETACHED` it moves six, which is the right answer to a different question.

Frustum culling is **off** by default, which is not a plain `Mesh`'s default. A posed skeleton carries vertices wherever the bones go, and the geometry's bound describes the rest pose only.

Turning it on measures that rest pose and nothing else. A mesh the bones have carried out of it can then be culled while it is still on screen. It is an opt-in to a known wrong answer rather than a free saving. A bound that follows the pose needs the deformed vertices. That is the evaluator [picking](Raycasting) now uses, and the natural place to take this next.

## The arithmetic

`bind_matrix` is where the mesh stood when it was attached, and `bind_inverse` undoes it. They exist because a bone's matrix carries a vertex in *world* space, while a geometry's vertices are in the mesh's own space.

```text
skinned = sum over the four bones of
          weight * bone_matrix * (bind_matrix * vertex)
vertex  = bind_inverse * skinned
```

That is three.js's `skinning_vertex` line for line. `blend_bones` builds the weighted sum as one matrix, and the same matrix moves the position and turns the normal, because a matrix sum is linear. three.js shares the blend between `skinning_vertex` and `skinnormal_vertex` for the same reason.

A matrix blend is also why an elbow made of two bones pinches slightly when it bends. The average of two rotations taken through their matrices is not a rotation. Every engine doing this on a GPU has the same pinch. Dual quaternions are a different feature, not a better version of this one.

## Skeleton tools

`core/skeleton_utils.mojo`. These read the scene, so they are free functions and not methods of `Skeleton`. A skeleton cannot import the scene, because the scene imports it. three.js: `Skeleton.getBoneByName`, `Skeleton.calculateInverses`, `Skeleton.pose`, `SkeletonUtils.clone`, `SkeletonUtils.retarget`.

```mojo
from core.skeleton_utils import RetargetOptions, clone_skinned, retarget

var copy = clone_skinned(scene, character)       # carried by its own bones
scene.add(copy)
var options = RetargetOptions()
options.names["Hips"] = "mixamorigHips"          # target bone -> source bone
options.names["Spine"] = "mixamorigSpine"
retarget(scene, 0, scene.skinned_meshes[1].skeleton.copy(), options)
```

| Function | Meaning |
|---|---|
| `get_bone_by_name(scene, skeleton, name) -> Optional[NodeId]` | The first bone with a name. |
| `calculate_inverses(scene, skeleton)` | Bind every bone where it stands in the scene. |
| `bone_world_matrices(scene, skeleton) -> List[Matrix4]` | Every bone's world matrix, for `pose` and `calculate_inverses`. |
| `restore_bind_pose(scene, skeleton)` | Put every bone back where it was bound, three.js's `Skeleton.pose`. |
| `clone_skinned(scene, node) -> NodeId` | Copy a subtree, each copied skinned mesh carried by the copies of its bones. |
| `retarget(scene, target, source, options)` | Pose a skinned mesh's bones like another skeleton's. |

`Skeleton.pose` here is three.js's `Skeleton.update`, so three.js's `Skeleton.pose` is `restore_bind_pose`. A bone whose parent is a bone of the skeleton takes the transform that puts it back under that parent. Any other bone takes its bind-time world matrix as its own transform, as in three.js.

### Clone

`Scene.clone` shares the skeleton, as three.js's `Object3D.clone` does. The copy is then carried by the original bones. `clone_skinned` points each copied skinned mesh at the copies of its bones. It matches the two subtrees side by side, as three.js's `parallelTraverse` does. A bone outside the copied subtree has no copy, and the copy keeps the original bone. three.js puts `undefined` in the skeleton there.

### Retarget

`retarget` puts the target's bones in their bind pose first. Then each bone that `options.names` maps to a source bone takes that bone's world rotation and position. The hip's position is scaled by `scale` and `hip_influence`, and moved by `hip_position`. With `preserve_bone_positions`, every other bone takes back its bind position. The arithmetic is three.js's, step for step.

| Option | Default | Meaning |
|---|---|---|
| `preserve_bone_matrix` | True | Measure the bones with the target mesh's node at the identity. |
| `preserve_bone_positions` | True | Keep every bone's position but the hip's. |
| `use_target_matrix` | False | Take the source bones' world matrices as they are. |
| `hip` | `"hip"` | The source name of the hip bone. |
| `hip_influence` | (1, 1, 1) | How much of the hip's position to carry, along each axis. |
| `hip_position` | none | Where to move the hip, before the scale. |
| `scale` | 1 | What the hip's position is scaled by. |
| `names` | empty | For each target bone's name, the source bone's name. |
| `local_offsets` | empty | A turn after the source's, by target bone name. |

A target bone with no entry in `names` takes no source bone, as in three.js. The target must be a skinned mesh. three.js also takes a bare skeleton. `retargetClip` and the `getBoneName` option are not ported.

## Inverse kinematics

`animation/ccd_ik_solver.mojo`. `CCDIKSolver` turns a chain of bones so that one bone, the effector, reaches for another, the target. It solves by cyclic coordinate descent, as three.js's `CCDIKSolver` does.

```mojo
from animation.ccd_ik_solver import CCDIKSolver, IkChain, IkLink

var arm = IkChain(target=4, effector=3, links=[IkLink(2), IkLink(1)])
arm.iteration = 10
var solver = CCDIKSolver(scene, 0, [arm^])
solver.update(scene)                          # after each animation step
```

| Member | Meaning |
|---|---|
| `IkLink(index)` | A bone that turns. `enabled`, `limitation`, `rotation_min` and `rotation_max` bound it. |
| `IkChain(target, effector, links)` | A chain. `iteration`, `min_angle`, `max_angle` and `blend_factor` tune it. |
| `CCDIKSolver(scene, mesh, iks)` | Chains on one skinned mesh's skeleton. Bones are named by their index in it. |
| `solver.update(scene, blend=1)` | Solve every chain, three.js's `update`. |
| `solver.update_one(scene, chain, blend=1)` | Solve one chain, three.js's `updateOne`. |

Each step turns one link so that the effector swings toward the target around it. A turn below 1e-5 radians is skipped. `min_angle` and `max_angle` clamp each turn. A `limitation` axis keeps the link turning about that axis only.

`rotation_min` and `rotation_max` are an `Euler` each, and clamp the link's angles in the bound's order. three.js clamps in the order of the link's own `rotation`. A node here has no order of its own.

A blend below one slerps each link from where it started toward the solved turn. A chain's own `blend_factor` wins over the solver's. The solver updates the scene after each turn. three.js updates one link's world matrix, which gives the same numbers.

The solver refuses a bone index the skeleton does not have, a negative `iteration`, and a blend outside zero to one. three.js warns when a link is not the parent of the one before it, and solves anyway. This checks nothing about the parents. `CCDIKHelper` is not ported.

## Both backends agree by construction

Skinning happens in `Renderer.prepare`, which is the one place the CPU and GPU rasterizers both read from. Neither rasterizer knows a bone exists, so they draw the same triangles. The same is true of [morph targets](Geometry#morph-targets), and the two compose: a vertex is morphed first and then carried by its bones, as in three.js.

## What is refused

| Mistake | Answer |
|---|---|
| A skeleton with no bones. | An error at construction. |
| An inverse bind that is not a finite affine transform. | An error at construction. |
| A bind matrix that cannot be inverted. | An error at construction. |
| A bone bound where it has no size. | An error at binding. |
| A pose given the wrong number of world matrices. | An error. |
| A node or a bone the scene does not hold. | An error at `add_skinned_mesh`. |
| A geometry without `skinIndex` and `skinWeight`. | An error at `prepare`. |
| A skin attribute that is not four numbers a vertex. | An error at `prepare`. |
| A vertex naming a bone the skeleton does not have. | An error at `prepare`. |
| A weight that is not a number, or is below zero. | An error at `prepare`. |
| A bone index that is not a whole number in range. | An error at `prepare`. |
| A supplied inverse bind with no inverse of its own. | An error at construction. |
| A bind mode that is neither of the two. | An error at construction. |
| An `ATTACHED` mesh scaled to nothing. | An error at `prepare`. |

Negative weights are refused for the same reason. Two bones at minus one and two sum to one, and send a vertex twice as far as the further one. glTF forbids them.

### Weights that do not sum to one

The renderer uses the weights as they are, as three.js's shader does. Weights summing to two put a vertex twice as far from the mesh's origin as the bones do. Weights of zero put it at the origin.

`normalize_skin_weights(geometry)` is three.js's `SkinnedMesh.normalizeSkinWeights`. It divides each vertex's weights by the sum of their magnitudes. A vertex with no weight goes to its first bone. The glTF, FBX and Collada loaders call it, as three.js's loaders do. The scene JSON loader does not, as three.js's `ObjectLoader` does not. Call it for a geometry that you build.

## See also

- [Animation](Animation) poses the bones.
- [Scene graph](Scene-graph) holds them.
- [Geometry](Geometry#morph-targets) has morph targets, the other way a vertex moves.
- [Meshes and assets](Meshes-and-assets#lod) has levels of detail, whose levels can be skinned meshes.
- [Raycasting](Raycasting) picks morphed meshes and skinned meshes where their bones carry them.
