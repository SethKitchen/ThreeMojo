# SVG renderer

`renderers/svg_renderer.mojo` draws a scene as SVG paths. It is three.js's `SVGRenderer` from `examples/jsm/renderers/`. `renderers/projector.mojo` flattens the scene into faces, lines and sprites first. It is three.js's `Projector`.

```mojo
from renderers.svg_renderer import SVGRenderer

var renderer = SVGRenderer(400, 300)
var image = renderer.render(scene, assets, camera)
Path("scene.svg").write_text(image.text())
```

The drawing is flat. Each face has one color, and nothing is textured or blended. Use it for diagrams and for output that must scale without pixels.

## The renderer

| Setting | Default | What it does |
|---|---|---|
| `set_size(width, height)` | Given to the constructor | The image size in pixels. The origin is at the center. |
| `set_precision(digits)` | -1, none | Writes each coordinate with this many digits after the point, as `toFixed` writes it. The digits must be from 0 to 100. With -1, a number is written as JavaScript writes it. |
| `set_quality(quality)` | `HIGH_QUALITY` | With `LOW_QUALITY`, each new path gets `shape-rendering="crispEdges"`. |
| `set_clear_color(color)` | White | The background that a clear shows. |
| `overdraw` | 0.5 | Pushes each edge of a face out by this many pixels. This hides the seams between faces. Zero keeps the faces as they are. |
| `auto_clear` | True | Removes the paths before each render. |
| `sort_objects`, `sort_elements` | True | Sorts the objects, and then the faces, lines and sprites, far to near. |

`render(scene, assets, camera)` returns an `SvgImage`. It holds the size, the `viewBox`, the background and the paths. `faces` and `vertices` on the renderer count what the last render drew, as three.js's `info.render` does. `SvgImage.text()` gives the SVG file.

A scene with a color background shows that color. Otherwise a render clears to the clear color. With `auto_clear` off and no background color, each render adds its paths to the paths of the last render.

## What each element becomes

The renderer joins the elements that are next to each other and have the same style into one path.

| Element | Material | Path |
|---|---|---|
| Face | `BASIC` | Filled with the color, times the first vertex color with vertex colors. |
| Face | `LAMBERT`, `PHONG`, `STANDARD`, `PHYSICAL` | Filled with the flat light of the face. See [Lighting](#lighting). |
| Face | `NORMALS` | Filled with the face normal in the camera's space, as half the normal plus one half. |
| Face | Any other kind | Filled with the color of the last face drawn. The first face gets white. |
| Face | A wireframe | Stroked one pixel wide, with round caps and joins. |
| Line | `BASIC` | Stroked one pixel wide, with round caps. A material with a gap gets `stroke-dasharray` of the dash and the gap. |
| Line | Any other kind | Nothing. |
| Sprite | `BASIC` | A square of the sprite's size on screen, filled with the color. |
| Point | `BASIC` | A square of the point's size on screen times the material's `point_size`, filled with the color. |

The opacity is the fill or stroke opacity. A material with an opacity of zero is not drawn.

A color is converted to linear and back to sRGB, as three.js converts it. It is written as `rgb(r,g,b)`. The numbers are rounded and not clamped, so a bright face can have a number above 255.

## Lighting

A lit face gets one color, at its center:

- The ambient lights are added, without their intensity.
- A directional light adds its color times its intensity times the cosine of the angle to its node's position. The light shines toward the origin, whatever its target.
- A point light adds the same, from the direction to the light. With a distance, the light is multiplied by one minus the distance over the light's distance, down to zero.
- The sum is multiplied by the material's color, and the emissive color is added.

Other lights are not read.

## The projector

`project_scene(scene, assets, projection, view, sort_objects, sort_elements)` returns a `RenderData`. It holds the visible lights and the elements. Each element is a `Renderable`. Its `kind` is `RENDERABLE_FACE`, `RENDERABLE_LINE` or `RENDERABLE_SPRITE`.

- A node that is not visible hides everything under it.
- An object is kept if its material is visible and the frustum does not cull it.
- A face is kept if it is on screen and faces the camera. A double-sided material keeps both sides.
- A line is clipped to the near and far planes.
- A point or a sprite is kept if its center is between the near and far planes.

An element's `z` is its depth. The depth of a face is the mean of its corners. The depth of a line is its farthest end. A sort puts render order first, then far to near, then the node's index.

## Same as three.js

The tests compare three renders of one scene with three.js 0.180 in Node: plain, precise and unsorted. The scene has lit, normal, vertex-colored and wireframe boxes, three kinds of lines, points and a sprite. `assets/svg_renderer/three_svg.mjs` writes the reference. The port keeps these three.js behaviors:

- A back-side material is culled like a front-side one.
- A line loop draws no closing segment. An indexed line pairs its indices, whatever its mode.
- The second end of a clipped line moves after the first end has moved.
- A point light's falloff is measured to the unit direction toward the light, not to the light. three.js uses one vector for both.
- A vertex normal, a texture coordinate or a color past its attribute reads NaN.

## Differences from three.js

- Mojo has no DOM. `SVGObject` is not ported, and `SvgImage` holds what three.js writes into its element.
- An object's id is its node's index.
- Instanced, batched and skinned meshes, and levels of detail, are not projected.
- A face or a line that names a vertex past its geometry is refused. three.js reads a vertex left from an earlier object.
- The precision is checked when it is set. three.js throws when it writes a number.
- The camera's matrices are single precision. The coordinates agree with three.js to a small part of a pixel.
