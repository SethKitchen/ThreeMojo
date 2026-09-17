# Lights

`lights/light.mojo` and `lights/lighting.mojo`. A scene holds ambient, directional, point, hemisphere and spot lights. The renderer resolves them once per frame and evaluates them at every fragment.

three.js: `AmbientLight`, `DirectionalLight`, `PointLight`, `HemisphereLight`, `SpotLight`.

## Add a light

```mojo
scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))
scene.add_light(point_light(Color(255, 200, 120), bulb_node, 0.5))
scene.add_light(hemisphere_light(Color(120, 160, 255), Color(120, 80, 40), sky_node, 0.6))
scene.add_light(spot_light(Color(255, 220, 180), beam_node, 2.0, angle=Angle(30.0, DEGREE), penumbra=0.3))
```

| Builder | Meaning |
|---|---|
| `ambient_light(color, intensity=1.0)` | The same light on every surface. |
| `directional_light(color, node, intensity=1.0, target=NO_PARENT)` | Parallel rays from the node's world position toward its target. |
| `point_light(color, node, intensity=1.0, decay=2.0, distance=0.0)` | A bulb at the node's world position. |
| `hemisphere_light(sky, ground, node, intensity=1.0)` | A sky color from the node's direction and a ground color from the other side. |
| `spot_light(color, node, intensity=1.0, distance=0.0, angle=60°, penumbra=0.0, decay=2.0, target=NO_PARENT)` | A bulb at the node's world position that shines in a cone toward its target. |

Intensity multiplies the color. Values above one are allowed. A negative intensity, decay or distance raises.

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
| `eye: Vector3` | Where the camera is, in world space. Only a highlight reads it. |
| `toward_eye: Vector3` | The one direction toward that camera, or `PERSPECTIVE_VIEW`. Normalized here. |
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

Every builder calls `validate`. `Lighting(scene)` calls it again on every light, because the fields are open and a light in a persistent scene is there to be edited.

## Highlights

A `PHONG` material adds a highlight to the diffuse term. `specular_at` sums it over the lights that have a direction: directional, point and spot. An ambient light and a hemisphere light make none. See [Materials](Materials#phong).

`blinn_phong(toward_light, toward_eye, normal, specular, shininess)` is three.js's `BRDF_BlinnPhong`, shared with the GPU kernel as `falloff` is.

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
