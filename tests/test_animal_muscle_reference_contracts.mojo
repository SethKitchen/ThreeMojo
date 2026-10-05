# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Source inputs remain separate from template choices and numeric guards."""

from extensions.anatomy.evidence import CROSS_CHECKED, DESIGN, FROM_TEXT
from extensions.animals.anatomy.body import BIRD, MAMMAL
from extensions.animals.anatomy.muscles import (
    MuscleSpec,
    plan_muscles,
    species_specs,
)
from extensions.animals.registry import (
    CHEETAH,
    DOG,
    SPECIES_COUNT,
    SpeciesId,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _fiber_spec(measured: Bool) raises -> MuscleSpec:
    var specs = plan_muscles(MAMMAL)
    if measured:
        specs = species_specs(DOG)
    return specs[0].copy()


def test_reference_rows_do_not_promote_template_evidence() raises:
    for i in range(SPECIES_COUNT):
        for spec in species_specs(SpeciesId(i)):
            assert_equal(spec.model_evidence(), DESIGN)
            assert_true(spec.share_source.evidence != CROSS_CHECKED)
            assert_true(spec.fiber_source.evidence != CROSS_CHECKED)
            assert_true(spec.pennation_source.evidence != CROSS_CHECKED)


def test_missing_soleus_angle_has_explicit_proxy_provenance() raises:
    for id in [DOG, CHEETAH]:
        var found = False
        for spec in species_specs(id):
            if spec.name == "soleus":
                found = True
                assert_almost_equal(spec.pennation_degrees, 3.9)
                assert_equal(spec.pennation_source.evidence, DESIGN)
                assert_equal(spec.pennation_source.source, "Eng2008")
                assert_equal(spec.share_source.evidence, FROM_TEXT)
                assert_equal(spec.share_source.source, "Hudson2011a")
        assert_true(found)


def test_bird_plan_uses_all_42_hartman_rows() raises:
    # Hartman1961 Table 3, p. 89: sorted middle values, rows 21 and 22.
    # Values are bilateral percentages; divide by 100 and then by two.
    var birds = plan_muscles(BIRD)
    assert_almost_equal(birds[0].share, (14.75 + 15.00) / 400.0)
    assert_almost_equal(birds[1].share, (1.39 + 1.44) / 400.0)
    assert_equal(birds[0].model_evidence(), DESIGN)
    assert_equal(birds[1].model_evidence(), DESIGN)


def test_direct_fiber_length_keeps_valid_scaling() raises:
    var plan = _fiber_spec(False)
    assert_almost_equal(plan.fiber_length(0.041, 0.323), 0.034)
    var measured = _fiber_spec(True)
    assert_almost_equal(measured.fiber_length(0.2, 31.8), 0.143)
    assert_almost_equal(measured.fiber_length(0.2, 8.0 * 31.8), 0.286)


def test_direct_fiber_length_rejects_invalid_arguments() raises:
    for measured in [False, True]:
        var spec = _fiber_spec(measured)
        for bad in [0.0, -1.0, nan[DType.float64](), inf[DType.float64]()]:
            with assert_raises(contains="reach"):
                _ = spec.fiber_length(bad, 1.0)
            with assert_raises(contains="body mass"):
                _ = spec.fiber_length(1.0, bad)


def test_direct_fiber_length_rejects_invalid_reference_state() raises:
    for measured in [False, True]:
        for bad in [-1.0, nan[DType.float64](), inf[DType.float64]()]:
            var spec = _fiber_spec(measured)
            spec.source_kg = bad
            with assert_raises(contains="source mass"):
                _ = spec.fiber_length(1.0, 1.0)
    for bad in [0.0, -1.0, nan[DType.float64](), inf[DType.float64]()]:
        var plan = _fiber_spec(False)
        plan.fiber_ratio = bad
        with assert_raises(contains="ratio"):
            _ = plan.fiber_length(1.0, 1.0)
        var measured = _fiber_spec(True)
        measured.fiber_m = bad
        with assert_raises(contains="Reference fiber length"):
            _ = measured.fiber_length(1.0, 1.0)


def test_direct_fiber_length_rejects_invalid_results() raises:
    var plan = _fiber_spec(False)
    plan.fiber_ratio = 1e300
    with assert_raises(contains="result"):
        _ = plan.fiber_length(1e300, 1.0)
    plan.fiber_ratio = 1e-300
    with assert_raises(contains="result"):
        _ = plan.fiber_length(1e-300, 1.0)
    var measured = _fiber_spec(True)
    measured.source_kg = 1.0
    measured.fiber_m = 1e300
    with assert_raises(contains="result"):
        _ = measured.fiber_length(1.0, 1e300)
    measured.fiber_m = 1e-300
    with assert_raises(contains="result"):
        _ = measured.fiber_length(1.0, 1e-300)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
