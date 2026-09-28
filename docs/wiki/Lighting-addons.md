# Lighting addons

This page describes five lighting addons from three.js. They are a sun, an IES spot light, a projector, a grid of light probes and an environment of one color. Each one lights a surface on both rasterizers, and the parity tests hold the two to the same pixels.

three.js: `SunLight` and `SunLightShadow`, `IESSpotLight`, `ProjectorLight`, `LightProbeGrid` with `LightProbeGridUtils` and `LightProbeGridHelper`, and `ColorEnvironment`.

| Addon | Module | Builder |
|---|---|---|
| Sun | `lights/sun_light.mojo` | `SunLight(scene, color, intensity, direction, shadow)` |
| IES spot light | `lights/ies_spot_light.mojo` | `ies_spot_light(color, node, ies_map, ...)` |
| Projector | `lights/projector_light.mojo` | `projector_light(color, node, ..., aspect)` |
| Light probe grid | `lights/light_probe_grid.mojo` | `LightProbeGrid(low, high, count_x, count_y, count_z)` |
| Grid bake | `renderers/light_probe_grid_utils.mojo` | `bake_light_probe_grid(grid, renderer, scene, assets)` |
| Grid helper | `helpers/light_probe_grid.mojo` | `LightProbeGridHelper(grid, scene, assets)` |
| Color environment | `environments/color_environment.mojo` | `color_environment(assets, color)` |

## Sun

A `SunLight` is a directional light with a direction and no target. Its shadow camera is fit to what the camera sees, so the shadow covers the view at every position.

```mojo
var sun = SunLight(scene, Color(255, 250, 240), 3.0, Vector3(1, -2, -1))
# For each frame, after the camera moves:
sun.update(scene, camera)
var frame = renderer.render(scene, assets, camera)
```

The constructor adds a node, a target node and a casting directional light to the scene. `direction` is the way the light travels. It is made unit length, and a zero or infinite direction is refused. `set_direction` turns the sun. Call `update` after it.

`update` fits the shadow camera to the view. `fit_sun` does the arithmetic:

1. It takes the camera's view volume, from the near plane to the far plane or `max_distance`, whichever is nearer.
2. It encloses the eight corners in a sphere. The middle is the average of the corners, and the radius is the distance to the furthest.
3. It rounds the radius up to a sixteenth of a meter, so the size does not change as the camera turns.
4. It snaps the middle to whole texels of the map, so the shadow does not crawl as the camera moves.
5. It puts the light `margin` beyond the sphere, back along the direction. A caster between the sun and the view then casts.

| `SunLightShadow` | Default | Meaning |
|---|---|---|
| `max_distance` | `100 m` | The furthest depth in front of the camera that the shadow covers. |
| `margin` | `50 m` | How far beyond the view's sphere the light stands. |
| `map_size` | `2048` | How many texels a side the map is. |

The light is an ordinary directional light. Its `bias` and its other shadow numbers stay as you set them. `update` sets only the map size, the four edges and the two planes.

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

A `LightProbeGrid` holds a light probe at each point of a regular grid in a box. Each probe holds nine spherical harmonic colors. A surface takes the eight probes around it and catches their irradiance at its normal.

```mojo
var grid = LightProbeGrid(Vector3(-5, 0, -5), Vector3(5, 3, 5), 4, 2, 4)
bake_light_probe_grid(grid, renderer, scene, assets)
renderer.set_light_probe_grid(grid^)
```

The first probe stands at `low` and the last at `high`. A single probe on an axis stands in the middle of that axis. `index(x, y, z)` gives the place of a probe in `probes`, with x fastest. `position(index)` gives where it stands.

### The bake

`bake_light_probe_grid` draws the scene into a cube at each probe with `scene_cube`, and projects the cube onto the nine terms with `sh_from_cube`. This is what three.js does with a `CubeCamera`. The cube is 16 texels a side by default, because the nine terms keep only the blur of the light. The bake does not use the renderer's grid, so a grid is not baked from its own light. Bake again when the lights or the objects move.

### The lookup

`grid_taps` gives the eight probes around a position and their weights. It is a trilinear read, as three.js's linear filter reads its probe textures. A position outside the box takes the probes on its nearest face. Both rasterizers blend the coefficients lane by lane over the eight corners, then sum the irradiance in index order.

The grid adds to the ambient term and the light probes in `Lighting.ambient_at`. A matte surface scatters it through `BRDF_Lambert`, and a physical surface through its diffuse term. `intensity` multiplies every coefficient. `Lighting` holds the grid with the intensity already multiplied in.

### The helper

`LightProbeGridHelper(grid, scene, assets, size, parent)` adds a sphere at each probe. Each sphere shows `1 / pi` times the irradiance of its probe, as `LightProbeHelper` shows one light probe. The shader is the same GLSL. Call `update(grid, assets)` after a new bake.

## Color environment

`color_environment(assets, color)` is a scene that is one color in every direction. It holds one unlit box, seen from inside. Draw it into a cube with `pmrem_from_scene` to get an even environment with no image file.

```mojo
var white = color_environment(assets, Color(255, 255, 255))
scene.environment = assets.cube_textures.add(pmrem_from_scene(renderer, white, assets))
```

The color is decoded from sRGB to linear light. A probe baked in it holds an irradiance of pi times the color in every direction.

## The GPU

A spot light takes sixteen floats in the light buffer. The sixteenth is where its profile begins, or `NO_SHADOW` for a cone. The profiles follow the spot light maps. Each is its shape, the slot of its IES profile in the texture table, and the sixteen floats of its frame.

The kernel reads an IES profile from the texture buffer that it already has, through the same filter as the host. `GpuRenderer.draw` refuses a profile that names a texture it did not upload.

The grid follows the profiles, as `LightProbeGrid.flatten` lays it out: the two corners, the three counts and 27 floats for each probe. The header float `LIGHTS_GRID` says where the grid begins, or holds `NO_SHADOW`. Nothing is added to the kernel's arguments. See [GPU backend](GPU-backend).

## Errors

- `Light.validate` refuses a `SpotShape` that is none of the three. It refuses a shape other than `CONE_SPOT` on a light that is not a spot light.
- `Light.validate` refuses an `ies_map` on a light that is not an `IES_SPOT`. It refuses a projector's aspect that is negative or not finite.
- `Lighting` refuses an IES spot light with a profile, or a projector, that has no `SpotProfile`. It refuses a profile that names a missing light or a light of another shape.
- `SpotProfile` refuses a shape that is not `IES_SPOT` or `PROJECTOR_SPOT`, and an IES profile with no texture or a blank one.
- `LightProbeGrid.validate` refuses a count below one, a corner that is not finite, and a box that is not wider than zero on each axis. It refuses an intensity that is negative or not finite, and a coefficient that is not finite.
- `SunLightShadow.validate` refuses a distance that is not a positive length, a negative margin and a map outside one to 8192 texels.
- `SunLight.update` refuses a scene that does not hold the sun's light.

## What is not ported

- three.js adds a `LightProbeGrid` to the scene. Here the renderer holds the grid, as it holds the LTC tables. Call `Renderer.set_light_probe_grid`.
- three.js keeps the probes in 3D textures and bakes them on the GPU. Here the probes are a list, and the bake draws each cube on the host.
- `lighting/` in three.js has no package here. The grid is in `lights/`, beside `light_probe.mojo`, and its bake is in `renderers/`, because it draws.
- `SunLight` and its fit follow the description of three.js's addon. The three.js source was not at hand to check each setting against, so its settings can differ.
- An IES spot light and a projector cannot be read from or written to Scene JSON.
- The color environment has no `dispose`, because the assets own the geometry and the material.
