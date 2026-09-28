# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usdc_parser`: LZ4 blocks, OpenUSD's integer coding,
halves, and crates built here, one value type and one quirk of three.js
r186's `USDCParser` at a time. `tests/test_usd.mojo` compares whole files
with three.js."""

from loaders.usd_specs import (
    SPEC_PRIM,
    USD_BOOLEAN,
    USD_NULL,
    USD_NUMBER,
    USD_NUMBERS,
    USD_OBJECT,
    USD_SAMPLES,
    USD_STRING,
    USD_STRINGS,
    UsdLayer,
)
from loaders.usdc_parser import (
    CRATE_ASSET_PATH,
    CRATE_BOOL,
    CRATE_DICTIONARY,
    CRATE_DOUBLE,
    CRATE_DOUBLE_VECTOR,
    CRATE_FLOAT,
    CRATE_HALF,
    CRATE_INT,
    CRATE_INT64,
    CRATE_MATRIX2D,
    CRATE_MATRIX3D,
    CRATE_MATRIX4D,
    CRATE_PATH_LIST_OP,
    CRATE_PATH_VECTOR,
    CRATE_QUATD,
    CRATE_QUATF,
    CRATE_QUATH,
    CRATE_SPECIFIER,
    CRATE_STRING,
    CRATE_TIME_SAMPLES,
    CRATE_TOKEN,
    CRATE_TOKEN_VECTOR,
    CRATE_UCHAR,
    CRATE_UINT,
    CRATE_UINT64,
    CRATE_VALUE_BLOCK,
    CRATE_VARIANT_SELECTION_MAP,
    CRATE_VEC2D,
    CRATE_VEC2F,
    CRATE_VEC2H,
    CRATE_VEC2I,
    CRATE_VEC3D,
    CRATE_VEC3F,
    CRATE_VEC3H,
    CRATE_VEC3I,
    CRATE_VEC4D,
    CRATE_VEC4F,
    CRATE_VEC4I,
    CrateType,
    MAX_COUNT,
    decode_integers32,
    decompress_integers32,
    decompress_lz4,
    half_to_float,
    is_crate,
    lz4_decompress_block,
    parse_usdc,
)
from std.math import isinf, isnan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _put(mut out: List[UInt8], value: Int, width: Int):
    """Append a little-endian integer.

    Args:
        out: The bytes.
        value: The integer.
        width: Its bytes.
    """
    for b in range(width):
        out.append(UInt8((value >> (8 * b)) & 0xFF))


def _f32(mut out: List[UInt8], value: Float64):
    """Append a float.

    Args:
        out: The bytes.
        value: The number.
    """
    _put(out, Int(bitcast[DType.uint32](Float32(value))), 4)


def _f64(mut out: List[UInt8], value: Float64):
    """Append a double.

    Args:
        out: The bytes.
        value: The number.
    """
    _put(out, Int(bitcast[DType.uint64](value)), 8)


def _lz4(data: List[UInt8]) -> List[UInt8]:
    """Return bytes as one LZ4 block of literals, after a zero chunk count.

    Args:
        data: The bytes.

    Returns:
        The compressed bytes.
    """
    var n = len(data)
    var out: List[UInt8] = [0]
    out.append(UInt8(min(n, 15) << 4))
    if n >= 15:
        var rest = n - 15
        while rest >= 255:
            out.append(255)
            rest -= 255
        out.append(UInt8(rest))
    out.extend(data.copy())
    return out^


def _ints(values: List[Int]) -> List[UInt8]:
    """Return integers in OpenUSD's coding: a zero common value, then each
    difference in four bytes, then LZ4.

    Args:
        values: The integers.

    Returns:
        The compressed bytes.
    """
    var out = List[UInt8]()
    _put(out, 0, 4)
    for _ in range((len(values) * 2 + 7) // 8):
        out.append(0xFF)
    var last = 0
    for value in values:
        _put(out, value - last, 4)
        last = value
    return _lz4(out)


def _sized(mut out: List[UInt8], data: List[UInt8]):
    """Append a size and bytes.

    Args:
        out: The bytes.
        data: What to append.
    """
    _put(out, len(data), 8)
    out.extend(data.copy())


def _rep(
    type: CrateType,
    payload: Int,
    array: Bool = False,
    inlined: Bool = False,
    compressed: Bool = False,
) -> Tuple[Int, Int]:
    """Return a `ValueRep` as its low and high halves.

    Args:
        type: The type.
        payload: The payload.
        array: Whether it is an array.
        inlined: Whether the payload is the value.
        compressed: Whether the array is compressed.

    Returns:
        The halves.
    """
    var hi = (type.value << 16) | ((payload >> 32) & 0xFFFF)
    if array:
        hi |= 0x80000000
    if inlined:
        hi |= 0x40000000
    if compressed:
        hi |= 0x20000000
    return (payload & 0xFFFFFFFF, hi)


struct _Builder(Movable):
    """A crate built field by field. The payloads follow the 24 bytes of
    the bootstrap, so a payload's offset is 24 plus its place in `data`."""

    var major: Int
    var minor: Int
    var patch: Int
    var tokens: List[String]
    var strings: List[Int]
    var field_tokens: List[Int]
    var field_reps: List[Tuple[Int, Int]]
    var field_sets: List[Int]
    var path_count: Int
    # A compressed tree.
    var path_indices: List[Int]
    var path_elements: List[Int]
    var path_jumps: List[Int]
    # A tree before 0.4.0: each item's index, token and bits, and the item
    # its sibling is, or -1.
    var items: List[Tuple[Int, Int, Int, Int]]
    var spec_paths: List[Int]
    var spec_sets: List[Int]
    var spec_types: List[Int]
    var data: List[UInt8]
    var skip: String
    var magic: String
    # A section whose size the table of contents gives wrong, and the size.
    var fake: String
    var fake_size: Int
    # Tokens the count names past those there, and whether the last one
    # has no zero after it.
    var extra_tokens: Int
    var open_end: Bool

    def __init__(out self, major: Int = 0, minor: Int = 8, patch: Int = 0):
        """Start a crate of a version with the root prim and no fields."""
        self.major = major
        self.minor = minor
        self.patch = patch
        self.tokens = [""]
        self.strings = List[Int]()
        self.field_tokens = List[Int]()
        self.field_reps = List[Tuple[Int, Int]]()
        self.field_sets = List[Int]()
        self.path_count = 1
        self.path_indices = [0]
        self.path_elements = [0]
        self.path_jumps = [-2]
        self.items = [(0, 0, 0, -1)]
        self.spec_paths = List[Int]()
        self.spec_sets = List[Int]()
        self.spec_types = List[Int]()
        self.data = List[UInt8]()
        self.skip = ""
        self.magic = "PXR-USDC"
        self.fake = ""
        self.fake_size = 0
        self.extra_tokens = 0
        self.open_end = False

    def token(mut self, text: String) -> Int:
        """Add a token.

        Returns:
            Its index.
        """
        self.tokens.append(text)
        return len(self.tokens) - 1

    def at(self) -> Int:
        """Return the offset the next payload byte will have."""
        return 24 + len(self.data)

    def field(mut self, name: String, rep: Tuple[Int, Int]) -> Int:
        """Add a field.

        Returns:
            Its index.
        """
        self.field_tokens.append(self.token(name))
        self.field_reps.append(rep)
        return len(self.field_reps) - 1

    def spec(mut self, path: Int, var fields: List[Int], type: Int = 6):
        """Add a spec whose field set is these fields and a terminator."""
        self.spec_paths.append(path)
        self.spec_sets.append(len(self.field_sets))
        self.spec_types.append(type)
        self.field_sets.extend(fields^)
        self.field_sets.append(-1 if self.compressed() else 0xFFFFFFFF)

    def root(mut self, var fields: List[Int]):
        """Add the root's spec."""
        self.spec(0, fields^, 7)

    def compressed(self) -> Bool:
        """Return True from 0.4.0."""
        return not (self.major == 0 and self.minor < 4)

    def section_bytes(self, name: String, start: Int) -> List[UInt8]:
        """Return a section's bytes.

        Args:
            name: The section.
            start: Where it starts in the file.

        Returns:
            Its bytes.
        """
        var out = List[UInt8]()
        if name == "TOKENS":
            var text = List[UInt8]()
            for t in self.tokens:
                text.extend(List[UInt8](t.as_bytes()))
                text.append(0)
            if self.open_end:
                _ = text.pop()
            _put(out, len(self.tokens) + self.extra_tokens, 8)
            if self.compressed():
                _put(out, len(text), 8)
                _sized(out, _lz4(text))
            else:
                _sized(out, text)
        elif name == "STRINGS":
            _put(out, len(self.strings), 8)
            for s in self.strings:
                _put(out, s, 4)
        elif name == "FIELDS":
            if self.compressed():
                _put(out, len(self.field_tokens), 8)
                _sized(out, _ints(self.field_tokens))
                var reps = List[UInt8]()
                for rep in self.field_reps:
                    _put(reps, rep[0], 4)
                    _put(reps, rep[1], 4)
                _sized(out, _lz4(reps))
            else:
                for k in range(len(self.field_tokens)):
                    _put(out, self.field_tokens[k], 4)
                    _put(out, self.field_reps[k][0], 4)
                    _put(out, self.field_reps[k][1], 4)
        elif name == "FIELDSETS":
            if self.compressed():
                _put(out, len(self.field_sets), 8)
                _sized(out, _ints(self.field_sets))
            else:
                for f in self.field_sets:
                    _put(out, f, 4)
        elif name == "PATHS":
            _put(out, self.path_count, 8)
            if self.compressed():
                _put(out, self.path_count, 8)
                _sized(out, _ints(self.path_indices))
                _sized(out, _ints(self.path_elements))
                _sized(out, _ints(self.path_jumps))
            else:
                var offsets = List[Int]()
                var at = start + 8
                for item in self.items:
                    offsets.append(at)
                    at += 17 if (item[2] & 3) == 3 else 9
                for item in self.items:
                    _put(out, item[0], 4)
                    _put(out, item[1], 4)
                    _put(out, item[2], 1)
                    if (item[2] & 3) == 3:
                        _put(out, offsets[item[3]], 8)
        else:
            if self.compressed():
                _put(out, len(self.spec_paths), 8)
                _sized(out, _ints(self.spec_paths))
                _sized(out, _ints(self.spec_sets))
                _sized(out, _ints(self.spec_types))
            else:
                var padded = self.minor == 0 and self.patch == 1
                for k in range(len(self.spec_paths)):
                    _put(out, self.spec_paths[k], 4)
                    _put(out, self.spec_sets[k], 4)
                    _put(out, self.spec_types[k], 4)
                    if padded:
                        _put(out, 0, 4)
        return out^

    def build(self) -> List[UInt8]:
        """Return the file."""
        var out = List[UInt8](self.magic.as_bytes())
        out.append(UInt8(self.major))
        out.append(UInt8(self.minor))
        out.append(UInt8(self.patch))
        for _ in range(5):
            out.append(0)
        var toc_at = len(out)
        _put(out, 0, 8)
        out.extend(self.data.copy())
        var names: List[String] = [
            "TOKENS",
            "STRINGS",
            "FIELDS",
            "FIELDSETS",
            "PATHS",
            "SPECS",
        ]
        var kept = List[String]()
        var starts = List[Int]()
        var sizes = List[Int]()
        for name in names:
            if name == self.skip:
                continue
            var start = len(out)
            var bytes = self.section_bytes(name, start)
            kept.append(name)
            starts.append(start)
            sizes.append(len(bytes))
            out.extend(bytes^)
        var toc = len(out)
        _put(out, len(kept), 8)
        for k in range(len(kept)):
            var name = List[UInt8](kept[k].as_bytes())
            while len(name) < 16:
                name.append(0)
            out.extend(name^)
            _put(out, starts[k], 8)
            _put(out, self.fake_size if kept[k] == self.fake else sizes[k], 8)
        for b in range(8):
            out[toc_at + b] = UInt8((toc >> (8 * b)) & 0xFF)
        return out^


def _one(mut builder: _Builder, rep: Tuple[Int, Int]) raises -> UsdLayer:
    """Parse a crate whose root has one field, `v`.

    Args:
        builder: The crate.
        rep: The field's `ValueRep`.

    Returns:
        The layer.
    """
    var field = builder.field("v", rep)
    builder.root([field])
    return parse_usdc(builder.build())


def _v(layer: UsdLayer) -> Int:
    """Return the root's `v`."""
    return layer.field("/", "v")


def _numbers(layer: UsdLayer, id: Int) raises -> List[Float64]:
    """Return an array of numbers, asserting that it is one."""
    assert_true(layer.kind(id) == USD_NUMBERS, "an array of numbers")
    return layer.values[id].numbers.copy()


def _same(got: List[Float64], want: List[Float64], what: String = "") raises:
    """Assert two lists of numbers are equal, NaN equal to NaN."""
    assert_equal(len(got), len(want), what)
    for k in range(len(got)):
        if isnan(want[k]):
            assert_true(isnan(got[k]), what)
        else:
            assert_equal(got[k], want[k], what)


def test_types_are_checked() raises:
    assert_true(CrateType(0).is_valid())
    assert_true(CrateType(60).is_valid())
    assert_false(CrateType(61).is_valid())
    assert_false(CrateType(-1).is_valid())


def test_is_crate() raises:
    assert_true(is_crate(List[UInt8]("PXR-USDC!".as_bytes())))
    assert_false(is_crate(List[UInt8]("PXR-USD".as_bytes())))
    assert_false(is_crate(List[UInt8]("PXR-USDA".as_bytes())))


def test_lz4_literals_and_matches() raises:
    # Two literals, then a match of offset 2 and length 4 + 2.
    var block: List[UInt8] = [0x22, 0x41, 0x42, 0x02, 0x00]
    var out = List[UInt8](length=8, fill=0)
    assert_equal(lz4_decompress_block(block, 0, len(block), out, 0, 8), 8)
    assert_equal(String(unsafe_from_utf8=out), "ABABABAB")
    # A block with nothing in it writes nothing.
    assert_equal(lz4_decompress_block(block, 2, 2, out, 0, 8), 0)


def test_lz4_long_runs() raises:
    # Fifteen and more literals, and a match of nineteen and more.
    var block: List[UInt8] = [0xFF, 1]
    for k in range(16):
        block.append(UInt8(65 + k))
    block.extend([0x10, 0x00, 255, 1])
    var out = List[UInt8](length=16 + 19 + 256, fill=0)
    var end = lz4_decompress_block(block, 0, len(block), out, 0, len(out))
    assert_equal(end, len(out))
    assert_equal(out[16], 65)
    assert_equal(out[len(out) - 1], out[len(out) - 17])
    # An extension that runs out of input stops the run.
    var cut: List[UInt8] = [0xF0, 255]
    var short = List[UInt8](length=4, fill=0)
    assert_equal(lz4_decompress_block(cut, 0, 2, short, 0, 4), 0)
    var cut_match: List[UInt8] = [0x1F, 0x41, 0x01, 0x00, 255]
    var small = List[UInt8](length=300, fill=0)
    assert_equal(
        lz4_decompress_block(cut_match, 0, 5, small, 0, 300), 1 + 19 + 255
    )


def test_lz4_stops() raises:
    var out = List[UInt8](length=4, fill=0)
    # Literals past the input are cut to it.
    var past: List[UInt8] = [0x50, 0x41, 0x42]
    assert_equal(lz4_decompress_block(past, 0, 3, out, 0, 4), 2)
    # Literals and a match past the output stop there.
    var full: List[UInt8] = [0x50, 1, 2, 3, 4, 5]
    assert_equal(lz4_decompress_block(full, 0, 6, out, 0, 4), 4)
    var copy: List[UInt8] = [0x14, 0x41, 0x01, 0x00]
    assert_equal(lz4_decompress_block(copy, 0, 4, out, 0, 4), 4)
    # An offset of zero, or one before the output, ends the block.
    var zero: List[UInt8] = [0x10, 0x41, 0x00, 0x00, 0x10, 0x42]
    assert_equal(lz4_decompress_block(zero, 0, 6, out, 0, 4), 1)
    var before: List[UInt8] = [0x10, 0x41, 0x05, 0x00]
    assert_equal(lz4_decompress_block(before, 0, 4, out, 0, 4), 1)


def test_decompress_lz4_chunks() raises:
    var single = decompress_lz4(_lz4([7, 8, 9]), 4)
    _same_bytes(single, [7, 8, 9, 0])
    # Nothing to read gives zeros.
    _same_bytes(decompress_lz4(List[UInt8](), 2), [0, 0])
    # Two chunks, each its own block; the second is empty.
    var chunks: List[UInt8] = [2, 3, 0, 0, 0, 0, 0, 0, 0, 0x20, 5, 6]
    _same_bytes(decompress_lz4(chunks, 3), [5, 6, 0])
    # A size past the input reads as zero, as `undefined | 0` does.
    var headless: List[UInt8] = [1, 0]
    _same_bytes(decompress_lz4(headless, 1), [0])
    with assert_raises(contains="past the end of its input"):
        _ = decompress_lz4([1, 9, 0, 0, 0, 0x10], 1)
    with assert_raises(contains="limit"):
        _ = decompress_lz4(List[UInt8](), -1)
    with assert_raises(contains="limit"):
        _ = decompress_lz4(List[UInt8](), MAX_COUNT * 4 + 65)


def _same_bytes(got: List[UInt8], want: List[UInt8]) raises:
    """Assert two byte lists are equal."""
    assert_equal(len(got), len(want))
    for k in range(len(got)):
        assert_equal(got[k], want[k])


def test_integers() raises:
    # A common value of 2; then each code: common, one byte, two bytes,
    # four bytes; then a common one in a second code byte.
    var data = List[UInt8]()
    _put(data, 2, 4)
    data.append(0b11100100)
    data.append(0b00000000)
    data.append(0xFF)
    _put(data, -300, 2)
    _put(data, 0x7FFFFFFF, 4)
    var got = decode_integers32(data, 5)
    var want: List[Int] = [2, 1, -299, 0x7FFFFFFF - 299, 0x7FFFFFFF - 297]
    assert_equal(len(got), 5)
    for k in range(5):
        assert_equal(got[k], want[k])
    # A sum past 2^31 wraps as an `Int32Array` holds it.
    var wrap = List[UInt8]()
    _put(wrap, 0x7FFFFFFF, 4)
    wrap.append(0)
    _put(wrap, 0, 4)
    var wrapped = decode_integers32(wrap, 2)
    assert_equal(wrapped[1], -2)
    assert_equal(len(decode_integers32(wrap, 0)), 0)
    var round = decompress_integers32(_ints([5, -7, 1000000]), 3)
    assert_equal(round[2], 1000000)
    with assert_raises(contains="limit"):
        _ = decompress_integers32(List[UInt8](), -1)
    with assert_raises(contains="limit"):
        _ = decompress_integers32(List[UInt8](), MAX_COUNT + 1)


def test_halves() raises:
    assert_equal(half_to_float(0x3C00), 1.0)
    assert_equal(half_to_float(0xC000), -2.0)
    assert_equal(half_to_float(0x7BFF), 65504.0)
    assert_equal(half_to_float(0x0001), 5.960464477539063e-08)
    assert_equal(half_to_float(0x0000), 0.0)
    var negative_zero = half_to_float(0x8000)
    assert_equal(negative_zero, 0.0)
    assert_true(bitcast[DType.uint64](negative_zero) != 0)
    assert_true(isinf(half_to_float(0x7C00)))
    assert_true(half_to_float(0xFC00) < 0)
    assert_true(isnan(half_to_float(0x7C01)))
    assert_equal(half_to_float(0x3400), 0.25)


def scalar(
    mut b: _Builder,
    mut fields: List[Int],
    mut names: List[String],
    name: String,
    type: CrateType,
    var bytes: List[UInt8],
):
    """Write a value that is not inlined and add a field of it."""
    var at = b.at()
    b.data.extend(bytes^)
    fields.append(b.field(name, _rep(type, at)))
    names.append(name)


def get(layer: UsdLayer, name: String) -> Int:
    """Return the place of the root's field."""
    return layer.field("/", name)


def op(mut b: _Builder, flags: Int, lists: List[List[Int]]) -> Tuple[Int, Int]:
    """Write a list operation of paths and return its `ValueRep`."""
    var at = b.at()
    b.data.append(UInt8(flags))
    for items in lists:
        _put(b.data, len(items), 8)
        for item in items:
            _put(b.data, item, 4)
    return _rep(CRATE_PATH_LIST_OP, at)


def test_values_of_each_type() raises:
    for minor in [3, 8]:
        var b = _Builder(0, minor)
        var fields = List[Int]()
        var names = List[String]()
        scalar(b, fields, names, "bool", CRATE_BOOL, [1])
        scalar(b, fields, names, "uchar", CRATE_UCHAR, [200])
        var bytes = List[UInt8]()
        _put(bytes, -7, 4)
        scalar(b, fields, names, "int", CRATE_INT, bytes^)
        bytes = List[UInt8]()
        _put(bytes, 4000000000, 4)
        scalar(b, fields, names, "uint", CRATE_UINT, bytes^)
        bytes = List[UInt8]()
        _put(bytes, -9000000000, 8)
        scalar(b, fields, names, "int64", CRATE_INT64, bytes^)
        bytes = List[UInt8]()
        _put(bytes, 9000000000, 8)
        scalar(b, fields, names, "uint64", CRATE_UINT64, bytes^)
        scalar(b, fields, names, "half", CRATE_HALF, [0x00, 0x3C])
        bytes = List[UInt8]()
        _f32(bytes, 0.1)
        scalar(b, fields, names, "float", CRATE_FLOAT, bytes^)
        bytes = List[UInt8]()
        _f64(bytes, 0.1)
        scalar(b, fields, names, "double", CRATE_DOUBLE, bytes^)
        var word = b.token("word")
        for type in [CRATE_STRING, CRATE_TOKEN, CRATE_ASSET_PATH]:
            bytes = List[UInt8]()
            _put(bytes, word, 4)
            scalar(b, fields, names, "text" + String(type.value), type, bytes^)
        for type in [CRATE_VEC2F, CRATE_VEC3F, CRATE_VEC4F, CRATE_QUATF]:
            bytes = List[UInt8]()
            for k in range(4):
                _f32(bytes, Float64(k) + 0.5)
            scalar(b, fields, names, "f" + String(type.value), type, bytes^)
        for type in [CRATE_VEC2D, CRATE_VEC3D, CRATE_VEC4D, CRATE_QUATD]:
            bytes = List[UInt8]()
            for k in range(4):
                _f64(bytes, Float64(k) + 0.25)
            scalar(b, fields, names, "d" + String(type.value), type, bytes^)
        bytes = List[UInt8]()
        for k in range(16):
            _f64(bytes, Float64(k))
        scalar(b, fields, names, "matrix", CRATE_MATRIX4D, bytes^)
        for type in [CRATE_VEC2I, CRATE_VEC3I]:
            bytes = List[UInt8]()
            for k in range(3):
                _put(bytes, -k, 4)
            scalar(b, fields, names, "i" + String(type.value), type, bytes^)
        bytes = List[UInt8]()
        _put(bytes, 2, 8)
        _put(bytes, word, 4)
        _put(bytes, 99, 4)
        scalar(b, fields, names, "tokens", CRATE_TOKEN_VECTOR, bytes^)
        bytes = List[UInt8]()
        _put(bytes, 2, 8)
        _put(bytes, 0, 4)
        _put(bytes, 7, 4)
        scalar(b, fields, names, "paths", CRATE_PATH_VECTOR, bytes^)
        bytes = List[UInt8]()
        _put(bytes, 1, 8)
        _f64(bytes, 2.5)
        scalar(b, fields, names, "doubles", CRATE_DOUBLE_VECTOR, bytes^)
        bytes = List[UInt8](length=28, fill=0)
        bytes[0] = 1
        scalar(b, fields, names, "dictionary", CRATE_DICTIONARY, bytes^)
        scalar(b, fields, names, "block", CRATE_VALUE_BLOCK, List[UInt8]())
        scalar(b, fields, names, "unknown", CrateType(99), List[UInt8]())
        b.root(fields^)
        var layer = parse_usdc(b.build())
        var id = layer.field("/", "bool")
        assert_true(layer.kind(id) == USD_BOOLEAN)
        assert_equal(layer.number(id), 1)
        assert_equal(layer.number(layer.field("/", "uchar")), 200)
        assert_equal(layer.number(layer.field("/", "int")), -7)
        assert_equal(layer.number(layer.field("/", "uint")), 4000000000)
        assert_equal(layer.number(layer.field("/", "int64")), -9000000000)
        assert_equal(layer.number(layer.field("/", "uint64")), 9000000000)
        assert_equal(layer.number(layer.field("/", "half")), 1)
        assert_equal(
            layer.number(layer.field("/", "float")), Float64(Float32(0.1))
        )
        assert_equal(layer.number(layer.field("/", "double")), 0.1)
        for type in [CRATE_STRING, CRATE_TOKEN, CRATE_ASSET_PATH]:
            # A string is read as a token, as three.js reads it.
            assert_equal(
                layer.text(layer.field("/", "text" + String(type.value))),
                "word",
            )
        _same(_numbers(layer, layer.field("/", "f20")), [0.5, 1.5])
        _same(_numbers(layer, layer.field("/", "f24")), [0.5, 1.5, 2.5])
        _same(_numbers(layer, layer.field("/", "f28")), [0.5, 1.5, 2.5, 3.5])
        _same(_numbers(layer, layer.field("/", "f17")), [0.5, 1.5, 2.5, 3.5])
        _same(_numbers(layer, layer.field("/", "d19")), [0.25, 1.25])
        _same(_numbers(layer, layer.field("/", "d23")), [0.25, 1.25, 2.25])
        _same(
            _numbers(layer, layer.field("/", "d27")), [0.25, 1.25, 2.25, 3.25]
        )
        _same(
            _numbers(layer, layer.field("/", "d16")), [0.25, 1.25, 2.25, 3.25]
        )
        assert_equal(len(_numbers(layer, layer.field("/", "matrix"))), 16)
        _same(_numbers(layer, layer.field("/", "i22")), [0, -1])
        _same(_numbers(layer, layer.field("/", "i26")), [0, -1, -2])
        var tokens = layer.field("/", "tokens")
        assert_true(layer.kind(tokens) == USD_STRINGS)
        assert_equal(layer.values[tokens].strings[0], "word")
        assert_equal(layer.values[tokens].strings[1], "")
        var paths = layer.field("/", "paths")
        assert_equal(layer.values[paths].strings[0], "/")
        assert_equal(layer.values[paths].strings[1], "")
        _same(_numbers(layer, layer.field("/", "doubles")), [2.5])
        var dictionary = layer.field("/", "dictionary")
        assert_true(layer.kind(dictionary) == USD_OBJECT)
        assert_equal(len(layer.values[dictionary].strings), 0)
        assert_true(layer.kind(layer.field("/", "block")) == USD_NULL)
        assert_true(layer.kind(layer.field("/", "unknown")) == USD_NULL)


def test_inlined_values() raises:
    var b = _Builder()
    b.strings = [0]
    var word = b.token("word")
    b.strings.append(word)
    var fields = List[Int]()
    var bits = Int(bitcast[DType.uint32](Float32(0.5)))
    var cases: List[Tuple[String, CrateType, Int]] = [
        ("bool", CRATE_BOOL, 0),
        ("uchar", CRATE_UCHAR, 0x1FF),
        ("int", CRATE_INT, 0xFFFFFFF9),
        ("float", CRATE_FLOAT, bits),
        ("double", CRATE_DOUBLE, bits),
        ("token", CRATE_TOKEN, word),
        ("asset", CRATE_ASSET_PATH, 99),
        ("string", CRATE_STRING, 1),
        ("far", CRATE_STRING, 5),
        ("half2", CRATE_VEC2H, 0xC0003C00),
        ("vec2f", CRATE_VEC2F, 0x0000FF01),
        ("vec2i", CRATE_VEC2I, 0x00000302),
        ("vec3f", CRATE_VEC3F, 0x00FE0201),
        ("vec3i", CRATE_VEC3I, 0x00030201),
        ("vec4f", CRATE_VEC4F, 0x80030201),
        ("vec4i", CRATE_VEC4I, 0x04030201),
        ("m2", CRATE_MATRIX2D, 0x00000302),
        ("m3", CRATE_MATRIX3D, 0x00040302),
        ("m4", CRATE_MATRIX4D, 0x01010101),
        ("specifier", CRATE_SPECIFIER, 2),
        ("half", CRATE_HALF, 0x3C00),
        ("double3", CRATE_VEC3D, 0x030201),
    ]
    for c in cases:
        fields.append(b.field(c[0], _rep(c[1], c[2], inlined=True)))
    b.root(fields^)
    var layer = parse_usdc(b.build())
    assert_equal(layer.number(get(layer, "bool")), 0)
    assert_equal(layer.number(get(layer, "uchar")), 255)
    # An inlined int reads as unsigned, as three.js reads it.
    assert_equal(layer.number(get(layer, "int")), 4294967289)
    assert_equal(layer.number(get(layer, "float")), 0.5)
    assert_equal(layer.number(get(layer, "double")), 0.5)
    assert_equal(layer.text(get(layer, "token")), "word")
    assert_equal(layer.text(get(layer, "asset")), "")
    assert_equal(layer.text(get(layer, "string")), "word")
    assert_equal(layer.text(get(layer, "far")), "")
    _same(_numbers(layer, get(layer, "half2")), [1, -2])
    _same(_numbers(layer, get(layer, "vec2f")), [1, -1])
    _same(_numbers(layer, get(layer, "vec2i")), [2, 3])
    _same(_numbers(layer, get(layer, "vec3f")), [1, 2, -2])
    _same(_numbers(layer, get(layer, "vec3i")), [1, 2, 3])
    _same(_numbers(layer, get(layer, "vec4f")), [1, 2, 3, -128])
    _same(_numbers(layer, get(layer, "vec4i")), [1, 2, 3, 4])
    _same(_numbers(layer, get(layer, "m2")), [2, 0, 0, 3])
    _same(_numbers(layer, get(layer, "m3")), [2, 0, 0, 0, 3, 0, 0, 0, 4])
    var m4 = _numbers(layer, get(layer, "m4"))
    _same(m4, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    assert_equal(layer.number(get(layer, "specifier")), 2)
    # A half and a double3 inlined read as the payload, as in three.js.
    assert_equal(layer.number(get(layer, "half")), 0x3C00)
    assert_equal(layer.number(get(layer, "double3")), 0x030201)


def _array(
    mut b: _Builder,
    type: CrateType,
    count: Int,
    var body: List[UInt8],
    compressed: Bool = False,
) -> Tuple[Int, Int]:
    """Write an array's size and body, and return its `ValueRep`.

    Args:
        b: The crate.
        type: The element type.
        count: The size.
        body: The bytes after the size.
        compressed: Whether it is compressed.

    Returns:
        The `ValueRep`.
    """
    var at = b.at()
    _put(b.data, count, 4 if b.minor < 7 else 8)
    b.data.extend(body^)
    return _rep(type, at, array=True, compressed=compressed)


def test_arrays() raises:
    for minor in [6, 8]:
        var b = _Builder(0, minor)
        var fields = List[Int]()
        var body = List[UInt8]()
        _put(body, -1, 4)
        _put(body, 2, 4)
        fields.append(b.field("int", _array(b, CRATE_INT, 2, body^)))
        body = List[UInt8]()
        _put(body, 0xFFFFFFFF, 4)
        fields.append(b.field("uint", _array(b, CRATE_UINT, 1, body^)))
        body = List[UInt8]()
        _f32(body, 1.5)
        fields.append(b.field("float", _array(b, CRATE_FLOAT, 1, body^)))
        body = List[UInt8]()
        _f64(body, 1.25)
        fields.append(b.field("double", _array(b, CRATE_DOUBLE, 1, body^)))
        for type in [CRATE_VEC2F, CRATE_VEC3F, CRATE_VEC4F, CRATE_QUATF]:
            body = List[UInt8]()
            for k in range(4):
                _f32(body, Float64(k))
            fields.append(
                b.field("f" + String(type.value), _array(b, type, 1, body^))
            )
        body = List[UInt8]()
        for k in range(16):
            _f64(body, Float64(k))
        fields.append(b.field("matrix", _array(b, CRATE_MATRIX4D, 1, body^)))
        for type in [CRATE_HALF, CRATE_VEC3H, CRATE_QUATH]:
            body = List[UInt8]()
            for _ in range(4):
                _put(body, 0x3C00, 2)
            fields.append(
                b.field("h" + String(type.value), _array(b, type, 1, body^))
            )
        var word = b.token("word")
        body = List[UInt8]()
        _put(body, word, 4)
        fields.append(b.field("tokens", _array(b, CRATE_TOKEN, 1, body^)))
        fields.append(
            b.field("strings", _array(b, CRATE_STRING, 1, List[UInt8]()))
        )
        fields.append(b.field("empty", _array(b, CRATE_INT, 0, List[UInt8]())))
        fields.append(b.field("zero", _rep(CRATE_INT, 0, array=True)))
        fields.append(b.field("origin", _rep(CRATE_INT, 0)))
        b.root(fields^)
        var layer = parse_usdc(b.build())
        _same(_numbers(layer, get(layer, "int")), [-1, 2])
        # A payload of zero that is not an array reads the file's start.
        assert_equal(layer.number(get(layer, "origin")), 0x2D525850)
        _same(_numbers(layer, get(layer, "uint")), [4294967295])
        _same(_numbers(layer, get(layer, "float")), [1.5])
        _same(_numbers(layer, get(layer, "double")), [1.25])
        assert_equal(len(_numbers(layer, get(layer, "f20"))), 2)
        assert_equal(len(_numbers(layer, get(layer, "f24"))), 3)
        assert_equal(len(_numbers(layer, get(layer, "f28"))), 4)
        assert_equal(len(_numbers(layer, get(layer, "f17"))), 4)
        assert_equal(len(_numbers(layer, get(layer, "matrix"))), 16)
        _same(_numbers(layer, get(layer, "h7")), [1])
        _same(_numbers(layer, get(layer, "h25")), [1, 1, 1])
        _same(_numbers(layer, get(layer, "h18")), [1, 1, 1, 1])
        var tokens = get(layer, "tokens")
        assert_equal(layer.values[tokens].strings[0], "word")
        # An array of a type three.js does not read is empty.
        assert_equal(len(_numbers(layer, get(layer, "strings"))), 0)
        assert_equal(len(_numbers(layer, get(layer, "empty"))), 0)
        assert_equal(len(_numbers(layer, get(layer, "zero"))), 0)


def test_compressed_arrays() raises:
    var b = _Builder()
    var fields = List[Int]()
    var body = List[UInt8]()
    _sized(body, _ints([3, -4]))
    fields.append(b.field("int", _array(b, CRATE_INT, 2, body^, True)))
    body = List[UInt8]()
    _sized(body, _ints([16777217]))
    fields.append(b.field("uint", _array(b, CRATE_UINT, 1, body^, True)))
    body = List[UInt8]()
    body.append(0x69)
    _sized(body, _ints([16777217, -2]))
    fields.append(b.field("ints", _array(b, CRATE_FLOAT, 2, body^, True)))
    body = List[UInt8]()
    body.append(0x74)
    _put(body, 2, 4)
    _f32(body, 0.5)
    _f32(body, 0.25)
    _sized(body, _ints([1, 0, 2, -1]))
    fields.append(b.field("table", _array(b, CRATE_FLOAT, 4, body^, True)))
    body = List[UInt8]()
    body.append(0x00)
    fields.append(b.field("other", _array(b, CRATE_FLOAT, 2, body^, True)))
    fields.append(
        b.field("double", _array(b, CRATE_DOUBLE, 2, List[UInt8](), True))
    )
    b.root(fields^)
    var layer = parse_usdc(b.build())
    _same(_numbers(layer, layer.field("/", "int")), [3, -4])
    _same(_numbers(layer, layer.field("/", "uint")), [16777217])
    # Integers become floats as a `Float32Array` stores them.
    _same(_numbers(layer, layer.field("/", "ints")), [16777216, -2])
    var nan = Float64(0) / Float64(0)
    _same(_numbers(layer, layer.field("/", "table")), [0.25, 0.5, nan, nan])
    _same(_numbers(layer, layer.field("/", "other")), [0, 0])
    assert_equal(len(_numbers(layer, layer.field("/", "double"))), 0)


def test_path_list_operations() raises:
    var b = _Builder()
    var fields = List[Int]()
    # Explicit, add, prepend, append, delete and reorder, in that order.
    fields.append(
        b.field("prepend", op(b, 0x7E, [[0], [0], [0], [0], [0], [0]]))
    )
    fields.append(b.field("explicit", op(b, 0x42, [[0], [0]])))
    fields.append(b.field("append", op(b, 0x44, [List[Int](), [0]])))
    fields.append(b.field("add", op(b, 0x24, [[0], List[Int]()])))
    fields.append(b.field("none", op(b, 0x01, List[List[Int]]())))
    b.root(fields^)
    var layer = parse_usdc(b.build())
    for name in ["prepend", "explicit", "append", "add"]:
        var id = layer.field("/", name)
        assert_true(layer.kind(id) == USD_STRINGS, name)
        assert_equal(layer.values[id].strings[0], "/")
    assert_true(layer.kind(layer.field("/", "none")) == USD_NULL)


def test_variant_selections() raises:
    var b = _Builder()
    var color = b.token("color")
    var red = b.token("red")
    var blue = b.token("blue")
    var size = b.token("size")
    b.strings = [color, red, blue, 0, size]
    var at = b.at()
    _put(b.data, 5, 8)
    for pair in [(0, 1), (4, 1), (0, 2), (3, 1), (0, 3)]:
        _put(b.data, pair[0], 4)
        _put(b.data, pair[1], 4)
    var layer = _one(b, _rep(CRATE_VARIANT_SELECTION_MAP, at))
    var id = _v(layer)
    assert_equal(len(layer.values[id].strings), 2)
    assert_equal(layer.text(layer.object_value(id, "color")), "blue")
    assert_equal(layer.text(layer.object_value(id, "size")), "red")


def test_time_samples() raises:
    var b = _Builder()
    # The payload holds a relative offset to the times' `ValueRep`; after
    # it, a relative offset to the count and the values' `ValueRep`s.
    var start = b.at()
    _put(b.data, 8, 8)
    var times = b.at() + 32
    var rep = _rep(CRATE_DOUBLE_VECTOR, times)
    _put(b.data, rep[0], 4)
    _put(b.data, rep[1], 4)
    _put(b.data, 8, 8)
    _put(b.data, 1, 8)
    var one = _rep(CRATE_INT, 7, inlined=True)
    _put(b.data, one[0], 4)
    _put(b.data, one[1], 4)
    _put(b.data, 1, 8)
    _f64(b.data, 0.5)
    var layer = _one(b, _rep(CRATE_TIME_SAMPLES, start))
    var id = _v(layer)
    assert_true(layer.kind(id) == USD_SAMPLES)
    _same(layer.values[id].numbers, [0.5])
    assert_equal(layer.number(layer.values[id].items[0]), 7)


def _samples(
    times: Tuple[Int, Int], depth_loop: Bool = False
) raises -> List[UInt8]:
    """Return a crate whose root's `v` is time samples with these times
    and no values.

    Args:
        times: The times' `ValueRep`.
        depth_loop: Whether the times are the samples themselves.

    Returns:
        The file.
    """
    var b = _Builder()
    var start = b.at()
    _put(b.data, 8, 8)
    var rep = times
    if depth_loop:
        rep = _rep(CRATE_TIME_SAMPLES, start)
    _put(b.data, rep[0], 4)
    _put(b.data, rep[1], 4)
    _put(b.data, 8, 8)
    _put(b.data, 0, 8)
    var field = b.field("v", _rep(CRATE_TIME_SAMPLES, start))
    b.root([field])
    return b.build()


def test_time_samples_of_one_time_and_refusals() raises:
    var layer = parse_usdc(
        _samples(_rep(CRATE_FLOAT, 0x3F800000, inlined=True))
    )
    var id = _v(layer)
    _same(layer.values[id].numbers, [1])
    assert_equal(len(layer.values[id].items), 0)
    with assert_raises(contains="times are not numbers"):
        _ = parse_usdc(_samples(_rep(CRATE_TOKEN, 0, inlined=True)))
    with assert_raises(contains="nested too deep"):
        _ = parse_usdc(_samples(_rep(CRATE_INT, 0), True))


def test_compressed_paths() raises:
    var b = _Builder()
    var a = b.token("a")
    var c = b.token("c")
    var p = b.token("p")
    b.path_count = 5
    # `/`, its child `/a` with a sibling `/c` three on, `/a`'s property
    # `.p`, and `/a/c` as `.p`'s sibling.
    b.path_indices = [0, 1, 2, 3, 4]
    b.path_elements = [0, a, -p, c, c]
    b.path_jumps = [-1, 3, 0, -2, -2]
    b.spec(1, List[Int]())
    b.spec(2, List[Int](), 1)
    b.spec(3, List[Int]())
    b.spec(4, List[Int]())
    b.spec(9, List[Int]())
    var layer = parse_usdc(b.build())
    assert_equal(len(layer.paths), 4)
    assert_equal(layer.paths[0], "/a")
    assert_equal(layer.paths[1], "/a.p")
    assert_equal(layer.paths[2], "/a/c")
    assert_equal(layer.paths[3], "/c")


def test_a_path_tree_that_does_not_end() raises:
    var b = _Builder()
    b.path_count = 12
    b.path_indices = List[Int]()
    b.path_elements = List[Int]()
    b.path_jumps = List[Int]()
    for k in range(12):
        b.path_indices.append(k)
        b.path_elements.append(0)
        b.path_jumps.append(1)
    with assert_raises(contains="does not end"):
        _ = parse_usdc(b.build())


def test_uncompressed_paths() raises:
    var b = _Builder(0, 3)
    var a = b.token("a")
    var c = b.token("c")
    var p = b.token("p")
    b.path_count = 5
    # Bits: 1 a child, 2 a sibling, 4 a property.
    var q = b.token("q")
    b.path_count = 6
    b.items = [
        (0, 0, 1, -1),
        (1, a, 3, 4),
        (2, p, 6, -1),
        (3, q, 4, -1),
        (4, c, 1, -1),
        (5, a, 0, -1),
    ]
    for k in range(1, 6):
        b.spec(k, List[Int]())
    var layer = parse_usdc(b.build())
    assert_equal(layer.paths[0], "/a")
    assert_equal(layer.paths[1], "/a.p")
    assert_equal(layer.paths[2], "/a.q")
    assert_equal(layer.paths[3], "/c")
    assert_equal(layer.paths[4], "/c/a")


def test_a_deep_path_tree_stops() raises:
    var b = _Builder(0, 3)
    var a = b.token("a")
    b.path_count = 1100
    b.items = List[Tuple[Int, Int, Int, Int]]()
    for k in range(1100):
        b.items.append((k, a, 1, -1))
    b.spec(1000, List[Int]())
    b.spec(1001, List[Int]())
    var layer = parse_usdc(b.build())
    # The walk stops past a depth of 1000, as three.js's does.
    assert_equal(len(layer.paths), 1)
    assert_equal(layer.paths[0].byte_length(), 2000)


def test_padded_specs_of_version_0_0_1() raises:
    var b = _Builder(0, 0, 1)
    var field = b.field("v", _rep(CRATE_INT, 3, inlined=True))
    b.root([field])
    var layer = parse_usdc(b.build())
    assert_equal(layer.number(_v(layer)), 3)
    var two = _Builder(0, 0, 2)
    var other = two.field("v", _rep(CRATE_INT, 4, inlined=True))
    two.root([other])
    assert_equal(parse_usdc(two.build()).number(0), 4)
    var one = _Builder(1, 0)
    var at = one.at()
    _put(one.data, 1, 8)
    _put(one.data, 5, 4)
    var third = one.field("v", _rep(CRATE_INT, at, array=True))
    one.root([third])
    # From 1.0 an array's size is eight bytes, as from 0.7.
    var layer_one = parse_usdc(one.build())
    _same(_numbers(layer_one, 0), [5])


def test_field_sets() raises:
    var b = _Builder()
    var good = b.field("v", _rep(CRATE_INT, 1, inlined=True))
    var nameless = b.field("w", _rep(CRATE_INT, 2, inlined=True))
    b.field_tokens[nameless] = 99
    # A field past the list is skipped, and a token past the list names
    # the field `undefined`.
    b.root([good, 50, -5, nameless])
    b.spec_sets.append(-3)
    b.spec_paths.append(0)
    b.spec_types.append(7)
    var layer = parse_usdc(b.build())
    assert_equal(layer.number(layer.field("/", "v")), 1)
    assert_equal(layer.number(layer.field("/", "undefined")), 2)


def test_a_field_set_past_the_end() raises:
    var b = _Builder()
    b.spec_paths.append(0)
    b.spec_sets.append(99)
    b.spec_types.append(7)
    var layer = parse_usdc(b.build())
    assert_equal(len(layer.paths), 1)
    assert_equal(layer.field("/", "v"), -1)


def test_ten_thousand_fields_at_most() raises:
    var b = _Builder(0, 3)
    var field = b.field("v", _rep(CRATE_INT, 1, inlined=True))
    b.spec_paths.append(0)
    b.spec_sets.append(0)
    b.spec_types.append(7)
    for _ in range(10001):
        b.field_sets.append(field)
    var layer = parse_usdc(b.build())
    assert_equal(layer.number(layer.field("/", "v")), 1)


def test_strings_are_optional() raises:
    var b = _Builder()
    b.skip = "STRINGS"
    var field = b.field("v", _rep(CRATE_STRING, 0, inlined=True))
    b.root([field])
    assert_equal(parse_usdc(b.build()).text(0), "")


def test_refusals() raises:
    var bad = _Builder()
    bad.magic = "PXR-USDA"
    with assert_raises(contains="not a valid USDC file"):
        _ = parse_usdc(bad.build())
    for name in ["TOKENS", "FIELDS", "FIELDSETS", "PATHS", "SPECS"]:
        var b = _Builder()
        b.skip = name
        with assert_raises(contains="no " + name + " section"):
            _ = parse_usdc(b.build())
    var kind = _Builder()
    kind.spec(0, List[Int](), 12)
    with assert_raises(contains="spec of no known type"):
        _ = parse_usdc(kind.build())
    var short = _Builder().build()
    _ = short.pop()
    with assert_raises(contains="past the end"):
        _ = parse_usdc(short^)
    var offset = _Builder()
    with assert_raises(contains="payload offset past"):
        _ = _one(offset, _rep(CRATE_INT, 1 << 40))
    var big = _Builder()
    var at = big.at()
    _put(big.data, 0x80000000, 8)
    with assert_raises(contains="2^31 - 1"):
        _ = _one(big, _rep(CRATE_INT, at, array=True))
    var negative = _Builder()
    at = negative.at()
    _put(negative.data, -1, 8)
    with assert_raises(contains="2^31 - 1"):
        _ = _one(negative, _rep(CRATE_INT, at, array=True))
    var many = _Builder()
    at = many.at()
    _put(many.data, MAX_COUNT + 1, 8)
    with assert_raises(contains="limit"):
        _ = _one(many, _rep(CRATE_TOKEN_VECTOR, at))
    var huge = _Builder()
    at = huge.at()
    _put(huge.data, 1000, 8)
    with assert_raises(contains="past the end"):
        _ = _one(huge, _rep(CRATE_TOKEN_VECTOR, at))


def test_reads_past_the_end() raises:
    # A negative seek, from a relative offset, and a negative size.
    var b = _Builder()
    var start = b.at()
    _put(b.data, -1000, 8)
    with assert_raises(contains="past the end"):
        _ = _one(b, _rep(CRATE_TIME_SAMPLES, start))
    var sized = _Builder()
    var at = sized.at()
    _put(sized.data, 1, 8)
    _put(sized.data, -2, 8)
    with assert_raises(contains="past the end"):
        _ = _one(sized, _rep(CRATE_INT, at, array=True, compressed=True))
    var count = _Builder()
    at = count.at()
    _put(count.data, -2, 8)
    with assert_raises(contains="limit"):
        _ = _one(count, _rep(CRATE_DOUBLE_VECTOR, at))
    # A section whose size is past the limit, or past 2^63.
    for size in [12 * (MAX_COUNT + 1), -12]:
        var fields = _Builder(0, 3)
        fields.fake = "FIELDS"
        fields.fake_size = size
        with assert_raises(contains="limit"):
            _ = parse_usdc(fields.build())
    var sets = _Builder(0, 3)
    sets.fake = "FIELDSETS"
    sets.fake_size = 4 * MAX_COUNT
    with assert_raises(contains="past the end"):
        _ = parse_usdc(sets.build())


def test_empty_crates() raises:
    for minor in [3, 8]:
        var layer = parse_usdc(_Builder(0, minor).build())
        assert_equal(len(layer.paths), 0)
    # A table of contents with no sections has no tokens.
    var bytes = List[UInt8]("PXR-USDC".as_bytes())
    for _ in range(8):
        bytes.append(0)
    _put(bytes, 24, 8)
    _put(bytes, 0, 8)
    with assert_raises(contains="no TOKENS section"):
        _ = parse_usdc(bytes^)
    # A crate before 0.4.0 can have no tokens and no token bytes.
    var tokenless = _Builder(0, 3)
    tokenless.tokens = List[String]()
    assert_equal(len(parse_usdc(tokenless.build()).paths), 0)


def test_tokens_past_their_bytes() raises:
    for open_end in [False, True]:
        var b = _Builder()
        var last = b.token("last")
        b.extra_tokens = 2
        b.open_end = open_end
        var named = b.field("v", _rep(CRATE_INT, 1, inlined=True))
        b.field_tokens[named] = last
        var far = b.field("w", _rep(CRATE_TOKEN, 0, inlined=True))
        b.field_reps[far] = _rep(CRATE_TOKEN, len(b.tokens) + 1, inlined=True)
        b.root([named, far])
        var layer = parse_usdc(b.build())
        assert_equal(layer.number(layer.field("/", "last")), 1)
        assert_equal(layer.text(layer.field("/", "w")), "")


def test_empty_lists() raises:
    var b = _Builder()
    b.strings = [0]
    var fields = List[Int]()
    var at = b.at()
    _put(b.data, 0, 8)
    fields.append(b.field("doubles", _rep(CRATE_DOUBLE_VECTOR, at)))
    at = b.at()
    _put(b.data, 0, 8)
    fields.append(b.field("map", _rep(CRATE_VARIANT_SELECTION_MAP, at)))
    at = b.at()
    _put(b.data, 1, 8)
    _put(b.data, 9, 4)
    _put(b.data, 0, 4)
    fields.append(b.field("far", _rep(CRATE_VARIANT_SELECTION_MAP, at)))
    at = b.at()
    _put(b.data, 0, 8)
    fields.append(b.field("tokens", _rep(CRATE_TOKEN_VECTOR, at)))
    var body = List[UInt8]()
    body.append(0x74)
    _put(body, 0, 4)
    _sized(body, _ints([0]))
    fields.append(b.field("table", _array(b, CRATE_FLOAT, 1, body^, True)))
    var negative = b.field("n", _rep(CRATE_INT, 1, inlined=True))
    b.field_tokens[negative] = -3
    fields.append(negative)
    b.root(fields^)
    var layer = parse_usdc(b.build())
    assert_equal(len(_numbers(layer, layer.field("/", "doubles"))), 0)
    assert_equal(len(layer.values[layer.field("/", "map")].strings), 0)
    assert_equal(len(layer.values[layer.field("/", "far")].strings), 0)
    assert_equal(len(layer.values[layer.field("/", "tokens")].strings), 0)
    var nan = Float64(0) / Float64(0)
    _same(_numbers(layer, layer.field("/", "table")), [nan])
    assert_equal(layer.number(layer.field("/", "undefined")), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
