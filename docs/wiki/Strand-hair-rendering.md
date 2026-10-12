# Strand hair rendering

The strand path uses feathered ribbons with stochastic sample coverage. A kept sample writes opaque depth. A rejected sample reveals the surface behind it. This is an approximation of transparency.

It does not use sorted alpha blending. The CPU rasterizer meets the thirteen reference requirements. Issue [298](https://github.com/SethKitchen/ThreeMojo/issues/298) stays open until a GPU device runs the parity tests and the 1080p benchmark.

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

`HairSimulation.step` reuses its particle arrays. It does not allocate a work list for each strand on every step. By default every follower has its own simulated particles. With `guides_only=True` the step lays each follower from its moved guide. No GPU dynamics are used.

`write` checks the strand topology before changing the groom. It rotates each rest normal with the shortest rotation of the local tangent. A reversed tangent uses a deterministic half-turn axis. The scalp-depth value is a rest-surface proxy: outward displacement reduces it, and inward displacement increases it.

This proxy is not the moving density volume. The ambient term uses that proxy. Direct self-shadow uses the rebuilt density field.

## Reference scenes and requirements

The strand path has thirteen measurable visual requirements. The CPU rasterizer meets all of them. The [reference report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/hair-reference-298.md) states each requirement and its measurement.

![Fine fibers and their ground truth, crossing layers, and a curtain that is self-shadowed, backlit and moving](out/hair_reference.png)

`extensions/humanoid/skeleton/head/hair/reference.mojo` builds the scenes. They are procedural and add no reference data.

- Fine silhouettes: `add_fine_silhouettes` draws tilted fibers of one width and one opacity.
- Crossing strands: `add_crossing_strands` draws two layers at distinct depths, wide or fine.
- Self-shadow, backlight and moving long hair: `HairReferenceRig` hangs four rows of long guide and follower strands. `advance` steps them in the wind.
- Cast shadow: `HairReferenceRig(receiver=True)` adds a receiver plane and a shadow-casting light.

The coverage ground truth is the same scene with solid coverage at eight times the size, box-filtered and multiplied by the opacity. `supersampled_coverage`, `coverage_samples`, `total_coverage_error` and `block_coverage_error` compare the two. The requirements are:

- Coverage: no bias beyond three binomial standard deviations. The error after a 16-pixel filter has a limit for each width from a quarter pixel to two pixels.
- Transparency: where two layers cross, the visible fractions match alpha compositing within 0.05. Submission order, worker count and repetition do not change a sample.
- Self-shadow: rows farther from a front light are darker, a denser volume is darker, and no row falls below `1 - HairLook.shadows` of the first.
- Backlight: the TT lobe brightens a backlit curtain at least 1.5 times and adds less than one percent under a front light. The optical depth decreases toward the light.
- Moving long hair: repeatable frames, covered samples within five percent of the rest pose, and a rebuilt density volume.
- Cast shadow: the receiver darkens, and more opaque strands darken it more.

`examples/hair_reference.mojo` renders the image above with the CPU rasterizer. `test_hair_reference_scenes` checks the requirements. `test_gpu` draws the same scenes on the GPU rasterizer and requires the same image. Those device tests compile for `sm_80` without a GPU, but no device has run them yet.

`test_hair_coverage` checks opaque occlusion, light-map samples for directional, spot and point lights and short subpixel caps. It does not assert analytic cap-area conservation. `test_hair_dynamic_fields` checks projected-area conservation, moving shadow direction, motion fields and retained allocations. `test_strand_hash` checks fixed unsigned-integer witnesses and state packing.

### The selected strategy

Keep stochastic coverage with opaque depth for strands, the stochastic light depth map for cast shadows and the density volume for self-shadow. This strategy is order-independent by construction, and both rasterizers share its arithmetic. It does not blend, so thin and transparent fibers show noise. There is no temporal accumulation to remove that noise.

The selected open-source reference is Frostbitten Hair WebGPU, with TressFX for guide and follower construction. Frostbitten rasterizes strands in software with analytic anti-aliasing, and blends them front to back in depth slices. This port does not reproduce that renderer. The report compares the two feature by feature. The pinned revisions and licenses remain in [Converted assets](Converted-assets) and `THIRD-PARTY-NOTICES.md`.

The strand path does not depend on the generic OIT pass of issue [251](https://github.com/SethKitchen/ThreeMojo/issues/251). That weighted blended pass keeps one layer for each draw at each pixel, and a groom is one draw that covers itself. It also selects only transparent materials, and strand materials are opaque.

## CPU stage costs

`bench/hair_cost_bench.mojo` times growth, the first upload, the four stages of shading and the simulation step and write at several groom sizes. With the runtime allocation hook it also counts the allocations of each stage on the calling thread. The [cost report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/hair-cost-298.md) records the results of two machines and the decisions they support.

The report decides two things. Guide-only interpolation stays: a laid follower costs about one seventh of a simulated follower. The hair simulation and shading stay on the CPU: strand rasterization costs about 50 to 110 times more than all the hair stages together. The GPU work is strand drawing and its device upload. On the calling thread, no per-frame allocation grows with the groom.

Pass `guides_only=True` to `HairSimulation` to step the guides only. Each follower then keeps its groomed offsets in its moved guide's frame, and the step with its write costs about a third as much. Each follower must name a guide strand with as many points. The constructor refuses a groom when a follower does not, or when the strand starts or shading fields do not match the points.

Shading, its self-shadow depths, the simulation step, the follower layout and the write all run on every logical core. Each task owns a disjoint run of strands, so the results equal the serial arithmetic bit for bit. A measured guides-only frame of the default groom takes about 7.3 milliseconds on a 12-core desktop. It takes about 64 milliseconds on a shared four-core cloud machine. That is the hair alone, not a whole 60 frames-per-second frame.

## Mixed body and strand frames

`bench/hair_strand_raster_bench.mojo` renders body triangles and the default groom at 1920 by 1080 on the CPU. It doubles the worker count from one up to every logical core. It stops with an error when a worker count's warm-up image CRC-32 differs from one worker. It does not compare pixels or depths directly, or checksum the timed frames. The [mixed frame report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/hair-strand-raster-298.md) records the original author's measurements on one machine. It does not qualify the later combined branch.

A one-pixel strand has an inner feather radius of zero. Its middle strip and two of the three triangles in each cap step then have two corners at the same place. Neither rasterizer draws a triangle of zero area. So the renderer does not emit an uncut triangle with two corners at the same pixel coordinates. The image and the depths do not change. The default groom's frame holds 60 percent fewer corners.

Each strand corner is projected once and shared by the triangles that use it. A draw with a polygon offset projects each triangle again, so its depths do not change. `test_strand_triangles` checks the triangle counts, the offset path and a strand cut by the image edge.

On that machine a whole render at 4 workers fell from about 1.8 seconds to about 0.95 seconds. Rasterization and resolve now take most of it.

## Hardware qualification

No machine meets the 1920 by 1080, 60 frames-per-second target yet. A frame at that rate has a 16.667 millisecond budget. `bench/hair_frame_bench.mojo` times a whole frame by stage. It prints the CPU model, the visible strand count and a PASS or FAIL line against that budget.

| Machine | Rasterizer | Visible strands | Median frame | Result |
|---|---|---:|---:|---|
| Intel Xeon at 2.80 GHz, 4 logical cores, shared cloud VM | CPU, 4 workers | 4,498 of 10,185 | 5,550 ms | FAIL |
| AMD Ryzen 9 5900X, 24 logical cores | CPU, 24 workers | Not counted | 791 ms | FAIL |

The [named-machine report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/hair-1080p-298.md) gives the Xeon breakdown. The simulation, density and shading take about 117 milliseconds there. Strand triangle preparation and rasterization take about 5.4 seconds. The [frame report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/hair-frame-729.md) gives the Ryzen breakdown.

The GPU result is pending. The current device rasterizer walks every primitive for each pixel, which is too slow for this scene. The repository owner reports tile-binned GPU strand drawing on a separate branch. A device run of the bench, with `gpu 1920 1080` on its command line, must give the GPU verdict.

A claim must name the CPU, GPU, driver, compiler, image size, visible strand count, points per strand, coverage width, opacity, density resolution and worker count. It must include warm-up, simulation, density and shading, geometry preparation, GPU submission and transfer, rasterization and readback costs where those stages apply. Count allocations separately from uninstrumented timings.

Measure a mixed scene with body triangles and many thin strands at several worker counts. Require the same image before comparing worker throughput or pending-vertex flush cost. A result from a smaller image, a smaller groom or a compile-only check cannot qualify this target.
