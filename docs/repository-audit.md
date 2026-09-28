# Repository audit

Review date: September 27, 2026.

Reviewed checkout: `7d04e11`, on `fix/ray-segment-distance-precision`.
The original base is `b1eac3e`.

The highest-priority work is preserving data across scene optimization and geometry operations, followed by loader bounds and animation correctness.
Several older helpers still assume the simpler data model that existed before typed attributes, interleaving, and newer material settings.

This review inventories all 351 production Mojo files, including 18 package initializers.
They contain 249,744 lines, including documentation, comments, and tables.
All 333 non-initializer production modules have an import path from the tests, according to the repository's dependency resolver.
There are 269 executable test suites and 182 compile-fail files.
Import reachability establishes coverage scope; it does not prove that every behavior has an assertion.

Detailed tracing focused on shared APIs, state transitions, numerical boundaries, and data preservation.
The review also covered build rules, CI, coverage instrumentation, fixtures, examples, benchmarks, and documentation.
Two small diagnostic programs confirmed the cases below.

The initial review did not rerun the full suite. The follow-up repair implements all 14 confirmed findings below, with regression tests. It also preserves glTF UInt32 values, handles matrix column padding, fixes byte estimates, and checks physical GPU availability. Validation results are recorded at the end of this report.

## Findings addressed

P1 means crashes, hangs, lost scene content, changed geometry or animation, or unreliable validation.
P2 means narrower data loss, API behavior, or performance work.

| Priority | Finding | Evidence | Repair in this PR |
| --- | --- | --- | --- |
| P1 | Scene batching merges different geometry. | `core/scene_optimizer.mojo`, `_same_geometry`, compares indices, attribute shapes, and only position `.data`. Two cubes with different UVs became one unique geometry in the probe. Interleaved positions also have empty `.data`. | Compare complete attribute contents through their storage-aware API. Include draw state and morph state in eligibility. |
| P1 | Scene batching removes child objects and drops object state. | `SceneOptimizer._batch` detaches every original mesh node. A child carrying points changed from present to absent. The replacement holder uses default node state and batch shadow settings. | Preserve child and co-located objects. Group only compatible visibility, layers, order, parent, and shadow state. Leave unsupported dynamic cases unchanged. |
| P1 | Material grouping merges different appearances. | `material_signature` omits shininess, specular settings, emissive intensity, normal scale, clipping, stencil, node programs, and other settings. Phong materials with different shininess produced equal signatures. | Establish one complete comparison of material rendering state, with color as the explicit per-instance exception. Avoid maintaining another partial property list. |
| P1 | glTF accessors can read before their buffer view. | `loaders/gltf.mojo`, `accessor_floats`, checks the end but not a negative accessor offset or invalid stride. A view starting at byte 4 accepted offset -4 and read the float at byte 0. | Validate offsets, strides, element layout, and both bounds before decoding. Use subtraction-based range checks where arithmetic could overflow. |
| P1 | An identity geometry transform changes relative morph normals. | `core/buffer_geometry.mojo`, `apply_matrix4`, normalizes each morph normal independently. A relative normal delta of `(0.5, 0, 0)` became `(1, 0, 0)` under the identity matrix. | Preserve the linear relationship between base normals and morph deltas. Add identity and nonuniform-transform invariance cases. |
| P1 | Cubic key optimization changes the animation. | `animation/keyframe_track.mojo`, `optimize`, removes equal values with equal nonzero tangents. For keys at 0, 1, and 2, values 0, and tangents 1, the sample at 0.5 changed from 0 to 0.1875. | Preserve tangent-based keys unless removal is proven curve-equivalent. Check Bezier handling in the same change. |
| P1 | Sampling a scalar track as a vector aborts. | `KeyframeTrack.sample_vector3` rejects quaternion tracks but accepts scalar tracks, then reads three lanes. The scalar probe hit a bounds assertion and exited by signal. | Check the supported track kind or component count before indexing. Update the documented error contract. |
| P1 | Large finite ellipse angles can hang. | `math/curve.mojo`, `ellipse_sweep`, repeatedly subtracts a turn in Float32. At `1e9` radians, subtraction cannot change the value. The compiled probe exceeded its three-second limit. | Use bounded range reduction and reject non-finite input. Preserve the existing full-turn and clockwise cases. |
| P1 | Breaking an interleaved object can discard it. | `geometries/convex_object_breaker.mojo`, `_cut`, reads position and normal `.data`. A plain cube produced two pieces; the same interleaved cube produced none. | Read packed values or use attribute accessors. Cover both indexed and non-indexed inputs. |
| P1 | Check caches omit relevant inputs. | `Makefile` hashes Mojo sources, the Makefile, the toolchain version, and affected path names. It omits fixture contents, Python tooling, package initializers, and compiler flags. `-I .` and `-I . -O0` produced the same key, `e78a96d2b9c8`. | Include file identities and contents for all consumed inputs, effective flags, and relevant tool versions. Keep partial and full runs distinct. |
| P2 | Attribute merging loses integer storage and precision. | `geometries/attribute_utils.mojo`, `merge_attributes`, converts to Float32. Integer 16,777,217 became 16,777,216. `geometries/utils.mojo`, `merge_geometries`, follows the same pattern. | Preserve compatible component types and normalized flags. Reject incompatible inputs. Share one merge implementation across geometry and attribute helpers. |
| P2 | Computation texture readback loses vertical wrapping. | `render/computation.mojo`, `current_texture`, passes `wrap_s` to a constructor that applies it to both axes. A variable with S=CLAMP and T=REPEAT returned T=CLAMP. | Copy both wrapping fields to the returned texture. |
| P2 | Affected-test parsing can miss dependencies. | `tools/affected.py`, `imported_names`, joins a multiline import before stripping comments. A comment after `vector2` hid a later `vector3` import in a direct parser probe. Git paths also use newline-delimited, quoted output. | Strip comments per line, handle supported import forms, and parse Git paths with NUL delimiters. Add focused Python tests. |
| P2 | Optimizer texture lookup bypasses checked access. | `_texture_key` directly indexes the texture list after checking only `NO_TEXTURE`. Invalid IDs can reach a bounds assertion. This finding comes from code tracing. | Use `TextureStore.get` so invalid IDs produce the documented error. |

Scene optimization now leaves morphs, restricted draw ranges, custom shadow materials, nodes with children, co-located objects, user data, and geometries without positions in place. Batches share a parent, rendering state, and indexed or nonindexed layout. The API documents its static snapshot behavior and the `keep` list for nodes that must remain addressable.

## Architecture and performance

The existing ownership model is useful: stores own assets, typed IDs name them, and scene nodes have stable identities.
CPU and GPU paths share coverage rules, blending, depth and stencil logic, and much of their shading arithmetic.
The normal-versus-color distinction and explicit units also prevent common classes of mistakes.
Retain those boundaries during the fixes.

The main architectural weakness is propagation of new state through older utilities.
For example, `attribute_utils.mojo` assumed every attribute was an unnormalized float, while `BufferAttribute` supports integer storage. The repair removes this assumption.
Material equivalence, geometry copying, export conversion, and GPU packing each maintain their own field lists.
New fields need cross-operation regression cases, not only tests of their constructor and renderer.

Several modules contain multiple stages of a pipeline:

| Module | Lines | Useful extraction boundary |
| --- | ---: | --- |
| `render/gpu.mojo` | 11,379 | Host packing, device sampling, kernels, and dispatch |
| `renderers/renderer.mojo` | 7,850 | Object collection, geometry preparation, pass orchestration |
| `materials/nodes.mojo` | 6,919 | Graph building, program validation, execution |
| `render/rasterizer.mojo` | 6,529 | Primitive setup, fragment work, scheduling |
| `materials/glsl.mojo` | 5,119 | Lexing, parsing, type checks, lowering |
| `postprocessing/composer.mojo` | 4,260 | Pass construction, dispatch, reusable image operations |

These are possible maintenance boundaries, not a reason to rewrite the renderer in this correctness batch.
Keep table-heavy files intact when length is the only reason to split them.

Performance work with concrete code locations:

1. `Renderer._sort_by` and `_sort_with` still use insertion sort for arbitrary result sizes. Preserve stable ordering and custom comparator semantics when replacing them.
2. `SceneOptimizer.to_batched_mesh` now buckets meshes by node and finds material groups by dictionary key. Geometry deduplication still uses exact comparisons. Hashed geometry candidates remain a possible improvement for very large groups.
3. `SelectionBox.select` similarly scans each object list per node. `exporters.common.world_meshes` already demonstrates local node buckets.
4. `ConvexObjectBreaker._cut` allocates a vertex-count-squared edge matrix and compares face pairs. A sparse edge representation is a candidate, subject to parity checks.
5. The GPU rasterizer assigns a pixel to a thread and walks all triangles. Tile binning is a larger performance project that needs device benchmarks and parity validation.

The earlier raycast sorting fix is already committed locally.
Its sorting-only benchmark measured 8,192 reversed hits at about 780 ms before and 0.95 ms after, best of three local runs.
That result measures sorting, not total renderer performance.

## Review coverage by subsystem

Every production module was inventoried and included in dependency and test-reachability analysis.
The following table records the main paths traced in greater depth and their disposition.

| Subsystem | Review focus | Result |
| --- | --- | --- |
| Math and units | Transforms, bounds, rays, curves, OBB assumptions, unit representation | Ellipse termination finding; earlier ray precision fix retained. |
| Cameras | Projection, view offsets, stereo construction, scene attachment | No additional confirmed fix; custom stereo projection behavior needs separate parity work. |
| Core and scene graph | Hierarchy removal, traversal, world transforms, asset ownership, optimizer, attributes | Optimizer and morph-normal findings. |
| Geometry | Merge/weld, interleaving, modifiers, surface sampling, breakup | Typed merge and interleaved breakup findings. |
| Objects and skinning | Instance lifecycle, batch ranges, skeleton transforms, morph state, reflection cleanup | Reflection visibility restoration uses `finally`; optimizer compatibility checks now preserve unsupported cases. |
| Animation | Key validation, interpolation, optimization, action loops, blending, target access | Cubic optimization and scalar-vector crash findings. |
| Materials and shaders | Material state, node execution, GLSL lowering and indexing | Partial state comparison is a confirmed weakness; interpreter performance overlaps existing PR #241. |
| Lights and shadows | World-space lighting, shadow state, physical layers, shared arithmetic | No additional confirmed defect from the traced paths. |
| Renderer | Collection, sorting, clipping, render-target state, transmission, hooks | Sorting opportunities; broad refactoring deferred until correctness changes settle. |
| Raster and GPU | Shared fragment rules, packing, texture descriptors, availability, scheduling | Physical-device detection now precedes kernel checks; host-layout checks still run without a GPU. |
| Textures and targets | Typed texels, wrapping, copies, mip levels, layered targets, computation | Computation readback wrapping finding. |
| Image and compression codecs | Representative bounds checks in PNG, ZIP, DEFLATE, Zstandard, Draco, and meshopt | Many paths have explicit bounds and output limits; exhaustive codec conformance was not rerun. |
| Model loaders | glTF accessors, sparse data, component conversion, node loading, Object JSON state | glTF bounds and UInt32 precision repairs, with direct and sparse accessor regressions. |
| Exporters | Shared world gathering, glTF accessors and typed output, Object JSON material mapping | Legacy instance behavior is documented; do not treat it as an accidental regression. |
| Post-processing | Pass insertion/removal, history storage, masks, frame conversion, dispatch | No additional confirmed defect from the traced lifecycle paths. |
| Controls and windows | Camera frames, selection, drag state, held keys, terminal cleanup, X11 resources | Selection lookup opportunity; native-platform execution remains unverified in this review. |
| Helpers and environments | World-space bounds and normals, skeleton helpers, environment prefiltering | Skeleton lookup is quadratic; lower priority than scene and geometry correctness. |
| Build, tests, coverage, docs, benchmarks | Cache keys, dependency selection, CI gates, instrumentation, fixture provenance | Cache and parser findings; fixture versions need a reproducible manifest. |

## Parity and validation gaps

Fixture generators commonly refer to three.js 0.180, some animation tests refer to r186, and the benchmark package declares `^0.170.0`.
These are different comparison baselines.
Each fixture family must declare its exact upstream version and regeneration command in a machine-readable manifest.
Existing reference fixtures are valuable, but a narrow example cannot establish general equivalence for all attribute layouts or scene states.

Some surprising behaviors are explicitly documented compatibility choices.
Examples include selection-box far-plane handling, legacy exporters writing one base geometry for an instanced mesh, and the optimizer's unimplemented instancing method.
Keep these separate from the confirmed regressions above.

GPU hardware validation is unavailable on this host. Native-window execution is also blocked: the command sandbox denies the local sockets that Xvfb needs. The permission policy refused an elevated run. CI runs this suite with Xvfb.

The repaired check uses MAX's physical-device count and reports a skip before kernel compilation. It does not treat compiler target capability as evidence of hardware.
The GPU-host suite passed all 39 tests with the repair batch.

## Coordinated implementation and validation

Write the fixes and their regression cases before running broad validation:

1. Preserve scene, material, geometry, and attribute state across optimization and conversion.
2. Repair glTF bounds, animation sampling and optimization, ellipse range reduction, and texture readback wrapping.
3. Correct cache inputs and affected-test parsing, with focused tooling regressions.
4. Run the affected functional suites together. Since build-tool changes affect selection itself, finish with the full CPU gate, compile-fail checks, documentation checks, and coverage.
5. Run GPU-host layout tests. Validate shared rendering changes on real GPU hardware when available.
6. Benchmark performance changes against matching input and output. Keep larger architecture changes separate from this repair batch.

The branch already contains the ray-to-segment precision fix and stable sorting for large raycast result sets.
Publishing follows the combined validation of the repair batch.

## Repair validation

The repair suites passed 26 regression tests. Across the repository, 5,332 CPU tests passed in 268 suites. The native-window suite compiled with warnings treated as errors. Its execution needs local sockets, which this host blocks. The standard full CPU gate remains incomplete for that reason.

All 182 compile-fail cases rejected their invalid programs. CPU lint passed for 69 non-test entry points and 338 modules. All 862 Mojo files passed formatting. The Python tooling suite passed 13 tests. The documentation check passed for 70 files.

All 39 GPU host-layout tests passed. The complete GPU parity suite compiled with Mojo 1.1.0 for the explicit CUDA target `sm_75`. Device execution is unavailable on this host.

All 268 locally runnable instrumented suites passed. The full report and final glTF regression report establish 100% line, branch, condition, and MC/DC coverage for 326 measured modules. The glTF report includes the two final Draco cases. These checks retain each module's probes in suite order. The complete coverage gate remains blocked by 329 untested native-window obligations.

The full coverage attempt exhausted the 32 GB workspace with repeated probe output. Coverage capture now uses lossless streaming compression. The reporter receives the original byte stream through named pipes. Tests verify byte-for-byte preservation, order, error propagation, and termination when a reporter exits early.

The formatting check now uses one formatter invocation for all source copies. It rejects unformatted input and leaves the original files unchanged.
