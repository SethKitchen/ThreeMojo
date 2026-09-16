# Materials

`materials/material.mojo`. A `Material` is a color, an optional texture, which sides to draw, an opacity, a blend policy, a kind and an emissive term.

three.js: `Material`, `MeshLambertMaterial`, `MeshBasicMaterial`, `side`, `opacity`, `transparent`, `map`, `emissive`, `emissiveIntensity`, `emissiveMap`.

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
| `kind` | `MaterialKind` | `LAMBERT` | Lit, or unlit. |
| `emissive` | `Color` | black | Light the surface gives off, as authored in sRGB. |
| `emissive_intensity` | `Float32` | `1.0` | Scales `emissive`. |
| `emissive_map` | `TextureId` | `NO_TEXTURE` | The texture that multiplies `emissive`. |
| `vertex_colors` | `Bool` | `False` | Multiply `color` by the geometry's `color` attribute. |

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
| `BASIC` | `MeshBasicMaterial` | The color and texture show as they are. |

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

## Opacity and blending

`opacity` below one, or a color with alpha below 255, makes the material blend. A blended surface tests depth without writing it, and the renderer draws it after every opaque mesh, furthest first.

Pass `blending=BLEND` when a texture's own alpha needs blending and the material looks opaque. Pass `blending=OPAQUE` to force an opaque draw.

| Method | Meaning |
|---|---|
| `is_lit() -> Bool` | `kind == LAMBERT`. |
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
