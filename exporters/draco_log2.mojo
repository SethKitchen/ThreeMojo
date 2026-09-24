# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The base-two logarithm of the C library that Draco's WebAssembly
encoder links: musl's `log2`, from Arm's optimized routines.

Draco's encoder picks between codings by estimates of their size in
bits, and those estimates sum logarithms. `std.math.log2` and the host C
library round some logarithms to the other neighbor of the true value.
A choice that rests on such a sum can then differ from the encoder that
three.js runs. This module ports musl 1.2.2's `log2`, which Emscripten
compiles into that encoder, with its tables and without the fused
multiply-add that WebAssembly does not have.

musl's `log2` is Copyright (c) 2018, Arm Limited, under the MIT License.
See THIRD-PARTY-NOTICES.md.
"""

from loaders.vrml_geometry import product
from std.memory import bitcast

# The bits of 1.0.
comptime _ONE: UInt64 = 0x3FF0000000000000
# The bits of the edges of the range near 1.0 that has its own polynomial.
comptime _LO: UInt64 = 0x3FEEA4AF00000000
comptime _HI: UInt64 = 0x3FF0B55900000000
# The bits of the start of the range that the tables split.
comptime _OFF: UInt64 = 0x3FE6000000000000
# `1/ln(2)` in two doubles.
comptime _INV_LN2_HI: UInt64 = 0x3FF7154765200000
comptime _INV_LN2_LO: UInt64 = 0x3DE705FC2EEFA200
# The polynomial near 1.0.
comptime _POLY1: List[UInt64] = [
    0xBFE71547652B82FE,
    0x3FDEC709DC3A03F7,
    0xBFD71547652B7C3F,
    0x3FD2776C50F05BE4,
    0xBFCEC709DD768FE5,
    0x3FCA61761EC4E736,
    0xBFC7153FBC64A79B,
    0x3FC484D154F01B4A,
    0xBFC289E4A72C383C,
    0x3FC0B32F285AEE66,
]
# The polynomial of the rest.
comptime _POLY: List[UInt64] = [
    0xBFE71547652B8339,
    0x3FDEC709DC3A04BE,
    0xBFD7154764702FFB,
    0x3FD2776C50034C48,
    0xBFCEC7B328EA92BC,
    0x3FCA6225E117F92E,
]
# `1/c` and `log2(c)` for each of the 64 parts of the range.
comptime _TAB: List[UInt64] = [
    0x3FF724286BB1ACF8,
    0xBFE1095FEECDB000,
    0x3FF6E1F766D2CCA1,
    0xBFE08494BD76D000,
    0x3FF6A13D0E30D48A,
    0xBFE00143AEE8F800,
    0x3FF661EC32D06C85,
    0xBFDEFEC5360B4000,
    0x3FF623FA951198F8,
    0xBFDDFDD91AB7E000,
    0x3FF5E75BA4CF026C,
    0xBFDCFFAE0CC79000,
    0x3FF5AC055A214FB8,
    0xBFDC043811FDA000,
    0x3FF571ED0F166E1E,
    0xBFDB0B67323AE000,
    0x3FF53909590BF835,
    0xBFDA152F5A2DB000,
    0x3FF5014FED61ADDD,
    0xBFD9217F5AF86000,
    0x3FF4CAB88E487BD0,
    0xBFD8304DB0719000,
    0x3FF49539B4334FEE,
    0xBFD74189F9A9E000,
    0x3FF460CBDFAFD569,
    0xBFD6552BB5199000,
    0x3FF42D664EE4B953,
    0xBFD56B23A29B1000,
    0x3FF3FB01111DD8A6,
    0xBFD483650F5FA000,
    0x3FF3C995B70C5836,
    0xBFD39DE937F6A000,
    0x3FF3991C4AB6FD4A,
    0xBFD2BAA1538D6000,
    0x3FF3698E0CE099B5,
    0xBFD1D98340CA4000,
    0x3FF33AE48213E7B2,
    0xBFD0FA853A40E000,
    0x3FF30D191985BDB1,
    0xBFD01D9C32E73000,
    0x3FF2E025CAB271D7,
    0xBFCE857DA2FA6000,
    0x3FF2B404CF13CD82,
    0xBFCCD3C8633D8000,
    0x3FF288B02C7CCB50,
    0xBFCB26034C14A000,
    0x3FF25E2263944DE5,
    0xBFC97C1C2F4FE000,
    0x3FF234563D8615B1,
    0xBFC7D6023F800000,
    0x3FF20B46E33EAF38,
    0xBFC633A71A05E000,
    0x3FF1E2EEFDCDA3DD,
    0xBFC494F5E9570000,
    0x3FF1BB4A580B3930,
    0xBFC2F9E424E0A000,
    0x3FF19453847F2200,
    0xBFC162595AFDC000,
    0x3FF16E06C0D5D73C,
    0xBFBF9C9A75BD8000,
    0x3FF1485F47B7E4C2,
    0xBFBC7B575BF9C000,
    0x3FF12358AD0085D1,
    0xBFB960C60FF48000,
    0x3FF0FEF00F532227,
    0xBFB64CE247B60000,
    0x3FF0DB2077D03A8F,
    0xBFB33F78B2014000,
    0x3FF0B7E6D65980D9,
    0xBFB0387D1A42C000,
    0x3FF0953EFE7B408D,
    0xBFAA6F9208B50000,
    0x3FF07325CAC53B83,
    0xBFA47A954F770000,
    0x3FF05197E40D1B5C,
    0xBF9D23A8C50C0000,
    0x3FF03091C1208EA2,
    0xBF916A2629780000,
    0x3FF0101025B37E21,
    0xBF7720F8D8E80000,
    0x3FEFC07EF9CAA76B,
    0x3F86FE53B1500000,
    0x3FEF4465D3F6F184,
    0x3FA11CCCE10F8000,
    0x3FEECC079F84107F,
    0x3FAC4DFC8C8B8000,
    0x3FEE573A99975AE8,
    0x3FB3AA321E574000,
    0x3FEDE5D6F0BD3DE6,
    0x3FB918A0D08B8000,
    0x3FED77B681FF38B3,
    0x3FBE72E9DA044000,
    0x3FED0CB5724DE943,
    0x3FC1DCD2507F6000,
    0x3FECA4B2DC0E7563,
    0x3FC476AB03DEA000,
    0x3FEC3F8EE8D6CB51,
    0x3FC7074377E22000,
    0x3FEBDD2B4F020C4C,
    0x3FC98EDE8BA94000,
    0x3FEB7D6C006015CA,
    0x3FCC0DB86AD2E000,
    0x3FEB20366E2E338F,
    0x3FCE840AAFCEE000,
    0x3FEAC57026295039,
    0x3FD0790AB4678000,
    0x3FEA6D01BC2731DD,
    0x3FD1AC056801C000,
    0x3FEA16D3BC3FF18B,
    0x3FD2DB11D4FEE000,
    0x3FE9C2D14967FEAD,
    0x3FD406464EC58000,
    0x3FE970E4F47C9902,
    0x3FD52DBE093AF000,
    0x3FE920FB3982BCF2,
    0x3FD651902050D000,
    0x3FE8D30187F759F1,
    0x3FD771D2CDEAF000,
    0x3FE886E5EBB9F66D,
    0x3FD88E9C857D9000,
    0x3FE83C97B658B994,
    0x3FD9A80155E16000,
    0x3FE7F405FFC61022,
    0x3FDABE186ED3D000,
    0x3FE7AD22181415CA,
    0x3FDBD0F2AEA0E000,
    0x3FE767DCF99EFF8C,
    0x3FDCE0A43DBF4000,
]
# `c` in two doubles, for each part.
comptime _TAB2: List[UInt64] = [
    0x3FE6200012B90A8E,
    0x3C8904AB0644B605,
    0x3FE66000045734A6,
    0x3C61FF9BEA62F7A9,
    0x3FE69FFFC325F2C5,
    0x3C827ECFCB3C90BA,
    0x3FE6E00038B95A04,
    0x3C88FF8856739326,
    0x3FE71FFFE09994E3,
    0x3C8AFD40275F82B1,
    0x3FE7600015590E10,
    0xBC72FD75B4238341,
    0x3FE7A00012655BD5,
    0x3C7808E67C242B76,
    0x3FE7E0003259E9A6,
    0xBC6208E426F622B7,
    0x3FE81FFFEDB4B2D2,
    0xBC8402461EA5C92F,
    0x3FE860002DFAFCC3,
    0x3C6DF7F4A2F29A1F,
    0x3FE89FFFF78C6B50,
    0xBC8E0453094995FD,
    0x3FE8E00039671566,
    0xBC8A04F3BEC77B45,
    0x3FE91FFFE2BF1745,
    0xBC77FA34400E203C,
    0x3FE95FFFCC5C9FD1,
    0xBC76FF8005A0695D,
    0x3FE9A0003BBA4767,
    0x3C70F8C4C4EC7E03,
    0x3FE9DFFFE7B92DA5,
    0x3C8E7FD9478C4602,
    0x3FEA1FFFD72EFDAF,
    0xBC6A0C554DCDAE7E,
    0x3FEA5FFFDE04FF95,
    0x3C867DA98CE9B26B,
    0x3FEA9FFFCA5E8D2B,
    0xBC8284C9B54C13DE,
    0x3FEADFFFDDAD03EA,
    0x3C5812C8EA602E3C,
    0x3FEB1FFFF10D3D4D,
    0xBC8EFADDAD27789C,
    0x3FEB5FFFCE21165A,
    0x3C53CB1719C61237,
    0x3FEB9FFFD950E674,
    0x3C73F7D94194CE00,
    0x3FEBE000139CA8AF,
    0x3C750AC4215D9BC0,
    0x3FEC20005B46DF99,
    0x3C6BEEA653E9C1C9,
    0x3FEC600040B9F7AE,
    0xBC7C079F274A70D6,
    0x3FECA0006255FD8A,
    0xBC7A0B4076E84C1F,
    0x3FECDFFFD94C095D,
    0x3C88F933F99AB5D7,
    0x3FED1FFFF975D6CF,
    0xBC582C08665FE1BE,
    0x3FED5FFFA2561C93,
    0xBC7B04289BD295F3,
    0x3FED9FFF9D228B0C,
    0x3C870251340FA236,
    0x3FEDE00065BC7E16,
    0xBC75011E16A4D80C,
    0x3FEE200002F64791,
    0x3C89802F09EF62E0,
    0x3FEE600057D7A6D8,
    0xBC7E0B75580CF7FA,
    0x3FEEA00027EDC00C,
    0xBC8C848309459811,
    0x3FEEE0006CF5CB7C,
    0xBC8F8027951576F4,
    0x3FEF2000782B7DCC,
    0xBC8F81D97274538F,
    0x3FEF6000260C450A,
    0xBC4071002727FFDC,
    0x3FEF9FFFE88CD533,
    0xBC581BDCE1FDA8B0,
    0x3FEFDFFFD50F8689,
    0x3C87F91ACB918E6E,
    0x3FF0200004292367,
    0x3C9B7FF365324681,
    0x3FF05FFFE3E3D668,
    0x3C86FA08DDAE957B,
    0x3FF0A0000A85A757,
    0xBC57E2DE80D3FB91,
    0x3FF0E0001A5F3FCC,
    0xBC91823305C5F014,
    0x3FF11FFFF8AFBAF5,
    0xBC8BFABB6680BAC2,
    0x3FF15FFFE54D91AD,
    0xBC9D7F121737E7EF,
    0x3FF1A00011AC36E1,
    0x3C9C000A0516F5FF,
    0x3FF1E00019C84248,
    0xBC9082FBE4DA5DA0,
    0x3FF220000FFE5E6E,
    0xBC88FDD04C9CFB43,
    0x3FF26000269FD891,
    0x3C8CFE2A7994D182,
    0x3FF2A00029A6E6DA,
    0xBC700273715E8BC5,
    0x3FF2DFFFE0293E39,
    0x3C9B7C39DAB2A6F9,
    0x3FF31FFFF7DCF082,
    0x3C7DF1336EDC5254,
    0x3FF35FFFF05A8B60,
    0xBC9E03564CCD31EB,
    0x3FF3A0002E0EAECC,
    0x3C75F0E74BD3A477,
    0x3FF3E000043BB236,
    0x3C9C7DCB149D8833,
    0x3FF4200002D187FF,
    0x3C7E08AFCF2D3D28,
    0x3FF460000D387CB1,
    0x3C820837856599A6,
    0x3FF4A00004569F89,
    0xBC89FA5C904FBCD2,
    0x3FF4E000043543F3,
    0xBC781125ED175329,
    0x3FF51FFFCC027F0F,
    0x3C9883D8847754DC,
    0x3FF55FFFFD87B36F,
    0xBC8709E731D02807,
    0x3FF59FFFF21DF7BA,
    0x3C87F79F68727B02,
    0x3FF5DFFFEBFC3481,
    0xBC9180902E30E93E,
]


def _f(bits: UInt64) -> Float64:
    """The double whose bits these are."""
    return bitcast[DType.float64](bits)


def _high(x: Float64) -> Float64:
    """The double with the low 32 bits of `x` cleared."""
    return _f(bitcast[DType.uint64](x) & 0xFFFFFFFF00000000)


def musl_log2(x: Float64) raises -> Float64:
    """Return musl's `log2(x)` for a positive, finite, normal `x`.

    Args:
        x: The number.

    Returns:
        Its base-two logarithm, rounded as musl rounds it.

    Raises:
        Error: If `x` is not positive, finite and normal: Draco never
            takes the logarithm of such a number.
    """
    var ix = bitcast[DType.uint64](x)
    var top = ix >> 48
    if top - 0x0010 >= 0x7FF0 - 0x0010:
        raise Error("Draco: a logarithm of a number that is not positive")
    if ix - _LO < _HI - _LO:
        if ix == _ONE:
            return 0.0
        var r = x - 1.0
        var rhi = _high(r)
        var rlo = r - rhi
        var hi = product(rhi, _f(_INV_LN2_HI))
        var lo = product(rlo, _f(_INV_LN2_HI)) + product(r, _f(_INV_LN2_LO))
        var r2 = product(r, r)
        var r4 = product(r2, r2)
        var b = materialize[_POLY1]()
        var p = product(r2, _f(b[0]) + product(r, _f(b[1])))
        var y = hi + p
        lo += hi - y + p
        var inner = (
            _f(b[2])
            + product(r, _f(b[3]))
            + product(r2, _f(b[4]) + product(r, _f(b[5])))
            + product(
                r4,
                _f(b[6])
                + product(r, _f(b[7]))
                + product(r2, _f(b[8]) + product(r, _f(b[9]))),
            )
        )
        lo += product(r4, inner)
        y += lo
        return y
    var tmp = ix - _OFF
    var i = Int((tmp >> 46) % 64)
    var k = Int(bitcast[DType.int64](tmp) >> 52)
    var iz = ix - (tmp & (UInt64(0xFFF) << 52))
    var tab = materialize[_TAB]()
    var tab2 = materialize[_TAB2]()
    var invc = _f(tab[2 * i])
    var logc = _f(tab[2 * i + 1])
    var z = _f(iz)
    var kd = Float64(k)
    var r = product(z - _f(tab2[2 * i]) - _f(tab2[2 * i + 1]), invc)
    var rhi = _high(r)
    var rlo = r - rhi
    var t1 = product(rhi, _f(_INV_LN2_HI))
    var t2 = product(rlo, _f(_INV_LN2_HI)) + product(r, _f(_INV_LN2_LO))
    var t3 = kd + logc
    var hi = t3 + t1
    var lo = t3 - hi + t1 + t2
    var r2 = product(r, r)
    var r4 = product(r2, r2)
    var a = materialize[_POLY]()
    var p = (
        _f(a[0])
        + product(r, _f(a[1]))
        + product(r2, _f(a[2]) + product(r, _f(a[3])))
        + product(r4, _f(a[4]) + product(r, _f(a[5])))
    )
    return lo + product(r2, p) + hi
