# Materials

`materials/material.mojo`. A `Material` is a color, an optional texture, which sides to draw, an opacity, a blend policy, a kind and an emissive term.

three.js: `Material`, `MeshLambertMaterial`, `MeshPhongMaterial`, `MeshBasicMaterial`, `MeshNormalMaterial`, `MeshDepthMaterial`, `side`, `opacity`, `transparent`, `map`, `emissive`, `emissiveIntensity`, `emissiveMap`, `specular`, `shininess`, `alphaMap`, `alphaTest`.

## Construct one

```mojo
Material(color)
Material(color, map)
Material(color, map, side, opacity)
Material(color, map, side, opacity, blending, kind)
Material(color, kind=BASIC)
Material(color, emissive=Color(255, 200, 120))
Material(color, emissive=Color(255, 255, 255), emissive_intensity=0.5, emissive_map=glow)
```

| Argument | Type | Default | Meaning |
|---|---|---|---|
| `color` | `Color` | required | The base color, as authored in sRGB. |
| `map` | `TextureId` | `NO_TEXTURE` | The texture that multiplies the color. |
| `side` | `Side` | `FRONT_SIDE` | Which faces are drawn. |
| `opacity` | `Float32` | `1.0` | One is opaque. Less shows what is behind. |
| `blending` | `Optional[Blending]` | inferred | `OPAQUE` or `BLEND`. |
| `kind` | `MaterialKind` | `LAMBERT` | Lit, unlit, or showing data. |
| `emissive` | `Color` | black | Light the surface gives off, as authored in sRGB. |
| `emissive_intensity` | `Float32` | `1.0` | Scales `emissive`. |
| `emissive_map` | `TextureId` | `NO_TEXTURE` | The texture that multiplies `emissive`. |
| `vertex_colors` | `Bool` | `False` | Multiply `color` by the geometry's `color` attribute. |
| `alpha_map` | `TextureId` | `NO_TEXTURE` | A texture whose green channel thins the surface. |
| `alpha_test` | `Float32` | `0.0` | The alpha a fragment must reach to be drawn. |
| `specular` | `Color` | black | How much light a `PHONG` surface sends to the camera. |
| `shininess` | `Float32` | `0.0` | How tight that highlight is. |

## Side

| Value | Draws |
|---|---|
| `FRONT_SIDE` | Faces that point at the camera. The default, as in three.js. |
| `BACK_SIDE` | Faces that point away. The inside of a closed mesh. |
| `DOUBLE_SIDE` | Both. Use it for an open surface. |

A face seen from behind is lit with its normal flipped. A mirrored mesh, with a negative world determinant, keeps the same convention.

## Kind

| Value | three.js | Meaning |
|---|---|---|
| `LAMBERT` | `MeshLambertMaterial` | The lights reach the surface. |
| `PHONG` | `MeshPhongMaterial` | Lit, and with a highlight that follows the camera. |
| `BASIC` | `MeshBasicMaterial` | The color and texture show as they are. |
| `NORMALS` | `MeshNormalMaterial` | The normal the camera sees, as a color. |
| `DEPTH` | `MeshDepthMaterial` | How far away the surface is, as a gray. |

`is_lit()` is true for the first two. `is_data()` is true for the last two, which show data rather than light. See [Data materials](#data-materials).

## Phong

A Phong surface is a Lambert surface with a highlight. Build one with its own function:

```mojo
var plastic = assets.materials.add(phong_material(Color(200, 60, 60)))
var glossy = assets.materials.add(
    phong_material(Color(60, 120, 200), bark, Color(255, 255, 255), 60.0)
)
```

`phong_material(color, map=NO_TEXTURE, specular=Color(17, 17, 17), shininess=30.0, side=FRONT_SIDE, opacity=1.0, blending=None)`.

The specular and the shininess are three.js's own defaults. `Material(color, kind=PHONG)` is the same surface with no highlight, because this project's defaults are neutral and three.js's are not.

| Property | Meaning |
|---|---|
| `specular` | How much light the surface sends toward the camera, as authored in sRGB. |
| `shininess` | How tight the highlight is. Zero spreads it over the whole lit side. |

### What the highlight is

The highlight is light bouncing off the surface rather than coming out of it. So `specular` tints it and `color` does not, and neither does the texture. A red plastic ball has a white highlight.

It is Blinn's half vector, as three.js uses: the highlight is brightest where the normal points half way between the light and the camera. Move the camera and the highlight moves. The diffuse term does not, because a Lambert term cannot.

Only the lights that have a direction make one. An ambient light has none, and a hemisphere light is an ambient term with a gradient. Both light a Phong surface diffusely and nothing more.

`blinn_phong(toward_light, toward_eye, normal, specular, shininess)` is the arithmetic, in `lights/lighting.mojo`. The GPU kernel calls the same function. `Lighting.specular_at(normal, position, specular, shininess)` sums it over the lights.

### One difference from three.js

three.js divides both its diffuse and its specular term by pi. The diffuse term here does not, so the specular term drops the same factor. That keeps the ratio of highlight to diffuse exactly three.js's, which is what decides how a surface looks. See the module docstring in `lights/lighting.mojo`.

The highlight can exceed one. That is what a highlight is. Set a tone mapping curve to bring it back. See [Render target](Render-target-and-framebuffer#tone-mapping).

three.js's `specularMap`, which varies the highlight per texel, is not ported.

## Data materials

A normal material and a depth material write bytes that a display must show as they are. Build one with its own function:

```mojo
var shown = assets.materials.add(normal_material())
var seen = assets.materials.add(depth_material())
var pane = assets.materials.add(normal_material(DOUBLE_SIDE, 0.5))
var cut = assets.materials.add(depth_material(mask, FRONT_SIDE, 1.0, BLEND))
```

| Builder | Meaning |
|---|---|
| `normal_material(side=FRONT_SIDE, opacity=1.0, blending=None, alpha_test=0.0)` | The view-space normal as a color. |
| `depth_material(map=NO_TEXTURE, side=FRONT_SIDE, opacity=1.0, blending=None, alpha_map=NO_TEXTURE, alpha_test=0.0)` | The depth as a gray. |

Both take `side`, `opacity` and `blending`, and nothing else. A depth material also takes a `map`.

### Normals

`NORMALS` writes the normal as three.js's `packNormalToRGB` does. Each component is halved and moved up by a half. A surface square on to the camera is (128, 128, 255). One turned to the camera's right is redder. One turned up is greener.

The normal is the one the camera sees, three.js's `vNormal`, not the one the world sees. Moving the camera changes the colors of a surface that never moved. The renderer carries each normal through the view matrix for this material alone.

A face seen from behind shows its normal flipped, as it is lit flipped. The normal is made unit length at every fragment, as it is for a lit surface. A geometry with no normals falls back to its face normal.

### Depth

`DEPTH` writes one minus the window-space depth in every channel. The near plane is white and the far plane is black. This is three.js's `MeshDepthMaterial` under `BasicDepthPacking`. The other packings are not ported.

Set the camera's `near` and `far` close together to see anything. A range of one to a thousand meters puts almost every surface within a few levels of black.

A map's alpha cuts the surface out, as three.js's does. Its color is not read. Pass `blending=BLEND` for the cut to show what is behind it.

### What they refuse

Neither shader reads a color, an emissive term or the vertex colors. A material of either kind refuses all three rather than ignoring them. Pass opaque white as the color, or use the builders, which do. A normal material refuses a map and an alpha map as well. Both take an alpha test, as three.js's do.

Neither is lit, fogged nor tone mapped. A veil of light over a normal, or a curve that compresses it, would make the image lie about its own numbers. Both rasterizers decide this per pixel. See [Why a normal is not a color](Why-a-normal-is-not-a-color).

## Vertex colors

`vertex_colors=True` multiplies the material color by the geometry's `color` attribute at every vertex. three.js: `Material.vertexColors`. The attribute holds three or four floats per vertex, in linear light. A fourth float multiplies the alpha.

The colors are interpolated across each face. Then the lights and the texture apply, as they apply to the material color. A vertex alpha below one blends only when the material blends. Pass `blending=BLEND` for that.

The renderer raises when the material asks and the geometry has no `color` attribute. It raises when the attribute has neither three nor four floats per vertex, or fewer colors than vertices. A `color` attribute on a geometry whose material does not ask is ignored.

```mojo
var tints = List[Float32]()
for vertex in range(count):
    var linear = FloatColor(srgb=Color(255, 128, 0))
    tints.append(linear.r)
    tints.append(linear.g)
    tints.append(linear.b)
geometry.set_attribute(String(COLOR), BufferAttribute(tints^, 3))
var painted = assets.materials.add(Material(Color(255, 255, 255), vertex_colors=True))
```

## Emissive

The emissive term is light the surface gives off. Both rasterizers add it after the lights, and the lights do not change it. A glowing surface shows in a dark scene. The term adds to red, green and blue. It does not change alpha.

`emissive` is the color, as authored in sRGB. `emissive_intensity` scales it. `emissive_map` multiplies it per texel, so a map over a black `emissive` adds nothing, as in three.js. `SHADE_LIT` ignores the map and keeps the color.

An emissive map must ignore its alpha. Build it with `alpha=IGNORED`, or copy one with `ignoring_alpha()`. The renderer refuses a map that reads alpha as coverage, because filtering would darken it wherever its alpha is low. See [Textures](Textures#alpha).

The emissive map is sampled at the same coordinate as `map`. When a material names both, their transforms must agree. See [Textures](Textures#transform).

The term changes the surface's own appearance. It does not light nearby objects, and it does not bloom.

A `BASIC` material refuses an emissive term. three.js's `MeshBasicMaterial` has none. An unlit surface already shows its own color.

```mojo
var lamp = assets.materials.add(
    Material(Color(40, 40, 40), emissive=Color(255, 220, 160), emissive_intensity=0.8)
)
var glow = assets.textures.add(texture_from(image, alpha=IGNORED))
var screen = assets.materials.add(
    Material(Color(0, 0, 0), emissive=Color(255, 255, 255), emissive_map=glow)
)
```

## Alpha map and alpha test

An alpha map thins a surface and an alpha test cuts it away. Together they make a shape out of a rectangle: a leaf, a fence, a chain link.

```mojo
var mask = assets.textures.add(
    Texture(width, height, bytes, REPEAT, NEAREST, LINEAR, False, IGNORED)
)
var leaf = assets.materials.add(
    Material(Color(255, 255, 255), bark, alpha_map=mask, alpha_test=0.5)
)
```

three.js: `Material.alphaMap` and `Material.alphaTest`.

### The map

The map's *green* channel multiplies the surface's alpha. three.js reads `.g` and nothing else. Red, blue and the map's own alpha say nothing. The map multiplies whatever alpha reached it, so a half opacity through a half map is a quarter.

An alpha map holds data, not color. Build it with `color_space=LINEAR` and `alpha=IGNORED`. The renderer refuses any other pair, on both backends. A linear texture hands back the byte as it was stored, which is what a coverage means. An sRGB one would turn a byte of 128 into 0.216. A coverage-weighted filter would weight the green by an alpha that means nothing.

The map is sampled at the same coordinate as `map` and `emissive_map`. A material naming more than one must give them all one transform. See [Textures](Textures#transform).

`SHADE_LIT` and `SHADE_UV` ignore the map, as they ignore every texture.

### The test

`alpha_test` is the alpha a fragment must reach to be drawn at all. Zero, the default, draws every fragment, as in three.js. Above zero, a fragment whose alpha falls below it is thrown away.

A thrown-away fragment writes no color and claims no depth. So the hole shows whatever is behind it. Without the test, a fully transparent fragment still claims the depth and hides what is behind it.

The test reaches every kind, a translucent surface and a data material included. The `SHADE_UV` view cuts nothing out: it shows the nearest surface's coordinates and samples no texture.

The comparison is strict, as three.js's is. A fragment whose alpha equals the test survives.

## Opacity and blending

`opacity` below one, or a color with alpha below 255, makes the material blend. A blended surface tests depth without writing it, and the renderer draws it after every opaque mesh, furthest first.

Pass `blending=BLEND` when a texture's own alpha needs blending and the material looks opaque. Pass `blending=OPAQUE` to force an opaque draw.

| Method | Meaning |
|---|---|
| `is_lit() -> Bool` | `kind` is `LAMBERT` or `PHONG`. |
| `has_highlight() -> Bool` | A `PHONG` material whose `specular` is not black. |
| `specular_light() -> FloatColor` | The specular color decoded to linear light. |
| `is_data() -> Bool` | `kind` is `NORMALS` or `DEPTH`. |
| `has_alpha_map() -> Bool` | `alpha_map != NO_TEXTURE`. |
| `is_alpha_tested() -> Bool` | `alpha_test > 0`. |
| `is_textured() -> Bool` | `map != NO_TEXTURE`. |
| `is_transparent() -> Bool` | `blending == BLEND`. |
| `is_emissive() -> Bool` | Whether the emissive color at its intensity adds any light. |
| `emissive_light() -> FloatColor` | The emissive color decoded to linear light, times the intensity. |

## Errors

The constructor raises for:

- A texture id or an emissive map id below zero that is not `NO_TEXTURE`.
- An opacity outside zero to one.
- A negative emissive intensity.
- An emissive color or map on a `BASIC` material.
- A color that is not opaque white on a `NORMALS` or `DEPTH` material.
- An emissive term or vertex colors on either of those two kinds.
- A map or an alpha map on a `NORMALS` material.
- An alpha map id below zero that is not `NO_TEXTURE`.
- An alpha test outside zero to one, or not finite.
- A negative or non-finite shininess.
- A specular that is not black, or a positive shininess, on a kind that is not `PHONG`.

`Renderer.prepare` raises for an emissive map that reads its alpha as coverage.
- A `Side`, `Blending` or `MaterialKind` that is none of its named values. The type stops a bare integer at compile time. `is_valid` stops `Side(99)` at run time.

## MaterialStore

`assets.materials.add(material)` returns a `MaterialId`. `get(id)` returns a copy.

## Example

```mojo
var glass = assets.materials.add(
    Material(Color(255, 80, 80), NO_TEXTURE, DOUBLE_SIDE, 0.45)
)
var sky = assets.materials.add(Material(Color(120, 170, 255), kind=BASIC))
```
