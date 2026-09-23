# More model files

These loaders read the less common model formats of three.js's `examples/jsm/loaders/`. Each one has its own module in `loaders/`. [Model files](Model-files) has the common formats: OBJ, STL, PLY, glTF, Collada and FBX.

| Format | Module | Read a file | three.js |
|---|---|---|---|
| [PCD](#pcd) | `loaders/pcd.mojo` | `read_pcd(path) -> PcdModel` | `PCDLoader` |
| [3MF](#3mf) | `loaders/three_mf.mojo` | `read_3mf(path, scene, assets) -> ThreeMfModel` | `ThreeMFLoader` |
| [ZIP](#zip) | `loaders/zip.mojo` | `unzip(bytes) -> List[ZipEntry]` | fflate's `unzipSync` |

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
