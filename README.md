<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# ThreeMojo

[![license](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-orange)](LICENSE)
[![mojo](https://img.shields.io/badge/Mojo-1.1.0-fe5c1c)](https://mojolang.org)
[![coverage](https://img.shields.io/badge/coverage-100%25%20line%20%7C%20branch%20%7C%20condition%20%7C%20MC%2FDC-brightgreen)](https://github.com/SethKitchen/ThreeMojo/wiki/Coverage-tool)

![A brick-textured cube, lit by a lamp, with the camera circling it](out/photo.png)

Rendered by `examples/photo.mojo`: a PNG decoded by this project, on a cube, seen from a camera that rides the scene graph.

ThreeMojo is a port of [three.js](https://threejs.org) to [Mojo](https://mojolang.org). It renders 3D scenes in software on the CPU, or on a GPU, and writes PNG files. It depends on the Mojo standard library and nothing else. The GPU backend is one file and needs MAX.

The project exists to learn graphics and Mojo from first principles. It is not a drop-in replacement for three.js. The [feature checklist](#features) says what is ported.

## Install

Supported platforms: macOS on Apple Silicon, Linux on x86-64 or aarch64, and Windows through WSL 2. You need Python 3.9 or later, `git`, `make` and [uv](https://docs.astral.sh/uv/).

```bash
git clone https://github.com/SethKitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install "mojo==1.1.0"
uv pip install "max==26.6.0"      # optional: the GPU backend
```

[How to install](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-install) covers WSL 2, the Metal toolchain and the editor setup.

## Start

```bash
make check-cpu                                            # format, lint, tests, docs
make animation                                            # every example, into out/
.venv/bin/mojo run -I . examples/cubes.mojo out/cubes.png
```

Then follow [Tutorial: render your first scene](https://github.com/SethKitchen/ThreeMojo/wiki/Tutorial-Render-your-first-scene).

## Documentation

The [wiki](https://github.com/SethKitchen/ThreeMojo/wiki) follows [Diátaxis](https://diataxis.fr). Tutorials teach. How-to guides solve one task. Reference pages describe each feature. Explanation pages say why the design is what it is.

The pages live in [`docs/wiki/`](docs/wiki) and are published to the wiki on every push to `main`. `make docs-check` enforces the [writing rules](https://github.com/SethKitchen/ThreeMojo/wiki/How-to-write-documentation).

## Features

A ticked item is ported, tested with full coverage, and documented on the linked wiki page. An unticked item is a three.js feature that is not ported yet. Each item has a GitHub issue.

The port is not at parity with three.js yet. 112 features are ported and 37 are open. Each section lists its open items first. Open the dropdown under a section to see what is ported.

<!-- features -->
### Scene


<details>
<summary>Ported: 13</summary>

- [x] [Scene graph](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-graph): `Object3D`, `Scene`, parent and child transforms [#1](https://github.com/SethKitchen/ThreeMojo/issues/1)
- [x] [Quaternion and Euler rotations](https://github.com/SethKitchen/ThreeMojo/wiki/Rotations): six Euler orders, `rotate_x`, `rotate_y`, `rotate_z`, `look_at`, `slerp` [#2](https://github.com/SethKitchen/ThreeMojo/issues/2)
- [x] [PerspectiveCamera](https://github.com/SethKitchen/ThreeMojo/wiki/Cameras#perspectivecamera) [#3](https://github.com/SethKitchen/ThreeMojo/issues/3)
- [x] [OrthographicCamera](https://github.com/SethKitchen/ThreeMojo/wiki/Cameras#orthographiccamera) [#4](https://github.com/SethKitchen/ThreeMojo/issues/4)
- [x] [Camera on a scene node](https://github.com/SethKitchen/ThreeMojo/wiki/Cameras#attach-a-camera-to-a-node): `attach`, orbit with a pivot [#5](https://github.com/SethKitchen/ThreeMojo/issues/5)
- [x] [CubeCamera](https://github.com/SethKitchen/ThreeMojo/wiki/Cameras#cubecamera): six faces rendered from one point into a cube texture, with layers to hide the mirror [#6](https://github.com/SethKitchen/ThreeMojo/issues/6)
- [x] [ArrayCamera and StereoCamera](https://github.com/SethKitchen/ThreeMojo/wiki/Cameras#arraycamera): cameras drawing into rectangles of one image, and two eyes skewed to converge at a focus [#7](https://github.com/SethKitchen/ThreeMojo/issues/7)
- [x] [Fog and FogExp2](https://github.com/SethKitchen/ThreeMojo/wiki/Fog): `scene.fog`, a linear or an exponential veil by camera-space depth, mixed in linear light on both rasterizers [#8](https://github.com/SethKitchen/ThreeMojo/issues/8)
- [x] [Scene background and environment](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-graph#background-and-environment): a color, a texture or a cube texture behind everything, and a cube texture materials reflect as `SCENE_ENVIRONMENT` [#9](https://github.com/SethKitchen/ThreeMojo/issues/9)
- [x] [Layers](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-graph#layers): a bit mask on nodes and cameras that the renderer filters meshes by [#10](https://github.com/SethKitchen/ThreeMojo/issues/10)
- [x] [Clock](https://github.com/SethKitchen/ThreeMojo/wiki/Units#clock): elapsed and delta time as Durations, from a monotonic counter [#11](https://github.com/SethKitchen/ThreeMojo/issues/11)
- [x] [Object3D visibility, names, traversal and render order](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-graph#visibility-names-and-render-order): a hidden node hides its subtree, and render order sorts before depth [#103](https://github.com/SethKitchen/ThreeMojo/issues/103)
- [x] [Clipping planes](https://github.com/SethKitchen/ThreeMojo/wiki/Renderer#clipping-planes): the renderer's planes and each material's own, union or intersection, cut before projection so both rasterizers agree [#104](https://github.com/SethKitchen/ThreeMojo/issues/104)

</details>

### Geometry

- [ ] Interleaved buffers and InstancedBufferGeometry [#111](https://github.com/SethKitchen/ThreeMojo/issues/111)
- [ ] Extrude a shape along a path [#113](https://github.com/SethKitchen/ThreeMojo/issues/113)
- [ ] TextGeometry and FontLoader [#114](https://github.com/SethKitchen/ThreeMojo/issues/114)

<details>
<summary>Ported: 15</summary>

- [x] [BufferGeometry and BufferAttribute](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry) [#12](https://github.com/SethKitchen/ThreeMojo/issues/12)
- [x] [BoxGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#box) [#13](https://github.com/SethKitchen/ThreeMojo/issues/13)
- [x] [SphereGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#sphere) [#14](https://github.com/SethKitchen/ThreeMojo/issues/14)
- [x] [PlaneGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#plane) [#15](https://github.com/SethKitchen/ThreeMojo/issues/15)
- [x] [CircleGeometry and RingGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#circle): pie slices and arcs with a start angle and a sweep [#16](https://github.com/SethKitchen/ThreeMojo/issues/16)
- [x] [CylinderGeometry and ConeGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#cylinder): frustums, pipes and sections, with caps that match three.js [#17](https://github.com/SethKitchen/ThreeMojo/issues/17)
- [x] [TorusGeometry and TorusKnotGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#torus): a tube around a circle, or around a p, q knot [#18](https://github.com/SethKitchen/ThreeMojo/issues/18)
- [x] [Polyhedron geometries: Icosahedron, Octahedron, Tetrahedron, Dodecahedron](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#polyhedra): the four regular solids and any polyhedron, cut toward a sphere by detail [#19](https://github.com/SethKitchen/ThreeMojo/issues/19)
- [x] [CapsuleGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#capsule): a cylinder with hemisphere caps and exact normals [#20](https://github.com/SethKitchen/ThreeMojo/issues/20)
- [x] [LatheGeometry and TubeGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#lathe): a profile revolved, and a tube swept along a path of points with three.js's frames [#21](https://github.com/SethKitchen/ThreeMojo/issues/21)
- [x] [ShapeGeometry and ExtrudeGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#shape): a drawn outline with holes cut into triangles by ear clipping, and given thickness with a bevel [#22](https://github.com/SethKitchen/ThreeMojo/issues/22)
- [x] [Parametric, convex, decal and rounded-box geometries](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#parametric): parametric surfaces, quickhull convex hulls, decals clipped to a projector box, and rounded boxes [#115](https://github.com/SethKitchen/ThreeMojo/issues/115)
- [x] [EdgesGeometry and WireframeGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#edges-and-wireframes): a surface read back as the lines of its edges, welded by position first [#23](https://github.com/SethKitchen/ThreeMojo/issues/23)
- [x] [computeVertexNormals and bounding volumes](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#buffergeometry): area-weighted normals, a bounding box and a bounding sphere on any geometry [#24](https://github.com/SethKitchen/ThreeMojo/issues/24)
- [x] [BufferGeometryUtils: merge, non-indexed, merge vertices, tangents, center](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#merge-weld-and-tangents): merge geometries, weld vertices, creased normals, non-indexed copies, centering and tangents with handedness [#110](https://github.com/SethKitchen/ThreeMojo/issues/110)

</details>

### Objects

- [ ] Per-instance colors [#112](https://github.com/SethKitchen/ThreeMojo/issues/112)
- [ ] Wide lines: Line2, LineSegments2 and LineMaterial [#116](https://github.com/SethKitchen/ThreeMojo/issues/116)
- [ ] Raycasting lines, points, sprites and skinned meshes [#117](https://github.com/SethKitchen/ThreeMojo/issues/117)

<details>
<summary>Ported: 7</summary>

- [x] [Mesh, with geometry, material and texture stores](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets) [#25](https://github.com/SethKitchen/ThreeMojo/issues/25)
- [x] [Line, LineLoop and LineSegments](https://github.com/SethKitchen/ThreeMojo/wiki/Lines): points joined by one-pixel strokes, walked by one rule both backends read [#26](https://github.com/SethKitchen/ThreeMojo/issues/26)
- [x] [Points](https://github.com/SethKitchen/ThreeMojo/wiki/Points-and-sprites#points): vertices drawn as squares of pixels, sized by distance, covered by one rule both backends read [#27](https://github.com/SethKitchen/ThreeMojo/issues/27)
- [x] [Sprite](https://github.com/SethKitchen/ThreeMojo/wiki/Points-and-sprites#sprites): a square that always faces the camera, built in camera space and drawn as two triangles [#28](https://github.com/SethKitchen/ThreeMojo/issues/28)
- [x] [InstancedMesh and BatchedMesh](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets#instancedmesh): one geometry, or one geometry per instance, at many transforms under one node, culled instance by instance [#29](https://github.com/SethKitchen/ThreeMojo/issues/29)
- [x] [SkinnedMesh, Bone and Skeleton](https://github.com/SethKitchen/ThreeMojo/wiki/Skinning): bones that are scene nodes, and a skeleton saying how far each has moved since the bind [#30](https://github.com/SethKitchen/ThreeMojo/issues/30)
- [x] [LOD](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets#lod): one of several geometries at a node, picked by the camera's distance each frame, with hysteresis [#31](https://github.com/SethKitchen/ThreeMojo/issues/31)

</details>

### Materials

- [ ] Ambient occlusion map and light map [#118](https://github.com/SethKitchen/ThreeMojo/issues/118)
- [ ] Displacement map [#119](https://github.com/SethKitchen/ThreeMojo/issues/119)
- [ ] Specular map and flat shading [#120](https://github.com/SethKitchen/ThreeMojo/issues/120)
- [ ] Transmission, thickness, attenuation and dispersion [#121](https://github.com/SethKitchen/ThreeMojo/issues/121)
- [ ] Sheen, iridescence and anisotropy [#122](https://github.com/SethKitchen/ThreeMojo/issues/122)
- [ ] Depth, color and stencil state [#124](https://github.com/SethKitchen/ThreeMojo/issues/124)
- [ ] MeshDistanceMaterial, depth packings and Material.fog [#125](https://github.com/SethKitchen/ThreeMojo/issues/125)
- [ ] Custom shading: ShaderMaterial and node materials [#126](https://github.com/SethKitchen/ThreeMojo/issues/126)

<details>
<summary>Ported: 19</summary>

- [x] [MeshLambertMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#kind): lit per fragment [#32](https://github.com/SethKitchen/ThreeMojo/issues/32)
- [x] [MeshBasicMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#kind): unlit [#33](https://github.com/SethKitchen/ThreeMojo/issues/33)
- [x] [Front, back and double side](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#side) [#34](https://github.com/SethKitchen/ThreeMojo/issues/34)
- [x] [Opacity and blending](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#opacity-and-blending) [#35](https://github.com/SethKitchen/ThreeMojo/issues/35)
- [x] [Additive, subtractive, multiply and custom blending](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#blending-modes): three.js's modes and WebGL's factors and equations, one function both rasterizers call [#123](https://github.com/SethKitchen/ThreeMojo/issues/123)
- [x] [Color map](https://github.com/SethKitchen/ThreeMojo/wiki/Materials): a texture on a material [#36](https://github.com/SethKitchen/ThreeMojo/issues/36)
- [x] [MeshPhongMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#phong): a highlight on Blinn's half vector that follows the camera, tinted by the specular and not by the color [#37](https://github.com/SethKitchen/ThreeMojo/issues/37)
- [x] [MeshStandardMaterial and MeshPhysicalMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#standard-and-physical): a metalness and a roughness through a GGX lobe and the split sum, with a clear coat [#38](https://github.com/SethKitchen/ThreeMojo/issues/38)
- [x] [MeshNormalMaterial and MeshDepthMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#data-materials): the view-space normal as a color and the depth as a gray, written as bytes no curve touches [#39](https://github.com/SethKitchen/ThreeMojo/issues/39)
- [x] [MeshToonMaterial and MeshMatcapMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#toon): a gradient ramp on the diffuse term, and an image looked up by which way a surface is turned [#40](https://github.com/SethKitchen/ThreeMojo/issues/40)
- [x] [LineBasicMaterial and LineDashedMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Lines#dashed-lines): a `BASIC` material draws a line, and `line_dashed_material` draws it in dashes measured along the line, on both backends [#41](https://github.com/SethKitchen/ThreeMojo/issues/41)
- [x] [PointsMaterial and SpriteMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Points-and-sprites#what-a-point-is-drawn-with): `points_material` with a `PointSize` and an attenuation, `sprite_material` with a rotation, both `BASIC` and both mapped [#42](https://github.com/SethKitchen/ThreeMojo/issues/42)
- [x] [ShadowMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#shadow-material): `shadow_material`, transparent where the lights reach and its color where they are blocked, on both backends [#43](https://github.com/SethKitchen/ThreeMojo/issues/43)
- [x] [Normal maps and bump maps](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#normal-maps-and-bump-maps): a tangent frame from the derivatives at every fragment, with no tangent attribute, on both backends [#44](https://github.com/SethKitchen/ThreeMojo/issues/44)
- [x] [Emissive color and emissive map](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#emissive): light a surface gives off, added after the lights on both rasterizers [#45](https://github.com/SethKitchen/ThreeMojo/issues/45)
- [x] [Alpha map and alpha test](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#alpha-map-and-alpha-test): a map's green channel thins a surface, and a test cuts away what claims no depth [#46](https://github.com/SethKitchen/ThreeMojo/issues/46)
- [x] [Vertex colors](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#vertex-colors): a `color` attribute that multiplies the material color at every vertex, on both rasterizers [#47](https://github.com/SethKitchen/ThreeMojo/issues/47)
- [x] [Wireframe rendering](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#wireframe): a material flag that sends a mesh through the whole pipeline and cuts its triangles into segments at the end [#48](https://github.com/SethKitchen/ThreeMojo/issues/48)
- [x] [Texture transforms: repeat, offset, rotation](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#transform): a texture's own `offset`, `repeat`, `rotation` and `center`, applied to a mesh's coordinates before either rasterizer samples [#49](https://github.com/SethKitchen/ThreeMojo/issues/49)

</details>

### Lights

- [ ] Point light shadows and spot light maps [#127](https://github.com/SethKitchen/ThreeMojo/issues/127)
- [ ] Soft shadows: PCFSoft and VSM [#128](https://github.com/SethKitchen/ThreeMojo/issues/128)
- [ ] Image-based lighting: PMREM and LightProbe [#129](https://github.com/SethKitchen/ThreeMojo/issues/129)

<details>
<summary>Ported: 8</summary>

- [x] [AmbientLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#ambient) [#50](https://github.com/SethKitchen/ThreeMojo/issues/50)
- [x] [DirectionalLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#directional) [#51](https://github.com/SethKitchen/ThreeMojo/issues/51)
- [x] [PointLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#point): inverse-square falloff, decay, cutoff distance [#52](https://github.com/SethKitchen/ThreeMojo/issues/52)
- [x] [Per-fragment Lambert shading](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#shading) [#53](https://github.com/SethKitchen/ThreeMojo/issues/53)
- [x] [SpotLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#spot): a bulb with a cone, a penumbra and a target, on both rasterizers [#54](https://github.com/SethKitchen/ThreeMojo/issues/54)
- [x] [HemisphereLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#hemisphere): a sky color and a ground color, blended by how far a surface is turned toward the sky [#55](https://github.com/SethKitchen/ThreeMojo/issues/55)
- [x] [RectAreaLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#rect-area): a glowing rectangle integrated with linearly transformed cosines from three.js's own tables, on both rasterizers [#56](https://github.com/SethKitchen/ThreeMojo/issues/56)
- [x] [Shadow maps](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#shadows): directional and spot lights draw the scene's depth and every lit sum compares nine taps against it [#57](https://github.com/SethKitchen/ThreeMojo/issues/57)

</details>

### Textures

- [ ] HDR images: RGBE and OpenEXR loaders, and float textures [#130](https://github.com/SethKitchen/ThreeMojo/issues/130)
- [ ] KTX2 and more compressed formats [#131](https://github.com/SethKitchen/ThreeMojo/issues/131)
- [ ] Data3DTexture and DataArrayTexture [#132](https://github.com/SethKitchen/ThreeMojo/issues/132)

<details>
<summary>Ported: 13</summary>

- [x] [Texture with repeat, clamp and mirror wrapping](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#wrap) [#58](https://github.com/SethKitchen/ThreeMojo/issues/58)
- [x] [Nearest and bilinear filters](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#filter) [#59](https://github.com/SethKitchen/ThreeMojo/issues/59)
- [x] [Mipmaps and trilinear filtering](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#mipmaps) [#60](https://github.com/SethKitchen/ThreeMojo/issues/60)
- [x] [sRGB and linear color spaces](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#color-space) [#61](https://github.com/SethKitchen/ThreeMojo/issues/61)
- [x] [PNG loader](https://github.com/SethKitchen/ThreeMojo/wiki/Image-files#read-a-png): every 8-bit color type, every filter, both Huffman block types [#62](https://github.com/SethKitchen/ThreeMojo/issues/62)
- [x] [CubeTexture and environment maps](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#cube-textures): six faces sampled by direction, reflected by a basic, lambert or phong material's `env_map` on both rasterizers [#63](https://github.com/SethKitchen/ThreeMojo/issues/63)
- [x] [DataTexture](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#from-numbers): `data_texture`, a linear texture from one to four fractions a texel, quantized without a curve [#64](https://github.com/SethKitchen/ThreeMojo/issues/64)
- [x] [CompressedTexture](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#from-a-compressed-file): BC1 and BC3 blocks decoded on the host into an ordinary texture [#65](https://github.com/SethKitchen/ThreeMojo/issues/65)
- [x] [DepthTexture](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#from-a-render): `depth_texture_of` and `RenderTarget.depth_texture`, the depth buffer as eight-bit window-space gray, a preview and not a depth to compare [#66](https://github.com/SethKitchen/ThreeMojo/issues/66)
- [x] [Anisotropic filtering](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#anisotropy): `texture.anisotropy`, several taps along the long axis of a footprint at the short axis's level, on both rasterizers [#67](https://github.com/SethKitchen/ThreeMojo/issues/67)
- [x] [Render target as a texture](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#from-a-render): `texture_of` and `RenderTarget.texture`, a render sampled by the next one [#68](https://github.com/SethKitchen/ThreeMojo/issues/68)
- [x] [JPEG loader](https://github.com/SethKitchen/ThreeMojo/wiki/Image-files#read-a-jpeg): baseline Huffman coding, gray and YCbCr, any subsampling, restart intervals, held to two levels of libjpeg [#69](https://github.com/SethKitchen/ThreeMojo/issues/69)
- [x] [Progressive JPEG and TGA](https://github.com/SethKitchen/ThreeMojo/wiki/Image-files#progressive-files): spectral selection and successive approximation, and TGA in color-mapped, true color and gray, plain or run-length [#133](https://github.com/SethKitchen/ThreeMojo/issues/133)

</details>

### Loaders and exporters

- [ ] glTF skins, animations, morph targets, cameras and sparse accessors [#134](https://github.com/SethKitchen/ThreeMojo/issues/134)
- [ ] glTF extensions [#135](https://github.com/SethKitchen/ThreeMojo/issues/135)
- [ ] FBX and Collada loaders [#138](https://github.com/SethKitchen/ThreeMojo/issues/138)
- [ ] Exporters: glTF, OBJ, STL and PLY [#139](https://github.com/SethKitchen/ThreeMojo/issues/139)
- [ ] JSON scene format: ObjectLoader and toJSON [#140](https://github.com/SethKitchen/ThreeMojo/issues/140)

<details>
<summary>Ported: 4</summary>

- [x] [GLTF loader](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#gltf): `.gltf` and `.glb` into geometries, standard materials, textures and a node hierarchy, with a JSON reader of its own [#70](https://github.com/SethKitchen/ThreeMojo/issues/70)
- [x] [OBJ loader](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files): positions, texture coordinates, normals and polygon faces, split by object and material [#71](https://github.com/SethKitchen/ThreeMojo/issues/71)
- [x] [STL and PLY loaders](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#stl): ASCII and binary STL with face colors, and PLY in all three encodings and every scalar type [#137](https://github.com/SethKitchen/ThreeMojo/issues/137)
- [x] [OBJ material libraries](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#material-libraries): an MTL reader building Phong materials and their textures, mapped to each OBJ object [#136](https://github.com/SethKitchen/ThreeMojo/issues/136)

</details>

### Rendering

- [ ] Anti-aliasing passes: FXAA, SMAA and TAA [#141](https://github.com/SethKitchen/ThreeMojo/issues/141)
- [ ] Screen-space passes: SSAO, SAO, SSR and outline [#142](https://github.com/SethKitchen/ThreeMojo/issues/142)
- [ ] Bokeh, glitch, halftone, mask, clear and texture passes [#143](https://github.com/SethKitchen/ThreeMojo/issues/143)
- [ ] Post-processing on the GPU backend [#144](https://github.com/SethKitchen/ThreeMojo/issues/144)
- [ ] Logarithmic and reversed depth buffers [#145](https://github.com/SethKitchen/ThreeMojo/issues/145)
- [ ] Multiple render targets and float render targets [#146](https://github.com/SethKitchen/ThreeMojo/issues/146)

<details>
<summary>Ported: 16</summary>

- [x] [Depth buffer](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#depth) [#72](https://github.com/SethKitchen/ThreeMojo/issues/72)
- [x] [Backface culling](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#culling) [#73](https://github.com/SethKitchen/ThreeMojo/issues/73)
- [x] [Near and far clipping](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#clipping) [#74](https://github.com/SethKitchen/ThreeMojo/issues/74)
- [x] [Perspective-correct interpolation](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#interpolation) [#75](https://github.com/SethKitchen/ThreeMojo/issues/75)
- [x] [Alpha blending with sorted draw order](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#transparency) [#76](https://github.com/SethKitchen/ThreeMojo/issues/76)
- [x] [Linear-light compositing and sRGB output](https://github.com/SethKitchen/ThreeMojo/wiki/Render-target-and-framebuffer) [#77](https://github.com/SethKitchen/ThreeMojo/issues/77)
- [x] [Multithreaded CPU renderer](https://github.com/SethKitchen/ThreeMojo/wiki/Renderer#workers) [#78](https://github.com/SethKitchen/ThreeMojo/issues/78)
- [x] [GPU rasterizer](https://github.com/SethKitchen/ThreeMojo/wiki/GPU-backend): the same rasterizer as a MAX kernel [#79](https://github.com/SethKitchen/ThreeMojo/issues/79)
- [x] [PNG, APNG and PPM writers](https://github.com/SethKitchen/ThreeMojo/wiki/Image-files) [#80](https://github.com/SethKitchen/ThreeMojo/issues/80)
- [x] [Frustum culling](https://github.com/SethKitchen/ThreeMojo/wiki/Renderer#frustum-culling): a mesh whose bounding sphere lies outside the view is skipped before a vertex of it is transformed [#81](https://github.com/SethKitchen/ThreeMojo/issues/81)
- [x] [Tone mapping](https://github.com/SethKitchen/ThreeMojo/wiki/Render-target-and-framebuffer#tone-mapping): three.js's six curves and an exposure, applied once to the composited light of each pixel, on both backends [#82](https://github.com/SethKitchen/ThreeMojo/issues/82)
- [x] [Anti-aliasing](https://github.com/SethKitchen/ThreeMojo/wiki/Renderer#anti-aliasing): `set_antialias`, four samples a pixel by supersampling, averaged in linear light [#83](https://github.com/SethKitchen/ThreeMojo/issues/83)
- [x] [Scissor and viewport](https://github.com/SethKitchen/ThreeMojo/wiki/Renderer#viewport-and-scissor): `set_viewport`, `set_scissor` and `set_scissor_test`, enforced by both backends, and `render_into` for a split screen in one target [#84](https://github.com/SethKitchen/ThreeMojo/issues/84)
- [x] [Post-processing](https://github.com/SethKitchen/ThreeMojo/wiki/Post-processing): an `EffectComposer` with render, copy, blur, bloom, film, dot screen, sepia, vignette, luminosity, afterimage and output passes over the frame's light [#85](https://github.com/SethKitchen/ThreeMojo/issues/85)
- [x] [Helpers: axes, grid, box, camera](https://github.com/SethKitchen/ThreeMojo/wiki/Helpers): line geometries for the axes, a ground grid, the box around a mesh and a camera's frustum [#86](https://github.com/SethKitchen/ThreeMojo/issues/86)
- [x] [Light, arrow, plane, skeleton and normals helpers](https://github.com/SethKitchen/ThreeMojo/wiki/Helpers#arrowhelper): arrow, polar grid, plane, skeleton, light, and vertex normal and tangent helpers as line geometries [#150](https://github.com/SethKitchen/ThreeMojo/issues/150)

</details>

### Windowing and controls

- [ ] A native window [#108](https://github.com/SethKitchen/ThreeMojo/issues/108)
- [ ] TerminalWindow: the terminal's size, and resize [#109](https://github.com/SethKitchen/ThreeMojo/issues/109)
- [ ] OrbitControls: orthographic zoom, zoom to cursor, and any camera up [#105](https://github.com/SethKitchen/ThreeMojo/issues/105)
- [ ] Trackball, Fly, FirstPerson, Map and PointerLock controls [#106](https://github.com/SethKitchen/ThreeMojo/issues/106)
- [ ] TransformControls and DragControls [#107](https://github.com/SethKitchen/ThreeMojo/issues/107)

<details>
<summary>Ported: 1</summary>

- [x] [Windowing and interactive controls](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls): a `TerminalWindow` that shows frames and reads the mouse, and `OrbitControls` that orbit a camera [#87](https://github.com/SethKitchen/ThreeMojo/issues/87)

</details>

### Animation

- [ ] Smooth and cubic-spline keyframe interpolation [#149](https://github.com/SethKitchen/ThreeMojo/issues/149)

<details>
<summary>Ported: 5</summary>

- [x] [AnimationMixer, AnimationClip and KeyframeTrack](https://github.com/SethKitchen/ThreeMojo/wiki/Animation): keyframes on a node's position, scale and rotation, blended by weight across the actions playing [#88](https://github.com/SethKitchen/ThreeMojo/issues/88)
- [x] [Animation fades, cross-fades, warps and events](https://github.com/SethKitchen/ThreeMojo/wiki/Animation#fades-warps-and-start-times): fades, cross-fades, warps, halt, start times, and loop and finished events drained from the mixer [#147](https://github.com/SethKitchen/ThreeMojo/issues/147)
- [x] [Property tracks, bindings and AnimationUtils](https://github.com/SethKitchen/ThreeMojo/wiki/Animation#a-track-names-a-target-not-a-string): tracks on visibility, morph targets, materials and lights, typed bindings, object groups, subclips and additive clips [#148](https://github.com/SethKitchen/ThreeMojo/issues/148)
- [x] [Morph targets](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#morph-targets): a second set of positions per geometry and a weight per mesh, blended into the vertex before it is projected [#89](https://github.com/SethKitchen/ThreeMojo/issues/89)
- [x] [Skinning](https://github.com/SethKitchen/ThreeMojo/wiki/Skinning#the-arithmetic): four bones a vertex, blended into one matrix and applied in `prepare`, so both backends draw it without knowing [#90](https://github.com/SethKitchen/ThreeMojo/issues/90)

</details>

### Math and foundations


<details>
<summary>Ported: 11</summary>

- [x] [Vector2, Vector3, Matrix4 and projection matrices](https://github.com/SethKitchen/ThreeMojo/wiki/Math) [#91](https://github.com/SethKitchen/ThreeMojo/issues/91)
- [x] [Compile-time units](https://github.com/SethKitchen/ThreeMojo/wiki/Units): meters, degrees, dimension checks [#92](https://github.com/SethKitchen/ThreeMojo/issues/92)
- [x] [Coverage tool](https://github.com/SethKitchen/ThreeMojo/wiki/Coverage-tool): line, branch, condition and MC/DC [#93](https://github.com/SethKitchen/ThreeMojo/issues/93)
- [x] [Euler angles from a quaternion](https://github.com/SethKitchen/ThreeMojo/wiki/Rotations#euler-and-eulerorder): all six orders, gimbal lock as in three.js, `Object3D.rotation` [#94](https://github.com/SethKitchen/ThreeMojo/issues/94)
- [x] [Matrix3 and Vector4](https://github.com/SethKitchen/ThreeMojo/wiki/Math#matrix3): the normal matrix at its own size, three.js's uv transform, and homogeneous coordinates that keep their `w` [#95](https://github.com/SethKitchen/ThreeMojo/issues/95)
- [x] [Box3, Sphere and Plane](https://github.com/SethKitchen/ThreeMojo/wiki/Math#box3-sphere-and-plane): bounds that grow, transform and test each other, and a plane with a signed distance [#96](https://github.com/SethKitchen/ThreeMojo/issues/96)
- [x] [Ray and Raycaster](https://github.com/SethKitchen/ThreeMojo/wiki/Raycasting): a ray against spheres, boxes, planes and triangles. A pick through a camera's pixel onto the meshes, instances, batches and LODs [#97](https://github.com/SethKitchen/ThreeMojo/issues/97)
- [x] [Curves and paths](https://github.com/SethKitchen/ThreeMojo/wiki/Curves): line, quadratic and cubic Bezier, and Catmull-Rom curves, joined into a path and closed into a shape with holes [#98](https://github.com/SethKitchen/ThreeMojo/issues/98)
- [x] [Ellipse and arc curves, and 3D curves](https://github.com/SethKitchen/ThreeMojo/wiki/Curves#curves-in-space): path arcs, 3D Bezier and Catmull-Rom curves, Frenet frames, and tubes along curves [#152](https://github.com/SethKitchen/ThreeMojo/issues/152)
- [x] [Color as floats](https://github.com/SethKitchen/ThreeMojo/wiki/Render-target-and-framebuffer#color-and-floatcolor): three.js's hex and HSL setters and getters, lerp, offset and arithmetic on the linear float color [#99](https://github.com/SethKitchen/ThreeMojo/issues/99)
- [x] [Triangle, Line3, Spherical, Cylindrical, Matrix2, Box2 and MathUtils](https://github.com/SethKitchen/ThreeMojo/wiki/Math#triangle-and-line3): barycentric weights, nearest points, segment distances, and three.js's seeded random numbers [#151](https://github.com/SethKitchen/ThreeMojo/issues/151)

</details>

<!-- /features -->

### Out of scope

Browser-only features have no place in a software renderer: the WebGL and WebGPU renderers, the CSS renderers, WebXR, audio, and video and canvas textures.

## Contributing

Open an issue before a large change. Run `make check` before you commit. Coverage must stay at 100%. Documentation must pass `make docs-check`. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules and the steps to add a feature.

## License

ThreeMojo is free for noncommercial use under the [PolyForm Noncommercial License 1.0.0](LICENSE): personal projects, study, research, and use by charities, schools and government bodies.

Commercial use requires a paid license. See [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md).

Copyright © 2026 Seth Kitchen, PE.

`math/` and `render/` are ported from three.js, which is MIT licensed. Those notices are preserved in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Nothing here restricts your rights in three.js itself. `coverage/` is original work with no three.js lineage.
