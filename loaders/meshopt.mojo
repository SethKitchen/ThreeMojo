# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The meshopt codecs that glTF's `EXT_meshopt_compression` stores buffer
views in: three.js's `MeshoptDecoder`, meshoptimizer 0.22's decoder.

**Three modes.** `ATTRIBUTES` stores elements of any size as byte deltas
from the element before, in blocks of up to 256 elements, each byte of the
element in its own stream. `TRIANGLES` stores a triangle list as one code
byte a triangle, from a cache of recent edges and vertices. `INDICES`
stores any list of indices as deltas from one of two running values.

**Three filters.** After `ATTRIBUTES`, a filter can turn each element back
into what it stood for: `OCTAHEDRAL` a unit vector from two coordinates,
`QUATERNION` a unit quaternion from three components, and `EXPONENTIAL` a
float from an exponent and a mantissa.

**Bit for bit.** three.js runs meshoptimizer's WebAssembly build, and a
browser with SIMD runs its SIMD filters. Those round to the nearest even
integer by adding 1.5 times 2^23, and they divide by a square root where
the scalar code multiplies by a reciprocal. This port does the same float
operations in the same order, so its output is the same bytes.

**Errors.** A stream that is too short, has the wrong header, or does not
end where its tail begins is refused with meshoptimizer's code, as
three.js's `Malformed buffer data`. A size, a count or a filter that the
extension's specification forbids is refused as well. meshoptimizer does
not check those, and what it makes of them is unspecified.
"""

from std.math import sqrt
from std.memory import bitcast


@fieldwise_init
struct MeshoptMode(Equatable, ImplicitlyCopyable, Writable):
    """Which of meshopt's three bitstreams a buffer view holds, as a type
    rather than a bare int.

    `decode_gltf_buffer` stops `MeshoptMode(9)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three modes.

        Returns:
            Whether it is `MESHOPT_ATTRIBUTES`, `MESHOPT_TRIANGLES` or
            `MESHOPT_INDICES`.
        """
        return (
            self == MESHOPT_ATTRIBUTES
            or self == MESHOPT_TRIANGLES
            or self == MESHOPT_INDICES
        )


# Elements of any size, as byte deltas: the extension's `ATTRIBUTES`.
comptime MESHOPT_ATTRIBUTES = MeshoptMode(0)
# A triangle list: the extension's `TRIANGLES`.
comptime MESHOPT_TRIANGLES = MeshoptMode(1)
# Any list of indices: the extension's `INDICES`.
comptime MESHOPT_INDICES = MeshoptMode(2)


@fieldwise_init
struct MeshoptFilter(Equatable, ImplicitlyCopyable, Writable):
    """Which filter turns decoded elements back into what they stood for,
    as a type rather than a bare int.

    `decode_gltf_buffer` stops `MeshoptFilter(9)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four filters.

        Returns:
            Whether it is `FILTER_NONE`, `FILTER_OCTAHEDRAL`,
            `FILTER_QUATERNION` or `FILTER_EXPONENTIAL`.
        """
        return (
            self == FILTER_NONE
            or self == FILTER_OCTAHEDRAL
            or self == FILTER_QUATERNION
            or self == FILTER_EXPONENTIAL
        )


# No filter: the elements are used as they are decoded.
comptime FILTER_NONE = MeshoptFilter(0)
# Unit vectors from two octahedral coordinates.
comptime FILTER_OCTAHEDRAL = MeshoptFilter(1)
# Unit quaternions from their three smallest components.
comptime FILTER_QUATERNION = MeshoptFilter(2)
# Floats from an 8-bit exponent and a 24-bit mantissa.
comptime FILTER_EXPONENTIAL = MeshoptFilter(3)

# The header byte's high nibble for each mode. The low nibble is a version.
comptime _VERTEX_HEADER = 0xA0
comptime _INDEX_HEADER = 0xE0
comptime _SEQUENCE_HEADER = 0xD0
# A block of elements fits in 8192 bytes and holds at most 256 elements,
# in groups of 16.
comptime _BLOCK_BYTES = 8192
comptime _BLOCK_MAX = 256
comptime _GROUP = 16
# The most bytes that one group of 16 deltas can take, which a decoder
# needs before it starts one.
comptime _GROUP_LIMIT = 24
# The attribute stream's tail is at least this long.
comptime _TAIL_MIN = 32
# Adding 1.5 times 2^23 to a float rounds it to the nearest even integer,
# which is then its low mantissa bits.
comptime _SNAP = Float32(12582912)


def meshopt_mode(name: String) raises -> MeshoptMode:
    """Return the mode that the extension names.

    Args:
        name: `ATTRIBUTES`, `TRIANGLES` or `INDICES`.

    Returns:
        The mode.

    Raises:
        If the name is none of those.
    """
    if name == "ATTRIBUTES":
        return MESHOPT_ATTRIBUTES
    if name == "TRIANGLES":
        return MESHOPT_TRIANGLES
    if name == "INDICES":
        return MESHOPT_INDICES
    raise Error("meshopt: a mode that is not known: " + name)


def meshopt_filter(name: String) raises -> MeshoptFilter:
    """Return the filter that the extension names.

    Args:
        name: `NONE`, `OCTAHEDRAL`, `QUATERNION` or `EXPONENTIAL`.

    Returns:
        The filter.

    Raises:
        If the name is none of those.
    """
    if name == "NONE":
        return FILTER_NONE
    if name == "OCTAHEDRAL":
        return FILTER_OCTAHEDRAL
    if name == "QUATERNION":
        return FILTER_QUATERNION
    if name == "EXPONENTIAL":
        return FILTER_EXPONENTIAL
    raise Error("meshopt: a filter that is not known: " + name)


def _malformed(code: Int) -> Error:
    """Return the error that three.js's decoder throws for a code."""
    return Error("meshopt: malformed buffer data: " + String(code))


def _unzigzag(value: UInt8) -> UInt8:
    """Return a zigzag-coded byte's signed delta, wrapped to a byte."""
    if value & 1 != 0:
        return ~(value >> 1)
    return value >> 1


def _decode_group(
    source: List[UInt8], at: Int, mut buffer: List[UInt8], first: Int, bits: Int
) -> Int:
    """Decode one group of 16 byte deltas into `buffer` from `first`, and
    return where the next group starts.

    Two bits of header say how: all zero, two or four bits a delta with a
    whole byte after for each that is all ones, or 16 whole bytes. The
    first delta is in a byte's high bits.
    """
    if bits == 0:
        for j in range(_GROUP):  # pragma: no branch
            buffer[first + j] = 0
        return at
    if bits == 3:
        for j in range(_GROUP):  # pragma: no branch
            buffer[first + j] = source[at + j]
        return at + _GROUP
    var width = 2 if bits == 1 else 4
    var sentinel = UInt8((1 << width) - 1)
    var extra = at + _GROUP * width // 8
    for j in range(_GROUP):  # pragma: no branch
        var byte = source[at + j * width // 8]
        var code = (byte >> UInt8(8 - width - j * width % 8)) & sentinel
        if code == sentinel:
            buffer[first + j] = source[extra]
            extra += 1
        else:
            buffer[first + j] = code
    return extra


def _decode_bytes(
    source: List[UInt8], at: Int, end: Int, mut buffer: List[UInt8], size: Int
) raises -> Int:
    """Decode one byte of every element of a block, `size` of them, and
    return where the next byte's stream starts."""
    var header = at
    var header_size = (size // _GROUP + 3) // 4
    if end - at < header_size:
        raise _malformed(-2)
    var next = at + header_size
    for first in range(0, size, _GROUP):  # pragma: no branch
        if end - next < _GROUP_LIMIT:
            raise _malformed(-2)
        var group = first // _GROUP
        var bits = (Int(source[header + group // 4]) >> (group % 4 * 2)) & 3
        next = _decode_group(source, next, buffer, first, bits)
    return next


def decode_vertex_buffer(
    count: Int, size: Int, source: List[UInt8]
) raises -> List[UInt8]:
    """Decode an `ATTRIBUTES` stream: meshoptimizer's
    `meshopt_decodeVertexBuffer`.

    Args:
        count: How many elements.
        size: Each element's bytes, a multiple of 4 from 4 to 256.
        source: The stream.

    Returns:
        The elements' bytes, `count` times `size` of them.

    Raises:
        If the size or the count is not allowed, or the stream is
        malformed.
    """
    if size < 4 or size > 256 or size % 4 != 0:
        raise Error(
            "meshopt: an element's size must be a multiple of 4 from 4 to 256"
        )
    if count < 0:
        raise Error("meshopt: a count must not be negative")
    var end = len(source)
    if end < 1 + size:
        raise _malformed(-2)
    if Int(source[0]) & 0xF0 != _VERTEX_HEADER or Int(source[0]) & 0x0F > 0:
        raise _malformed(-1)
    # The element before the first is stored whole at the end.
    var last = List[UInt8](capacity=size)
    for k in range(size):  # pragma: no branch
        last.append(source[end - size + k])
    var block = min((_BLOCK_BYTES // size) & ~(_GROUP - 1), _BLOCK_MAX)
    var out = List[UInt8](length=count * size, fill=0)
    var buffer = List[UInt8](length=_BLOCK_MAX, fill=0)
    var at = 1
    var offset = 0
    while offset < count:
        var elements = min(block, count - offset)
        var aligned = (elements + _GROUP - 1) & ~(_GROUP - 1)
        for k in range(size):  # pragma: no branch
            at = _decode_bytes(source, at, end, buffer, aligned)
            var previous = last[k]
            for i in range(elements):  # pragma: no branch
                previous = _unzigzag(buffer[i]) + previous
                out[(offset + i) * size + k] = previous
            last[k] = previous
        offset += elements
    if end - at != max(size, _TAIL_MIN):
        raise _malformed(-3)
    return out^


def _vbyte(source: List[UInt8], mut at: Int) -> UInt32:
    """Read an unsigned LEB128 number of up to five bytes, as
    meshoptimizer does: the bits past 32 are dropped."""
    var lead = source[at]
    at += 1
    if lead < 128:
        return UInt32(lead)
    var result = UInt32(lead & 127)
    var shift = UInt32(7)
    for _ in range(4):  # pragma: no branch
        var group = source[at]
        at += 1
        result |= UInt32(group & 127) << shift
        shift += 7
        if group < 128:
            break
    return result


def _delta(value: UInt32) -> UInt32:
    """Return a zigzag-coded 32-bit delta, wrapped to 32 bits."""
    if value & 1 != 0:
        return ~(value >> 1)
    return value >> 1


def _put_index(mut out: List[UInt8], slot: Int, size: Int, value: UInt32):
    """Write an index little-endian at `slot`, cut to `size` bytes."""
    for b in range(size):  # pragma: no branch
        out[slot * size + b] = UInt8((value >> UInt32(8 * b)) & 0xFF)


struct _Fifos(Movable):
    """The triangle decoder's caches: 16 edges and 16 vertices, each with
    the slot the next push writes."""

    var edges: List[UInt32]
    var vertices: List[UInt32]
    var edge_at: Int
    var vertex_at: Int

    def __init__(out self):
        """Start both caches full of all-ones indices, as meshoptimizer
        does."""
        self.edges = List[UInt32](length=32, fill=UInt32.MAX)
        self.vertices = List[UInt32](length=16, fill=UInt32.MAX)
        self.edge_at = 0
        self.vertex_at = 0

    def edge(self, back: Int) -> Tuple[UInt32, UInt32]:
        """Return the edge `back` pushes ago, 0 the latest."""
        var slot = (self.edge_at - 1 - back) & 15
        return (self.edges[slot * 2], self.edges[slot * 2 + 1])

    def vertex(self, slot: Int) -> UInt32:
        """Return the vertex at a slot, wrapped to the cache."""
        return self.vertices[slot & 15]

    def push_edge(mut self, a: UInt32, b: UInt32):
        """Push an edge."""
        self.edges[self.edge_at * 2] = a
        self.edges[self.edge_at * 2 + 1] = b
        self.edge_at = (self.edge_at + 1) & 15

    def push_vertex(mut self, v: UInt32, keep: Bool = True):
        """Write a vertex, and move on only when `keep` is set, as
        meshoptimizer writes it either way."""
        self.vertices[self.vertex_at] = v
        if keep:
            self.vertex_at = (self.vertex_at + 1) & 15


def decode_index_buffer(
    count: Int, size: Int, source: List[UInt8]
) raises -> List[UInt8]:
    """Decode a `TRIANGLES` stream: meshoptimizer's
    `meshopt_decodeIndexBuffer`.

    Args:
        count: How many indices, three a triangle.
        size: Each index's bytes, 2 or 4.
        source: The stream.

    Returns:
        The indices' bytes, little-endian.

    Raises:
        If the size or the count is not allowed, or the stream is
        malformed.
    """
    if size != 2 and size != 4:
        raise Error("meshopt: an index's size must be 2 or 4")
    if count < 0 or count % 3 != 0:
        raise Error("meshopt: a triangle list's count must be a multiple of 3")
    var length = len(source)
    if length < 1 + count // 3 + 16:
        raise _malformed(-2)
    if Int(source[0]) & 0xF0 != _INDEX_HEADER:
        raise _malformed(-1)
    var version = Int(source[0]) & 0x0F
    if version > 1:
        raise _malformed(-1)
    var out = List[UInt8](length=count * size, fill=0)
    var fifos = _Fifos()
    var next = UInt32(0)
    var last = UInt32(0)
    # Version 1 spends codes 13 and 14 on the vertex just before and just
    # after the last free one.
    var cached = 13 if version >= 1 else 15
    var code = 1
    var data = 1 + count // 3
    # The last 16 bytes are the table of three-vertex codes.
    var table = length - 16
    for triangle in range(count // 3):
        if data > table:
            raise _malformed(-2)
        var tri = Int(source[code])
        code += 1
        var a: UInt32
        var b: UInt32
        var c: UInt32
        if tri < 0xF0:
            var edge = fifos.edge(tri >> 4)
            a = edge[0]
            b = edge[1]
            var fec = tri & 15
            if fec < cached:
                if fec == 0:
                    c = next
                    next += 1
                else:
                    c = fifos.vertex(fifos.vertex_at - 1 - fec)
                fifos.push_vertex(c, fec == 0)
            else:
                if fec == 13:
                    c = last - 1
                elif fec == 14:
                    c = last + 1
                else:
                    c = last + _delta(_vbyte(source, data))
                last = c
                fifos.push_vertex(c)
            fifos.push_edge(c, b)
            fifos.push_edge(a, c)
        else:
            # Codes below 0xFE look their two nibbles up in the table; 0xFE
            # and 0xFF read them from a byte, where a nibble of 15 is a
            # free index.
            var slow = tri >= 0xFE
            var aux: Int
            if slow:
                aux = Int(source[data])
                data += 1
                if aux == 0:
                    # A zero restarts the new vertices at zero.
                    next = 0
            else:
                aux = Int(source[table + (tri & 15)])
            var free_a = tri == 0xFF
            var free_b = slow and aux >> 4 == 15
            var free_c = slow and aux & 15 == 15
            var feb = aux >> 4
            var fec = aux & 15
            a = 0
            if not free_a:
                a = next
                next += 1
            if feb == 0:
                b = next
                next += 1
            else:
                b = fifos.vertex(fifos.vertex_at - feb)
            if fec == 0:
                c = next
                next += 1
            else:
                c = fifos.vertex(fifos.vertex_at - fec)
            if free_a:
                a = last + _delta(_vbyte(source, data))
                last = a
            if free_b:
                b = last + _delta(_vbyte(source, data))
                last = b
            if free_c:
                c = last + _delta(_vbyte(source, data))
                last = c
            fifos.push_vertex(a)
            fifos.push_vertex(b, feb == 0 or free_b)
            fifos.push_vertex(c, fec == 0 or free_c)
            fifos.push_edge(b, a)
            fifos.push_edge(c, b)
            fifos.push_edge(a, c)
        _put_index(out, triangle * 3, size, a)
        _put_index(out, triangle * 3 + 1, size, b)
        _put_index(out, triangle * 3 + 2, size, c)
    if data != table:
        raise _malformed(-3)
    return out^


def decode_index_sequence(
    count: Int, size: Int, source: List[UInt8]
) raises -> List[UInt8]:
    """Decode an `INDICES` stream: meshoptimizer's
    `meshopt_decodeIndexSequence`.

    Args:
        count: How many indices.
        size: Each index's bytes, 2 or 4.
        source: The stream.

    Returns:
        The indices' bytes, little-endian.

    Raises:
        If the size or the count is not allowed, or the stream is
        malformed.
    """
    if size != 2 and size != 4:
        raise Error("meshopt: an index's size must be 2 or 4")
    if count < 0:
        raise Error("meshopt: a count must not be negative")
    var length = len(source)
    if length < 1 + count + 4:
        raise _malformed(-2)
    if Int(source[0]) & 0xF0 != _SEQUENCE_HEADER:
        raise _malformed(-1)
    if Int(source[0]) & 0x0F > 1:
        raise _malformed(-1)
    var out = List[UInt8](length=count * size, fill=0)
    # Two running values; each delta's low bit says which it moves.
    var last = List[UInt32](length=2, fill=0)
    var data = 1
    # The last 4 bytes are a tail that holds nothing.
    var tail = length - 4
    for i in range(count):
        if data >= tail:
            raise _malformed(-2)
        var value = _vbyte(source, data)
        var which = Int(value & 1)
        last[which] = last[which] + _delta(value >> 1)
        _put_index(out, i, size, last[which])
    if data != tail:
        raise _malformed(-3)
    return out^


def _i16(data: List[UInt8], at: Int) -> Int32:
    """Read a little-endian 16-bit signed integer."""
    return Int32(Int16(UInt16(data[at]) | (UInt16(data[at + 1]) << 8)))


def _u32(data: List[UInt8], at: Int) -> UInt32:
    """Read a little-endian 32-bit word."""
    return (
        UInt32(data[at])
        | (UInt32(data[at + 1]) << 8)
        | (UInt32(data[at + 2]) << 16)
        | (UInt32(data[at + 3]) << 24)
    )


def _put_u32(mut data: List[UInt8], at: Int, value: UInt32):
    """Write a little-endian 32-bit word."""
    for b in range(4):  # pragma: no branch
        data[at + b] = UInt8((value >> UInt32(8 * b)) & 0xFF)


@no_inline
def _mul(a: Float32, b: Float32) -> Float32:
    """Return a product rounded to a float on its own.

    The compiler would fuse a product and the sum it feeds into one
    operation that rounds once. WebAssembly rounds twice, and so must
    this, so each product is made where it cannot be fused.
    """
    return a * b


def _snap(value: Float32) -> UInt32:
    """Round a float to the nearest even integer by the SIMD filters'
    addition, and return the sum's bits, whose low bits are that integer."""
    return bitcast[DType.uint32](value + _SNAP)


def _negative(value: Float32) -> Bool:
    """Return whether a float's sign bit is set, which is what an integer
    comparison of its bits with zero asks."""
    return bitcast[DType.int32](value) < 0


def _flip(value: Float32, like: Float32) -> Float32:
    """Return `value` with its sign bit flipped when `like`'s is set."""
    var sign = bitcast[DType.uint32](like) & 0x80000000
    return bitcast[DType.float32](bitcast[DType.uint32](value) ^ sign)


def _octahedral(
    x0: Int32, y0: Int32, z0: Int32, scale: Float32
) -> Tuple[UInt32, UInt32, UInt32]:
    """Turn two octahedral coordinates and a one into a unit vector at
    `scale`, as meshoptimizer's SIMD filter does, and return each
    component's snapped bits."""
    var x = Float32(x0)
    var y = Float32(y0)
    var z = Float32(z0) - (abs(x) + abs(y))
    # Fold the lower half of the octahedron over.
    var t = z if _negative(z) else Float32(0)
    x = x + _flip(t, x)
    y = y + _flip(t, y)
    var s = scale / sqrt(_mul(x, x) + (_mul(y, y) + _mul(z, z)))
    return (_snap(_mul(x, s)), _snap(_mul(y, s)), _snap(_mul(z, s)))


def decode_filter_oct(mut data: List[UInt8], count: Int, stride: Int) raises:
    """Undo the octahedral filter in place: meshoptimizer's
    `meshopt_decodeFilterOct`.

    Each element is x, y, a one that sets the precision, and a fourth
    component that is kept. It becomes a unit vector at the full range of
    its component type.

    Args:
        data: The decoded elements.
        count: How many elements.
        stride: 4 for 8-bit components, 8 for 16-bit ones.

    Raises:
        If the stride is not 4 or 8.
    """
    if stride == 4:
        for i in range(count):
            var at = i * 4
            var r = _octahedral(
                Int32(Int8(data[at])),
                Int32(Int8(data[at + 1])),
                Int32(Int8(data[at + 2])),
                127,
            )
            data[at] = UInt8(r[0] & 0xFF)
            data[at + 1] = UInt8(r[1] & 0xFF)
            data[at + 2] = UInt8(r[2] & 0xFF)
        return
    if stride != 8:
        raise Error("meshopt: the octahedral filter needs a stride of 4 or 8")
    for i in range(count):
        var at = i * 8
        # The one is read without its sign, as meshoptimizer masks it.
        var one = Int32(UInt16(data[at + 4]) | (UInt16(data[at + 5]) << 8))
        var r = _octahedral(
            _i16(data, at), _i16(data, at + 2), one & 0x7FFF, 32767
        )
        var parts: List[UInt32] = [r[0], r[1], r[2]]
        for c in range(3):  # pragma: no branch
            data[at + c * 2] = UInt8(parts[c] & 0xFF)
            data[at + c * 2 + 1] = UInt8((parts[c] >> 8) & 0xFF)


def decode_filter_quat(mut data: List[UInt8], count: Int, stride: Int) raises:
    """Undo the quaternion filter in place: meshoptimizer's
    `meshopt_decodeFilterQuat`.

    Each element is the three smallest components, scaled by the square
    root of two, and a one whose low two bits name the largest. The
    largest is rebuilt as positive.

    Args:
        data: The decoded elements.
        count: How many elements.
        stride: 8.

    Raises:
        If the stride is not 8.
    """
    if stride != 8:
        raise Error("meshopt: the quaternion filter needs a stride of 8")
    var scale = Float32(1) / sqrt(Float32(2))
    for i in range(count):
        var at = i * 8
        var c = _i16(data, at + 6)
        var ss = scale / Float32(c | 3)
        var x = _mul(Float32(_i16(data, at)), ss)
        var y = _mul(Float32(_i16(data, at + 2)), ss)
        var z = _mul(Float32(_i16(data, at + 4)), ss)
        var ww = Float32(1) - (_mul(x, x) + (_mul(y, y) + _mul(z, z)))
        var w = sqrt(Float32(0) if _negative(ww) else ww)
        var parts: List[UInt32] = [
            _snap(_mul(w, 32767)),
            _snap(_mul(x, 32767)),
            _snap(_mul(y, 32767)),
            _snap(_mul(z, 32767)),
        ]
        var first = Int(c) & 3
        for k in range(4):  # pragma: no branch
            var slot = at + ((first + k) & 3) * 2
            data[slot] = UInt8(parts[k] & 0xFF)
            data[slot + 1] = UInt8((parts[k] >> 8) & 0xFF)


def decode_filter_exp(mut data: List[UInt8], count: Int, stride: Int) raises:
    """Undo the exponential filter in place: meshoptimizer's
    `meshopt_decodeFilterExp`.

    Each 32-bit word is a signed 8-bit exponent over a signed 24-bit
    mantissa, and it becomes the float that is the mantissa times two to
    the exponent.

    Args:
        data: The decoded elements.
        count: How many elements.
        stride: Each element's bytes, a multiple of 4.

    Raises:
        If the stride is not a positive multiple of 4.
    """
    if stride <= 0 or stride % 4 != 0:
        raise Error(
            "meshopt: the exponential filter needs a stride that is a"
            " multiple of 4"
        )
    for i in range(count * (stride // 4)):
        var v = _u32(data, i * 4)
        var e = Int(bitcast[DType.int32](v) >> 24)
        var power = bitcast[DType.float32](
            UInt32(((e + 127) << 23) & 0xFFFFFFFF)
        )
        var m = Float32(bitcast[DType.int32](v << 8) >> 8)
        _put_u32(data, i * 4, bitcast[DType.uint32](power * m))


def decode_gltf_buffer(
    count: Int,
    stride: Int,
    source: List[UInt8],
    mode: MeshoptMode,
    filter: MeshoptFilter = FILTER_NONE,
) raises -> List[UInt8]:
    """Decode a buffer view that `EXT_meshopt_compression` stores:
    three.js's `MeshoptDecoder.decodeGltfBuffer`.

    Args:
        count: How many elements.
        stride: Each element's bytes.
        source: The compressed bytes.
        mode: The bitstream.
        filter: The filter to undo after it, for `ATTRIBUTES`.

    Returns:
        The view's bytes, `count` times `stride` of them.

    Raises:
        If the mode or the filter is not valid, a filter follows a mode of
        indices, the stride or the count does not fit the mode or the
        filter, or the stream is malformed.
    """
    if not mode.is_valid():
        raise Error("meshopt: a mode that is not known")
    if not filter.is_valid():
        raise Error("meshopt: a filter that is not known")
    if mode == MESHOPT_TRIANGLES:
        if filter != FILTER_NONE:
            raise Error("meshopt: only ATTRIBUTES can have a filter")
        return decode_index_buffer(count, stride, source)
    if mode == MESHOPT_INDICES:
        if filter != FILTER_NONE:
            raise Error("meshopt: only ATTRIBUTES can have a filter")
        return decode_index_sequence(count, stride, source)
    var out = decode_vertex_buffer(count, stride, source)
    if filter == FILTER_OCTAHEDRAL:
        decode_filter_oct(out, count, stride)
    elif filter == FILTER_QUATERNION:
        decode_filter_quat(out, count, stride)
    elif filter == FILTER_EXPONENTIAL:
        decode_filter_exp(out, count, stride)
    return out^
