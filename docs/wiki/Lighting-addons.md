# Lighting addons

This page describes five lighting addons from three.js. They are a sun, an IES spot light, a projector, a grid of light probes and an environment of one color. Each one lights a surface on both rasterizers, and the parity tests hold the two to the same pixels.

![A low sun walks around a cube and throws a long shadow](out/lighting.png)

`examples/sunlight.mojo` draws this picture.

three.js: `SunLight` and `SunLightShadow`, `IESSpotLight`, `ProjectorLight`, `LightProbeGrid` with `LightProbeGridUtils` and `LightProbeGridHelper`, and `ColorEnvironment`.

| Addon | Module | Builder |
|---|---|---|
| Sun | `lights/sun_light.mojo` | `SunLight(scene, color, intensity)` |
| IES spot light | `lights/ies_spot_light.mojo` | `ies_spot_light(color, node, ies_map, ...)` |
| Projector | `lights/projector_light.mojo` | `projector_light(color, node, ..., aspect)` |
| Light probe grid | `lights/light_probe_grid.mojo` | `LightProbeGrid(width, height, depth, ...)` |
| Grid bake | `renderers/light_probe_grid_utils.mojo` | `bake_light_probe_grid(grid, renderer, scene, assets)` |
| Grid helper | `helpers/light_probe_grid.mojo` | `LightProbeGridHelper(grid, scene, assets)` |
| Color environment | `environments/color_environment.mojo` | `color_environment(assets, color)` |

## Sun

A `SunLight` is a light with a position and no target. Its light travels from its position toward the world origin. Its shadow is two cascades, each fit to one slice of what the camera sees.

```mojo
var sun = SunLight(scene, Color(255, 250, 240), 3.0)
sun.cast_shadow = True
scene.node(sun.node).set_position(-1, 2, 1)
# For each frame, after the camera moves:
sun.update(scene, camera)
var frame = renderer.render(scene, assets, camera)
```

three.js: `new SunLight( color, intensity )`. The sun's node is its `position`, and it starts at `(0, 1, 0)`, as three.js's `Object3D.DEFAULT_UP`. `cast_shadow` is off by default, as on every three.js light. `sun.shadow` is a `LightShadow` with three.js's `SunLightShadow` defaults. The map is 1024 texels, the near plane 0.5 m and the far plane 500 m.

The constructor adds the node and two directional lights, one for each cascade. `update` gives both lights the sun's color, intensity, shadow and `cast_shadow`, and fits their cameras. `fit_sun` is three.js's `SunLightShadow.updateMatrices`:

1. It splits the view's depth halfway between an even and a logarithmic split. The depth ends at the nearer of the two far planes.
2. It turns the view's eight corners into the light's frame. Up is `+y`, or `+z` when the light is within about eight degrees of vertical.
3. Each cascade reaches from the fade start of the cascade before it to its split. Its corners are enclosed in a sphere: their middle, and the distance to the furthest.
4. It pads the radius by half a texel and rounds the middle to whole texels.
5. It puts the camera half a near plane above the caster ceiling: the highest corner, raised by the view's depth. The far plane reaches the lowest corner of the cascade.

The cascades blend as three.js's `SunShadowNode` blends them. The last tenth of each cascade fades into the next. Past the last cascade the light has no shadow. Each cascade light carries a `ShadowCascade` of `SUN_BLEND`, and `sun_reach` splits the light between the two. The shares add to one light at every depth.

three.js draws both cascades into one atlas, each tile inset by `ceil( radius ) + 1` texels. Here each cascade has a map of its own, the size of the tile less its inset: 1020 texels for a map of 1024.

`CascadeBlend` is a type, so a bare integer does not compile. `CSM_BLEND` is the blend of a `CSM`, and `SUN_BLEND` is the blend of a sun.

## IES spot light

An IES spot light is a spot light whose beam comes from a measured profile, not from a cone. `loaders/ies.mojo` reads the profile, and `ies_texture` stores it as a texture.

```mojo
var lamp = read_ies("assets/ies/full.ies")
var profile = assets.textures.add(ies_texture(lamp, IES_FLOAT))
scene.add_light(ies_spot_light(Color(255, 240, 220), lamp_node, profile, 40.0))
```

The light reads the first row of the profile at `acos(angle_cos) / pi`, linearly. `angle_cos` is the cosine of the angle between the way to the light and the light's axis. This is three.js's `IESSpotLightNode.getSpotAttenuation`. The profile replaces the cone. The light keeps its distance falloff, its shadow and its map.

`ies_spot_light` takes the numbers of `spot_light`, in the same order, after `ies_map`. The angle still sets the shadow camera and the frame of the map. With `ies_map` set to `NO_TEXTURE`, the light keeps its cone, as three.js's does when `iesMap` is null.

## Projector

A projector is a spot light whose beam is the rectangle that its shadow camera sees. `aspect` is the width of the rectangle over its height.

```mojo
var projector = projector_light(Color(255, 255, 255), beam_node, 40.0, angle=Angle(35.0, DEGREE))
projector.map = assets.textures.add(slide)
scene.add_light(projector)
```

With `aspect` set to `ASPECT_FROM_MAP`, the default, the aspect is the width of the map over its height. With no map, it is one. `projector_aspect` gives the value. The shadow camera and the frame of the map use the same aspect, so a picture keeps its proportions.

The beam fades in from the edge of the rectangle. `projector_attenuation` is three.js's `ProjectorLightNode.getSpotAttenuation`:

| Step | Arithmetic |
|---|---|
| Position | The fragment's world position through the shadow camera. Behind the light, where `w` is not positive, the beam is zero. |
| Distance | `sd_box(uv - 0.5, 0.5)`: negative inside the rectangle, zero on its edge. |
| Fade | `saturate(-2 * distance / acos(penumbra_cos))`. |
| Cap | `penumbra_cos` is `min(cos(angle * (1 - penumbra)), 0.99999)`. |

A narrow cone gives a factor above one, so most of the rectangle is at full light. A penumbra of one gives a thin band at the edge.

## Spot shapes and profiles

`SpotShape` says what shapes the beam of a spot light: `CONE_SPOT`, `IES_SPOT` or `PROJECTOR_SPOT`. It is a type, so a bare integer does not compile. The light holds it in `spot_shape`, with `ies_map` and `aspect`.

The beam of an IES spot light or a projector needs the textures, which `Lighting` does not hold. `Renderer.spot_profiles` builds one `SpotProfile` for each such light, as `Renderer.spot_light_maps` builds the maps. `Lighting` takes them in its `profiles` argument. `Renderer.render` builds them in every shading mode, because the beam is not the texture of a surface.

```mojo
var lighting = Lighting(
    scene,
    shadows=renderer.shadow_maps(scene, assets),
    spot_maps=renderer.spot_light_maps(scene, assets),
    profiles=renderer.spot_profiles(scene, assets),
)
```

`Lighting.spot_attenuation` gives the beam of one spot light. Every lit kind reads it where it read the cone. That is the diffuse term, the highlight, the toon ramp, the scattered light, the physical lobe and the Gouraud vertex.

## Light probe grid

A `LightProbeGrid` is a box around its `position`, with a light probe at each point of a regular grid in the box. Each probe holds nine spherical harmonic colors. A surface takes the probes around it and adds their irradiance at its normal to its indirect light.

```mojo
var grid = LightProbeGrid(Length(10.0, METER), Length(3.0, METER), Length(10.0, METER))
bake_light_probe_grid(grid, renderer, scene, assets)
renderer.set_light_probe_grid(grid^)
```

three.js: `new LightProbeGrid( width, height, depth, widthProbes, heightProbes, depthProbes )`. A count left at `AUTO_PROBES` is `max( 2, round( size ) + 1 )`, as in three.js. `get_probe_position(x, y, z)` gives where a probe stands. The first and the last probe on an axis stand at the faces of the box. A single probe on an axis stands at `position`. `index(x, y, z)` gives the place of a probe in `probes`, with x fastest.

| Member | three.js | Meaning |
|---|---|---|
| `width`, `height`, `depth` | the same | The size of the box. |
| `resolution_x`, `resolution_y`, `resolution_z` | `resolution` | How many probes along each axis. |
| `position` | `position` | The middle of the box. |
| `intensity` | `intensity` | What the irradiance is multiplied by. |
| `falloff` | `falloff` | How far outside the box the grid fades out. Zero applies the grid everywhere. |

`validate()` requires one stored probe per grid point and finite coefficients. Call it after edits to the counts or probe array. The renderer and `Lighting` check a nonempty grid before they adopt it. Counts must fit the shared host and device indices; invalid counts fail before allocation.

### The bake

`bake_light_probe_grid` is three.js's `LightProbeGrid.bake`. For each probe it draws the scene into a cube with `scene_cube`. Then `project_sh` reads the cube in `sample_count` directions on an equal-area Fibonacci sphere. Each sample is multiplied by the basis, and the sum by `4 pi / sample_count`.

| Option | Default | Meaning |
|---|---|---|
| `cubemap_size` | `8` | How many texels a side each cube is. |
| `near`, `far` | `0.1 m`, `100 m` | The planes of each cube. |
| `bounces` | `0` | How many more passes to draw. Each pass is lit by the grid that the pass before left. |
| `sample_count` | `512` | How many directions each cube is read in. |
| `start`, `count` | `0`, `ALL_PROBES` | Which probes to bake. |

The bake does not use the renderer's grid. A sun's shadow is fit to one view camera, and a cube has six. So `replace_sun_lights` draws each sun that casts as one directional light, as three.js's `LightProbeGridUtils` does. Its shadow camera is fit to the sphere around every mesh that casts. `restore_sun_lights` puts the sun back after the bake, also when the bake raises.

### The lookup

The lookup is three.js's `LightProbeGridNode`:

1. The surface moves half a probe spacing along its normal, so it does not read the probe behind it.
2. The position is clamped to the box. `grid_taps` gives the eight probes around it and their weights, a trilinear read.
3. Both rasterizers blend the coefficients lane by lane over the eight corners, then sum the irradiance in index order.
4. The irradiance is held at zero or above and multiplied by `intensity` and by `grid_falloff`.

`Lighting.ambient_at` adds the result to the ambient term and the light probes. `Lighting` holds the grid with the intensity already multiplied in. The intensity is not negative, so the order does not change the result.

### The helper

`LightProbeGridHelper(grid, scene, assets, sphere_size, parent)` adds a sphere at each probe. Each sphere shows the irradiance of its probe at its normal, held at zero or above. It is not divided by pi and the intensity is not applied, as in three.js's helper. The default `sphere_size` is 0.12 m, and each sphere has sixteen segments each way. Call `update(grid, assets)` after a new bake.

## Color environment

`color_environment(assets, color)` is a scene that is one color in every direction. It holds one unlit sphere of radius one with sixteen segments each way, seen from inside: three.js's `ColorEnvironment`. Draw it into a cube with `pmrem_from_scene` to get an even environment with no image file.

```mojo
var white = color_environment(assets, Color(255, 255, 255))
scene.environment = assets.cube_textures.add(pmrem_from_scene(renderer, white, assets))
```

The color is decoded from sRGB to linear light. A probe baked in it holds an irradiance of pi times the color in every direction.

## The GPU

A spot light takes sixteen floats in the light buffer. The sixteenth is where its profile begins, or `NO_SHADOW` for a cone. The profiles follow the spot light maps. Each is its shape, the slot of its IES profile in the texture table, and the sixteen floats of its frame.

The kernel reads an IES profile from the texture buffer that it already has, through the same filter as the host. `GpuRenderer.draw` refuses a profile that names a texture it did not upload.

The grid follows the profiles, as `LightProbeGrid.flatten` lays it out: the two corners, the three counts, the falloff and 27 floats for each probe. The header float `LIGHTS_GRID` says where the grid begins, or holds `NO_SHADOW`. A directional light takes fifteen floats. The last three of its cascade are its `CascadeBlend`, its fade start and where the cascade before it ends. Nothing is added to the kernel's arguments. See [GPU backend](GPU-backend).

## Errors

- `Light.validate` refuses a `SpotShape` that is none of the three. It refuses a shape other than `CONE_SPOT` on a light that is not a spot light.
- `Light.validate` refuses an `ies_map` on a light that is not an `IES_SPOT`. It refuses a projector's aspect that is negative or not finite.
- `Lighting` refuses an IES spot light with a profile, or a projector, that has no `SpotProfile`. It refuses a profile that names a missing light or a light of another shape.
- `SpotProfile` refuses a shape that is not `IES_SPOT` or `PROJECTOR_SPOT`, and an IES profile with no texture or a blank one.
- `LightProbeGrid.validate` refuses a count below one, a size that is not a positive length and a position that is not finite. It refuses an intensity or a falloff that is negative or not finite, and a coefficient that is not finite.
- `bake_light_probe_grid` refuses a range outside the grid, negative bounces, bounces over part of the grid, and a sample count below one.
- `SunLight.update` refuses a scene that does not hold the sun's cascades, a sun at the origin, and a shadow that `LightShadow.validate` refuses.
- `ShadowCascade.validate` refuses a `CascadeBlend` that is none of the two. It refuses a `SUN_BLEND` cascade that fades after it ends or ramps in before it starts.

## What is not ported

- three.js adds a `LightProbeGrid` to the scene. Here the renderer holds the grid, as it holds the LTC tables. Call `Renderer.set_light_probe_grid`.
- three.js keeps the probes in seven 3D textures of half floats and bakes them on the GPU. Here the probes are a list of 32-bit floats, and the bake draws each cube on the host. The bake has no `pass` option for ranged indirect passes.
- A grid with one probe on an axis reads that probe at every position. three.js divides by zero there.
- The bake takes the casters from the meshes alone, not from instanced, skinned or batched meshes.
- A sun's cascade cameras look along the light with this project's `up`. Their square can turn about the axis relative to three.js's, so the texels are snapped on another grid.
- `lighting/` in three.js has no package here. The grid is in `lights/`, beside `light_probe.mojo`, and its bake is in `renderers/`, because it draws.
- An IES spot light, a projector, a sun and a grid cannot be read from or written to Scene JSON.
- The color environment has no `dispose`, because the assets own the geometry and the material.
