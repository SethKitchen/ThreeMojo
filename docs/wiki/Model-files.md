# Model files

`loaders/obj.mojo`, `loaders/mtl.mojo`, `loaders/stl.mojo`, `loaders/ply.mojo` and `loaders/gltf.mojo`. `read_obj` reads a Wavefront OBJ file into named objects, each with a `BufferGeometry`. `parse_obj` reads the text of one. `read_obj_with_materials` also reads the OBJ file's material libraries and gives each object a `MaterialId`. `read_stl` and `read_ply` read an STL or a PLY file into one `BufferGeometry`. `read_gltf` reads a glTF 2.0 file, `.gltf` or `.glb`, into a scene and its assets.

![A cube loaded from an OBJ file turns under a lamp](out/model.png)

three.js: `OBJLoader`, `MTLLoader`, `STLLoader` and `PLYLoader`.

To write these files, see [Exporters](Exporters).

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
- A fragment samples all maps at one coordinate. Thus the renderer refuses a material whose maps have different `-s` or `-o` values. three.js lets each map have its own transform.
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

`loaders/gltf.mojo`. `read_gltf(path, scene, assets)` reads a glTF 2.0 file into the scene and the assets it is handed. three.js: `GLTFLoader`.

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

### What maps to what

| glTF | ThreeMojo |
|---|---|
| A primitive of triangles | A `BufferGeometry` with `position`, and `normal`, `uv` and `color` when present, indexed when it is. |
| A material | A `standard_material`: base color and alpha, base color texture, metallic and roughness factors, the metallic-roughness texture as both `roughness_map` and `metalness_map`, normal texture and scale, emissive factor and texture, `doubleSided`. `BLEND` sets `transparent`. `MASK` sets `alpha_test` to `alphaCutoff`. |
| A texture | A `Texture` at its sampler's wrap and filters. A base color or emissive map is read as sRGB, a metallic-roughness or normal map as linear. One glTF texture read both ways is two textures. |
| A node | An `Object3D` at its translation, rotation and scale, or at its matrix decomposed. Each primitive of its mesh is a `Mesh`. |
| The default scene | Its roots and everything under them, each node after its parent. `scene` picks it. |

A primitive without a material draws with one default `standard_material`. A primitive with `COLOR_0` draws with a copy of its material that has `vertex_colors` on, one copy per material. An accessor without a buffer view reads as zeros. A normalized integer accessor divides by its largest value, as the specification has it.

glTF's texture coordinates run down from an image's top left. This renderer's `v` runs up from the bottom. Each glTF texture is given a `repeat` of `(1, -1)` and an `offset` of `(0, 1)`, which flips `v`, as three.js sets `flipY = false`. The geometry's coordinates are kept as the file has them.

### Not read

Skins, animations, cameras, morph targets and sparse accessors are not read. No extension is read. A file whose `extensionsRequired` names one is refused. A file that only lists an extension under `extensionsUsed` is read without it. A primitive of points, lines or strips is refused. Only the first set of texture coordinates is read.

### Errors

The loader raises for:

- A file it cannot read. A document that is not JSON or not glTF 2. A required extension.
- A buffer shorter than its length. A buffer view or accessor that runs past its buffer.
- An unknown accessor type or component type. An attribute of the wrong width. Indices that are not unsigned integers.
- An image that is not PNG, JPEG or TGA. A texture or material that names something the file does not have.
- An unknown wrap mode or alpha mode.
- A node reached twice. A node matrix that flattens an axis.

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
