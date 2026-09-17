# Fog

`core/fog.mojo`. A scene holds one fog in `scene.fog`. The renderer mixes every fragment toward the fog color by its camera-space depth. Both rasterizers apply it, in linear light.

three.js: `Fog`, `FogExp2`, `Scene.fog`.

## Set the fog

```mojo
scene.fog = linear_fog(Color(160, 170, 190), Length(2.0, METER), Length(30.0, METER))
scene.fog = exp2_fog(Color(160, 170, 190), InverseLength(0.05, PER_METER))
scene.fog = no_fog()
```

| Builder | Meaning |
|---|---|
| `no_fog()` | No fog. What a scene starts with. |
| `linear_fog(color, near=1 m, far=1000 m)` | Nothing before `near`, the fog color alone past `far`, a smooth step between. three.js's `Fog`. |
| `exp2_fog(color, density=0.00025 per m)` | `1 - exp(-(density * depth)^2)`. three.js's `FogExp2`. |

The defaults are three.js's. `near` and `far` are a `Length`. `density` is an `InverseLength`, a quantity per meter. A bare number does not compile. `tests/compile_fail/` proves it.

`linear_fog` raises when `near` is negative or `far` is not beyond `near`. `exp2_fog` raises when the density is negative.

## Fog

| Field | Meaning |
|---|---|
| `kind: FogKind` | `NO_FOG`, `LINEAR_FOG` or `EXP2_FOG`. |
| `color: Color` | The color a fragment is mixed toward, as authored in sRGB. |
| `near: Length`, `far: Length` | The edges of a linear fog. |
| `density: InverseLength` | The density of an exponential fog. |
| `is_on() -> Bool` | Whether the fog changes any fragment. |

The fields are open. The renderer checks them again each frame. It refuses an unknown kind, a negative `near`, a `far` that is not beyond `near`, or a negative density.

## Depth

The depth is the camera-space depth, three.js's `vFogDepth`. It is how far in front of the camera a fragment is, not how far from it. Two fragments at the same depth get the same fog, wherever they are across the image. The renderer takes it from the fragment's interpolated world position and the camera's view matrix.

## Where the mix happens

A fragment is shaded first: the material color, the texture, the lights and the emissive term. Then it is mixed toward the fog color. Then it is blended or written. Alpha is coverage and the fog leaves it alone.

The mix is in linear light, before the image is encoded. three.js mixes after its output color-space conversion, on the encoded color. Halfway into the fog here is half the light of each color. See [Why color is linear](Why-color-is-linear).

Every material is fogged, lit or unlit. three.js's `Material.fog` flag is not ported. The `SHADE_UV` debug view is never fogged. It shows coordinates, not light. Pixels that no triangle covers keep the background color.

## FogView

`FogView(fog, view)` is the fog seen through one camera, as both rasterizers take it. `Renderer.render` builds one each frame from `scene.fog` and the camera's view matrix. Build the same value for `GpuRenderer.draw` and `rasterize_all`.

| Member | Meaning |
|---|---|
| `FogView(fog, view)` | Resolve a fog for a view matrix. Raises for a fog the builders refuse. |
| `FogView.none()` | The view of no fog. The default of every rasterizer. |
| `is_on() -> Bool` | Whether the fog changes any fragment. |
| `depth_of(world) -> Float32` | A world position's camera-space depth. |
| `factor_at(world) -> Float32` | How much of the fog color a fragment there shows, zero to one. |
| `color: FloatColor` | The fog color, linear. |

`fog_factor(kind, depth, near, far, density)` and `fog_depth(zx, zy, zz, zw, wx, wy, wz)` are the arithmetic. The GPU kernel calls the same two functions. See [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code).

## Rules

- Setting `scene.fog` does not make the scene stale. Fog holds no transform.
- `linear_fog` with equal edges is refused. A fog needs room to rise.
- A linear fog can start at the camera, at a `near` of zero.
- A density of zero is a legal fog that changes nothing.
