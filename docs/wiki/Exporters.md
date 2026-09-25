# Exporters

`exporters/gltf.mojo`, `exporters/obj.mojo`, `exporters/stl.mojo` and `exporters/ply.mojo` write a scene and its assets to model files. `exporters/exr.mojo` writes an HDR image, and `exporters/ktx2.mojo` a texture. `exporters/usdz.mojo` writes a scene for AR Quick Look, and `exporters/draco.mojo` writes a geometry as a Draco file. Each file reads back through the matching loader in `loaders/` to the same geometry. A glTF file also reads back to the same node transforms and materials. three.js: `GLTFExporter`, `OBJExporter`, `STLExporter`, `PLYExporter` and `DRACOExporter`.

![A knot written to glTF and read back turns under a lamp](out/exporters.png)

`examples/reloaded.mojo` draws the knot that `read_gltf` built. To write a scene as three.js JSON, see [Scene JSON](Scene-JSON).

```mojo
scene.update()
write_gltf("out/model.glb", scene, assets, GLB)
write_obj("out/model.obj", scene, assets)
write_stl("out/model.stl", scene, assets, STL_BINARY)
write_ply("out/model.ply", scene, assets, PLY_BINARY_LITTLE_ENDIAN)
```

| Function | Meaning |
|---|---|
| `export_gltf(scene, assets, container, binary_name, only_visible, cameras, animations, options) -> GltfFiles` | A glTF 2.0 file, and its `.bin` for `GLTF_SEPARATE`. |
| `write_gltf(path, scene, assets, container, only_visible, cameras, animations, options)` | Write a `.gltf` or a `.glb` file. |
| `export_obj(scene, assets) -> String` | The text of an OBJ file, with its meshes, lines and points. |
| `write_obj(path, scene, assets)` | Write an OBJ file. |
| `export_stl(scene, assets, format) -> List[UInt8]` | The bytes of an STL file. |
| `write_stl(path, scene, assets, format)` | Write an STL file. |
| `export_ply(scene, assets, format, exclude_normals=, exclude_uvs=, exclude_colors=, exclude_index=) -> List[UInt8]` | The bytes of a PLY file, with its meshes and points. |
| `write_ply(path, scene, assets, format, exclude_normals=, exclude_uvs=, exclude_colors=, exclude_index=)` | Write a PLY file. |
| `export_exr(width, height, data, compression, type) -> List[UInt8]` | An OpenEXR file of RGBA floats. See [EXR](#exr). |
| `export_exr_half(width, height, data, compression, type) -> List[UInt8]` | An OpenEXR file of RGBA halves. |
| `export_exr_image(image, compression, type) -> List[UInt8]` | An OpenEXR file of a `FloatImage`. |
| `export_ktx2(texture, channels, half, writer) -> List[UInt8]` | A KTX 2.0 file of a texture. See [KTX2](#ktx2). |
| `export_ktx2_volume(texture, channels, half, writer) -> List[UInt8]` | A KTX 2.0 file of a `Data3DTexture`. |
| `export_usdz(scene, assets, cameras, options) -> List[UInt8]` | A USDZ archive for AR Quick Look. See [USDZ](#usdz). |
| `usdz_files(scene, assets, cameras, options) -> UsdzFiles` | The files of the archive: `model.usda`, the geometries and the textures. |
| `export_draco(geometry, kind, options) -> List[UInt8]` | A Draco file of a mesh or a point cloud. See [Draco](#draco). |
| `write_draco(path, geometry, kind, options)` | Write a Draco file. |
| `zlib_deflate(data, level) -> List[UInt8]`, `deflate(data, level)` | A zlib or a raw DEFLATE stream, as fflate writes it. These are in `render/deflate.mojo`. |

## glTF

`export_gltf` writes the nodes, the meshes, the materials and the textures of a scene. It also writes the lights, the cameras, the skins, the morph targets, the instances, the lines, the points and the animation clips. `read_gltf` reads the file back. See [Model files](Model-files).

```mojo
var files = export_gltf(
    scene, assets, GLB, cameras=cameras, animations=clips
)
```

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

### User data and options

`GltfExportOptions` holds the options of three.js's `GLTFExporter` that are not arguments of `export_gltf`. It also holds the user data of the scene and of each material, because a `Scene` and a `Material` here hold no user data.

| Field | three.js | Default |
|---|---|---|
| `max_texture_size` | `maxTextureSize` | None: no limit |
| `include_custom_extensions` | `includeCustomExtensions` | `False` |
| `scene_user_data` | `scene.userData` | Empty |
| `set_material_user_data(id, data)` | `material.userData` | Empty |

The user data of a node, of a geometry, of the scene and of each material is written as `extras`, as three.js's `serializeUserData` writes it. A geometry's user data goes on each primitive that draws it. User data is a `UserData` from `core/user_data.mojo`, the same map that [Scene JSON](Scene-JSON) writes.

With `include_custom_extensions`, a `gltfExtensions` key in user data is written as the object's `extensions`. Each name also goes into `extensionsUsed`. The rest of the user data stays in `extras`. The value of `gltfExtensions` must be an object. A custom extension comes before the extensions that the writer adds. A custom extension with the name of a writer's extension takes the writer's value, as a three.js plugin overwrites it.

`max_texture_size` clamps the width and the height of each image, each side on its own, as three.js's canvas does. The writer resamples the image bilinear at the center of each pixel. three.js lets the browser's canvas resample it, so the pixels can differ. A size below one is refused.

```mojo
var options = GltfExportOptions()
options.max_texture_size = 1024
options.include_custom_extensions = True
options.scene_user_data.set_string("author", "me")
var files = export_gltf(scene, assets, options=options)
```

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
| `metalness`, `roughness` | `metallicFactor`, `roughnessFactor`. A kind that is not `STANDARD` or `PHYSICAL` writes zero and one, as three.js does. An unlit `BASIC` material writes a roughness of 0.9, as three.js's unlit extension does. |
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

A `STANDARD` or `PHYSICAL` material with a `bump_map` writes the `EXT_materials_bump` extension, as three.js does. The extension holds `bumpTexture` and `bumpFactor`, the `bump_scale`. `read_gltf` reads it back as a `PHYSICAL` material, as three.js does. Another kind with a bump map writes no bump map.

Every extension that the writer uses is listed once in `extensionsUsed`. Only `EXT_mesh_gpu_instancing` is listed in `extensionsRequired`, as three.js lists it. A reader without it draws one instance, not all of them.

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

### What a node carries

A glTF node carries one mesh, one skin, one camera and one light. The writer puts on one node everything that rides one scene node. These are the rules for each kind of thing.

#### Lights

A directional light, a point light and a spot light are written with the `KHR_lights_punctual` extension, as three.js's `GLTFLightExtension` writes them. Each light is one entry of the extension's `lights`, and its node names that entry.

| Property | glTF |
|---|---|
| The node's name | `name`, when the node has one. |
| `color` | `color`, in linear light. |
| `intensity` | `intensity`. |
| The kind | `type`: `directional`, `point` or `spot`. |
| `distance` of a point or spot light | `range`, when it is above zero. |
| `angle` and `penumbra` of a spot light | `spot.outerConeAngle` is the angle. `spot.innerConeAngle` is `(1 - penumbra) * angle`. |

glTF points a directional light and a spot light down the -z axis of its node. The writer does not write the target. A target that is a child of the light's node, on its -z axis, keeps the direction. `read_gltf` adds such a target. Any other target loses its direction, and three.js only warns.

glTF lights fall off with a decay of two. The writer does not write the decay.

An ambient light, a hemisphere light, a rect area light and a light probe have no glTF form. The writer leaves them out, as three.js does.

#### Cameras

The `cameras` argument is a `CameraList`. Each camera rides a node of the scene, and the node names the camera. A camera on a hidden node is left out with the node.

| Camera | glTF |
|---|---|
| `PerspectiveCamera` | `perspective`: `aspectRatio`, `yfov` in radians, `zfar` and `znear` in meters. |
| `OrthographicCamera` | `orthographic`: `xmag` and `ymag`, half the width and half the height, and `zfar` and `znear` in meters. |

The camera's `name` is the node's name. The zoom and the view offset are not written, as three.js does not write them.

#### Morph targets

A geometry's morph targets are the primitive's `targets`, as three.js writes them. Each target has a `POSITION` and, when the geometry has morph normals, a `NORMAL`. glTF holds offsets. Thus a geometry without `morph_relative` has the base taken off each target.

The glTF mesh writes `weights`, the `morph_influences` of the mesh. It writes `extras.targetNames`, from the geometry's `morph_names`. A target with no name is named by its index, as three.js names it. `read_gltf` reads the names back into `morph_names`.

All primitives of one glTF mesh have one set of targets and one set of weights. Thus the meshes on one node must have as many morph targets and wear one set of influences. An instanced mesh, a line and points on such a node add zero weights, as three.js starts them at zero.

#### Skins

A skinned mesh writes `JOINTS_0` as unsigned shorts and `WEIGHTS_0` as floats. Its node gets a skin, as three.js's `processSkin` writes it.

| Skin | Value |
|---|---|
| `joints` | The node of each bone. |
| `skeleton` | The node of the first bone. |
| `inverseBindMatrices` | The inverse bind of each bone, times the `bind_matrix` of the mesh. |

The skinned meshes on one node must share one skeleton and one bind matrix. A node with a skinned mesh carries no other mesh, line or points, since glTF skins the whole mesh of a node.

#### Instances

An instanced mesh writes the `EXT_mesh_gpu_instancing` extension on its node, as three.js's `GLTFMeshGpuInstancing` writes it. The matrix of each instance is split into `TRANSLATION`, `ROTATION` and `SCALE`. The colors of the instances are `_COLOR_0`, in linear light, when the mesh has colors.

The instanced meshes on one node must place and color their instances alike. A node with an instanced mesh carries no other mesh, line or points, since glTF instances the whole mesh of a node.

#### Lines and points

A line and points are primitives of their own mode, as three.js writes them. The geometry has no index here, so the primitive has none.

| Object | `mode` |
|---|---|
| `Points` | `POINTS`, 0. |
| `Line` with `SEGMENTS` | `LINES`, 1. |
| `Line` with `LOOP` | `LINE_LOOP`, 2. |
| `Line` with `STRIP` | `LINE_STRIP`, 3. |

The material is written as every other material is. A `BASIC` material writes `KHR_materials_unlit`. The point size is not written, because glTF has no point size.

### Animations

The `animations` argument is a list of `AnimationClip`s. Each clip becomes one glTF animation, as three.js's `processAnimation` writes it. An unnamed clip is named `clip_` and its index.

| Track | Channel `path` |
|---|---|
| `POSITION` of a node | `translation`. |
| `QUATERNION` of a node | `rotation`. |
| `SCALE` of a node | `scale`. |
| `MORPH_INFLUENCE` or `SKINNED_MORPH_INFLUENCE` | `weights`, on the node of the mesh. |

A `STEP` track is written `STEP`. A `CUBIC_SPLINE` track is written `CUBICSPLINE`, with each key's in-tangent, value and out-tangent in that order. Every other track is written `LINEAR`, as three.js writes it. Each sampler's `input` has the `min` and the `max` that the specification requires.

A glTF `weights` channel drives every target of a node at once. Thus the writer merges the morph tracks of one node into one channel, as three.js's `mergeMorphTargetTracks` merges them:

1. The channel starts with the keys of the first track. Every other target is zero at each key.
2. Each next track gives its value at every key of the channel. A step track holds its last key, and a linear track is blended.
3. Each key of that track is added to the channel, unless a key is within a millisecond of it. A new key starts with the channel's own value at that time.

A cubic spline merges only with cubic splines at the same times. three.js refuses to merge a cubic spline at all.

A track on a node that is not written is left out. So is a track of any other kind: `VISIBLE`, a material, a light or a camera. three.js leaves such a track out and warns. A clip left with no channel is not written, since a glTF animation needs one.

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

A line and points are written as three.js's `OBJExporter` writes them:

| Object | OBJ |
|---|---|
| A `Line` of `STRIP` | An `o`, the positions as `v`, and one `l` through every vertex. |
| A `Line` of `SEGMENTS` | An `o`, the positions as `v`, and one `l` for each pair of vertices. A last vertex without a pair has no `l`. |
| A `Line` of `LOOP` | An `o` and the positions as `v`. three.js writes no `l` for a `LineLoop`. |
| A `Points` | An `o`, the positions as `v`, and one `p` through every vertex. When the geometry has colors, each `v` has the color after the position, in sRGB. |

The index of a line or points is not read, as in three.js. `read_obj` skips `l` and `p`.

## STL

`export_stl` writes each triangle as one facet. The facet normal is `(C - B) x (A - B)`, made unit length, as three.js calculates it. The vertex normals of the geometry are not written.

A skinned mesh is written where its bones hold it now, as three.js's `applyBoneTransform` puts it. The other writers write a skinned mesh at rest, as three.js does.

`StlFormat` is a type. `export_stl` refuses a value that is not one of the two formats.

| Format | Meaning |
|---|---|
| `STL_ASCII` | `solid exported`, one `facet` for each triangle, and `endsolid exported`. This is the default. |
| `STL_BINARY` | An 80-byte header of zeros, the face count, and 50 bytes for each face. The attribute is zero. |

## PLY

`export_ply` writes all meshes and all points into one `vertex` element, and the faces of the meshes into one `face` element. A face is `property list uchar int vertex_index`, with three corners. A text file ends with one more line break, as three.js ends it.

| Property | Meaning |
|---|---|
| `x`, `y`, `z` | Always, as `float`. |
| `nx`, `ny`, `nz` | When a mesh has normals. |
| `s`, `t` | When a mesh has texture coordinates. |
| `red`, `green`, `blue` | When a mesh has colors, as `uchar` in sRGB. |

A mesh without a property writes zeros for a normal and a texture coordinate, and white for a color, as three.js does. The format is `PlyFormat` from `loaders/ply.mojo`: `PLY_ASCII`, the default, `PLY_BINARY_LITTLE_ENDIAN` or `PLY_BINARY_BIG_ENDIAN`.

A scene with points writes no `face` element, as in three.js. Then a mesh need not be whole triangles. The texture coordinates are written when a mesh has them. Then points write their own texture coordinates, or zeros.

The four `exclude_` flags are three.js's `excludeAttributes`:

| Flag | three.js | Leaves out |
|---|---|---|
| `exclude_normals` | `'normal'` | `nx`, `ny` and `nz`. |
| `exclude_uvs` | `'uv'` | `s` and `t`. |
| `exclude_colors` | `'color'` | `red`, `green` and `blue`. |
| `exclude_index` | `'index'` | The `face` element. The file is a point cloud. |

With faces, each mesh must be whole triangles. three.js checks only the total count of faces.

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

## KTX2

`exporters/ktx2.mojo` writes a texture as a KTX 2.0 file. three.js: `KTX2Exporter`. `render.ktx2.read` reads the file back to the same texels.

```mojo
var bytes = export_ktx2(texture)
var sky = export_ktx2(hdr, half=True)
```

- The file has one level, the texture's full size, with no supercompression.
- `channels` is 4, 2 or 1: the first channels of each texel, three.js's `RGBAFormat`, `RGFormat` or `RedFormat`.
- A byte texture is written as bytes: `SRGB` with the sRGB transfer function, and `LINEAR` with the linear one.
- A float texture is written as floats, or as halves when `half` is on. It must be `LINEAR`. A half is made as three.js's `DataUtils.toHalfFloat` makes it.
- The rows are written in the order the texture holds them, as three.js writes a data texture's array.
- The key and value data has one key, `KTXwriter`. Its value is `writer`, `ThreeMojo` by default. three.js writes `three.js` and its revision.
- A texture here has no `NoColorSpace`, so the primaries are always BT.709, three.js's for `LinearSRGBColorSpace`.

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
| A node with one mesh of a `STANDARD` or `PHYSICAL` material | An `Xform` that references its geometry file and binds its material. A skinned mesh is a mesh at rest. An instanced mesh is a mesh of its one geometry. |
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
| `max_texture_size` | `maxTextureSize` | `1024` |

Each material is a `UsdPreviewSurface`. It has the color or the map, the emissive color or map, the normal map, the ao map, the roughness, the metalness and the opacity. A `PHYSICAL` material also has the clear coat and the index of refraction. Each map has a `UsdTransform2d` of the texture's repeat, offset and rotation.

### Numbers

The text is the text that three.js writes for a scene whose numbers are short decimals:

- A vertex value has seven significant digits, as three.js writes it.
- A color is the linear double that three.js's `setHex` gives for the same sRGB bytes.
- Another number is held here as a `Float32` and in three.js as a double. It is written as the shortest text that reads back to the `Float32`, so `0.1` is `0.1`.
- A matrix is this port's `Float32` matrix. A turn that a `Float32` cannot hold exactly is written a few units apart in the last digits.

`loaders/js_number.mojo` has the JavaScript number text that this uses: `js_number_text`, `js_float32_text`, `js_to_precision` and `js_to_fixed`.

### Differences from three.js

- A texture larger than `max_texture_size` is scaled down to it, keeping its shape, as three.js's `imageToCanvas` scales it. The writer resamples it bilinear at the center of each pixel. three.js lets the canvas resample it, so the pixels can differ.
- A texture file is named for the texture's id. three.js names it for the id of its source.
- Each file's data starts at a multiple of 64 bytes. three.js pads each file by a count that is right only for the first file.
- A geometry that is not whole triangles is refused. three.js throws a `RangeError`.

## Draco

`exporters/draco.mojo` writes a mesh or a point cloud as a Draco file (`.drc`). three.js: `DRACOExporter`, which runs Draco's own encoder, compiled to WebAssembly. The port is that encoder, from Draco 1.5.6, the version of `draco3d` that three.js 0.180 uses. It writes the same bytes that three.js writes. `read_draco` reads the file back. See [Draco](More-model-files#draco).

```mojo
var bytes = export_draco(geometry)
var options = DracoExportOptions(encode_speed=0, decode_speed=0)
write_draco("out/cloud.drc", cloud, DRACO_EXPORT_POINTS, options)
```

Five modules hold its parts. `draco_writer.mojo` writes the bytes, the bits and the rANS streams. `draco_connectivity.mojo` builds the corner tables and writes the Edgebreaker symbols. `draco_predict.mojo` quantizes and predicts the attributes. `draco_kd_tree.mojo` writes the KD-tree of a point cloud. `draco_log2.mojo` has the logarithm of the C library that the WebAssembly encoder links.

| `DracoExportOptions` | Meaning |
|---|---|
| `encode_speed`, `decode_speed` | From 0 to 10. The larger of the two is Draco's speed. 0 gives the smallest file, and 10 the fastest encoder. The default of each is 5. |
| `encoder_method` | `DRACO_MESH_EDGEBREAKER_ENCODING`, the default, or `DRACO_MESH_SEQUENTIAL_ENCODING`. For a point cloud, Edgebreaker selects the KD-tree. |
| `quantization` | The bits of `POSITION`, `NORMAL`, `COLOR`, `TEX_COORD` and `GENERIC`, in that order. The default is `[16, 8, 8, 8, 8]`. A missing entry, or zero, keeps the floats. |
| `export_uvs`, `export_normals` | Write the `uv` and the `normal` of a mesh. Both are on by default. |
| `export_color` | Write the `color`, converted from linear to sRGB. It is off by default. |

`DracoObjectKind` is a type. `DRACO_EXPORT_MESH`, the default, is three.js's `Mesh`, and `DRACO_EXPORT_POINTS` is its `Points`. `DracoEncoderMethod` is a type too. A bare integer does not compile.

### Speed

The speed selects Draco's coding, as it does in three.js:

- Speed 0 stores the positions of a mesh in the order of the best prediction.
- Below speed 2, a mesh of 40 points or more takes the constrained multi-parallelogram prediction. Up to speed 7, it takes the parallelogram prediction. From speed 8, it takes the difference prediction.
- Below speed 4, the texture coordinates and the normals take their own predictions when the positions are quantized. Otherwise the normals take the difference prediction.
- Below speed 5, a mesh of 1000 triangles or more takes the valence traversal.
- From speed 6, all attributes share one connectivity, and no seam is written.
- A point cloud takes a KD-tree at level 6, or at level 10 minus the speed when that is less.

### Same as three.js

- Each file has the bytes that three.js 0.180 writes with draco3d 1.5.6. `make draco-export-check` compares 323 exports.
- Equal values and equal points are merged before the encoding, in the order they first come.
- A color is converted to sRGB with three.js's `LinearToSRGB`, and a normal is folded onto an octahedron.
- The size estimates use musl's `log2`, which the WebAssembly encoder links. The host's `log2` rounds some values differently.
- A cast of a float to an integer gives the smallest integer for `NaN`, as the WebAssembly build gives it.

### Differences from three.js

- A geometry without an index is written with one triangle for each three vertices. three.js gives Draco one triangle for each vertex. Draco then reads past the end of the index, so that file is not the same from one run to the next.
- A geometry quantized to more than 24 bits is written. The WebAssembly encoder can run out of memory there, and three.js throws.
- A `position` or a `normal` must have three components, a `uv` two, and a `color` three or four. three.js passes any item size to Draco.
- An attribute must have one value for each vertex, and a geometry must have a vertex.
- A speed must be from 0 to 10. A normal must be finite. Draco writes an infinite normal as the result of an overflow.
- A quantized attribute with a range of 2^31 or more is refused. Draco fails there, or writes a file that its decoder refuses.

## World space

OBJ, STL and PLY hold no transforms. Thus their writers put each vertex through the world matrix of its node, as three.js does. Each normal goes through the normal matrix and is made unit length. The scene must be current. Call `scene.update()` first, or the writer raises.

The writers write every mesh, in the order of `Scene.traverse`, as three.js's `traverse` reaches them. On one node, the meshes come first, then the skinned meshes, then the instanced meshes, then the lines and the points. three.js writes any object that `isMesh`:

- A skinned mesh is at rest. STL puts it where its bones hold it.
- An instanced mesh is its one geometry at its node. three.js reads `matrixWorld`, not `instanceMatrix`, so the instances are not written.

`exporters/common.mojo` has `world_meshes(scene, assets, options)`. It gives one `WorldMesh` for each mesh, line or points. `WorldOptions` chooses what it gathers: `posed`, `lines`, `points` and `whole_triangles`. `WorldKind` says what each is: `WORLD_MESH`, `WORLD_LINE` or `WORLD_POINTS`.

## Numbers

OBJ, STL and PLY write a number as three.js writes it: the JavaScript text of its exact `Float64`. Thus `1` is `1`, and the `Float32` nearest a tenth is `0.10000000149011612`. `format_js_float32` gives this text. three.js moves a vertex by a matrix in doubles, and this port in `Float32`s. The text is the same when both results are exact, for example after a move by whole numbers or a scale by two.

JSON numbers are written as the shortest text that reads back to the same `Float32`. `String(Float32)` misses by one unit in the last place for about one number in 200. For those numbers, the writer uses the exact `Float64` text. The writer refuses a number that is not finite.

`exporters/json_writer.mojo` has `JsonWriter`, which writes JSON one value at a time. It adds the commas and the colons. It refuses a value in an object without a key, a key outside an object, and a close that does not match its open. It escapes a string as RFC 8259 requires. `quote_json(text)` gives the escaped string.

## Differences from three.js

- A PLY color is clamped to zero through one before it is encoded.
- An OBJ point color above the linear part of the sRGB curve goes through the C library's `pow`. V8's `Math.pow` can give a different last digit.
- `KHR_materials_emissive_strength` is written for every kind of material. three.js writes it only for a standard or physical material.
- A texture's `center` is folded into the `offset` of its transform. three.js drops the `center`.
- A volume is written when any of its fields is not at its default. three.js writes it only for a material that transmits. A clear coat is written when its roughness is not zero, also when its factor is zero.
- The sheen color is written times the `sheen` amount. three.js writes the color as it is, so an amount between zero and one is lost.
- An ao map on a `BASIC` material is written, as three.js writes it. `read_gltf` reads no occlusion for an unlit material.
- A combined metallic-roughness image needs two maps of one size. three.js scales them to one size.
- A node that keeps its own matrix writes `matrix`. Every other node writes its translation, its rotation and its scale. three.js writes `matrix` unless you set `trs`.
- An empty geometry is refused by `export_gltf`. glTF does not allow a buffer view of zero bytes.
- An orthographic camera writes half its width as `xmag`, as the specification says. three.js writes twice `right`, and then the camera reads back twice as wide. A box that is not centered on its axis is refused.
- A camera is named after its node. three.js names it after its type, `PerspectiveCamera` or `OrthographicCamera`.
- Cubic spline morph tracks at the same times are merged. three.js refuses them.
- A clip with no channel is left out. three.js writes it with no channels.
- The things that ride one scene node share one glTF node. Thus two lights or two cameras on one node are refused. In three.js each of them is a node of its own.

## Not written

- Ambient, hemisphere and rect area lights, and light probes. glTF has no form for them.
- The decay of a light, the target of a directional or spot light, and the zoom and view offset of a camera.
- Tracks of the visibility, a material, a light or a camera.
- A morph target of colors. glTF allows only positions, normals and tangents.
- Batched meshes and sprites.
- Batched meshes, sprites and wide lines in OBJ, STL and PLY. three.js writes a batched mesh and a `LineSegments2` because each is a mesh there, but it writes their buffers and not their shapes. A batched mesh gives its shared buffer once at the node, with the unused vertices as zeros and no instance moved. A wide line gives the quad that each segment is drawn from. A three.js sprite is not a mesh, and is not written. The meshes on an LOD's levels are written, every level, as three.js writes them.
- The instances of an instanced mesh in OBJ, STL, PLY and USDZ, as in three.js.
- Alpha maps, light maps, specular maps, displacement maps, environment maps, matcaps and gradient maps.
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
- Two lights or two cameras on one node, or a light or a camera on a node that is not in the scene.
- A light of a kind that is not a named one, or one that `Light.validate` refuses.
- An orthographic camera whose box is not centered on its axis.
- A skinned mesh and anything else on one node, or skinned meshes on one node with different skeletons or bind matrices.
- A bone on a node that is not written.
- A skinned geometry without four `skinIndex` and four `skinWeight` values a vertex.
- A skin index that is not a whole number that names a bone.
- An instanced mesh and anything else on one node, or an instanced mesh with no instances.
- Instanced meshes on one node that place or color their instances differently.
- Meshes on one node with different counts of morph targets or different influences.
- Morph normals in a geometry without `normal` and without `morph_relative`.
- A line or points on an indexed geometry.
- A morph track on a mesh that is not there, or on a target that the mesh does not have.
- A node track on a node that is not in the scene, and cubic spline morph tracks that cannot merge.
- A number that is not finite.
- A stale scene, or a node whose world matrix flattens an axis, for OBJ, STL and PLY.
- A mesh, a line or points on a node that is not in the scene, for OBJ, STL and PLY.
- A skinned mesh without `skinIndex` and `skinWeight`, for STL.
- A PLY mesh that is not whole triangles, when the file has faces.
- A `max_texture_size` below one, or a `gltfExtensions` that is not an object when `include_custom_extensions` is on.
- An EXR image with no texels, or data that is not four values a texel.
- An EXR compression other than none, ZIPS or ZIP, or a sample type other than HALF or FLOAT.
- A DEFLATE level that is not from 0 to 9.
- A KTX2 texture that is blank, or a channel count that is not 1, 2 or 4.
- A KTX2 byte texture asked for halves, or a float texture that is `SRGB`.
- A USDZ mesh that names a node that is not in the scene.
- A USDZ geometry with no position, or that is not whole triangles.
- A USDZ texture with a wrap or a channel that is not valid.
- A Draco object kind, encoder method or speed that is not valid.
- A Draco geometry without a vertex, or with an attribute of the wrong item size or count.
- A Draco quantization above 30 bits, or of one bit for normals.
- A Draco value to quantize that is not finite, or an infinite normal.
- A Draco point cloud with an attribute that is not quantized, for the KD-tree.
- A Draco mesh whose triangles all repeat a vertex, for Edgebreaker.

## Example

`tests/test_gltf_exporter.mojo` writes a scene in the three containers and reads each file back with `read_gltf`. `tests/test_model_exporters.mojo` does the same for OBJ, STL and PLY. `tests/test_exr_export.mojo` compares EXR files with the files that three.js 0.180 writes, in `assets/exr_export/three.json`. `tests/test_deflate.mojo` compares zlib and DEFLATE streams with fflate's, in `assets/deflate/fflate.json`, and Huffman code lengths with fflate's, in `assets/deflate/trees.json`.

`tests/test_ktx2_export.mojo` compares KTX2 files with the files that three.js writes, in `assets/ktx2_export/three.json`. `tests/test_usdz.mojo` compares the `.usda` files with the files that three.js writes, in `assets/usdz/three.json`. `tests/test_js_number.mojo` compares the number text with V8's, in `assets/js_number/v8.json`.

`tests/test_draco_export.mojo` compares Draco files with the files that three.js writes, in `assets/draco/export/three.json` and `three.bin`. It checks a representative subset of the 323 cases: each encoder method, both traversals, each KD-tree level and each class of quantization. It reads the files of the smaller geometries back with `decode_draco` and finds each triangle of the geometry in them. To check all 323 cases, run `make draco-export-check`. This target is not part of `make check` or `make coverage`. `assets/draco/export/three_export.mjs` writes the three.js files in Node.

`tests/test_export_options.mojo` compares the OBJ, STL, PLY and USDZ files byte for byte with the files of three.js 0.180. The scene has a mesh, a skinned mesh, an instanced mesh, three lines and points. It also compares the glTF `extras` and `extensions`, and what `read_gltf` and `parse_ply` read. The three.js files are in `assets/exporters/three.json`, and `assets/exporters/three_exporters.mjs` writes them in Node.

`tests/test_gltf_export_scene.mojo` writes a scene with lights, cameras, a morph target, a skin, instances, lines, points and a clip. It compares the JSON with `assets/gltf/three_export.gltf`, which three.js 0.180 wrote for the same scene. It also reads both files and compares the two scenes. `assets/gltf/three_export.mjs` writes the three.js file in Node.
