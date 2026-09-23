# Model files

`loaders/obj.mojo`, `loaders/mtl.mojo`, `loaders/stl.mojo`, `loaders/ply.mojo`, `loaders/gltf.mojo`, `loaders/collada.mojo`, `loaders/fbx.mojo` and `loaders/font.mojo`. `read_obj` reads a Wavefront OBJ file into named objects, each with a `BufferGeometry`. `parse_obj` reads the text of one.

`read_obj_with_materials` also reads the OBJ file's material libraries and gives each object a `MaterialId`. `read_stl` and `read_ply` read an STL or a PLY file into one `BufferGeometry`. `read_gltf` reads a glTF 2.0 file, `.gltf` or `.glb`, into a scene and its assets. `read_collada` and `read_fbx` read a [Collada](#collada) or an [FBX](#fbx) file into a scene and its assets. `read_font` reads a typeface.js font, which lays text out as [shapes](#fonts).

![A cube loaded from an OBJ file turns under a lamp](out/model.png)

three.js: `OBJLoader`, `MTLLoader`, `STLLoader`, `PLYLoader`, `GLTFLoader`, `ColladaLoader`, `FBXLoader` and `FontLoader`.

To write these files, see [Exporters](Exporters). To read a scene in three.js JSON, see [Scene JSON](Scene-JSON).

## Read a file

```mojo
var model = read_obj("assets/cube.obj")
for index in range(model.count()):
    print(model.objects[index].name, model.objects[index].material)
var shape = assets.geometries.add(model.objects[0].take_geometry())
```

| Function | Meaning |
|---|---|
| `read_obj(path) -> ObjModel` | Read a file. |
| `parse_obj(text) -> ObjModel` | Read the text of one. |

## ObjModel and ObjObject

`ObjModel.objects` holds one `ObjObject` per object, in file order. `count()` says how many. `ObjModel.material_libraries` holds the file name of each `mtllib` line, in file order.

| Field | Meaning |
|---|---|
| `name` | From `o` or `g`. Empty when the file has neither. Faces read before the first `o` or `g` belong to it, as three.js has it. |
| `material` | The name from `usemtl`. Empty before one. See [Material libraries](#material-libraries). |
| `geometry` | A non-indexed `BufferGeometry` with `position`, and with `normal` and `uv` when the faces name them. |

`take_geometry()` swaps the geometry out for an empty one, so it can go into a store. A `BufferGeometry` moves and does not copy.

## What is read

| Line | Meaning |
|---|---|
| `v x y z` | A position. A fourth number is ignored. |
| `vt u v` | A texture coordinate. |
| `vn x y z` | A normal. |
| `f a b c ...` | A face of three or more corners, cut into a fan of triangles. A polygon must be convex. Each corner is `v`, `v/vt`, `v//vn` or `v/vt/vn`. |
| `o name`, `g name` | A new object. One with no faces is dropped. |
| `usemtl name` | A new object under that material, with the same name. |
| `mtllib name` | A material library. The rest of the line is one file name. |
| `#` | A comment, to the end of the line. |

An index counts from one. A negative index counts back from the last entry so far. `s`, `l`, `p` and unknown lines are skipped.

Every face of one object must agree about normals and texture coordinates. A geometry without normals shades flat. See [Renderer](Renderer).

## Errors

The parser raises, naming the line, for:

- A `v`, `vt` or `vn` line with too few coordinates. A coordinate that is not a number, or is not finite as a `Float32`.
- A face with fewer than three corners, or a corner with more than three parts.
- A face of four or more corners that is not convex, or has no area. A fan covers a convex polygon and only that.
- An index that is not a whole number, is zero, or names an entry the file does not have.
- A face that names a normal or a texture coordinate where an earlier face of the object did not, or the other way round.
- An `mtllib` line with no file name.

`read_obj` raises for a file it cannot read.

## Example

`assets/cube.obj` is a unit cube with normals and texture coordinates. `tests/test_obj.mojo` reads it and draws it.

## Material libraries

`loaders/mtl.mojo`. `read_mtl(path, assets)` reads a Wavefront `.mtl` file into an `MtlLibrary`. It adds one `PHONG` material for each `newmtl` to `assets.materials`, and each image it names to `assets.textures`. three.js: `MTLLoader` and `OBJLoader.setMaterials`.

```mojo
var assets = Assets()
var read = read_obj_with_materials("assets/cube.obj", assets)
var shape = assets.geometries.add(read.model.objects[0].take_geometry())
scene.add_mesh(Mesh(shape, read.materials[0], node))
```

| Function | Meaning |
|---|---|
| `read_mtl(path, assets) -> MtlLibrary` | Read a file. Texture file names are relative to its directory. |
| `parse_mtl(text, directory, assets) -> MtlLibrary` | Read the text of one. `directory` ends in `/`, or is empty. |
| `set_materials(model, library, assets) -> List[MaterialId]` | One `MaterialId` for each object of an `ObjModel`, in its order. |
| `read_obj_with_materials(path, assets) -> ObjWithMaterials` | Read an OBJ file and each library its `mtllib` lines name. |

`ObjWithMaterials` has `model`, the `ObjModel`, `library`, the combined `MtlLibrary`, and `materials`, one `MaterialId` for each object. The loader reads each library relative to the OBJ file. A material in a later library replaces a material of the same name in an earlier one.

### MtlLibrary

| Member | Meaning |
|---|---|
| `names`, `materials` | The name and the `MaterialId` of each material, in the order the names first appear. |
| `count()` | How many materials the library has. |
| `find(name) -> Int` | The index of a name, or -1. |
| `get(name) -> MaterialId` | The material of a name. It raises for a name the library does not have. |
| `add(name, material)` | Add a material. It replaces a material of the same name. |
| `merge(other)` | Add each material of another library. |
| `create(name, assets) -> MaterialId` | The material of a name. For a name the library does not have, it adds a default `PHONG` material once and keeps it. This is three.js's `MaterialCreator.create`. |

An OBJ object with no `usemtl`, or with a name that no library has, gets a default material. Each such name gets its own default, as in three.js.

### What is read

A keyword can be in any case. Each key keeps the last value that a material gives it. The loader applies the keys in the order they first appear, as three.js does.

| Key | Meaning |
|---|---|
| `newmtl name` | A new material. A second `newmtl` of the same name replaces the first. |
| `Kd r g b` | The color. Three numbers from zero to one, in sRGB. |
| `Ks r g b` | The specular color. |
| `Ke r g b` | The emissive color. |
| `Ns n` | The shininess. It must not be negative. |
| `d n` | The opacity, from zero to one. Below one, it sets `opacity` and `transparent`. |
| `Tr n` | The transparency, from zero to one. Above zero, it sets `opacity` to `1 - n` and sets `transparent`. |
| `illum n` | The illumination model, a whole number from 0 to 10. The loader checks it and ignores it, as three.js does. |
| `map_Kd file` | The color map, in sRGB. |
| `map_Ke file` | The emissive map, in sRGB. |
| `map_d file` | The alpha map, as data. It also sets `transparent`. |
| `map_bump file`, `bump file` | The bump map, as data. The first of the two is kept. |
| `norm file` | The normal map, as data. |
| `#` | A comment, to the end of the line. |

The defaults are those of three.js's `MeshPhongMaterial`: a white color, a specular of `0x111111`, a shininess of 30, no emissive color, and opaque. Lines before the first `newmtl` are skipped. A key with no value is skipped. `Ka`, `map_Ka` and unknown keys are skipped, as three.js skips them.

A material that has a normal map and a bump map keeps the normal map. three.js ignores the bump map in that case, and `Material` refuses both.

### Texture options

A texture line has options, then a file name. The file name can contain spaces.

| Option | Meaning |
|---|---|
| `-s u v w` | The texture's `repeat`. `w` is ignored. When `v` is missing, it is one. |
| `-o u v w` | The texture's `offset`. `w` is ignored. When `v` is missing, it is zero. |
| `-bm n` | The material's `bump_scale`, on any texture line, as three.js reads it. |
| `-mm base gain` | Read and ignored. It scales a displacement map, which is not ported. |
| `-clamp on`, `-clamp off` | `CLAMP` or `REPEAT` wrap. three.js always repeats. |

A texture repeats by default, as in three.js. The loader decodes PNG, JPEG and TGA images, and tells them apart by their first bytes. A color map is `SRGB`, and its alpha is coverage. An emissive map is `SRGB`, and its alpha is `IGNORED`. An alpha map, a bump map and a normal map are `LINEAR`, and their alpha is `IGNORED`. One image read the same way twice gives one texture.

### Differences from three.js

- `map_Ks`, the specular map, is skipped. `Material` has no specular map.
- `disp`, the displacement map, is skipped. No material moves its vertices.
- The options of `MTLLoader` are not ported: `side`, `wrap`, `normalizeRGB`, `ignoreZeroRGBs` and `invertTrProperty`.
- An unknown texture option is refused. three.js reads it as part of the file name, and then cannot load the file.
- A color above one is refused. `Color` holds eight bits for each channel.

### Errors

The loader raises, and names the line, for:

- A `newmtl` line with no name.
- A color that is not three numbers from zero to one.
- An `Ns` that is not a number, is not finite, or is negative.
- A `d` or `Tr` outside zero to one.
- An `illum` that is not a whole number from 0 to 10.
- A texture option that is not known, or does not have its numbers. A `-clamp` without `on` or `off`.
- A texture line with no file name.
- An image that the loader cannot read or decode.

`read_mtl` and `read_obj_with_materials` also raise for a file that they cannot read.

### Example

`assets/cube.mtl` is the `Brick` material that `assets/cube.obj` names, with the texture `assets/brick.png`. `assets/mtl/` holds an OBJ file with two libraries. `tests/test_mtl.mojo` reads them and draws the cube.

## STL

`loaders/stl.mojo`. `read_stl(path)` reads an STL file, binary or ASCII, into an `StlModel`. three.js: `STLLoader`.

```mojo
var model = read_stl("assets/tetrahedron.stl")
print(model.geometry.triangle_count(), model.has_colors(), model.alpha)
var shape = assets.geometries.add(model.take_geometry())
```

| Function | Meaning |
|---|---|
| `read_stl(path) -> StlModel` | Read a file. |
| `parse_stl(bytes) -> StlModel` | Read the bytes of one, binary or ASCII. |
| `parse_stl_text(text) -> StlModel` | Read the text of an ASCII file. |
| `is_binary_stl(bytes) -> Bool` | Tell the two encodings apart, as three.js does. |

A file exactly as long as its face count says is binary. Otherwise, a file with `solid` in its first ten bytes is ASCII. Any other file is binary.

### StlModel

| Field | Meaning |
|---|---|
| `geometry` | A non-indexed `BufferGeometry`. It has `position` and `normal`, and `color` when the binary header has `COLOR=`. Each corner gets the normal of its face. |
| `solids` | One `StlSolid` for each solid, in file order: `name`, `start` and `count`. `start` and `count` count corners. A binary file has one solid with no name. These are the groups of three.js. |
| `alpha` | The alpha of `COLOR=`, from zero to one. It is one when the file has no header color. |

`has_colors()` is true when the geometry has a `color` attribute. `take_geometry()` swaps the geometry out for an empty one.

### Binary colors

The binary format has no standard color. This loader reads the convention that three.js reads:

- A header with `COLOR=` and four bytes gives a default color and an alpha. The last `COLOR=` in the header wins.
- Each face then has a 16-bit color. Red is in bits 0 to 4, green in bits 5 to 9, and blue in bits 10 to 14.
- A face with bit 15 set uses the default color.

The colors are sRGB. The loader decodes them to linear light, as three.js does. A header without `COLOR=` gives no `color` attribute. Most writers put zeros in the 16 bits, and zero is black.

### Errors

The loader raises for:

- A binary file shorter than 84 bytes, or shorter than its face count needs. The loader reads a binary file with bytes after its faces.
- A coordinate or a normal that is not a number, or is not finite as a `Float32`.
- An ASCII file with no solid, or a solid without `endsolid`. A solid in a solid.
- A keyword in the wrong place, such as `vertex` outside a facet.
- A facet without `normal`, or with other than three vertices. `outer` without `loop`.
- A word that STL does not have. Text that is not UTF-8.

## PLY

`loaders/ply.mojo`. `read_ply(path)` reads a PLY file into one indexed `BufferGeometry`. three.js: `PLYLoader`.

```mojo
var shape = assets.geometries.add(read_ply("assets/cube.ply"))
```

| Function | Meaning |
|---|---|
| `read_ply(path) -> BufferGeometry` | Read a file. |
| `parse_ply(bytes) -> BufferGeometry` | Read the bytes of one. |
| `ply_format(name) -> PlyFormat` | The format a `format` line names. |
| `ply_scalar(name) -> PlyScalar` | The type a `property` line names. |
| `decode_ply_scalar(bytes, at, scalar, format) -> Float64` | One binary value. |

The loader reads the three formats: `ascii`, `binary_little_endian` and `binary_big_endian`. It reads every scalar type: `char`, `uchar`, `short`, `ushort`, `int`, `uint`, `float` and `double`. It also reads the names `int8` to `float64`.

`PlyFormat` and `PlyScalar` are types. A bare integer does not compile. `PlyScalar.size()` and `decode_ply_scalar` refuse a value that is not valid.

### What is read

| Element and property | Attribute |
|---|---|
| `vertex`: `x`, `y`, `z` | `position`. A file must have them. |
| `vertex`: `nx`, `ny`, `nz` | `normal`. |
| `vertex`: `s`, `t`, or `u`, `v`, or `texture_u`, `texture_v`, or `tx`, `ty` | `uv`. |
| `vertex`: `red`, `green`, `blue`, or `r`, `g`, `b`, or `diffuse_red` and so on | `color`, divided by 255 and decoded from sRGB. |
| `vertex`: `alpha` or `a` | The fourth channel of `color`, divided by 255. three.js does not read it. |
| `face`: `vertex_indices` or `vertex_index` | The index. |

A face of more than three corners becomes a fan of triangles from its first corner. Thus the face must be convex, as an OBJ face must be. three.js cuts a quad on the other diagonal, and it does not read a face of five or more corners.

The loader reads past all other elements and properties. A file without a `face` element is a point cloud, and its geometry has no index.

### Errors

The loader raises, and names the element and the row, for:

- A file that does not start with `ply`, or has no `end_header`. A header with no `format` line.
- A format or a type that is not known. An `element` or `property` line with the wrong fields.
- A property before any element. An element named twice. A list length that is not an integer type.
- A header line that is not `format`, `element`, `property`, `comment` or `obj_info`.
- No `vertex` element, or a vertex without `x`, `y` and `z`. A vertex property that is a list.
- Only some channels of a normal, a texture coordinate or a color. An alpha without a color.
- A face without a list of integer vertex indices.
- An ASCII row with too few or too many values. A value that is not a number of its type, or is out of its range.
- A file that ends before its last row. A list with a negative length.
- A value of a vertex that is not finite as a `Float32`.
- A face with fewer than three corners, or one that names a vertex the file does not have. A face that is not convex, or has no area.

### Example

`assets/cube.ply` is a unit cube in ASCII, with a color at each corner and six quads. `assets/tetrahedron.stl` is a binary tetrahedron with a header color. `tests/test_ply.mojo` and `tests/test_stl.mojo` read them and draw them.

## glTF

`loaders/gltf.mojo`. `read_gltf(path, scene, assets)` reads a glTF 2.0 file into the scene and the assets it is handed. It reads meshes, materials, textures, nodes, skins, morph targets, animations, cameras, sparse accessors and twelve [extensions](#gltf-extensions). three.js: `GLTFLoader`.

```mojo
var model = read_gltf("assets/gltf/box.glb", scene, assets)
print(model.node_names[0], model.mesh_count)
var camera_node = model.nodes[2]
```

A `.glb` is told by its magic. Anything else is read as JSON. A buffer or an image named by a relative URI is read from the file's own directory. A `data:` URI must be base64.

| Function | Meaning |
|---|---|
| `read_gltf(path, scene, assets) -> GltfModel` | Read a file. |
| `load_gltf(text, bin, directory, scene, assets) -> GltfModel` | Read the JSON of one, with a `.glb`'s binary chunk or none. |
| `split_glb(bytes) -> (String, List[UInt8])` | A `.glb`'s JSON and its binary chunk. |
| `decode_base64(text) -> List[UInt8]` | The bytes of a base64 text. |
| `decode_image(bytes) -> DecodedImage` | A PNG or a JPEG, told by its first bytes. Other bytes are read as a TGA, which has no signature. |

### GltfModel

The model says what went where, by the file's own indices.

| Field | Meaning |
|---|---|
| `nodes` | One `NodeId` per glTF node. `NO_PARENT` for a node the loaded scene does not reach. |
| `node_names` | Each node's `name`, or empty. |
| `geometries` | One `GeometryId` per primitive, mesh by mesh. `mesh_geometries(mesh)` returns one mesh's. |
| `materials` | One `MaterialId` per glTF material. |
| `color_textures`, `data_textures` | One `TextureId` per glTF texture, as read for a color map and as read for a data map. `NO_TEXTURE` when no material read it that way. |
| `first_mesh`, `mesh_count` | Where the meshes this file added begin in `scene.meshes`, and how many. |
| `first_skinned_mesh`, `skinned_mesh_count` | Where the skinned meshes this file added begin in `scene.skinned_meshes`, and how many. |
| `first_instanced_mesh`, `instanced_mesh_count` | Where the instanced meshes this file added begin in `scene.instanced_meshes`, and how many. |
| `first_light`, `light_count` | Where the lights this file added begin in `scene.lights`, and how many. |
| `cameras` | One `GltfCamera` per node that carries a camera and that the loaded scene reaches. |
| `animations` | One `AnimationClip` per animation that drives something the loaded scene reaches, in file order. |

### What maps to what

| glTF | ThreeMojo |
|---|---|
| A primitive of triangles | A `BufferGeometry` with `position`, and `normal`, `uv`, `uv1` and `color` when present, indexed when it is. `TEXCOORD_1` becomes `uv1`. |
| A material | A `STANDARD` material, or a `BASIC` or `PHYSICAL` one when an [extension](#gltf-extensions) asks. It reads base color and alpha, base color texture, metallic and roughness factors, the metallic-roughness texture as both `roughness_map` and `metalness_map`, normal texture and scale, the [occlusion texture](#occlusion), emissive factor and texture, `doubleSided`. `BLEND` sets `transparent`. `MASK` sets `alpha_test` to `alphaCutoff`. |
| A texture | A `Texture` at its sampler's wrap and filters. A base color or emissive map is read as sRGB. A metallic-roughness, normal or occlusion map is read as linear, with its alpha ignored. One glTF texture read both ways is two textures. |
| A node | An `Object3D` at its translation, rotation and scale, or at its matrix decomposed, with the node's `name`. Each primitive of its mesh is a `Mesh`. |
| A node with a `skin` | Each primitive of its mesh is a `SkinnedMesh`. See [Skins, morph targets and animations](#skins-morph-targets-and-animations). |
| A node with a `camera` | A `PerspectiveCamera` or an `OrthographicCamera` attached to the node. See [Cameras](#cameras). |
| A sparse accessor | Its values replace the elements that its indices name. The other elements come from the buffer view, or are zero when there is none. |
| The default scene | Its roots and everything under them, each node after its parent. `scene` picks it. |

A primitive without a material draws with one default `standard_material`. A primitive with `COLOR_0` draws with a copy of its material that has `vertex_colors` on, one copy per material. An accessor without a buffer view reads as zeros. A normalized integer accessor divides by its largest value, as the specification has it.

glTF's texture coordinates run down from an image's top left. This renderer's `v` runs up from the bottom. Each glTF texture is given a `repeat` of `(1, -1)` and an `offset` of `(0, 1)`, which flips `v`, as three.js sets `flipY = false`. The geometry's coordinates are kept as the file has them.

### Occlusion

A material's `occlusionTexture` becomes its `ao_map`. Its `strength` becomes `ao_map_intensity`, or one when it is not there. This is what three.js reads into `aoMap` and `aoMapIntensity`. The red channel of the map dims the indirect light. See [Materials](Materials).

Every map can read the second set of texture coordinates, the occlusion texture among them. A `texCoord` of one gives a copy of the texture the channel `UV_CHANNEL_1`. The renderer then samples it at the geometry's `uv1`. A `texCoord` in the map's `KHR_texture_transform` replaces the map's own.

An unlit material reads no occlusion, as in three.js.

### Skins, morph targets and animations

The loader reads a skin into a `Skeleton`, a morph target into the geometry, and an animation into an `AnimationClip`. The names are three.js's, as in [Skinning](Skinning) and [Animation](Animation).

| glTF | ThreeMojo |
|---|---|
| `JOINTS_0` | The `skinIndex` attribute. The components must be unsigned bytes or unsigned shorts. |
| `WEIGHTS_0` | The `skinWeight` attribute. The loader divides each vertex's four weights by their sum, as three.js's `normalizeSkinWeights` does. Four zeros become one on the first bone. |
| A skin | A `Skeleton` with one `Bone` per joint. The inverse bind matrices come from `inverseBindMatrices`, or are the identity. The mesh is bound at the identity, in `ATTACHED` mode. |
| A primitive's `targets` | Morph targets of the geometry, with `morph_relative` set, because glTF holds offsets. `POSITION` and `NORMAL` are read. |
| `weights` | The morph influences of each mesh. A node's `weights` replace its mesh's `weights`. |
| An animation | An `AnimationClip`, named by the file or `animation_` and its index. |
| A `translation`, `rotation` or `scale` channel | A `POSITION`, `QUATERNION` or `SCALE` track on the node. |
| A `weights` channel | One `MORPH_INFLUENCE` track for each mesh on the node and each morph target. |
| `STEP`, `LINEAR` | The track's `STEP` or `LINEAR` interpolation. |
| `CUBICSPLINE` | The track's `CUBIC_SPLINE` interpolation. Each key's in-tangent, value and out-tangent go to `in_tangents`, `values` and `out_tangents`. |

A skinned mesh waits until the loader has placed every node. Thus a joint can come after the mesh in the file. Each primitive gets its own copy of the skeleton, because a `SkinnedMesh` owns its skeleton.

### Cameras

A node with a `camera` gets a camera attached to it. The camera looks down the node's -z axis, with its +y axis up. `GltfCamera` holds the camera.

| Member | Meaning |
|---|---|
| `kind` | `GLTF_PERSPECTIVE` or `GLTF_ORTHOGRAPHIC`, a `GltfCameraKind`. A bare integer does not compile. |
| `index`, `name` | The camera's index in the file's `cameras`, and its `name`. |
| `node` | The scene node that the camera rides. |
| `perspective()` | The `PerspectiveCamera`. It raises for an orthographic camera, or a kind that is not valid. |
| `orthographic()` | The `OrthographicCamera`. It raises for a perspective camera, or a kind that is not valid. |

A perspective camera takes `yfov` in radians and `znear`. Without `aspectRatio`, the aspect is one. Without `zfar`, the far plane is at two million meters. These are three.js's values. An orthographic camera spans `xmag` and `ymag` on each side of its axis. One glTF camera on two nodes is two cameras.

### Differences from three.js

- A morph target without `POSITION` moves no position. three.js adds the base positions to it as offsets.
- A `weights` channel drives the meshes on its own node. three.js also drives the meshes of the node's children.
- A `weights` channel does not drive a skinned mesh. The mixer drives morph influences on `scene.meshes` only.
- A channel on a node that the default scene does not reach is left out. An animation left with no track is left out.
- A skin joint that the scene does not reach is refused. three.js puts a new bone in its place.
- A morph target of colors is refused. three.js reads it.
- A rotation key must be of unit length. A track refuses one that is not.
- A map other than the occlusion texture must read the first set of texture coordinates. three.js reads any set. Here, only the ao map and the light map are sampled at a second set.
- A map that reads the third set of texture coordinates or a later set is refused. A geometry here has only `uv` and `uv1`.

### glTF extensions

The loader reads fifteen extensions. They are the ones three.js's `GLTFLoader` reads that map onto a feature of this renderer. `is_supported_extension(name)` tells if the loader reads an extension.

| Extension | ThreeMojo |
|---|---|
| `KHR_materials_unlit` | A `BASIC` material: the base color, its texture, `doubleSided` and the alpha mode. The loader ignores the emissive, normal and metallic-roughness terms and every other material extension, as three.js does. |
| `KHR_materials_emissive_strength` | `emissiveStrength` sets `emissive_intensity`. |
| `KHR_materials_ior` | A `PHYSICAL` material. `ior` sets `ior`, or 1.5 when it is not there. |
| `KHR_materials_specular` | A `PHYSICAL` material. `specularFactor` sets `specular_intensity`. `specularColorFactor` sets `specular_color`, converted from linear to sRGB. `specularTexture` sets `specular_intensity_map`, linear with its alpha kept. `specularColorTexture` sets `specular_color_map`, sRGB with its alpha ignored. |
| `KHR_materials_clearcoat` | A `PHYSICAL` material. `clearcoatFactor` and `clearcoatRoughnessFactor` set `clearcoat` and `clearcoat_roughness`. `clearcoatTexture`, `clearcoatRoughnessTexture` and `clearcoatNormalTexture` set the three coat maps, as data. The normal texture's `scale` sets `clearcoat_normal_scale` on both axes, as three.js sets it. |
| `KHR_materials_transmission` | A `PHYSICAL` material. `transmissionFactor` sets `transmission`, and `transmissionTexture` sets `transmission_map`, read as data. See [Materials](Materials#transmission). |
| `KHR_materials_volume` | A `PHYSICAL` material. `thicknessFactor` sets `thickness`, and `thicknessTexture` sets `thickness_map`, read as data. `attenuationDistance` sets `attenuation_distance`, and a distance of zero or none is infinite, as three.js reads it. `attenuationColor` sets `attenuation_color`, converted from linear to sRGB. |
| `KHR_materials_dispersion` | A `PHYSICAL` material. `dispersion` sets `dispersion`. |
| `KHR_materials_sheen` | A `PHYSICAL` material with a `sheen` of one, as three.js sets it. `sheenColorFactor` sets `sheen_color`, converted from linear to sRGB, and `sheenRoughnessFactor` sets `sheen_roughness`. Both are zero when they are not there. `sheenColorTexture` and `sheenRoughnessTexture` set the two maps. The roughness texture keeps its alpha, because the roughness is stored there. See [Materials](Materials#sheen). |
| `KHR_materials_iridescence` | A `PHYSICAL` material. `iridescenceFactor`, `iridescenceIor`, `iridescenceThicknessMinimum` and `iridescenceThicknessMaximum` set the film, in nanometers. `iridescenceTexture` and `iridescenceThicknessTexture` set its maps. See [Materials](Materials#iridescence). |
| `KHR_materials_anisotropy` | A `PHYSICAL` material. `anisotropyStrength` and `anisotropyRotation` set `anisotropy` and `anisotropy_rotation`, and `anisotropyTexture` sets its map. See [Materials](Materials#anisotropy). |
| `KHR_texture_transform` | A copy of the texture with its `offset`, `rotation` and `repeat` set. See [Texture transforms](#texture-transforms). |
| `KHR_lights_punctual` | A directional, point or spot `Light` on the node. See [Punctual lights](#punctual-lights). |
| `KHR_mesh_quantization` | Nothing more. The loader reads every attribute at any component type, and a normalized one divides by its largest value. |
| `EXT_mesh_gpu_instancing` | One `InstancedMesh` for each primitive of the node's mesh. See [Instancing](#instancing). |

A file that lists another extension in `extensionsRequired` is refused, as three.js refuses it. A file that lists an extension only in `extensionsUsed` is read without that extension.

#### Texture transforms

The transform is applied first, then the flip of `v`. So the copy gets an `offset` of `(x, 1 - y)`, a `repeat` of `(x, -y)`, and the `rotation` as the file gives it. The glTF coordinates then go where three.js's matrix puts them. A transform that names only `texCoord` makes no copy.

The transform's `texCoord` replaces the texture's own `texCoord`, as in three.js. It must be zero or one. Each map keeps its own transform and its own set, as in three.js.

#### Punctual lights

| glTF | ThreeMojo |
|---|---|
| `directional` | `directional_light`. Its target is a new node one meter down the node's -z axis, as three.js adds its `target`. |
| `point` | `point_light` with `distance` set to `range`, or zero for no cutoff. |
| `spot` | `spot_light` with `angle` set to `outerConeAngle` and `penumbra` set to `1 - innerConeAngle / outerConeAngle`. Its target is as for a directional light. |

The color is linear in the file and sRGB in the `Light`. The intensity is one when the file gives none. Point and spot lights use a decay of two, as three.js does.

#### Instancing

Each instance matrix is `TRANSLATION`, `ROTATION` and `SCALE` composed. An attribute that is not there is the identity's part. `_COLOR_0` colors the instances, as three.js reads it into `instanceColor`. The loader counts every other attribute but does not read it, because it is for a custom shader. A node with an empty `attributes` object draws plain meshes, as in three.js.

#### Not ported

- `KHR_materials_variants`.
- `KHR_draco_mesh_compression`, `EXT_meshopt_compression`, `KHR_texture_basisu`, `EXT_texture_webp` and `EXT_texture_avif`.

#### Differences from three.js

- A `specularColorFactor` outside zero to one is refused. A `Color` cannot hold it. three.js keeps it.
- An `ior` outside 1 to 2.333 is refused, because `Material` refuses it.
- A clear coat texture with a `clearcoatFactor` of zero is left out, with the normal texture's `scale`. three.js keeps them, but draws none.
- An `iridescenceTexture` or `iridescenceThicknessTexture` with an `iridescenceFactor` of zero is left out. So is an `anisotropyTexture` with an `anisotropyStrength` of zero. three.js keeps them, but draws neither.
- A `sheenColorFactor` outside zero to one is refused, as a `specularColorFactor` is.
- A skinned node with `EXT_mesh_gpu_instancing` is refused. An instanced skinned mesh is not ported. three.js drops the skin.

### Not read

A primitive of points, lines or strips is refused. Only the first two sets of texture coordinates are read.

### Errors

The loader raises for:

- A file it cannot read. A document that is not JSON or not glTF 2. A required extension that the loader does not read.
- A buffer shorter than its length. A buffer view or accessor that runs past its buffer.
- An unknown accessor type or component type. An attribute of the wrong width. Indices that are not unsigned integers.
- An image that is not PNG, JPEG or TGA. A texture or material that names something the file does not have.
- An unknown wrap mode or alpha mode.
- A node reached twice. A node matrix that flattens an axis.
- A sparse accessor with indices that do not rise, that are not unsigned integers, or that name an element past the accessor.
- A skin without joints. A joint that the file does not have, or that the scene does not reach. Inverse bind matrices that are not one `MAT4` per joint.
- A skinned primitive without `JOINTS_0` and `WEIGHTS_0`.
- More than eight morph targets. Primitives of one mesh with different numbers of targets. `weights` that are not one number per target.
- A camera of an unknown type, or without the values it needs. A camera that `PerspectiveCamera` or `OrthographicCamera` refuses.
- An animation channel with an unknown path, or a sampler with an unknown interpolation. A sampler output that does not hold one value per key, or three for `CUBICSPLINE`.
- A track or a clip that `KeyframeTrack` or `AnimationClip` refuses.
- An `extensions` value, or an extension, that is not an object.
- A texture reference or a texture transform on a third set of coordinates or past it. A `specularColorFactor` outside zero to one.
- A node that names a light the file does not have. A light of an unknown type, a `range` that is not above zero, or a spot light without `spot`. A light that `Light` refuses.
- Instancing without an `attributes` object. Instancing attributes of different counts, or of the wrong width. A skinned node that is instanced.

## Collada

`loaders/collada.mojo`. `read_collada(path, scene, assets)` reads a Collada `.dae` file into the scene and the assets it is handed. It reads the geometries, the materials and their textures, the node hierarchy, the cameras and the lights. three.js: `ColladaLoader`.

```mojo
from loaders.collada import read_collada

var model = read_collada("assets/room.dae", scene, assets)
print(model.node_names[0], model.mesh_count)
var camera = model.perspective_cameras[0]
```

The file is XML. [XML](#xml) reads it. An image is read from the directory of the file.

| Function | Meaning |
|---|---|
| `read_collada(path, scene, assets) -> ColladaModel` | Read a file. |
| `load_collada(text, directory, scene, assets) -> ColladaModel` | Read the text of one. `directory` ends in `/`, or is empty. |
| `up_axis_rotation(axis) -> Quaternion` | The rotation of the root node for an `UpAxis`. |

### ColladaModel

The model tells what went where.

| Field | Meaning |
|---|---|
| `root` | The node of the visual scene. Each root `<node>` is a child of it. |
| `up_axis`, `unit` | The `<up_axis>` as an `UpAxis`, and `<unit meter>` as a `Length`. |
| `nodes`, `node_names` | One `NodeId` and one name for each `<node>` placed, in the order placed. A `JOINT` node has its `sid` as its name, as in three.js. |
| `materials`, `material_ids`, `material_names` | One `MaterialId`, `id` and `name` for each `<material>`, in file order. `material(id)` finds one. |
| `geometries` | One `GeometryId` for each primitive built. |
| `textures` | One `TextureId` for each map that a material reads. |
| `perspective_cameras`, `orthographic_cameras` | Each camera that an `<instance_camera>` places. Each camera rides its node. |
| `first_mesh`, `mesh_count`, `first_line`, `line_count`, `first_light`, `light_count` | Where the meshes, lines and lights of the file start in the scene, and how many there are. |

`UpAxis` is a type: `X_UP`, `Y_UP` or `Z_UP`. A bare integer does not compile. `up_axis_rotation` refuses a value that is none of the three.

### What maps to what

| Collada | ThreeMojo |
|---|---|
| `<triangles>`, `<polylist>`, `<polygons>` | A `BufferGeometry` with `position`, and `normal`, `uv` and `color` when the inputs give them. It is drawn as a `Mesh`. |
| `<lines>`, `<linestrips>` | A geometry of point pairs, drawn as a `Line` in `SEGMENTS` mode. |
| `phong`, `blinn` | A `PHONG` material, three.js's `MeshPhongMaterial`. |
| `lambert` | A `LAMBERT` material, three.js's `MeshLambertMaterial`. |
| `constant` | A `BASIC` material, three.js's `MeshBasicMaterial`. |
| `<node>` | An `Object3D`. Its `<matrix>`, `<translate>`, `<rotate>` and `<scale>` steps are multiplied in file order and decomposed. |
| `<instance_geometry>` | A mesh or a line for each primitive, with the material that `<bind_material>` binds to its symbol. |
| `<instance_node>` | The node from `<library_nodes>` or the visual scene, placed again. |
| `<instance_camera>` | A `PerspectiveCamera` or an `OrthographicCamera` that rides the node. |
| `<instance_light>` | A directional, point, spot or ambient light at the node. |
| `<visual_scene>` | The root node. A `Z_UP` file turns it by -90 degrees about x. The root is scaled by `<unit meter>`. The vertices do not change, as in three.js. |

A quad of a `<polylist>` or a `<polygons>` is cut into the triangles `(a, b, d)` and `(b, c, d)`, as in three.js. A larger polygon is cut into a fan from its first corner. A polygon of fewer than three corners gives no triangle.

A vertex color is sRGB in the file and linear in a geometry, so the loader decodes it. A fourth value is kept as alpha. Only the first two values of a texture coordinate are read.

### Materials

A material reads the `profile_COMMON` technique of its effect. The last `constant`, `lambert`, `blinn` or `phong` element sets the kind.

| Parameter | Meaning |
|---|---|
| `diffuse` | The color, and a color map in sRGB. |
| `specular` | The specular color, on a `PHONG` material only. |
| `shininess` | The shininess, on a `PHONG` material only. Zero keeps the default of 30, as in three.js. |
| `emission` | The emissive color and an emissive map, on a `PHONG` or `LAMBERT` material only. |
| `bump` | A normal map, on a `PHONG` or `LAMBERT` material only. |
| `transparent`, `transparency` | The opacity. See below. |
| `<extra>` `double_sided` | `DOUBLE_SIDE` for 1, `FRONT_SIDE` for anything else. |
| `<extra>` `bump` | A normal map. It replaces the `bump` parameter. |

The opacity comes from the `opaque` mode of `<transparent>`, its color and the `<transparency>` factor:

| Mode | Opacity |
|---|---|
| `A_ONE`, the default | alpha times the factor |
| `RGB_ZERO` | one minus red times the factor |
| `A_ZERO` | one minus alpha times the factor |
| `RGB_ONE` | red times the factor |

A missing `<transparency>` is 1. A missing `<transparent>` is a white of alpha 1 in `A_ONE`. An opacity below 1 sets `transparent`. A `<transparent>` with a texture sets `transparent` and no alpha map, as in three.js.

A `<texture>` names a `sampler2D`, the sampler names a `surface`, and the surface names an `<image>`. When no sampler has the name, the name is the image, as in three.js. A texture of an image that the file does not have is left out. The `<extra><technique>` of a texture can set `wrapU`, `repeatU`, `repeatV`, `offsetU` and `offsetV`. `wrapU` sets one wrap for both axes. A texture repeats by default.

A primitive with no `material` symbol draws with a white `PHONG` material, or a white `BASIC` material for lines. A symbol that `<bind_material>` does not bind draws with a magenta `BASIC` material, as in three.js. A line draws with a `BASIC` copy of a lit material. The copy keeps the color, the opacity and `transparent`.

### Cameras and lights

A `perspective` camera reads `yfov` in degrees, `aspect_ratio`, `znear` and `zfar`. A number that is missing takes the three.js default: 50 degrees, an aspect of 1, 0.1 and 2000. An `orthographic` camera reads `xmag` and `ymag`. When one of them is missing, `aspect_ratio` gives it. The camera spans half of each on each side.

A light reads its `color`. A point or spot light reads `quadratic_attenuation`, and its distance is the square root of one over it. A spot light has a cone of 60 degrees, as in three.js, which does not read `falloff_angle`. A directional or spot light shines toward the world origin.

A node with no child nodes and one object becomes that object in three.js, at the transform of the node. A node with more objects becomes a group, and each object keeps its own transform. Only a directional or spot light shows the difference. When such a light is one object of several, three.js places it one unit up the y axis of the node. This loader does the same.

### Differences from three.js

- Each primitive is its own geometry and its own `Mesh`. three.js makes one geometry for each kind of primitive, with groups and an array of materials. A mesh here draws one material.
- `<polygons>` is read. three.js does not read it.
- A vertex color is decoded from sRGB in each of its three channels. three.js decodes the wrong three values of each color.
- A texture coordinate keeps its first two values. three.js keeps all the values of the source.
- A `<linestrips>` element gives point pairs, so each strip is drawn alone. three.js joins every strip into one line.
- An image path must be relative. A path with `:` is refused.
- A color channel outside zero to one is refused.

### Not read

Controllers and skins, animations and animation clips, kinematics and physics are not read. `<instance_controller>` is skipped. `<lookat>` and `<skew>` steps are skipped. `<trifans>`, `<tristrips>` and polygons with holes are not read. A second set of texture coordinates is skipped. The specular map and the ambient map are skipped, because no material here has a specular map or a light map.

### Errors

The loader raises for:

- A text that is not XML, or a root that is not `<COLLADA>`.
- A unit that is not one positive number. An up axis other than `X_UP`, `Y_UP` and `Z_UP`.
- No `<scene>`, or a scene that names no visual scene. A reference that is not `#id`.
- A material with no effect, or an effect with no `profile_COMMON` technique and shading.
- A number that is not a number or is not finite as a `Float32`. A color with too few numbers. An opacity outside zero to one. An `opaque` mode that is not known.
- A sampler with no surface, or a surface or an image with no `init_from`. An image that cannot be read.
- A geometry that the file does not have, or one with no `<mesh>`. A source with a stride below one.
- A primitive with no inputs, an input with no offset, or an input that names no source. A `<p>` or a `<vcount>` that does not fill whole corners and faces. An index outside its source. A primitive with corners and no positions, or two inputs that give one attribute.
- A node that `<instance_node>` names and the file does not have. Nodes that instance each other more than `MAX_INSTANCE_DEPTH` deep.
- A step with the wrong count of numbers. A transform that flattens an axis.
- A camera or a light that its builder refuses, or a light with no technique.

## FBX

`loaders/fbx.mojo` and `loaders/fbx_tree.mojo`. `read_fbx(path, scene, assets)` reads an FBX file into the scene and the assets it is handed. The file can be binary or ASCII. It reads the meshes, the materials and their textures, the model hierarchy, the cameras and the lights. three.js: `FBXLoader`.

```mojo
from loaders.fbx import read_fbx

var model = read_fbx("assets/robot.fbx", scene, assets)
var arm = model.model("Arm")
print(model.mesh_count, len(model.materials))
```

| Function | Meaning |
|---|---|
| `read_fbx(path, scene, assets) -> FbxModel` | Read a file. A texture is read from the directory of the file, or from the file when it is embedded. |
| `parse_fbx(bytes) -> FbxDocument` | Read the tree of a file. Bytes that start with the binary magic are binary. Other bytes are ASCII. |
| `parse_fbx_text(text) -> FbxDocument` | Read the tree of an ASCII file. |
| `load_fbx(document, directory, scene, assets) -> FbxModel` | Read a tree into a scene. |

### FbxModel

| Field | Meaning |
|---|---|
| `root` | The node that each root model hangs on, three.js's `sceneGraph` group. |
| `format`, `version` | `FBX_ASCII` or `FBX_BINARY`, and the version of the file. |
| `models`, `model_ids`, `model_names` | One `NodeId`, id and name for each `Model`, parents first. `model(name)` finds one. |
| `materials`, `material_ids`, `material_names` | One `MaterialId`, id and name for each `Material` that has a connection, in file order. |
| `geometries` | One `GeometryId` for each material index of each geometry. |
| `textures` | One `TextureId` for each texture and each use of it. |
| `cameras` | Each `PerspectiveCamera`, riding its model. |
| `unit` | The length of one unit of the file, a `Length`: `UnitScaleFactor` from `GlobalSettings`, in centimeters. Like three.js, the loader keeps it and does not apply it. |
| `first_mesh`, `mesh_count`, `first_light`, `light_count` | Where the meshes and lights of the file start in the scene, and how many there are. |

A name is sanitized as three.js's `PropertyBinding.sanitizeNodeName` does it. White space becomes `_`, and `[`, `]`, `.`, `:` and `/` are removed.

### The tree

An FBX file is a tree of nodes. Each node has a name, properties and children. `FbxDocument` holds each node in one list. Node zero has no name, and its children are the top-level nodes. `FbxPropertyKind` tells what a property holds: `FBX_INTEGER`, `FBX_NUMBER`, `FBX_STRING`, `FBX_INTEGERS`, `FBX_NUMBERS` or `FBX_BYTES`.

| Member | Meaning |
|---|---|
| `children(node)`, `children_named(node, name)`, `child(node, name)` | The children of a node. `child` gives `NO_FBX_NODE` when there is none. |
| `property_count(node)`, `property(node, index)` | The properties of a node. `property` refuses a kind that is none of the six. |
| `integer`, `number`, `string` | One property as a whole number, a number or a string. |
| `numbers(node)`, `integers(node)` | The array of a node, or its single numbers. |

The binary form is read at version 6400 and later, and the ASCII form at version 7000 and later, as in three.js. From version 7500, the three sizes of a record are 64 bits. An array can be raw or compressed with zlib. `render/inflate.mojo` expands a compressed array, as it does for a [PNG](Image-files). An ASCII array, `Name: *count { a: ... }`, becomes one array property of its node, so the two forms give the same tree.

A binary file writes an object name as `Name\x00\x01Class`. three.js stops the string at the zero byte, and so does this reader. An ASCII file writes `"Class::Name"`. `object_name(name, format)` removes the `Class::`.

### What maps to what

| FBX | ThreeMojo |
|---|---|
| `Model` | An `Object3D` under its parent model. |
| `Geometry` of type `Mesh` | For each material index, a `BufferGeometry` with `position`, and `normal`, `uv` and `color` when the layer elements give them. |
| `Material` | A `LAMBERT` material for the `lambert` shading model, and a `PHONG` material for any other, as in three.js. |
| `Texture` and `Video` | A `Texture`. |
| `NodeAttribute` of a `Camera` model | A `PerspectiveCamera`. |
| `NodeAttribute` of a `Light` model | A point, directional or spot light. |
| `GlobalSettings` `AmbientColor` | An ambient light, when the color is not black. |

The transform of a model is three.js's `generateTransform`. The local chain is: translation, rotation offset, rotation pivot, pre-rotation, rotation, inverse post-rotation, inverse rotation pivot, scaling offset, scaling pivot, scale, inverse scaling pivot. The rotation and scale then combine with the parent in the order that `InheritType` names. `RotationOrder` sets the order of the rotation, and `fbx_euler_order` converts it. The pre-rotation and the post-rotation always turn in `ZYX`, as in three.js.

The geometric translation, rotation and scale of the first model of a geometry move its positions and normals, as in three.js.

### Geometry

`PolygonVertexIndex` lists the corners of each polygon. A negative index ends a polygon, and its position is `-index - 1`. A triangle is kept. A polygon of four or more corners is laid flat on the plane of its Newell normal and cut by ear clipping. A convex polygon is cut into a fan from its first corner. A polygon of fewer than three corners gives no triangle.

`FbxLayer` holds one layer element: the values, the indices, and how they map onto the corners. The first `LayerElementNormal`, `LayerElementUV`, `LayerElementColor` and `LayerElementMaterial` with values are read.

| Mapping | `FbxMapping` | One value for each |
|---|---|---|
| `ByPolygonVertex` | `BY_POLYGON_VERTEX` | corner |
| `ByPolygon` | `BY_POLYGON` | polygon |
| `ByVertice`, `ByVertex` | `BY_VERTEX` | position |
| `AllSame` | `ALL_SAME` | mesh |

A reference of `Direct` reads the values directly. `IndexToDirect`, or the older `Index`, reads them through the indices. `FbxMapping` and `FbxReference` are types. `FbxLayer.start` refuses a value that is none of the named constants.

A vertex color is decoded from sRGB. A material index below zero is zero, as in three.js. A mesh with no material draws with a gray `PHONG` material, `0xcccccc`. An index past the materials of a mesh draws with a white `PHONG` material. When the geometry has colors, each material of the mesh gets `vertex_colors`, as in three.js.

### Materials

| Property | Meaning |
|---|---|
| `Diffuse`, or `DiffuseColor` of type `Color` or `ColorRGB` | The color. |
| `Emissive`, or `EmissiveColor` of type `Color` or `ColorRGB` | The emissive color. |
| `EmissiveFactor` | The emissive intensity. |
| `Specular`, or `SpecularColor` of type `Color` | The specular color, on a `PHONG` material. |
| `Shininess` | The shininess, on a `PHONG` material. |
| `ReflectionFactor` | The reflectivity. |
| `BumpFactor` | The bump scale, with a bump map only. |
| `TransparencyFactor`, `Opacity`, `TransparentColor` | The opacity. See below. |

The opacity is one minus `TransparencyFactor`. When that is exactly 0 or 1, `Opacity` gives the opacity, or else one minus the red of `TransparentColor`. This is three.js's rule. An opacity below 1 sets `transparent`.

A texture connects to a material under the name of its map:

| Connection | Map |
|---|---|
| `DiffuseColor`, `Maya\|TEX_color_map` | `map`, sRGB |
| `EmissiveColor` | `emissive_map`, sRGB |
| `NormalMap`, `Maya\|TEX_normal_map` | `normal_map`, linear |
| `Bump` | `bump_map`, linear. A normal map replaces it. |
| `TransparentColor`, `TransparencyFactor` | `alpha_map`, linear. It also sets `transparent`. |

A texture reads the first `Video` connected to it. The image is the `Content` of the video: raw bytes in a binary file, base64 in an ASCII file. When the video has no content, another video of the same name can give it, as in three.js. Otherwise the image is the file that `RelativeFilename` or `Filename` names, after its last `\`.

`WrapModeU` of 0 repeats, and any other value clamps. `Scaling` and `Translation` set `repeat` and `offset`. A layered texture gives its first layer. A texture with no video is left out.

### Cameras and lights

A camera reads `FieldOfView` in degrees, 45 by default, and `AspectWidth` over `AspectHeight`. Without an aspect, three.js uses the shape of the window, and this loader uses a square. `FocalLength` sets the field of view through a 35 mm film gauge, three.js's `setFocalLength`.

`NearPlane` and `FarPlane` are divided by 1000, as in three.js. Without them, the planes are 1 and 1000.

A light reads `LightType`: 0 is a point light, 1 a directional light and 2 a spot light. Any other type is a point light with three.js's defaults. `Color` is sRGB. `Intensity` is divided by 100. `CastLightOnObject` of 0 sets the intensity to zero.

`FarAttenuationEnd` is the distance, unless `EnableFarAttenuation` is 0. The decay is 1. A spot light reads `InnerAngle` in degrees, 60 by default. `OuterAngle` sets the penumbra to 1. `CastShadows` of 1 casts a shadow from a directional or spot light.

A directional or spot light stands one unit up its own y axis before the model transform applies, as in three.js. It shines toward the world origin.

### Differences from three.js

- Each material index of a geometry is its own geometry and its own `Mesh`. three.js makes one geometry with groups.
- A polygon of four or more corners is cut by ear clipping. three.js uses earcut, which picks other diagonals. A flat polygon gives the same surface.
- The ASCII reader reads tokens, not lines and tabs. A file that three.js reads, this reader reads the same way.
- three.js sets the penumbra of a spot light to the outer angle in radians, at least 1. This loader uses 1, because a penumbra above 1 is refused.
- A point light that casts a shadow draws without one. This renderer has no shadow for a point light.
- `ByVertex` and `Index` are read as `ByVertice` and `IndexToDirect`. three.js does not read them.
- A texture with no image is `NO_TEXTURE`. three.js makes an empty texture.
- A bump scale without a bump map is dropped, because `Material` refuses it.
- An image path must be relative. A path with `:` is refused.

### Not read

Skin deformers, blend shapes and animation are not read. A skinned mesh draws without its skin, in the pose that its vertices are stored in. NURBS curves, `LookAtProperty`, orthographic cameras, a second set of texture coordinates, and the ambient occlusion, displacement, reflection and specular maps are skipped.

### Errors

The reader raises for:

- An ASCII file with no `FBXVersion`, or one older than 7000. A binary file older than 6400.
- A binary record or property that runs past the file, or children that run past their record. An unknown property type. An array encoding that is not 0 or 1. A zlib array of the wrong length.
- An ASCII node without `:`, a `{` that is not closed, or a `}` that closes nothing.
- An ASCII string that is not closed, or a `*count` that does not match its `a`.
- Nodes nested deeper than `MAX_FBX_DEPTH`.

The loader raises for:

- A format that is neither ASCII nor binary. A file with no `Objects`.
- A material with no `ShadingModel`. A color channel outside zero to one.
- A connection to a texture that is not there. An image path that is not relative, or an image that cannot be read. A `Content` that is neither bytes nor base64.
- A mapping or a reference that is not known. A layer index outside its values.
- A position index outside `Vertices`. A last polygon with no negative index. A polygon of four or more corners with no area, or one that crosses itself so that no ear is left.
- A mesh model with no mesh geometry. Models connected in a loop, or nested deeper than `MAX_MODEL_DEPTH`. A transform that flattens an axis.
- A camera, a light or a material that its builder refuses.

## Fonts

```mojo
from loaders.font import read_font

var font = read_font("assets/fonts/fixture.typeface.json")
var shapes = font.generate_shapes("AO i8\nD", Length(1, METER))
```

`loaders/font.mojo`. `read_font(path)` reads a typeface.js JSON font into a `Font`. `parse_font(text)` reads the text of one. `Font.generate_shapes(text, size)` lays the text out as [shapes](Curves#shape) with holes. [Text](Geometry#text) extrudes them. three.js: `FontLoader`, `Font` and `ShapePath`.

### What is read

| Key | Meaning |
|---|---|
| `resolution` | The font units in one em. It must be positive. |
| `boundingBox.yMin`, `boundingBox.yMax` | The lowest and highest point of a glyph, in font units. |
| `underlineThickness` | The underline, in font units. |
| `familyName` | The name of the font. It is optional. |
| `glyphs` | One object for each character. The key must be one character. |
| `glyphs.X.ha` | The advance of the glyph: how far the next glyph starts to the right. |
| `glyphs.X.o` | The outline of the glyph. It is optional. A space has none. |

An outline is a string of commands, each with its numbers, in font units. Other keys are ignored.

| Command | Draws |
|---|---|
| `m x y` | A new outline that starts at the point. |
| `l x y` | A straight run to the point. |
| `q x y cx cy` | A quadratic Bezier curve to `x y`, with the control point `cx cy`. |
| `b x y c1x c1y c2x c2y` | A cubic Bezier curve to `x y`, with two control points. |

The end point comes first in `q` and `b`. That is the order of the file, and three.js reads it the same way.

### Layout

One font unit is `size / resolution` meters. The glyphs run left to right from the origin. Each glyph starts at the advance of the glyph before it. A line break, `\n`, moves back to x zero and down by one line height:

```
(boundingBox.yMax - boundingBox.yMin + underlineThickness) * size / resolution
```

`Font.line_height(size)` gives it. A character with no glyph takes the `?` glyph, as in three.js.

### Holes

A font does not mark its holes. A solid runs clockwise and a hole runs counterclockwise. `ShapePath.to_shapes` sorts the outlines of a glyph by that rule, as three.js does:

- An outline that runs clockwise is a solid. `to_shapes(is_ccw=True)` swaps the rule.
- A hole goes to the solid before it. When the first outline is a hole, each hole goes to the solid after it.
- With two or more solids, a hole that lies inside a different solid moves to it. No hole moves when one hole lies inside two solids.
- When no outline is a solid, each outline is a shape of its own.

`math/shape_path.mojo` holds `ShapePath`, `signed_area`, `is_clockwise` and `is_point_inside_polygon`. The point test is the three.js ray test, and a point on an edge is inside.

### Differences from three.js

- The file is checked when it is read. three.js reads a glyph when it draws it, and skips a command it does not know.
- A `Shape` must be closed. `to_shapes` adds the closing run when an outline does not end where it started. The surface is the same.
- A step that draws nothing, such as a line to the current point, is skipped. three.js keeps it and then drops the repeated point.
- The layout is calculated in `Float64`, as in three.js. Each point is stored as a `Float32`.

### Errors

`parse_font` raises, with the glyph when there is one, for:

- A document that is not a JSON object.
- A missing or non-positive `resolution`, or a missing `boundingBox`, `yMin`, `yMax`, `underlineThickness` or `glyphs`. A metric that is not a finite `Float32`.
- A glyph key that is not one character. A glyph that is not an object, or has no `ha`. An `o` that is not a string.
- An outline command other than `m`, `l`, `q` and `b`. A command with too few numbers. A number that is not a finite `Float32`.
- An outline that draws before its first `m`. An `m` that draws nothing before the next `m` or the end.

`generate_shapes` raises for a size that is not positive. It raises for a character with no glyph in a font with no `?` glyph.

### Example

`assets/fonts/fixture.typeface.json` is a small font made for the tests. It has `A`, `D`, `O`, `i`, `8`, `?` and a space. `tests/test_font.mojo` compares its layout with three.js 0.180.

## JSON

`loaders/json.mojo`. `parse_json(text)` reads a JSON text into a `JsonDocument`: one `JsonNode` per value, the root at node zero. The glTF loader reads with it. It is exactly RFC 8259. No comments, no trailing commas, no bare words.

| Member | Meaning |
|---|---|
| `kind(node) -> JsonKind` | `OBJECT`, `ARRAY`, `STRING`, `NUMBER`, `BOOLEAN` or `NULL`. |
| `length(node)` | How many children an object or an array has. |
| `get(node, key)`, `has(node, key)` | An object's child by key, or `NO_NODE`. The last of two equal keys wins. |
| `at(node, index)`, `key(node, index)` | A child, or an object's key, by position. |
| `number(node)`, `integer(node)`, `string(node)`, `boolean(node)`, `is_null(node)` | The leaf values. Each raises for a node of another kind. `integer` refuses a fraction. |

A text that bends the grammar is refused with the byte it went wrong at. Nesting past `MAX_DEPTH` is refused. `JsonKind` is a type. A bare integer does not compile.

## XML

`loaders/xml.mojo`. `parse_xml(text)` reads an XML text into an `XmlDocument`: one `XmlElement` for each element, with the root element at element zero. The Collada loader reads with it. three.js uses the `DOMParser` of the browser.

| Member | Meaning |
|---|---|
| `name(element)`, `parent(element)` | The name of an element, as written, and the element that holds it. The root has `NO_ELEMENT` as its parent. |
| `attribute(element, key, default)`, `has_attribute(element, key)` | An attribute, or `default` when there is none. |
| `children(element)`, `children_named(element, name)`, `child(element, name)` | The child elements, in file order. `child` gives the first, or `NO_ELEMENT`. |
| `text(element)`, `text_content(element)` | The text directly inside an element, or all the text inside it. |

The reader reads elements, attributes, text, CDATA sections, comments and processing instructions. It resolves the five named entities and character references. It changes each line ending to a line feed. It skips a document type declaration, so an entity that the declaration names is not known. It does not resolve namespaces: `a:b` is the name of the element.

A text that is not well formed is refused with the byte it went wrong at:

- No root element, or text after it. A declaration, a comment, a CDATA section or an instruction that is not closed.
- A malformed name or tag. An attribute without a quoted value, a `<` in a value, or an attribute given twice.
- An end tag that does not match, or an element that is not closed.
- An entity that is not known, or a character reference that names no character.
- Elements nested deeper than `MAX_XML_DEPTH`.
