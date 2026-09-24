# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""IES light profiles, from three.js `examples/jsm/loaders/IESLoader.js`.

An IES file (IESNA LM-63) says how bright a lamp is in each direction:
its candela at a list of vertical angles, for each of a list of
horizontal angles. `parse_ies` reads it into an `IesLamp` as three.js's
`IESLamp` does, and `ies_values` samples it at each whole degree, as
three.js's `_getIESValues` does, for its `DataTexture`.

**What is read.** Lines up to the one with `TILT`. With `TILT=INCLUDE`,
the tilt data: the lamp-to-luminaire geometry, the number of angles, the
angles and their factors. Then the ten lamp values, the three factors,
the vertical and horizontal angles, and the candela values. Numbers are
split by white space and commas, and read over as many lines as they
take, as three.js's `readArray` reads them.

**The values.** three.js multiplies each candela value by itself and by
the multiplier, and divides every one by the largest, so the brightest
is one. `ies_values` gives 360 rows of 180, one row for each whole
horizontal degree and one value for each whole vertical degree,
interpolated as three.js interpolates them. A profile of one quadrant or
one half fills only the rows its angles reach: three.js writes a mirrored
row where the mirror is, and leaves the rows past its angles empty.
They are NaN here.

**The texture.** `ies_texture` stores the values as three.js's `type`
says: bytes, halves or floats. three.js gives its `DataTexture` a width
of 180 and a height of one, and 64800 values; the texture here is 180
wide and 360 high. An empty row is zero in each type, as three.js's
bytes and halves have it; three.js's floats have NaN there.

**Where this port differs.** A value that is not a number, which three.js
reads as `NaN`, is refused, and so is a line with more numbers than an
array needs, which three.js reads past until the file runs out and it
throws. So is a file with no `TILT` line, a count that is not a whole
number, and a file that ends early. An empty line is zero, as
`Number("")` is in JavaScript.
"""

from render.exr import half_to_float
from render.srgb import LINEAR
from render.texture import BILINEAR, IGNORED, Texture, float_texture
from std.math import floor, isfinite, isnan, nan
from std.memory import bitcast
from std.pathlib import Path

comptime IES_WIDTH = 360
comptime IES_HEIGHT = 180


@fieldwise_init
struct IesType(Equatable, ImplicitlyCopyable, Writable):
    """The type three.js stores the values as, its `type`, as a type
    rather than a bare int.

    `ies_texture` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three types."""
        return self.value >= IES_UNSIGNED_BYTE.value and (
            self.value <= IES_FLOAT.value
        )


comptime IES_UNSIGNED_BYTE = IesType(0)
comptime IES_HALF_FLOAT = IesType(1)
comptime IES_FLOAT = IesType(2)


struct IesLamp(Copyable, Movable):
    """A profile, three.js's `IESLamp`."""

    var count: Float64
    var lumens: Float64
    var multiplier: Float64
    var num_ver_angles: Int
    var num_hor_angles: Int
    var gonio_type: Float64
    var units: Float64
    var width: Float64
    var length: Float64
    var height: Float64
    var ball_factor: Float64
    var blp_factor: Float64
    var input_watts: Float64
    # The `TILT=INCLUDE` data, empty otherwise.
    var lamp_to_lum_geometry: Float64
    var tilt_angles: List[Float64]
    var tilt_factors: List[Float64]
    # Degrees.
    var ver_angles: List[Float64]
    var hor_angles: List[Float64]
    # One list of vertical values for each horizontal angle, squared,
    # multiplied and made to peak at one.
    var candela: List[List[Float64]]

    def __init__(out self):
        """Start empty."""
        self.count = 0
        self.lumens = 0
        self.multiplier = 0
        self.num_ver_angles = 0
        self.num_hor_angles = 0
        self.gonio_type = 0
        self.units = 0
        self.width = 0
        self.length = 0
        self.height = 0
        self.ball_factor = 0
        self.blp_factor = 0
        self.input_watts = 0
        self.lamp_to_lum_geometry = 0
        self.tilt_angles = List[Float64]()
        self.tilt_factors = List[Float64]()
        self.ver_angles = List[Float64]()
        self.hor_angles = List[Float64]()
        self.candela = List[List[Float64]]()


def _js_number(text: String) raises -> Float64:
    """Return JavaScript's `Number(text)` for one number of a line.

    Raises:
        Error: If it is not a finite number, where JavaScript gives NaN.
    """
    if text.byte_length() == 0:
        return 0
    var value: Float64
    try:
        value = Float64(text)
    except:
        raise Error("IES: `" + text + "` is not a number")
    if not isfinite(value):
        raise Error("IES: `" + text + "` is not a number")
    return value


def _is_space(byte: UInt8) -> Bool:
    """Return True for an ASCII white space byte."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def _tokens(line: String) -> List[String]:
    """Return a line's numbers as three.js's `textToArray` splits them:
    trimmed, commas as spaces, each run of two or more white space bytes
    as one space, and split on a space. A lone tab stays inside its
    token, as it does in three.js."""
    var bytes = String(line.strip()).replace(",", " ").as_bytes()
    var text = String()
    var i = 0
    while i < len(bytes):
        var end = i
        while _space_at(bytes, end):
            end += 1
        if end - i >= 2:
            text += " "
            i = end
        else:
            text += chr(Int(bytes[i]))
            i += 1
    var out = List[String]()
    for token in text.split(" "):  # pragma: no branch
        out.append(String(token))
    return out^


def _space_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a white space byte at `i`."""
    return i < len(bytes) and _is_space(bytes[i])


struct _Lines:
    """The lines of a file, read as three.js's `IESLamp` reads them."""

    var lines: List[String]
    var at: Int

    def __init__(out self, text: String):
        """Split a text on line feeds."""
        self.lines = List[String]()
        for line in text.split("\n"):  # pragma: no branch
            self.lines.append(String(line))
        self.at = 0

    def next(mut self) raises -> String:
        """Return the next line.

        Raises:
            Error: If the file has no more.
        """
        if self.at >= len(self.lines):
            raise Error("IES: the file ends early")
        self.at += 1
        return self.lines[self.at - 1]

    def array(mut self, count: Int) raises -> List[Float64]:
        """Read `count` numbers over as many lines as they take, three.js's
        `readArray`.

        Raises:
            Error: If a number is not one, a line runs past `count`, or
                the file ends first.
        """
        var out = List[Float64]()
        self._append(out)
        while len(out) < count:
            self._append(out)
        if len(out) > count:
            raise Error("IES: a line has more numbers than its array")
        return out^

    def _append(mut self, mut out: List[Float64]) raises:
        """Add the numbers of the next line."""
        # A split gives at least one token: the loop always runs.
        for token in _tokens(self.next()):  # pragma: no branch
            out.append(_js_number(token))


def _count(value: Float64, what: String) raises -> Int:
    """Return a count read as a number.

    Raises:
        Error: If it is not a whole number of zero or more.
    """
    var whole = value >= 0 and floor(value) == value
    if not whole:
        raise Error("IES: " + what + " is not a whole number")
    return Int(value)


def parse_ies(text: String) raises -> IesLamp:
    """Read an IES file's text, three.js's `IESLamp`.

    Args:
        text: The file.

    Returns:
        The lamp, its candela values normalized.

    Raises:
        Error: For anything the module docstring lists.
    """
    var lines = _Lines(text)
    var line = lines.next()
    while "TILT" not in line:
        line = lines.next()
    var lamp = IesLamp()
    var include = "NONE" not in line and "INCLUDE" in line
    if include:
        lamp.lamp_to_lum_geometry = _js_number(_tokens(lines.next())[0])
        var angles = _count(
            _js_number(_tokens(lines.next())[0]), "the number of tilt angles"
        )
        lamp.tilt_angles = lines.array(angles)
        lamp.tilt_factors = lines.array(angles)
    var values = lines.array(10)
    lamp.count = values[0]
    lamp.lumens = values[1]
    lamp.multiplier = values[2]
    lamp.num_ver_angles = _count(values[3], "the number of vertical angles")
    lamp.num_hor_angles = _count(values[4], "the number of horizontal angles")
    lamp.gonio_type = values[5]
    lamp.units = values[6]
    lamp.width = values[7]
    lamp.length = values[8]
    lamp.height = values[9]
    var factors = lines.array(3)
    lamp.ball_factor = factors[0]
    lamp.blp_factor = factors[1]
    lamp.input_watts = factors[2]
    lamp.ver_angles = lines.array(lamp.num_ver_angles)
    lamp.hor_angles = lines.array(lamp.num_hor_angles)
    # `lines.array` refuses a count of zero, since a line has one number
    # or more: each of these loops runs.
    for _ in range(lamp.num_hor_angles):  # pragma: no branch
        lamp.candela.append(lines.array(lamp.num_ver_angles))
    var largest = Float64(-1)
    for i in range(lamp.num_hor_angles):  # pragma: no branch
        for j in range(lamp.num_ver_angles):  # pragma: no branch
            ref v = lamp.candela[i][j]
            v *= v * lamp.multiplier
            largest = v if largest < v else largest
    if largest > 0:
        for i in range(lamp.num_hor_angles):  # pragma: no branch
            for j in range(lamp.num_ver_angles):  # pragma: no branch
                lamp.candela[i][j] /= largest
    return lamp^


def _lerp(x: Float64, y: Float64, t: Float64) -> Float64:
    """Return three.js's `MathUtils.lerp`, each product rounded before the
    sum as JavaScript rounds it."""
    return _product(1 - t, x) + _product(t, y)


@no_inline
def _product(a: Float64, b: Float64) -> Float64:
    """Return `a * b` rounded, where the compiler cannot fuse it into a
    multiply-add."""
    return a * b


def _interpolate(lamp: IesLamp, phi: Float64, theta: Float64) -> Float64:
    """Return the value at a vertical and a horizontal angle, three.js's
    `interpolateCandelaValues`."""
    var theta_index = 0
    var phi_index = 0
    var start_theta = Float64(0)
    var end_theta = Float64(0)
    var start_phi = Float64(0)
    var end_phi = Float64(0)
    for i in range(lamp.num_hor_angles - 1):
        var here = (
            theta < lamp.hor_angles[i + 1] or i == lamp.num_hor_angles - 2
        )
        if here:
            theta_index = i
            start_theta = lamp.hor_angles[i]
            end_theta = lamp.hor_angles[i + 1]
            break
    for i in range(lamp.num_ver_angles - 1):
        var here = phi < lamp.ver_angles[i + 1] or i == lamp.num_ver_angles - 2
        if here:
            phi_index = i
            start_phi = lamp.ver_angles[i]
            end_phi = lamp.ver_angles[i + 1]
            break
    var delta_theta = end_theta - start_theta
    var delta_phi = end_phi - start_phi
    if delta_phi == 0:
        return 0
    var t1 = 0.0 if delta_theta == 0 else (theta - start_theta) / delta_theta
    var t2 = (phi - start_phi) / delta_phi
    var next_theta = theta_index if delta_theta == 0 else theta_index + 1
    ref c = lamp.candela
    var v1 = _lerp(c[theta_index][phi_index], c[next_theta][phi_index], t1)
    var v2 = _lerp(
        c[theta_index][phi_index + 1], c[next_theta][phi_index + 1], t1
    )
    return _lerp(v1, v2, t2)


def _js_rem(a: Float64, b: Float64) -> Float64:
    """Return JavaScript's `a % b`: the remainder with the sign of `a`."""
    var r = a % b
    var wrong = r != 0 and (r < 0) != (a < 0)
    if wrong:
        r -= b
    return r


def ies_values(lamp: IesLamp) raises -> List[Float64]:
    """Return the lamp at each whole degree, three.js's `_getIESValues`
    before it is typed.

    Args:
        lamp: The lamp.

    Returns:
        360 rows of 180 values, `phi + theta * 180`, NaN where three.js
        leaves a row empty.

    Raises:
        Error: If the lamp has no horizontal angle, where three.js reads
            `undefined`.
    """
    if lamp.num_hor_angles < 1:
        raise Error("IES: a lamp with no horizontal angle")
    var size = IES_WIDTH * IES_HEIGHT
    var data = List[Float64](length=size, fill=nan[DType.float64]())
    var start_theta = lamp.hor_angles[0]
    var end_theta = lamp.hor_angles[lamp.num_hor_angles - 1]
    for i in range(size):  # pragma: no branch
        var theta = Float64(i % IES_WIDTH)
        var phi = Float64(i // IES_WIDTH)
        var outside = end_theta - start_theta != 0 and (
            theta < start_theta or theta >= end_theta
        )
        if outside:
            theta = _js_rem(theta, end_theta * 2)
            if theta > end_theta:
                theta = end_theta * 2 - theta
        var index = phi + theta * IES_HEIGHT
        var slot = (
            index >= 0 and index < Float64(size) and (floor(index) == index)
        )
        if slot:
            data[Int(index)] = _interpolate(lamp, phi, theta)
    return data^


def to_half_float(value: Float64) -> UInt16:
    """Return the half bits of a value, three.js's `DataUtils.toHalfFloat`:
    clamped to the half's range, made a `Float32`, and its mantissa cut,
    not rounded.

    Args:
        value: The value.

    Returns:
        The half's sixteen bits.
    """
    var clamped = value
    if value > 65504:
        clamped = 65504
    elif value < -65504:
        clamped = -65504
    var f = Int(bitcast[DType.uint32](Float32(clamped)))
    var e = (f >> 23) & 0x1FF
    var sign = 0x8000 if e >= 256 else 0
    var exponent = (e & 0xFF) - 127
    var base: Int
    var shift: Int
    if exponent < -27:
        base = sign
        shift = 24
    elif exponent < -14:
        base = (0x0400 >> (-exponent - 14)) | sign
        shift = -exponent - 1
    elif exponent <= 15:
        base = ((exponent + 15) << 10) | sign
        shift = 13
    else:
        # After the clamp, only NaN is left here. three.js's table for an
        # exponent from 16 to 127 is never reached for the same reason.
        base = 0x7C00 | sign
        shift = 13
    return UInt16(base + ((f & 0x007FFFFF) >> shift))


def ies_byte(value: Float64) -> UInt8:
    """Return a value as three.js's `UnsignedByteType` holds it:
    `Math.min( v * 0xFF, 0xFF )` into a `Uint8Array`, which cuts it toward
    zero and wraps it modulo 256.

    Args:
        value: The value; NaN, an empty row, is zero.

    Returns:
        The byte.
    """
    if isnan(value):
        return 0
    var scaled = min(value * 255, 255)
    var whole = Int(scaled)
    return UInt8(((whole % 256) + 256) % 256)


def ies_texture(
    lamp: IesLamp, type: IesType = IES_HALF_FLOAT
) raises -> Texture:
    """Return the lamp as a linear red texture, three.js's `IESLoader.parse`.

    Args:
        lamp: The lamp.
        type: `IES_UNSIGNED_BYTE`, `IES_HALF_FLOAT`, three.js's default,
            or `IES_FLOAT`.

    Returns:
        A texture 180 wide and 360 high, the value in red, bilinear, with
        no mip chain.

    Raises:
        Error: If the type is not valid, or `ies_values` refuses the lamp.
    """
    if not type.is_valid():
        raise Error("IES: a type that is not valid")
    var values = ies_values(lamp)
    if type == IES_UNSIGNED_BYTE:
        var pixels = List[UInt8]()
        for v in values:  # pragma: no branch
            pixels.append(ies_byte(v))
            pixels.append(0)
            pixels.append(0)
            pixels.append(255)
        return Texture(
            IES_HEIGHT,
            IES_WIDTH,
            pixels^,
            filter=BILINEAR,
            color_space=LINEAR,
            mipmapped=False,
            alpha=IGNORED,
        )
    var data = List[Float32]()
    for v in values:  # pragma: no branch
        var red = Float32(0)
        if not isnan(v):
            red = half_to_float(
                to_half_float(v)
            ) if type == IES_HALF_FLOAT else (Float32(v))
        data.append(red)
        data.append(0)
        data.append(0)
        data.append(1)
    return float_texture(IES_HEIGHT, IES_WIDTH, data^, alpha=IGNORED)


def read_ies(path: String) raises -> IesLamp:
    """Read an IES file.

    Args:
        path: The file.

    Returns:
        What `parse_ies` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_ies`
            refuses.
    """
    return parse_ies(Path(path).read_text())
