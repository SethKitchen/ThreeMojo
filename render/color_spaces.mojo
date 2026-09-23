# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color spaces and the conversions between them, from three.js
`src/math/ColorManagement.js` and `examples/jsm/math/ColorSpaces.js`.

A color space is two things: the primaries, which say what pure red, green
and blue are, and a transfer function, which says how a stored number maps to
an amount of light. sRGB and Display P3 use the same transfer function and
different primaries. Display P3's red and green are deeper, so a wide-gamut
display shows colors that sRGB cannot store.

A conversion decodes the source's transfer function, carries the color
through CIE XYZ from the source's primaries to the target's, and encodes the
target's transfer function. The step through XYZ is skipped when the
primaries are the same. This is three.js's `ColorManagement.convert`, step
for step.

The spaces are three.js's: sRGB and linear sRGB, which `ColorManagement`
defines, and Display P3, linear Display P3, linear Rec. 2020 and extended
sRGB, which `ColorSpaces.js` adds. The matrices are three.js's, to seven
places. `NO_COLOR_SPACE` is three.js's `NoColorSpace`: a color that is not
color, which no conversion changes.

`render.srgb` holds the transfer function the renderer uses on textures,
written from its definition. The functions here are three.js's
`SRGBToLinear` and `LinearToSRGB`, with three.js's constants, so that a
conversion gives three.js's numbers. The two agree to about one part in
ten thousand.

The arithmetic is in `Float64`, as JavaScript's is, and the answer is stored
in a `FloatColor`. Each product is rounded before it is added, as JavaScript
rounds it: Mojo fuses a multiply and an add by default, which rounds once.

**Difference from three.js.** `conversion_matrix` is the target's matrix from
XYZ times the source's matrix to XYZ, the matrix that `convert` applies.
three.js's internal `_getMatrix` multiplies the two the other way round.
"""

from render.framebuffer import FloatColor
from std.benchmark import black_box
from std.math import pow


@fieldwise_init
struct ColorTransfer(Equatable, ImplicitlyCopyable, Writable):
    """How a stored number maps to an amount of light, as a type rather than
    a bare int. three.js: `LinearTransfer` and `SRGBTransfer`.

    See `core.object3d.NodeId` for why these are wrapped.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the transfer functions below.

        Returns:
            Whether the value names a transfer function.
        """
        return self == LINEAR_TRANSFER or self == SRGB_TRANSFER


# The number is the amount of light.
comptime LINEAR_TRANSFER = ColorTransfer(0)
# The number is sRGB encoded.
comptime SRGB_TRANSFER = ColorTransfer(1)


@fieldwise_init
struct ColorSpaceId(Equatable, ImplicitlyCopyable, Writable):
    """Which color space, as a type rather than a bare int. three.js names a
    color space with a string.

    See `core.object3d.NodeId` for why these are wrapped. This is not
    `render.srgb.ColorSpace`, which says whether a texture decodes.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the color spaces below.

        Returns:
            Whether the value names a color space.
        """
        return self.value >= 0 and self.value <= 6


# three.js's `NoColorSpace`: numbers that are not color.
comptime NO_COLOR_SPACE = ColorSpaceId(0)
# three.js's `SRGBColorSpace`, `'srgb'`.
comptime SRGB_COLOR_SPACE = ColorSpaceId(1)
# three.js's `LinearSRGBColorSpace`, `'srgb-linear'`: the working space.
comptime LINEAR_SRGB_COLOR_SPACE = ColorSpaceId(2)
# `ColorSpaces.js`'s `DisplayP3ColorSpace`, `'display-p3'`.
comptime DISPLAY_P3_COLOR_SPACE = ColorSpaceId(3)
# `ColorSpaces.js`'s `LinearDisplayP3ColorSpace`, `'display-p3-linear'`.
comptime LINEAR_DISPLAY_P3_COLOR_SPACE = ColorSpaceId(4)
# `ColorSpaces.js`'s `LinearRec2020ColorSpace`, `'rec2020-linear'`.
comptime LINEAR_REC2020_COLOR_SPACE = ColorSpaceId(5)
# `ColorSpaces.js`'s `ExtendedSRGBColorSpace`, `'extended-srgb'`: sRGB whose
# values can pass one, for a display that shows brighter than white.
comptime EXTENDED_SRGB_COLOR_SPACE = ColorSpaceId(6)

comptime Row3 = SIMD[DType.float64, 4]
comptime Pair = SIMD[DType.float64, 2]

# Rec. 709 is sRGB's primaries. three.js: `LINEAR_REC709_TO_XYZ` and
# `XYZ_TO_LINEAR_REC709`, row by row, the fourth lane unused.
comptime _REC709_TO_XYZ = (
    Row3(0.4123908, 0.3575843, 0.1804808, 0),
    Row3(0.2126390, 0.7151687, 0.0721923, 0),
    Row3(0.0193308, 0.1191948, 0.9505322, 0),
)
comptime _XYZ_TO_REC709 = (
    Row3(3.2409699, -1.5373832, -0.4986108, 0),
    Row3(-0.9692436, 1.8759675, 0.0415551, 0),
    Row3(0.0556301, -0.2039770, 1.0569715, 0),
)
# three.js: `LINEAR_DISPLAY_P3_TO_XYZ` and `XYZ_TO_LINEAR_DISPLAY_P3`.
comptime _P3_TO_XYZ = (
    Row3(0.4865709, 0.2656677, 0.1982173, 0),
    Row3(0.2289746, 0.6917385, 0.0792869, 0),
    Row3(0.0000000, 0.0451134, 1.0439444, 0),
)
comptime _XYZ_TO_P3 = (
    Row3(2.4934969, -0.9313836, -0.4027108, 0),
    Row3(-0.8294890, 1.7626641, 0.0236247, 0),
    Row3(0.0358458, -0.0761724, 0.9568845, 0),
)
# three.js: `LINEAR_REC2020_TO_XYZ` and `XYZ_TO_LINEAR_REC2020`.
comptime _REC2020_TO_XYZ = (
    Row3(0.6369580, 0.1446169, 0.1688810, 0),
    Row3(0.2627002, 0.6779981, 0.0593017, 0),
    Row3(0.0000000, 0.0280727, 1.0609851, 0),
)
comptime _XYZ_TO_REC2020 = (
    Row3(1.7166512, -0.3556708, -0.2533663, 0),
    Row3(-0.6666844, 1.6164812, 0.0157685, 0),
    Row3(0.0176399, -0.0427706, 0.9421031, 0),
)


@fieldwise_init
struct Primaries(Equatable, ImplicitlyCopyable):
    """The chromaticities of a space's red, green and blue."""

    var red: Pair
    var green: Pair
    var blue: Pair

    def __eq__(self, other: Self) -> Bool:
        """Return whether two sets of primaries are the same.

        Args:
            other: The other set.

        Returns:
            Whether every chromaticity is equal.
        """
        return (
            self.red == other.red
            and self.green == other.green
            and self.blue == other.blue
        )

    def __ne__(self, other: Self) -> Bool:
        """Return whether two sets of primaries differ.

        Args:
            other: The other set.

        Returns:
            Whether any chromaticity differs.
        """
        return not (self == other)


# three.js's `REC709_PRIMARIES`, `P3_PRIMARIES` and `REC2020_PRIMARIES`.
comptime REC709_PRIMARIES = Primaries(
    Pair(0.640, 0.330), Pair(0.300, 0.600), Pair(0.150, 0.060)
)
comptime P3_PRIMARIES = Primaries(
    Pair(0.680, 0.320), Pair(0.265, 0.690), Pair(0.150, 0.060)
)
comptime REC2020_PRIMARIES = Primaries(
    Pair(0.708, 0.292), Pair(0.170, 0.797), Pair(0.131, 0.046)
)
# The white of daylight, three.js's `D65`.
comptime D65 = Pair(0.3127, 0.3290)


struct Matrix3x3(ImplicitlyCopyable):
    """A 3x3 matrix of `Float64`, row by row: a conversion between RGB and
    XYZ."""

    var rows: Tuple[Row3, Row3, Row3]

    def __init__(out self, rows: Tuple[Row3, Row3, Row3]):
        """Create a matrix from its rows.

        Args:
            rows: The rows. The fourth lane of each is not read.
        """
        self.rows = rows

    def get(self, row: Int, column: Int) raises -> Float64:
        """Return one element.

        Args:
            row: The row, 0 to 2.
            column: The column, 0 to 2.

        Returns:
            The element.

        Raises:
            Error: If either index is outside 0 to 2.
        """
        if row < 0 or row > 2 or column < 0 or column > 2:
            raise Error("A 3x3 matrix has rows and columns 0 to 2")
        if row == 0:
            return self.rows[0][column]
        if row == 1:
            return self.rows[1][column]
        return self.rows[2][column]

    def apply(self, r: Float64, g: Float64, b: Float64) -> Row3:
        """Return the matrix times a column. three.js: `Color.applyMatrix3`.

        Args:
            r: The first component.
            g: The second.
            b: The third.

        Returns:
            The product, in the first three lanes.
        """
        return Row3(
            _dot(self.rows[0], r, g, b),
            _dot(self.rows[1], r, g, b),
            _dot(self.rows[2], r, g, b),
            0,
        )

    def times(self, other: Self) -> Self:
        """Return this matrix times another.

        Args:
            other: The matrix on the right, applied first.

        Returns:
            The product.
        """
        return Matrix3x3(
            (
                _row_times(self.rows[0], other),
                _row_times(self.rows[1], other),
                _row_times(self.rows[2], other),
            )
        )


def _dot(row: Row3, r: Float64, g: Float64, b: Float64) -> Float64:
    """Return a row times a column, summed in three.js's order.

    Args:
        row: The row.
        r: The first component.
        g: The second.
        b: The third.

    Returns:
        `row[0] * r + row[1] * g + row[2] * b`.
    """
    return black_box(row[0] * r) + black_box(row[1] * g) + black_box(row[2] * b)


def _row_times(row: Row3, matrix: Matrix3x3) -> Row3:
    """Return a row times a matrix: one row of a product.

    Args:
        row: The row.
        matrix: The matrix.

    Returns:
        The row of the product.
    """
    return (
        matrix.rows[0] * row[0]
        + matrix.rows[1] * row[1]
        + matrix.rows[2] * row[2]
    )


@fieldwise_init
struct ColorSpaceDefinition(ImplicitlyCopyable):
    """What three.js's `ColorManagement.spaces` holds for one space."""

    var primaries: Primaries
    var white_point: Pair
    var transfer: ColorTransfer
    # From linear RGB in this space to CIE XYZ. three.js: `toXYZ`.
    var to_xyz: Matrix3x3
    # From CIE XYZ to linear RGB in this space. three.js: `fromXYZ`.
    var from_xyz: Matrix3x3
    # How much each of linear red, green and blue adds to brightness.
    var luminance_coefficients: Row3
    # Which space a canvas shows this one in, or none. three.js:
    # `outputColorSpaceConfig.drawingBufferColorSpace`.
    var drawing_buffer: Optional[ColorSpaceId]
    # Which space a texture is unpacked to when this one is the working
    # space, or none. three.js: `workingColorSpaceConfig.unpackColorSpace`.
    var unpack: Optional[ColorSpaceId]
    # Whether tone mapping lets values past one through. three.js:
    # `outputColorSpaceConfig.toneMappingMode` is `'extended'`.
    var extended_tone_mapping: Bool


def check_color_space(space: ColorSpaceId) raises:
    """Refuse a value that names no color space.

    Args:
        space: The value.

    Raises:
        Error: If it is not one of the color spaces of this module.
    """
    if not space.is_valid():
        raise Error("Not a color space: " + String(space.value))


def color_space(space: ColorSpaceId) raises -> ColorSpaceDefinition:
    """Return a color space's definition. three.js:
    `ColorManagement.spaces[space]`.

    Args:
        space: The color space.

    Returns:
        Its primaries, white point, transfer function, matrices and
        luminance coefficients.

    Raises:
        Error: If the value names no color space, or it is `NO_COLOR_SPACE`,
            which has no definition.
    """
    check_color_space(space)
    var rec709 = Row3(0.2126, 0.7152, 0.0722, 0)
    if space == SRGB_COLOR_SPACE or space == EXTENDED_SRGB_COLOR_SPACE:
        return ColorSpaceDefinition(
            REC709_PRIMARIES,
            D65,
            SRGB_TRANSFER,
            Matrix3x3(_REC709_TO_XYZ),
            Matrix3x3(_XYZ_TO_REC709),
            rec709,
            SRGB_COLOR_SPACE,
            None,
            space == EXTENDED_SRGB_COLOR_SPACE,
        )
    if space == LINEAR_SRGB_COLOR_SPACE:
        return ColorSpaceDefinition(
            REC709_PRIMARIES,
            D65,
            LINEAR_TRANSFER,
            Matrix3x3(_REC709_TO_XYZ),
            Matrix3x3(_XYZ_TO_REC709),
            rec709,
            SRGB_COLOR_SPACE,
            SRGB_COLOR_SPACE,
            False,
        )
    var p3 = Row3(0.2289, 0.6917, 0.0793, 0)
    if space == DISPLAY_P3_COLOR_SPACE:
        return ColorSpaceDefinition(
            P3_PRIMARIES,
            D65,
            SRGB_TRANSFER,
            Matrix3x3(_P3_TO_XYZ),
            Matrix3x3(_XYZ_TO_P3),
            p3,
            DISPLAY_P3_COLOR_SPACE,
            None,
            False,
        )
    if space == LINEAR_DISPLAY_P3_COLOR_SPACE:
        return ColorSpaceDefinition(
            P3_PRIMARIES,
            D65,
            LINEAR_TRANSFER,
            Matrix3x3(_P3_TO_XYZ),
            Matrix3x3(_XYZ_TO_P3),
            p3,
            DISPLAY_P3_COLOR_SPACE,
            DISPLAY_P3_COLOR_SPACE,
            False,
        )
    if space == LINEAR_REC2020_COLOR_SPACE:
        return ColorSpaceDefinition(
            REC2020_PRIMARIES,
            D65,
            LINEAR_TRANSFER,
            Matrix3x3(_REC2020_TO_XYZ),
            Matrix3x3(_XYZ_TO_REC2020),
            Row3(0.2627, 0.6780, 0.0593, 0),
            None,
            None,
            False,
        )
    raise Error("No color space has no definition")


def color_space_name(space: ColorSpaceId) raises -> String:
    """Return the string three.js names a color space with.

    Args:
        space: The color space.

    Returns:
        The name three.js uses: `'srgb'`, `'display-p3-linear'` and so on, and the
        empty string for `NO_COLOR_SPACE`.

    Raises:
        Error: If the value names no color space.
    """
    check_color_space(space)
    var names: List[String] = [
        "",
        "srgb",
        "srgb-linear",
        "display-p3",
        "display-p3-linear",
        "rec2020-linear",
        "extended-srgb",
    ]
    return names[space.value]


def transfer_of(space: ColorSpaceId) raises -> ColorTransfer:
    """Return a color space's transfer function. three.js:
    `ColorManagement.getTransfer`.

    Args:
        space: The color space.

    Returns:
        Its transfer function. Linear for `NO_COLOR_SPACE`.

    Raises:
        Error: If the value names no color space.
    """
    check_color_space(space)
    if space == NO_COLOR_SPACE:
        return LINEAR_TRANSFER
    return color_space(space).transfer


def srgb_to_linear_three(c: Float64) -> Float64:
    """Return three.js's `SRGBToLinear`, with its constants.

    Args:
        c: An sRGB-encoded channel.

    Returns:
        The linear channel.
    """
    if c < 0.04045:
        return c * 0.0773993808
    return pow(black_box(c * 0.9478672986) + 0.0521327014, 2.4)


def linear_to_srgb_three(c: Float64) -> Float64:
    """Return three.js's `LinearToSRGB`, with its constants.

    Args:
        c: A linear channel.

    Returns:
        The sRGB-encoded channel.
    """
    if c < 0.0031308:
        return c * 12.92
    return black_box(1.055 * pow(c, 0.41666)) - 0.055


def conversion_matrix(
    source: ColorSpaceId, target: ColorSpaceId
) raises -> Matrix3x3:
    """Return the matrix that carries linear RGB from one space's primaries
    to another's: the target's `from_xyz` times the source's `to_xyz`.

    three.js's `_getMatrix` multiplies the two the other way round. See the
    module docstring.

    Args:
        source: The space the color is in.
        target: The space to carry it to.

    Returns:
        The matrix.

    Raises:
        Error: If either names no color space or is `NO_COLOR_SPACE`.
    """
    return color_space(target).from_xyz.times(color_space(source).to_xyz)


def convert(
    color: FloatColor, source: ColorSpaceId, target: ColorSpaceId
) raises -> FloatColor:
    """Return a color converted from one space to another. three.js:
    `ColorManagement.convert`.

    Args:
        color: The color. Its alpha is kept.
        source: The space it is in.
        target: The space to convert it to.

    Returns:
        The converted color. The same color if the two spaces are the
        same, or either is `NO_COLOR_SPACE`.

    Raises:
        Error: If either value names no color space.
    """
    check_color_space(source)
    check_color_space(target)
    var unchanged = (
        source == target or source == NO_COLOR_SPACE or target == NO_COLOR_SPACE
    )
    if unchanged:
        return color
    var from_space = color_space(source)
    var to_space = color_space(target)
    var r = Float64(color.r)
    var g = Float64(color.g)
    var b = Float64(color.b)
    if from_space.transfer == SRGB_TRANSFER:
        r = srgb_to_linear_three(r)
        g = srgb_to_linear_three(g)
        b = srgb_to_linear_three(b)
    if from_space.primaries != to_space.primaries:
        var xyz = from_space.to_xyz.apply(r, g, b)
        var rgb = to_space.from_xyz.apply(xyz[0], xyz[1], xyz[2])
        r = rgb[0]
        g = rgb[1]
        b = rgb[2]
    if to_space.transfer == SRGB_TRANSFER:
        r = linear_to_srgb_three(r)
        g = linear_to_srgb_three(g)
        b = linear_to_srgb_three(b)
    return FloatColor(Float32(r), Float32(g), Float32(b), color.a)
