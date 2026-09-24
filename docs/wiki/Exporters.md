# Exporters

`exporters/gltf.mojo`, `exporters/obj.mojo`, `exporters/stl.mojo` and `exporters/ply.mojo` write a scene and its assets to model files. `exporters/exr.mojo` writes an HDR image. `exporters/usdz.mojo` writes a scene for AR Quick Look. Each file reads back through the matching loader in `loaders/` to the same geometry. A glTF file also reads back to the same node transforms and materials. three.js: `GLTFExporter`, `OBJExporter`, `STLExporter` and `PLYExporter`.

To write a scene as three.js JSON, see [Scene JSON](Scene-JSON).

```mojo
scene.update()
write_gltf("out/model.glb", scene, assets, GLB)
write_obj("out/model.obj", scene, assets)
write_stl("out/model.stl", scene, assets, STL_BINARY)
write_ply("out/model.ply", scene, assets, PLY_BINARY_LITTLE_ENDIAN)
```

| Function | Meaning |
|---|---|
| `export_gltf(scene, assets, container, binary_name, only_visible) -> GltfFiles` | A glTF 2.0 file, and its `.bin` for `GLTF_SEPARATE`. |
| `write_gltf(path, scene, assets, container, only_visible)` | Write a `.gltf` or a `.glb` file. |
| `export_obj(scene, assets) -> String` | The text of an OBJ file. |
| `write_obj(path, scene, assets)` | Write an OBJ file. |
| `export_stl(scene, assets, format) -> List[UInt8]` | The bytes of an STL file. |
| `write_stl(path, scene, assets, format)` | Write an STL file. |
| `export_ply(scene, assets, format) -> List[UInt8]` | The bytes of a PLY file. |
| `write_ply(path, scene, assets, format)` | Write a PLY file. |
| `export_exr(width, height, data, compression, type) -> List[UInt8]` | An OpenEXR file of RGBA floats. See [EXR](#exr). |
| `export_exr_half(width, height, data, compression, type) -> List[UInt8]` | An OpenEXR file of RGBA halves. |
| `export_exr_image(image, compression, type) -> List[UInt8]` | An OpenEXR file of a `FloatImage`. |
| `export_usdz(scene, assets, cameras, options) -> List[UInt8]` | A USDZ archive for AR Quick Look. See [USDZ](#usdz). |
| `usdz_files(scene, assets, cameras, options) -> UsdzFiles` | The files of the archive: `model.usda`, the geometries and the textures. |
| `zlib_deflate(data, level) -> List[UInt8]`, `deflate(data, level)` | A zlib or a raw DEFLATE stream, as fflate writes it. These are in `render/deflate.mojo`. |

## glTF

`export_gltf` writes the nodes, the meshes, the materials and the textures of a scene. `read_gltf` reads the file back. See [Model files](Model-files).

### Containers

`GltfContainer` is a type. `export_gltf` refuses a value that is none of the three.

| Container | Meaning |
|---|---|
| `GLTF_EMBEDDED` | One `.gltf`. The buffer and the images are `data:` URIs in the JSON. This is the default. |
| `GLTF_SEPARATE` | A `.gltf` and a `.bin` beside it. The buffer names the `.bin` by a relative URI. The images are `data:` URIs. |
| `GLB` | One binary container: a JSON chunk, then a binary chunk. The images are in the binary chunk. |

`GltfFiles` has `document`, the `.gltf` text as UTF-8 or the whole `.glb`, and `binary`, the `.bin`. `binary` is empty for `GLTF_EMBEDDED` and `GLB`. `write_gltf` names the `.bin` after the `.gltf`: `scene.gltf` gets `scene.bin`. `binary_name_for(path)` gives that name.

### Nodes

Each node becomes a glTF node with its name, its translation, its rotation, its scale and its children. A node with `matrix_auto_update` off writes its `matrix` instead. The writer leaves out a transform that moves nothing, as three.js does.

The nodes keep the scene order. Node `k` of the file is the `k`th node that the writer keeps. With `only_visible`, the default, a hidden node is left out, with its descendants and its meshes. This is three.js's `onlyVisible`.

### Meshes

The meshes on one node become one glTF mesh with one primitive each. `read_gltf` reads each primitive back as one `Mesh` on that node.

A mesh that wears a list of materials writes one primitive for each group, as three.js's `processMesh` writes it. Each primitive has the slice of the index that the group draws, and the material of the group. A geometry without an index gets one for the slice. A group whose material is not in the list writes nothing, because nothing is drawn for it. three.js writes it with no material. A node whose meshes write no primitive gets no mesh.

| Attribute | Meaning |
|---|---|
| `POSITION` | Always. The accessor has `min` and `max`, as the specification requires. |
| `NORMAL` | When the geometry has `normal`. |
| `TEXCOORD_0` | When the geometry has `uv`. |
| `TEXCOORD_1` | When the geometry has `uv1`. |
| `COLOR_0` | When the geometry has `color` and the material has `vertex_colors` on. `read_gltf` turns `vertex_colors` on for a primitive with `COLOR_0`. |
| `indices` | When the geometry has an index. Unsigned shorts for up to 65535 vertices, unsigned integers above that. |

A geometry that two meshes use is written once. A material that two meshes use is written once. The buffer views start on four-byte boundaries.

### Materials

Every material is written as a metallic-roughness material.

| Property | glTF |
|---|---|
| `color`, `opacity` | `baseColorFactor`, in linear light. Left out for opaque white. |
| `metalness`, `roughness` | `metallicFactor`, `roughnessFactor`. A kind that is not `STANDARD` or `PHYSICAL` writes zero and one, as three.js does. |
| `map` | `baseColorTexture`. |
| `roughness_map`, `metalness_map` | `metallicRoughnessTexture`. See [Textures](#textures). |
| `normal_map`, `normal_scale.x` | `normalTexture` and its `scale`. |
| `ao_map`, `ao_map_intensity` | `occlusionTexture` and its `strength`. The texture's `channel` is the `texCoord`. |
| `emissive` | `emissiveFactor`, in linear light. |
| `emissive_intensity` | The `KHR_materials_emissive_strength` extension, when it is not one. |
| `emissive_map` | `emissiveTexture`. |
| A transparent material | `alphaMode` `BLEND`. |
| `alpha_test` above zero | `alphaMode` `MASK`, and `alphaCutoff`. |
| `DOUBLE_SIDE` | `doubleSided`. |
| `BASIC` | The `KHR_materials_unlit` extension. |

Every extension that the writer uses is listed once in `extensionsUsed`. The writer lists none in `extensionsRequired`, as three.js does.

### Physical extensions

A `PHYSICAL` material writes the extensions that `read_gltf` reads for it. Thus a file that is read, written and read again keeps them. The writer writes an extension when a field that it holds is not at its default.

| Property | Extension |
|---|---|
| `ior` | `KHR_materials_ior`. |
| `specular_intensity`, `specular_color`, `specular_intensity_map`, `specular_color_map` | `KHR_materials_specular`: `specularFactor` and `specularColorFactor`, in linear light, `specularTexture` and `specularColorTexture`. The intensity is in the alpha, and the image keeps it. |
| `clearcoat`, `clearcoat_roughness`, the three coat maps | `KHR_materials_clearcoat`: `clearcoatFactor`, `clearcoatRoughnessFactor`, `clearcoatTexture`, `clearcoatRoughnessTexture` and `clearcoatNormalTexture`. The normal texture's `scale` is the x of `clearcoat_normal_scale`, as three.js writes it. |
| `transmission`, `transmission_map` | `KHR_materials_transmission`: `transmissionFactor` and `transmissionTexture`. |
| `thickness`, `thickness_map`, `attenuation_distance`, `attenuation_color` | `KHR_materials_volume`: `thicknessFactor` in meters, `thicknessTexture`, `attenuationDistance` in meters when it is finite, and `attenuationColor` in linear light. |
| `dispersion` | `KHR_materials_dispersion`. |

A `PHYSICAL` material with every field at its default writes no extension. `read_gltf` reads it back as a `STANDARD` material, as three.js does.

### Sheen, iridescence and anisotropy

A `PHYSICAL` material writes its sheen, its thin film and its stretched lobe, with their maps. The writer writes each extension when its amount is not zero, as three.js does. A layer with an amount of zero draws nothing, so the writer drops its other fields.

| Property | Extension |
|---|---|
| `sheen`, `sheen_color`, `sheen_roughness`, `sheen_color_map`, `sheen_roughness_map` | `KHR_materials_sheen`: `sheenColorFactor` in linear light, times `sheen`. `sheenRoughnessFactor`, `sheenColorTexture` and `sheenRoughnessTexture`. |
| `iridescence`, `iridescence_ior`, the thickness range, `iridescence_map`, `iridescence_thickness_map` | `KHR_materials_iridescence`: `iridescenceFactor`, `iridescenceIor`, `iridescenceThicknessMinimum` and `iridescenceThicknessMaximum` in nanometers, `iridescenceTexture` and `iridescenceThicknessTexture`. |
| `anisotropy`, `anisotropy_rotation`, `anisotropy_map` | `KHR_materials_anisotropy`: `anisotropyStrength`, `anisotropyRotation` in radians, and `anisotropyTexture`. |

The sheen roughness is in the alpha channel of its texture. The written image keeps the alpha, and `read_gltf` reads it back. Each map writes its channel as `texCoord` and its transform as `KHR_texture_transform`, as every other map does.

glTF has no sheen amount. `read_gltf` reads a sheen of one, as three.js does. The renderer multiplies the sheen color by the amount, so the writer writes the color times the amount. The material draws the same after it is read back.

### Textures

Each texture becomes a PNG image and a sampler. The sampler holds the wrap, the filter and whether the texture has a mip chain. Each distinct image is written once, as three.js's `processImage` caches it. Two textures with the same pixels and size share one image, and each keeps its own sampler.

The `v` coordinate of glTF runs down from the top of the image. The `v` coordinate of this renderer runs up from the bottom. Thus the writer turns the image upside down, as three.js does for a `flipY` texture. A texture from `read_gltf` has this flip in its `repeat` and `offset`. The writer keeps the image of such a texture as it is.

A texture with an `offset`, a `repeat`, a `rotation` or a `center` is written with the `KHR_texture_transform` extension, as three.js writes it. The extension holds only what moves: `offset`, `rotation` and `scale`. `GltfPlacement.of(texture)` gives the transform and the `texCoord` that the writer writes.

- A texture with a `repeat.y` of zero or more has its image turned upside down. Its transform is its own.
- A texture with a negative `repeat.y` has its image kept as it is. A texture from `read_gltf` is of this kind. The flip of `v` goes into its transform. The `v` of the offset is one minus the matrix's, and the `v` of the scale changes sign.
- The offset is the translation of the texture's whole matrix. Thus a texture turned or scaled about its `center` samples the same when it is read back.

glTF keeps roughness in green and metalness in blue, in one image. When the two maps are one texture, the writer writes it once. When they are different textures, the writer combines them into one image, as three.js does. The combined image has red at zero, and white in a channel that has no map. The two maps must have one transform and one channel, because one texture reference holds them.

three.js writes the transform of the metalness map for both and only warns. This port refuses the pair, because the roughness map would then read back at the wrong place. Every other map keeps its own transform and channel.

## OBJ

`export_obj` writes each mesh as one `o`, named after its node. Then it writes the positions as `v`, the texture coordinates as `vt`, the normals as `vn` and the triangles as `f`. The corner numbers count from one across the whole file, as three.js counts them. `read_obj` reads each mesh back as one object with a non-indexed geometry.

`export_obj` refuses a name that `read_obj` reads back differently: a name with `#`, or with spaces other than one space between words.

A mesh that wears a list of materials writes each group that it draws as a run of faces, in the order of the groups. Each run starts with `usemtl material` and the id of its material, for example `usemtl material3`. A material here has no name, so the id names it. `read_obj` reads the runs back as groups. three.js writes a `usemtl` only for one named material, and no groups.

## STL

`export_stl` writes each triangle as one facet. The facet normal is `(C - B) x (A - B)`, made unit length, as three.js calculates it. The vertex normals of the geometry are not written.

`StlFormat` is a type. `export_stl` refuses a value that is not one of the two formats.

| Format | Meaning |
|---|---|
| `STL_ASCII` | `solid exported`, one `facet` for each triangle, and `endsolid exported`. This is the default. |
| `STL_BINARY` | An 80-byte header of zeros, the face count, and 50 bytes for each face. The attribute is zero. |

## PLY

`export_ply` writes all meshes into one `vertex` element and one `face` element. A face is `property list uchar int vertex_index`, with three corners.

| Property | Meaning |
|---|---|
| `x`, `y`, `z` | Always, as `float`. |
| `nx`, `ny`, `nz` | When a mesh has normals. |
| `s`, `t` | When a mesh has texture coordinates. |
| `red`, `green`, `blue` | When a mesh has colors, as `uchar` in sRGB. |

A mesh without a property writes zeros for a normal and a texture coordinate, and white for a color, as three.js does. The format is `PlyFormat` from `loaders/ply.mojo`: `PLY_ASCII`, the default, `PLY_BINARY_LITTLE_ENDIAN` or `PLY_BINARY_BIG_ENDIAN`.

## EXR

`exporters/exr.mojo` writes RGBA texels as an OpenEXR file. three.js: `EXRExporter`. `render.exr.decode` reads the file back.

```mojo
var bytes = export_exr_image(image, ZIP_COMPRESSION, HALF_SAMPLES)
```

- `export_exr` takes the `Float32` texels of a three.js `FloatType` data texture. `export_exr_half` takes the half bits of a `HalfFloatType` one. Both take four values a texel, from the bottom row up.
- `export_exr_image` takes a `FloatImage`, from the top row down. `decode` gives the same image back.
- The compression is `NO_COMPRESSION`, `ZIPS_COMPRESSION` (one line a block) or `ZIP_COMPRESSION` (sixteen lines a block, the default).
- The sample type is `HALF_SAMPLES` (the default) or `FLOAT_SAMPLES`. A half is made as three.js's `DataUtils.toHalfFloat` makes it: the extra bits are cut off, and a value is clamped to 65,504.
- The channels are `A`, `B`, `G` and `R`. The header has the attributes that three.js writes, in its order.

zlib is a port of fflate 0.8.2, the library that three.js exports with. `render/deflate.mojo` gives the same bytes as fflate at each level from 0 to 9.

### Differences from three.js

three.js writes two kinds of block that its own `EXRLoader` reads wrong values from. This port writes them as OpenEXR says:

- The last block of a `ZIP_COMPRESSION` file, when the height is not a multiple of 16. three.js compresses it at the size of a full block, with bytes of the block before it. This port compresses only the real lines.
- A block that zlib does not make smaller, for example in a small image. A reader takes such a block as raw lines. three.js writes the zlib stream. This port writes the raw lines.

Every other block, and the header, are the bytes that three.js writes. A NaN is written as three.js writes it on x86-64: `0xFE00` as a half, and `0x7FC00000` as a float. An image with no texels, or data of the wrong length, is refused.

## USDZ

`exporters/usdz.mojo` writes a scene as a USDZ archive. three.js: `USDZExporter`.

```mojo
var archive = export_usdz(scene, assets, cameras)
```

The archive is a ZIP file that is not compressed. Each file's data starts at a multiple of 64 bytes. It holds:

- `model.usda`: a `Root` `Xform`, a `Scenes` scope and a `Scene` `Xform` that holds the nodes, then a `Materials` scope.
- `geometries/Geometry_<id>.usda`: one `Mesh` for each geometry, with its triangles, normals, points, texture coordinates and colors.
- `textures/Texture_<id>_true.png`: one PNG for each texture.

| Node | USD |
|---|---|
| A node with one mesh of a `STANDARD` or `PHYSICAL` material | An `Xform` that references its geometry file and binds its material. |
| A node with one mesh of another material | Not written, and nothing under it, as in three.js. |
| A node with one camera of `cameras` | A `Camera`, with its clipping range and apertures. A perspective camera has a film gauge of 35 and a focus of 10, as in three.js. |
| A node with more than one mesh or camera | An `Xform` with one child for each. three.js has no such node. |
| Any other node | An `Xform`. |

| `UsdzOptions` field | three.js option | Default |
|---|---|---|
| `anchoring_type` | `ar.anchoring.type` | `plane` |
| `plane_alignment` | `ar.planeAnchoring.alignment` | `horizontal` |
| `include_anchoring_properties` | `includeAnchoringProperties` | `True` |
| `only_visible` | `onlyVisible` | `True` |
| `quick_look_compatible` | `quickLookCompatible` | `False` |

Each material is a `UsdPreviewSurface`. It has the color or the map, the emissive color or map, the normal map, the ao map, the roughness, the metalness and the opacity. A `PHYSICAL` material also has the clear coat and the index of refraction. Each map has a `UsdTransform2d` of the texture's repeat, offset and rotation.

### Numbers

The text is the text that three.js writes for a scene whose numbers are short decimals:

- A vertex value has seven significant digits, as three.js writes it.
- A color is the linear double that three.js's `setHex` gives for the same sRGB bytes.
- Another number is held here as a `Float32` and in three.js as a double. It is written as the shortest text that reads back to the `Float32`, so `0.1` is `0.1`.
- A matrix is this port's `Float32` matrix. A turn that a `Float32` cannot hold exactly is written a few units apart in the last digits.

`loaders/js_number.mojo` has the JavaScript number text that this uses: `js_number_text`, `js_float32_text`, `js_to_precision` and `js_to_fixed`.

### Differences from three.js

- Each texture is written as its own pixels, as a PNG from `render.png`, at its own size. three.js draws it on a canvas and scales it to `maxTextureSize`.
- A texture file is named for the texture's id. three.js names it for the id of its source.
- Each file's data starts at a multiple of 64 bytes. three.js pads each file by a count that is right only for the first file.
- A geometry that is not whole triangles is refused. three.js throws a `RangeError`.

## World space

OBJ, STL and PLY hold no transforms. Thus their writers put each vertex through the world matrix of its node, as three.js does. Each normal goes through the normal matrix and is made unit length. The scene must be current. Call `scene.update()` first, or the writer raises.

## Numbers

A number is written as the shortest text that reads back to the same `Float32`. `String(Float32)` misses by one unit in the last place for about one number in 200. For those numbers, the writer uses the exact `Float64` text. The writer refuses a number that is not finite.

`exporters/json_writer.mojo` has `JsonWriter`, which writes JSON one value at a time. It adds the commas and the colons. It refuses a value in an object without a key, a key outside an object, and a close that does not match its open. It escapes a string as RFC 8259 requires. `quote_json(text)` gives the escaped string.

## Differences from three.js

- A PLY color is rounded to the nearest byte. three.js rounds down, and then a file loses one level each time it is read and written again.
- A PLY color is clamped to zero through one before it is encoded.
- `KHR_materials_emissive_strength` is written for every kind of material. three.js writes it only for a standard or physical material.
- A texture's `center` is folded into the `offset` of its transform. three.js drops the `center`.
- A volume is written when any of its fields is not at its default. three.js writes it only for a material that transmits. A clear coat is written when its roughness is not zero, also when its factor is zero.
- The sheen color is written times the `sheen` amount. three.js writes the color as it is, so an amount between zero and one is lost.
- An ao map on a `BASIC` material is written, as three.js writes it. `read_gltf` reads no occlusion for an unlit material.
- A combined metallic-roughness image needs two maps of one size. three.js scales them to one size.
- A node that keeps its own matrix writes `matrix`. Every other node writes its translation, its rotation and its scale. three.js writes `matrix` unless you set `trs`.
- An empty geometry is refused by `export_gltf`. glTF does not allow a buffer view of zero bytes.

## Not written

- Lights, cameras, animations, skins and morph targets.
- Instanced, batched and skinned meshes, lines, points and sprites.
- Bump maps, alpha maps, light maps, specular maps, displacement maps, environment maps, matcaps and gradient maps.
- The groups of a geometry of a mesh with one material, as in three.js.
- A `BACK_SIDE` material is written single-sided, as three.js writes it. glTF has no back side.
- OBJ materials and a material library. three.js writes none. Only the `usemtl` names of a mesh that wears a list are written.

## Errors

The writers raise for:

- A container or a format that is none of the named values.
- A `.bin` name that is empty or has a scheme, for `GLTF_SEPARATE`.
- A mesh that names a node, a geometry, a material or a texture that is not there.
- A geometry without `position`, or with an attribute of the wrong size or count.
- An index entry past the last vertex, or a geometry without an index that is not whole triangles.
- A blank texture, or a texture with a wrap, filter, color space or channel that is none of its named values.
- A roughness map and a metalness map that are not one size, or that do not share one transform and one channel.
- A number that is not finite.
- A stale scene, or a node whose world matrix flattens an axis, for OBJ, STL and PLY.
- An EXR image with no texels, data that is not four values a texel, a compression other than none, ZIPS or ZIP, or a sample type other than HALF or FLOAT.
- A DEFLATE level that is not from 0 to 9.
- A USDZ mesh that names a node that is not in the scene, a geometry with no position or that is not whole triangles, or a texture with a wrap or a channel that is not valid.

## Example

`tests/test_gltf_exporter.mojo` writes a scene in the three containers and reads each file back with `read_gltf`. `tests/test_model_exporters.mojo` does the same for OBJ, STL and PLY. `tests/test_exr_export.mojo` compares EXR files with the files that three.js 0.180 writes, in `assets/exr_export/three.json`. `tests/test_deflate.mojo` compares zlib and DEFLATE streams with fflate's, in `assets/deflate/fflate.json`, and Huffman code lengths with fflate's, in `assets/deflate/trees.json`. `tests/test_usdz.mojo` compares the `.usda` files with the files that three.js writes, in `assets/usdz/three.json`. `tests/test_js_number.mojo` compares the number text with V8's, in `assets/js_number/v8.json`.
