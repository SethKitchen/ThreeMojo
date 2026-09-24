# More model files

These loaders read the less common model formats of three.js's `examples/jsm/loaders/`. Each one has its own module in `loaders/`. [Model files](Model-files) has the common formats: OBJ, STL, PLY, glTF, Collada and FBX.

| Format | Module | Read a file | three.js |
|---|---|---|---|
| [PCD](#pcd) | `loaders/pcd.mojo` | `read_pcd(path) -> PcdModel` | `PCDLoader` |
| [3MF](#3mf) | `loaders/three_mf.mojo` | `read_3mf(path, scene, assets) -> ThreeMfModel` | `ThreeMFLoader` |
| [ZIP](#zip) | `loaders/zip.mojo` | `unzip(bytes) -> List[ZipEntry]` | fflate's `unzipSync` |
| [SVG](#svg) | `loaders/svg.mojo` | `read_svg(path) -> SvgData` | `SVGLoader` |
| [BVH](#bvh) | `loaders/bvh.mojo` | `read_bvh(path, scene) -> BvhModel` | `BVHLoader` |
| [3DS](#3ds) | `loaders/tds.mojo` | `read_3ds(path, scene, assets) -> TdsModel` | `TDSLoader` |
| [XYZ](#xyz) | `loaders/xyz.mojo` | `read_xyz(path) -> BufferGeometry` | `XYZLoader` |
| [AMF](#amf) | `loaders/amf.mojo` | `read_amf(path, scene, assets) -> AmfModel` | `AMFLoader` |
| [VOX](#vox) | `loaders/vox.mojo` | `read_vox(path) -> List[VoxModel]` | `VOXLoader` |

## PCD

`loaders/pcd.mojo`. `read_pcd(path)` reads a Point Cloud Library file into a `PcdModel`. It reads the three encodings: `ascii`, `binary` and `binary_compressed`. three.js: `PCDLoader`.

```mojo
var cloud = read_pcd("assets/pcd/binary_compressed.pcd")
var shape = assets.geometries.add(cloud.geometry.clone())
```

| Function | What it does |
|---|---|
| `read_pcd(path) -> PcdModel` | Read a file. |
| `parse_pcd(bytes) -> PcdModel` | Read the bytes of one. |
| `parse_pcd_header(bytes) -> PcdHeader` | Read the header only. |
| `decompress_lzf(data, out_length) -> List[UInt8]` | Expand LZF data. |
| `decode_pcd_value(bytes, at, type, size) -> Float64` | Read one little-endian value. |
| `pcd_data_format(name) -> PcdDataFormat` | The format a `DATA` line names. |
| `pcd_field_type(name) -> PcdFieldType` | The type a `TYPE` line names. |

`PcdDataFormat` and `PcdFieldType` are types. A bare integer does not compile. `PcdHeader.check` and `decode_pcd_value` refuse a value that is not valid.

### PcdModel

| Field | What it holds |
|---|---|
| `header` | The `PcdHeader`: the fields, their sizes, types and counts, the width, height, points and viewpoint. |
| `geometry` | A `BufferGeometry` with no index. It has `position`, `normal`, `color` and `intensity` when the file has them. |
| `labels` | One `Int` a point from the `label` field, or an empty list. |

The loader does not make the `Points` object or its material. three.js makes a `PointsMaterial` of size 0.005, with vertex colors when the file has `rgb`.

### What is read

- `x`, `y` and `z` go into `position`.
- `normal_x`, `normal_y` and `normal_z` go into `normal`.
- `rgb` is a packed 32-bit value. Its red, green and blue bytes are divided by 255 and decoded from sRGB, as three.js does.
- `intensity` goes into the `intensity` attribute, one value a point.
- `label` goes into `labels`. A geometry holds `Float32` values, and a `Float32` rounds an integer past 2^24.
- The loader reads past every other field.

In a `binary_compressed` file, the data after the header is two sizes and an LZF stream. The stream expands to one column for each field.

### Differences from three.js

- three.js reads a text row by field position and ignores `COUNT`. This port reads each field after the sum of the counts before it.
- three.js reads a binary `label` as an `Int32`. This port reads it as its declared type.
- three.js reads an 8-byte integer as its low four bytes. This port reads all eight.

### Errors

The loader refuses these, with a message that names the problem:

- A file with no `DATA` line, or a data format that is not known.
- A `SIZE`, `TYPE` or `COUNT` line that does not give one value for each field.
- A type other than `F`, `I` or `U`, or a size that the type does not have. A count below one.
- A `WIDTH`, `HEIGHT` or `POINTS` value that is not a whole number of zero or more.
- Some of `x`, `y` and `z` without the others. The same for the three normals.
- An `rgb` field that is not four bytes.
- A text row with fewer values than its fields, or a value that is not a number.
- A coordinate that is not finite as a `Float32`, or a label that is not a whole number.
- A file that ends early, and LZF data that is not valid or does not fill its declared size.

three.js reads past most of these problems and gives `NaN`, or throws a `RangeError`.

### Example

`assets/pcd/` has one cloud of five points in the three encodings. `tests/test_pcd.mojo` reads each file and compares the values with three.js's `PCDLoader`.

## 3MF

`loaders/three_mf.mojo`. `read_3mf(path, scene, assets)` reads a 3D Manufacturing Format file into a scene and its assets. three.js: `ThreeMFLoader`.

```mojo
var scene = Scene()
var assets = Assets()
var model = read_3mf("assets/3mf/fixture.3mf", scene, assets)
```

| Function | What it does |
|---|---|
| `read_3mf(path, scene, assets) -> ThreeMfModel` | Read a file. |
| `parse_3mf(bytes, scene, assets) -> ThreeMfModel` | Read the bytes of one. |
| `three_mf_unit(name) -> Length` | The length of one unit: `micron`, `millimeter`, `centimeter`, `inch`, `foot` or `meter`. |
| `three_mf_transform(text) -> Matrix4` | The matrix of a `transform` attribute. |
| `three_mf_wrap(style) -> Wrap` | The wrap of a `tilestyleu` attribute. |
| `js_key_order(keys) -> List[String]` | The order in which a JavaScript object walks its keys. |

### ThreeMfModel

| Field | What it holds |
|---|---|
| `root` | The node that three.js returns as its `Group`. Each build item is under it. |
| `unit` | The root model's `unit`, as a `Length`. The loader keeps it and does not apply it, as three.js does. |
| `metadata_names`, `metadata_values` | The metadata that three.js keeps: `Title`, `Designer`, `Description`, `Copyright`, `LicenseTerms`, `Rating`, `CreationDate` and `ModificationDate`. |
| `nodes`, `node_names` | Each node that the loader placed, in order, and its name. |
| `materials`, `material_names` | Each material that the loader made, and its three.js name. |
| `geometries`, `textures` | Each geometry and texture that the loader made. |
| `first_mesh`, `mesh_count` | Where the file's meshes start in `scene.meshes`, and how many there are. |

### What is built

The archive is a ZIP file. `_rels/.rels` names the root model part. `3D/_rels/*.model.rels` names the texture files. A `.model` file in a folder under `3D/` is a sub model.

Each object becomes a node. The triangles of a mesh object are put in groups by their `pid`, or by the object's `pid`. Each group becomes one or more meshes:

- A `basematerials` group gives one mesh for each material index. The material is `STANDARD` when the base material names `pbmetallicdisplayproperties`, and `PHONG` if not. A ninth and tenth hex digit of `displaycolor` give the opacity.
- A `texture2dgroup` gives a mesh with texture coordinates, and a `PHONG` material with the texture as its map.
- A `colorgroup` gives a mesh with a color at each corner, and a `PHONG` material with vertex colors.
- Triangles with no `pid` give the whole mesh, indexed, with a white `PHONG` material named `__DEFAULT`.

All materials use flat shading. A component object puts its components under its own node, each at its `transform`. Each build item puts its object under `root`, at its `transform`. A mesh has its own node under its object's node. Clones share their geometry and material, as three.js clones do.

The loader walks each dictionary in JavaScript key order, as three.js does. Keys that are array indices come first, in numeric order. Thus the meshes come out in three.js's order.

### Differences from three.js

- A texture has one wrap mode. The loader uses `tilestyleu`. three.js also reads `tilestylev`.
- A material has no name in this port. The names are in `material_names`.
- The loader does not read three.js's extensions or implicit functions.
- three.js logs and skips a `pid` that names no resource, a missing root model and a missing texture file. This port refuses them.

### Errors

The loader refuses these, with a message that names the problem:

- An archive that `unzip` refuses. An archive with no `_rels/.rels`, no root model, or no relationship to a model part.
- A part that is not XML, a root element that is not `<model>`, or a unit that is not known.
- An object with no `<mesh>` and no `<components>`. A component that contains itself.
- A number that is not finite, or a transform that does not have twelve numbers.
- A vertex, material, color or texture coordinate index that is out of range.
- A color that three.js's `setStyle` does not read, or an alpha that is not hex.
- A texture file that is not in the archive, or an image that `decode_image` does not read.

### Example

`assets/3mf/fixture.3mf` has base materials, metallic display properties, a color group, a texture group and the default material. Components and build items place them with transforms. `assets/3mf/prefixed.3mf` is the same model with `m:` prefixes. `tests/test_three_mf.mojo` compares both files with three.js's `ThreeMFLoader`.

## ZIP

`loaders/zip.mojo`. `unzip(bytes)` reads the entries of a ZIP archive. `zip_archive(entries, align)` writes entries without compression. three.js uses fflate's `unzipSync` and `zipSync`.

| Function | What it does |
|---|---|
| `unzip(bytes) -> List[ZipEntry]` | Read each entry, in central directory order. |
| `zip_archive(entries, align) -> List[UInt8]` | Write stored entries. Each entry's data starts at a multiple of `align`. |

`ZipMethod` is a type. A bare integer does not compile. `unzip` reads `ZIP_STORED` and `ZIP_DEFLATED` entries, and `zip_archive` writes `ZIP_STORED` entries only.

`unzip` checks each entry's size and CRC-32. fflate does not check them. `unzip` refuses encrypted entries, other compression methods, ZIP64 archives and archives on more than one disk.

## SVG

`loaders/svg.mojo`. `read_svg(path)` reads a Scalable Vector Graphics file into shape paths, one for each element that draws. `loaders/svg_shapes.mojo` turns a shape path into filled shapes and into strokes. three.js: `SVGLoader`, `SVGLoader.createShapes` and `SVGLoader.pointsToStroke`.

```mojo
var data = read_svg("assets/svg/fixture.svg")
for path in data.paths:
    for shape in create_shapes(path):
        var fill = shape_geometry(shape.to_shape())
    for sub in path.sub_paths:
        var stroke = points_to_stroke(sub.get_points(), SvgStrokeStyle(path.style))
```

| Function | What it does |
|---|---|
| `read_svg(path, default_unit, default_dpi) -> SvgData` | Read a file. |
| `parse_svg(text, default_unit, default_dpi) -> SvgData` | Read the text of one. |
| `parse_path_data(d) -> SvgShapePath` | Read the `d` attribute of a `path`. |
| `parse_floats(text, flags, stride) -> List[Float64]` | Read a list of numbers, as three.js's `parseFloats` does. |
| `parse_css_rules(text) -> List[CssRule]` | Read the rules of a `style` element. |
| `create_shapes(path) -> List[SvgShape]` | Sort the outlines into shapes with holes, by the path's `fill-rule`. |
| `points_to_stroke(points, style, arc_divisions, min_distance) -> SvgStroke` | Make the triangles of a stroke. |
| `transform_path(path, matrix)` | Move each curve of a shape path. |

`SvgUnit`, `SvgFillRule`, `SvgLineJoin`, `SvgLineCap` and `PointLocation` are types. A bare integer does not compile. `svg_unit_scale`, `create_shapes_with_rule` and `points_to_stroke` refuse a value that is not valid.

### SvgData and SvgShapePath

`SvgData` has `paths` and `document`, the parsed XML. three.js returns the same two things as `paths` and `xml`.

| `SvgShapePath` field | What it holds |
|---|---|
| `sub_paths` | The outlines. Each `SvgSubPath` has its curves and its `auto_close` flag. |
| `color` | The fill as a linear color. It is white when there is no fill, as in three.js. |
| `style` | The `SvgStyle`: fill, fill opacity, fill rule, opacity, stroke, stroke opacity, stroke width, joins, caps, miter limit and visibility. |
| `node` | The element, as an index into `document`. |

An `SvgCurve` is a line, a quadratic Bezier curve, a cubic Bezier curve or an arc of an ellipse. Its numbers are `Float64`, as in three.js. `SvgSubPath.get_points(divisions)` samples it as three.js's `getPoints` does. `SvgShape.to_shape()` gives a `math.path.Shape` for `shape_geometry`.

### What is read

- The elements `path`, `rect`, `polygon`, `polyline`, `circle`, `ellipse` and `line` draw.
- `svg` and `g` give their style to their children.
- `style` holds CSS rules. A rule applies to an element by its class or its id.
- `defs` hides its children, except `style` and `defs`.
- `use` draws the element that its `xlink:href` names, at its `x` and `y`.
- The `transform` attribute: `translate`, `rotate`, `scale`, `skewX`, `skewY` and `matrix`.
- The loader reads each other element's children with the parent's style.

A style property comes from the parent, then the attribute, then a CSS rule, then the `style` attribute. A length can have the unit `mm`, `cm`, `in`, `pt`, `pc` or `px`. The loader converts it to `default_unit` with `default_dpi` pixels for each inch.

### Units

An SVG coordinate is a user unit, a number with no length. three.js uses it as a world unit, and this port does the same. `to_shape` makes one user unit one meter.

### Differences from three.js

- three.js uses the browser's `DOMParser` and CSS parser. This port uses `loaders/xml.mojo` and a small CSS reader. The CSS reader skips comments and at-rules.
- A `use` element with only one of `x` and `y` uses zero for the other. three.js reads the other as `NaN`.
- Mojo fuses a multiply and an add into one instruction, and JavaScript rounds twice. The results agree to about one part in 10^15. Where two segments of a stroke meet almost in line, a join is badly conditioned, and the stroke can differ.

### Errors

The loader refuses these, with a message that names the problem:

- A file that is not well-formed XML.
- A path that draws before it moves, or a path command that is not known.
- A path command whose numbers do not fill its last step.
- A number that is not a number, or two commas or two signs together.
- A `rect` with no `width` or no `height`, and a `polygon` or `polyline` with no points.
- A `use` that names no element, or that draws itself.
- A transform with no parenthesis.
- A `fill-rule` other than `nonzero` and `evenodd`, in `create_shapes`.
- An outline that the scan line of `create_shapes` does not cross. This happens only with a coordinate that is not a number.

three.js throws for most of these, or continues with `NaN`. A fill that three.js cannot read, such as `url(#gradient)`, keeps the path white, as in three.js.

### Example

`assets/svg/fixture.svg` has each element, each path command, styles from CSS, transforms, `use` and `defs`. `assets/svg/fixture.json` has what three.js 0.180 gives for it: colors, styles, curves, points, shapes and strokes. `assets/svg/strokes.json` has three.js's strokes for each join and cap. `tests/test_svg.mojo` compares all of them.

## BVH

`loaders/bvh.mojo`. `read_bvh(path, scene)` reads a Biovision Hierarchy motion capture file into a skeleton and an animation clip. three.js: `BVHLoader`.

```mojo
var scene = Scene()
var model = read_bvh("assets/bvh/fixture.bvh", scene)
var mixer = AnimationMixer()
var which = mixer.add(AnimationAction(model.clip.value().copy()))
```

| Function | What it does |
|---|---|
| `read_bvh(path, scene, parent, animate_positions, animate_rotations) -> BvhModel` | Read a file. |
| `parse_bvh(text, scene, parent, animate_positions, animate_rotations) -> BvhModel` | Read the text of one. |
| `bvh_channel(name) -> BvhChannel` | The channel that a `CHANNELS` line names. |
| `axis_rotation(channel, degrees) -> Rotation` | A turn about one axis, as a quaternion in `Float64`. |

`BvhChannel` is a type. A bare integer does not compile. `axis_rotation` refuses a channel that is not a rotation.

### BvhModel

| Field | What it holds |
|---|---|
| `joints` | Each joint and end site, in file order: its name, parent, offset, channels and the values of each frame. |
| `nodes` | One scene node for each joint, at its offset under its parent. |
| `skeleton` | The nodes as bones. Each inverse bind is the identity, as in three.js. |
| `frame_count`, `frame_time` | The number of frames, and the `Duration` of one frame. |
| `clip` | The `AnimationClip` named `animation`, or none. |

For each joint, the clip has a `POSITION` track and a `QUATERNION` track. The position is the offset plus the position channels. The rotation is the product of the rotation channels, in file order. An end site has no track. `animate_positions` and `animate_rotations` turn the two kinds of track off, as three.js's `animateBonePositions` and `animateBoneRotations` do.

### Differences from three.js

- The joints are nodes in a scene. three.js returns `Bone` objects that are not in a scene.
- A clip must last longer than no time. A file with fewer than two frames, or a frame time of zero or less, has no clip. A file with both kinds of track turned off has no clip.

### Errors

The loader refuses these, with a message that names the problem:

- A file with no `HIERARCHY` or no `MOTION`.
- A joint with no name, no `{`, no `OFFSET` or no `CHANNELS`. An end site with a joint under it.
- An `OFFSET` that does not have three numbers.
- A `CHANNELS` count that is not the number of names after it, and a channel that is not known.
- A number of frames or a frame time that is not a number.
- A frame with too few values, or a value that is not a number.
- A file that ends early, and joints nested more than 256 deep.

three.js logs most of these problems and continues, or throws a `TypeError`.

### Example

`assets/bvh/fixture.bvh` has a root with six channels, joints with channels in different orders, and end sites. It has three frames and uses CRLF line ends. `assets/bvh/fixture.json` has what three.js 0.180 gives for it. `tests/test_bvh.mojo` compares the bones and each track.

## 3DS

`loaders/tds.mojo`. `read_3ds(path, scene, assets)` reads an Autodesk 3D Studio file into a scene and its assets. three.js: `TDSLoader`.

```mojo
var scene = Scene()
var assets = Assets()
var model = read_3ds("assets/3ds/fixture.3ds", scene, assets)
```

| Function | What it does |
|---|---|
| `read_3ds(path, scene, assets, parent) -> TdsModel` | Read a file. The maps come from the directory of the file. |
| `parse_3ds(bytes, scene, assets, resource_path, parent) -> TdsModel` | Read the bytes of one. The maps come from `resource_path`. |

### TdsModel

| Field | What it holds |
|---|---|
| `root` | The node that three.js returns as its `Group`. The master scale scales it. |
| `nodes`, `names` | One node for each triangle mesh, under `root`, and its name. |
| `geometries` | The geometry of each mesh, with its material groups. |
| `mesh_materials` | The materials of each mesh, as three.js lists them. |
| `materials`, `material_ids` | Each material entry as a `TdsMaterial`, and its `Material` in the assets. |
| `textures` | Each texture that the loader read. |
| `first_mesh`, `mesh_count` | Where the meshes of the file start in `scene.meshes`, and how many there are. |

### What is read

- A material entry becomes a `PHONG` material. The loader reads the name, the diffuse and ambient colors, the specular color, the shininess and the transparency. It also reads two sides, additive blending, the wireframe flag and width, and the color, bump, opacity and specular maps.
- A named object with a triangle mesh becomes a node. The loader reads the points, the texture coordinates, the faces, the material groups and the matrix.
- The matrix places the node. The inverse of the matrix moves the points, as in three.js.
- The loader computes the vertex normals, as three.js does.

three.js reads the bytes of a color over 255 as linear light. The material keeps the sRGB bytes of that light.

A mesh takes the materials that its groups name, in order. It skips a name that no material entry has had before it. Each group starts where the group before it ends, and it has three index entries for each face. three.js makes the same assumption.

### Differences from three.js

- A mesh here draws one material. A mesh with more than one material becomes one mesh for each group that has a material.
- A `Material` draws a wireframe only when it is `BASIC`. The wireframe flag and width stay in `TdsMaterial`, and the material draws the surface.
- three.js loads a map with `TextureLoader`. This port reads the file with `decode_image`, as a linear texture, because three.js does not set the color space. A map whose file is missing has no texture.

### Errors

The loader refuses these, with a message that names the problem:

- A chunk or a value that runs past the end of the file.
- A chunk whose size is less than its six-byte header. three.js reads such a file forever.
- A color or a percentage chunk with no value.
- A map that sets an offset or a scale before its file name, and a map with no file name.
- A mesh with no points, and a face that names a point that is not there.
- A map file that `decode_image` does not read.

### Example

`assets/3ds/fixture.3ds` has two materials with every property and four maps, and four meshes. One mesh has a matrix, and the meshes have material groups in the orders that three.js reads in its own way. `assets/3ds/fixture.json` has what three.js 0.180 gives for it. `tests/test_tds.mojo` compares each node, attribute, group and material.

## XYZ

`loaders/xyz.mojo`. `read_xyz(path)` reads an XYZ point cloud into a geometry. three.js: `XYZLoader`.

```mojo
var cloud = read_xyz("assets/xyz/colored.xyz")
var shape = assets.geometries.add(cloud^)
```

| Function | What it does |
|---|---|
| `read_xyz(path) -> BufferGeometry` | Read a file. |
| `parse_xyz(text) -> BufferGeometry` | Read the text of one. |

Each line is one point: `x y z`, or `x y z r g b` with channels from 0 to 255. A line that starts with `#` is a comment. The geometry has `position`, and `color` when the points have colors. The loader divides each channel by 255 and decodes it from sRGB, as three.js does.

As in three.js, the loader steps over a line that does not have three or six values. It reads a value as `parseFloat` does, so `2m` is 2.

### Errors

The loader refuses these, with a message that names the problem:

- A value that is not a number. three.js keeps `NaN`.
- A file with some points that have colors and some that do not. three.js makes a `color` attribute that is shorter than `position`.

### Example

`assets/xyz/colored.xyz` and `assets/xyz/plain.xyz` have comments, CRLF line ends, tabs and a line of four values. `tests/test_xyz.mojo` compares both with three.js 0.180.

## AMF

`loaders/amf.mojo`. `read_amf(path, scene, assets)` reads an Additive Manufacturing File into a scene and its assets. The file is XML, or a ZIP archive that holds the XML. three.js: `AMFLoader`.

```mojo
var scene = Scene()
var assets = Assets()
var model = read_amf("assets/amf/fixture.amf", scene, assets)
```

| Function | What it does |
|---|---|
| `read_amf(path, scene, assets, parent) -> AmfModel` | Read a file. |
| `parse_amf(bytes, scene, assets, parent) -> AmfModel` | Read the bytes of one. |
| `amf_unit_scale(unit) -> Float64` | The millimeters in one unit: `inch`, `feet`, `meter`, `micron`, or one for any other. |
| `amf_material(color) -> Material` | The flat-shaded `PHONG` material of a color. |

### AmfModel

| Field | What it holds |
|---|---|
| `root`, `name`, `author` | The node that three.js returns as its `Group`, and the `name` and `author` metadata. |
| `scale` | The millimeters in one unit of the file. |
| `objects`, `object_names`, `object_ids` | One node for each object, in the order in which a JavaScript object walks their ids. |
| `geometries`, `materials`, `material_names` | One entry for each mesh, with its geometry, its material and the three.js name of the material. |
| `first_mesh`, `mesh_count` | Where the meshes of the file start in `scene.meshes`, and how many there are. |

### What is built

Each volume of a mesh becomes one mesh on the node of its object. The mesh has the vertices and normals of its `<mesh>` and the triangles of its `<volume>`. The unit scales the vertices. three.js scales the normals too, and makes them unit length again.

The material is flat-shaded `PHONG`. It comes from the volume's `materialid`, or from the object's `<color>`, or it is three.js's default, `0xaaaaff`. three.js reads the text of `<r>`, `<g>` and `<b>` as linear light. The material keeps the sRGB bytes of that light.

three.js compares the text of an `<a>` with the number 1, and the two are never equal. Thus a color with an `<a>` gives a transparent material, whatever the alpha is. This port does the same.

In an archive, the loader reads the first file whose name ends in `.amf`. When there is no such file, it reads the last file, as three.js does.

### Errors

The loader refuses these, with a message that names the problem:

- An archive with no files, a file that is not XML, and a root that is not `<amf>`.
- An object or a material with no `id`.
- A coordinate, a normal or a vertex index that is missing or not a number. An empty value is zero, as in JavaScript.
- A vertex index that is not a whole number, or that is past the last vertex.
- A mesh with normals for only some of its vertices.

three.js logs a root that is not `<amf>` and returns nothing. It throws a `TypeError` for a missing `id` or value, and it reads `NaN` for a value that is not a number.

### Example

`assets/amf/fixture.amf` has metadata, two materials, and three objects whose ids are not in order. It has object colors, normals, a volume with a material that is not there, and an empty volume. `assets/amf/fixture.zip` has the same model in an archive, in microns. `tests/test_amf.mojo` compares both with three.js 0.180.

## VOX

`loaders/vox.mojo`. `read_vox(path)` reads the models of a MagicaVoxel file. `vox_geometry` and `vox_data_3d_texture` turn a model into a mesh or a volume. three.js: `VOXLoader`, `VOXMesh` and `VOXData3DTexture`.

```mojo
var models = read_vox("assets/vox/fixture.vox")
var node = add_vox_mesh(models[0], scene, assets)
var volume = assets.data_3d_textures.add(vox_data_3d_texture(models[0]))
```

| Function | What it does |
|---|---|
| `read_vox(path) -> List[VoxModel]` | Read a file. |
| `parse_vox(bytes) -> List[VoxModel]` | Read the bytes of one. |
| `vox_geometry(model) -> BufferGeometry` | The faces of a model, three.js's `VOXMesh` geometry. |
| `vox_material(model) -> Material` | Its `STANDARD` material, with vertex colors when the model has colors. |
| `add_vox_mesh(model, scene, assets, parent) -> NodeId` | Add a node and a mesh of a model. |
| `vox_data_3d_texture(model) -> Data3DTexture` | The model as a volume, three.js's `VOXData3DTexture`. |

A `VoxModel` has its size in voxels, four bytes for each voxel (x, y, z and a color index), and its palette.

### What is read

`SIZE` starts a model, `XYZI` gives its voxels and `RGBA` gives a palette. The loader steps over the other chunks and reads their children.

A model takes three.js's default palette. An `RGBA` chunk gives its palette to the last model before it, as three.js does.

`vox_geometry` makes two triangles for each face of a voxel that has no voxel next to it. The model is centered, with y up. Each vertex has a color, decoded from sRGB, when a voxel is not black.

`vox_data_3d_texture` has one red byte for each cell: 255 where a voxel is, and zero where there is none.

### Differences from three.js

- three.js filters the volume with nearest filtering when it shrinks, and linear filtering when it grows. A `Data3DTexture` has one filter, and it is `BILINEAR`.

### Errors

The loader refuses these, with a message that names the problem:

- A file that is not `VOX `, or not version 150. three.js logs these and returns nothing.
- A file that ends inside a chunk, and voxels or a palette before any `SIZE`. three.js throws for these.
- A `SIZE` whose content is shorter than its three sizes. three.js reads the file backward from there.
- A voxel outside its model, and a color index past the palette.

### Example

`assets/vox/fixture.vox` has three models, a chunk that the loader skips, and a palette for the last model. One model is all black. `tests/test_vox.mojo` compares each geometry and volume with three.js 0.180.
