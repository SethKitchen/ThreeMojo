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
| `bind_skeleton(nodes, placed)` | Bind nodes where they stand, three.js's `calculateInverses`. |

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
| `skinWeight` | Four weights per vertex, summing to one. |

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
| Weights that do not sum to one. | An error at `prepare`. |
| A weight that is not a number, or is below zero. | An error at `prepare`. |
| A bone index that is not a whole number in range. | An error at `prepare`. |
| A supplied inverse bind with no inverse of its own. | An error at construction. |
| A bind mode that is neither of the two. | An error at construction. |
| An `ATTACHED` mesh scaled to nothing. | An error at `prepare`. |

Negative weights are refused for the same reason. Two bones at minus one and two sum to one, and send a vertex twice as far as the further one. glTF forbids them.

The sum rule is stricter than three.js, which normalizes in its loader and lets the shader take whatever arrives. Weights summing to two put a vertex twice as far from the origin as the bones do. That reads as a mesh which swells where it bends, and it is a rig with a mistake in it.

## See also

- [Animation](Animation) poses the bones.
- [Scene graph](Scene-graph) holds them.
- [Geometry](Geometry#morph-targets) has morph targets, the other way a vertex moves.
- [Raycasting](Raycasting) picks morphed meshes, and does not pick rigs yet.
