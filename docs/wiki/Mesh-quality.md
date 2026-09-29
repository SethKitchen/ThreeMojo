# Mesh quality

A `Quality` level sets how many triangles one humanoid holds. `LOW` keeps 90,000 triangles for a whole body. `XHIGH` keeps one million.

![A six-foot male body below the neck at HIGH quality: bones, joint tissues and muscles on the left, the skin on the right](out/torso.png)

The module is `extensions/humanoid/quality.mojo`. The simplifier is `extensions/humanoid/skeleton/simplify.mojo`. This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.quality import (
    anatomy_detail,
    hand_skin_detail,
    quality_named,
    skin_detail,
    triangle_budget,
)
from extensions.humanoid.skeleton.simplify import fit_triangle_budget
from renderers.renderer import available_workers

var level = quality_named("medium")
var first = len(scene.meshes)
_ = add_body(
    scene, assets, parent, person, bone, cartilage, cartilage,
    ligament, muscle, tendon, BOTH,
    anatomy_detail(level), skin_detail(level), hand_skin_detail(level),
)
fit_triangle_budget(
    scene, assets, first, triangle_budget(level), available_workers()
)
```

Do these steps for each body:

1. Read the mesh count of the scene.
2. Add the body with the three `detail` values of the level.
3. Call `fit_triangle_budget` on the meshes from that count on.

## Levels

| Level | Anatomy | Body skin | Hand skin | Triangle budget |
|---|---|---|---|---|
| `LOW` | 8 | 32 | 24 | 90,000 |
| `MEDIUM` | 10 | 40 | 32 | 200,000 |
| `HIGH` | 12 | 48 | 40 | 450,000 |
| `XHIGH` | 16 | 56 | 48 | 1,000,000 |

The three `detail` values set how finely the mesher samples each solid. The budget sets how many triangles are kept after the merge. Each level has about twice the triangles of the level below it.

| Function | Returns |
|---|---|
| `anatomy_detail(quality)` | The detail of each bone, ligament, muscle and vessel. |
| `skin_detail(quality)` | The detail of a skin over the body or a limb. |
| `hand_skin_detail(quality)` | The detail of the skin of one hand. |
| `triangle_budget(quality)` | The triangles one whole body keeps. |
| `quality_named(name)` | The level that `low`, `medium`, `high` or `xhigh` names. |
| `quality_label(quality)` | The name of the level. |

A bare integer is a compile error. A value that is not a named level raises.

## Budget

`fit_triangle_budget(scene, assets, first_mesh, budget, workers=1)` shares the budget between the meshes by surface area. Each mesh keeps at least `MIN_PART_TRIANGLES`, which is 32. A mesh never keeps more triangles than it has. The triangles that it cannot use go to the other meshes. A geometry that two meshes name is decimated once.

`share_budget(areas, counts, budget)` does the sharing alone. `simplify(geometry, target)` decimates one geometry.

## Merge

The merge is quadric-error edge collapse (Garland and Heckbert, 1997):

1. The corners that are within 10 micrometers of each other are welded into one vertex.
2. Each vertex keeps the sum of the plane quadrics of the faces around it. A quadric is weighted by its face's area.
3. The edge whose collapse moves the surface least goes first.

A collapse is refused in four cases:

- An end has moved since the edge was measured.
- More than two faces hold the edge.
- The ends share a neighbor that is not a corner of a shared face. The collapse would pinch the surface.
- A face would turn by more than about 78 degrees.

An open edge carries a stiff plane at right angles to its face. The border of an open mesh stays in place.

The normals are the area-weighted mean of the faces around each vertex. A vertex keeps its own texture coordinates.

## Performance

The torso gallery draws two bodies at 640 by 360, in 36 frames, with a soft shadow. These times are for 24 logical cores:

| Level | Triangles in the frame | Frame with shadows |
|---|---|---|
| `LOW` | 182,000 | 0.9 seconds |
| Before the budget, detail 8 | 3,282,000 | 29 seconds |

At `XHIGH` the whole gallery takes 268 seconds, compile time included. Before the budget, the gallery at detail 16 took about 70 minutes.

## Errors

`fit_triangle_budget` raises in these cases:

- The budget is less than one.
- `workers` is less than one.
- `first_mesh` is not in the scene.
- A geometry has no positions, holds a partial triangle, or has an index entry past its last vertex.

`simplify` raises if the target is less than one, or for the same geometry errors.
