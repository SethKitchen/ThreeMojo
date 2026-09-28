# Voxel global illumination

`lights/vxgi_volume.mojo` voxelizes a scene into a lit volume, and `postprocessing/vxgi_node.mojo` gathers indirect light from it for each pixel. They are three.js's `VXGIVolume` and `VXGINode` from `examples/jsm/lighting/vxgi/`. The cones follow Crassin et al., "Interactive Indirect Illumination Using Voxel Cone Tracing".

```mojo
var node = VXGINode(resolution=64)
node.volume.bounces = 1
# For each frame, from a frame drawn with its depth and normals:
var gathered = node.render(view, camera_world, scene, assets, frame_id)
vxgi_light(frame, gathered, diffuse)
```

## The volume

`VXGIVolume(resolution)` holds the voxels. `update(scene, assets)` voxelizes the scene when `needs_update` is set, and injects the light when a light or a setting changes.

| Field | three.js | Default | Meaning |
|---|---|---|---|
| `resolution` | `resolution` | 128 | Voxels along the longest axis of the bounds. |
| `bounds` | `bounds` | empty | The world box to voxelize. Empty fits the scene. |
| `layers` | `layers` | layer 0 | A node must share one of these layers. |
| `bounces` | `bounces` | 1 | How many bounces the volume caches. |
| `min_opacity` | `minOpacity` | 0.1 | A less opaque triangle is skipped. |
| `max_lights` | `maxLights` | 8 | The most lights injected. |
| `max_distance` | `maxDistance` | 0 m | How far a cone reaches. Zero has no limit. |
| `step_scale` | `stepScale` | 0.5 | A cone's step, in texels of the level it reads. |
| `shadow_cone_angle` | `shadowConeAngle` | 10° | The aperture of a cone toward a light. |
| `bounce_cone_angle` | `bounceConeAngle` | 60° | The aperture of a bounce's cones. |

After an update, `world_bounds` is the box the grid covers. `opacity_at` and `radiance_at` read one texel of a level.

`validate` refuses a resolution that is not positive and negative bounces or lights. It refuses a step scale or a distance that is not usable, and an aperture that is not between 0° and 180°.

## The grid

The longest axis of the bounds gets `resolution` voxels. The resolution is at least 8. Each axis gets one more voxel on each side. Each axis is then rounded up to a multiple of the coarsest level's step. The chain has two levels fewer than the powers of two in the resolution, from one to eight.

A volume is a flat list of four floats a voxel. Level zero comes first, then each smaller level. `VxgiGrid` in `lights/vxgi_cone_tracer.mojo` gives the size and the start of each level.

## Collecting the triangles

`lights/vxgi_scene_collector.mojo` is three.js's `VXGISceneCollector`. It reads each mesh, instanced mesh and skinned mesh on a visible node. It reads the groups and the draw range as three.js reads them.

- The albedo is the material's color times its `map`, read at the triangle's centroid.
- A basic material is unlit. Its color is emissive, and its albedo is black.
- A lit material glows with `emissive` times `emissive_intensity`, times its `emissive_map`.
- A triangle that is too faint, of no size, or outside the bounds is skipped.
- A triangle with an edge longer than 16 sub-voxels is split at the middle of that edge.

## Voxelization

Each voxel has two by two by two sub-voxels. A triangle is projected along its dominant axis and rasterized conservatively. A sub-voxel column is covered when its center is within half a sub-voxel of each edge. The triangle's plane then fills the column's depth range. A voxel keeps a bit for each covered sub-voxel, and the last triangle that covers it.

The opacity along an axis is a quarter for each of the four sub-voxel columns on that axis that has a bit. The occupancy is an eighth for each bit. A coarser level combines two children along each axis, `1 - (1 - a)(1 - b)`, and averages the pairs across it. The opacity is stored in eight-bit texels, as three.js stores it.

## Light

Each occupied voxel reads the plane of its last triangle. Each directional, point or spot light gives it irradiance, times the visibility along a cone traced toward the light. The voxel's radiance is its albedo times the irradiance over pi, plus its emissive color, times its occupancy.

Each bounce traces eight cosine-weighted cones from every occupied voxel through the radiance of the pass before. A hash of the voxel turns the cones. The voxel adds its albedo times the mean of the cones. The radiance is stored in half floats, as three.js stores it.

## The cone

`trace_cone` starts one voxel from its origin. At each step it reads the level whose texel matches the cone's diameter, with linear filtering in and between levels. It reads three opacities, one for each axis, and blends them by the squared direction. It corrects the opacity for the step size and adds the radiance front to back. It stops when the cone is nearly opaque, leaves the volume, or reaches its distance.

## The pass

`VXGINode(resolution)` holds a volume and the pass's settings.

| Field | three.js | Default |
|---|---|---|
| `cone_count` | `coneCount` | 3 |
| `cone_angle` | `coneAngle` | 40° |
| `gi_intensity` | `giIntensity` | 1 |
| `ao_intensity` | `aoIntensity` | 1 |
| `ao_min_visibility` | `aoMinVisibility` | 0 |
| `ao_distance` | `aoDistance` | 1 m |
| `normal_offset` | `normalOffset` | 1.5 voxels |
| `debug`, `debug_level` | `debug`, `debugLevel` | off, 0 |
| `use_temporal_filtering` | `useTemporalFiltering` | on |

`render(view, camera_world, scene, assets, frame_id)` updates the volume. Then it gathers a `VxgiFrame`: one occlusion and one irradiance for each pixel. These are three.js's AO and GI textures.

For each pixel, the cones leave the surface one and a half voxels along the normal. Interleaved gradient noise turns them. With temporal filtering on, the noise moves with `frame_id` over a cycle of 64 frames. The mean radiance of the cones times pi is the irradiance. A pixel with no surface keeps the pass's white clear.

The debug view `VXGI_DEBUG_RADIANCE` shows the first voxel with radiance along the view. `VXGI_DEBUG_OPACITY` shows the first voxel with opacity.

`vxgi_light(frame, gathered, diffuse)` lays the pass over a drawn frame. Each pixel's light is multiplied by the occlusion. The diffuse color times the irradiance over pi is added, as three.js's `BRDF_Lambert` weighs indirect light.

## Both backends

`render/gpu_vxgi.mojo` runs every pass on the device. `GpuVxgi.update` voxelizes and lights a volume, and `GpuVxgi.render` gathers the pixels. Each kernel calls the host's own function for its voxel or its pixel.

three.js voxelizes with one thread for each triangle, with `atomicOr`. Here one thread owns one voxel and asks each triangle with `VoxelTriangle.covers`. That is the arithmetic of the host's walk, so the two backends set the same bits. `tests/test_vxgi_volume.mojo` checks the walk against the query on the host. `tests/test_gpu.mojo` compares the two backends.

## What is not ported

- three.js reads a light's shadow map for the injected visibility. Here every light is seen through a traced cone, as three.js sees a light that has no shadow map.
- The directionally filtered radiance, `directionalRadiance`, is not ported.
- three.js adds the two images to the lighting of the next draw with `builtinAOContext` and `builtinGIContext`. `vxgi_light` lays them over a drawn frame instead, so the occlusion also darkens the direct light.
- A changed light is detected by any change of its numbers. three.js compares them rounded to a few places.
- The collector reads a texture's texels as they are. three.js first scales an image to 64 by 64 pixels on a canvas.
- The normals are the frame's, or the ones `DepthView` reconstructs, as the other screen-space passes read them.
