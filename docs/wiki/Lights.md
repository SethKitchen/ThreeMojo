# Lights

`lights/light.mojo` and `lights/lighting.mojo`. A scene holds ambient, directional, point, hemisphere and spot lights. The renderer resolves them once per frame and evaluates them at every fragment.

![Three colored lamps and a warm bulb light one white sphere](out/lamps.png)

three.js: `AmbientLight`, `DirectionalLight`, `PointLight`, `HemisphereLight`, `SpotLight`.

## Add a light

```mojo
scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.36))
scene.add_light(point_light(Color(255, 200, 120), bulb_node, 1.57))
scene.add_light(hemisphere_light(Color(120, 160, 255), Color(120, 80, 40), sky_node, 1.88))
scene.add_light(spot_light(Color(255, 220, 180), beam_node, 6.28, angle=Angle(30.0, DEGREE), penumbra=0.3))
```

| Builder | Meaning |
|---|---|
| `ambient_light(color, intensity=1.0)` | The same light on every surface. |
| `directional_light(color, node, intensity=1.0, target=NO_PARENT)` | Parallel rays from the node's world position toward its target. |
| `point_light(color, node, intensity=1.0, decay=2.0, distance=0.0)` | A bulb at the node's world position. |
| `hemisphere_light(sky, ground, node, intensity=1.0)` | A sky color from the node's direction and a ground color from the other side. |
| `spot_light(color, node, intensity=1.0, distance=0.0, angle=60°, penumbra=0.0, decay=2.0, target=NO_PARENT)` | A bulb at the node's world position that shines in a cone toward its target. |

Intensity multiplies the color. Values above one are allowed. A negative intensity, decay or distance raises.

### Units

The light that reaches a surface is divided by pi, as three.js's `BRDF_Lambert` divides it. A white surface square on to a white light of intensity one reflects a third of it, byte 153. An intensity of about three lights it to full white. The examples use 0.79 of ambient and 2.36 of directional light, which is a quarter and three quarters of full white. `Lighting.uniform` is the identity and is not divided. See the module docstring in `lights/lighting.mojo`.

Every light has `layers`, layer zero alone by default. A camera lights its meshes with only the lights that share a layer with it. Set the layers before you add the light, or through `scene.lights`. See [Layers](Scene-graph#layers).

```mojo
var sun = directional_light(Color(255, 255, 255), lamp_node)
sun.layers.set(1)                    # only a camera watching layer one sees it
scene.add_light(sun)
```

## Ambient

A constant term added to every surface. A scene with no lights renders black. A blue ambient tints the shadows blue.

## Directional

Only the direction matters. Moving the node twice as far changes nothing. The light shines from the node's world position toward its `target`. The target is the world origin by default, as in three.js. Pass a node id as `target` to aim the light at that node. The node must not sit on its target.

Parent the node to a moving object, and the light moves with it.

## Point

The light at a surface is the intensity divided by the distance to the power of `decay`. Two is the inverse-square law. Zero is no falloff. With a `distance`, the light fades smoothly to nothing at that range.

A surface facing away from the bulb gets nothing from it. A surface on top of the bulb gets nothing either, because there is no direction.

## Hemisphere

Two colors, blended by how far a surface is turned toward the sky. A surface that faces the sky gets the sky color. A surface that faces the ground gets the ground color. A surface edge-on gets half of each. There is no Lambert cutoff: a surface facing straight down is lit by the ground, not by nothing.

The node's world position, seen from the origin, is the direction of the sky. A node straight above the origin puts the sky up. The node must not sit at the origin. One `intensity` scales both colors.

three.js: `HemisphereLight(skyColor, groundColor, intensity)`.

## Spot

A point light with a cone. The light shines from the node's world position toward its `target`, the world origin by default. `angle` is half the width of the cone, from the axis to the rim, as an `Angle`. The default is sixty degrees. The widest cone is ninety degrees. A bare number does not compile.

`penumbra` is how much of the cone is a soft rim, from zero to one. At zero the rim is hard. At one the light fades from the axis to the rim. Inside `angle * (1 - penumbra)` of the axis the surface gets the full light. Beyond `angle` it gets nothing. Between the two it gets a smooth step.

`decay` and `distance` work as they do for a point light. The node must not sit on its target.

The cone must be wide enough to resolve. The fragment compares cosines, and the cosine of a half-angle below about 0.014 degrees rounds to one in `Float32`. Such a light lit nothing on its own axis. `spot_light` and `Lighting` refuse it.

three.js: `SpotLight(color, intensity, distance, angle, penumbra, decay)` and `SpotLight.target`. The spot light's `map` and shadow are not ported.

## Rect area

`lights/ltc.mojo`. A rectangle that glows: three.js's `RectAreaLight`. The node is the rectangle's center. The rectangle shines along the node's -z, as a camera looks. Its width runs along the node's x and its height along its y. A scaled node makes a larger rectangle, as it does in three.js.

```mojo
var panel = Object3D()
panel.set_position(0, 3, 0)
panel.rotate_x(Angle(-90.0, DEGREE))
var node = scene.add(panel^)
scene.add_light(
    rect_area_light(Color(255, 220, 180), node, 2.0, Length(4.0, METER), Length(1.0, METER))
)
renderer.set_ltc_tables(load_ltc_tables())
```

`width` and `height` are `Length`s. The default is ten meters each. Zero, a negative length and a non-finite length are refused.

Only a `STANDARD` or `PHYSICAL` surface is lit by a rectangle. Every other material kind leaves it out, as only three.js's physical materials define `RE_Direct_RectArea`. The light has no falloff setting, no target and no shadow, as three.js's has none.

### The tables

A rectangle is integrated with linearly transformed cosines, the method of Heitz, Dupuy, Hill and Neubelt. The lobe of the surface at its roughness and viewing angle is fitted by a linear transform of a cosine lobe. The rectangle is pushed through the inverse transform and the cosine lobe's form factor is summed over its edges.

The transforms are three.js's own `LTC_MAT_1` and `LTC_MAT_2`, sixty-four roughnesses by sixty-four angles. They are read from `assets/ltc.f32` by `load_ltc_tables` and handed to the renderer with `set_ltc_tables`. A scene with a rectangle and no tables is refused when its lighting is resolved. A scene without one never opens the file.

The form factor already integrates the cosine over the rectangle. It is added after the reciprocal pi that scales every other lit sum, as three.js adds it. Seen straight along the normal the lookup frame takes the axis least along the normal, where GLSL would normalize a zero vector.

### The GPU

The rectangles ride in the light buffer after the spot lights, twelve floats each. Their count is in the buffer's header. When there is at least one, the two tables follow the last rectangle and the shadow maps follow the tables. Nothing is added to the kernel's arguments. See [GPU backend](GPU-backend).

## Lighting

`Lighting(scene)` resolves every light against the scene's world matrices. Build it after `scene.update()`. `Lighting(scene, visible=camera.visible_layers())` resolves only the lights on the camera's layers. Pass the camera's world position as `eye` as well, which a `PHONG` material measures its highlight from.

Pass `toward_eye` with it, the one direction toward a camera whose rays run parallel. `Renderer.render` builds both for each frame, with `camera_position(scene, camera)` and `toward_camera(scene, camera)`. Build the same two for `GpuRenderer.draw`.

| Member | Meaning |
|---|---|
| `ambient: FloatColor` | The sum of the ambient lights, linear. |
| `count()` | The number of directional lights. |
| `point_count()` | The number of point lights. |
| `hemisphere_count()` | The number of hemisphere lights. |
| `spot_count()` | The number of spot lights. |
| `intensity_at(normal, position) -> FloatColor` | The light that reaches a surface with that unit normal at that world position. |
| `specular_at(normal, position, specular, shininess) -> FloatColor` | The highlight a `PHONG` surface there sends to the camera. |
| `toon_at(normal, position, ramp) -> FloatColor` | The light that reaches a `TOON` surface, every cosine read off `ramp`. |
| `eye: Vector3` | Where the camera is, in world space. Only a highlight reads it. |
| `toward_eye: Vector3` | The one direction toward that camera, or `PERSPECTIVE_VIEW`. Normalized here. |
| `up: Vector3` | Which way is up for that camera, in world space. Only a matcap reads it. Normalized here. |
| `shade(base, normal, position) -> FloatColor` | `base` decoded from sRGB and multiplied by `intensity_at`. |
| `Lighting.uniform()` | Light of one everywhere. The identity for a hand-built triangle. |

`Lighting(scene)` raises in four cases:

- A light's numbers are refused by `validate`, on the camera's layers or not.
- A light names a node or a target the scene does not have.
- A directional, hemisphere or spot light has no direction. Its node sits at the origin, or on its target.
- A light's kind is none of the five.

The kinds are summed in one fixed order: ambient, directional, point, hemisphere, spot. Both rasterizers use that order, so their sums round alike.

## Validation

`Light.validate()` refuses the numbers a kind cannot use. An intensity, decay or distance that is negative or not finite raises. A spot angle that is not finite, not above zero, past ninety degrees, or too narrow to resolve raises. A penumbra outside zero to one raises. A number the kind never reads is not checked.

A shadow on an ambient, hemisphere or rect area light raises. A map on a light that is not a spot light raises.

Every builder calls `validate`. `Lighting(scene)` calls it again on every light, because the fields are open and a light in a persistent scene is there to be edited.

## Shadows

`lights/shadow.mojo`. A directional, a point or a spot light can cast shadows: three.js's `castShadow` and `LightShadow`, with `DirectionalLightShadow`, `PointLightShadow` and `SpotLightShadow`. A spot light can also project a picture. See [Point light shadows](#point-light-shadows) and [Spot light maps](#spot-light-maps).

```mojo
var sun = directional_light(Color(255, 255, 255), lamp_node, 3.0)
sun.cast_shadow = True
sun.shadow.map_size = 1024
sun.shadow.bias = -0.002
sun.shadow.extent = Length(8.0, METER)
scene.add_light(sun)
scene.add_mesh(Mesh(box, paint, node, cast_shadow=True, receive_shadow=True))
```

A shadow needs three things to be said, as in three.js. The light must cast. The mesh that blocks it must cast. The mesh the shadow falls on must receive. Every one is off by default.

| Property | three.js | Default | Meaning |
|---|---|---|---|
| `cast_shadow` | `castShadow` | `False` | Whether the light draws a shadow map. |
| `shadow.map_size` | `shadow.mapSize` | `512` | How many texels a side the map is. |
| `shadow.bias` | `shadow.bias` | `0.0` | Added to a fragment's depth, from zero to one across the planes, before it is compared. Negative moves it toward the light. |
| `shadow.normal_bias` | `shadow.normalBias` | `0.0` | How far a fragment is moved along its normal before it is projected, in meters. |
| `shadow.radius` | `shadow.radius` | `1.0` | How many texels the nine taps spread over. |
| `shadow.near`, `shadow.far` | `shadow.camera.near`, `far` | `0.5 m`, `500 m` | The shadow camera's planes. A point or spot light with a `distance` puts the far plane at that distance, as three.js does. |
| `shadow.extent` | `shadow.camera.left` through `top` | `5 m` | How far to each side a directional light's camera sees. A spot light's camera is as wide as its cone. |

### How a shadow is drawn

The renderer draws the scene once per casting light, from the light, keeping only the depth: `Renderer.shadow_maps`. A directional light draws through an orthographic camera at its node looking at its target, `extent` meters to each side. A spot light draws through a perspective camera twice its angle wide. Only the meshes that cast are drawn, under lit shading with no lights. A skinned, instanced or batched mesh, an LOD and a sprite cast nothing yet. A cut-out map cuts nothing out of a shadow, and a translucent surface, which claims no depth, casts none.

Each fragment the camera then shades is projected into each map, `shadow_coordinate`, and compared against the depth stored there. Nine taps in a three-by-three square of `radius` texels are compared on their own and averaged: three.js's `PCFShadowMap`, its default. A fragment off the map or past the far plane is lit. `ShadowMap.lit` is the arithmetic, from five functions the GPU kernel calls too.

Every lit sum reads the map: the diffuse term, the toon ramp, the highlight and the physical lobe. Each is scaled by what the light's map lets through, as three.js scales `directLight.color`. A surface that does not receive skips every map.

### Acne and the two biases

A surface compared against its own depth is half in shadow, because the map's depth is quantized: the stripes called shadow acne. `bias` moves the fragment toward the light in the map's depth. `normal_bias` moves it along its normal before it is projected. Both are zero by default, as three.js's are. A scene that shows stripes is the scene to raise them in, by a few thousandths and a few centimeters.

### Point light shadows

A point light draws six shadow maps, one for each face of a cube around the bulb. This is three.js's `PointLightShadow`.

```mojo
var bulb = point_light(Color(255, 240, 220), bulb_node, 40.0)
bulb.cast_shadow = True
bulb.shadow.map_size = 256
bulb.shadow.bias = -0.005
scene.add_light(bulb)
```

`Renderer.shadow_maps` draws six square views of ninety degrees from the bulb. The views look along +x, -x, +z, -z, +y and -y, with three.js's `_cubeDirections` and `_cubeUps`. Each texel keeps the distance from the bulb, from zero at the near plane to one at the far plane. A texel where nothing was drawn keeps one. `ShadowMap.cube` is true for this map.

A fragment is compared along the direction from the bulb to the fragment. `cube_face` finds the face: the largest component wins, and on a tie z wins before x, and x before y. `cube_texel` finds the texel on that face. Nine taps move the direction by `radius` texels of three.js's atlas, in the order of three.js's `getPointShadow`. A fragment nearer than the near plane or farther than the far plane is lit.

`bias` is added to the fragment's distance, in the same zero-to-one measure. `normal_bias` moves the fragment along its normal first, in meters. A light with a `distance` puts the far plane at that distance. That distance must be beyond the near plane.

This port differs from three.js in two places:

- three.js puts the six faces on one texture four faces wide and two faces high, and `cubeToUV` keeps a small border from each seam. This port keeps six separate squares, so a tap near a seam reads the next face directly.
- three.js writes the distance of each fragment with `MeshDistanceMaterial`. The rasterizer here keeps depth, so `cube_stored` calculates the distance from the depth at each texel's center.

### Spot light maps

A spot light can project a picture, as a slide projector does. This is three.js's `SpotLight.map`.

```mojo
var beam = spot_light(Color(255, 255, 255), beam_node, 40.0, angle=Angle(30.0, DEGREE))
beam.map = assets.textures.add(slide)
scene.add_light(beam)
```

The picture is seen through the spot light's shadow camera: twice the cone's angle wide, from the shadow's near plane to its far plane. The light's color is multiplied by the picture's color where a fragment lands on it. Outside the picture, the light keeps its color. The light does not need to cast a shadow. When it casts, `normal_bias` moves the fragment before it is projected, as three.js does.

`Renderer.spot_light_maps` builds the maps, one `SpotLightMap` for each spot light that names a texture. `Lighting` takes them in its `spot_maps` argument. Only `SHADE_TEXTURE` projects a map, because the other shading modes ignore every texture. A map is not a shadow: a `SHADOW` material does not show it.

Only a spot light can carry a map. `Light.validate` refuses a map on any other kind. The renderer refuses a map that is not in the texture store or is blank.

This port reads the picture at its full size, with its filter and its wrap mode. three.js can choose a smaller mip level of the picture. This port does not, because a light has no footprint to measure.

### The GPU

The maps ride in the light buffer after the lights, each its header and its depths. Each directional, point and spot light carries where its map begins. A point light's cube holds the bulb's position and its two planes where a frame would be, then six faces. The spot light maps follow the shadow maps: the texture's slot, the normal bias and the frame.

The kernel reads the picture from the texture buffer it already has. Nothing is added to the kernel's arguments. See [GPU backend](GPU-backend).

## Highlights

A `PHONG` material adds a highlight to the diffuse term. `specular_at` sums it over the lights that have a direction: directional, point and spot. An ambient light and a hemisphere light make none. See [Materials](Materials#phong).

`blinn_phong(toward_light, toward_eye, normal, specular, shininess)` is three.js's `BRDF_BlinnPhong`, shared with the GPU kernel as `falloff` is.

A `STANDARD` or `PHYSICAL` material has a GGX lobe instead. `ggx(toward_light, toward_eye, normal, f0, f90, roughness)` is three.js's `BRDF_GGX`, and `f_schlick(f0, f90, cos_vh)` its Fresnel, which `blinn_phong` reads too. `physical_at` sums the lobe, the diffuse term and the clear coat over the lights that have a direction. `indirect_at` gathers the ambient and hemisphere light. See [Materials](Materials#standard-and-physical).

### The toon ramp

A `TOON` material replaces each cosine with a tone off a ramp. `toon_at` sums that over the lights, where `intensity_at` sums the cosines themselves. Four functions do the arithmetic, and both rasterizers call them:

| Function | Meaning |
|---|---|
| `toon_coord(dot_nl)` | Where a cosine falls on the ramp: `dot * 0.5 + 0.5`. |
| `toon_step(coord)` | three.js's fallback ramp: `TOON_SHADE` below `TOON_EDGE`, one above. |
| `toon_index(coord, count)` | Which tone of a ramp of `count` tones to read. Nearest, ends clamped. |
| `toon_tone(dot_nl, ramp)` | The three above together, for a ramp that can be empty. |

A lamp the surface is turned away from still counts, because the ramp has no zero to clamp at. A point or spot light is still cut off by distance and by its cone, as three.js's `directLight.visible` is false there. An ambient light and a hemisphere light are not stepped at all. See [Materials](Materials#toon).

### Which way the camera lies

A perspective camera's rays converge on one point, so each surface sees it from its own direction. `specular_at` works that direction out from `eye` and the surface position.

An orthographic camera's rays run parallel, so every surface sees it from the same direction. Working the direction out from a position would put a false bright spot in the middle of a flat sheet. It would also move the highlight when the camera slides along its own axis, which a parallel projection cannot do.

`toward_eye_at(eye, parallel, position)` decides between the two. It returns `parallel` when that vector has a length, and the way to `eye` otherwise. `PERSPECTIVE_VIEW`, the zero vector, is what says the rays converge. Both backends call this one function.

## Rules

- Lights add in linear light. Two lamps at half strength make one at full strength.
- Nothing is clamped until the image is resolved. Two lamps can overexpose a white surface.
- Adding a light does not make the scene stale.
- A light's layers are its own, not its node's. An ambient light has no node and has layers like any other light.
- A spot light's angle is an `Angle`. `tests/compile_fail/` proves that a bare float is refused.

## Example

`examples/lamps.mojo` shows three colored directional lights and a point light carried by a turntable.
