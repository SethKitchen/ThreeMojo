# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The shared extraction preserves the original humanoid import types."""

from extensions.anatomy.tissue import BoneTissue, CORTICAL, TRABECULAR
from extensions.anatomy.soft_tissue import (
    SoftTissue,
    MUSCLE,
    CARTILAGE,
    ADIPOSE,
)
from extensions.humanoid.skeleton.tissue import (
    BoneKind as LegacyBoneKind,
    BoneTissue as LegacyBoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftTissue as LegacySoftTissue,
    SoftTissueKind as LegacySoftTissueKind,
    muscle_tissue,
    cartilage_tissue,
    adipose_tissue,
    arterial_tissue,
    venous_tissue,
    vessel_tissue,
    ligament_tissue,
    meniscus_tissue,
    tendon_tissue,
    lymph_tissue,
    nerve_tissue,
    skin_tissue,
    hair_tissue,
    filled_density,
    SOFT_FILL,
)
from std.testing import TestSuite, assert_equal, assert_true


def test_old_bone_imports_are_the_same_shared_types() raises:
    var cortex: BoneTissue = cortical_tissue()
    var legacy: LegacyBoneTissue = cortex
    legacy.validate()
    assert_equal(LegacyBoneKind(0), CORTICAL)
    assert_equal(legacy.kind, CORTICAL)
    var trabecular: BoneTissue = trabecular_tissue()
    assert_equal(trabecular.kind, TRABECULAR)


def test_old_soft_imports_and_mass_consumers_keep_type_identity() raises:
    var muscle: SoftTissue = muscle_tissue()
    var legacy: LegacySoftTissue = muscle
    legacy.validate()
    assert_equal(LegacySoftTissueKind(3), MUSCLE)
    assert_equal(
        filled_density(SOFT_FILL, muscle).value, muscle.wet_density.value
    )
    assert_equal(cartilage_tissue().kind, CARTILAGE)
    assert_equal(adipose_tissue().kind, ADIPOSE)
    for tissue in [
        arterial_tissue(),
        venous_tissue(),
        vessel_tissue(True),
        ligament_tissue(),
        meniscus_tissue(),
        tendon_tissue(),
        lymph_tissue(),
        nerve_tissue(),
        skin_tissue(),
        hair_tissue(),
    ]:
        var same: SoftTissue = tissue
        same.validate()
        assert_true(same.kind.is_valid())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
