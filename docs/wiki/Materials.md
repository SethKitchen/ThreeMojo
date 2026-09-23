# Materials

`materials/material.mojo`. A `Material` is a color, an optional texture, which sides to draw, an opacity, a blend policy, a kind and an emissive term.

![A white highlight follows the camera around a red sphere](out/phong.png)

three.js: `Material`, `MeshLambertMaterial`, `MeshPhongMaterial`, `MeshStandardMaterial`, `MeshPhysicalMaterial`, `MeshToonMaterial`, `MeshMatcapMaterial`, `MeshBasicMaterial`, `MeshNormalMaterial`, `MeshDepthMaterial`, `LineBasicMaterial`, `LineDashedMaterial`, `PointsMaterial`, `SpriteMaterial`.

Properties: `side`, `opacity`, `transparent`, `map`, `emissive`, `emissiveIntensity`, `emissiveMap`, `specular`, `shininess`, `alphaMap`, `alphaTest`, `gradientMap`, `matcap`, `wireframe`, `dashSize`, `gapSize`, `scale`, `size`, `sizeAttenuation`, `rotation`, `envMap`, `reflectivity`, `combine`.

Physical properties: `roughness`, `metalness`, `roughnessMap`, `metalnessMap`, `envMapIntensity`, `ior`, `specularColor`, `specularIntensity`, `clearcoat`, `clearcoatRoughness`. Map properties: `normalMap`, `normalScale`, `bumpMap`, `bumpScale`.

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
| `point_size` | `PointSize` | `PointSize(1.0)` | How many pixels across a point is. See [points](Points-and-sprites#points). |
| `size_attenuation` | `Bool` | `True` | Whether a point or a sprite shrinks with distance. |
| `rotation` | `Angle` | zero | How far a sprite is turned about the line of sight. See [sprites](Points-and-sprites#sprites). |
| `env_map` | `CubeTextureId` | `NO_CUBE_TEXTURE` | The cube texture the surface reflects, or `SCENE_ENVIRONMENT`. See [Environment map](#environment-map). |
| `reflectivity` | `Float32` | `1.0` | How much of the reflection joins the surface's light. |
| `combine` | `Combine` | `MULTIPLY_OPERATION` | How the reflection joins. |
| `roughness` | `Float32` | `1.0` | How rough a `STANDARD` or `PHYSICAL` surface is. See [Standard and physical](#standard-and-physical). |
| `metalness` | `Float32` | `0.0` | How much of a metal it is. |
| `roughness_map` | `TextureId` | `NO_TEXTURE` | A texture whose green channel multiplies the roughness. |
| `metalness_map` | `TextureId` | `NO_TEXTURE` | A texture whose blue channel multiplies the metalness. |
| `env_map_intensity` | `Float32` | `1.0` | What a physical surface's environment is multiplied by. |
| `normal_map` | `TextureId` | `NO_TEXTURE` | A texture of tangent-space normals. See [Normal maps and bump maps](#normal-maps-and-bump-maps). |
| `normal_scale` | `Vector2` | `Vector2(1, 1)` | What the map's x and y are scaled by. |
| `bump_map` | `TextureId` | `NO_TEXTURE` | A texture whose red channel is a height. |
| `bump_scale` | `Float32` | `1.0` | What that height is scaled by. |
| `ior` | `Float32` | `1.5` | A `PHYSICAL` surface's index of refraction. |
| `specular_color` | `Color` | white | What its reflectance head on is tinted by. |
| `specular_intensity` | `Float32` | `1.0` | What that reflectance is scaled by. |
| `clearcoat` | `Float32` | `0.0` | How much clear coat lies over a `PHYSICAL` surface. |
| `clearcoat_roughness` | `Float32` | `0.0` | How rough the coat is. |

## Side

| Value | Draws |
|---|---|
| `FRONT_SIDE` | Faces that point at the camera. The default, as in three.js. |
| `BACK_SIDE` | Faces that point away. The inside of a closed mesh. |
| `DOUBLE_SIDE` | Both. Use it for an open surface. |

A `DOUBLE_SIDE` face seen from behind is lit with its normal flipped. This is three.js's rule: its shader flips the normal under `DOUBLE_SIDED` by which way the face is seen. A `BACK_SIDE` face is lit with its normal flipped whichever way it is seen. That is three.js's `FLIP_SIDED`, which `defaultnormal_vertex` applies when `side` is `BackSide`. The inside of a box lit by a lamp inside it is lit. A mirrored mesh, with a negative world determinant, keeps the same convention.

## Kind

| Value | three.js | Meaning |
|---|---|---|
| `LAMBERT` | `MeshLambertMaterial` | The lights reach the surface. |
| `PHONG` | `MeshPhongMaterial` | Lit, and with a highlight that follows the camera. |
| `STANDARD` | `MeshStandardMaterial` | Lit by a roughness and a metalness, with a GGX lobe. See [Standard and physical](#standard-and-physical). |
| `PHYSICAL` | `MeshPhysicalMaterial` | `STANDARD` with an index of refraction and a clear coat. |
| `BASIC` | `MeshBasicMaterial`, `LineBasicMaterial`, `PointsMaterial`, `SpriteMaterial` | The color and texture show as they are. The kind a [line](Lines), a [point or a sprite](Points-and-sprites) is drawn with. |
| `NORMALS` | `MeshNormalMaterial` | The normal the camera sees, as a color. |
| `DEPTH` | `MeshDepthMaterial` | How far away the surface is, as a gray. |

`is_lit()` is true for the first four. `is_physical()` is true for `STANDARD` and `PHYSICAL`. `is_data()` is true for the last two, which show data rather than light. See [Data materials](#data-materials).

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

## Environment map

A `BASIC`, `LAMBERT` or `PHONG` material can reflect a [cube texture](Textures#cube-textures): three.js's `envMap` on `MeshBasicMaterial`, `MeshLambertMaterial` and `MeshPhongMaterial`. A `STANDARD` or `PHYSICAL` material reflects one by its roughness instead; see [The environment](#the-environment). The direction the camera sees a fragment along is turned back through the fragment's normal, and the cube is read in that direction. That is what a mirror shows.

```mojo
var chrome = Material(Color(255, 255, 255), kind=BASIC, env_map=sky)
var glossy = phong_material(Color(200, 40, 40))
var tinted = Material(Color(150, 150, 150), env_map=SCENE_ENVIRONMENT, reflectivity=0.35, combine=MIX_OPERATION)
```

| Property | three.js | Default | Meaning |
|---|---|---|---|
| `env_map` | `envMap` | `NO_CUBE_TEXTURE` | The cube texture to reflect. `SCENE_ENVIRONMENT` reflects the scene's `environment`. |
| `reflectivity` | `reflectivity` | `1.0` | How much of the reflection joins, from zero to one. |
| `combine` | `combine` | `MULTIPLY_OPERATION` | How it joins. See the table below. |

| `combine` | three.js | The surface's light becomes |
|---|---|---|
| `MULTIPLY_OPERATION` | `MultiplyOperation` | `mix(light, light * reflection, reflectivity)`. A tinted mirror. |
| `MIX_OPERATION` | `MixOperation` | `mix(light, reflection, reflectivity)`. A reflection laid over the surface. |
| `ADD_OPERATION` | `AddOperation` | `light + reflection * reflectivity`. A gloss on top. |

`combine_light` in `materials/material.mojo` is that arithmetic, three.js's `envmap_fragment`. Both rasterizers call it. The reflection joins after the lights, the highlight and the emissive term, and before the fog, where three.js joins it. Alpha is coverage and is left alone. A white `BASIC` surface with a multiply is a plain mirror. A colored one is a mirror tinted by its color.

The reflected direction is `reflected(toward_eye, normal)` in `render/cube_texture.mojo`, GLSL's `reflect`. It is measured from where the camera stands under either projection, as three.js reads `cameraPosition` here. The cube is read at its full size, never down a mip chain; see [Textures](Textures#cube-textures).

A reflection is a texture. `SHADE_TEXTURE` draws it and the other two shading modes ignore it, as they ignore every map.

`SCENE_ENVIRONMENT` is not an id. The renderer replaces it with whatever the scene's `environment` names when it prepares the frame. A scene with no environment gives the material nothing to reflect, as three.js's `material.envMap || scene.environment` gives nothing. three.js applies the environment to its physically based materials without asking. Those are not ported, and this project's materials reflect nothing unless told to, so a material asks. See [Scene graph](Scene-graph#background-and-environment).

No other kind reflects this way. A toon surface steps through a ramp, a matcap surface is an image already, and the data kinds show no light. Each refuses an env map, a reflectivity that is not one, and a combine that is not the default. A physical kind takes an env map and refuses the other two. A wireframe refuses an env map too. So do a line, a point and a sprite, in their own passes: none has a surface to reflect from.

`examples/mirror.mojo` reflects a scene in a chrome ball, through a [CubeCamera](Cameras#cubecamera).

## Standard and physical

![Ten spheres from chalk to mirror, dielectric above and metal below](out/physical.png)

A `STANDARD` surface is shaded by a roughness and a metalness rather than by a color and a highlight: three.js's `MeshStandardMaterial`. A `PHYSICAL` surface adds an index of refraction, a specular color and intensity, and a clear coat: part of three.js's `MeshPhysicalMaterial`. Build either with its own function:

```mojo
var chalk = assets.materials.add(standard_material(Color(200, 200, 200)))
var gold = assets.materials.add(
    standard_material(Color(255, 200, 90), roughness=0.3, metalness=1.0, env_map=sky)
)
var lacquer = assets.materials.add(
    physical_material(Color(180, 30, 30), roughness=0.5, clearcoat=1.0, clearcoat_roughness=0.1)
)
```

`standard_material(color, map=NO_TEXTURE, roughness=1.0, metalness=0.0, side=FRONT_SIDE, opacity=1.0, blending=None, transparent=False, env_map=NO_CUBE_TEXTURE, env_map_intensity=1.0, roughness_map=NO_TEXTURE, metalness_map=NO_TEXTURE, normal_map=NO_TEXTURE, normal_scale=Vector2(1, 1), bump_map=NO_TEXTURE, bump_scale=1.0, emissive=black, emissive_intensity=1.0, emissive_map=NO_TEXTURE)`.

`physical_material(color, map=NO_TEXTURE, roughness=1.0, metalness=0.0, ior=1.5, specular_color=white, specular_intensity=1.0, clearcoat=0.0, clearcoat_roughness=0.0, ...)` takes the same arguments after those.

The defaults are three.js's own: a roughness of one and a metalness of zero, a chalky dielectric. `Material(color, kind=STANDARD)` is the same surface.

| Property | three.js | Default | Meaning |
|---|---|---|---|
| `roughness` | `roughness` | `1.0` | Zero is a mirror, one is chalk. See [Three roughnesses](#three-roughnesses). |
| `metalness` | `metalness` | `0.0` | Zero scatters the color, one reflects it. |
| `roughness_map` | `roughnessMap` | `NO_TEXTURE` | Its green channel multiplies the roughness. Data: `LINEAR` and `IGNORED`. |
| `metalness_map` | `metalnessMap` | `NO_TEXTURE` | Its blue channel multiplies the metalness. Data: `LINEAR` and `IGNORED`. |
| `env_map` | `envMap` | `NO_CUBE_TEXTURE` | The cube texture the surface reflects, or `SCENE_ENVIRONMENT`. |
| `env_map_intensity` | `envMapIntensity` | `1.0` | What the environment is multiplied by. |
| `ior` | `ior` | `1.5` | The index of refraction, from one to 2.333. `PHYSICAL` only. |
| `specular_color` | `specularColor` | white | What the reflectance head on is tinted by. `PHYSICAL` only. |
| `specular_intensity` | `specularIntensity` | `1.0` | What that reflectance is scaled by, from zero to one. `PHYSICAL` only. |
| `clearcoat` | `clearcoat` | `0.0` | How much clear coat lies over the surface, from zero to one. `PHYSICAL` only. |
| `clearcoat_roughness` | `clearcoatRoughness` | `0.0` | How rough the coat is. `PHYSICAL` only. |

### What the shader does

The diffuse term is Lambert's, on the color times one minus the metalness. The lobe is three.js's `BRDF_GGX`: Schlick's Fresnel, Smith's correlated visibility and the GGX distribution. `ggx(toward_light, toward_eye, normal, f0, f90, roughness)` is that arithmetic, in `lights/lighting.mojo`. Both rasterizers call it. `Lighting.physical_at` sums it over the lights that have a direction, and `Lighting.indirect_at` gathers the ambient and hemisphere light for the diffuse term.

What the surface reflects head on is `Material.base_reflectance()`. A `STANDARD` surface reflects four percent, three.js's `vec3(0.04)`. A `PHYSICAL` surface reflects `((ior - 1) / (ior + 1))^2`, tinted by its specular color and scaled by its specular intensity. A metal reflects its own color instead, and the metalness mixes between the two, as `lights_physical_fragment` mixes them.

The reciprocal of pi is applied once per sum, as it is for every lit kind. See [The reciprocal of pi](#the-reciprocal-of-pi).

### Three roughnesses

The number you set is the *authored* roughness, from zero to one, times any map. The lobe is evaluated with the *BRDF* roughness: the authored one floored at `ROUGHNESS_FLOOR`, three.js's 0.0525, by `floored_roughness`. three.js applies that floor once and both its lobes read the floored number, the direct lights' included. So a roughness of zero, of 0.01 and of 0.0525 make one lobe under a lamp, there and here. The floor is what keeps `ggx` finite too: at zero and head on its distribution divides zero by zero. The *environment* roughness is the BRDF roughness read as a mip level, below.

### The environment

A physical surface reflects its environment by its roughness, not by a `combine`. Both refuse a `reflectivity` or a `combine`. The reflection is three.js's split sum: `dfg_approx` fits the lobe's integral, and `physical_outgoing` in `lights/lighting.mojo` joins the radiance and the irradiance with Fdez-Aguera's multiple scattering. The radiance is read along `rough_reflection`, the view turned back and bent toward the normal by the square of the roughness. The irradiance is read around the normal at the coarsest level.

The roughness picks a level of the cube's chain: `reflection_level(roughness, levels)`, from the full size at zero to one texel a face at one. That is an approximation. Its contract is monotonic: a rising roughness moves a reflection steadily from the texel it lands on toward its face's average. three.js's PMREM holds the environment weighted by the GGX lobe at each roughness, which a mip chain's box average is not.

The irradiance is an approximation too. The coarsest level is each face's average, not the cosine-weighted integral over the hemisphere. Under a sky that is one bright patch on black it reads high. A cube built without a chain reflects sharply at every roughness. Either level can be replaced by a prefiltered cube without the material changing. See [Textures](Textures#cube-textures).

### The clear coat

A clear coat is a second, colorless GGX lobe over the surface. It lies on the surface's own normal, before any normal map perturbs it, as three.js's `nonPerturbedNormal` does. It dims everything under it by its own Fresnel and adds its own reflection on top: a red car under a white gloss. `clearcoat=0`, the default, is no coat.

### What is not ported

three.js's transmission, sheen, iridescence, anisotropy, dispersion and their maps are not ported. Nor is the geometric roughness three.js adds from how fast the normal changes across a pixel, which needs neighboring pixels this project shades without.

`examples/physical.mojo` draws the range: a row of spheres from chalk to mirror, and from dielectric to metal.

## Normal maps and bump maps

A normal map is a texture whose texels are tangent-space normals: three.js's `normalMap`. A bump map is a texture whose red channel is a height: three.js's `bumpMap`. Either perturbs the normal every lit shader reads, so every lit kind and a `MATCAP` surface can carry one.

```mojo
var brick = assets.materials.add(Material(Color(200, 120, 90), normal_map=bricks))
var leather = assets.materials.add(
    standard_material(Color(60, 40, 30), roughness=0.8, bump_map=grain, bump_scale=0.05)
)
```

| Property | three.js | Default | Meaning |
|---|---|---|---|
| `normal_map` | `normalMap` | `NO_TEXTURE` | Red is x, green is y, blue is z, each unpacked from zero to one into minus one to one. |
| `normal_scale` | `normalScale` | `Vector2(1, 1)` | What the unpacked x and y are multiplied by. |
| `bump_map` | `bumpMap` | `NO_TEXTURE` | Its red channel is a height. |
| `bump_scale` | `bumpScale` | `1.0` | What the height is multiplied by. |

Both are data. A texture named as either must be `LINEAR` and `IGNORED`, as an alpha map must. Both are sampled at the same coordinate as `map`, so their transforms must agree with it. A material names one or the other, not both: three.js reads the normal map and ignores the bump map.

### The tangent frame

Neither needs a tangent attribute. The frame is built from how the world position and the texture coordinates change across one pixel, as three.js's `getTangentFrame` builds it without one. The tangent is the direction along which `u` grows, the bitangent the direction along which `v` grows, both made perpendicular to the normal. Both rasterizers evaluate the change one pixel to the right and one pixel up from the triangle's own functions, as they evaluate a mip footprint. `mapped_normal` in `render/rasterizer.mojo` is the arithmetic. The GPU kernel calls the same function.

A bump map's slope is three.js's `perturbNormalArb`. The height one pixel over and one pixel up, less the height here, tilts the normal against the rise. `bumped_normal` is that arithmetic. The position changes are normalized first, so the bump looks the same however the texture is scaled.

### The far side

A `DOUBLE_SIDE` or `BACK_SIDE` face seen from behind is lit with its normal flipped. Its frame flips with it: the far side's perturbed normal is the front's, negated, as three.js negates the tangent and the bitangent by `faceDirection`. The renderer does that by negating `normal_scale` and `bump_scale` on a corner it turns around. So a bump that rises toward the light on the front falls away from it on the back.

### What refuses one

A `BASIC` surface reads no normal and a `DEPTH` surface reads none. A `NORMALS` surface reads one in the camera's frame, and the frame a map is measured in is the world's. Each refuses both maps. A wireframe is `BASIC`, so it refuses them too. A `normal_scale` that is not one and one needs a normal map, and a `bump_scale` that is not one needs a bump map.

Only `SHADE_TEXTURE` reads either. A normal map is a texture, and the other two shading modes ignore every texture.

## Shadow material

A `SHADOW` material shows the shadows falling on it and nothing else: three.js's `ShadowMaterial`. It is transparent wherever the lights that cast reach it and shows its color wherever they are blocked, by how much. A floor drawn with one catches a shadow on whatever is behind it.

```mojo
var catcher = assets.materials.add(shadow_material())
var faint = assets.materials.add(shadow_material(Color(20, 0, 40), 0.6))
scene.add_mesh(Mesh(floor, catcher, node, receive_shadow=True))
```

`shadow_material(color=Color(0, 0, 0), opacity=1.0, side=FRONT_SIDE)`. Black at an opacity of one is three.js's default.

The alpha is `opacity` times one minus `Lighting.shadow_mask`, three.js's `opacity * (1.0 - getShadowMask())`, the product of what every casting light lets through. The material always blends, as three.js's is built `transparent`, and refuses to be made opaque. It is unlit, so it refuses an emissive term, and it refuses every map, vertex colors, a wireframe and an environment. See [Shadows](Lights#shadows).

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

A `DOUBLE_SIDE` face seen from behind shows its normal flipped, as it is lit flipped. A `BACK_SIDE` face shows its normal flipped too, as three.js's `FLIP_SIDED` flips it. The normal is made unit length at every fragment, as it is for a lit surface. A geometry with no normals falls back to its face normal.

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

## Points and sprites

`points_material(color)` is three.js's `PointsMaterial`: a `BASIC` material with a `PointSize` of one pixel and its attenuation on. `sprite_material()` is three.js's `SpriteMaterial`: a white `BASIC` material with no rotation, its attenuation on and `transparent=True`. Both can carry a map and an alpha map. Only a point reads the size and only a sprite reads the rotation. A size that is not the default, attenuation off or a rotation is refused on any other kind. See [Points and sprites](Points-and-sprites).

## Opacity and blending

`transparent=True` makes the material blend, as in three.js. A blended surface tests depth without writing it, and the renderer draws it after every opaque mesh, furthest first. Its alpha is `opacity` times the color's alpha, the texture's alpha and the alpha map.

A material that is not `transparent` is drawn opaque whatever its opacity or its maps say. Every fragment is written with an alpha of one, as three.js's `opaque_fragment` writes it. The opacity and the maps still feed the alpha test. A `DEPTH` material keeps its opacity as its alpha, as three.js's does.

Pass `blending=BLEND` or `blending=OPAQUE` to state the policy outright. A `NORMALS` or `DEPTH` material must be opaque either way.

### Blending modes

`render/blend.mojo` holds the arithmetic of every mode, and both rasterizers call it. three.js: `NormalBlending`, `AdditiveBlending`, `SubtractiveBlending`, `MultiplyBlending` and `CustomBlending`, with `premultipliedAlpha` off.

| Mode | Color | Alpha |
|---|---|---|
| `BLEND` | `src * a + dst * (1 - a)` | `a + dst_a * (1 - a)` |
| `ADDITIVE` | `src * a + dst` | `a * a + dst_a` |
| `SUBTRACTIVE` | `dst * (1 - src)` | `dst_a` |
| `MULTIPLY` | `dst * src` | `dst_a * a` |

`custom_blending(src, dst, equation, src_alpha, dst_alpha, equation_alpha)` builds a custom mode. The factors are the eleven `BlendFactor`s, `ZERO_FACTOR` to `SRC_ALPHA_SATURATE_FACTOR`. The equations are the five `BlendEquation`s: `ADD_EQUATION`, `SUBTRACT_EQUATION`, `REVERSE_SUBTRACT_EQUATION`, `MIN_EQUATION` and `MAX_EQUATION`. The alpha parts take the color parts when left out. A custom mode packs its six parts into the one integer a `Blending` holds, so it travels the same path as a named mode.

Every mode but `OPAQUE` mixes. A mixing surface tests depth without claiming it and is drawn in the translucent pass, furthest first. three.js draws an additive material that is not `transparent` in its opaque pass, and this port does not.

The pixel is stored premultiplied. The factors read it as WebGL reads its framebuffer. Over an opaque pixel, stored and straight color are the same numbers, so every mode agrees with three.js there. The result's alpha stays between zero and one, and its color stays at zero or above.

Under `BLEND`, a fragment with an alpha of zero changes nothing. Under the other modes a clear fragment still acts, as in WebGL: a clear subtractive fragment still darkens.

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
| `is_transparent() -> Bool` | `blending.mixes()`: any mode but `OPAQUE`. It follows `transparent` unless stated. |
| `is_dashed() -> Bool` | `gap_size` is above zero. A dash with no gap is a solid line. |
| `is_emissive() -> Bool` | Whether the emissive color at its intensity adds any light. |
| `emissive_light() -> FloatColor` | The emissive color decoded to linear light, times the intensity. |

## Depth, color and stencil

A material decides how its fragments meet the depth, color and stencil buffers. The fields are three.js's, with three.js's defaults. Set them after you build the material, as you set them in three.js. `render/raster_state.mojo` holds the arithmetic, and both rasterizers call it.

```mojo
var mask = Material(Color(255, 255, 255), kind=BASIC)
mask.color_write = False
mask.depth_write = False
mask.stencil_write = True
mask.stencil_ref = 1
mask.stencil_z_pass = REPLACE_STENCIL_OP
var shown = Material(Color(255, 0, 0), kind=BASIC)
shown.stencil_write = True
shown.stencil_func = EQUAL_STENCIL_FUNC
shown.stencil_ref = 1
```

Draw the mask first, with a lower render order. The second material then draws only inside the shape of the first.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `depth_test` | `Bool` | `True` | Compare the depth. Off, every fragment passes and writes no depth. |
| `depth_write` | `Bool` | `True` | A fragment that passes writes its depth. |
| `depth_func` | `DepthFunc` | `LESS_EQUAL_DEPTH` | How the depth is compared. |
| `color_write` | `Bool` | `True` | A fragment that passes writes its color. Off, it still writes depth and stencil. |
| `polygon_offset` | `Bool` | `False` | Push the filled triangles back. |
| `polygon_offset_factor` | `Float32` | `0` | What the depth slope is multiplied by. |
| `polygon_offset_units` | `Float32` | `0` | What the smallest depth step is multiplied by. |
| `stencil_write` | `Bool` | `False` | Run the stencil test and write the stencil. |
| `stencil_write_mask` | `Int` | `255` | The bits an operation can change. |
| `stencil_func` | `StencilFunc` | `ALWAYS_STENCIL_FUNC` | How the reference is compared. |
| `stencil_ref` | `Int` | `0` | The reference value. |
| `stencil_func_mask` | `Int` | `255` | The bits the test compares. |
| `stencil_fail` | `StencilOp` | `KEEP_STENCIL_OP` | The operation when the stencil test fails. |
| `stencil_z_fail` | `StencilOp` | `KEEP_STENCIL_OP` | The operation when the depth test fails. |
| `stencil_z_pass` | `StencilOp` | `KEEP_STENCIL_OP` | The operation when both tests pass. |

The depth functions are `NEVER_DEPTH`, `ALWAYS_DEPTH`, `LESS_DEPTH`, `LESS_EQUAL_DEPTH`, `EQUAL_DEPTH`, `GREATER_EQUAL_DEPTH`, `GREATER_DEPTH` and `NOT_EQUAL_DEPTH`. They keep three.js's numbers, zero to seven. The stencil functions are `NEVER_STENCIL_FUNC` to `ALWAYS_STENCIL_FUNC`, in WebGL's order. The operations are `ZERO_STENCIL_OP`, `KEEP_STENCIL_OP`, `REPLACE_STENCIL_OP`, `INCREMENT_STENCIL_OP`, `DECREMENT_STENCIL_OP`, `INCREMENT_WRAP_STENCIL_OP`, `DECREMENT_WRAP_STENCIL_OP` and `INVERT_STENCIL_OP`. The stencil functions and the operations count from zero, not from three.js's WebGL values.

### The order of the tests

The order is OpenGL's. The stencil test runs first, and a fragment that fails it takes `stencil_fail` and is discarded. The depth test runs next, and a fragment that fails it takes `stencil_z_fail` and is discarded. A fragment that passes both takes `stencil_z_pass` and is drawn.

`stencil_write` turns the whole stencil test on, as three.js's `stencilWrite` does. Off, the stencil buffer is neither read nor written. The test compares `stencil_ref & stencil_func_mask` with the stored value under the same mask, the reference on the left. An operation changes only the bits `stencil_write_mask` sets. The increment and the decrement stop at 255 and at zero.

An alpha test runs before the stencil and the depth are written. A fragment that the alpha test discards changes no stencil value, as a GPU's `discard` changes none.

### Where this port differs

A blending surface never writes depth, whatever `depth_write` says. The renderer sorts blending surfaces and draws them last; see [Why transparency is sorted](Why-transparency-is-sorted). An opaque surface writes depth when `depth_test` and `depth_write` are both on.

The reference and the masks must be from 0 to 255, because the stencil buffer is eight bits deep. WebGL masks a larger value, and this port refuses it.

A light's view of the casters ignores these fields. three.js draws a shadow with its own depth material, so a mask that writes no color still casts its shadow.

### Polygon offset

`polygon_offset` pushes a filled triangle back by `factor * m + r * units`, as OpenGL defines it. `m` is the larger of the depth's slopes across x and across y, per pixel. `r` is the smallest depth step. This port stores depth as a `Float32` NDC depth, so `r` is one unit in the last place of the deepest corner. A positive offset pushes the triangle away, and a negative one pulls it nearer.

The renderer adds the offset to the corners before either rasterizer sees them. So both backends receive the same depths. Lines and points are not pushed, as OpenGL's `POLYGON_OFFSET_FILL` pushes neither.

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
- A point size that is not a positive number, or a rotation that is not finite.
- A point size that is not the default, attenuation off, or a rotation, on a kind that is not `BASIC`.
- An env map id below zero that is not `NO_CUBE_TEXTURE` or `SCENE_ENVIRONMENT`.
- A reflectivity outside zero to one or not finite, or a `Combine` that is none of the three.
- An env map, a reflectivity that is not one, or a combine that is not the default, on a kind that does not reflect.
- An env map on a wireframe.
- A roughness, metalness, clearcoat, clearcoat roughness or specular intensity outside zero to one, or not finite.
- An index of refraction outside one to 2.333, or not finite. A negative or non-finite env map intensity.
- A roughness that is not one or a metalness that is not zero on a kind that is not `STANDARD` or `PHYSICAL`. A roughness or metalness map, or an env map intensity that is not one, on such a kind.
- A reflectivity that is not one, or a combine that is not the default, on a `STANDARD` or `PHYSICAL` material.
- An index of refraction that is not the default, or a specular color that is not white, on a kind that is not `PHYSICAL`. A specular intensity that is not one, or a clear coat, on such a kind.
- A normal map or a bump map on a `BASIC`, `DEPTH` or `NORMALS` material, which a wireframe is. Both on one material.
- A normal scale that is not one and one with no normal map. A bump scale that is not one with no bump map. A scale that is not finite.
- A roughness, metalness, normal or bump map id below zero that is not `NO_TEXTURE`.

`Renderer.prepare` raises for a depth function, a stencil function or a stencil operation that is none of the eight. It raises for a stencil reference or mask outside 0 to 255, and for a polygon offset that is not finite. `Material.raster_state` and `Material.depth_offset` make these checks.

`Renderer.prepare` raises for an emissive map that reads its alpha as coverage. It raises for an env map, or a scene environment, that is not in the assets. It raises for a roughness, metalness, normal or bump map that is not in the assets or is not stored as data.
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
