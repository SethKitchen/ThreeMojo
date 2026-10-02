# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The data of 3D Gaussian splats, from three.js
`examples/jsm/utils/GaussianSplatUtils.js`.

A splat is a 3D Gaussian: a center, a covariance, a color with an
opacity, and optionally spherical harmonics that change its color with
the direction it is seen from. `GaussianSplatGeometry` holds many of
them in flat arrays, as three.js's splat `BufferGeometry` holds them:

- `centers`: three floats a splat, three.js's `position`.
- `covariances`: six floats a splat, the upper triangle of the symmetric
  covariance, `c00 c01 c02 c11 c12 c22`, three.js's `covariance`.
- `colors`: four bytes a splat, red, green, blue and opacity, read as
  byte / 255, three.js's normalized `color`.
- `sh1`, `sh2` and `sh3`: the higher spherical harmonics bands, one
  list of bytes each. A band of degree `d` has `sh_band_components(d)`
  coefficients a splat, three channels each, coefficient by coefficient:
  `r0 g0 b0 r1 g1 b1 ...`. A byte `b` stands for `(b - 128) / 128`. Each
  splat takes `sh_band_words(d)` 32-bit words, so the bytes a band holds
  for a splat are four times that; the bytes past the coefficients stay
  128. three.js packs the same bytes into a `Uint32Array`, and
  `band_words` returns that view.

The file formats store a scale and a rotation instead of a covariance.
`write_covariance` makes one from the other, as three.js does: the matrix
`M = R S` of the quaternion's rotation and the scale, and the covariance
`M M^T`, in 64-bit floats and then stored as 32-bit ones.

Colors are stored through `clamped_byte`, which is how a
`Uint8ClampedArray` stores a number: clamped to 0 through 255 and rounded
half to even.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from math.utils import FLOAT32_COMPONENT, UINT32_COMPONENT, UINT8_COMPONENT
from std.math import exp, floor, isnan, sqrt

# The zeroth-band spherical harmonics constant, `1 / (2 sqrt(pi))`.
comptime SH_C0 = Float64(0.2820947917738781)
# The highest band a splat carries.
comptime MAX_SH_DEGREE = 3
# The name of the covariance attribute in a `BufferGeometry`.
comptime COVARIANCE = "covariance"
# What an unset band byte holds: the coefficient zero.
comptime SH_ZERO_BYTE = UInt8(128)


def sh_band_components(degree: Int) raises -> Int:
    """Return how many numbers a splat holds in one spherical harmonics
    band, three.js's `SH_BAND_COMPONENTS`.

    Args:
        degree: The band, 0 through 3.

    Returns:
        0, 9, 15 or 21: the band's `2 d + 1` coefficients, three channels
        each, and none for the zeroth band, which is the color.

    Raises:
        Error: If the degree is not 0 through 3.
    """
    _check_degree(degree)
    if degree == 0:
        return 0
    return (2 * degree + 1) * 3


def sh_band_words(degree: Int) raises -> Int:
    """Return how many 32-bit words a splat takes in one band, three.js's
    `SH_BAND_WORDS`.

    Args:
        degree: The band, 0 through 3.

    Returns:
        0, 3, 4 or 6: enough four-byte words for the band's numbers.

    Raises:
        Error: If the degree is not 0 through 3.
    """
    return (sh_band_components(degree) + 3) // 4


def _check_degree(degree: Int) raises:
    """Refuse a spherical harmonics degree that is not 0 through 3.

    Args:
        degree: The degree.

    Raises:
        Error: If it is below 0 or above 3.
    """
    if degree < 0 or degree > MAX_SH_DEGREE:
        raise Error(
            "Gaussian splat: spherical harmonics degree "
            + String(degree)
            + " is not 0 through 3"
        )


def sigmoid(value: Float64) -> Float64:
    """Return the logistic function, three.js's `sigmoid`.

    Args:
        value: Any number.

    Returns:
        `1 / (1 + exp(-value))`.
    """
    return 1 / (1 + exp(-value))


def sh0_to_linear(coefficient: Float64) -> Float64:
    """Return the color a zeroth-band coefficient stands for, three.js's
    `sh0ToLinear`.

    Args:
        coefficient: The coefficient.

    Returns:
        `coefficient * SH_C0 + 0.5`.
    """
    return coefficient * SH_C0 + 0.5


def linear_to_sh0(color: Float64) -> Float64:
    """Return the zeroth-band coefficient of a color, three.js's
    `linearToSH0`.

    Args:
        color: The color channel.

    Returns:
        `(color - 0.5) / SH_C0`.
    """
    return (color - 0.5) / SH_C0


def clamped_byte(value: Float64) -> UInt8:
    """Return what a `Uint8ClampedArray` stores for a number.

    Args:
        value: Any number.

    Returns:
        Zero for NaN and anything below zero, 255 for anything above 255,
        and otherwise the nearest integer, a half going to the even one.
    """
    if isnan(value) or value <= 0:
        return 0
    if value >= 255:
        return 255
    var low = floor(value)
    var fraction = value - low
    if fraction > 0.5:
        return UInt8(Int(low) + 1)
    if fraction < 0.5:
        return UInt8(Int(low))
    return UInt8(Int(low) + Int(low) % 2)


def write_covariance(
    mut target: List[Float32],
    offset: Int,
    sx: Float64,
    sy: Float64,
    sz: Float64,
    qx: Float64,
    qy: Float64,
    qz: Float64,
    qw: Float64,
):
    """Write the covariance of a scale and a rotation, three.js's
    `writeCovariance`.

    The quaternion is normalized first, and a quaternion of length zero is
    the identity, as three.js's `Quaternion.normalize` makes it. The matrix
    is `Matrix4.compose` of that rotation and the scale, and the covariance
    is its upper 3 by 3 times its own transpose.

    Args:
        target: The covariances. Six floats are written at `offset`.
        offset: Where the splat's six floats start.
        sx: The scale along the splat's x axis.
        sy: The scale along its y axis.
        sz: The scale along its z axis.
        qx: The rotation's x.
        qy: The rotation's y.
        qz: The rotation's z.
        qw: The rotation's w.
    """
    var length = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    var x = Float64(0)
    var y = Float64(0)
    var z = Float64(0)
    var w = Float64(1)
    if length != 0:
        var inverse = 1 / length
        x = qx * inverse
        y = qy * inverse
        z = qz * inverse
        w = qw * inverse
    var x2 = x + x
    var y2 = y + y
    var z2 = z + z
    var xx = x * x2
    var xy = x * y2
    var xz = x * z2
    var yy = y * y2
    var yz = y * z2
    var zz = z * z2
    var wx = w * x2
    var wy = w * y2
    var wz = w * z2
    # The rows of M = R S: M[r][c] is Matrix4.compose's te[c * 4 + r].
    var m00 = (1 - (yy + zz)) * sx
    var m10 = (xy + wz) * sx
    var m20 = (xz - wy) * sx
    var m01 = (xy - wz) * sy
    var m11 = (1 - (xx + zz)) * sy
    var m21 = (yz + wx) * sy
    var m02 = (xz + wy) * sz
    var m12 = (yz - wx) * sz
    var m22 = (1 - (xx + yy)) * sz
    target[offset] = Float32(m00 * m00 + m01 * m01 + m02 * m02)
    target[offset + 1] = Float32(m00 * m10 + m01 * m11 + m02 * m12)
    target[offset + 2] = Float32(m00 * m20 + m01 * m21 + m02 * m22)
    target[offset + 3] = Float32(m10 * m10 + m11 * m11 + m12 * m12)
    target[offset + 4] = Float32(m10 * m20 + m11 * m21 + m12 * m22)
    target[offset + 5] = Float32(m20 * m20 + m21 * m21 + m22 * m22)


def write_color_bytes(
    mut target: List[UInt8],
    offset: Int,
    r: Float64,
    g: Float64,
    b: Float64,
    a: Float64,
):
    """Write four numbers as clamped bytes, three.js's `writeColorBytes`.

    Args:
        target: The colors. Four bytes are written at `offset`.
        offset: Where the splat's four bytes start.
        r: Red, 0 through 255.
        g: Green, 0 through 255.
        b: Blue, 0 through 255.
        a: Opacity, 0 through 255.
    """
    target[offset] = clamped_byte(r)
    target[offset + 1] = clamped_byte(g)
    target[offset + 2] = clamped_byte(b)
    target[offset + 3] = clamped_byte(a)


def write_color_bytes_from_sh0(
    mut target: List[UInt8],
    offset: Int,
    r: Float64,
    g: Float64,
    b: Float64,
    a: Float64,
):
    """Write a color given as zeroth-band coefficients and an opacity,
    three.js's `writeColorBytesFromSH0`.

    Args:
        target: The colors. Four bytes are written at `offset`.
        offset: Where the splat's four bytes start.
        r: Red's coefficient.
        g: Green's coefficient.
        b: Blue's coefficient.
        a: The opacity, 0 through 1.
    """
    write_color_bytes(
        target,
        offset,
        sh0_to_linear(r) * 255,
        sh0_to_linear(g) * 255,
        sh0_to_linear(b) * 255,
        a * 255,
    )


def packed_band(count: Int, degree: Int) raises -> List[UInt8]:
    """Return a band of spherical harmonics bytes with every coefficient
    zero, three.js's `createPackedSphericalHarmonicsBand`.

    Args:
        count: How many splats.
        degree: The band, 1 through 3.

    Returns:
        `count * sh_band_words(degree) * 4` bytes of 128.

    Raises:
        Error: If the degree is not 1 through 3, or the count is negative.
    """
    if degree < 1:
        raise Error("Gaussian splat: a packed band has a degree of 1 to 3")
    if count < 0:
        raise Error("Gaussian splat: a splat count cannot be negative")
    return List[UInt8](
        length=count * sh_band_words(degree) * 4, fill=SH_ZERO_BYTE
    )


def band_words(bytes: List[UInt8]) raises -> List[UInt32]:
    """Return a band's bytes as three.js packs them: little-endian 32-bit
    words.

    Args:
        bytes: The band's bytes.

    Returns:
        One word per four bytes.

    Raises:
        Error: If the length is not a whole number of words.
    """
    if len(bytes) % 4 != 0:
        raise Error("Gaussian splat: a band is not a whole number of words")
    var words = List[UInt32](capacity=len(bytes) // 4)
    for at in range(0, len(bytes), 4):
        words.append(
            UInt32(bytes[at])
            | (UInt32(bytes[at + 1]) << 8)
            | (UInt32(bytes[at + 2]) << 16)
            | (UInt32(bytes[at + 3]) << 24)
        )
    return words^


struct GaussianSplatGeometry(Copyable, Movable):
    """Many Gaussian splats in flat arrays; see the module docstring.

    Build one with `create_gaussian_splat_geometry`, which checks the
    lengths agree."""

    var centers: List[Float32]
    var covariances: List[Float32]
    var colors: List[UInt8]
    var sh1: List[UInt8]
    var sh2: List[UInt8]
    var sh3: List[UInt8]

    def __init__(out self):
        """Start with no splats."""
        self.centers = List[Float32]()
        self.covariances = List[Float32]()
        self.colors = List[UInt8]()
        self.sh1 = List[UInt8]()
        self.sh2 = List[UInt8]()
        self.sh3 = List[UInt8]()

    def count(self) -> Int:
        """Return how many splats there are."""
        return len(self.centers) // 3

    def spherical_harmonics_degree(self) -> Int:
        """Return the highest band the splats carry, three.js's
        `getSphericalHarmonicsDegree`: 0 when they carry only a color."""
        if len(self.sh3) > 0:
            return 3
        if len(self.sh2) > 0:
            return 2
        if len(self.sh1) > 0:
            return 1
        return 0

    def band_byte(self, degree: Int, splat: Int, index: Int) raises -> UInt8:
        """Return one stored byte of a band.

        Args:
            degree: The band, 1 through 3.
            splat: Which splat.
            index: Which number of the band, 0 up to the band's components.

        Returns:
            The byte.

        Raises:
            Error: If the splats carry no such band, or either index is out
                of range.
        """
        if degree < 1 or degree > self.spherical_harmonics_degree():
            raise Error(
                "Gaussian splat: no spherical harmonics band " + String(degree)
            )
        if splat < 0 or splat >= self.count():
            raise Error("Gaussian splat: no splat " + String(splat))
        if index < 0 or index >= sh_band_components(degree):
            raise Error("Gaussian splat: no band number " + String(index))
        var at = splat * sh_band_words(degree) * 4 + index
        if degree == 1:
            return self.sh1[at]
        if degree == 2:
            return self.sh2[at]
        return self.sh3[at]

    def to_buffer_geometry(self) raises -> BufferGeometry:
        """Return the splats as three.js's splat `BufferGeometry` holds them.

        Returns:
            A geometry with `position`, `covariance`, a normalized
            eight-bit `color` and one `sphericalHarmonicsN` attribute of
            32-bit words for each band, of item size `sh_band_words(N)`.

        Raises:
            Error: If the arrays do not agree; see
                `create_gaussian_splat_geometry`.
        """
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(self.centers.copy(), 3)
        )
        geometry.set_attribute(
            String(COVARIANCE), BufferAttribute(self.covariances.copy(), 6)
        )
        var colors = List[Int](capacity=len(self.colors))
        for at in range(len(self.colors)):
            colors.append(Int(self.colors[at]))
        geometry.set_attribute(
            String(COLOR), BufferAttribute(colors, 4, UINT8_COMPONENT, True)
        )
        for degree in range(1, self.spherical_harmonics_degree() + 1):
            var words = List[Int]()
            for word in band_words(self._band(degree)):  # pragma: no branch
                words.append(Int(word))
            geometry.set_attribute(
                "sphericalHarmonics" + String(degree),
                BufferAttribute(words, sh_band_words(degree), UINT32_COMPONENT),
            )
        return geometry^

    def _band(self, degree: Int) -> List[UInt8]:
        """Return a copy of one band's bytes.

        Args:
            degree: The band, 1 through 3.

        Returns:
            The bytes.
        """
        if degree == 1:
            return self.sh1.copy()
        if degree == 2:
            return self.sh2.copy()
        return self.sh3.copy()


def create_gaussian_splat_geometry(
    var centers: List[Float32],
    var covariances: List[Float32],
    var colors: List[UInt8],
    var sh1: List[UInt8] = List[UInt8](),
    var sh2: List[UInt8] = List[UInt8](),
    var sh3: List[UInt8] = List[UInt8](),
) raises -> GaussianSplatGeometry:
    """Hold splat arrays as a geometry, three.js's
    `createGaussianSplatGeometry`.

    Args:
        centers: Three floats a splat.
        covariances: Six floats a splat.
        colors: Four bytes a splat.
        sh1: The first band's bytes, or none.
        sh2: The second band's bytes, or none.
        sh3: The third band's bytes, or none.

    Returns:
        The geometry.

    Raises:
        Error: If the centers are not whole splats, the covariances or the
            colors are not as many splats, a band is not
            `count * sh_band_words(d) * 4` bytes, or a band is given
            without the bands below it.
    """
    if len(centers) % 3 != 0:
        raise Error("Gaussian splat: the centers are not whole splats")
    var count = len(centers) // 3
    if len(covariances) != count * 6:
        raise Error("Gaussian splat: the covariances are not one a splat")
    if len(colors) != count * 4:
        raise Error("Gaussian splat: the colors are not one a splat")
    _check_band(sh1, count, 1)
    _check_band(sh2, count, 2)
    _check_band(sh3, count, 3)
    # three.js: `Spherical harmonics attributes must be contiguous.`
    var missing = len(sh1) == 0
    if len(sh2) > 0 and missing:
        raise Error(
            "Gaussian splat: spherical harmonics bands must be contiguous"
        )
    missing = missing or len(sh2) == 0
    if len(sh3) > 0 and missing:
        raise Error(
            "Gaussian splat: spherical harmonics bands must be contiguous"
        )
    var geometry = GaussianSplatGeometry()
    geometry.centers = centers^
    geometry.covariances = covariances^
    geometry.colors = colors^
    geometry.sh1 = sh1^
    geometry.sh2 = sh2^
    geometry.sh3 = sh3^
    return geometry^


def _check_band(band: List[UInt8], count: Int, degree: Int) raises:
    """Refuse a band that is not empty and not the right length.

    Args:
        band: The band's bytes.
        count: How many splats.
        degree: The band.

    Raises:
        Error: If the band has bytes and not `count * words * 4` of them.
    """
    if len(band) == 0:
        return
    if len(band) != count * sh_band_words(degree) * 4:
        raise Error(
            "Gaussian splat: invalid sphericalHarmonics"
            + String(degree)
            + " packed length"
        )


def spherical_harmonics_degree(geometry: BufferGeometry) raises -> Int:
    """Return the highest band a splat `BufferGeometry` carries, three.js's
    `getSphericalHarmonicsDegree`.

    Args:
        geometry: The geometry.

    Returns:
        The number of `sphericalHarmonicsN` attributes, 0 through 3.

    Raises:
        Error: If a band's item size is not `sh_band_words(N)`, it is not
            stored as 32-bit words, a band is present above a missing one,
            or a band's count is not the positions' count.
    """
    var degree = 0
    for band in range(1, MAX_SH_DEGREE + 1):  # pragma: no branch
        var name = "sphericalHarmonics" + String(band)
        if not geometry.has_attribute(name):
            break
        ref attribute = geometry.attribute_view(name)
        if attribute.item_size != sh_band_words(band):
            raise Error(
                "Gaussian splat: invalid sphericalHarmonics"
                + String(band)
                + " item size"
            )
        if attribute.component_type() != UINT32_COMPONENT:
            raise Error(
                "Gaussian splat: sphericalHarmonics"
                + String(band)
                + " must use packed 32-bit words"
            )
        degree = band
    for band in range(degree + 1, MAX_SH_DEGREE + 1):
        if geometry.has_attribute("sphericalHarmonics" + String(band)):
            raise Error(
                "Gaussian splat: spherical harmonics bands must be contiguous"
            )
    if not geometry.has_attribute(String(POSITION)):
        return degree
    var count = geometry.attribute_view(String(POSITION)).count()
    for band in range(1, degree + 1):
        var name = "sphericalHarmonics" + String(band)
        if geometry.attribute_view(name).count() != count:
            raise Error(
                "Gaussian splat: spherical harmonics counts must match position"
            )
    return degree


def gaussian_splat_geometry_of(
    geometry: BufferGeometry,
) raises -> GaussianSplatGeometry:
    """Read a splat `BufferGeometry` back, what three.js's `GaussianSplat`
    reads from the geometry it is given.

    Args:
        geometry: A geometry with `position`, `covariance`, a four-channel
            `color` and any `sphericalHarmonicsN` attributes.

    Returns:
        The splats. A color is read as three.js's `getX` reads it and
        stored as `clamped_byte(value * 255)`, which gives an eight-bit
        normalized color's bytes back exactly.

    Raises:
        Error: If an attribute is missing or of the wrong item size, or
            anything `spherical_harmonics_degree` or
            `create_gaussian_splat_geometry` raises.
    """
    var degree = spherical_harmonics_degree(geometry)
    ref position = geometry.attribute_view(String(POSITION))
    ref covariance = geometry.attribute_view(String(COVARIANCE))
    ref color = geometry.attribute_view(String(COLOR))
    if position.item_size != 3:
        raise Error("Gaussian splat: position must have three components")
    if covariance.item_size != 6:
        raise Error("Gaussian splat: covariance must have six components")
    if color.item_size != 4:
        raise Error("Gaussian splat: color must have four components")
    var channels = color.packed()
    var colors = List[UInt8](capacity=len(channels))
    for at in range(len(channels)):
        colors.append(clamped_byte(Float64(channels[at]) * 255))
    var bands = List[List[UInt8]]()
    for band in range(1, MAX_SH_DEGREE + 1):  # pragma: no branch
        var bytes = List[UInt8]()
        if band <= degree:
            var name = "sphericalHarmonics" + String(band)
            for word in geometry.attribute_view(name).stored_values():
                for shift in range(4):  # pragma: no branch
                    bytes.append(UInt8((word >> (shift * 8)) & 255))
        bands.append(bytes^)
    return create_gaussian_splat_geometry(
        position.packed(),
        covariance.packed(),
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )
