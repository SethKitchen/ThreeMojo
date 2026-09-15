# Lights

`lights/light.mojo` and `lights/lighting.mojo`. A scene holds ambient, directional and point lights. The renderer resolves them once per frame and evaluates them at every fragment.

three.js: `AmbientLight`, `DirectionalLight`, `PointLight`.

## Add a light

```mojo
scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))
scene.add_light(point_light(Color(255, 200, 120), bulb_node, 0.5))
```

| Builder | Arguments | Meaning |
|---|---|---|
| `ambient_light(color, intensity=1.0)` | | The same light on every surface. |
| `directional_light(color, node, intensity=1.0)` | | Parallel rays from the node's world position towards the origin. |
| `point_light(color, node, intensity=1.0, decay=2.0, distance=0.0)` | | A bulb at the node's world position. |

Intensity multiplies the color. Values above one are allowed. A negative intensity, decay or distance raises.

## Ambient

A constant term added to every surface. A scene with no lights renders black. A blue ambient tints the shadows blue.

## Directional

Only the direction matters. Moving the node twice as far changes nothing. The node's world position must not be the origin.

Parent the node to a moving object, and the light moves with it.

## Point

The light at a surface is the intensity divided by the distance to the power of `decay`. Two is the inverse-square law. Zero is no falloff. With a `distance`, the light fades smoothly to nothing at that range.

A surface facing away from the bulb gets nothing from it. A surface on top of the bulb gets nothing either, because there is no direction.

## Lighting

`Lighting(scene)` resolves every light against the scene's world matrices. Build it after `scene.update()`.

| Member | Meaning |
|---|---|
| `ambient: FloatColor` | The sum of the ambient lights, linear. |
| `count()` | The number of directional lights. |
| `point_count()` | The number of point lights. |
| `intensity_at(normal, position) -> FloatColor` | The light that reaches a surface with that unit normal at that world position. |
| `shade(base, normal, position) -> FloatColor` | `base` decoded from sRGB and multiplied by `intensity_at`. |
| `Lighting.uniform()` | Light of one everywhere. The identity for a hand-built triangle. |

`Lighting(scene)` raises in three cases. A light names a node the scene does not have. A directional light sits at the origin. A light's kind is none of the three.

## Rules

- Lights add in linear light. Two lamps at half strength make one at full strength.
- Nothing is clamped until the image is resolved. Two lamps can overexpose a white surface.
- Adding a light does not make the scene stale.

## Example

`examples/lamps.mojo` shows three colored directional lights and a point light carried by a turntable.
