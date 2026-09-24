# Geometry addons

The geometry addons of three.js's `examples/jsm/`: two more geometries, four modifiers, the rest of `BufferGeometryUtils`, MikkTSpace tangents, `SceneUtils`, NURBS and the named curves. Each module is a line-by-line port. Its tests check it against values that three.js 0.180 calculated under node.

| Module | three.js |
|---|---|
| `geometries/teapot.mojo` | `TeapotGeometry` |
| `geometries/box_line.mojo` | `BoxLineGeometry` |
| `geometries/tessellate.mojo` | `TessellateModifier` |
| `geometries/simplify.mojo` | `SimplifyModifier` |
| `geometries/edge_split.mojo` | `EdgeSplitModifier` |
| `geometries/curve_modifier.mojo` | `Flow`, `InstancedFlow` |
| `geometries/attribute_utils.mojo` | `mergeAttributes`, `interleaveAttributes`, `deinterleaveAttribute`, `deinterleaveGeometry`, `estimateBytesUsed`, `toTrianglesDrawMode`, `mergeGroups`, `computeMorphedAttributes` |
| `geometries/mikktspace.mojo` | `computeMikkTSpaceTangents`, and `mikktspace.c` |
| `core/scene_utils.mojo` | `createMeshesFromInstancedMesh`, `createMultiMaterialObject`, `sortInstancedMesh`, `reduceVertices` |
| `math/nurbs.mojo` | `NURBSUtils`, `NURBSCurve`, `NURBSSurface`, `NURBSVolume` |
| `math/curve_extras.mojo` | `CurveExtras` |
| `math/space_curve.mojo` | the base `Curve`: arc lengths, spaced points, Frenet frames |

`mergeGeometries`, `mergeVertices` and `toCreasedNormals` are in `geometries/utils.mojo`. See [Geometry](Geometry#merge-weld-and-tangents).

## Teapot

`teapot(size, segments, bottom, lid, body, fit_lid, blinn)` is the Utah teapot. It has 32 bicubic Bezier patches. Each patch is a grid of `segments + 1` by `segments + 1` vertices.

![The Utah teapot turns under a lamp](out/teapot.png)

`examples/utah.mojo` draws this picture.

| Argument | Meaning |
|---|---|
| `size` | Half the height. 50 meters by default, as three.js has 50 units. |
| `segments` | Cells along each side of a patch, two or more. Ten by default. |
| `bottom`, `lid`, `body` | Which parts to make. |
| `fit_lid` | Widen the lid by 7.7 % so that it meets the rim. |
| `blinn` | Keep Jim Blinn's shorter proportions. |

A triangle with two corners in one place is dropped, as in three.js. three.js raises a count of segments below two to two. This port refuses it.

## Box lines

`box_line(width, height, depth, width_segments, height_segments, depth_segments)` is a box as line segments. Draw it with a `LineSegments`. Each segment boundary gives a ring of four sticks round the box.

## Tessellate

`tessellate(geometry, max_edge_length, max_iterations)` cuts every triangle in two across its longest edge until no edge is longer than the limit. The passes stop after `max_iterations`, so an edge can stay long.

The midpoint takes the average position, normal, color and both texture coordinates. Only `position`, `normal`, `color`, `uv` and `uv1` are kept. The result has no index.

## Simplify

`simplify(geometry, count)` removes `count` vertices, one edge at a time. It is Stan Melax's progressive mesh reduction. The cost of a vertex is the distance to a neighbor times the curvature there.

The geometry is welded first with `merge_vertices`. `position`, `uv`, `normal`, `tangent` and `color` are kept. Every search is a walk down a list, as in three.js. So ties go to the same vertex, and the result is three.js's, vertex for vertex.

## Edge split

`edge_split(geometry, cut_off_angle, try_keep_normals)` gives a vertex a copy for each group of triangles that turn from each other by the cut-off angle or more. Then the normals are calculated again. A vertex that was not split keeps its normal if `try_keep_normals` is set.

The copies go after a run as long as the index, as in three.js. So the result has unused vertices of zeros. The vertices that keep their normals follow three.js's rule, which reads a corner number as a vertex number.

## Curve modifier

`Flow` bends a mesh along a curve. three.js writes the curve into a data texture and bends the mesh in a vertex shader. This port writes the same texture, and bends the mesh on the CPU.

| Member | Meaning |
|---|---|
| `Flow(curve_count)` | An empty spine texture with room for some curves. |
| `update_curve(index, curve)` | Write a `SpaceCurve` into its four rows: points, tangents, normals, binormals. |
| `spine` | The half floats of the texture, the same bits as three.js's. |
| `move_along_curve(amount)` | Move the mesh along the path, in shares of the path. |
| `path_offset`, `path_segment`, `spine_offset`, `spine_length`, `flow` | The shader's uniforms. |
| `deform(geometry, model)` | The geometry bent as the shader bends it. |
| `InstancedFlow(count, curve_count)` | A flow whose instances each ride their own curve. |
| `set_curve(i, curve)`, `move_individual_along_curve(i, offset)` | Put an instance on a curve, and move it along. |
| `deform_instance(geometry, i, model)` | The geometry bent as one instance is drawn. |

`deform` reads the texture with linear filtering and wraps at the ends of a row. The result is in the space of the shader's `transformed`. Draw it with the mesh's own matrix. `to_half_float` is three.js's `DataUtils.toHalfFloat`, which cuts off the extra bits and does not round.

To bend a `Curve3`, wrap it in a `SpaceCurve3`.

## Attribute utilities

| Function | Meaning |
|---|---|
| `merge_attributes(list)` | Join attributes end to end. |
| `interleave_attributes(list)` | Put attributes side by side in one `InterleavedBuffer`. |
| `deinterleave_attribute(a)` | Give an interleaved attribute an array of its own. |
| `deinterleave_geometry(g)` | Do that to every attribute and morph target of a geometry. |
| `estimate_bytes_used(g)` | The bytes of the arrays and the index. |
| `to_triangles_draw_mode(g, mode)` | Turn a strip or a fan into a list of triangles. |
| `merge_groups(g)` | Sort the groups by material and join the groups of one material. |
| `compute_morphed_attributes(g, influences)` | The positions and normals with the morph targets worn. |
| `compute_morphed_attributes(g, influences, carriers)` | The same, carried by the bones of a skinned mesh. |

`DrawMode` is a type: `TRIANGLES_DRAW_MODE`, `TRIANGLE_STRIP_DRAW_MODE` or `TRIANGLE_FAN_DRAW_MODE`. An index of a `BufferGeometry` holds whole triangles. So a strip or a fan is the vertices in order, or an index that you give beside the geometry.

An index takes two bytes an entry in `estimate_bytes_used`, or four bytes if an entry is 65535 or more. This is what three.js's `setIndex` chooses.

## MikkTSpace

`compute_mikktspace_tangents(geometry, negate_sign)` gives a geometry the tangents that normal-map bakers use. `generate_tangents(positions, normals, uvs, angular_threshold)` gives the tangents of a list of triangles.

three.js runs MikkTSpace as a WebAssembly build of a Rust port. This module ports Morten Mikkelsen's `mikktspace.c`, function for function, in floats. The tests compare it with the WebAssembly build, and with the C built by `gcc`. The C and the WebAssembly build agree to 5e-10.

The quad paths of the C are not ported, because three.js gives only triangles. An indexed geometry becomes non-indexed, as in three.js.

## Scene utilities

A three.js group holds its children. Here a group is a scene node, and a mesh names its node. So each function adds nodes and meshes to a `Scene` and returns the node of the group.

| Function | Meaning |
|---|---|
| `create_meshes_from_instanced_mesh(scene, i)` | One mesh for each instance, under a copy of the instanced mesh's node. |
| `create_meshes_from_multi_material_mesh(scene, assets, i)` | One mesh for each material of a mesh that wears a list, under a copy of its node. three.js: `createMeshesFromMultiMaterialMesh`. |
| `create_multi_material_object(scene, geometry, materials)` | One mesh for each material, all of one geometry. |
| `sort_instanced_mesh(scene, assets, i, keys)` | Sort the instances by one key each, and move the per-instance attributes too. |
| `reduce_vertices[func](scene, assets, root, initial)` | Fold `func` over every vertex under a node, in world space. |
| `visible_nodes(scene, root)` | The visible nodes under a node, depth first. |
| `node_vertices(scene, assets, node)` | The vertices of everything a node draws. |
| `compute_mesh_morphed_attributes`, `compute_skinned_morphed_attributes` | `compute_morphed_attributes` for a mesh and for a skinned mesh. |

`reduce_vertices` needs a current scene. Call `scene.update()` first.

## NURBS

`NURBSCurve(degree, knots, control_points, start_knot, end_knot)` is a NURBS curve. Each control point is a `Vector4` with its weight in `w`. The functions of `NURBSUtils` are there too, in doubles: `find_span`, `basis_functions`, `bspline_point`, `nurbs_derivatives` and more.

`NURBSSurface` is a `ParametricSurface`, so `parametric(surface, slices, stacks)` makes a mesh of it. `NURBSVolume.point(u, v, w)` gives a point inside a volume.

The knots must not fall, and their count must be the number of control points, plus the degree, plus one. three.js does not check this.

## Named curves

`math/curve_extras.mojo` has three.js's fourteen named curves. `ExtraCurveKind` is a type, and each curve has a function that makes it.

| Function | three.js |
|---|---|
| `granny_knot()`, `knot_curve()`, `helix_curve()` | `GrannyKnot`, `KnotCurve`, `HelixCurve` |
| `heart_curve(scale)`, `viviani_curve(scale)` | `HeartCurve`, `VivianiCurve` |
| `trefoil_knot`, `torus_knot`, `cinquefoil_knot` | `TrefoilKnot`, `TorusKnot`, `CinquefoilKnot` |
| `trefoil_polynomial_knot`, `figure_eight_polynomial_knot` | `TrefoilPolynomialKnot`, `FigureEightPolynomialKnot` |
| `decorated_torus_knot_4a`, `_4b`, `_5a`, `_5c` | `DecoratedTorusKnot4a`, `4b`, `5a`, `5c` |

## Space curves

A named curve and a NURBS curve are each a `SpaceCurve`. The functions of `math/space_curve.mojo` are three.js's base `Curve`, in doubles:

| Function | three.js |
|---|---|
| `lengths_of`, `length_of` | `getLengths`, `getLength` |
| `u_to_t` | `getUtoTmapping` |
| `points_of`, `spaced_points_of` | `getPoints`, `getSpacedPoints` |
| `point_at`, `tangent_at` | `getPointAt`, `getTangentAt` |
| `frames_of`, `frames3_of` | `computeFrenetFrames` |
| `chord_tangent` | the base `getTangent`: a chord a ten-thousandth either side |

## Where this port differs

- `compute_morphed_attributes` wears the normal targets on the normals. three.js wears the position targets on them.
- For a skinned mesh, `compute_morphed_attributes` carries a normal as a direction. three.js also moves it by the bones' translation.
- `deinterleave_geometry` does the morph targets too. three.js reads a field that a geometry does not have, and so leaves them.
- `deinterleave_attribute` keeps the instancing of an attribute on an instanced buffer. three.js loses it.
- `interleave_attributes` refuses attributes of different counts, and an item of more than four numbers.
- `sort_instanced_mesh` takes one key for each instance, and not a comparison function.
- `Flow` measures a curve over 200 runs every time. three.js uses 512 runs for the second update of one curve object.
- `generate_tangents` gives the C's default frame on a surface where every triangle is degenerate. The WebAssembly build fails there.
- `merge_groups`, `edge_split` and the modifiers refuse the input that makes three.js read past the end of an array.

## What is not ported

- `traverseGenerator` and its kin are JavaScript generators. `Scene.descendants` and `visible_nodes` walk the scene.
- `CurveModifierGPU` is the WebGPU form of `Flow`. `Flow.deform` does its work on the CPU.
