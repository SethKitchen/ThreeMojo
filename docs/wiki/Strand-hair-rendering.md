# Strand hair rendering

The strand path uses feathered ribbons with stochastic sample coverage. A kept sample writes opaque depth. A rejected sample reveals the surface behind it. This is an approximation of transparency.

It does not use sorted alpha blending. Issue [298](https://github.com/SethKitchen/ThreeMojo/issues/298) stays open until the required device and visual qualification is complete.

## Draw a groom

Use `add_groom` to grow and attach a humanoid groom. Use `add_strands` to attach a `HairGroom` that already exists. Both return `HairStrands` and create one geometry, one material and one child node. The child starts on its parent's current layers.

Its layers can then be set separately.

Pass a `LineWidth` to `add_strands`. It can name pixels or a physical length. The default is one output pixel with opacity 0.65. Opacity must be finite and between zero and one.

A width in pixels has that same width in a light map's texels. Use world units when the cast width must shrink with distance from a light.

Call `hair.shade(assets, lights, camera, ambient)` after motion or a lighting change. Give the lights and camera in the groom's local frame. `HairStrands` retains an interleaved position and color buffer. After the first installation, an update keeps the geometry and material ids and the buffer allocation.

A changed light count can resize the optical-depth workspace. A changed strand topology needs a new groom. A replaced geometry or a different store is refused before the retained buffer is written.

The renderer still builds camera-facing raster ribbons each frame. These generated raster vertices are not a persistent GPU strand simulation buffer. Use a persistent `GpuRenderer` for repeated GPU draws. Resource destruction remains subject to the scene and asset-store lifetime APIs.

## Coverage and occlusion

`STRAND_LINE_COVERAGE` is an opt-in `LineCoverage` value. `SOLID_LINE_COVERAGE` is the ordinary `LineSegments2` default. No ordinary line, cap, dash or alpha hash changes its rule.

The strand ribbon has a one-output-pixel linear feather. The cross-section is the box-filtered strip profile: its integral is the requested projected width. A subpixel ribbon has a lower plateau instead of an opaque center. Round caps use the same inner and outer radii as a radial approximation.

This cap rule reuses the strip's peak coverage. It is not an analytic filter of the physical disc area. A very short subpixel strand can therefore appear heavier than an area-preserving cap filter. The caps and neighboring segments can overlap at joints.

The approximation does not evaluate exact pixel-area intersections.

A fixed unsigned-integer spatial hash selects accepted samples. It uses world-position derivatives to set the cell size. The seed does not change with frame number or submission order. The grid repeats every 65536 cells.

Nearby fibers can share a threshold. Changes in projection or a cell boundary can change the noise during motion. There is no temporal accumulation or guaranteed noise-free silhouette.

The strand material must use opaque blending, depth testing and depth writes. It cannot use dashes. The coverage rule supplies the alpha hash itself. Opaque foreground geometry occludes accepted strand samples.

For distinct depths, reversing strand submission order leaves the image unchanged. Coincident surfaces retain the renderer's ordinary depth-tie rule. The feather can extend beyond the centerline bound, so the strand path does not use that bound to reject a visible ribbon.

The CPU and GPU call the same threshold function. Its integer operations wrap modulo 2 to the power 32. This removes sine-hash amplification. It does not prove that two devices interpolate coordinates or alpha identically.

The device parity tests include partial alpha, subpixel widths, crossing strands and camera motion. A compile-only result does not mean those device tests ran.

## Cast and self-shadow

`LineSegments2.cast_shadow` is off by default. `add_strands` turns it on. Directional, spot and point light maps include these ribbons when the node is visible on the camera's layers. They use the same feather, material opacity and integer coverage hash.

Zero opacity writes no shadow depth. A hidden node or a disabled caster writes none. The normal renderer shadow-map path is used by CPU frames and by the maps uploaded for GPU frames. This is a binary stochastic depth-map approximation, not a deep opacity map.

`HairDensity` supplies direct-light self-shadow in strand space. Each cell stores segment length times fiber diameter divided by cell volume. The current positions rebuild the grid before shading. A ray toward each distant light integrates that density, and Beer-Lambert attenuation uses the result.

The default grid has 24 cells on each axis. The permitted range is four through 64. The default physical fiber diameter is 80 micrometers. The diameter must be finite and positive.

Construction, rebuilding and optical-depth queries check both settings. A query checks its finite point and light direction first, even when the grid is empty. After changing either setting, rebuild the grid before querying it. Invalid current settings now raise an error before a query reads the grid, including an empty grid. Earlier queries did not check these settings.

Rebuilding checks the rounded sample count before conversion to signed `Int`. A nonfinite count or a positive count outside that integer range raises an error. Earlier conversions had no defined result for these values. Finite counts at most one use one sample. This check adds no fixed sample cap and preserves healthy rebuild results.

This is a coarse volume approximation. It is not strand-exact visibility. The ray skips one cell near its origin to reduce self-occlusion from its own fiber. That bias also misses nearby fibers.

The existing `HairLook.shadows` limit still bounds the darkness. The scalp-facing term remains a head-occlusion approximation. The unlit strand material does not evaluate the scene's arbitrary receiver-shadow shader.

## Motion fields

`HairSimulation.step` reuses its particle arrays. It no longer allocates a work list for each strand on every step. Every follower still has its own simulated particles. No GPU dynamics or guide-only interpolation speed claim is made.

`write` checks the strand topology before changing the groom. It rotates each rest normal with the shortest rotation of the local tangent. A reversed tangent uses a deterministic half-turn axis. The scalp-depth value is a rest-surface proxy: outward displacement reduces it, and inward displacement increases it.

This proxy is not the moving density volume. The ambient term uses that proxy. Direct self-shadow uses the rebuilt density field.

## Reference scenes and checks

The acceptance scenes are procedural. They add no scanned reference data.

- Fine silhouettes: horizontal subpixel fibers with zero, half and full opacity
- Crossing strands: two colors at distinct depths, reversed submission order and repeated frames
- Opaque occlusion: a foreground surface covering all strand samples
- Backlight: the existing Marschner TT and TRT controls with dynamic optical-depth attenuation
- Moving long hair: retained positions, changing tangents and shading fields, with a rebuilt density volume
- Cast shadows: directional, spot and point light maps with opacity, layer and visibility controls

`test_hair_coverage` checks image and depth behavior. Its short-strand control checks visibility, bounded sample energy and the response to width. It does not assert analytic cap-area conservation. `test_hair_dynamic_fields` checks projected-area conservation, moving shadow direction, motion fields and retained allocations.

`test_strand_hash` checks fixed unsigned-integer witnesses and state packing. The original wide-line, material-flag, hair and simulation suites remain compatibility controls. `test_gpu` includes device-only partial-coverage and cast-shadow parity fixtures.

The selected open-source targets remain the existing Frostbitten Hair WebGPU shading and dynamics model and TressFX guide/follower construction. They guide the visual comparisons. This implementation does not reproduce their complete renderer. The existing pinned asset revisions and licenses remain in [Converted assets](Converted-assets) and `THIRD-PARTY-NOTICES.md`.

The new coverage, density grid and procedural scenes add no third-party asset or implementation dependency.

## CPU stage costs

`bench/hair_cost_bench.mojo` times growth, upload, shading and one simulation step at several groom sizes. The [cost report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/hair-cost-298.md) records one machine's results and the decisions they support. On that machine the default groom needs about 53 milliseconds a frame on one thread.

Pass `guides_only=True` to `HairSimulation` to step the guides only. Each follower then keeps its groomed offsets in its moved guide's frame, and the step with its write costs about a third as much. Shading and its self-shadow depths run on every logical core, with the serial results. A measured frame of that groom then takes 19 milliseconds on that machine, still over a 60 frames-per-second budget.

## Hardware qualification

A 1920 by 1080 frame at 60 frames per second has a 16.667 millisecond budget. A claim must name the CPU, GPU, driver, compiler, image size, visible strand count, points per strand, coverage width, opacity, density resolution and worker count. It must include warm-up, simulation, density and shading, geometry preparation, GPU submission and transfer, rasterization and readback costs where those stages apply. Count allocations separately from uninstrumented timings.

Measure a mixed scene with body triangles and many thin strands at several worker counts. Require the same image before comparing worker throughput or pending-vertex flush cost. A result from a smaller image, a smaller groom or a compile-only check cannot qualify this target. The physical-device frame-time and selected-reference visual comparisons are still required.
