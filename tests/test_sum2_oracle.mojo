# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The streaming Sum2 total stays inside its rational bound."""

from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true

from tools._bigint import BigInt
from tools._fraction import Fraction


@no_inline
def _add(left: Float64, right: Float64) -> Float64:
    """Add two floats without a fused multiply-add."""
    return left + right


@no_inline
def _sub(left: Float64, right: Float64) -> Float64:
    """Subtract two floats without a fused multiply-add."""
    return left - right


@no_inline
def _mul(left: Float64, right: Float64) -> Float64:
    """Multiply two floats without a fused multiply-add."""
    return left * right


def _word(value: Float64) -> UInt64:
    """Return the IEEE bits of `value`."""
    return bitcast[DType.uint64](value)


def _float(bits: UInt64) -> Float64:
    """Return the float with IEEE bits `bits`."""
    return bitcast[DType.float64](bits)


def _two_sum(left: Float64, right: Float64) -> Tuple[Float64, Float64]:
    """Return Python's `two_sum` pair."""
    var value = _add(left, right)
    var second = _sub(value, left)
    var first = _sub(value, second)
    var error = _add(_sub(left, first), _sub(right, second))
    return (value, error)


def _sum2(values: List[Float64]) -> Float64:
    """Return the streaming Sum2 total."""
    var total = Float64(0)
    var residual = Float64(0)
    for value in values:
        var pair = _two_sum(total, value)
        total = pair[0]
        residual = _add(residual, pair[1])
    return _add(total, residual)


def _unit() raises -> Fraction:
    """Return 2**-53."""
    return Fraction.of(BigInt(1), BigInt.power_of_two(53))


def _exact(values: List[Float64]) raises -> Fraction:
    """Return the exact sum of `values`."""
    var total = Fraction(0)
    for value in values:
        total = total + Fraction.from_float(value)
    return total^


def _inside(values: List[Float64]) raises:
    """Require Sum2 and each two-sum step to meet the rational bound."""
    var exact = _exact(values)
    var magnitude = Fraction(0)
    for value in values:
        magnitude = magnitude + abs(Fraction.from_float(value))
    var count = len(values)
    var unit = _unit()
    var steps = Fraction(count - 1)
    var gamma = (steps * unit) / (Fraction(1) - (steps * unit))
    var result = _sum2(values)
    var gap = abs(Fraction.from_float(result) - exact)
    var limit = unit * abs(exact) + gamma * gamma * magnitude
    assert_true(gap <= limit)
    var running = Float64(0)
    for value in values:
        var pair = _two_sum(running, value)
        var left = Fraction.from_float(pair[0]) + Fraction.from_float(pair[1])
        var right = Fraction.from_float(running) + Fraction.from_float(value)
        assert_true(left == right)
        running = pair[0]


def _native_words() -> List[UInt64]:
    """Return the 100 reviewed native term pairs."""
    var words = List[UInt64]()
    words.append(UInt64(0x3FBB7005E832D25A))
    words.append(UInt64(0x3E9031D46618F6D0))
    words.append(UInt64(0x3FCBB6CD63E3B454))
    words.append(UInt64(0x3EE8BDA8E660BC28))
    words.append(UInt64(0x3FD0785F8190BC60))
    words.append(UInt64(0x3F1141A90477226A))
    words.append(UInt64(0x3FCBB6CD0F5C8B9D))
    words.append(UInt64(0x3F212E912FF19882))
    words.append(UInt64(0x3FBB7005215F1A3A))
    words.append(UInt64(0x3F1A1D1598B30A0A))
    words.append(UInt64(0x3FBB7004C6BED394))
    words.append(UInt64(0x3F1F81FE56CEE2AA))
    words.append(UInt64(0x3FCBB6CB361CBFA1))
    words.append(UInt64(0x3F35FE1253F08960))
    words.append(UInt64(0x3FD0785CAE5A8D66))
    words.append(UInt64(0x3F4369DD08DF3AAA))
    words.append(UInt64(0x3FCBB6C413DAE3C3))
    words.append(UInt64(0x3F46B90FEE704F42))
    words.append(UInt64(0x3FBB6FF8360BE2AF))
    words.append(UInt64(0x3F3B6A262431017A))
    words.append(UInt64(0x3FBB6FF5623BCFF1))
    words.append(UInt64(0x3F3E1C991F6F5AB7))
    words.append(UInt64(0x3FCBB6B5D96FDA2D))
    words.append(UInt64(0x3F520FE9432B74E0))
    words.append(UInt64(0x3FD078497887FCF2))
    words.append(UInt64(0x3F5AF68C10AC94F5))
    words.append(UInt64(0x3FCBB6957B7B279B))
    words.append(UInt64(0x3F5BD58DD8BB0754))
    words.append(UInt64(0x3FBB6FBE531A253A))
    words.append(UInt64(0x3F4F5642D6F3D883))
    words.append(UInt64(0x3FBB6FB4C9020695))
    words.append(UInt64(0x3F50AE0A4806763E))
    words.append(UInt64(0x3FCBB665D0309ACA))
    words.append(UInt64(0x3F62F144896A3A58))
    words.append(UInt64(0x3FD0780AC17D7E0A))
    words.append(UInt64(0x3F6A6C5D7C1216E0))
    words.append(UInt64(0x3FCBB60D7FA732CD))
    words.append(UInt64(0x3F69C8508EE0E7B0))
    words.append(UInt64(0x3FBB6F200F3441A3))
    words.append(UInt64(0x3F5C137012D561EF))
    words.append(UInt64(0x3FBB6F0973550E6C))
    words.append(UInt64(0x3F5D6C9E7528C4D5))
    words.append(UInt64(0x3FCBB59CCCAA6ADD))
    words.append(UInt64(0x3F703DBD19552D59))
    words.append(UInt64(0x3FD07777DC4E1834))
    words.append(UInt64(0x3F75D6B3853A02B8))
    words.append(UInt64(0x3FCBB4E18B28C290))
    words.append(UInt64(0x3F74A341E2D8CEAE))
    words.append(UInt64(0x3FBB6DCF6D52B43C))
    words.append(UInt64(0x3F660984CD887A0F))
    words.append(UInt64(0x3FBB6DA3462C6872))
    words.append(UInt64(0x3F66E1371F6A491C))
    words.append(UInt64(0x3FCBB405B48502D7))
    words.append(UInt64(0x3F78D306AC0BE385))
    words.append(UInt64(0x3FD0765A9056E3D0))
    words.append(UInt64(0x3F804F671A14E7CB))
    words.append(UInt64(0x3FCBB2B03FBAF15B))
    words.append(UInt64(0x3F7E324B6BCD9581))
    words.append(UInt64(0x3FBB6B67E3290270))
    words.append(UInt64(0x3F6FD4860D85C921))
    words.append(UInt64(0x3FBB6B1B9A2153E9))
    words.append(UInt64(0x3F706BA260D5F89F))
    words.append(UInt64(0x3FCBB134A8D744D1))
    words.append(UInt64(0x3F819BFB61FFB1B8))
    words.append(UInt64(0x3FD0746F1F18A4E5))
    words.append(UInt64(0x3F86C6E025686ABE))
    words.append(UInt64(0x3FCBAF0181E6D014))
    words.append(UInt64(0x3F84C844ED0CEE32))
    words.append(UInt64(0x3FBB676E66679269))
    words.append(UInt64(0x3F75B4F775B0ECA8))
    words.append(UInt64(0x3FBB66F54982E330))
    words.append(UInt64(0x3F764BD0581CA8EE))
    words.append(UInt64(0x3FCBACA7161957AE))
    words.append(UInt64(0x3F87B5CEE3163FF7))
    words.append(UInt64(0x3FD071644F57E24F))
    words.append(UInt64(0x3F8E5121CD753164))
    words.append(UInt64(0x3FCBA9468ED15EE3))
    words.append(UInt64(0x3F8B5E6257FD5491))
    words.append(UInt64(0x3FBB61518496F6FF))
    words.append(UInt64(0x3F7C643730B00E5A))
    words.append(UInt64(0x3FBB609CC9690AB6))
    words.append(UInt64(0x3F7D107595D4FFD2))
    words.append(UInt64(0x3FCBA5C3D0009416))
    words.append(UInt64(0x3F8EB63D0132EB1F))
    words.append(UInt64(0x3FD06CDB800CFC33))
    words.append(UInt64(0x3F9376954B060D9F))
    words.append(UInt64(0x3FCBA0DA207A0513))
    words.append(UInt64(0x3F916D45D4411E4E))
    words.append(UInt64(0x3FBB58698A2794A7))
    words.append(UInt64(0x3F81FB7FEEA7FE12))
    words.append(UInt64(0x3FBB576852758E46))
    words.append(UInt64(0x3F825C42FC3C2258))
    words.append(UInt64(0x3FCB9BDB3E27BFCB))
    words.append(UInt64(0x3F934E116A79FC43))
    words.append(UInt64(0x3FD06668C62DAFA1))
    words.append(UInt64(0x3F984CBDDBA3FCBE))
    words.append(UInt64(0x3FCB9500A5BF2024))
    words.append(UInt64(0x3F959DAEC3DFA9DE))
    words.append(UInt64(0x3FBB4BF8BE2442D7))
    words.append(UInt64(0x3F8635ECF677A37F))
    words.append(UInt64(0x3FBB4A981EC51DB0))
    words.append(UInt64(0x3F86A13EB53A5622))
    words.append(UInt64(0x3FCB8E279F3AF4B9))
    words.append(UInt64(0x3F97B2EF628609D0))
    words.append(UInt64(0x3FD05D9318D750D5))
    words.append(UInt64(0x3F9DA9FAF7F068F0))
    words.append(UInt64(0x3FCB84E89450CAF0))
    words.append(UInt64(0x3F9A3F72845FDE8D))
    words.append(UInt64(0x3FBB3B2BB8C60F82))
    words.append(UInt64(0x3F8AE05CDC7626D6))
    words.append(UInt64(0x3FBB3956C361F3FA))
    words.append(UInt64(0x3F8B562055677FB1))
    words.append(UInt64(0x3FCB7BCD692E9C92))
    words.append(UInt64(0x3F9C88982CD354F0))
    words.append(UInt64(0x3FD051D48FDBA8C3))
    words.append(UInt64(0x3FA1C66C8AAB9814))
    words.append(UInt64(0x3FCB6FAADB867B77))
    words.append(UInt64(0x3F9F513ECF975C5C))
    words.append(UInt64(0x3FBB2519DBF05D56))
    words.append(UInt64(0x3F8FF96E98A68914))
    words.append(UInt64(0x3FBB22B9AC51A1CF))
    words.append(UInt64(0x3F903CBEAAC76B3D))
    words.append(UInt64(0x3FCB63DBCDD1BA36))
    words.append(UInt64(0x3FA0E6C52893AEC1))
    words.append(UInt64(0x3FD0429AB92846C1))
    words.append(UInt64(0x3FA4F9B58717F18C))
    words.append(UInt64(0x3FCB544B7FCFC788))
    words.append(UInt64(0x3FA268AAEF0C971C))
    words.append(UInt64(0x3FBB08C5F55C5F1B))
    words.append(UInt64(0x3F92BFA9905F7C8B))
    words.append(UInt64(0x3FBB05C1C3166AE1))
    words.append(UInt64(0x3F9304BDA9E26CA6))
    words.append(UInt64(0x3FCB454D6BCA3C5B))
    words.append(UInt64(0x3FA3BFE7D5616375))
    words.append(UInt64(0x3FD02F4709EF49F7))
    words.append(UInt64(0x3FA86D9942F6F109))
    words.append(UInt64(0x3FCB31BA67300C33))
    words.append(UInt64(0x3FA55EBD0FD2EC03))
    words.append(UInt64(0x3FBAE51F12EDDE77))
    words.append(UInt64(0x3F95B7DC86C0B1C3))
    words.append(UInt64(0x3FBAE15C482E1E32))
    words.append(UInt64(0x3F9601DDCA7D8727))
    words.append(UInt64(0x3FCB1F0934BA7287))
    words.append(UInt64(0x3FA6CE74378F3601))
    words.append(UInt64(0x3FD0172F70DEBF19))
    words.append(UInt64(0x3FAC2083420038E2))
    words.append(UInt64(0x3FCB06D45FDB93F1))
    words.append(UInt64(0x3FA8896C3DDED50D))
    words.append(UInt64(0x3FBAB901924CE841))
    words.append(UInt64(0x3F98E3DB6928DDE6))
    words.append(UInt64(0x3FBAB463E8B81DD1))
    words.append(UInt64(0x3F9932A28E165462))
    words.append(UInt64(0x3FCAEFE391EC4D53))
    words.append(UInt64(0x3FAA10DA66BC9CD2))
    words.append(UInt64(0x3FCFF33E1E1B8BBF))
    words.append(UInt64(0x3FB0083E1C198770))
    words.append(UInt64(0x3FCAD2646A9E0A81))
    words.append(UInt64(0x3FABE6F8A077F6FA))
    words.append(UInt64(0x3FBA8338756B275F))
    words.append(UInt64(0x3F9C41D9D77934C8))
    words.append(UInt64(0x3FBA7DA219F51012))
    words.append(UInt64(0x3F9C9536BFF6DB3D))
    words.append(UInt64(0x3FCAB69FD1644ABA))
    words.append(UInt64(0x3FAD852EA9183D5A))
    words.append(UInt64(0x3FCFABAE3B22AB7D))
    words.append(UInt64(0x3FB21D8DEA0E4E72))
    words.append(UInt64(0x3FCA932553278B5E))
    words.append(UInt64(0x3FAF753FF9AD0983))
    words.append(UInt64(0x3FBA427F060A44AF))
    words.append(UInt64(0x3F9FCFA7C6A7D67C))
    words.append(UInt64(0x3FBA3BD0C4BE3907))
    words.append(UInt64(0x3FA013B02C5208CC))
    words.append(UInt64(0x3FCA71F1E5A457EE))
    words.append(UInt64(0x3FB0948E90D689EC))
    words.append(UInt64(0x3FCF56200BC35B38))
    words.append(UInt64(0x3FB44EBCFB59D398))
    words.append(UInt64(0x3FCA47C3A0B06826))
    words.append(UInt64(0x3FB198D88D82B255))
    words.append(UInt64(0x3FB9F582D2A37C8A))
    words.append(UInt64(0x3FA1C552822A3F5F))
    words.append(UInt64(0x3FB9ED9C4B599638))
    words.append(UInt64(0x3FA1F339FC967763))
    words.append(UInt64(0x3FCA208082A72565))
    words.append(UInt64(0x3FB27CEE8E005BDE))
    words.append(UInt64(0x3FCEF0F566B16274))
    words.append(UInt64(0x3FB69A0FC0D84C5A))
    words.append(UInt64(0x3FC9EEDFE98BFEA5))
    words.append(UInt64(0x3FB38C9F85EA500A))
    words.append(UInt64(0x3FB99AE60F2FC099))
    words.append(UInt64(0x3FA3B7DA3A0D4AFF))
    words.append(UInt64(0x3FB991A5F42A718E))
    words.append(UInt64(0x3FA3E7A41205ABDD))
    words.append(UInt64(0x3FC9C0E7A2AE0F8B))
    words.append(UInt64(0x3FB47A120E2E1C07))
    words.append(UInt64(0x3FCE7A8448272CFB))
    words.append(UInt64(0x3FB8FD7B76B673B6))
    words.append(UInt64(0x3FC987119437C53F))
    words.append(UInt64(0x3FB5942A0634B8E1))
    words.append(UInt64(0x3FB93142643A472F))
    words.append(UInt64(0x3FA5BD979962FF00))

    return words^


def _one(value: Float64) -> List[Float64]:
    """Return a one-element list."""
    var values = List[Float64]()
    values.append(value)
    return values^


def test_cancellation_and_zero_stay_exact() raises:
    """Cancellation and signed zero keep the Sum2 total exact."""
    var first = List[Float64]()
    first.append(1.0)
    first.append(1e-16)
    first.append(-1.0)
    _inside(first)
    var second = List[Float64]()
    second.append(1e100)
    second.append(1.0)
    second.append(-1e100)
    _inside(second)
    var third = List[Float64]()
    third.append(1.0)
    third.append(-1.0)
    third.append(_float(UInt64(1) << UInt64(63)))
    third.append(0.0)
    _inside(third)
    var ulp = _float(UInt64(0x3CA0000000000000))
    var tiny = _mul(ulp, ulp)
    var fourth = List[Float64]()
    fourth.append(1.0)
    fourth.append(ulp)
    fourth.append(tiny)
    fourth.append(-ulp)
    fourth.append(-tiny)
    fourth.append(-1.0)
    _inside(fourth)
    var negative = _one(_float(UInt64(1) << UInt64(63)))
    var zero = _one(Float64(0))
    _inside(negative)
    _inside(zero)
    assert_equal(_word(_sum2(negative)), UInt64(0))
    assert_equal(_word(_sum2(zero)), UInt64(0))


def test_gradual_underflow_keeps_the_subnormal_residual() raises:
    """A cancelled normal leaves the smallest subnormal residual."""
    var eta = _float(UInt64(1))
    var normal = _float(UInt64(1) << UInt64(52))
    var many = List[Float64]()
    for _ in range(100):
        many.append(eta)
    _inside(many)
    var cancelled = List[Float64]()
    cancelled.append(normal)
    cancelled.append(eta)
    cancelled.append(-normal)
    _inside(cancelled)
    var pair = List[Float64]()
    pair.append(eta)
    pair.append(eta)
    pair.append(-eta)
    pair.append(-eta)
    _inside(pair)
    var flipped = List[Float64]()
    flipped.append(-eta)
    flipped.append(-eta)
    flipped.append(eta)
    _inside(flipped)
    assert_equal(_word(_sum2(cancelled)), UInt64(1))


def test_a_rounded_product_is_not_the_exact_fused_value() raises:
    """The stored product rounds to 1, and Sum2 does not recover the fused gap.
    """
    var step = _float(UInt64(0x3E40000000000000))
    var high = _add(1.0, step)
    var low = _sub(1.0, step)
    var product = _mul(high, low)
    assert_equal(_word(product), _word(Float64(1)))
    var values = List[Float64]()
    values.append(-1.0)
    values.append(product)
    assert_equal(_sum2(values), Float64(0))
    var fused = Fraction.from_float(high) * Fraction.from_float(low) - Fraction(
        1
    )
    assert_true(fused == Fraction.of(BigInt(-1), BigInt.power_of_two(54)))
    assert_true(fused != Fraction.from_float(_sum2(values)))


def test_native_term_words_match_the_exact_sum() raises:
    """Each reviewed native axis matches its exact sum and its stored bits."""
    var words = _native_words()
    assert_equal(len(words), 200)
    var expected = List[UInt64]()
    expected.append(UInt64(0x4031CB40CCBDAAF6))
    expected.append(UInt64(0x40038371A9A609EC))
    for axis in range(2):
        var values = List[Float64]()
        var index = axis
        while index < len(words):
            values.append(_float(words[index]))
            index += 2
        var result = _sum2(values)
        _inside(values)
        assert_equal(_word(result), expected[axis])


def main() raises:
    """Run the Sum2 oracle tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
