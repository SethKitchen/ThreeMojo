# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hairstyles: how a head of hair is cut and laid.

`GROWN` is the groom's own hair, grown from the scalp and combed down
to the length `HAIR_LENGTH` asks for. Ten more are designed on the
groom's own guides:

- `LONG`: parted down the middle and falling past the shoulders.
- `PONYTAIL`: gathered to a tie at the back of the head, and a tail
  that springs back from it and falls.
- `BUN`: gathered higher, and coiled round a ball on the tie.
- `HIGH_PONYTAIL`: gathered high on the crown, with a longer tail.
- `PIGTAILS`: parted down the middle and gathered to a tie behind each
  ear.
- `SPACE_BUNS`: parted down the middle and coiled into a bun on each
  side of the crown.
- `BRAID`: gathered at the nape into one braid of three strands.
- `HALF_UP`: the top gathered to a small tail at the back, the rest
  falling long.
- `BOB`: parted down the middle and cut level at the jaw.
- `PIXIE`: cropped short and combed forward and down.

Two are strands an artist groomed, kept in `assets/hair/`:

- `LAYERED`: Sintel's hair, a layered cut to the jaw with a fringe,
  from Sintel Lite 2.57b by BenDansie. (c) the Blender Foundation,
  CC-BY 3.0, durian.blender.org.
- `MOHAWK`: Ratboy's mohawk from AMD TressFX 4.1, MIT license,
  copyright 2017 Advanced Micro Devices, a crest from the brow to the
  nape.

`tools/hair_style.py` converts their TressFX files. A style keeps no
head of its own: each strand's root is a point of the unit cranium,
and its points are offsets in the cranium's frame at the root, in its
mean radius. `HairStyleFile.strand` puts a strand on a person's
cranium, so a style fits every head a genome makes. See
THIRD-PARTY-NOTICES.md.

This is not a three.js port. See Extensions.

    var style = HairStyleFile(hair_style_path(LAYERED))
    var strand = style.strand(dims.head, 0)
"""

from extensions.humanoid.assets import humanoid_asset_path
from extensions.humanoid.skeleton.head.frame import HeadDimensions
from math.vector3 import Vector3

comptime _VERSION = 1
comptime _HEADER = 20
# The cranium a style's roots lie on, in template centimeters: its
# center and its semi-axes across, up and along.
comptime CRANIUM_Y = Float32(75.1)
comptime CRANIUM_Z = Float32(-1.0)
comptime CRANIUM_X_RADIUS = Float32(8.1)
comptime CRANIUM_Y_RADIUS = Float32(9.3)
comptime CRANIUM_Z_RADIUS = Float32(10.6)


@fieldwise_init
struct HairStyle(Equatable, ImplicitlyCopyable, Writable):
    """How a head of hair is cut and laid.

    The type stops a bare integer at compile time. A value that is not a
    named style is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named style."""
        return self.value >= 0 and self.value <= PIXIE.value

    def is_scanned(self) -> Bool:
        """Return True for a style an artist groomed, kept in a file."""
        return self == LAYERED or self == MOHAWK

    def is_designed(self) -> Bool:
        """Return True for a style the groom designs on its guides."""
        return self.is_valid() and self != GROWN and not self.is_scanned()

    def is_tied(self) -> Bool:
        """Return True for a style that gathers all of its hair into
        ties."""
        return (
            self == PONYTAIL
            or self == BUN
            or self == HIGH_PONYTAIL
            or self == PIGTAILS
            or self == SPACE_BUNS
            or self == BRAID
        )

    def ties(self) -> Int:
        """Return how many ties the style gathers its hair to: none, one,
        or one on each side."""
        if self == PIGTAILS or self == SPACE_BUNS:
            return 2
        if self.is_tied() or self == HALF_UP:
            return 1
        return 0


comptime GROWN = HairStyle(0)
comptime LAYERED = HairStyle(1)
comptime MOHAWK = HairStyle(2)
comptime LONG = HairStyle(3)
comptime PONYTAIL = HairStyle(4)
comptime BUN = HairStyle(5)
comptime HIGH_PONYTAIL = HairStyle(6)
comptime PIGTAILS = HairStyle(7)
comptime SPACE_BUNS = HairStyle(8)
comptime BRAID = HairStyle(9)
comptime HALF_UP = HairStyle(10)
comptime BOB = HairStyle(11)
comptime PIXIE = HairStyle(12)


def hair_style_label(style: HairStyle) -> String:
    """Return the name of `style` for error text and tables.

    Args:
        style: A style, named or not.

    Returns:
        Its name in lower case, as `"grown"`, `"high ponytail"` or
        `"pixie"`, or `"hair style"` when `style` is not named.
    """
    var names: List[String] = [
        "grown",
        "layered",
        "mohawk",
        "long",
        "ponytail",
        "bun",
        "high ponytail",
        "pigtails",
        "space buns",
        "braid",
        "half up",
        "bob",
        "pixie",
    ]
    if not style.is_valid():
        return "hair style"
    return names[style.value]


def named_hair_styles() -> List[HairStyle]:
    """Return every named style in a stable order.

    Returns:
        `GROWN` through `PIXIE`.
    """
    var all = List[HairStyle]()
    for value in range(PIXIE.value + 1):  # pragma: no branch
        all.append(HairStyle(value))
    return all^


def hair_style_path(style: HairStyle) raises -> String:
    """Return the file an artist's style is kept in.

    Args:
        style: `LAYERED` or `MOHAWK`.

    Returns:
        The path under `assets/hair/`.

    Raises:
        Error: If `style` is not named, or is grown or designed, and so
            has no file.
    """
    if not style.is_valid():
        raise Error("A hair style must be a named style")
    if not style.is_scanned():
        raise Error("A grown or designed hair style has no file")
    return humanoid_asset_path(
        String("assets/hair/") + hair_style_label(style) + ".bin"
    )


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 32-bit integer at `at`."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def _unit(v: Vector3) -> Vector3:
    """Return `v` scaled to unit length, or `v` where it has none."""
    var length = v.length()
    if length < Float32(1e-12):
        return v
    return v / length


def cranium_frame(
    q: Vector3, radii: Vector3
) -> Tuple[Vector3, Vector3, Vector3]:
    """Return the frame of an ellipsoid where the point `q` of the unit
    sphere lands on it: across, up and along.

    Up is the ellipsoid's normal. Across is plus x made square to it;
    on the midline's pole, where plus x is the normal, plus z instead.
    Along is up crossed with across.

    Args:
        q: A point of the unit sphere.
        radii: The ellipsoid's semi-axes.

    Returns:
        The three unit directions.
    """
    var up = _unit(Vector3(q.x / radii.x, q.y / radii.y, q.z / radii.z))
    var across = Vector3(1, 0, 0) - up * up.x
    if across.dot(across) < Float32(1e-6):
        across = Vector3(0, 0, 1) - up * up.z
    across = _unit(across)
    var along = Vector3(
        up.y * across.z - up.z * across.y,
        up.z * across.x - up.x * across.z,
        up.x * across.y - up.y * across.x,
    )
    return (across, up, along)


struct HairStyleFile(Movable):
    """An artist's style, read from its file: each strand's root on the
    unit cranium and its points' offsets."""

    var count: Int
    var points: Int
    var roots: List[Vector3]
    var offsets: List[Vector3]

    def __init__(out self, path: String) raises:
        """Read a style that `tools/hair_style.py` wrote.

        Args:
            path: The style's file.

        Raises:
            Error: If the file cannot be read, is not a style, or is cut
                short.
        """
        var bytes: List[UInt8]
        with open(path, "r") as source:
            bytes = source.read_bytes()
        if (
            len(bytes) < _HEADER
            or bytes[0] != 84
            or bytes[1] != 72
            or bytes[2] != 82
            or bytes[3] != 83
        ):
            raise Error("Not a hair style: " + path)
        if _u32(bytes, 4) != _VERSION:
            raise Error("The hair style is another version: " + path)
        self.count = _u32(bytes, 8)
        self.points = _u32(bytes, 12)
        if self.count < 1 or self.points < 2:
            raise Error("The hair style has no strands: " + path)
        var roots_at = _HEADER
        var offsets_at = (roots_at + self.count * 6 + 3) // 4 * 4
        var end = offsets_at + self.count * self.points * 6
        if end > len(bytes):
            raise Error("The hair style ends early: " + path)
        var scale = bytes.unsafe_ptr().unsafe_bitcast[Float32]()[
            unsafe_offset=4
        ]
        var shorts = bytes.unsafe_ptr().unsafe_bitcast[Int16]()
        self.roots = List[Vector3](capacity=self.count)
        var unit = Float32(1) / Float32(32767)
        for s in range(self.count):  # pragma: no branch
            var at = roots_at // 2 + 3 * s
            self.roots.append(
                Vector3(
                    Float32(shorts[unsafe_offset=at]) * unit,
                    Float32(shorts[unsafe_offset=at + 1]) * unit,
                    Float32(shorts[unsafe_offset=at + 2]) * unit,
                )
            )
        self.offsets = List[Vector3](capacity=self.count * self.points)
        for k in range(self.count * self.points):  # pragma: no branch
            var at = offsets_at // 2 + 3 * k
            self.offsets.append(
                Vector3(
                    Float32(shorts[unsafe_offset=at]) * scale,
                    Float32(shorts[unsafe_offset=at + 1]) * scale,
                    Float32(shorts[unsafe_offset=at + 2]) * scale,
                )
            )

    def strand(self, h: HeadDimensions, index: Int) raises -> List[Vector3]:
        """Return one strand put on the cranium of `h`.

        The root goes where its point of the unit cranium lands on the
        template's, through the head's frame, so the genome's head genes
        move it; the points follow in the cranium's frame there, in its
        mean radius.

        Args:
            h: Head landmarks.
            index: Which strand, zero through `count` less one.

        Returns:
            Its points from the root to the tip, in the pelvis frame, in
            meters.

        Raises:
            Error: If `index` names no strand.
        """
        if index < 0 or index >= self.count:
            raise Error("The hair style has no such strand")
        var q = self.roots[index]
        var root = h.at(
            q.x * CRANIUM_X_RADIUS,
            CRANIUM_Y + q.y * CRANIUM_Y_RADIUS,
            CRANIUM_Z + q.z * CRANIUM_Z_RADIUS,
        )
        var radii = h.cranium(
            CRANIUM_X_RADIUS, CRANIUM_Y_RADIUS, CRANIUM_Z_RADIUS
        )
        var frame = cranium_frame(q, radii)
        var mean = (radii.x + radii.y + radii.z) / 3
        var points = List[Vector3](capacity=self.points)
        var first = index * self.points
        for k in range(self.points):  # pragma: no branch
            var o = self.offsets[first + k]
            points.append(
                root
                + frame[0] * (o.x * mean)
                + frame[1] * (o.y * mean)
                + frame[2] * (o.z * mean)
            )
        return points^
