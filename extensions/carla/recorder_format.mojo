# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers and dates as CARLA's recorder writes them in its text.

CARLA's recorder queries build their text with a C++ `std::stringstream`
and, for a few vectors, with C's `snprintf`. The text of a number is the
text that the GNU C library gives, so these functions give it too:

- `c_general` is a stream's default: C's `%g` with six significant
  digits. It writes `1`, `0.5`, `1234.57` and `1.23457e+06`.
- `c_fixed` is a stream after `std::fixed` and `std::setprecision(n)`:
  C's `%.nf`. `c_fixed(x, 6)` is `snprintf`'s `%f`.
- `pad_right` and `pad_left` are `std::setw` with `std::right` and
  `std::left`.
- `c_date` is `strftime`'s `%x %X` in the C locale: `09/29/26 14:05:09`.

Each function works from the exact binary value of the number, and
rounds a tie to the even digit, as the GNU C library does in its default
rounding mode. A number that is not finite is `inf`, `-inf`, `nan` or
`-nan`.

The source is CARLA's simulator plugin, `Carla/Recorder/
CarlaRecorderQuery.cpp`, which writes every number through these forms.

**The time zone is UTC.** CARLA prints a recording's date with C's
`localtime`, which reads the machine's time zone. `c_date` prints the date
in UTC, which is what `localtime` gives on a machine with no time zone
set.
"""

from std.memory import bitcast

comptime _BILLION = UInt64(1000000000)


def _limbs_to_digits(limbs: List[UInt64]) -> String:
    """Write a number held as base-10^9 limbs, least significant first.
    The last limb is not zero."""
    var top = len(limbs) - 1
    var out = String(limbs[top])
    # A double's mantissa at its scale always spans more than one limb.
    for i in range(top - 1, -1, -1):  # pragma: no branch
        var part = String(limbs[i])
        out += "0" * (9 - part.byte_length()) + part
    return out


def _multiply(mut limbs: List[UInt64], factor: UInt64):
    """Multiply base-10^9 limbs by a factor below 2^31."""
    var carry = UInt64(0)
    # There is always a limb.
    for i in range(len(limbs)):  # pragma: no branch
        var product = limbs[i] * factor + carry
        limbs[i] = product % _BILLION
        carry = product // _BILLION
    while carry > 0:
        limbs.append(carry % _BILLION)
        carry //= _BILLION


@fieldwise_init
struct _Decimal(Copyable, Movable):
    """A positive number as 0.d1 d2 d3 ... times ten to the `point`."""

    # The digits, with no zero in front. Empty for zero.
    var digits: String
    var point: Int


def _exact(value: Float64) -> _Decimal:
    """Return the exact decimal of a finite number's magnitude."""
    var bits = bitcast[DType.uint64](value)
    var exponent = Int((bits >> 52) & 0x7FF)
    var mantissa = bits & 0xFFFFFFFFFFFFF
    if exponent == 0:
        exponent = 1
    else:
        mantissa |= UInt64(1) << 52
    if mantissa == 0:
        return _Decimal("", 0)
    # The value is mantissa times two to the `shift`.
    var shift = exponent - 1075
    var limbs: List[UInt64] = [mantissa % _BILLION]
    if mantissa >= _BILLION:
        limbs.append(mantissa // _BILLION)
    var fraction = 0
    if shift >= 0:
        var left = shift
        while left > 0:
            var step = min(left, 29)
            _multiply(limbs, UInt64(1) << UInt64(step))
            left -= step
    else:
        # m / 2^k is m 5^k / 10^k.
        fraction = -shift
        var left = fraction
        while left > 0:
            var step = min(left, 13)
            var power = UInt64(1)
            # A step is at least one.
            for _ in range(step):  # pragma: no branch
                power *= 5
            _multiply(limbs, power)
            left -= step
    var text = _limbs_to_digits(limbs)
    var point = text.byte_length() - fraction
    # Drop the zeros at the end: they carry no value.
    var end = text.byte_length()
    while text.as_bytes()[end - 1] == 48:
        end -= 1
    return _Decimal(String(text[byte=:end]), point)


def _round(number: _Decimal, keep: Int) -> _Decimal:
    """Round to `keep` digits, a tie to the even digit, as C does.

    `keep` may be zero or less: the number then rounds to zero or to one
    unit of the first place kept.
    """
    var n = number.digits.byte_length()
    if keep >= n:
        return number.copy()
    var bytes = number.digits.as_bytes()
    var up = False
    if keep >= 0:
        var next = bytes[keep]
        if next > 53:
            up = True
        elif next == 53:
            # Past the five, any digit that is not zero breaks the tie.
            # The digits end with one that is not zero, so a five that is
            # not the last digit is more than half.
            if keep + 1 < n:
                up = True
            else:
                up = keep > 0 and (Int(bytes[keep - 1]) - 48) % 2 == 1
    if keep <= 0:
        # Every digit is cut. The number is below one unit of the kept
        # place, and rounds up to it only when it is past the half.
        if keep == 0 and up:
            return _Decimal("1", number.point + 1)
        return _Decimal("", 0)
    var kept = List[UInt8]()
    # `keep` is more than zero here.
    for i in range(keep):  # pragma: no branch
        kept.append(bytes[i])
    var point = number.point
    if up:
        var i = keep - 1
        while i >= 0 and kept[i] == 57:
            kept[i] = 48
            i -= 1
        if i < 0:
            kept.insert(0, 49)
            point += 1
        else:
            kept[i] += 1
    # Drop the zeros at the end.
    # The first digit is never zero, so the loop stops at it.
    while kept[len(kept) - 1] == 48:
        _ = kept.pop()
    return _Decimal(String(unsafe_from_utf8=kept), point)


def _digit_run(digits: String, start: Int, end: Int) -> String:
    """Return digits `start` to `end`, zeros past the last one."""
    var out = String()
    var n = digits.byte_length()
    # Every caller asks for at least one digit.
    for i in range(start, end):  # pragma: no branch
        if i < n:
            out += chr(Int(digits.as_bytes()[i]))
        else:
            out += "0"
    return out


def _special(value: Float64) -> String:
    """The text of a number that is not finite, as the GNU C library
    writes it."""
    var negative = (bitcast[DType.uint64](value) >> 63) != 0
    var sign = "-" if negative else ""
    if value != value:
        return sign + "nan"
    return sign + "inf"


def _is_finite(value: Float64) -> Bool:
    return ((bitcast[DType.uint64](value) >> 52) & 0x7FF) != 0x7FF


def _sign(value: Float64) -> String:
    return "-" if (bitcast[DType.uint64](value) >> 63) != 0 else ""


def c_fixed(value: Float64, precision: Int) raises -> String:
    """Write a number as C's `%.nf`, a stream's `std::fixed`.

    Args:
        value: The number.
        precision: The digits after the point, from 0 to 60.

    Returns:
        The text: `3` for 2.5 at no digits, `1.500000` for 1.5 at six. A
        negative number, minus zero included, keeps its sign.

    Raises:
        Error: If the precision is out of range.
    """
    if precision < 0 or precision > 60:
        raise Error("c_fixed: the precision must be from 0 to 60")
    if not _is_finite(value):
        return _special(value)
    var number = _round(_exact(value), _exact(value).point + precision)
    var whole: String
    if number.point > 0:
        whole = _digit_run(number.digits, 0, number.point)
    else:
        whole = "0"
    var tail = String()
    for i in range(precision):
        var at = number.point + i
        if at < 0:
            tail += "0"
        else:
            tail += _digit_run(number.digits, at, at + 1)
    var text = whole if precision == 0 else whole + "." + tail
    return _sign(value) + text


def c_general(value: Float64) -> String:
    """Write a number as a C++ stream does by default: C's `%g`.

    Six significant digits are kept. The number is in exponent form when
    its exponent is below -4 or not below 6. Zeros at the end of the
    fraction are dropped, and a point with nothing after it.

    Args:
        value: The number. A `float` is widened to a `double` first, as a
            stream does.

    Returns:
        The text: `1`, `0.5`, `1234.57`, `1e-05`, `1.23457e+06`, `-0`.
    """
    if not _is_finite(value):
        return _special(value)
    var number = _round(_exact(value), 6)
    if number.digits.byte_length() == 0:
        return _sign(value) + "0"
    var e = number.point - 1
    ref d = number.digits
    var n = d.byte_length()
    var text: String
    if e < -4 or e >= 6:
        text = _digit_run(d, 0, 1)
        if n > 1:
            text += "." + _digit_run(d, 1, n)
        var magnitude = String(abs(e))
        if magnitude.byte_length() < 2:
            magnitude = "0" + magnitude
        text += ("e-" if e < 0 else "e+") + magnitude
    elif e >= 0:
        text = _digit_run(d, 0, e + 1)
        if n > e + 1:
            text += "." + _digit_run(d, e + 1, n)
    else:
        text = "0." + "0" * (-e - 1) + d
    return _sign(value) + text


def pad_right(text: String, width: Int) -> String:
    """Right-justify text in a field, `std::setw` with `std::right`.

    Args:
        text: The text.
        width: The field's width in bytes. Longer text is not cut.

    Returns:
        The text with spaces in front up to the width.
    """
    var n = text.byte_length()
    if n >= width:
        return text
    return " " * (width - n) + text


def pad_left(text: String, width: Int) -> String:
    """Left-justify text in a field, `std::setw` with `std::left`.

    Args:
        text: The text.
        width: The field's width in bytes. Longer text is not cut.

    Returns:
        The text with spaces after it up to the width.
    """
    var n = text.byte_length()
    if n >= width:
        return text
    return text + " " * (width - n)


def _two(value: Int) -> String:
    if value < 10:
        return "0" + String(value)
    return String(value)


def c_date(seconds: Int) -> String:
    """Write a time as `strftime`'s `%x %X` in the C locale, in UTC.

    Args:
        seconds: Seconds since 1970-01-01 00:00:00 UTC, C's `time_t`.

    Returns:
        The month, day and two-digit year, then the time:
        `09/29/26 14:05:09`.
    """
    var days = seconds // 86400
    var rest = seconds - days * 86400
    # A civil date from a day count, the proleptic Gregorian calendar in
    # eras of 400 years.
    var z = days + 719468
    # Mojo's `//` rounds down, so a day before the calendar's start falls
    # in the era before.
    var era = z // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var year = yoe + era * 400
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var day = doy - (153 * mp + 2) // 5 + 1
    var month = mp + 3 if mp < 10 else mp - 9
    if month <= 2:
        year += 1
    var hour = rest // 3600
    var minute = (rest % 3600) // 60
    var second = rest % 60
    return (
        _two(month)
        + "/"
        + _two(day)
        + "/"
        + _two(((year % 100) + 100) % 100)
        + " "
        + _two(hour)
        + ":"
        + _two(minute)
        + ":"
        + _two(second)
    )
