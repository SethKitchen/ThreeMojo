# Model files

`loaders/obj.mojo` and `loaders/gltf.mojo`. `read_obj` reads a Wavefront OBJ file into named objects, each with a `BufferGeometry`. `parse_obj` reads the text of one. `read_gltf` reads a glTF 2.0 file, `.gltf` or `.glb`, into a scene and its assets.

![A cube loaded from an OBJ file turns under a lamp](out/model.png)

three.js: `OBJLoader`.

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

`ObjModel.objects` holds one `ObjObject` per object, in file order. `count()` says how many.

| Field | Meaning |
|---|---|
| `name` | From `o` or `g`. Empty when the file has neither. Faces read before the first `o` or `g` belong to it, as three.js has it. |
| `material` | The name from `usemtl`. Empty before one. The material library is not read. |
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
| `#` | A comment, to the end of the line. |

An index counts from one. A negative index counts back from the last entry so far. `mtllib`, `s`, `l`, `p` and unknown lines are skipped.

Every face of one object must agree about normals and texture coordinates. A geometry without normals shades flat. See [Renderer](Renderer).

## Errors

The parser raises, naming the line, for:

- A `v`, `vt` or `vn` line with too few coordinates. A coordinate that is not a number, or is not finite as a `Float32`.
- A face with fewer than three corners, or a corner with more than three parts.
- A face of four or more corners that is not convex, or has no area. A fan covers a convex polygon and only that.
- An index that is not a whole number, is zero, or names an entry the file does not have.
- A face that names a normal or a texture coordinate where an earlier face of the object did not, or the other way round.

`read_obj` raises for a file it cannot read.

## Example

`assets/cube.obj` is a unit cube with normals and texture coordinates. `tests/test_obj.mojo` reads it and draws it.

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
| `decode_image(bytes) -> DecodedImage` | A PNG or a JPEG, told by its first bytes. |

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
- An image that is neither PNG nor JPEG. A texture or material that names something the file does not have.
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
