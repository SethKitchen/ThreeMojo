# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Mutable reference and sampled-mass boundaries remain explicit estimates."""

from extensions.anatomy.inertia import InertiaTally
from extensions.animals.anatomy.body import (
    BODY_LENGTH,
    MAMMAL,
    BodyPlan,
    SHOULDER_HEIGHT,
    TOTAL_LENGTH,
    ReferenceKind,
)
from extensions.animals.anatomy.axial import axial_muscles
from extensions.animals.anatomy.stance import _load, standing_loads
from extensions.animals.anatomy.muscles import AnimalMuscle
from extensions.animals.rig import Rig
from extensions.animals.anatomy.engineering import calibrate, calibrated_mass
from extensions.animals.anatomy.mass import BodyMass, _check_sampling_model
from extensions.animals.anatomy.reference import _extent, reference_length
from extensions.animals.build import create_animal
from extensions.animals.options import CROWD, Variant, animal_options
from extensions.animals.registry import CHICKEN, RAT, SPIDER, SpeciesId
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import (
    BoneId,
    PrimitiveKind,
    SurfacePart,
    CONE,
    LENS,
    FIN,
)
from extensions.sdf.vector import V3
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_almost_equal,
)
from units.si import Length, Mass


def _mass() -> BodyMass:
    return BodyMass(
        [InertiaTally()],
        Length(0.01),
        SIMD[DType.float64, 8](0, 1, 0, 1, 0, 1, 1, 0),
    )


def test_sampled_reference_handles_all_kinds_and_missing_extents() raises:
    var mass = _mass()
    for kind in [BODY_LENGTH, SHOULDER_HEIGHT, TOTAL_LENGTH]:
        assert_equal(mass.reference(kind).value, 1.0)
    for kind in [ReferenceKind(-1), ReferenceKind(3)]:
        with assert_raises(contains="named"):
            _ = mass.reference(kind)
    for value in [Float32(0), nan[DType.float32](), inf[DType.float32]()]:
        mass = _mass()
        mass.withers = Length(value)
        with assert_raises(contains="under-resolved"):
            _ = mass.reference(SHOULDER_HEIGHT)
        mass.body_length = Length(value)
        with assert_raises(contains="under-resolved"):
            _ = mass.reference(BODY_LENGTH)
        mass.total_length = Length(value)
        with assert_raises(contains="under-resolved"):
            _ = mass.reference(TOTAL_LENGTH)
    mass = _mass()
    mass.withers = Length(-1)
    with assert_raises(contains="no withers"):
        _ = mass.reference(SHOULDER_HEIGHT)
    for index in [-1, 1]:
        with assert_raises(contains="no such bone"):
            _ = mass.bone(index, 1)
    with assert_raises(contains="positive mass"):
        _ = mass.bone(0, 1)
    with assert_raises(contains="positive mass"):
        _ = mass.total()


def test_calibration_rejects_mutable_identity_and_scale_boundaries() raises:
    var cal = calibrate(SPIDER, Variant(-1), allow_estimates=True)
    for index in [-2, 100000]:
        var bad = cal
        bad.variant = Variant(index)
        with assert_raises(contains="variant"):
            bad.check()
    var bad = cal
    bad.species = SpeciesId(-1)
    with assert_raises(contains="species"):
        bad.check()
    for value in [
        Float64(-1),
        Float64(0),
        Float64(1000),
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        bad = cal
        bad.scale = value
        with assert_raises(contains="scale"):
            bad.check()
    bad = cal
    bad.published = bad.published.scaled(2)
    with assert_raises(contains="match its species"):
        bad.check()
    bad = cal
    bad.published_mass = Mass(bad.published_mass.value * 2)
    with assert_raises(contains="match its species"):
        bad.check()
    for value in [Float32(0), nan[DType.float32](), inf[DType.float32]()]:
        bad = cal
        bad.measured = Length(value)
        with assert_raises(contains="reference quantities"):
            bad.check()
        bad = cal
        bad.predicted_mass = Mass(value)
        with assert_raises(contains="reference quantities"):
            bad.check()
        bad = cal
        bad.published_mass = Mass(value)
        with assert_raises(contains="reference quantities"):
            bad.check()


def test_unmatched_calibration_never_normalizes_even_inside_ratio_tolerance() raises:
    var cal = calibrate(SPIDER, Variant(0), allow_estimates=True)
    assert_equal(cal.density_factor, 1.0)
    # The prior relative-reference comparison permits a tiny mismatch,
    # but unmatched morphs require exactly neutral normalization.
    cal.density_factor = 1.000001
    with assert_raises(contains="unmatched morph"):
        cal.check()
    cal.density_factor = 1.0
    cal.allow_estimates = False
    with assert_raises(contains="allow_estimates"):
        cal.check()
    # Chicken has a cited mass excerpt but an unverified length input.
    with assert_raises(contains="allow_estimates"):
        _ = calibrate(CHICKEN, Variant(-1))


def test_calibration_checks_resolved_animal_variant_and_resolution() raises:
    var cal = calibrate(RAT, Variant(-1), allow_estimates=True)
    var animal = create_animal(RAT, animal_options(1, quality=CROWD))
    for index in [-1, 100000]:
        animal.traits.variant = index
        with assert_raises(contains="resolved variant"):
            cal.check_animal(animal)
    animal = create_animal(RAT, animal_options(1, quality=CROWD))
    for cells in [
        Float64(0),
        Float64(-1),
        Float64(401),
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        with assert_raises(contains="cells"):
            _ = calibrated_mass(animal, cal, cells)


def _model() raises -> SdfModel:
    var model = SdfModel()
    _ = model.sphere("body", BoneId(0), V3(0, 0, 0), 1.0)
    return model^


def test_sampler_geometry_preflight_rejects_nonfinite_components() raises:
    var model = _model()
    _check_sampling_model(model)
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        model = _model()
        model.outline.append(value)
        with assert_raises(contains="outline"):
            _check_sampling_model(model)
        for axis in range(3):
            model = _model()
            if axis == 0:
                model.prims[0].c.x = value
            elif axis == 1:
                model.prims[0].c.y = value
            else:
                model.prims[0].c.z = value
            with assert_raises(contains="geometry"):
                _check_sampling_model(model)
        for member in range(3):
            model = _model()
            if member == 0:
                model.prims[0].k = value
            elif member == 1:
                model.prims[0].lo = value
            else:
                model.prims[0].hi = value
            with assert_raises(contains="geometry"):
                _check_sampling_model(model)
    model = _model()
    model.prims[0].part = SurfacePart(-1)
    with assert_raises(contains="named"):
        _check_sampling_model(model)
    model = _model()
    model.prims[0].kind = PrimitiveKind(-1)
    with assert_raises(contains="named"):
        _check_sampling_model(model)
    model = _model()
    model.prims[0].k = -0.1
    with assert_raises(contains="blend radius"):
        _check_sampling_model(model)
    model = _model()
    model.prims[0].r.z = 0
    with assert_raises(contains="ellipsoid radii"):
        _check_sampling_model(model)


def test_sampler_preflight_keeps_cone_lens_and_fin_domains_distinct() raises:
    var model = _model()
    model.prims[0].kind = CONE
    model.prims[0].b = V3(0, 1, 0)
    model.prims[0].r = V3(0.1, 0.1, 0)
    _check_sampling_model(model)
    model.prims[0].r.x = -0.1
    with assert_raises(contains="cone radii"):
        _check_sampling_model(model)
    model.prims[0].r.x = 0.1
    model.prims[0].b = model.prims[0].c
    with assert_raises(contains="valid ends"):
        _check_sampling_model(model)
    model.prims[0].b = V3(1e308, 0, 0)
    model.prims[0].c = V3(-1e308, 0, 0)
    with assert_raises(contains="valid ends"):
        _check_sampling_model(model)
    model = _model()
    model.prims[0].kind = LENS
    model.prims[0].r = V3(0.2, 0.1, 0)
    model.prims[0].lo = -0.3
    model.prims[0].hi = 0.3
    _check_sampling_model(model)
    model.prims[0].r.x = 0.1
    with assert_raises(contains="arc and depth"):
        _check_sampling_model(model)
    model.prims[0].r.x = 0.2
    model.prims[0].hi = -0.3
    with assert_raises(contains="arc and depth"):
        _check_sampling_model(model)
    model = _model()
    model.prims[0].kind = FIN
    model.prims[0].r = V3(0.1, 0, 0)
    model.prims[0].first = 0
    model.prims[0].count = 3
    model.outline = [Float64(0), 0, 1, 0, 0, 1]
    _check_sampling_model(model)
    model.prims[0].first = -1
    with assert_raises(contains="outside"):
        _check_sampling_model(model)
    model.prims[0].first = 0
    model.prims[0].count = 2
    with assert_raises(contains="outside"):
        _check_sampling_model(model)
    model.prims[0].count = 4
    with assert_raises(contains="outside"):
        _check_sampling_model(model)
    model.prims[0].count = 3
    model.prims[0].r.x = 0
    with assert_raises(contains="thickness"):
        _check_sampling_model(model)
    model.prims[0].r.x = 0.1
    model.prims[0].r.y = -0.1
    with assert_raises(contains="thickness"):
        _check_sampling_model(model)


def test_reference_lens_envelope_has_independent_axis_extents() raises:
    var model = _model()
    model.prims[0].kind = LENS
    model.prims[0].r = V3(0.2, 0.1, 0)
    model.prims[0].lo = -0.3
    model.prims[0].hi = 0.5
    _check_sampling_model(model)
    var x = _extent(model.prims[0], model.outline, V3(1, 0, 0))
    var y = _extent(model.prims[0], model.outline, V3(0, 1, 0))
    var z = _extent(model.prims[0], model.outline, V3(0, 0, 1))
    assert_almost_equal(x[0], -sqrt(0.03), atol=1e-12)
    assert_almost_equal(x[1], sqrt(0.03), atol=1e-12)
    assert_almost_equal(y[0], -0.1, atol=1e-12)
    assert_almost_equal(y[1], 0.1, atol=1e-12)
    assert_almost_equal(z[0], -0.3, atol=1e-12)
    assert_almost_equal(z[1], 0.5, atol=1e-12)


def test_reference_rejects_absent_and_unrepresentable_landmarks() raises:
    var animal = create_animal(RAT, animal_options(1, quality=CROWD))
    animal.model = SdfModel()
    with assert_raises(contains="finite SI length"):
        _ = reference_length(animal)
    for radius in [Float64(1e-100), Float64(1e39)]:
        var model = SdfModel()
        _ = model.sphere("head", animal.rig.bone("head"), V3(0, 0, 0), radius)
        animal.model = model^
        with assert_raises(contains="finite SI length"):
            _ = reference_length(animal)


def test_empty_axial_plan_is_well_defined_and_mismatched_mass_is_rejected() raises:
    var rig = Rig()
    var mass = _mass()
    with assert_raises(contains="another rig"):
        _ = axial_muscles(rig, MAMMAL, mass)
    mass.bones.clear()
    with assert_raises(contains="named"):
        _ = axial_muscles(rig, BodyPlan(-1), mass)
    assert_equal(len(axial_muscles(rig, MAMMAL, mass)), 0)


def test_standing_load_inputs_reject_nonfinite_forces_and_wrong_mass_identity() raises:
    var animal = create_animal(RAT, animal_options(1, quality=CROWD))
    var muscles = List[AnimalMuscle]()
    var foot = animal.rig.j("kneeL")
    for value in [Float64(-1), nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises(contains="force and moment inputs"):
            _ = _load(animal, muscles, "kneeL", foot, value)
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises(contains="force and moment inputs"):
            _ = _load(animal, muscles, "kneeL", foot, 0, value)
    var empty = _mass()
    with assert_raises(contains="another rig"):
        _ = standing_loads(animal, empty, muscles)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
