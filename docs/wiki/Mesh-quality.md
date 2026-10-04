# Mesh quality

A `Quality` level sets a target triangle count for one humanoid. `LOW` targets 90,000 triangles for a whole body. `XHIGH` targets one million.

For engineering use and representation limits, see [Humanoid fidelity](Humanoid-fidelity).

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

The three `detail` values set how finely the mesher samples each solid. The budget sets the target triangle count after the merge. Each level has about twice the triangles of the level below it.

| Function | Returns |
|---|---|
| `anatomy_detail(quality)` | The detail of each bone, ligament, muscle and vessel. |
| `skin_detail(quality)` | The detail of a skin over the body or a limb. |
| `hand_skin_detail(quality)` | The detail of the skin of one hand. |
| `triangle_budget(quality)` | The target triangle count for one whole body. |
| `quality_named(name)` | The level that `low`, `medium`, `high` or `xhigh` names. |
| `quality_label(quality)` | The name of the level. |

A bare integer is a compile error. A value that is not a named level raises.

## Budget

`fit_triangle_budget(scene, assets, first_mesh, budget, workers=1)` shares the budget between unique geometries by surface area. Each geometry keeps at least `MIN_PART_TRIANGLES`, which is 32. If welding leaves fewer than 32 triangles, it keeps that count. A geometry never receives a share larger than its count after welding. The triangles that it cannot use go to the other geometries. A geometry that two meshes name is counted and decimated once.

The original call keeps its best-effort, no-result interface. The budget is a target. It is not a hard maximum. The minimum shares take priority when the budget cannot cover them. Safe collapse rules can also leave more triangles than a geometry's share. A collapse never crosses the 32-triangle minimum.

The allocator reserves minimum shares before it assigns larger shares. For a feasible budget, the assigned shares total at most that budget. Shares are rounded down. A geometry with no surface area receives only its minimum share.

`share_budget(areas, counts, budget)` does the sharing alone. `simplify(geometry, target)` decimates one geometry.

### Read the result

`fit_triangle_budget_result` fits the same meshes and returns a `TriangleBudgetResult`. Its first five arguments match `fit_triangle_budget`. Its last argument is a `TriangleBudgetMode`: `BEST_EFFORT` by default, or `STRICT`.

```mojo
from extensions.humanoid.skeleton.simplify import (
    MINIMUM_SHARES,
    SAFE_COLLAPSE_LIMIT,
    SMALL_WELDED_SOURCES,
    STRICT,
    fit_triangle_budget_result,
)

var result = fit_triangle_budget_result(scene, assets, first, 90000)
print(result.requested_triangles, result.retained_triangles)
print(result.target_met())
print(result.has_reason(MINIMUM_SHARES))
print(result.has_reason(SMALL_WELDED_SOURCES))
print(result.has_reason(SAFE_COLLAPSE_LIMIT))
```

| Result member | Meaning |
|---|---|
| `requested_triangles` | The caller's budget. |
| `retained_triangles` | The actual triangle total after welding and decimation. |
| `minimum_triangles` | The sum of `min(32, welded_count)` across unique geometries. |
| `small_source_triangles` | The triangles contributed to that minimum by welded sources below 32 triangles. |
| `protected_triangles` | The total triangles retained above their allocated shares. |
| `target_met()` | True when the retained total is at most the requested total. |
| `has_reason(reason)` | Whether a named limit contributed to a missed target. |

Every count includes each selected geometry once, even when several meshes share it. Only meshes from `first_mesh` onward select geometries. Replacement also affects earlier meshes that share a selected geometry. An empty selection retains zero triangles and meets every valid budget.

Reasons are typed `TriangleBudgetReason` values. A met target has no failure reason. Reasons can overlap:

- `MINIMUM_SHARES`: the sum of minimum shares exceeds the requested budget
- `SMALL_WELDED_SOURCES`: those minimum shares include triangles from sources smaller than 32 after welding
- `SAFE_COLLAPSE_LIMIT`: safe collapse rules keep triangles above their shares

The last reason includes protected topology, face turns and collapses that would cross a part's minimum. It does not identify individual rejected edges. A geometry can exceed its share while the total still meets the budget. The report marks that result as success.

### Require the target

```mojo
var result = fit_triangle_budget_result(
    scene, assets, first, 90000, mode=STRICT
)
```

`STRICT` commits replacements only when the actual retained total meets the target. A missed target raises with the requested, retained, minimum, small-source and above-share counts. No geometry is replaced on that failure. Shared geometry references remain unchanged.

Strict mode converts all replacement geometries before changing the asset store. Invalid input or a strict conversion error leaves every original geometry unchanged. Strict mode needs memory for that complete replacement set, in addition to the source assets and working meshes.

Best effort keeps the original incremental replacement path. A conversion error can follow replacements of earlier geometries. It holds only one extra converted geometry at a time. Neither mode copies a shared geometry for each mesh that names it.

A source whose faces all disappear in welding produces zero triangles. Its positions, normals and texture coordinates are empty. Unused vertices do not create new triangles.

Strict mode does not change the allocator, weld tolerance, minimum shares or safe collapse rules. It can refuse a budget that another allocation or another algorithm could meet. It tests the actual result of this fitting pass.

Do not fit a skin to the budget. The skins are meshed smooth and lean by surface nets already. They carry the face's colors and their thinness, which decimation drops, and a seam in their texture coordinates, which welding closes. Add the skin after `fit_triangle_budget`, as `examples/head.mojo` and `examples/torso.mojo` do.

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

`fit_triangle_budget_result` has the same errors. It also refuses unnamed modes and missed strict targets. `has_reason` refuses an unnamed reason. A bare integer cannot replace a mode or reason.

`simplify` raises if the target is less than one, or for the same geometry errors.
