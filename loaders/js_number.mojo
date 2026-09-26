# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JavaScript's `parseFloat`, `parseInt` and `Number`, for the loaders that
read text the way three.js reads it.

`parseFloat` and `parseInt` read the longest number at the start of a
text, after white space, and ignore what follows it. So
`parseFloat("12px")` is 12, and `parseInt("1.5")` is 1. `Number` reads
the whole text, less white space at its ends, or gives NaN: `Number("12px")`
is NaN, `Number("")` is 0 and `Number("0x1F")` is 31. Where JavaScript
gives `NaN`, so do these.

**Where this differs.** White space is ASCII white space here;
JavaScript also skips the Unicode spaces. A number with more digits than
Mojo's parser reads gives NaN; JavaScript rounds it. A `0x`, `0o` or `0b`
integer past 2 to the 53 is summed a digit at a time, so it can round
differently.
"""

from std.math import inf, isfinite, isnan, nan
from std.ffi import external_call
from std.memory import bitcast


def _is_space(byte: UInt8) -> Bool:
    """Return True for an ASCII white space byte."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def _is_digit(byte: UInt8) -> Bool:
    """Return True for `0` to `9`."""
    return byte >= 48 and byte <= 57


def _space_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a white space byte at `i`."""
    return i < len(bytes) and _is_space(bytes[i])


def _digit_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a digit at `i`."""
    return i < len(bytes) and _is_digit(bytes[i])


def _sign_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a `+` or a `-` at `i`."""
    return i < len(bytes) and (bytes[i] == 43 or bytes[i] == 45)


def js_parse_float(text: String) -> Float64:
    """Return JavaScript's `parseFloat(text)`.

    Args:
        text: The text.

    Returns:
        The longest decimal number at the start, after white space,
        `Infinity` included; NaN when there is none.
    """
    var b = text.as_bytes()
    var n = len(b)
    var i = 0
    while _space_at(b, i):
        i += 1
    var start = i
    if _sign_at(b, i):
        i += 1
    if String(text[byte=i:]).startswith("Infinity"):
        return -inf[DType.float64]() if b[start] == 45 else inf[DType.float64]()
    var digits = 0
    while _digit_at(b, i):
        i += 1
        digits += 1
    var point = i < n and b[i] == 46
    if point:
        i += 1
        while _digit_at(b, i):
            i += 1
            digits += 1
    if digits == 0:
        return nan[DType.float64]()
    var end = i
    var exp = i < n and (b[i] == 101 or b[i] == 69)
    if exp:
        i += 1
        if _sign_at(b, i):
            i += 1
        var exponent = 0
        while _digit_at(b, i):
            i += 1
            exponent += 1
        if exponent > 0:
            end = i
    try:
        return Float64(String(text[byte=start:end]))
    except:
        return nan[DType.float64]()


def js_parse_int(text: String) -> Float64:
    """Return JavaScript's `parseInt(text)`, in base ten.

    Args:
        text: The text.

    Returns:
        The whole number at the start, after white space and a sign; NaN
        when there is none. It is a `Float64`, as a JavaScript number is,
        so that NaN can be returned.
    """
    var b = text.as_bytes()
    var i = 0
    while _space_at(b, i):
        i += 1
    var start = i
    if _sign_at(b, i):
        i += 1
    var first = i
    while _digit_at(b, i):
        i += 1
    if i == first:
        return nan[DType.float64]()
    try:
        return Float64(String(text[byte=start:i]))
    except:
        return nan[DType.float64]()


def _digit_value(byte: UInt8, radix: Int) -> Int:
    """Return a digit's value in a radix, or -1.

    Args:
        byte: The character.
        radix: 2, 8 or 16.

    Returns:
        The value, or -1 when the character is not a digit of the radix.
    """
    var value = -1
    if byte >= 48 and byte <= 57:
        value = Int(byte) - 48
    elif byte >= 97 and byte <= 102:
        value = Int(byte) - 87
    elif byte >= 65 and byte <= 70:
        value = Int(byte) - 55
    return value if value < radix else -1


def js_string_to_number(text: String) -> Float64:
    """Return JavaScript's `Number(text)` for a string.

    Args:
        text: The text.

    Returns:
        The number the whole text less white space at its ends writes:
        a decimal, `Infinity` with a sign or without, or a `0x`, `0o` or
        `0b` integer with no sign. Zero for an empty text. NaN for any
        other text.
    """
    var b = text.as_bytes()
    var start = 0
    var end = len(b)
    while _space_at(b, start):
        start += 1
    while end > start and _is_space(b[end - 1]):
        end -= 1
    if start == end:
        return 0
    var body = String(text[byte=start:end])
    var bytes = body.as_bytes()
    var n = len(bytes)
    if n > 2 and bytes[0] == 48:
        var marker = bytes[1] | 32
        var radix = 16 if marker == 120 else (
            8 if marker == 111 else (2 if marker == 98 else 0)
        )
        if radix > 0:
            var value = Float64(0)
            for k in range(2, n):  # pragma: no branch
                var digit = _digit_value(bytes[k], radix)
                if digit < 0:
                    return nan[DType.float64]()
                value = value * Float64(radix) + Float64(digit)
            return value
    var i = 1 if _sign_at(bytes, 0) else 0
    if String(body[byte=i:]) == "Infinity":
        return js_parse_float(body)
    var digits = 0
    while _digit_at(bytes, i):
        i += 1
        digits += 1
    if i < n and bytes[i] == 46:
        i += 1
        while _digit_at(bytes, i):
            i += 1
            digits += 1
    if digits == 0:
        return nan[DType.float64]()
    if i < n and (bytes[i] | 32) == 101:
        i += 1
        if _sign_at(bytes, i):
            i += 1
        var exponent = 0
        while _digit_at(bytes, i):
            i += 1
            exponent += 1
        if exponent == 0:
            return nan[DType.float64]()
    if i != n:
        return nan[DType.float64]()
    return js_parse_float(body)


struct _Decimal(Movable):
    """The decimal digits of a number: its value is `0.d1 d2 d3...` times
    ten to the `point`. The digits have no zero at either end, and no
    digits means zero."""

    var digits: List[Int]
    var point: Int

    def __init__(out self, var digits: List[Int], point: Int):
        """Hold digits and the place of the point."""
        self.digits = digits^
        self.point = point


def _trimmed(digits: List[Int], point: Int) -> _Decimal:
    """Return digits without zeros at either end, the point moved for
    each zero taken from the front."""
    var start = 0
    while start < len(digits) and digits[start] == 0:
        start += 1
    var end = len(digits)
    while end > start and digits[end - 1] == 0:
        end -= 1
    var out = List[Int]()
    for i in range(start, end):
        out.append(digits[i])
    var moved = point - start if len(out) > 0 else 0
    return _Decimal(out^, moved)


def _shortest(text: String) raises -> _Decimal:
    """Return the digits of Mojo's shortest text of a finite magnitude,
    such as `1.25`, `0.0` or `1.5e-07`."""
    var mantissa = text
    var exponent = 0
    var bytes = text.as_bytes()
    # Mojo's text of a number is not empty. The loop always runs.
    for i in range(len(bytes)):  # pragma: no branch
        if bytes[i] == 101:
            mantissa = String(text[byte=:i])
            exponent = Int(String(text[byte = i + 1 :]).lstrip("+"))
            break
    var digits = List[Int]()
    var point = 0
    var seen_point = False
    # The text has a digit. The loop always runs.
    for b in mantissa.as_bytes():  # pragma: no branch
        if b == 46:
            seen_point = True
        else:
            digits.append(Int(b) - 48)
            if not seen_point:
                point += 1
    return _trimmed(digits, point + exponent)


def _exact(value: Float64) -> _Decimal:
    """Return every decimal digit of a finite double's magnitude.

    A double is `m` times two to the `q`. For `q` of zero or more that is
    a whole number. For `q` below zero it is `m` times five to the `-q`,
    over ten to the `-q`. Either way the digits come from a whole number,
    held in base 1,000,000,000.
    """
    var bits = bitcast[DType.uint64](value)
    var field = Int((bits >> 52) & 0x7FF)
    var m = Int(bits & 0xFFFFFFFFFFFFF)
    var q: Int
    if field == 0:
        q = -1074
    else:
        m |= 1 << 52
        q = field - 1075
    comptime BASE = 1_000_000_000
    var limbs = List[Int]()
    while m > 0:
        limbs.append(m % BASE)
        m //= BASE
    # Two to the q, or five to the -q, a few factors at a time: a limb
    # times the factor stays below two to the 63.
    var remaining = q if q >= 0 else -q
    var step = 29 if q >= 0 else 12
    var factor = 2 if q >= 0 else 5
    while remaining > 0:
        var n = min(step, remaining)
        remaining -= n
        var multiplier = factor**n
        var carry = 0
        for i in range(len(limbs)):
            var product = limbs[i] * multiplier + carry
            limbs[i] = product % BASE
            carry = product // BASE
        while carry > 0:
            limbs.append(carry % BASE)
            carry //= BASE
    var digits = List[Int]()
    var i = len(limbs) - 1
    while i >= 0:
        var limb = limbs[i]
        var chunk = List[Int](length=9, fill=0)
        # Nine digits. The loop always runs.
        for k in range(9):  # pragma: no branch
            chunk[8 - k] = limb % 10
            limb //= 10
        digits.extend(chunk^)
        i -= 1
    var point = len(digits) + (q if q < 0 else 0)
    return _trimmed(digits, point)


def _round(number: _Decimal, keep: Int) -> _Decimal:
    """Return a number rounded to its first `keep` digits, a tie away from
    zero. With `keep` of zero, the result is one unit at the first digit
    when that digit is five or more, and zero if not."""
    if keep < 0:
        return _Decimal(List[Int](), 0)
    if len(number.digits) <= keep:
        return _Decimal(number.digits.copy(), number.point)
    var digits = List[Int]()
    for i in range(keep):
        digits.append(number.digits[i])
    var point = number.point
    if number.digits[keep] >= 5:
        var i = keep - 1
        while i >= 0 and digits[i] == 9:
            digits[i] = 0
            i -= 1
        if i < 0:
            digits.insert(0, 1)
            point += 1
        else:
            digits[i] += 1
    return _trimmed(digits, point)


def _text(digits: List[Int], start: Int, end: Int) -> String:
    """Return digits from `start` to `end` as text, zeros past the end."""
    var out = String()
    # The callers give one digit or more. The loop always runs.
    for i in range(start, end):  # pragma: no branch
        out += String(digits[i] if i < len(digits) else 0)
    return out


def _exponent(e: Int) -> String:
    """Return JavaScript's exponent: `e+21`, `e-7`."""
    return "e" + ("+" if e >= 0 else "-") + String(abs(e))


def _format(number: _Decimal, negative: Bool) -> String:
    """Return JavaScript's text of a number from its shortest digits."""
    if len(number.digits) == 0:
        return "0"
    var sign = "-" if negative else ""
    ref d = number.digits
    var k = len(d)
    var n = number.point
    if k <= n and n <= 21:
        return sign + _text(d, 0, n)
    if 0 < n and n <= 21:
        return sign + _text(d, 0, n) + "." + _text(d, n, k)
    if -6 < n and n <= 0:
        return sign + "0." + "0" * (-n) + _text(d, 0, k)
    var tail = "" if k == 1 else "." + _text(d, 1, k)
    return sign + _text(d, 0, 1) + tail + _exponent(n - 1)


def _special(value: Float64) -> String:
    """Return `NaN`, `Infinity` or `-Infinity`."""
    if isnan(value):
        return "NaN"
    return "Infinity" if value > 0 else "-Infinity"


def js_number_text(value: Float64) raises -> String:
    """Return JavaScript's `String(value)` for a number.

    Args:
        value: The number.

    Returns:
        The shortest digits that read back to it: `0.1`, `100`, `1e+21`,
        `1e-7`, `NaN`, `Infinity`. Minus zero is `0`.

    Raises:
        Error: If Mojo's own text of the number cannot be read, which
            does not happen for a finite number.
    """
    if not isfinite(value):
        return _special(value)
    return _format(_shortest(String(abs(value))), value < 0)


def js_float32_text(value: Float32) raises -> String:
    """Return the shortest text that reads back to a `Float32`, written as
    JavaScript writes a number.

    Args:
        value: The number.

    Returns:
        The text: `0.1` for the `Float32` nearest a tenth, where
        `js_number_text` writes `0.10000000149011612`.

    Raises:
        Error: If Mojo's own text of the number cannot be read, which
            does not happen for a finite number.
    """
    if not isfinite(value):
        return _special(Float64(value))
    return _format(_shortest(String(abs(value))), value < 0)


def js_to_precision(value: Float64, precision: Int) raises -> String:
    """Return JavaScript's `value.toPrecision(precision)`.

    Args:
        value: The number.
        precision: The significant digits, from 1 to 100.

    Returns:
        The text, in exponent form when the exponent is below minus six
        or not below the precision: `1.000000`, `0.0001000000`,
        `1.234568e+21`.

    Raises:
        Error: If the precision is not from 1 to 100, as JavaScript
            throws a `RangeError`.
    """
    if precision < 1 or precision > 100:
        raise Error("toPrecision: the precision must be from 1 to 100")
    if not isfinite(value):
        return _special(value)
    var number = _round(_exact(abs(value)), precision)
    if len(number.digits) == 0:
        # Zero: its digits are all zeros, and its exponent is zero.
        return "0" + ("" if precision == 1 else "." + "0" * (precision - 1))
    var sign = "-" if value < 0 else ""
    var e = number.point - 1
    ref d = number.digits
    if e < -6 or e >= precision:
        var tail = "" if precision == 1 else "." + _text(d, 1, precision)
        return sign + _text(d, 0, 1) + tail + _exponent(e)
    if e >= 0:
        var whole = _text(d, 0, e + 1)
        if precision == e + 1:
            return sign + whole
        return sign + whole + "." + _text(d, e + 1, precision)
    return sign + "0." + "0" * (-e - 1) + _text(d, 0, precision)


def js_to_fixed(value: Float64, fraction: Int) raises -> String:
    """Return JavaScript's `value.toFixed(fraction)`.

    Args:
        value: The number.
        fraction: The digits after the point, from 0 to 100.

    Returns:
        The text. A negative number keeps its sign when it rounds to
        zero, and minus zero does not. From `1e21` up, and for NaN and
        the infinities, the text of `js_number_text`.

    Raises:
        Error: If the digits are not from 0 to 100, as JavaScript throws
            a `RangeError`.
    """
    if fraction < 0 or fraction > 100:
        raise Error("toFixed: the digits must be from 0 to 100")
    if not isfinite(value) or abs(value) >= 1e21:
        return js_number_text(value)
    var sign = "-" if value < 0 else ""
    var number = _exact(abs(value))
    var rounded = _round(number, number.point + fraction)
    # The whole number that is the value times ten to the `fraction`.
    var length = rounded.point + fraction
    var digits = _text(rounded.digits, 0, length) if length > 0 else String()
    if digits.byte_length() < fraction + 1:
        digits = "0" * (fraction + 1 - digits.byte_length()) + digits
    if fraction == 0:
        return sign + digits
    var cut = digits.byte_length() - fraction
    return sign + String(digits[byte=:cut]) + "." + String(digits[byte=cut:])


# three.js's `SRGBToLinear` of each byte over 255, as V8 works it out:
# the bits of each double. V8's `Math.pow` is neither Mojo's `pow` nor
# the C library's, and each gives another last digit for some bytes, so
# the 256 answers are kept here. `assets/js_number/srgb.mjs` wrote them.
comptime _SRGB_TO_LINEAR: List[UInt64] = [
    0x0000000000000000,
    0x3F33E45677BBFF31,
    0x3F43E45677BBFF31,
    0x3F4DD681B399FECA,
    0x3F53E45677BBFF31,
    0x3F58DD6C15AAFEFD,
    0x3F5DD681B399FECA,
    0x3F6167CBA8C47F4B,
    0x3F63E45677BBFF31,
    0x3F6660E146B37F17,
    0x3F68DD6C15AAFEFD,
    0x3F6B6A31B4E63D40,
    0x3F6E1E31D6C9EDF9,
    0x3F707C38BF628428,
    0x3F71FCC2BEC8B809,
    0x3F7390FFAF6F86F9,
    0x3F753936CC53BBB1,
    0x3F76F5ADDB270744,
    0x3F78C6A940063D0E,
    0x3F7AAC6C0F8C4282,
    0x3F7CA7381F707519,
    0x3F7EB74E15D8D1D9,
    0x3F806E76BBC16098,
    0x3F818C2A5A706EDA,
    0x3F82B4E09B2419A5,
    0x3F83E8B7B3A217D5,
    0x3F8527CD6092D946,
    0x3F86723EEA6FA3BF,
    0x3F87C8292A1F4221,
    0x3F8929A88D485F19,
    0x3F8A96D91A5FDF1F,
    0x3F8C0FD67478E176,
    0x3F8D94BBDEDB792D,
    0x3F8F25A44066ABD4,
    0x3F9061551360E7A9,
    0x3F9135F3E4B07D5A,
    0x3F9210BB862FF16F,
    0x3F92F1B8C19B1664,
    0x3F93D8F839A3FB8C,
    0x3F94C6866B2A8F2F,
    0x3F95BA6FAE64C2E9,
    0x3F96B4C037F83E4F,
    0x3F97B5841A0694E0,
    0x3F98BCC7452CE032,
    0x3F99CA9589778C80,
    0x3F9ADEFA974B15BE,
    0x3F9BFA02004263AA,
    0x3F9D1BB73803668B,
    0x3F9E4425950A893B,
    0x3F9F7358516D829A,
    0x3FA054AD45CB02E1,
    0x3FA0F31BA37A63C6,
    0x3FA194FCB656A392,
    0x3FA23A55E61D5FFA,
    0x3FA2E32C8E0751DE,
    0x3FA38F85FD147AE8,
    0x3FA43F6776556CAD,
    0x3FA4F2D63131D05C,
    0x3FA5A9D759AC528E,
    0x3FA6647010A41530,
    0x3FA722A56C13C70A,
    0x3FA7E47C774E7E72,
    0x3FA8A9FA333A72DA,
    0x3FA973239689AF83,
    0x3FAA3FFD8DF0D780,
    0x3FAB108CFC5C1258,
    0x3FABE4D6BB2236C0,
    0x3FACBCDF9A3647F7,
    0x3FAD98AC60575900,
    0x3FAE7841CB3EE7E1,
    0x3FAF5BA48FCDC1EC,
    0x3FB0216CAD1BC0BC,
    0x3FB096F267165A29,
    0x3FB10E65C381DC9B,
    0x3FB187C90BF0311B,
    0x3FB2031E85ED347A,
    0x3FB2806873116094,
    0x3FB2FFA91113EA69,
    0x3FB380E299DC5ACB,
    0x3FB404174393A6A4,
    0x3FB4894940B4CC26,
    0x3FB5107AC01CF95B,
    0x3FB599ADED1B40C4,
    0x3FB624E4EF7FE044,
    0x3FB6B221EBAB1E8B,
    0x3FB74167029BC2BB,
    0x3FB7D2B651FD2A32,
    0x3FB86611F434FFD7,
    0x3FB8FB7C00709888,
    0x3FB992F68AB1F795,
    0x3FBA2C83A3DC7EB0,
    0x3FBAC82559C14C08,
    0x3FBB65DDB72B4990,
    0x3FBC05AEC3EAEFFE,
    0x3FBCA79A84E1C02D,
    0x3FBD4BA2FC0D7549,
    0x3FBDF1CA2892F24E,
    0x3FBE9A1206C8ECD9,
    0x3FBF447C904257B0,
    0x3FBFF10BBBD88EFF,
    0x3FC04FE0BEDAA425,
    0x3FC0A84FE3AE23FF,
    0x3FC101D443DA6F43,
    0x3FC15C6ED5899742,
    0x3FC1B8208DA09F09,
    0x3FC214EA5FC3EA42,
    0x3FC272CD3E5B9323,
    0x3FC2D1CA1A97A82F,
    0x3FC331E1E4745284,
    0x3FC393158ABDE564,
    0x3FC3F565FB14D79D,
    0x3FC458D421F1A785,
    0x3FC4BD60EAA8AA23,
    0x3FC5230D3F6DC619,
    0x3FC589DA09581AE7,
    0x3FC5F1C830659510,
    0x3FC65AD89B7E6FBA,
    0x3FC6C50C3078A437,
    0x3FC73063D41B480A,
    0x3FC79CE06A21D9CF,
    0x3FC80A82D53F7D9B,
    0x3FC8794BF722291F,
    0x3FC8E93CB075C028,
    0x3FC95A55E0E721BA,
    0x3FC9CC986727265B,
    0x3FCA400520ED8FD6,
    0x3FCAB49CEAFBEACA,
    0x3FCB2A60A120628A,
    0x3FCBA1511E38879A,
    0x3FCC196F3C340900,
    0x3FCC92BBD41760DB,
    0x3FCD0D37BDFE74B4,
    0x3FCD88E3D11F297A,
    0x3FCE05C0E3CBEBDB,
    0x3FCE83CFCB762D04,
    0x3FCF03115CB0D431,
    0x3FCF83866B32A528,
    0x3FD00297E4EC4E19,
    0x3FD0440725541FB2,
    0x3FD086115F68F300,
    0x3FD0C8B6FB597AC8,
    0x3FD10BF860EC0AC7,
    0x3FD14FD5F77FACAE,
    0x3FD19450260D3092,
    0x3FD1D967532838BD,
    0x3FD21F1BE500411B,
    0x3FD2656E4161A25F,
    0x3FD2AC5ECDB690D4,
    0x3FD2F3EDEF081730,
    0x3FD33C1C09FF0D27,
    0x3FD384E982E50A51,
    0x3FD3CE56BDA554EE,
    0x3FD418641DCDCD16,
    0x3FD46312068FD40B,
    0x3FD4AE60DAC1301A,
    0x3FD4FA50FCDCECCF,
    0x3FD546E2CF0437BC,
    0x3FD59416B2FF39E2,
    0x3FD5E1ED0A3DEDC5,
    0x3FD6306635D8F246,
    0x3FD67F8296925A36,
    0x3FD6CF428CD678F7,
    0x3FD71FA678BCABE0,
    0x3FD770AEBA0820CE,
    0x3FD7C25BB02899A8,
    0x3FD814ADBA3B2D15,
    0x3FD867A5370B0469,
    0x3FD8BB42851216B6,
    0x3FD90F860279E152,
    0x3FD964700D1C1D88,
    0x3FD9BA01028373E8,
    0x3FDA10393FEC2CD3,
    0x3FDA67192244DEC3,
    0x3FDABEA1062F19E2,
    0x3FDB16D148001180,
    0x3FDB6FAA43C142FC,
    0x3FDBC92C55311A68,
    0x3FDC2357D7C39508,
    0x3FDC7E2D26A2E16A,
    0x3FDCD9AC9CAFFD83,
    0x3FDD35D694835278,
    0x3FDD92AB686D4E75,
    0x3FDDF02B7276FC60,
    0x3FDE4E570C629998,
    0x3FDEAD2E8FAC2997,
    0x3FDF0CB2558A07D4,
    0x3FDF6CE2B6ED7790,
    0x3FDFCDC00C8331CE,
    0x3FE017A55759F8C7,
    0x3FE048C17AD27EFF,
    0x3FE07A349C9C599B,
    0x3FE0ABFEE8878472,
    0x3FE0DE208A430BBB,
    0x3FE11099AD5D4DBB,
    0x3FE1436A7D443BB1,
    0x3FE17693254599D4,
    0x3FE1AA13D08F3EAB,
    0x3FE1DDECAA2F5178,
    0x3FE2121DDD1487F1,
    0x3FE246A7940E6338,
    0x3FE27B89F9CD6C04,
    0x3FE2B0C538E36E24,
    0x3FE2E6597BC3B331,
    0x3FE31C46ECC33CA2,
    0x3FE3528DB618FD1E,
    0x3FE3892E01DE111E,
    0x3FE3C027FA0DF6F4,
    0x3FE3F77BC886C60C,
    0x3FE42F29970965A4,
    0x3FE467318F39C2C1,
    0x3FE49F93DA9F05A5,
    0x3FE4D850A2A3C67E,
    0x3FE51168109641A2,
    0x3FE54ADA4DA88B06,
    0x3FE584A782F0C14F,
    0x3FE5BECFD9694016,
    0x3FE5F95379F0D1CC,
    0x3FE634328D4AE0EC,
    0x3FE66F6D3C1FA8AA,
    0x3FE6AB03AEFC651D,
    0x3FE6E6F60E5382CD,
    0x3FE72344827CCDCC,
    0x3FE75FEF33B5A03E,
    0x3FE79CF64A211066,
    0x3FE7DA59EDC81E22,
    0x3FE8181A4699DFFB,
    0x3FE856377C6BAFAC,
    0x3FE894B1B6F95624,
    0x3FE8D3891DE53730,
    0x3FE912BDD8B87C74,
    0x3FE952500EE34032,
    0x3FE9923FE7BCB760,
    0x3FE9D28D8A835B77,
    0x3FEA13391E5D13AC,
    0x3FEA5442CA575DE0,
    0x3FEA95AAB56776F8,
    0x3FEAD771066A82F4,
    0x3FEB1995E425B476,
    0x3FEB5C19754673F3,
    0x3FEB9EFBE0628682,
    0x3FEBE23D4BF8342A,
    0x3FEC25DDDE6E6DF2,
    0x3FEC69DDBE14F360,
    0x3FECAE3D112477C7,
    0x3FECF2FBFDBEC706,
    0x3FED381AA9EEEA08,
    0x3FED7D993BA94AE0,
    0x3FEDC377D8CBD874,
    0x3FEE09B6A71E29F0,
    0x3FEE5055CC51A1B8,
    0x3FEE97556E019026,
    0x3FEEDEB5B1B355CD,
    0x3FEF2676BCD6858C,
    0x3FEF6E98B4C5061C,
    0x3FEFB71BBEC33384,
    0x3FF0000000000000,
]


def srgb_to_linear(byte: UInt8) -> Float64:
    """Return a channel of three.js's `Color.setHex`: the byte over 255,
    through `SRGBToLinear`, as the double that V8 works out.

    Args:
        byte: The sRGB byte.

    Returns:
        The linear channel that three.js holds.
    """
    return bitcast[DType.float64](materialize[_SRGB_TO_LINEAR]()[Int(byte)])


def js_pow(base: Float64, exponent: Float64) -> Float64:
    """Return JavaScript's `Math.pow(base, exponent)`, to within a unit in
    the last place.

    `std.math.pow` works through `exp` and `log`, and is off by some
    hundreds of units in the last place. That is enough to move a result
    that is rounded to a `Float32` next. The C library's `pow` is within
    one unit of V8's.

    Args:
        base: The base.
        exponent: The exponent.

    Returns:
        The power.
    """
    return external_call["pow", Float64](base, exponent)


def js_log2(value: Float64) -> Float64:
    """Return JavaScript's `Math.log2(value)`, to within a unit in the
    last place, from the C library, as `js_pow` is.

    Args:
        value: The number.

    Returns:
        Its base-two logarithm.
    """
    return external_call["log2", Float64](value)
