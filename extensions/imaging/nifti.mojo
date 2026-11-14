# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read and write NIfTI-1 volumes, as research imaging tools exchange them.

A NIfTI-1 file is a header of 348 bytes, four bytes of extension flags,
and the voxels from `vox_offset`. The reader takes a single `.nii` file
in either byte order, and a `.nii` file inside gzip. It takes unsigned
and signed integers of 8, 16 and 32 bits, and floats of 32 and 64 bits.
It reads the first volume of a file with more than three dimensions.

The values are `scl_slope * stored + scl_inter`. A slope of zero means
no scaling, as the standard says.

The placement comes from the first of these that the file sets: the
sform rows, the qform quaternion, or the voxel sizes alone. NIfTI's world
coordinates are RAS: x to the right, y to the front, z up. The volume
keeps DICOM's LPS patient space, so x and y change sign.

`encode_nifti` writes a volume as 32-bit floats, and `encode_nifti_labels`
writes a label map as unsigned bytes with the label intent. Both write
the placement as sform rows, in millimeters.
"""

from extensions.imaging.ids import LabelId, require_label
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.sdf.vector import V3, dot, length, v3
from loaders.bytes import bytes_match
from loaders.nrrd import gunzip
from render.checksum import crc32
from render.deflate import deflate
from std.math import floor, isfinite, max, sqrt
from std.memory import bitcast
from std.pathlib import Path
from units.si import Length64, METER

comptime HEADER_SIZE = 348
comptime DATA_OFFSET = 352
# The largest file the gzip reader expands, 2^31 bytes.
comptime MAX_NIFTI_BYTES = 2147483648
# The intent code of a label map.
comptime LABEL_INTENT = 1002
# Two axes are square when the cosine between them is below this.
comptime SQUARE_TOLERANCE = 1.0e-3


def _u16(bytes: Span[UInt8, _], at: Int, big: Bool) -> Int:
    """Read an unsigned 16-bit value."""
    if big:
        return (Int(bytes[at]) << 8) | Int(bytes[at + 1])
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


def _i16(bytes: Span[UInt8, _], at: Int, big: Bool) -> Int:
    """Read a signed 16-bit value."""
    var value = _u16(bytes, at, big)
    if value >= 32768:
        return value - 65536
    return value


def _u32(bytes: Span[UInt8, _], at: Int, big: Bool) -> Int:
    """Read an unsigned 32-bit value."""
    if big:
        return (_u16(bytes, at, True) << 16) | _u16(bytes, at + 2, True)
    return _u16(bytes, at, False) | (_u16(bytes, at + 2, False) << 16)


def _f32(bytes: Span[UInt8, _], at: Int, big: Bool) -> Float64:
    """Read a 32-bit float."""
    return Float64(bitcast[DType.float32](UInt32(_u32(bytes, at, big))))


def _value(
    bytes: Span[UInt8, _], at: Int, size: Int, kind: Int, big: Bool
) -> Float64:
    """Read one stored value: kind 0 unsigned, 1 signed, 2 float."""
    var bits: UInt64 = 0
    for k in range(size):  # pragma: no branch
        var byte = bytes[at + size - 1 - k] if big else bytes[at + k]
        bits |= UInt64(byte) << UInt64(8 * k)
    if kind == 2:
        if size == 4:
            return Float64(bitcast[DType.float32](UInt32(bits)))
        return bitcast[DType.float64](bits)
    if kind == 1 and bits >= (UInt64(1) << UInt64(8 * size - 1)):
        return Float64(Int(bits) - (1 << (8 * size)))
    return Float64(Int(bits))


def _datatype(code: Int) raises -> Tuple[Int, Int]:
    """Return the byte size and the kind of a NIfTI datatype."""
    if code == 2:
        return (1, 0)
    if code == 256:
        return (1, 1)
    if code == 512:
        return (2, 0)
    if code == 4:
        return (2, 1)
    if code == 768:
        return (4, 0)
    if code == 8:
        return (4, 1)
    if code == 16:
        return (4, 2)
    if code == 64:
        return (8, 2)
    raise Error("The NIfTI datatype " + String(code) + " is not supported")


def _unit_millimeters(units: Int) raises -> Float64:
    """Return the millimeters of one spatial unit of `xyzt_units`."""
    var spatial = units & 7
    if spatial == 1:
        return 1000.0
    if spatial == 3:
        return 0.001
    if spatial > 3:
        raise Error(
            "The NIfTI spatial unit is not meters, millimeters or microns"
        )
    return 1.0


def _quaternion_columns(
    b: Float64, c: Float64, d: Float64
) -> Tuple[V3, V3, V3]:
    """Return the columns of the rotation of a NIfTI quaternion."""
    var a = sqrt(max(1.0 - b * b - c * c - d * d, 0.0))
    return (
        v3(
            a * a + b * b - c * c - d * d,
            2 * (b * c + a * d),
            2 * (b * d - a * c),
        ),
        v3(
            2 * (b * c - a * d),
            a * a + c * c - b * b - d * d,
            2 * (c * d + a * b),
        ),
        v3(
            2 * (b * d + a * c),
            2 * (c * d - a * b),
            a * a + d * d - c * c - b * b,
        ),
    )


def _lps(p: V3) -> V3:
    """Return a RAS point as an LPS point, or the reverse."""
    return v3(-p.x, -p.y, p.z)


def _gzipped(bytes: Span[UInt8, _]) -> Bool:
    """Return whether bytes start with the gzip magic, 1F 8B."""
    if len(bytes) < 2:
        return False
    return Int(bytes[0]) * 256 + Int(bytes[1]) == 0x1F8B


def parse_nifti(bytes: Span[UInt8, _]) raises -> ImageVolume:
    """Read the first volume of a NIfTI-1 file.

    Args:
        bytes: The whole `.nii` file, or the file inside gzip.

    Returns:
        The volume, in LPS patient space. Its window comes from `cal_min`
        and `cal_max` when they make a range, and from its values when
        they do not.

    Raises:
        Error: If the file is not single-file NIfTI-1, its datatype or
            spatial unit is not supported, a size or a voxel size is not
            positive, its axes are sheared, or it is shorter than its data.
    """
    var data: List[UInt8]
    if _gzipped(bytes):
        data = gunzip(bytes, MAX_NIFTI_BYTES)
    else:
        data = List[UInt8](bytes)
    if len(data) < HEADER_SIZE:
        raise Error("A NIfTI file has a header of 348 bytes")
    var big: Bool
    if _u32(data, 0, False) == HEADER_SIZE:
        big = False
    elif _u32(data, 0, True) == HEADER_SIZE:
        big = True
    elif _u32(data, 0, False) == 540:
        raise Error("NIfTI-2 files are not supported")
    else:
        raise Error("The file is not NIfTI-1")
    if bytes_match(data, 344, len(data), "ni1"):
        raise Error("A NIfTI header and image pair is not supported")
    if not bytes_match(data, 344, len(data), "n+1"):
        raise Error("A NIfTI-1 file has the magic n+1")
    var dims = _i16(data, 40, big)
    if dims < 1 or dims > 7:
        raise Error("A NIfTI file has from 1 to 7 dimensions")
    var sizes = List[Int]()
    for axis in range(1, 4):
        sizes.append(_i16(data, 40 + 2 * axis, big) if axis <= dims else 1)
    var layout = _datatype(_i16(data, 70, big))
    var size = layout[0]
    var pixdim = List[Float64]()
    for axis in range(4):
        pixdim.append(_f32(data, 76 + 4 * axis, big))
    var offset = Int(_f32(data, 108, big))
    var slope = _f32(data, 112, big)
    var intercept = _f32(data, 116, big)
    if slope == 0 or not isfinite(slope) or not isfinite(intercept):
        slope = 1.0
        intercept = 0.0
    var unit = _unit_millimeters(Int(data[123]))
    var columns = (
        v3(pixdim[1], 0, 0),
        v3(0, pixdim[2], 0),
        v3(0, 0, pixdim[3]),
    )
    var origin = v3(0, 0, 0)
    if _i16(data, 254, big) > 0:
        var rows = List[Float64]()
        for k in range(12):
            rows.append(_f32(data, 280 + 4 * k, big))
        columns = (
            v3(rows[0], rows[4], rows[8]),
            v3(rows[1], rows[5], rows[9]),
            v3(rows[2], rows[6], rows[10]),
        )
        origin = v3(rows[3], rows[7], rows[11])
    elif _i16(data, 252, big) > 0:
        var turn = _quaternion_columns(
            _f32(data, 256, big), _f32(data, 260, big), _f32(data, 264, big)
        )
        var flip = -1.0 if pixdim[0] < 0 else 1.0
        columns = (
            turn[0] * pixdim[1],
            turn[1] * pixdim[2],
            turn[2] * (pixdim[3] * flip),
        )
        origin = v3(
            _f32(data, 268, big), _f32(data, 272, big), _f32(data, 276, big)
        )
    var mm = Length64(unit, MILLIMETER64).to(METER)
    var volume = ImageVolume(
        sizes[0],
        sizes[1],
        sizes[2],
        Length64(length(columns[0]) * mm, METER),
        Length64(length(columns[1]) * mm, METER),
        Length64(length(columns[2]) * mm, METER),
    )
    volume.axis_x = _lps(columns[0] * (1.0 / length(columns[0])))
    volume.axis_y = _lps(columns[1] * (1.0 / length(columns[1])))
    volume.axis_z = _lps(columns[2] * (1.0 / length(columns[2])))
    volume.origin = _lps(origin * mm)
    var square = max(
        abs(dot(volume.axis_x, volume.axis_y)),
        max(
            abs(dot(volume.axis_x, volume.axis_z)),
            abs(dot(volume.axis_y, volume.axis_z)),
        ),
    )
    if square > SQUARE_TOLERANCE:
        raise Error("NIfTI axes that are not square are not supported")
    var count = volume.count()
    if offset < DATA_OFFSET or len(data) < offset + count * size:
        raise Error("The NIfTI file is shorter than its data")
    for index in range(count):  # pragma: no branch
        var stored = _value(data, offset + index * size, size, layout[1], big)
        volume.values[index] = Float32(slope * stored + intercept)
    var low = _f32(data, 128, big)
    var high = _f32(data, 124, big)
    if high > low:
        volume.window_center = (low + high) / 2
        volume.window_width = high - low
    else:
        volume.fit_window()
    return volume^


def read_nifti(path: String) raises -> ImageVolume:
    """Read the first volume of a NIfTI-1 file.

    Args:
        path: The `.nii` or `.nii.gz` file.

    Returns:
        The volume.

    Raises:
        Error: If the file cannot be read, or `parse_nifti` refuses it.
    """
    var bytes = Path(path).read_bytes()
    return parse_nifti(bytes)


def labels_from_volume(volume: ImageVolume) raises -> LabelMap:
    """Return the label map whose labels are a volume's values.

    Use it to read a segmentation from a NIfTI file.

    Args:
        volume: A volume of whole values from 0 to 255.

    Returns:
        The label map, on the volume's grid.

    Raises:
        Error: If a value is not a whole number from 0 to 255.
    """
    var map = LabelMap(volume)
    for index in range(volume.count()):  # pragma: no branch
        var value = volume.values[index]
        var label = Int(value)
        if Float32(label) != value:
            raise Error("A label must be a whole number")
        require_label(LabelId(label))
        map.labels[index] = UInt8(label)
    return map^


def _push16(mut out: List[UInt8], value: Int):
    """Append a little-endian 16-bit value."""
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))


def _push32(mut out: List[UInt8], value: Int):
    """Append a little-endian 32-bit value."""
    _push16(out, value & 0xFFFF)
    _push16(out, (value >> 16) & 0xFFFF)


def _push_float(mut out: List[UInt8], value: Float64):
    """Append a little-endian 32-bit float."""
    _push32(out, Int(bitcast[DType.uint32](Float32(value))))


def _header(
    volume: ImageVolume,
    datatype: Int,
    bits: Int,
    intent: Int,
    low: Float64,
    high: Float64,
) raises -> List[UInt8]:
    """Return a header and its extension flags, little endian."""
    var out = List[UInt8]()
    _push32(out, HEADER_SIZE)
    for _ in range(36):
        out.append(0)
    var sizes: List[Int] = [3, volume.nx, volume.ny, volume.nz, 1, 1, 1, 1]
    for value in sizes:  # pragma: no branch
        _push16(out, value)
    for _ in range(3):
        _push_float(out, 0)
    _push16(out, intent)
    _push16(out, datatype)
    _push16(out, bits)
    _push16(out, 0)
    var sx = volume.spacing_x.to(MILLIMETER64)
    var sy = volume.spacing_y.to(MILLIMETER64)
    var sz = volume.spacing_z.to(MILLIMETER64)
    var pixdim: List[Float64] = [1, sx, sy, sz, 0, 0, 0, 0]
    for value in pixdim:  # pragma: no branch
        _push_float(out, value)
    _push_float(out, Float64(DATA_OFFSET))
    _push_float(out, 1)
    _push_float(out, 0)
    _push16(out, 0)
    out.append(0)
    # Spatial units of millimeters.
    out.append(2)
    _push_float(out, high)
    _push_float(out, low)
    for _ in range(4):
        _push_float(out, 0)
    var description = String("ThreeMojo").as_bytes()
    for k in range(80):
        out.append(description[k] if k < len(description) else 0)
    for _ in range(24):
        out.append(0)
    # No qform; an sform in scanner coordinates.
    _push16(out, 0)
    _push16(out, 1)
    for _ in range(6):
        _push_float(out, 0)
    var mm = 1.0 / Length64(1.0, MILLIMETER64).to(METER)
    var x = _lps(volume.axis_x) * sx
    var y = _lps(volume.axis_y) * sy
    var z = _lps(volume.axis_z) * sz
    var o = _lps(volume.origin) * mm
    var rows: List[Float64] = [
        x.x,
        y.x,
        z.x,
        o.x,
        x.y,
        y.y,
        z.y,
        o.y,
        x.z,
        y.z,
        z.z,
        o.z,
    ]
    for value in rows:  # pragma: no branch
        _push_float(out, value)
    for _ in range(16):
        out.append(0)
    out.append(110)
    out.append(43)
    out.append(49)
    out.append(0)
    for _ in range(4):
        out.append(0)
    return out^


def _gzip(var data: List[UInt8]) raises -> List[UInt8]:
    """Return bytes wrapped as one gzip member."""
    var out: List[UInt8] = [31, 139, 8, 0, 0, 0, 0, 0, 0, 255]
    out.extend(deflate(data))
    _push32(out, Int(crc32(data)))
    _push32(out, len(data) & 0xFFFFFFFF)
    return out^


def encode_nifti(volume: ImageVolume, compress: Bool) raises -> List[UInt8]:
    """Return a volume as a NIfTI-1 file of 32-bit floats.

    The display range is the volume's window.

    Args:
        volume: The volume.
        compress: Whether to wrap the file in gzip, for `.nii.gz`.

    Returns:
        The file.

    Raises:
        Error: If the volume has more than 32767 voxels on an axis.
    """
    _require_nifti_grid(volume.nx, volume.ny, volume.nz)
    var low = volume.window_center - volume.window_width / 2
    var high = volume.window_center + volume.window_width / 2
    var out = _header(volume, 16, 32, 0, low, high)
    for value in volume.values:  # pragma: no branch
        _push32(out, Int(bitcast[DType.uint32](value)))
    if compress:
        return _gzip(out^)
    return out^


def encode_nifti_labels(
    map: LabelMap, volume: ImageVolume, compress: Bool
) raises -> List[UInt8]:
    """Return a label map as a NIfTI-1 file of unsigned bytes.

    The file has the placement of the volume and the label intent, 1002.

    Args:
        map: The label map.
        volume: The volume the map was made for.
        compress: Whether to wrap the file in gzip, for `.nii.gz`.

    Returns:
        The file.

    Raises:
        Error: If the grids differ, or the volume has more than 32767
            voxels on an axis.
    """
    require_same_grid(map, volume)
    _require_nifti_grid(volume.nx, volume.ny, volume.nz)
    var out = _header(volume, 2, 8, LABEL_INTENT, 0, 0)
    out.extend(map.labels.copy())
    if compress:
        return _gzip(out^)
    return out^


def _require_nifti_grid(nx: Int, ny: Int, nz: Int) raises:
    """Refuse a grid that a NIfTI-1 header cannot hold."""
    if max(nx, max(ny, nz)) > 32767:
        raise Error("A NIfTI-1 file has at most 32767 voxels on an axis")
