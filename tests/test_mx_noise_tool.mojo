# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The MaterialX noise reference gives the numpy transcription's values.

The expected text is what the numpy transcription printed with numpy 2.5.
"""

from std.memory import bitcast
from std.testing import TestSuite, assert_equal

from tools._float32 import round32
from tools.mx_noise_reference import report


def test_the_values_match_the_numpy_transcription() raises:
    assert_equal(
        report(),
        (
            "perlin_vec3 [0.3, 0.7] [0.04074367880821228, 0.6510121822357178,"
            " -0.30239030718803406]\nperlin_vec3 [-1.25, 2.5]"
            " [-0.4991074204444885, 0.0029074219055473804,"
            " -0.07123183459043503]\nperlin_vec3 [0.3, 0.7, 0.2]"
            " [0.2737118899822235, -0.18833453953266144,"
            " 0.40486136078834534]\nperlin_vec3 [3.1, -2.3, 5.9]"
            " [0.07585524767637253, -0.061793237924575806,"
            " 0.1329670399427414]\ncell_float [0.3] 0.5824258327484131"
            " cell_vec3 [0.8603127598762512, 0.842521071434021,"
            " 0.9748212099075317]\ncell_float [-1.25, 2.5] 0.5628882646560669"
            " cell_vec3 [0.9262238144874573, 0.7473284602165222,"
            " 0.4198946952819824]\ncell_float [0.3, 0.7, 0.2]"
            " 0.6110676527023315 cell_vec3 [0.11157296597957611,"
            " 0.3250998854637146, 0.33994728326797485]\ncell_float [3.1, -2.3,"
            " 5.9, -0.4] 0.4390026032924652 cell_vec3 [0.11370349675416946,"
            " 0.10571760684251785, 0.41482704877853394]\nworley [0.3, 0.7] 1.0"
            " 1 [0.3611402213573456]\nworley [0.3, 0.7] 1.0 2"
            " [0.3611402213573456, 0.4000799059867859]\nworley [0.3, 0.7] 1.0 3"
            " [0.3611402213573456, 0.4000799059867859,"
            " 1.0939582586288452]\nworley [0.3, 0.7] 0.5 1"
            " [0.19280943274497986]\nworley [0.3, 0.7] 0.5 2"
            " [0.19280943274497986, 0.459095299243927]\nworley [0.3, 0.7] 0.5 3"
            " [0.19280943274497986, 0.459095299243927,"
            " 0.8585674166679382]\nworley [-1.25, 2.5, 0.6] 1.0 1"
            " [0.2914171814918518]\nworley [-1.25, 2.5, 0.6] 1.0 2"
            " [0.2914171814918518, 0.4579774737358093]\nworley [-1.25, 2.5,"
            " 0.6] 1.0 3 [0.2914171814918518, 0.4579774737358093,"
            " 0.5820276737213135]\nworley [-1.25, 2.5, 0.6] 0.5 1"
            " [0.09683658182621002]\nworley [-1.25, 2.5, 0.6] 0.5 2"
            " [0.09683658182621002, 0.5652338266372681]\nworley [-1.25, 2.5,"
            " 0.6] 0.5 3 [0.09683658182621002, 0.5652338266372681,"
            " 0.6648467183113098]\n"
        ),
    )


def test_round32_rounds_once_with_ties_to_even() raises:
    assert_equal(round32(1.0), Float32(1.0))
    assert_equal(round32(-0.0), Float32(-0.0))
    # 1 + 2**-24 is a tie: it rounds to even, which is 1.
    assert_equal(round32(1.0 + 2.0**-24), Float32(1.0))
    # 1 + 3 * 2**-24 is a tie: it rounds up to 1 + 2**-22.
    assert_equal(round32(1.0 + 3.0 * 2.0**-24), Float32(1.0 + 2.0**-22))
    assert_equal(
        round32(1.0 + 2.0**-24 + 2.0**-40), Float32(1.0 + 2.0**-23)
    )
    # Rounding up across a power of two.
    assert_equal(round32(2.0 - 2.0**-30), Float32(2.0))
    # The smallest subnormal, and a value that rounds to zero.
    assert_equal(bitcast[DType.uint32](round32(2.0**-149)), UInt32(1))
    assert_equal(round32(2.0**-151), Float32(0.0))
    assert_equal(round32(1e-310), Float32(0.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
