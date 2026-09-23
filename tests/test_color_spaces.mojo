# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.color_spaces`: three.js's `ColorManagement` and the
spaces of `examples/jsm/math/ColorSpaces.js`.

The expected conversions were calculated by three.js 0.180, by node on
`ColorManagement.convert` with the four spaces of `ColorSpaces.js` defined:
three colors, from each of six spaces to each.
"""

from render.color_spaces import (
    D65,
    DISPLAY_P3_COLOR_SPACE,
    EXTENDED_SRGB_COLOR_SPACE,
    LINEAR_DISPLAY_P3_COLOR_SPACE,
    LINEAR_REC2020_COLOR_SPACE,
    LINEAR_SRGB_COLOR_SPACE,
    LINEAR_TRANSFER,
    NO_COLOR_SPACE,
    P3_PRIMARIES,
    REC2020_PRIMARIES,
    REC709_PRIMARIES,
    SRGB_COLOR_SPACE,
    SRGB_TRANSFER,
    ColorSpaceId,
    ColorTransfer,
    color_space,
    color_space_name,
    conversion_matrix,
    convert,
    linear_to_srgb_three,
    srgb_to_linear_three,
    transfer_of,
)
from render.framebuffer import FloatColor
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)


def check(
    source: ColorSpaceId,
    target: ColorSpaceId,
    r: Float32,
    g: Float32,
    b: Float32,
    er: Float64,
    eg: Float64,
    eb: Float64,
) raises:
    """Assert one conversion against three.js's, alpha kept."""
    var out = convert(FloatColor(r, g, b, 0.5), source, target)
    assert_almost_equal(Float64(out.r), er, atol=TOLERANCE)
    assert_almost_equal(Float64(out.g), eg, atol=TOLERANCE)
    assert_almost_equal(Float64(out.b), eb, atol=TOLERANCE)
    assert_equal(out.a, 0.5)


def test_convert_matches_three() raises:
    """Every pair of spaces, three colors each."""
    check(SRGB_COLOR_SPACE, SRGB_COLOR_SPACE, 1, 0, 0, 1.0, 0.0, 0.0)
    check(SRGB_COLOR_SPACE, SRGB_COLOR_SPACE, 0.25, 0.5, 0.75, 0.25, 0.5, 0.75)
    check(
        SRGB_COLOR_SPACE, SRGB_COLOR_SPACE, 0.02, 0.9, 0.001, 0.02, 0.9, 0.001
    )
    check(SRGB_COLOR_SPACE, LINEAR_SRGB_COLOR_SPACE, 1, 0, 0, 1.0, 0.0, 0.0)
    check(
        SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.050876088164650994,
        0.2140411404715882,
        0.5225215539594343,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.001547987616,
        0.7874122893910657,
        7.739938080000001e-05,
    )
    check(
        SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.91748883110906,
        0.20029255462303036,
        0.13856568866544872,
    )
    check(
        SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.3130110750938544,
        0.4941103807578015,
        0.7301542196924276,
    )
    check(
        SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.411502776868975,
        0.8866895363962243,
        0.2650395886267218,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.8224619821354799,
        0.03319418360945996,
        0.017082598067640002,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.07984406981289857,
        0.20862501278841053,
        0.49213142298557927,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.14106869459620397,
        0.761326224135566,
        0.05710354785609316,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        1,
        0,
        0,
        0.62740390517572,
        0.06909725054308001,
        0.016391441464999996,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.1250319628432314,
        0.2062718847393295,
        0.4876402510598606,
    )
    check(
        SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.26025600627606593,
        0.7241652582498387,
        0.06939748370311684,
    )
    check(
        SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        0.9999999999999999,
        0.0,
        0.0,
    )
    check(
        SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25000605604610776,
        0.5000057038898478,
        0.7500034834463251,
    )
    check(
        SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.01999999999872,
        0.9000015216532112,
        0.000999999999936,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        1,
        0,
        0,
        0.9999999999999999,
        0.0,
        0.0,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.5371042026626895,
        0.7353606352856507,
        0.8808268158925643,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.15170911025124179,
        0.9546878810938558,
        0.012920000000000001,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE, LINEAR_SRGB_COLOR_SPACE, 1, 0, 0, 1.0, 0.0, 0.0
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25,
        0.5,
        0.75,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.02,
        0.9,
        0.001,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.91748883110906,
        0.20029255462303036,
        0.13856568866544872,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.5788267036428403,
        0.7298683391963858,
        0.866830202463772,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.45683212011312396,
        0.9409020386239108,
        0.2858190729782913,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.8224619821354799,
        0.03319418360945996,
        0.017082598067640002,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.29438445773123484,
        0.49170147279905746,
        0.7233593274550051,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.1762333603264241,
        0.8707891854597268,
        0.06640986396408585,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        1,
        0,
        0,
        0.62740390517572,
        0.06909725054308001,
        0.016391441464999996,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.35397724727535496,
        0.48556618783263494,
        0.719800999765385,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.30894604488503563,
        0.8289796736183205,
        0.08043543684635437,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        0.9999999999999999,
        0.0,
        0.0,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.5371042026626895,
        0.7353606352856507,
        0.8808268158925643,
    )
    check(
        LINEAR_SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.15170911025124179,
        0.9546878810938558,
        0.012920000000000001,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.0930647164361962,
        -0.5433741511669604,
        -0.25371732894862115,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.12408101052624312,
        0.5073514352944246,
        0.771130646788406,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -2.2638999324537035,
        0.9165034641022628,
        -0.7992878078162268,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.2249399378491899,
        -0.04205682284573997,
        -0.019637564160109998,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.014173705601999376,
        0.22090337093359702,
        0.556041208707255,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -0.17522445297629283,
        0.8204633203494988,
        -0.061864381409924674,
    )
    check(
        DISPLAY_P3_COLOR_SPACE, DISPLAY_P3_COLOR_SPACE, 1, 0, 0, 1.0, 0.0, 0.0
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25,
        0.5,
        0.75,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.02,
        0.9,
        0.001,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        1.0,
        0.0,
        0.0,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.050876088164650994,
        0.2140411404715882,
        0.5225215539594343,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.001547987616,
        0.7874122893910657,
        7.739938080000001e-05,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        1,
        0,
        0,
        0.7538329402084,
        0.04574390765356001,
        -0.0012103190078499998,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.10571622147387341,
        0.21042678644839302,
        0.5176626387494984,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.15754861969400563,
        0.7416386707921919,
        0.013934095314922557,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.0930647164361962,
        -0.5433741511669604,
        -0.25371732894862115,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.12408101052624312,
        0.5073514352944246,
        0.771130646788406,
    )
    check(
        DISPLAY_P3_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -2.2638999324537035,
        0.9165034641022628,
        -0.7992878078162268,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.0930647164361962,
        -0.5433741511669604,
        -0.25371732894862115,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.47746187012816205,
        0.7422435655709931,
        0.8959800607980153,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -2.299079677899296,
        0.9717847886259466,
        -0.9052645852934379,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.2249399378491899,
        -0.04205682284573997,
        -0.019637564160109998,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.1937649072942051,
        0.5105142625446824,
        0.77947780329868,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -0.1779473434906576,
        0.9370100901109962,
        -0.07006691836636517,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.9999999999999999,
        0.0,
        0.0,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.5371042026626895,
        0.7353606352856507,
        0.8808268158925643,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.15170911025124179,
        0.9546878810938558,
        0.012920000000000001,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        1.0,
        0.0,
        0.0,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25,
        0.5,
        0.75,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.02,
        0.9,
        0.001,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        1,
        0,
        0,
        0.7538329402084,
        0.04574390765356001,
        -0.0012103190078499998,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.32343412313275,
        0.49168367603916996,
        0.74620477812995,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.1938618659787055,
        0.8485267830280768,
        0.016800981728578777,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.0930647164361962,
        -0.5433741511669604,
        -0.25371732894862115,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.47746187012816205,
        0.7422435655709931,
        0.8959800607980153,
    )
    check(
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -2.299079677899296,
        0.9717847886259466,
        -0.9052645852934379,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.2482153665235782,
        -1.6091915236268766,
        -0.23450783805803196,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.2863634412823238,
        0.7541791924470466,
        0.8983864798144129,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -6.4049624956385065,
        1.0074842153031807,
        -1.1597678741769621,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.6604908314475604,
        -0.12455042752530004,
        -0.0181507614596,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.06666472599253992,
        0.5290503045481352,
        0.7842201211430074,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -0.49574013124137045,
        1.0171106057915182,
        -0.08976531533877416,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        1.1381484785818268,
        -0.8436429617406055,
        0.03645719555600638,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.42193084984604223,
        0.7443138303108128,
        0.8826381354010838,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -2.934798215387068,
        0.9853037987564933,
        -0.2140254878988224,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        1.34357814043348,
        -0.06529744285917999,
        0.0028217643619199984,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.1487557812497899,
        0.5137017607365602,
        0.7534887288360975,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -0.2271515646584418,
        0.9668927535241785,
        -0.016565440239846935,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        1,
        0,
        0,
        1.0,
        0.0,
        0.0,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25,
        0.5,
        0.75,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.02,
        0.9,
        0.001,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.2482153665235782,
        -1.6091915236268766,
        -0.23450783805803196,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.2863634412823238,
        0.7541791924470466,
        0.8983864798144129,
    )
    check(
        LINEAR_REC2020_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        -6.4049624956385065,
        1.0074842153031807,
        -1.1597678741769621,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        1,
        0,
        0,
        0.9999999999999999,
        0.0,
        0.0,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25000605604610776,
        0.5000057038898478,
        0.7500034834463251,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.01999999999872,
        0.9000015216532112,
        0.000999999999936,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.0,
        0.0,
        0.0,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.050876088164650994,
        0.2140411404715882,
        0.5225215539594343,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.001547987616,
        0.7874122893910657,
        7.739938080000001e-05,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.91748883110906,
        0.20029255462303036,
        0.13856568866544872,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.3130110750938544,
        0.4941103807578015,
        0.7301542196924276,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.411502776868975,
        0.8866895363962243,
        0.2650395886267218,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        1,
        0,
        0,
        0.8224619821354799,
        0.03319418360945996,
        0.017082598067640002,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.07984406981289857,
        0.20862501278841053,
        0.49213142298557927,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.14106869459620397,
        0.761326224135566,
        0.05710354785609316,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        1,
        0,
        0,
        0.62740390517572,
        0.06909725054308001,
        0.016391441464999996,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.1250319628432314,
        0.2062718847393295,
        0.4876402510598606,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.26025600627606593,
        0.7241652582498387,
        0.06939748370311684,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        1,
        0,
        0,
        1.0,
        0.0,
        0.0,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.25,
        0.5,
        0.75,
        0.25,
        0.5,
        0.75,
    )
    check(
        EXTENDED_SRGB_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
        0.02,
        0.9,
        0.001,
        0.02,
        0.9,
        0.001,
    )


def test_no_color_space_is_left_alone() raises:
    """Numbers that are not color are never converted."""
    var c = FloatColor(0.1, 0.2, 0.3, 1)
    var out = convert(c, NO_COLOR_SPACE, DISPLAY_P3_COLOR_SPACE)
    assert_equal(out.r, c.r)
    out = convert(c, SRGB_COLOR_SPACE, NO_COLOR_SPACE)
    assert_equal(out.b, c.b)


def test_refuses_what_is_not_a_color_space() raises:
    """A value outside the list is refused at every door."""
    var bad = ColorSpaceId(7)
    var c = FloatColor(0.1, 0.2, 0.3, 1)
    with assert_raises(contains="Not a color space"):
        _ = convert(c, bad, SRGB_COLOR_SPACE)
    with assert_raises(contains="Not a color space"):
        _ = convert(c, SRGB_COLOR_SPACE, ColorSpaceId(-1))
    with assert_raises(contains="Not a color space"):
        _ = color_space(bad)
    with assert_raises(contains="Not a color space"):
        _ = color_space_name(bad)
    with assert_raises(contains="Not a color space"):
        _ = transfer_of(bad)
    with assert_raises(contains="no definition"):
        _ = color_space(NO_COLOR_SPACE)
    assert_false(ColorSpaceId(7).is_valid())
    assert_true(EXTENDED_SRGB_COLOR_SPACE.is_valid())


def test_definitions_match_three() raises:
    """Primaries, white point, transfer, luminance and the output spaces."""
    var srgb = color_space(SRGB_COLOR_SPACE)
    assert_true(srgb.primaries == REC709_PRIMARIES)
    assert_true(srgb.white_point == D65)
    assert_true(srgb.transfer == SRGB_TRANSFER)
    assert_equal(srgb.luminance_coefficients[1], 0.7152)
    assert_true(srgb.drawing_buffer.value() == SRGB_COLOR_SPACE)
    assert_false(Bool(srgb.unpack))
    assert_false(srgb.extended_tone_mapping)
    var linear = color_space(LINEAR_SRGB_COLOR_SPACE)
    assert_true(linear.transfer == LINEAR_TRANSFER)
    assert_true(linear.unpack.value() == SRGB_COLOR_SPACE)
    var p3 = color_space(DISPLAY_P3_COLOR_SPACE)
    assert_true(p3.primaries == P3_PRIMARIES)
    assert_true(p3.primaries != REC709_PRIMARIES)
    assert_equal(p3.luminance_coefficients[0], 0.2289)
    assert_equal(p3.to_xyz.get(0, 0), 0.4865709)
    assert_equal(p3.from_xyz.get(2, 2), 0.9568845)
    assert_true(p3.drawing_buffer.value() == DISPLAY_P3_COLOR_SPACE)
    var linear_p3 = color_space(LINEAR_DISPLAY_P3_COLOR_SPACE)
    assert_true(linear_p3.transfer == LINEAR_TRANSFER)
    assert_true(linear_p3.unpack.value() == DISPLAY_P3_COLOR_SPACE)
    var rec2020 = color_space(LINEAR_REC2020_COLOR_SPACE)
    assert_true(rec2020.primaries == REC2020_PRIMARIES)
    assert_false(Bool(rec2020.drawing_buffer))
    assert_equal(rec2020.luminance_coefficients[2], 0.0593)
    assert_equal(rec2020.to_xyz.get(1, 2), 0.0593017)
    var extended = color_space(EXTENDED_SRGB_COLOR_SPACE)
    assert_true(extended.extended_tone_mapping)
    assert_true(extended.drawing_buffer.value() == SRGB_COLOR_SPACE)
    assert_equal(extended.to_xyz.get(2, 1), 0.1191948)


def test_names_and_transfers() raises:
    """The strings of three.js, and the transfer of each space."""
    assert_equal(color_space_name(NO_COLOR_SPACE), "")
    assert_equal(color_space_name(SRGB_COLOR_SPACE), "srgb")
    assert_equal(color_space_name(LINEAR_SRGB_COLOR_SPACE), "srgb-linear")
    assert_equal(color_space_name(DISPLAY_P3_COLOR_SPACE), "display-p3")
    assert_equal(
        color_space_name(LINEAR_DISPLAY_P3_COLOR_SPACE), "display-p3-linear"
    )
    assert_equal(color_space_name(LINEAR_REC2020_COLOR_SPACE), "rec2020-linear")
    assert_equal(color_space_name(EXTENDED_SRGB_COLOR_SPACE), "extended-srgb")
    assert_true(transfer_of(NO_COLOR_SPACE) == LINEAR_TRANSFER)
    assert_true(transfer_of(DISPLAY_P3_COLOR_SPACE) == SRGB_TRANSFER)
    assert_true(transfer_of(LINEAR_REC2020_COLOR_SPACE) == LINEAR_TRANSFER)
    assert_true(LINEAR_TRANSFER.is_valid())
    assert_true(SRGB_TRANSFER.is_valid())
    assert_false(ColorTransfer(2).is_valid())


def test_matrix_element_refusals() raises:
    """A matrix has three rows and three columns."""
    var m = color_space(SRGB_COLOR_SPACE).to_xyz
    assert_equal(m.get(1, 0), 0.2126390)
    with assert_raises(contains="0 to 2"):
        _ = m.get(3, 0)
    with assert_raises(contains="0 to 2"):
        _ = m.get(-1, 0)
    with assert_raises(contains="0 to 2"):
        _ = m.get(0, 3)
    with assert_raises(contains="0 to 2"):
        _ = m.get(0, -1)


def test_conversion_matrix_is_what_convert_applies() raises:
    """Linear sRGB red in linear Display P3, by the matrix and by convert.

    three.js's `_getMatrix` gives 0.738, -0.060, -0.017 for this: the two
    matrices multiplied the other way round.
    """
    var m = conversion_matrix(
        LINEAR_SRGB_COLOR_SPACE, LINEAR_DISPLAY_P3_COLOR_SPACE
    )
    assert_almost_equal(m.get(0, 0), 0.82246198213547994, atol=1e-12)
    assert_almost_equal(m.get(1, 0), 0.033194183609459957, atol=1e-12)
    assert_almost_equal(m.get(2, 0), 0.017082598067640002, atol=1e-12)
    var same = conversion_matrix(SRGB_COLOR_SPACE, LINEAR_SRGB_COLOR_SPACE)
    assert_almost_equal(same.get(0, 0), 1, atol=1e-6)
    assert_almost_equal(same.get(0, 1), 0, atol=1e-6)


def test_transfer_functions_are_three_s() raises:
    """Both sides of each knee, with three.js's constants."""
    assert_almost_equal(
        srgb_to_linear_three(0.04), 0.04 * 0.0773993808, atol=1e-15
    )
    assert_almost_equal(
        srgb_to_linear_three(0.5), 0.21404114048223255, atol=1e-9
    )
    assert_almost_equal(linear_to_srgb_three(0.003), 0.003 * 12.92, atol=1e-15)
    assert_almost_equal(linear_to_srgb_three(0.5), 0.7353610205, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
