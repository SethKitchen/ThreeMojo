# Materials

`materials/material.mojo`. A `Material` is a color, an optional texture, which sides to draw, an opacity, a blend policy, a kind and an emissive term.

![A white highlight follows the camera around a red sphere](out/phong.png)

three.js: `Material`, `MeshLambertMaterial`, `MeshPhongMaterial`, `MeshToonMaterial`, `MeshMatcapMaterial`, `MeshBasicMaterial`, `MeshNormalMaterial`, `MeshDepthMaterial`, `LineBasicMaterial`, `LineDashedMaterial`.

Properties: `side`, `opacity`, `transparent`, `map`, `emissive`, `emissiveIntensity`, `emissiveMap`, `specular`, `shininess`, `alphaMap`, `alphaTest`, `gradientMap`, `matcap`, `wireframe`, `dashSize`, `gapSize`, `scale`.

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
| `opacity` | `Float32` | `1.0` | One is opaque. Less shows what is behind, when `transparent`. |
| `blending` | `Optional[Blending]` | follows `transparent` | `OPAQUE` or `BLEND`. |
| `transparent` | `Bool` | `False` | Whether the surface blends over what is behind it, three.js's `transparent`. |
| `kind` | `MaterialKind` | `LAMBERT` | Lit, unlit, or showing data. |
| `emissive` | `Color` | black | Light the surface gives off, as authored in sRGB. |
| `emissive_intensity` | `Float32` | `1.0` | Scales `emissive`. |
| `emissive_map` | `TextureId` | `NO_TEXTURE` | The texture that multiplies `emissive`. |
| `vertex_colors` | `Bool` | `False` | Multiply `color` by the geometry's `color` attribute. |
| `alpha_map` | `TextureId` | `NO_TEXTURE` | A texture whose green channel thins the surface. |
| `alpha_test` | `Float32` | `0.0` | The alpha a fragment must reach to be drawn. |
| `specular` | `Color` | black | How much light a `PHONG` surface sends to the camera. |
| `shininess` | `Float32` | `0.0` | How tight that highlight is. |
| `gradient_map` | `TextureId` | `NO_TEXTURE` | The ramp a `TOON` surface steps through. |
| `matcap` | `TextureId` | `NO_TEXTURE` | The image a `MATCAP` surface is looked up in. |
| `wireframe` | `Bool` | `False` | Draw the lines of the triangles rather than fill them. |
| `dash_size` | `Length` | zero | How long each dash of a line is. See [dashed lines](Lines#dashed-lines). |
| `gap_size` | `Length` | zero | How long the gap after each dash is. Zero is a solid line. |
| `dash_scale` | `Float32` | `1.0` | What the distance along the line is multiplied by first. |

## Side

| Value | Draws |
|---|---|
| `FRONT_SIDE` | Faces that point at the camera. The default, as in three.js. |
| `BACK_SIDE` | Faces that point away. The inside of a closed mesh. |
| `DOUBLE_SIDE` | Both. Use it for an open surface. |

A `DOUBLE_SIDE` face seen from behind is lit with its normal flipped. This is three.js's rule: its shader flips the normal under `DOUBLE_SIDED` and nowhere else. A `BACK_SIDE` face keeps the normal it was given. three.js turns the winding round for `BackSide`, not the normal. The inside of a box lit from outside is bright on the wall the light reaches through and dark on the wall it sees. A mirrored mesh, with a negative world determinant, keeps the same convention.

## Kind

| Value | three.js | Meaning |
|---|---|---|
| `LAMBERT` | `MeshLambertMaterial` | The lights reach the surface. |
| `PHONG` | `MeshPhongMaterial` | Lit, and with a highlight that follows the camera. |
| `BASIC` | `MeshBasicMaterial`, `LineBasicMaterial` | The color and texture show as they are. The kind a [line](Lines) is drawn with. |
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

The specular and the shininess are three.js's own defaults. `Material(color, kind=PHONG)` gives the same surface a black specular, because this project's defaults are neutral and three.js's are not.

A black specular is a base reflectance of zero. It is not a highlight switched off. three.js's Fresnel factor rises toward one at a grazing angle, whatever the surface reflects head on. So a Phong surface with a black specular still catches a dim rim where a Lambert surface catches nothing. `has_highlight()` asks the kind alone for that reason.

| Property | Meaning |
|---|---|
| `specular` | How much light the surface sends toward the camera, as authored in sRGB. |
| `shininess` | How tight the highlight is. Zero spreads it over the whole lit side. |

### What the highlight is

The highlight is light bouncing off the surface rather than coming out of it. So `specular` tints it and `color` does not, and neither does the texture. A red plastic ball has a white highlight.

It is Blinn's half vector, as three.js uses: the highlight is brightest where the normal points half way between the light and the camera. Move the camera and the highlight moves. The diffuse term does not, because a Lambert term cannot.

Only the lights that have a direction make one. An ambient light has none, and a hemisphere light is an ambient term with a gradient. Both light a Phong surface diffusely and nothing more.

`blinn_phong(toward_light, toward_eye, normal, specular, shininess)` is the arithmetic, in `lights/lighting.mojo`. The GPU kernel calls the same function. `Lighting.specular_at(normal, position, specular, shininess)` sums it over the lights.

### The reciprocal of pi

three.js divides both its diffuse and its specular term by pi, and so does this: `Lighting` scales every sum of arriving light by `RECIPROCAL_PI`. A white surface square on to a white light of intensity one reflects a third of it. A light meant to read as full white has an intensity of about three, as in three.js's own examples. See [Lights](Lights#units).

The highlight can exceed one. That is what a highlight is. Set a tone mapping curve to bring it back. See [Render target](Render-target-and-framebuffer#tone-mapping).

three.js's `specularMap`, which varies the highlight per texel, is not ported.

## Toon

A toon surface is lit like a Lambert one, then stepped through a ramp instead of faded. That is what makes the cartoon look. Build one with its own function:

```mojo
var cel = assets.materials.add(toon_material(Color(200, 60, 60)))
var banded = assets.materials.add(
    toon_material(Color(60, 120, 200), bark, ramp)
)
```

`toon_material(color, map=NO_TEXTURE, gradient_map=NO_TEXTURE, side=FRONT_SIDE, opacity=1.0, blending=None)`.

three.js: `MeshToonMaterial`, `gradientMap`.

| Property | Meaning |
|---|---|
| `gradient_map` | The ramp to step through, or `NO_TEXTURE` for three.js's fallback. |

### How the ramp is read

The cosine between the surface normal and the direction toward a light picks a tone. three.js reads its ramp at `dot(N, L) * 0.5 + 0.5`, so the whole range of angles maps onto the whole ramp.

**A lamp the surface is turned away from still counts.** A Lambert term clamps the cosine at zero. A ramp has no zero to clamp at. So a surface facing away reads the ramp's left end rather than nothing, which is what keeps the shaded side flat.

How dark that side is belongs to the ramp. three.js's fallback puts its left end at 0.7, so a default toon surface never goes black. A ramp of your own can put zero there, and then it does. A toon surface with no light reaching it is black either way.

With no `gradient_map`, three.js's fallback applies: two tones, with the edge where the coordinate reads 0.7, and the low tone at 0.7 as well.

three.js softens that edge with `fwidth`, a screen-space derivative. The edge is hard here because that antialiasing is not implemented yet. The architecture does not forbid it: this rasterizer already evaluates a triangle's varyings at neighboring pixels, which is how `mip_level` picks a level. The difference shows on the single row of fragments the edge crosses.

### The gradient map is a lookup table

A ramp must be exactly one row high, and that row is read left to right, red channel only. Nothing is filtered and nothing is wrapped: a ramp of three texels gives three flat tones, each covering a third of the range. three.js builds its own gradient maps `NearestFilter` and `ClampToEdgeWrapping` for the same reason.

The height is a rule and not a convention. three.js reads its gradient map at `vec2(coord, 0.0)`. Under this project's texture convention a `v` of zero is the *bottom* row, because every sampler flips with `1 - v`. So "the first stored row" and "`v` of zero" name different rows in a taller image. There is no way to tell which one the author meant, and one row has only one, so a taller image is refused.

So a ramp holds data, and must say so twice, as an alpha map must. Build it `LINEAR`, or the sRGB curve changes what its bytes mean. Build it `IGNORED`, or its own alpha weights them.

A ramp is read at no surface coordinate. So its own `repeat`, `offset` and `rotation` are never applied. They are never asked to agree with the material's other maps either. See [Texture transforms](Textures#transform).

### What a toon material does not have

A highlight. three.js's `MeshToonMaterial` has no `specular` and no `shininess`, and a material of this kind refuses both, as every other non-Phong kind does.

An ambient light and a hemisphere light are not stepped. three.js reflects both through `RE_IndirectDiffuse`, which no ramp touches, so both reach a toon surface exactly as they reach a Lambert one.

## Matcap

A matcap is a photograph of a sphere, lit however the artist liked. The shader looks a surface up in it by which way the surface is turned. So a whole lighting rig arrives as one image, and the scene's own lights are not consulted at all.

```mojo
var clay = assets.materials.add(matcap_material(ball))
var tinted = assets.materials.add(matcap_material(ball, Color(255, 200, 160)))
var plain = assets.materials.add(matcap_material())
```

`matcap_material(matcap=NO_TEXTURE, color=Color(255, 255, 255), map=NO_TEXTURE, side=FRONT_SIDE, opacity=1.0, blending=None)`.

three.js: `MeshMatcapMaterial`, `matcap`.

The image comes first, because a matcap surface is the image. The color is a tint over it, and white, the default, leaves it alone.

| Property | Meaning |
|---|---|
| `matcap` | The image to look the surface up in, or `NO_TEXTURE` for three.js's gradient. |

### The frame is the camera's own

three.js builds a frame from the direction toward the camera and the camera's own up axis, then reads how far the normal leans along each:

```
x  = normalize(cross(up, toward_eye))
y  = cross(toward_eye, x)
uv = (dot(x, normal), dot(y, normal)) * 0.495 + 0.5
```

`matcap_uv` is that arithmetic, in `render/rasterizer.mojo`. Both rasterizers call it. three.js works in view space and this works in world space. The two give the same dot products: the view transform is rigid, and a dot product does not care how the pair is turned. Doing it in world space saves carrying a second normal and a second position per corner.

**A matcap turns with the camera.** Orbit the camera around a sphere and the image stays where it is on the screen. That is what makes the trick cheap, and what stops it working for anything that has to stay put in the world.

The direction toward the camera is measured from where the camera stands, under either projection. three.js reads `vViewPosition` in this shader and does not special-case a parallel one, so neither does this. `toward_camera` is not consulted here.

The 0.495 is three.js's own. It is there to reduce artifacts from an undersized matcap disk. It keeps the lookup a little inside the image, but it does not make the wrap mode irrelevant. On a small image a bilinear footprint at 0.005 can still cross the edge.

### The fallback

With no `matcap`, three.js falls back to `mix(0.2, 0.8, uv.y)`. That is a gray gradient, dark at the bottom and pale at the top, which reads as a sphere lit from above. `matcap_fallback` is that mix. It is linear light rather than an authored byte, because three.js writes it straight into the outgoing light.

### What a matcap material does not have

An emissive term. The image already holds every bit of light the surface shows, so a `MATCAP` material refuses one, exactly as a `BASIC` material does. `MaterialKind.is_unlit` is the question both answer.

The image is sampled at its full-size level and never down a mip chain. A mip chain is only progressively filtered copies of an image, so normal-derived coordinates could use one. What is missing is the screen-space footprint of *those* coordinates. `mip_level` measures the footprint of the surface's own texture coordinates, which is a different quantity. Matcap-coordinate derivatives and mip selection are not implemented.

A matcap's own alpha means nothing: three.js reads `.rgb` and no more. So the texture must be built `IGNORED`, or filtering would weight its channels by an alpha that says nothing. Its color space is free, because a matcap really is color.

## Data materials

A normal material and a depth material write bytes that a display must show as they are. Build one with its own function:

```mojo
var shown = assets.materials.add(normal_material())
var seen = assets.materials.add(depth_material())
var pane = assets.materials.add(normal_material(DOUBLE_SIDE))
var cut = assets.materials.add(depth_material(mask))
```

| Builder | Meaning |
|---|---|
| `normal_material(side=FRONT_SIDE, opacity=1.0, blending=None, alpha_test=0.0)` | The view-space normal as a color. |
| `depth_material(map=NO_TEXTURE, side=FRONT_SIDE, opacity=1.0, blending=None, alpha_map=NO_TEXTURE, alpha_test=0.0)` | The depth as a gray. |

Both take `side`, `opacity` and `blending`, and nothing else. A depth material also takes a `map`. Neither can blend: see [What they refuse](#what-they-refuse).

### Normals

`NORMALS` writes the normal as three.js's `packNormalToRGB` does. Each component is halved and moved up by a half. A surface square on to the camera is (128, 128, 255). One turned to the camera's right is redder. One turned up is greener.

The normal is the one the camera sees, three.js's `vNormal`, not the one the world sees. Moving the camera changes the colors of a surface that never moved. The renderer carries each normal through the view matrix for this material alone.

A `DOUBLE_SIDE` face seen from behind shows its normal flipped, as it is lit flipped. A `BACK_SIDE` face shows the normal it was given. The normal is made unit length at every fragment, as it is for a lit surface. A geometry with no normals falls back to its face normal.

### Depth

`DEPTH` writes one minus the window-space depth in every channel. The near plane is white and the far plane is black. This is three.js's `MeshDepthMaterial` under `BasicDepthPacking`. The other packings are not ported.

Set the camera's `near` and `far` close together to see anything. A range of one to a thousand meters puts almost every surface within a few levels of black.

A map's alpha cuts the surface out, as three.js's does. Its color is not read. Give the material an `alpha_test` to throw the cut fragments away. Such a fragment claims no depth, so what is behind it draws. A depth material cannot blend, so blending is not the way to show the cut.

### What they refuse

Neither shader reads a color, an emissive term or the vertex colors. A material of either kind refuses all three rather than ignoring them. Pass opaque white as the color, or use the builders, which do. A normal material refuses a map and an alpha map as well. Both take an alpha test, as three.js's do.

Neither is lit, fogged nor tone mapped. A veil of light over a normal, or a curve that compresses it, would make the image lie about its own numbers. Both rasterizers decide this per pixel. See [Why a normal is not a color](Why-a-normal-is-not-a-color).

Neither can blend. One pixel holds its own bytes or the scene's light. A mixture of the two is neither. So a `NORMALS` or `DEPTH` material whose blending resolves to `BLEND` is refused, stated or taken from `transparent`. Both rasterizers refuse a blended data triangle as well, from the same function. That is what lets `RenderTarget.blend` say a mixture is always light.

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

## Wireframe

`wireframe=True` draws the lines of a surface's triangles rather than filling them, three.js's `material.wireframe`.

```mojo
var wire = Material(Color(120, 220, 255), kind=BASIC, wireframe=True)
scene.add_mesh(Mesh(shape, assets.materials.add(wire), node))
```

The mesh goes through the pipeline every other mesh goes through: morph, skin, instance, cull, transform. It then assembles its own triangle edges as segments rather than filling them. A wireframe of a morphed, skinned or instanced mesh therefore needs no further word about any of the three. The segments are drawn by the [line pass](Lines).

The edges come from the mesh, not from the filled triangles. Cutting prepared fill into lines looks equivalent and is not. Clipping a triangle leaves a polygon that has to be fanned. The fan's diagonal and the cut along the near plane both become edges the mesh never had. Each edge is clipped with `clip_segment` instead.

A wireframe is submitted as lines, so it has no facing. A front-sided wireframe shows its far side, as three.js's does.

The kind must be `BASIC` and there must be no map. A line has no surface, so it has no normal for a light to reach and no coordinate to sample an image at. A lit or mapped wireframe is refused rather than drawn with one of the two quietly dropped.

An edge shared by two triangles is drawn once. `triangle_edges` pairs them by vertex index, as three.js's `getWireframeAttribute` does. Drawing it twice is not free even though it is the same pixels: a blended segment drawn over itself is twice as opaque.

To keep only the edges that show the shape, build a geometry with [`edges_geometry`](Geometry#edges-and-wireframes) and draw it with a `Line`.

## Dashes

`line_dashed_material(color)` is three.js's `LineDashedMaterial`: a `BASIC` material with a dash of three, a gap of one and a scale of one. `Material(color, kind=BASIC, dash_size=..., gap_size=...)` spells the same material out. Only a line reads the dashes. See [dashed lines](Lines#dashed-lines) for what they measure and where they are refused.

## Opacity and blending

`transparent=True` makes the material blend, as in three.js. A blended surface tests depth without writing it, and the renderer draws it after every opaque mesh, furthest first. Its alpha is `opacity` times the color's alpha, the texture's alpha and the alpha map.

A material that is not `transparent` is drawn opaque whatever its opacity or its maps say. Every fragment is written with an alpha of one, as three.js's `opaque_fragment` writes it. The opacity and the maps still feed the alpha test. A `DEPTH` material keeps its opacity as its alpha, as three.js's does.

Pass `blending=BLEND` or `blending=OPAQUE` to state the policy outright. A `NORMALS` or `DEPTH` material must be opaque either way.

| Method | Meaning |
|---|---|
| `is_lit() -> Bool` | `kind` is `LAMBERT`, `PHONG` or `TOON`. |
| `is_unlit() -> Bool` | `kind` is `BASIC` or `MATCAP`. Neither has an emissive term. |
| `has_highlight() -> Bool` | `kind` is `PHONG`. A black specular is a reflectance of zero, not a switch. |
| `specular_light() -> FloatColor` | The specular color decoded to linear light. |
| `has_gradient_map() -> Bool` | `gradient_map != NO_TEXTURE`. A `TOON` material without one steps through the fallback. |
| `has_matcap() -> Bool` | `matcap != NO_TEXTURE`. A `MATCAP` material without one takes the gradient. |
| `is_data() -> Bool` | `kind` is `NORMALS` or `DEPTH`. |
| `has_alpha_map() -> Bool` | `alpha_map != NO_TEXTURE`. |
| `is_alpha_tested() -> Bool` | `alpha_test > 0`. |
| `is_textured() -> Bool` | `map != NO_TEXTURE`. |
| `is_transparent() -> Bool` | `blending == BLEND`, which follows `transparent` unless stated. |
| `is_dashed() -> Bool` | `gap_size` is above zero. A dash with no gap is a solid line. |
| `is_emissive() -> Bool` | Whether the emissive color at its intensity adds any light. |
| `emissive_light() -> FloatColor` | The emissive color decoded to linear light, times the intensity. |

## Errors

The constructor raises for:

- A texture id or an emissive map id below zero that is not `NO_TEXTURE`.
- An opacity outside zero to one.
- A negative emissive intensity.
- A color that is not opaque white on a `NORMALS` or `DEPTH` material.
- An emissive term or vertex colors on either of those two kinds.
- A map or an alpha map on a `NORMALS` material.
- An alpha map id below zero that is not `NO_TEXTURE`.
- An alpha test outside zero to one, or not finite.
- A negative or non-finite shininess.
- A specular that is not black, or a positive shininess, on a kind that is not `PHONG`.
- A gradient map on a kind that is not `TOON`, or a gradient map id below zero that is not `NO_TEXTURE`.
- A matcap on a kind that is not `MATCAP`, or a matcap id below zero that is not `NO_TEXTURE`.
- An emissive term on an unlit material, which is a `BASIC` or a `MATCAP` one.
- A `NORMALS` or `DEPTH` material whose blending resolves to `BLEND`, stated or inferred.
- A wireframe on a kind that is not `BASIC`, or beside a map or an alpha map.
- A dash or a gap that is negative or not finite, or a dash scale that is not finite.
- A gap with no dash before it, which would draw nothing.
- Dashes on a kind that is not `BASIC`, or on a wireframe.

`Renderer.prepare` raises for an emissive map that reads its alpha as coverage.
- A `Side`, `Blending` or `MaterialKind` that is none of its named values. The type stops a bare integer at compile time. `is_valid` stops `Side(99)` at run time.

## MaterialStore

`assets.materials.add(material)` returns a `MaterialId`. `get(id)` returns a copy.

## Example

```mojo
var glass = assets.materials.add(
    Material(Color(255, 80, 80), NO_TEXTURE, DOUBLE_SIDE, 0.45, transparent=True)
)
var sky = assets.materials.add(Material(Color(120, 170, 255), kind=BASIC))
```
