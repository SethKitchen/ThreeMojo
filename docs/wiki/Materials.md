# Materials

`materials/material.mojo`. A `Material` is a color, an optional texture, which sides to draw, an opacity, a blend policy and a kind.

three.js: `Material`, `MeshLambertMaterial`, `MeshBasicMaterial`, `side`, `opacity`, `transparent`, `map`.

## Construct one

```mojo
Material(color)
Material(color, map)
Material(color, map, side, opacity)
Material(color, map, side, opacity, blending, kind)
Material(color, kind=BASIC)
```

| Argument | Type | Default | Meaning |
|---|---|---|---|
| `color` | `Color` | required | The base color, as authored in sRGB. |
| `map` | `TextureId` | `NO_TEXTURE` | The texture that multiplies the color. |
| `side` | `Side` | `FRONT_SIDE` | Which faces are drawn. |
| `opacity` | `Float32` | `1.0` | One is opaque. Less shows what is behind. |
| `blending` | `Optional[Blending]` | inferred | `OPAQUE` or `BLEND`. |
| `kind` | `MaterialKind` | `LAMBERT` | Lit, or unlit. |

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

## Opacity and blending

`opacity` below one, or a color with alpha below 255, makes the material blend. A blended surface tests depth without writing it, and the renderer draws it after every opaque mesh, furthest first.

Pass `blending=BLEND` when a texture's own alpha needs blending and the material looks opaque. Pass `blending=OPAQUE` to force an opaque draw.

| Method | Meaning |
|---|---|
| `is_lit() -> Bool` | `kind == LAMBERT`. |
| `is_textured() -> Bool` | `map != NO_TEXTURE`. |
| `is_transparent() -> Bool` | `blending == BLEND`. |

## Errors

The constructor raises for:

- A texture id below zero that is not `NO_TEXTURE`.
- An opacity outside zero to one.
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
