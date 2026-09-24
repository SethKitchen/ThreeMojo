# Renderer hooks and material flags

The renderer runs hooks around a frame and draws a scene with an override material. It sorts by your functions, clears by its `auto_clear` flags and counts what it draws. A material turns dithering, alpha hash, alpha to coverage, premultiplied alpha and tone mapping on or off, and sets a blend constant. Both rasterizers read every flag.

three.js: `scene.overrideMaterial`, `onBeforeRender`, `onAfterRender`, `onBeforeShadow`, `customDepthMaterial`, `customDistanceMaterial`, `setOpaqueSort`, `setTransparentSort`, `autoClear`, `renderer.info` and `CustomToneMapping`. The `Material` fields are `visible`, `shadowSide`, `dithering`, `toneMapped`, `alphaHash`, `alphaToCoverage`, `premultipliedAlpha`, `blendColor` and `blendAlpha`.

## Hooks

A hook is a struct that conforms to the `RenderHooks` trait. Pass it to `render_with` or `render_into_with`. Replace only the methods you need. The other methods do nothing.

```mojo
struct Counter(Movable, RenderHooks):
    var drawn: Int

    def __init__(out self):
        self.drawn = 0

    def on_before_render(mut self, scene: Scene, item: RenderItem) raises:
        self.drawn += item.count

var hooks = Counter()
var image = renderer.render_with(hooks, scene, assets, camera)
```

| Method | three.js | When it runs |
|---|---|---|
| `on_before_scene(scene)` | `scene.onBeforeRender` | Before the frame is prepared. |
| `on_before_shadow(scene, item, light)` | `object.onBeforeShadow` | Once for each caster run that a shadow map drew, after the shadow maps. A point light calls it once for each face that draws the caster. |
| `on_before_render(scene, item)` | `object.onBeforeRender` | Once for each run, in draw order, before the frame is rasterized. |
| `on_after_render(scene, item)` | `object.onAfterRender` | Once for each run, in draw order, after the frame is rasterized. |
| `on_after_scene(scene)` | `scene.onAfterRender` | After the frame is drawn. |

A hook that raises stops the frame. `render` and `render_into` run `NoHooks`, which does nothing. See [Why render hooks are a trait](Why-render-hooks-are-a-trait) for the reason.

A hook reads the scene and the item. It cannot change the frame that it is called for, because the frame is prepared before the object hooks run. Change the scene between frames instead.

## Render items

A `RenderItem` is one run of a frame: what three.js puts in its render list for one object. `Frame.items` holds one item for each entry of `Frame.draws`.

| Field | Meaning |
|---|---|
| `node` | The object's node. |
| `geometry` | The object's geometry. A sprite has none, and its value is -1. |
| `material` | The material that draws the run: the scene's override when it applies. |
| `kind`, `count` | `DRAW_TRIANGLES`, `DRAW_SEGMENTS` or `DRAW_POINTS`, and how many. |
| `order` | The node's render order, three.js's `renderOrder`. |
| `z` | How far ahead of the camera the object's origin is, in meters. A larger value is further. |

## Sorts

`set_opaque_sort(method)` and `set_transparent_sort(method)` take a `RenderSort`: a function of two items that returns True when the first is drawn first. The sort is stable. Pass `None` to use the renderer's own order again.

```mojo
def nearest_first(a: RenderItem, b: RenderItem) -> Bool:
    return a.z < b.z

renderer.set_transparent_sort(nearest_first)
```

- The opaque sort orders every opaque run of every kind together. The renderer's own order puts the triangles first, then the segments, then the points, each nearest first.
- The transparent sort orders the transmissive runs, and then the blended runs, each list on its own. The renderer's own order is render order, then furthest first.

three.js gives a JavaScript comparator a number. This port gives a Mojo function a `Bool`, as `sort` does in Mojo.

## Override material

Set `scene.override_material` to a material id. Every object is then drawn with that material, three.js's `scene.overrideMaterial`.

- An object whose own material sets `allow_override = False` keeps its own material.
- Each object stays in the list that its own material chose. A transparent object drawn with an opaque override is still drawn after the opaque objects.
- The shadow maps use each object's own material.
- A line or a point refuses an override that it cannot draw, such as a `NORMALS` material. It refuses such a material of its own too.
- An opaque override leaves no run that transmits, so the frame has no transmission pass. three.js also skips the pass.

## Visible

A material with `visible = False` removes its object from the frame and from the shadow maps, three.js's `material.visible`. Nothing is counted for it and no hook runs for it.

## Shadows

| Member | three.js | Meaning |
|---|---|---|
| `Material.shadow_side` | `shadowSide` | The faces that a shadow map draws. `None` draws the faces of `side`. |
| `Mesh.custom_depth_material` | `customDepthMaterial` | The material that a directional or spot light's map draws the mesh with. |
| `Mesh.custom_distance_material` | `customDistanceMaterial` | The material that a point light's cube draws the mesh with. |

The mesh's own material still decides whether the mesh is drawn and which faces the map draws. `Material.shadow_face()` refuses a `shadow_side` that is none of the three sides.

When `shadow_side` is `None`, three.js draws the back faces of a front-sided caster, and the front faces of a back-sided caster. This port draws the faces of `side`, as it did before. Set `shadow_side` to get the three.js result.

## Automatic clear

`render_into` clears the target before it draws when `auto_clear` is True. `auto_clear_color`, `auto_clear_depth` and `auto_clear_stencil` choose the buffers. All four are True by default, as in three.js.

`clear(target, color=True, depth=True, stencil=True)` clears the target by hand with the renderer's `background`. With the scissor test on, it clears the scissor only. A cleared color also clears the pixel's normal and its data flag.

`render` always draws into a new target, so the automatic clear changes only `render_into` and `render_array_into`.

## Info

`info()` returns a `RenderInfo`: three.js's `renderer.info.render`.

| Field | Meaning |
|---|---|
| `frame` | How many frames the renderer drew. An array camera counts one frame. |
| `calls` | How many runs the last frame drew. |
| `triangles`, `lines`, `points` | How many of each the last frame drew. |

With `info_auto_reset = False`, the counts add up over frames until `reset_info()`. A supersampled frame counts into the renderer that `render` was called on.

The counts are what the rasterizer receives, after back faces are culled and the clipper cuts. three.js counts what it submits. The transmission pass, the shadow maps and the background are not counted.

## Custom tone mapping

`CUSTOM_TONE_MAPPING` maps each pixel through a [node program](Node-materials). Set `custom_tone_mapping` to the program's id. The program's `OUTPUT_NODE` reads the light with its `lit` node.

```mojo
var graph = NodeGraph()
graph.set_output(OUTPUT_NODE, graph.mul(graph.lit(), graph.float(0.5)))
renderer.custom_tone_mapping = assets.programs.add(graph.compile())
renderer.set_tone_mapping(CUSTOM_TONE_MAPPING)
```

With no program, the curve returns the light as it is, as three.js's default `CustomToneMapping` does. The exposure is not applied. `curve_program(assets)` returns the program's floats for a caller that resolves a target itself. `GpuRenderer.draw` takes the id as `custom_tone_mapping`.

## Material flags

| Field | three.js | Default | Effect |
|---|---|---|---|
| `dithering` | `dithering` | False | Adds three.js's dither of up to half a byte to the encoded color. |
| `tone_mapped` | `toneMapped` | True | False keeps the tone mapping curve off the pixels that an opaque fragment writes. |
| `alpha_hash` | `alphaHash` | False | Discards a fragment below a hashed threshold. |
| `alpha_to_coverage` | `alphaToCoverage` | False | Discards a sample that the alpha does not cover. |
| `premultiplied_alpha` | `premultipliedAlpha` | False | Multiplies the color by the alpha before the blend, and uses three.js's premultiplied factors. |
| `blend_color`, `blend_alpha` | `blendColor`, `blendAlpha` | Black, 0 | The constant that the four constant factors read. |

A flag has an effect only where three.js's shader for the primitive reads it:

| Primitive | Dithers | Hashes its alpha | Premultiplies |
|---|---|---|---|
| Mesh, except the kinds below | Yes | Yes | Yes |
| `DEPTH` and `DISTANCE` mesh | No | Yes | No |
| `NORMALS` and `SHADOW` mesh | No | No | No |
| Line | Yes | No | Yes |
| Dashed line | No | No | Yes |
| Wide line | No | No | Yes |
| Points | No | No | Yes |
| Sprite | No | Yes | No |

`tone_mapped` and `alpha_to_coverage` are read by every primitive. `RasterState` carries the five flags in five more bits of its `ops_word`, and the blend constant in four float lanes. See [Rasterization](Rasterization).

### Blend factors

`CONSTANT_COLOR_FACTOR`, `ONE_MINUS_CONSTANT_COLOR_FACTOR`, `CONSTANT_ALPHA_FACTOR` and `ONE_MINUS_CONSTANT_ALPHA_FACTOR` read `blend_color`, decoded to linear light, and `blend_alpha`. Use them in `custom_blending`. `raster_state()` refuses a `blend_alpha` outside zero to one.

With `premultiplied_alpha` on, the named modes take the factors of three.js 0.180:

| Mode | Color | Alpha |
|---|---|---|
| Normal | `src * a + dst * (1 - a)` | `a + dst_a * (1 - a)` |
| Additive | `src * a + dst` | `a + dst_a` |
| Subtractive | `dst * (1 - src * a)` | `dst_a` |
| Multiply | `src * a * dst + dst * (1 - a)` | `dst_a` |

## Scene JSON

The loader and the exporter carry `shadowSide`, `blendColor`, `blendAlpha`, `dithering`, `alphaHash`, `alphaToCoverage`, `premultipliedAlpha`, `visible` and `toneMapped` with three.js's keys. The exporter writes a key only when its value is not three.js's default. See [Scene JSON](Scene-JSON).

## Differences from three.js

- **Hooks observe.** A hook cannot change the frame that it is called for. The before hooks all run before the frame is rasterized, and the after hooks all run after it.
- **Tone mapping is per pixel.** This port applies the curve when a target is resolved. So `tone_mapped = False` works on opaque fragments only. Under a curve, a frame that holds both an untoned primitive and a blended primitive is refused. A frame with a data material and a blend is refused too.
- **Dithering is before the curve.** The dither is added to the encoded color and decoded again. With no curve, the resolved byte is the one three.js writes.
- **Alpha hash uses the world position.** A corner does not carry its object-space position, so the noise stays fixed to the world. It moves across an object that moves. Lines and points have no alpha hash.
- **Alpha to coverage is an ordered pattern.** A sample is kept where the alpha is above a four-by-four ordered threshold. With `antialias`, the average of the samples follows the alpha. The `fwidth` ramp that three.js puts on an alpha test is not ported. A shadow map approximates alpha to coverage with an alpha test of one half, as three.js does.
- **Premultiplied alpha is for blends.** An opaque fragment is written with an alpha of one, so the premultiply changes only a blended fragment.
- **The default shadow side is `side`.** See [Shadows](#shadows).
- **A custom curve is a node program.** three.js replaces a shader chunk with GLSL. The [post-processing](Post-processing) passes apply the default custom curve, which returns the light as it is.
