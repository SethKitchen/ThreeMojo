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

The port is not at parity with three.js yet. 173 features are ported and 7 are open. Each section lists its open items first. Open the dropdown under a section to see what is ported.

<!-- features -->
### Scene


<details>
<summary>Ported: 15</summary>

- [x] [Scene graph](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-graph): `Object3D`, `Scene`, parent and child transforms [#1](https://github.com/SethKitchen/ThreeMojo/issues/1)
- [x] [Edit the scene graph](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-graph#edit-the-graph): reparent, attach, remove, clone and traverse nodes; world-space queries; Group and userData in scene JSON. [#165](https://github.com/SethKitchen/ThreeMojo/issues/165)
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
- [x] [Camera API and raycast hit data](https://github.com/SethKitchen/ThreeMojo/wiki/Cameras#view-offset): zoom, film, focal length and view offset, and raycast uv, face, barycoord and point-on-line data. [#172](https://github.com/SethKitchen/ThreeMojo/issues/172)

</details>

### Geometry


<details>
<summary>Ported: 19</summary>

- [x] [BufferGeometry and BufferAttribute](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry) [#12](https://github.com/SethKitchen/ThreeMojo/issues/12)
- [x] [Geometry addons](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry-addons): teapot, box lines, modifiers, BufferGeometryUtils, MikkTSpace tangents, SceneUtils, NURBS and named curves. [#180](https://github.com/SethKitchen/ThreeMojo/issues/180)
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
- [x] [Extrude a shape along a path](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#along-a-path): a shape swept along a 3D curve in its Frenet frames [#113](https://github.com/SethKitchen/ThreeMojo/issues/113)
- [x] [EdgesGeometry and WireframeGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#edges-and-wireframes): a surface read back as the lines of its edges, welded by position first [#23](https://github.com/SethKitchen/ThreeMojo/issues/23)
- [x] [computeVertexNormals and bounding volumes](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#buffergeometry): area-weighted normals, a bounding box and a bounding sphere on any geometry [#24](https://github.com/SethKitchen/ThreeMojo/issues/24)
- [x] [BufferGeometryUtils: merge, non-indexed, merge vertices, tangents, center](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#merge-weld-and-tangents): merge geometries, weld vertices, creased normals, non-indexed copies, centering and tangents with handedness [#110](https://github.com/SethKitchen/ThreeMojo/issues/110)
- [x] [TextGeometry and FontLoader](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#text): typeface.js fonts laid out as shapes with holes and extruded, as in three.js [#114](https://github.com/SethKitchen/ThreeMojo/issues/114)
- [x] [Interleaved buffers and InstancedBufferGeometry](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#interleaved-buffers): attributes sharing one strided array, and instanced geometry drawn per instance with offsets and colors [#111](https://github.com/SethKitchen/ThreeMojo/issues/111)

</details>

### Objects

- [ ] Skeleton, morph, batch and LOD tools [#181](https://github.com/SethKitchen/ThreeMojo/issues/181)
- [ ] Scene objects: Reflector, Refractor, Water, Sky, Lensflare, MarchingCubes [#177](https://github.com/SethKitchen/ThreeMojo/issues/177)

<details>
<summary>Ported: 11</summary>

- [x] [Multi-material meshes](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets#several-materials): geometry groups drawn with a material list by both rasterizers, the raycaster, loaders, exporters and SceneUtils [#167](https://github.com/SethKitchen/ThreeMojo/issues/167)
- [x] [Mesh, with geometry, material and texture stores](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets) [#25](https://github.com/SethKitchen/ThreeMojo/issues/25)
- [x] [Line, LineLoop and LineSegments](https://github.com/SethKitchen/ThreeMojo/wiki/Lines): points joined by one-pixel strokes, walked by one rule both backends read [#26](https://github.com/SethKitchen/ThreeMojo/issues/26)
- [x] [Points](https://github.com/SethKitchen/ThreeMojo/wiki/Points-and-sprites#points): vertices drawn as squares of pixels, sized by distance, covered by one rule both backends read [#27](https://github.com/SethKitchen/ThreeMojo/issues/27)
- [x] [Sprite](https://github.com/SethKitchen/ThreeMojo/wiki/Points-and-sprites#sprites): a square that always faces the camera, built in camera space and drawn as two triangles [#28](https://github.com/SethKitchen/ThreeMojo/issues/28)
- [x] [InstancedMesh and BatchedMesh](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets#instancedmesh): one geometry, or one geometry per instance, at many transforms under one node, culled instance by instance [#29](https://github.com/SethKitchen/ThreeMojo/issues/29)
- [x] [SkinnedMesh, Bone and Skeleton](https://github.com/SethKitchen/ThreeMojo/wiki/Skinning): bones that are scene nodes, and a skeleton saying how far each has moved since the bind [#30](https://github.com/SethKitchen/ThreeMojo/issues/30)
- [x] [LOD](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets#lod): one of several geometries at a node, picked by the camera's distance each frame, with hysteresis [#31](https://github.com/SethKitchen/ThreeMojo/issues/31)
- [x] [Per-instance colors](https://github.com/SethKitchen/ThreeMojo/wiki/Meshes-and-assets#instance-colors): a color per instance of an instanced or batched mesh that multiplies the material color [#112](https://github.com/SethKitchen/ThreeMojo/issues/112)
- [x] [Raycasting lines, points, sprites and skinned meshes](https://github.com/SethKitchen/ThreeMojo/wiki/Raycasting#lines-points-and-sprites): skinned meshes picked where the bones carry them, with three.js's line and point thresholds [#117](https://github.com/SethKitchen/ThreeMojo/issues/117)
- [x] [Wide lines: Line2, LineSegments2 and LineMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Lines#wide-lines): lines of any width in pixels or meters, with round caps, dashes, vertex colors and picking [#116](https://github.com/SethKitchen/ThreeMojo/issues/116)

</details>

### Materials


<details>
<summary>Ported: 30</summary>

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
- [x] [Depth, color and stencil state](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#depth-color-and-stencil): depth test, write and function, color write, polygon offset, and an eight-bit stencil buffer [#124](https://github.com/SethKitchen/ThreeMojo/issues/124)
- [x] [Ambient occlusion map and light map](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#ambient-occlusion-map): baked maps that dim or add indirect light, read from a second set of texture coordinates [#118](https://github.com/SethKitchen/ThreeMojo/issues/118)
- [x] [Specular map and flat shading](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#specular-map): highlights and reflections scaled by a map, and faces lit by their own normals [#120](https://github.com/SethKitchen/ThreeMojo/issues/120)
- [x] [Displacement map](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#displacement-map): vertices moved along their normals by a map, and drawn, shadowed and picked where they moved [#119](https://github.com/SethKitchen/ThreeMojo/issues/119)
- [x] [Transmission, thickness, attenuation and dispersion](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#transmission): the opaque scene drawn first, then refracted, blurred and tinted through physical surfaces on both backends [#121](https://github.com/SethKitchen/ThreeMojo/issues/121)
- [x] [Sheen, iridescence and anisotropy](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#sheen): Charlie sheen, thin-film Fresnel and stretched GGX on physical materials, with their maps and glTF extensions. [#122](https://github.com/SethKitchen/ThreeMojo/issues/122)
- [x] [Node materials and ShaderMaterial](https://github.com/SethKitchen/ThreeMojo/wiki/Node-materials): expression graphs compiled to bytecode, run by both rasterizers. [#126](https://github.com/SethKitchen/ThreeMojo/issues/126)
- [x] [Node library and GLSL source](https://github.com/SethKitchen/ThreeMojo/wiki/Node-materials#glsl-source): the rest of the TSL library, control flow, varyings, derivatives, noise, and a GLSL subset for ShaderMaterial. [#162](https://github.com/SethKitchen/ThreeMojo/issues/162)
- [x] [Specular and clearcoat maps](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#specular-and-clearcoat-maps): specular intensity and color, clear coat, roughness and normal maps on both rasterizers, in glTF and in scene JSON. [#159](https://github.com/SethKitchen/ThreeMojo/issues/159)
- [x] [Per-map texture transforms](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#transform): each map samples at its own transform and channel, and physical materials add three.js's geometric roughness. [#161](https://github.com/SethKitchen/ThreeMojo/issues/161)
- [x] [MeshDistanceMaterial, depth packings and Material.fog](https://github.com/SethKitchen/ThreeMojo/wiki/Materials#meshdistancematerial): distance from a point, the four depth packings, and a per-material fog switch [#125](https://github.com/SethKitchen/ThreeMojo/issues/125)

</details>

### Lights

- [ ] Shadow camera frustum, light power, CSM and room environments [#173](https://github.com/SethKitchen/ThreeMojo/issues/173)

<details>
<summary>Ported: 12</summary>

- [x] [AmbientLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#ambient) [#50](https://github.com/SethKitchen/ThreeMojo/issues/50)
- [x] [DirectionalLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#directional) [#51](https://github.com/SethKitchen/ThreeMojo/issues/51)
- [x] [PointLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#point): inverse-square falloff, decay, cutoff distance [#52](https://github.com/SethKitchen/ThreeMojo/issues/52)
- [x] [Per-fragment Lambert shading](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#shading) [#53](https://github.com/SethKitchen/ThreeMojo/issues/53)
- [x] [SpotLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#spot): a bulb with a cone, a penumbra and a target, on both rasterizers [#54](https://github.com/SethKitchen/ThreeMojo/issues/54)
- [x] [HemisphereLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#hemisphere): a sky color and a ground color, blended by how far a surface is turned toward the sky [#55](https://github.com/SethKitchen/ThreeMojo/issues/55)
- [x] [RectAreaLight](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#rect-area): a glowing rectangle integrated with linearly transformed cosines from three.js's own tables, on both rasterizers [#56](https://github.com/SethKitchen/ThreeMojo/issues/56)
- [x] [Shadow maps](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#shadows): directional and spot lights draw the scene's depth and every lit sum compares nine taps against it [#57](https://github.com/SethKitchen/ThreeMojo/issues/57)
- [x] [Point light shadows and spot light maps](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#point-light-shadows): point light shadows through six cube faces, and spot lights that project a texture [#127](https://github.com/SethKitchen/ThreeMojo/issues/127)
- [x] [Image-based lighting: PMREM and LightProbe](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#pmrem): environments prefiltered per roughness for physical surfaces, and light probes of nine spherical-harmonic colors [#129](https://github.com/SethKitchen/ThreeMojo/issues/129)
- [x] [Faster PMREM prefiltering](https://github.com/SethKitchen/ThreeMojo/wiki/Benchmarks#pmrem-and-the-coverage-run): the blur and hot texture helpers cut coverage capture by up to 74%, with bit-identical output. [#157](https://github.com/SethKitchen/ThreeMojo/issues/157)
- [x] [Soft shadows: PCFSoft and VSM](https://github.com/SethKitchen/ThreeMojo/wiki/Lights#soft-shadows): basic, PCF, soft PCF or variance shadow maps, chosen on the renderer as in three.js [#128](https://github.com/SethKitchen/ThreeMojo/issues/128)

</details>

### Textures


<details>
<summary>Ported: 19</summary>

- [x] [Texture sampling, environment mapping and background parameters](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#mapping): per-axis wrap, filters, flipY, equirectangular and cube mappings, and the scene's background and environment settings [#171](https://github.com/SethKitchen/ThreeMojo/issues/171)
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
- [x] [HDR images: RGBE and OpenEXR, and float textures](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#hdr-images): Radiance HDR and OpenEXR loaders, float textures, and panoramas as backgrounds and environments [#130](https://github.com/SethKitchen/ThreeMojo/issues/130)
- [x] [KTX2 and more compressed formats](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#ktx2-and-compressed-formats): KTX2, KTX and DDS files, with BC2 to BC7, ETC and EAC blocks decoded into textures [#131](https://github.com/SethKitchen/ThreeMojo/issues/131)
- [x] [KTX2 Zstandard and Basis Universal](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#basis-universal): Zstandard supercompression, and UASTC and ETC1S decoded to RGBA as three.js transcodes them. [#156](https://github.com/SethKitchen/ThreeMojo/issues/156)
- [x] [KTX2 UASTC HDR and ETC1S video](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#basis-universal): UASTC HDR 4x4 decoded to floats, and ETC1S video with P-frames, as three.js's transcoder decodes them. [#163](https://github.com/SethKitchen/ThreeMojo/issues/163)
- [x] [Data3DTexture and DataArrayTexture](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#3d-textures): volume and layered textures with GLSL sampling, a LUT pass and a .cube loader [#132](https://github.com/SethKitchen/ThreeMojo/issues/132)

</details>

### Loaders and exporters

- [ ] More loaders and exporters: 3MF, PCD, SVG, Draco, VRML, 3DS, BVH and others [#176](https://github.com/SethKitchen/ThreeMojo/issues/176)
- [ ] glTF: export lights, cameras, animations, skins, morphs and instancing; read bump, basisu and webp [#168](https://github.com/SethKitchen/ThreeMojo/issues/168)

<details>
<summary>Ported: 15</summary>

- [x] [FBX and Collada skins and animation](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#skins-blend-shapes-and-animation): skins, blend shapes and animations read into skinned meshes, morph targets and clips [#175](https://github.com/SethKitchen/ThreeMojo/issues/175)
- [x] [GLTF loader](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#gltf): `.gltf` and `.glb` into geometries, standard materials, textures and a node hierarchy, with a JSON reader of its own [#70](https://github.com/SethKitchen/ThreeMojo/issues/70)
- [x] [OBJ loader](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files): positions, texture coordinates, normals and polygon faces, split by object and material [#71](https://github.com/SethKitchen/ThreeMojo/issues/71)
- [x] [STL and PLY loaders](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#stl): ASCII and binary STL with face colors, and PLY in all three encodings and every scalar type [#137](https://github.com/SethKitchen/ThreeMojo/issues/137)
- [x] [OBJ material libraries](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#material-libraries): an MTL reader building Phong materials and their textures, mapped to each OBJ object [#136](https://github.com/SethKitchen/ThreeMojo/issues/136)
- [x] [PCD and 3MF loaders](https://github.com/SethKitchen/ThreeMojo/wiki/More-model-files): ascii, binary and compressed point clouds, and 3MF packages with a ZIP reader and writer. [#176](https://github.com/SethKitchen/ThreeMojo/issues/176)
- [x] [Exporters: glTF, OBJ, STL and PLY](https://github.com/SethKitchen/ThreeMojo/wiki/Exporters): glTF (.gltf/.glb), OBJ, STL and PLY writers that read back through the project's own loaders [#139](https://github.com/SethKitchen/ThreeMojo/issues/139)
- [x] [glTF skins, animations, morph targets, cameras and sparse accessors](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#skins-morph-targets-and-animations): joints, morph weights, cubic-spline clips, both camera kinds and sparse data [#134](https://github.com/SethKitchen/ThreeMojo/issues/134)
- [x] [Scene JSON: ObjectLoader and toJSON](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-JSON): three.js's JSON object format written and read: nodes, meshes, lights, cameras, materials and textures [#140](https://github.com/SethKitchen/ThreeMojo/issues/140)
- [x] [glTF extensions](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#gltf-extensions): unlit, emissive strength, IOR, specular, clearcoat, texture transform, punctual lights, quantization and GPU instancing [#135](https://github.com/SethKitchen/ThreeMojo/issues/135)
- [x] [glTF occlusion and material export](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#occlusion): occlusion maps and the second UV set; export of texture transforms, emissive strength and physical material extensions. [#154](https://github.com/SethKitchen/ThreeMojo/issues/154)
- [x] [glTF export of sheen, iridescence and anisotropy](https://github.com/SethKitchen/ThreeMojo/wiki/Exporters#sheen-iridescence-and-anisotropy): the three layer extensions, with their maps, channels and texture transforms. [#158](https://github.com/SethKitchen/ThreeMojo/issues/158)
- [x] [Scene JSON: newer fields and objects](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-JSON#other-objects): every newer material field, plus lines, points, sprites, LODs, batched and skinned meshes. [#155](https://github.com/SethKitchen/ThreeMojo/issues/155)
- [x] [Scene JSON: environments and clipping](https://github.com/SethKitchen/ThreeMojo/wiki/Scene-JSON#cube-textures): cube textures, environment maps, clipping planes, distance ranges, morph influences and calculated bone inverses. [#160](https://github.com/SethKitchen/ThreeMojo/issues/160)
- [x] [FBX and Collada loaders](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#collada): Collada and ASCII or binary FBX files read into meshes, materials, textures, nodes, cameras and lights [#138](https://github.com/SethKitchen/ThreeMojo/issues/138)

</details>

### Rendering

- [ ] Render-target features: MSAA, 3D, array and cube targets, texture copies [#174](https://github.com/SethKitchen/ThreeMojo/issues/174)
- [ ] Renderer hooks and material flags [#170](https://github.com/SethKitchen/ThreeMojo/issues/170)

<details>
<summary>Ported: 25</summary>

- [x] [View, light probe, octree and texture helpers, and a shadow map viewer](https://github.com/SethKitchen/ThreeMojo/wiki/Helpers): drawn by both rasterizers, except the view helper [#182](https://github.com/SethKitchen/ThreeMojo/issues/182)
- [x] [More post-processing passes and shader effects](https://github.com/SethKitchen/ThreeMojo/wiki/Post-processing#scene-gtao-and-shader-passes): pixelated, GTAO, transition and shader passes, fifteen screen shaders, god rays, and stereo and outline effects [#178](https://github.com/SethKitchen/ThreeMojo/issues/178)
- [x] [Depth buffer](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#depth) [#72](https://github.com/SethKitchen/ThreeMojo/issues/72)
- [x] [Match three.js where it accepts](https://github.com/SethKitchen/ThreeMojo/wiki/Textures#wrap): clamp by default, lights at their target, the shadow bias order and unnormalized skin weights. [#164](https://github.com/SethKitchen/ThreeMojo/issues/164)
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
- [x] [Anti-aliasing passes: FXAA, SMAA, SSAA and TAA](https://github.com/SethKitchen/ThreeMojo/wiki/Post-processing#anti-aliasing): FXAA and SMAA, and SSAA and TAA averaging jittered samples at once or over frames [#141](https://github.com/SethKitchen/ThreeMojo/issues/141)
- [x] [Screen-space passes: SSAO, SAO, SSR and outline](https://github.com/SethKitchen/ThreeMojo/wiki/Post-processing#screen-space-passes): ambient occlusion, reflections and outlines read from the depth buffer, with seeded sampling [#142](https://github.com/SethKitchen/ThreeMojo/issues/142)
- [x] [Bokeh, glitch, halftone, mask, clear and texture passes](https://github.com/SethKitchen/ThreeMojo/wiki/Post-processing#more-passes): bokeh, glitch, halftone, clear and texture passes, and masks on the stencil buffer [#143](https://github.com/SethKitchen/ThreeMojo/issues/143)
- [x] [Logarithmic and reversed depth buffers](https://github.com/SethKitchen/ThreeMojo/wiki/Rasterization#logarithmic-depth): logarithmic and reversed depth on both backends, with depth readers and passes kept correct [#145](https://github.com/SethKitchen/ThreeMojo/issues/145)
- [x] [Multiple render targets and float render targets](https://github.com/SethKitchen/ThreeMojo/wiki/Render-target-and-framebuffer#float-render-targets): float targets, float depth textures and a normal attachment, filled in one pass [#146](https://github.com/SethKitchen/ThreeMojo/issues/146)
- [x] [Post-processing on the GPU backend](https://github.com/SethKitchen/ThreeMojo/wiki/GPU-backend#post-processing-on-the-gpu): passes run as GPU kernels, keeping the frame on the device between passes [#144](https://github.com/SethKitchen/ThreeMojo/issues/144)

</details>

### Windowing and controls


<details>
<summary>Ported: 7</summary>

- [x] [Windowing and interactive controls](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls): a `TerminalWindow` that shows frames and reads the mouse, and `OrbitControls` that orbit a camera [#87](https://github.com/SethKitchen/ThreeMojo/issues/87)
- [x] [TerminalWindow: the terminal's size, and resize](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls#terminalwindow): the terminal asked its size, the answer a resize event [#109](https://github.com/SethKitchen/ThreeMojo/issues/109)
- [x] [OrbitControls: orthographic zoom, zoom to cursor, and any camera up](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls#orthographic-cameras): orthographic zoom, zoom toward the pointer, and any up [#105](https://github.com/SethKitchen/ThreeMojo/issues/105)
- [x] [Trackball, Fly, FirstPerson, Map and PointerLock controls](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls#trackballcontrols): five more camera controls, with held keys timed out for the terminal [#106](https://github.com/SethKitchen/ThreeMojo/issues/106)
- [x] [TransformControls and DragControls](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls#transformcontrols): drag objects with the pointer, or move, turn and scale one with a pickable gizmo [#107](https://github.com/SethKitchen/ThreeMojo/issues/107)
- [x] [ArcballControls](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls#arcballcontrols): a camera turned on a virtual trackball, with pan, zoom, field-of-view zoom, focus, inertia and a gizmo [#153](https://github.com/SethKitchen/ThreeMojo/issues/153)
- [x] [A native X11 window](https://github.com/SethKitchen/ThreeMojo/wiki/Windowing-and-controls#x11window): an `X11Window` from libX11 that shows frames and reads keys, buttons, resizes and the close button [#108](https://github.com/SethKitchen/ThreeMojo/issues/108)

</details>

### Animation


<details>
<summary>Ported: 7</summary>

- [x] [AnimationMixer, AnimationClip and KeyframeTrack](https://github.com/SethKitchen/ThreeMojo/wiki/Animation): keyframes on a node's position, scale and rotation, blended by weight across the actions playing [#88](https://github.com/SethKitchen/ThreeMojo/issues/88)
- [x] [The rest of the animation API](https://github.com/SethKitchen/ThreeMojo/wiki/Animation): Bezier and string tracks, repetitions, mixer time scale and cache, camera and light tracks, and clip JSON. [#169](https://github.com/SethKitchen/ThreeMojo/issues/169)
- [x] [Animation fades, cross-fades, warps and events](https://github.com/SethKitchen/ThreeMojo/wiki/Animation#fades-warps-and-start-times): fades, cross-fades, warps, halt, start times, and loop and finished events drained from the mixer [#147](https://github.com/SethKitchen/ThreeMojo/issues/147)
- [x] [Property tracks, bindings and AnimationUtils](https://github.com/SethKitchen/ThreeMojo/wiki/Animation#a-track-names-a-target-not-a-string): tracks on visibility, morph targets, materials and lights, typed bindings, object groups, subclips and additive clips [#148](https://github.com/SethKitchen/ThreeMojo/issues/148)
- [x] [Morph targets](https://github.com/SethKitchen/ThreeMojo/wiki/Geometry#morph-targets): a second set of positions per geometry and a weight per mesh, blended into the vertex before it is projected [#89](https://github.com/SethKitchen/ThreeMojo/issues/89)
- [x] [Skinning](https://github.com/SethKitchen/ThreeMojo/wiki/Skinning#the-arithmetic): four bones a vertex, blended into one matrix and applied in `prepare`, so both backends draw it without knowing [#90](https://github.com/SethKitchen/ThreeMojo/issues/90)
- [x] [Smooth and cubic-spline keyframe interpolation](https://github.com/SethKitchen/ThreeMojo/wiki/Animation#smooth-tracks): smooth and glTF cubic-spline interpolation, with three.js's ending modes chosen from each action's loop mode [#149](https://github.com/SethKitchen/ThreeMojo/issues/149)

</details>

### Math and foundations


<details>
<summary>Ported: 13</summary>

- [x] [Vector2, Vector3, Matrix4 and projection matrices](https://github.com/SethKitchen/ThreeMojo/wiki/Math) [#91](https://github.com/SethKitchen/ThreeMojo/issues/91)
- [x] [The three.js math API](https://github.com/SethKitchen/ThreeMojo/wiki/Math#the-threejs-math-api): the missing vector, quaternion, matrix, box, plane and frustum members, object bounds and CSS colors. [#166](https://github.com/SethKitchen/ThreeMojo/issues/166)
- [x] [Compile-time units](https://github.com/SethKitchen/ThreeMojo/wiki/Units): meters, degrees, dimension checks [#92](https://github.com/SethKitchen/ThreeMojo/issues/92)
- [x] [Math addons](https://github.com/SethKitchen/ThreeMojo/wiki/Math-addons): Perlin and simplex noise, OBB, Capsule, Octree collisions, surface sampler, color maps and Display P3 color spaces. [#179](https://github.com/SethKitchen/ThreeMojo/issues/179)
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
