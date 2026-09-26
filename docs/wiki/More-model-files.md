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
| [MD2](#md2) | `loaders/md2.mojo` | `read_md2(path) -> Md2Model` | `MD2Loader` |
| [IES](#ies) | `loaders/ies.mojo` | `read_ies(path) -> IesLamp` | `IESLoader` |
| [3DL](#3dl) | `loaders/lut_3dl.mojo` | `read_lut_3dl(path) -> Lut3dl` | `LUT3dlLoader` |
| [LUT image](#lut-image) | `loaders/lut_image.mojo` | `read_lut_image(path) -> LutImage` | `LUTImageLoader` |
| [VRML](#vrml) | `loaders/vrml.mojo` | `read_vrml(path, scene, assets) -> VrmlModel` | `VRMLLoader` |
| [PDB](#pdb) | `loaders/pdb.mojo` | `read_pdb(path) -> PdbModel` | `PDBLoader` |
| [MDD](#mdd) | `loaders/mdd.mojo` | `read_mdd(path) -> MddModel` | `MDDLoader` |
| [G-code](#g-code) | `loaders/gcode.mojo` | `read_gcode(path, scene, assets) -> GCodeModel` | `GCodeLoader` |
| [KMZ](#kmz) | `loaders/kmz.mojo` | `read_kmz(path, scene, assets) -> ColladaModel` | `KMZLoader` |
| [VTK](#vtk) | `loaders/vtk.mojo` | `read_vtk(path) -> BufferGeometry` | `VTKLoader` |
| [NRRD](#nrrd) | `loaders/nrrd.mojo` | `read_nrrd(path) -> Volume` | `NRRDLoader`, and `Volume` |
| [USD](#usd) | `loaders/usd.mojo` | `read_usd(path, scene, assets) -> UsdModel` | `USDLoader` |
| [Draco](#draco) | `loaders/draco.mojo` | `read_draco(path) -> BufferGeometry` | `DRACOLoader`, and `DRACOExporter` in [Exporters](Exporters#draco) |

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

## MD2

`loaders/md2.mojo`. `read_md2(path)` reads a Quake II model into a geometry, its frames and its animations. three.js: `MD2Loader`.

```mojo
var model = read_md2("assets/md2/fixture.md2")
var shape = assets.geometries.add(model.geometry.clone())
var clip = md2_clip(model, 0, MeshIndex(0))
```

| Function | What it does |
|---|---|
| `read_md2(path) -> Md2Model` | Read a file. |
| `parse_md2(bytes) -> Md2Model` | Read the bytes of one. |
| `md2_clip(model, animation, mesh, fps, loop) -> AnimationClip` | One animation as morph target tracks, three.js's `CreateFromMorphTargetSequence`. |
| `md2_animation_name(frame) -> Optional[String]` | The animation that a frame belongs to: its name without the digits at the end. |

### Md2Model

| Field | What it holds |
|---|---|
| `geometry` | One vertex for each corner of each triangle, with no index. It has the position and normal of the first frame, and the texture coordinates. |
| `frames` | Each frame's name, and a position and a normal for each vertex of the geometry. |
| `animations` | Each animation's name and frames. |

Positions and normals turn from z up to y up, as in three.js. Each frame is also a morph target of the geometry, named by the frame. The morph targets are whole, not relative.

three.js puts frames in an animation by their names: `run1` to `run6` are the animation `run`. `md2_clip` makes one track for each frame of an animation, at ten frames each second. A track goes to one at the time of its frame, and to zero at the times of the frames next to it. When `loop` is True, a track whose first key is at zero gets one more key at the end, as three.js does.

### Differences from three.js


- `md2_clip` refuses an animation of one or two frames. three.js makes tracks that have two keys at one time for these.

### Errors

The loader refuses these, with a message that names the problem:

- A file that is not `IDP2` version 8, or whose size is not the end in its header. three.js logs these and returns nothing.
- A file that ends inside a value, and a model with no frames.
- A vertex, texture coordinate or normal index that is past its list.

### Example

`assets/md2/fixture.md2` has eight frames in three animations and one frame that is in no animation. `assets/md2/many.md2` has ten frames. `tests/test_md2.mojo` compares the geometry, the frames and each clip with three.js 0.180.

## IES

`loaders/ies.mojo`. `read_ies(path)` reads an IES light profile (IESNA LM-63) into an `IesLamp`. `ies_texture` makes the texture that three.js makes of it. three.js: `IESLoader`.

```mojo
var lamp = read_ies("assets/ies/full.ies")
var profile = assets.textures.add(ies_texture(lamp))
```

| Function | What it does |
|---|---|
| `read_ies(path) -> IesLamp` | Read a file. |
| `parse_ies(text) -> IesLamp` | Read the text of one. |
| `ies_values(lamp) -> List[Float64]` | The lamp at each whole degree, three.js's `_getIESValues`. |
| `ies_texture(lamp, type) -> Texture` | The values as a red texture: `IES_UNSIGNED_BYTE`, `IES_HALF_FLOAT` (the default) or `IES_FLOAT`. |
| `to_half_float(value) -> UInt16` | The half bits of a value, three.js's `DataUtils.toHalfFloat`. |

`IesType` is a type. A bare integer does not compile. `ies_texture` refuses a type that is not valid.

### What is read

The loader reads the lines up to the one with `TILT`. With `TILT=INCLUDE`, it reads the tilt data. Then it reads the ten lamp values, the three factors, the vertical and horizontal angles, and the candela values. Numbers can go over many lines, with spaces or commas between them.

three.js multiplies each candela value by itself and by the multiplier. Then it divides each value by the largest one, so that the brightest value is one. This port does the same.

`ies_values` gives 360 rows of 180 values. There is one row for each whole horizontal degree, and one value for each whole vertical degree. A profile of one quadrant or one half fills only the rows that its angles reach, as in three.js. The other rows are NaN.

### Differences from three.js

- three.js gives its `DataTexture` a width of 180 and a height of one, but 64800 values. The texture here is 180 wide and 360 high.
- An empty row is zero in each type. three.js has NaN in an empty row of a float texture.

### Errors

The loader refuses these, with a message that names the problem:

- A file with no `TILT` line, and a file that ends early.
- A value that is not a number. three.js reads it as `NaN`. An empty line is zero, as in JavaScript.
- A line with more numbers than its array needs. three.js reads past it until the file ends, and then throws.
- A number of angles that is not a whole number.

### Example

`assets/ies/` has four profiles. They are a quadrant with tilt data, a full circle, one whose horizontal angles go backward, and one with a fractional last angle. `assets/ies/fixture.json` has a digest of three.js 0.180's texture data for each, in each type. `tests/test_ies.mojo` compares them.

## 3DL

`loaders/lut_3dl.mojo`. `read_lut_3dl(path)` reads a `.3dl` color lookup table into a `Lut3dl`. Its texture is a `Data3DTexture` of `size` texels a side. three.js: `LUT3dlLoader`.

```mojo
var table = read_lut_3dl("assets/lut/table.3dl")
var floats = read_lut_3dl("assets/lut/table.3dl", FLOAT_TYPE)
```

| Function | What it does |
|---|---|
| `read_lut_3dl(path, texel_type) -> Lut3dl` | Read a file. |
| `parse_lut_3dl(text, texel_type) -> Lut3dl` | Read the text of one. |
| `lut_3dl_byte(value) -> UInt8` | A number as a `Uint8Array` stores it. |

| Field | What it holds |
|---|---|
| `size` | The number of entries on one side. |
| `grid` | The input values of the grid line. |
| `max_bit_value` | The power of two that divides each number. |
| `texture` | The table: red across, green up and blue deep. It is clamped, bilinear and linear. |

### What is read

The first line of only digits and spaces is the grid. Each line of exactly three numbers is an entry. Blue changes fastest, then green, then red. A grid of three values is an entry too, as in three.js.

The loader finds the largest number. It divides each number by the power of two at or above it. `UNSIGNED_BYTE_TYPE` is the default. It stores each value times 255, cut to a whole number. `FLOAT_TYPE` stores the value. Alpha is one.

Entries past `size` cubed wrap around and write over the first ones, as in three.js. Missing entries are zero.

### Errors

The loader refuses these, with a message that names the problem:

- A texel type that is not valid.
- A file with no grid, and a grid that is not evenly spaced. three.js throws for these too.
- A number that is not one. three.js reads it as `NaN`.
- A table whose largest number is not above zero. three.js divides by zero.

### Example

`assets/lut/table.3dl` is a 10-bit table of size three. `assets/lut/small.3dl` has a grid of three values and one entry past its size. `assets/lut/fixture.json` has three.js 0.180's texture data for each, in each type. `tests/test_lut_3dl.mojo` compares them.

## LUT image

`loaders/lut_image.mojo`. `read_lut_image(path)` reads a color lookup table that is stored as an image into a `LutImage`. three.js: `LUTImageLoader`.

```mojo
var table = read_lut_image("assets/lut/column.png")
```

| Function | What it does |
|---|---|
| `read_lut_image(path) -> LutImage` | Read a PNG, a JPEG or a TGA. |
| `lut_image_from(image) -> LutImage` | Make a table of a decoded image. |
| `parse_lut_image(data, size) -> LutImage` | Make a table of RGBA bytes in a column of squares. |

A table of size `n` is `n` squares of `n` by `n` texels. There is one square for each blue value. Red goes across and green goes down. The squares can be in a column or in a row. The loader turns a row into a column, as three.js does. The texture is clamped, bilinear and linear.

### Differences from three.js

- three.js draws the image on a canvas. This port reads the decoded bytes.
- three.js's `flip` option is not ported.
- A column must be `n` squares high, and a row must be `n` squares wide. three.js makes a texture that its data does not fill for any other shape. This port refuses it.

### Example

`assets/lut/row.png` and `assets/lut/column.png` hold one table of size three, as a row and as a column. `tests/test_lut_3dl.mojo` checks that they give the same texture.

## VRML

`loaders/vrml.mojo`. `read_vrml(path, scene, assets)` reads a VRML 2.0 world (`.wrl`) into the scene and the assets. three.js: `VRMLLoader`.

```mojo
var world = read_vrml("assets/vrml/scene.wrl", scene, assets)
print(world.count(VRML_MESH))
```

| Function | What it does |
|---|---|
| `read_vrml(path, scene, assets, parent) -> VrmlModel` | Read a file. An `ImageTexture` comes from the directory of the file. |
| `parse_vrml(text, scene, assets, resource_path, parent) -> VrmlModel` | Read the text of one. |
| `lex_vrml(text) -> List[VrmlToken]` | Cut the text into tokens, as three.js's chevrotain lexer does. |
| `parse_vrml_tree(tokens) -> VrmlTree` | Read the tokens into a tree of nodes and fields. |
| `vrml_scene(tree, scene, assets, resource_path, parent) -> VrmlModel` | Build a tree into the scene. |
| `earcut(data) -> List[Int]` | Cut a polygon into triangles, three.js's earcut. It is in `geometries/earcut.mojo`. |

| Field | What it holds |
|---|---|
| `root` | The node that three.js returns as its `Scene`. The nodes at the top of the file are under it. |
| `objects` | Each node that the loader made: its kind, its geometry and its material. |
| `geometries`, `materials`, `textures` | The records of each geometry, material and texture, with the values that three.js holds. |
| `has_world_info`, `title`, `info` | The last `WorldInfo` at the top of the file. |
| `tree` | The parsed file. |

`VrmlTokenKind`, `VrmlValueKind` and `VrmlObjectKind` are types. A bare integer does not compile.

### What is built

- `Anchor`, `Group`, `Transform` and `Collision` become groups. A `Transform` gives the translation, the rotation and the scale.
- `Background` becomes a group of a sky sphere and a ground sphere. The colors are blended between their angles.
- `Shape` becomes a mesh, points or lines. Its `Appearance` gives a `PHONG` material, a map from an `ImageTexture` or a `PixelTexture`, and a `TextureTransform`.
- `IndexedFaceSet`, `IndexedLineSet`, `PointSet`, `ElevationGrid`, `Extrusion`, `Box`, `Cone`, `Cylinder` and `Sphere` become geometries.

The loader cuts each face into a fan of triangles. It gives colors and normals to each vertex or to each face, as the file says. When a face set has no normals, the loader finds them from the crease angle. An extrusion's caps are cut by earcut.

The other nodes are read but not built, as in three.js. These are the lights, the sensors, the interpolators and `Text`. A `DEF` name names what the node builds. A `USE` of a group or a shape adds a copy of it. A `USE` of an appearance copies its material.

### Same as three.js

- The values of a field are grouped by kind, so `children [ USE A Shape { } ]` adds the shape first.
- A shape with no appearance is black, in a `BASIC` material named `__DEFAULT`.
- A `texture` field that holds a `USE` is not read.
- A texture transform with no `scale` gives a repeat of zero.
- A `PixelTexture` of one or three components has an alpha of one, not 255.

### Differences from three.js

- three.js builds a geometry with `NaN` in it from a missing number. This port refuses it.
- A field of the wrong kind is refused. So is a `USE` of a name that no `DEF` gives, and a node that uses itself.
- A texture transform with no `rotation` turns by zero.
- An `ImageTexture` is decoded at once, when its file is there.
- A number too big for a double is refused.

### Example

`assets/vrml/` has six worlds. They hold groups and shapes, face sets, line sets and point sets, primitives and grids and extrusions, pixel textures, and empty nodes. Each `.json` file beside them holds what three.js 0.180 builds, in node. `tests/test_vrml.mojo` compares them. `assets/vrml/earcut.json` holds earcut's triangles for `tests/test_earcut.mojo`.

## Draco

`loaders/draco.mojo`. `read_draco(path)` reads a Draco file (`.drc`) into a `BufferGeometry`. three.js: `DRACOLoader`, which runs Draco's own decoder, compiled to WebAssembly. The port is that decoder, from Draco 1.5.6, the version that three.js 0.180 ships. Four modules hold its parts: `draco_buffer.mojo`, `draco_mesh.mojo`, `draco_attributes.mojo` and `draco_kd_tree.mojo`.

```mojo
var geometry = read_draco("assets/draco/sphere.drc")
print(geometry.attribute_view(String(POSITION)).count())
```

| Function | What it does |
|---|---|
| `read_draco(path) -> BufferGeometry` | Read a file. |
| `parse_draco(bytes) -> BufferGeometry` | Read the bytes of one, as `DRACOLoader.parse` does. |
| `decode_draco(bytes) -> DracoGeometry` | Decode the bytes as Draco's decoder does. |
| `draco_buffer_geometry(geometry, names, attributes, srgb_colors) -> BufferGeometry` | Build a geometry from decoded data. |

| `DracoGeometry` | What it holds |
|---|---|
| `geometry_type` | `DRACO_POINT_CLOUD` or `DRACO_TRIANGULAR_MESH`. |
| `points` | The points. |
| `faces` | Three points for each triangle. A point cloud has none. |
| `attributes` | Each `DracoAttribute`: its type, its data type, its components, `normalized`, its unique id, its values and the value of each point. |
| `named_attribute(type)`, `unique_attribute(id)` | The first attribute of a type, or the attribute with a unique id. |
| `float32_values(index)`, `integer_values(index, type)` | An attribute's values for every point, as `Float32` or at an integer type. |

`DracoGeometryType`, `DracoEncoding`, `DracoAttributeCoding`, `DracoElement`, `DracoDataType`, `DracoAttributeType`, `DracoPrediction`, `DracoTransform`, `DracoTraversal` and `DracoTraversalMethod` are types. A bare integer does not compile.

### What is read

- A mesh of bitstream 2.2, sequential or Edgebreaker. The Edgebreaker symbols can use the standard or the valence traversal.
- A point cloud of bitstream 2.3, sequential or a KD-tree, at every compression level.
- Attributes of the raw, integer, quantized and octahedral normal codings.
- The difference, parallelogram, multi-parallelogram, constrained multi-parallelogram, texture coordinate and geometric normal predictions, with the wrap and both octahedron transforms.
- Metadata. The decoder reads past it, as three.js does not use it.

### What is built

`parse_draco` builds the geometry that `DRACOLoader.parse` builds:

- The first `POSITION`, `NORMAL`, `COLOR` and `TEX_COORD` attributes become `position`, `normal`, `color` and `uv`.
- Each value is a `Float32`. An integer is cast. It is divided by the largest value of its type when the attribute is normalized.
- The colors are sRGB in the file. They are made linear, as three.js makes them.
- A mesh has an index of three points for each triangle.

A glTF file can hold Draco data. See [Draco primitives](Model-files#draco-primitives).

### Writing a Draco file

`exporters/draco.mojo` writes a Draco file, as three.js's `DRACOExporter` writes it. The port is Draco 1.5.6's encoder, and its files have the same bytes as three.js's files. `read_draco` reads them back. See [Draco](Exporters#draco) in the exporters.

```mojo
write_draco("out/model.drc", geometry)
var geometry = read_draco("out/model.drc")
```

### Same as three.js

- Each value is the same `Float32` that three.js's decoder gives. The floats of dequantization and of the normals are computed in `Float32`, in Draco's order.
- A prediction that Draco 1.5.6 does not know is read as a difference.
- A sequential mesh with more points than three for each triangle is refused.

### Differences from three.js

- Draco reads bitstreams back to 1.0. This port reads 2.2 and 2.3 only. Draco has written these since 2017.
- A triangle of a sequential mesh that names a point that the mesh does not have is refused. three.js keeps an index past the end of the attributes.
- A color of one or two components is refused. three.js reads past the end of each item.
- The deprecated texture coordinate prediction and a geometric normal prediction with the wrap transform are refused. Draco decodes them.

### Errors

The decoder raises for a file that does not start with `DRACO`, and for another bitstream version. It raises for an encoding, attribute coding, transform or traversal that is not known. It raises everywhere Draco's decoder fails, with the reason as the message.

### Example

`assets/draco/` has 60 files. The Draco 1.5.7 encoder wrote most of them. They hold meshes at several speeds, with seams, holes, handles, the valence traversal and metadata. They hold point clouds of every type too. Some were changed by one byte to reach a path that the encoder does not write. Some were written by hand: empty geometry and bad counts.

`three.json` and `three.bin` hold what three.js 0.180's decoder gives for each file, in node. `tests/test_draco.mojo` compares each value by its bits.

`assets/draco/export/` holds the files that three.js's `DRACOExporter` writes for 14 geometries, with many options. `tests/test_draco_export.mojo` compares the files that `export_draco` writes with them, byte for byte. It also reads each file back with this decoder.

## PDB

`loaders/pdb.mojo`. `read_pdb(path)` reads a Protein Data Bank file into its atoms and bonds. three.js: `PDBLoader`.

```mojo
var molecule = read_pdb("assets/pdb/fixture.pdb")
var atoms = assets.geometries.add(molecule.atoms_geometry.clone())
var bonds = assets.geometries.add(molecule.bonds_geometry.clone())
```

| Function | What it does |
|---|---|
| `read_pdb(path) -> PdbModel` | Read a file. |
| `parse_pdb(text) -> PdbModel` | Read the text of one. |
| `cpk_color(element) -> Tuple[Int, Int, Int]` | The CPK color of an element, in sRGB bytes, or -1 in each channel. |

### PdbModel

| Field | What it holds |
|---|---|
| `atoms_geometry` | The atoms as points: `position`, and `color` in linear light. |
| `bonds_geometry` | The bonds as line segments: `position`, two points for each bond. |
| `atoms` | Each atom's position, its CPK color in sRGB bytes, and its element with a capital letter first. |

### What is read

An `ATOM` or `HETATM` line gives an atom. The loader reads the columns that three.js reads. The element is in columns 77 and 78, or in columns 13 and 14 when those are blank. A `CONECT` line bonds an atom to up to four others.

The loader keeps each bond once. It steps over a bond to atom zero, as three.js does. It steps over the other lines.

### Errors

The loader refuses these, with a message that names the problem. three.js throws on both when it builds the geometry.

- An element that has no CPK color.
- A bond to an atom that no line gives.

### Example

`assets/pdb/fixture.pdb` has atoms, hetero atoms, bonds that repeat, and an element in the name columns. `tests/test_pdb.mojo` compares the geometries and the atoms with three.js 0.180.

## MDD

`loaders/mdd.mojo`. `read_mdd(path)` reads a point cache into morph targets and their times. `mdd_clip` makes the clip that plays them. three.js: `MDDLoader`.

```mojo
var cache = read_mdd("assets/mdd/fixture.mdd")
for i in range(len(cache.morph_targets)):
    geometry.add_morph_target(cache.morph_targets[i].copy(), name=cache.names[i])
geometry.morph_relative = False
var clip = mdd_clip(cache, MeshIndex(0))
```

| Function | What it does |
|---|---|
| `read_mdd(path) -> MddModel` | Read a file. |
| `parse_mdd(bytes) -> MddModel` | Read the bytes of one. |
| `mdd_clip(model, mesh) -> AnimationClip` | The clip `default`, which shows each frame at its time. |

### MddModel

| Field | What it holds |
|---|---|
| `times` | The time of each frame, in seconds. |
| `morph_targets` | The positions of each frame, three numbers for each point. |
| `names` | The name of each target: `morph_0`, `morph_1` and on. |

A target holds each point's position, not how far the point moves. So clear `morph_relative` on the geometry.

### Differences from three.js

- three.js makes one track that holds every influence. `mdd_clip` makes one track for each target. The weights are the same: a target is at one at its frame's time and at zero at the other times.
- `mdd_clip` refuses a file with no frames. It also refuses times that are negative, that do not rise, or that end at zero. three.js makes a clip of these, but the clip has no length or plays its keys out of order.

### Errors

The loader refuses a file that ends inside a value. three.js's `DataView` throws on this. The loader steps over bytes after the last frame, as three.js does.

### Example

`assets/mdd/fixture.mdd` has three frames of four points. `tests/test_mdd.mojo` compares the targets and the clip with three.js 0.180.

## G-code

`loaders/gcode.mojo`. `read_gcode(path, scene, assets)` reads the moves of a 3D printer file and adds them to the scene as line segments. three.js: `GCodeLoader`.

```mojo
var toolpath = read_gcode("assets/gcode/fixture.gcode", scene, assets)
var layers = len(toolpath.layers)
```

| Function | What it does |
|---|---|
| `read_gcode(path, scene, assets, split_layer, parent) -> GCodeModel` | Read a file into the scene. |
| `parse_gcode(text, scene, assets, split_layer, parent) -> GCodeModel` | Read the text of one into the scene. |
| `gcode_layers(text) -> List[GCodeLayer]` | Read the moves into layers, and add nothing. |
| `gcode_scene(layers, scene, assets, split_layer, parent) -> GCodeModel` | Add layers to the scene. |

### What is read

| Command | What it does |
|---|---|
| `G0`, `G1` | Move to the `X`, `Y` and `Z` it gives. A move that raises `E` extrudes. |
| `G90`, `G91` | Set absolute or relative positions. |
| `G92` | Set the position without a move. |

The loader steps over other commands, and over `G2` and `G3` arcs, as three.js does. A `;` and the text after it on its line is a comment. A move that extrudes at a new height starts a layer.

### What is built

The root node is named `gcode`. It turns a quarter turn back about x, so that z is up. Under it are line segments named `layer` and a number. There is one pair for each layer when `split_layer` is True. There is one pair for the whole file when it is False, the default.

The extruded lines are green. The travel lines are red.

### Same as three.js

The loader keeps these three.js behaviors:

- The loader compares a command with its letters made capital, but it keeps a carriage return. So `G90` at the end of a CRLF line does nothing.
- Each move starts a new state. So `G91` holds for the next move only.
- A comment needs a character after its `;`. A lone `;` stays in its word.
- A letter with no number gives NaN.

### Example

`assets/gcode/fixture.gcode` has comments, relative moves, a reset of `E`, an arc and three layers. `tests/test_gcode.mojo` compares both kinds of group with three.js 0.180.

## KMZ

`loaders/kmz.mojo`. `read_kmz(path, scene, assets)` reads a zipped KML model into a scene. The model is a Collada file in the archive. three.js: `KMZLoader`.

```mojo
var model = read_kmz("assets/kmz/model.kmz", scene, assets)
```

| Function | What it does |
|---|---|
| `read_kmz(path, scene, assets) -> ColladaModel` | Read a file. An image that is not in the archive is read from the file's folder. |
| `parse_kmz(bytes, scene, assets, directory) -> ColladaModel` | Read the bytes of one. |
| `kml_model_path(kml) -> Optional[String]` | The model a `doc.kml` names. |

### What is read

When the archive has a `doc.kml`, the model is the file that its first `href` in a `Link`, in a `Model`, in a `Placemark` names. With no `doc.kml`, the model is the first file with the extension `dae`, in upper or lower case. `load_collada` reads the model. An image is the first file in the archive whose name ends with the image's path.

A `doc.kml` that names no model gives an empty node, as three.js gives an empty `Group`. So does an archive with no `doc.kml` and no `.dae` file.

### Errors

The loader refuses these, with a message that names the problem:

- A `doc.kml` that names a file that is not in the archive. three.js throws on this.
- A `doc.kml` or a model that is not UTF-8 or not XML.
- A ZIP or a Collada file that `unzip` or `load_collada` refuses.

### Example

`assets/kmz/model.kmz` holds a `doc.kml`, the model `models/tri.dae` and the texture `images/brick.png`. `tests/test_kmz.mojo` compares it with the same model read from the disk.

## VTK

`loaders/vtk.mojo`. `read_vtk(path)` reads VTK poly data into a geometry. It reads legacy text, legacy binary and XML files. three.js: `VTKLoader`.

```mojo
var shape = assets.geometries.add(read_vtk("assets/vtk/ascii.vtk"))
```

| Function | What it does |
|---|---|
| `read_vtk(path) -> BufferGeometry` | Read a file. |
| `parse_vtk(bytes) -> BufferGeometry` | Read the bytes of one, and choose its kind as three.js does. |
| `parse_vtk_ascii(text) -> BufferGeometry` | Read a legacy text file. |
| `parse_vtk_binary(bytes) -> BufferGeometry` | Read a legacy binary file. |
| `parse_vtk_xml(text) -> BufferGeometry` | Read an XML poly data file. |

### What is read

The loader looks at the first 250 bytes, as three.js does. A first line that holds `xml` is an XML file. A third line that holds `ASCII` is a legacy text file. Any other file is a legacy binary file.

- **Legacy text.** `POINTS`, `POLYGONS`, `TRIANGLE_STRIPS`, and `NORMALS` and `COLOR_SCALARS` in `POINT_DATA` or `CELL_DATA`. Each section of cells adds to the index.
- **Legacy binary.** Big-endian `POINTS`, `POLYGONS` and `TRIANGLE_STRIPS`, and the normals after `POINT_DATA`. Each section of cells replaces the index.
- **XML.** The first `Piece` of a `PolyData`: its `Points`, the normals that `PointData` names, `Strips` and `Polys`. A data array can be text, base64, base64 zlib blocks or appended base64.

The geometry has an index, `position`, and `normal` when there is one normal for each point. A legacy text file can also give `color`.

### Same as three.js

The loader keeps these three.js behaviors:

- A colors section with one color for each index entry is a set of cell colors. The geometry loses its index, and each color is decoded from sRGB two times.
- The text patterns share one `lastIndex`, as three.js's global pattern does. So a line that starts with a word changes where the next line is read from.
- An index entry that is not a number is point zero.
- An empty index gives an empty draw range, so the geometry draws nothing.
- In XML, `Polys` replaces the index of `Strips`. Each strip reads the connectivity from its start.
- An `Int64` array keeps the low half of each value.

### Errors

The loader refuses these, with a message that names the problem. three.js throws on most of them.

- A file that is shorter than 250 bytes, or whose third line is past them.
- A `DATASET` that is not `POLYDATA`.
- A value past the end of the file, base64 that is not a multiple of four characters, and zlib data that is not zlib.
- An XML file with no cells or no points, or a part that three.js reads but the file does not have.
- A binary line with no end, and a count that is not a number. three.js reads these for ever.
- An index past the points. three.js keeps it and draws from undefined positions.
- A text or XML file that is not UTF-8.

### Example

`assets/vtk/` holds each kind and each XML encoding, and files of the quirks above. `tests/test_vtk.mojo` compares each one with three.js 0.180.

## NRRD

`loaders/nrrd.mojo`. `read_nrrd(path)` reads an NRRD volume into a `Volume`. three.js: `NRRDLoader`. The `Volume` is in `objects/volume.mojo`. three.js: `Volume`.

```mojo
var volume = read_nrrd("assets/nrrd/raw.nrrd")
var value = volume.get_data(1, 0, 1)
```

| Function | What it does |
|---|---|
| `read_nrrd(path) -> Volume` | Read a file. |
| `parse_nrrd(bytes) -> Volume` | Read the bytes of one. |
| `parse_nrrd_header(text) -> NrrdHeader` | Read a header only. |
| `gunzip(bytes) -> List[UInt8]` | Expand gzip data, as fflate's `gunzipSync` does. |

### Volume

| Field or method | What it holds or does |
|---|---|
| `data` | One value for each voxel, x fastest. |
| `x_length`, `y_length`, `z_length`, `dimensions` | The lengths of the grid. |
| `spacing`, `axis_order` | The distance between voxels, and the axis that each index runs along. |
| `matrix`, `inverse_matrix` | From voxel indices to RAS space, and back. |
| `ras_dimensions` | The lengths times the spacings. |
| `min`, `max`, `window_low`, `window_high`, `lower_threshold`, `upper_threshold` | The range of the values. |
| `get_data(i, j, k)`, `access(i, j, k)`, `reverse_access(index)` | Read a voxel, and change between indices and places in `data`. |
| `Volume(x, y, z, type, bytes)` | Make a volume from a buffer, as three.js's constructor does. |

### What is read

The loader reads the header fields that three.js reads, and keeps the others in `field_names` and `field_values`. It reads `raw`, `gzip`, and the text encodings `ascii`, `text`, `txt` and `hex`. With no `space directions`, the directions are the axes, scaled by `spacings`.

### Same as three.js

The loader keeps these three.js behaviors:

- three.js cuts the header one character short. So the last line before the blank line loses its last character. `encoding: raw` on that line reads as `ra`.
- An encoding that three.js does not know reads the whole file, with the header, as the data.
- The `endian` field is read but not applied. The data is little-endian.
- gzip data is cut or filled with zeros to the length in its trailer.

### Errors

The loader refuses these, with a message that names the problem. three.js throws on all of them.

- A file with no blank line after the header, or that is not NRRD.
- A `bz2` or `bzip2` encoding, a type that three.js does not know, and no type or no encoding.
- A `space origin` with no `(`, and `space directions` with no `( )` or fewer than three.
- gzip data that is not gzip, and data that is not whole values of its type.

### Differences from three.js

- The port does not have `extractSlice`, `repaintAllSlices` or `VolumeSlice`. They draw on a canvas, which this port does not have.

### Example

`assets/nrrd/` holds raw, gzip, text and hexadecimal volumes, and a file whose data is the whole file. `tests/test_nrrd.mojo` compares each one with three.js 0.180.

## USD

`loaders/usd.mojo`. `read_usd(path, scene, assets)` reads a USDZ archive into a scene. `read_usda` reads USDA text. three.js: `USDLoader`.

```mojo
var model = read_usd("assets/usd/scene.usdz", scene, assets)
```

| Function | What it does |
|---|---|
| `read_usd(path, scene, assets) -> UsdModel` | Read a file as bytes, as three.js's `load` does. |
| `read_usda(path, scene, assets) -> UsdModel` | Read a file as USDA text. |
| `parse_usd(bytes, scene, assets) -> UsdModel` | Read the bytes of a USDZ archive or a USDC crate. |
| `parse_usda(text, scene, assets) -> UsdModel` | Read USDA text. |
| `usda_tree(text) -> UsdaTree` | Read USDA text into three.js's tree of names and values. |

### UsdModel

| Field | What it holds |
|---|---|
| `root` | The node that three.js's `Group` becomes. |
| `objects` | Each node that was added, a mesh or a node with nothing to draw, in the order added. |
| `textures` | Each texture that a material read. |
| `missing_textures` | The file of each map whose image is not in the archive. |

### What is built

Each `def Xform` is a node under the `def Xform` or `def Scope` that holds it. Its name is its quoted word. It is a mesh when a `def Mesh` is in it, or in the layer that its `prepend references` names. The mesh has `position`, `normal` and `uv`, and no index. Its material is a physical material from a `UsdPreviewSurface`, with the maps that three.js reads. A `matrix4d xformOp:transform` places the node.

A USDC crate gives an empty node, as three.js's crate reader does.

### Same as three.js

The loader keeps these three.js behaviors:

- A node takes the first `def Mesh` that is in it. So a parent shows the mesh of its first child too.
- `material:binding` finds a material by the second part of its path.
- The corners of a face start at its index times its count of corners.
- A corner past the list is NaN.
- A map whose image is not in the archive is one black texel. three.js keeps a texture with no image, which draws black.
- A texture's rotation is in radians.
- `read_usd` refuses a `.usda` file, because three.js's `load` reads it as a ZIP.

### Errors

The loader refuses these, with a message that names the problem:

- A value that is not JSON, and a line that writes into a string or into nothing. three.js throws on these.
- A reference with no `@`, a texture input that names no shader, and a shader with no file. three.js throws on these too.
- An array value that is not an array, a color outside zero to one, and a wrap that three.js does not know.
- Points that are not three numbers each, a transform that is not sixteen finite numbers, and text that is not UTF-8.

### Example

`assets/usd/cube.usda` has meshes of quads and triangles, normals, texture coordinates and a material. `assets/usd/scene.usdz` references a mesh in another layer, and has a textured material. `tests/test_usd.mojo` compares both with three.js 0.180.
