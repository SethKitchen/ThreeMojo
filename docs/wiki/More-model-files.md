# More model files

These loaders read the less common model formats of three.js's `examples/jsm/loaders/`. Each one has its own module in `loaders/`. [Model files](Model-files) has the common formats: OBJ, STL, PLY, glTF, Collada and FBX.

| Format | Module | Read a file | three.js |
|---|---|---|---|
| [PCD](#pcd) | `loaders/pcd.mojo` | `read_pcd(path) -> PcdModel` | `PCDLoader` |

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
