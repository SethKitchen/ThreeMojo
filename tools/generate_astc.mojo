# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate raw ASTC reference texels with pinned Arm astcenc 5.3.0.

    mojo run -I . tools/generate_astc.mojo LIBRARY OUTPUT

Build the adapter as documented in docs/validation/raw-astc.md. This tool
never calls ThreeMojo. Seeded random blocks and every 11-bit block mode are
validated by the independent decoder. The output is portable hex text.

The random blocks are those of `random.Random(617180)`, so the output is
the same, byte for byte, as the Python generator's that this tool replaces.
"""

from std.collections import Set
from std.ffi import OwnedDLHandle
from std.os import makedirs
from std.os.path import dirname
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom
from tools._sha256 import sha256_hex

comptime PIN = "30aabb3f42406df45a910d8496f9bee17eeba9bb"
"""The astcenc commit of release 5.3.0."""
comptime SEED = 617180
"""The seed of the random blocks."""
comptime RANDOM_BLOCKS = 120000
"""The random blocks tried for each block size."""
comptime INVALID_LIMIT = 4096
"""The invalid blocks recorded for each block size."""
comptime HEX = "0123456789abcdef"


def hex_text(bytes: List[UInt8], count: Int) -> String:
    """Return the first bytes as lowercase hex, as `bytes.hex()` does.

    Args:
        bytes: The bytes.
        count: How many bytes to write.

    Returns:
        Two hex digits for each byte.
    """
    var digits = HEX.as_bytes()
    var out = String(capacity_bytes=2 * count)
    for index in range(count):
        out += chr(Int(digits[Int(bytes[index] >> 4)]))
        out += chr(Int(digits[Int(bytes[index] & 15)]))
    return out^


def block_bytes(value: BigInt) -> List[UInt8]:
    """Return a 128-bit value as 16 little-endian bytes.

    Args:
        value: A value from zero below 2**128.

    Returns:
        The block.
    """
    var out = List[UInt8](capacity=16)
    for index in range(16):
        var byte = 0
        for bit in range(8):
            if value.bit(8 * index + bit):
                byte |= 1 << bit
        out.append(UInt8(byte))
    return out^


struct Reference(Movable):
    """The adapter library and one decoder context for each profile."""

    var library: OwnedDLHandle
    """The adapter library."""
    var contexts: List[Int]
    """The UNORM, sRGB and SFLOAT contexts, as C pointers."""
    var metadata: List[UInt32]
    """The block information of the last call."""
    var pixels: List[UInt8]
    """The texels of the last call."""
    var size: Int
    """The block's width and height, in texels."""

    def __init__(out self, path: String, size: Int) raises:
        """Load the adapter and open its three contexts.

        Args:
            path: The adapter library.
            size: The block size: 4 or 6.

        Raises:
            Error: If the library or a context cannot be opened.
        """
        self.library = OwnedDLHandle(path)
        self.contexts = List[Int]()
        self.metadata = List[UInt32](length=15, fill=0)
        self.pixels = List[UInt8](length=size * size * 8, fill=0)
        self.size = size
        for profile in range(3):
            var context = self.library.call["reference_context", Int](
                UInt32(size), UInt32(profile)
            )
            if context == 0:
                raise Error("the reference decoder cannot open a context")
            self.contexts.append(context)

    def decode(mut self, block: List[UInt8], profile: Int) -> Int32:
        """Decode one block into `pixels`, with its information in
        `metadata`.

        Args:
            block: The 16 block bytes.
            profile: 0 for UNORM, 1 for sRGB, 2 for SFLOAT.

        Returns:
            0 for a decoded block, 1 for an error block, -1 for no block
            information.
        """
        return self.library.call["reference_block", Int32](
            self.contexts[profile],
            block.unsafe_ptr().unsafe_bitcast[NoneType](),
            self.metadata.unsafe_ptr().unsafe_bitcast[NoneType](),
            self.pixels.unsafe_ptr().unsafe_bitcast[NoneType](),
            UInt32(self.size),
            UInt32(profile),
        )

    def close(mut self):
        """Free the three contexts."""
        for context in self.contexts:
            self.library.call["reference_free", NoneType](context)
        self.contexts.clear()


@fieldwise_init
struct Selected(Copyable, Movable):
    """A block kept for the fixture."""

    var block: List[UInt8]
    """The 16 block bytes."""
    var metadata: List[UInt32]
    """Its block information."""


struct Survey(Movable):
    """The blocks of one size, and what they cover."""

    var size: Int
    """The block size."""
    var selected: List[Selected]
    """The blocks kept, in the order they were found."""
    var invalid: List[String]
    """The first invalid blocks, as `SIZE HEX` lines."""
    var seen: Set[String]
    """The features that kept blocks cover."""
    var modes: Set[Int]
    """The 11-bit block modes of valid blocks."""
    var endpoint_modes: Set[Int]
    """The color endpoint modes of valid blocks."""
    var partitions: Set[Int]
    """The partition counts of valid blocks."""
    var grids: Set[Int]
    """The weight grids of valid blocks, as x * 64 + y."""
    var weight_levels: Set[Int]
    """The weight level counts of valid blocks."""
    var endpoint_levels: Set[Int]
    """The color level counts of valid blocks."""
    var dual_components: Set[Int]
    """The dual-plane components of valid blocks."""

    def __init__(out self, size: Int):
        """Start an empty survey.

        Args:
            size: The block size.
        """
        self.size = size
        self.selected = List[Selected]()
        self.invalid = List[String]()
        self.seen = Set[String]()
        self.modes = Set[Int]()
        self.endpoint_modes = Set[Int]()
        self.partitions = Set[Int]()
        self.grids = Set[Int]()
        self.weight_levels = Set[Int]()
        self.endpoint_levels = Set[Int]()
        self.dual_components = Set[Int]()

    def inspect(
        mut self, mut reference: Reference, block: List[UInt8], force: Bool
    ):
        """Decode a block as SFLOAT and keep it if it covers a new feature.

        Args:
            reference: The reference decoder.
            block: The 16 block bytes.
            force: True to keep any valid, finite block.
        """
        if reference.decode(block, 2) != 0:
            if len(self.invalid) < INVALID_LIMIT:
                self.invalid.append(
                    String(self.size) + " " + hex_text(block, 16)
                )
            return
        var m = reference.metadata.copy()
        # Skip blocks that decode to an infinity or a NaN half.
        for index in range(0, len(reference.pixels), 2):
            var half = Int(reference.pixels[index]) | (
                Int(reference.pixels[index + 1]) << 8
            )
            if half & 0x7C00 == 0x7C00:
                return
        var features = Set[String]()
        if m[1] != 0:
            features.add("constant " + String((Int(block[1]) >> 1) & 1))
        else:
            var mode = (Int(block[0]) | (Int(block[1]) << 8)) & 2047
            self.modes.add(mode)
            features.add("mode " + String(mode))
            features.add("partitions " + String(m[4]))
            features.add("grid " + String(m[13]) + " " + String(m[14]))
            features.add("weight_levels " + String(m[12]))
            features.add("endpoint_levels " + String(m[11]))
            for index in range(Int(m[4])):
                features.add("endpoint " + String(m[7 + index]))
                self.endpoint_modes.add(Int(m[7 + index]))
            if m[3] != 0:
                features.add("dual " + String(m[6]))
                self.dual_components.add(Int(m[6]))
            # Keep separate coverage for HDR and LDR endpoint/weight
            # combinations.
            features.add("kind_mode " + String(m[2]) + " " + String(mode))
            self.partitions.add(Int(m[4]))
            self.grids.add(Int(m[13]) * 64 + Int(m[14]))
            self.weight_levels.add(Int(m[12]))
            self.endpoint_levels.add(Int(m[11]))
        if not force and features.issubset(self.seen):
            return
        for feature in features:
            self.seen.add(feature)
        self.selected.append(Selected(block.copy(), m^))


def _sorted(values: Set[Int]) -> List[Int]:
    """Return a set's values in increasing order."""
    var out = List[Int]()
    for value in values:
        out.append(value)
    sort(out)
    return out^


def _write_list(mut out: JsonWriter, values: Set[Int]):
    """Write a set's values in increasing order."""
    out.begin_array()
    for value in _sorted(values):
        out.integer(value)
    out.end()


def survey(
    library: String,
    size: Int,
    mut random: PythonRandom,
    mut lines: List[String],
) raises -> Tuple[Survey, Int]:
    """Find the blocks of one size and append their texel records.

    Args:
        library: The adapter library.
        size: The block size.
        random: The random source, shared by both sizes.
        lines: The fixture lines.

    Returns:
        The survey and its record count.

    Raises:
        Error: If the reference refuses a selected block.
    """
    var reference = Reference(library, size)
    var found = Survey(size)
    # All encodable 11-bit layouts. One partition, LDR luminance CEM 0
    # leaves the maximum endpoint budget; invalid modes cannot be rescued
    # by spending more bits on extra partitions or endpoint values.
    var low_bits = (BigInt(1) << 17) - BigInt(1)
    for mode in range(2048):
        var tail = random.getrandbits(128)
        # (tail & ~(2**17 - 1)) | mode
        var value = tail - (tail % (low_bits + BigInt(1))) + BigInt(mode)
        found.inspect(reference, block_bytes(value), True)
    for _ in range(RANDOM_BLOCKS):
        found.inspect(reference, block_bytes(random.getrandbits(128)), False)
    # Exact UNORM rounding boundaries and signed/HDR half constants.
    # Each row: the HDR flag, then four half or UNORM16 colors.
    var constants: List[Int] = [
        0,
        0,
        0xFFFF,
        0x8080,
        0x00FF,
        0,
        0x0100,
        0x7FFF,
        0x8000,
        0xFF00,
        1,
        0x0001,
        0x3C00,
        0x7BFF,
        0x3800,
        1,
        0xBC00,
        0x0000,
        0x4000,
        0x3C00,
    ]
    for row in range(0, len(constants), 5):
        var header = UInt64(0xFFFFFFFFFFFFFDFC) | (UInt64(constants[row]) << 9)
        var block = List[UInt8]()
        for index in range(8):
            block.append(UInt8((header >> UInt64(8 * index)) & 255))
        for color in constants[row + 1 : row + 5]:
            block.append(UInt8(color & 255))
            block.append(UInt8(color >> 8))
        found.inspect(reference, block, True)
    var records = 0
    for item in found.selected:
        var profiles: List[Int] = [0, 1, 2]
        if item.metadata[2] != 0 or (
            item.metadata[1] != 0 and Int(item.block[1]) & 2 != 0
        ):
            profiles = [2]
        for profile in profiles:
            if reference.decode(item.block, profile) != 0:
                raise Error("the reference refused a selected block")
            var count = size * size * (8 if profile == 2 else 4)
            lines.append(
                String(size)
                + " "
                + String(profile)
                + " "
                + hex_text(item.block, 16)
                + " "
                + hex_text(reference.pixels, count)
            )
            records += 1
    reference.close()
    return (found^, records)


def generate(library: String, output: String) raises -> String:
    """Write the fixture, its invalid blocks and its report.

    Args:
        library: The adapter library.
        output: The fixture file. The report replaces its suffix with
            `.json`, and `raw_astc_invalid.txt` goes beside it.

    Returns:
        The summary that the tool prints.

    Raises:
        Error: If the library fails or a file cannot be written.
    """
    var random = PythonRandom(SEED)
    var lines: List[String] = [
        "# Arm astcenc 5.3.0 " + PIN,
        "# size profile(0=UNORM,1=sRGB,2=SFLOAT) block_hex output_hex",
    ]
    var invalid = List[String]()
    var report = JsonWriter()
    report.begin_object()
    report.key("reference_commit")
    report.string(PIN)
    report.key("seed")
    report.integer(SEED)
    report.key("sizes")
    report.begin_object()
    var summary = String("{")
    for size in [4, 6]:
        var result = survey(library, size, random, lines)
        ref found = result[0]
        invalid.extend(found.invalid.copy())
        report.key(String(size))
        report.begin_object()
        report.key("blocks")
        report.integer(len(found.selected))
        report.key("records")
        report.integer(result[1])
        report.key("block_modes")
        _write_list(report, found.modes)
        report.key("endpoint_modes")
        _write_list(report, found.endpoint_modes)
        report.key("partitions")
        _write_list(report, found.partitions)
        report.key("grids")
        report.begin_array()
        for grid in _sorted(found.grids):
            report.begin_array()
            report.integer(grid // 64)
            report.integer(grid % 64)
            report.end()
        report.end()
        report.key("weight_levels")
        _write_list(report, found.weight_levels)
        report.key("endpoint_levels")
        _write_list(report, found.endpoint_levels)
        report.key("dual_components")
        _write_list(report, found.dual_components)
        report.end()
        if size != 4:
            summary += ", "
        summary += (
            '"'
            + String(size)
            + '": {"blocks": '
            + String(len(found.selected))
            + ', "records": '
            + String(result[1])
            + ', "block_modes": '
            + String(len(found.modes))
            + "}"
        )
    report.end()
    var text = "\n".join(lines) + "\n"
    var digest = sha256_hex(text.as_bytes())
    report.key("fixture_sha256")
    report.string(digest)
    report.end()
    var folder = dirname(output)
    if folder:
        makedirs(folder, exist_ok=True)
    Path(output).write_text(text)
    var prefix = folder + "/" if folder else String()
    Path(prefix + "raw_astc_invalid.txt").write_text("\n".join(invalid) + "\n")
    var stem = output
    var name_start = output.rfind("/") + 1
    var dot = output.rfind(".")
    if dot > name_start:
        stem = String(output[byte=:dot])
    Path(stem + ".json").write_text(report.text() + "\n")
    return summary + "}\n" + digest


def main() raises:
    var given = argv()
    if len(given) != 3:
        print("usage: generate_astc LIBRARY OUTPUT", file=stderr)
        exit(2)
    print(generate(String(given[1]), String(given[2])))
