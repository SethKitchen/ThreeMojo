# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of one leg.

Ten transverse sections enclose the bones, knee tissues, muscles,
vessels, lymphatics and nerves. Smooth segments join those sections.
A separate shell represents the dermis for occupancy and mass.

The solid lives in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = muscle_dimensions(person)
    var d = skin_distance(dims, Vector3(0, 0.2, 0.08))
"""

from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    empty_bounds,
    field_gradient,
    mix_point,
    sd_ellipse_segment,
    smin,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurField,
    femur_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    FibulaField,
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    LATERAL_COLLATERAL,
    LATERAL_MENISCUS,
    MEDIAL_COLLATERAL,
    MEDIAL_MENISCUS,
    CartilageField,
    CollateralField,
    MeniscusField,
    femur_origin,
    fibula_origin,
    knee_dimensions_from_bones,
    patella_origin,
    tibia_origin,
)
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    DEEP_LYMPHATICS,
    INGUINAL_NODES,
    POPLITEAL_NODES,
    SUPERFICIAL_LYMPHATICS,
    LymphField,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    ACHILLES_TENDON,
    ADDUCTOR_LONGUS,
    ADDUCTOR_MAGNUS,
    BICEPS_FEMORIS,
    EXTENSOR_DIGITORUM_LONGUS,
    GASTROCNEMIUS,
    GLUTEUS_MAXIMUS,
    GLUTEUS_MEDIUS,
    GRACILIS,
    ILIOTIBIAL_TRACT,
    PATELLAR_TENDON,
    PECTINEUS,
    PERONEUS_BREVIS,
    PERONEUS_LONGUS,
    RECTUS_FEMORIS,
    SARTORIUS,
    SEMIMEMBRANOSUS,
    SEMITENDINOSUS,
    SOLEUS,
    TENSOR_FASCIAE_LATAE,
    TIBIALIS_ANTERIOR,
    TIBIALIS_POSTERIOR,
    VASTUS_INTERMEDIUS,
    VASTUS_LATERALIS,
    VASTUS_MEDIALIS,
    MuscleDimensions,
    MuscleField,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    COMMON_FIBULAR_NERVE,
    FEMORAL_NERVE,
    SAPHENOUS_NERVE,
    SCIATIC_NERVE,
    SURAL_NERVE,
    TIBIAL_NERVE,
    NerveField,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaField,
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaField,
    tibia_dimensions,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    ANTERIOR_TIBIAL_ARTERY,
    FEMORAL_ARTERY,
    FEMORAL_VEIN,
    FIBULAR_ARTERY,
    GREAT_SAPHENOUS_VEIN,
    POPLITEAL_ARTERY,
    POPLITEAL_VEIN,
    POSTERIOR_TIBIAL_ARTERY,
    SMALL_SAPHENOUS_VEIN,
    TIBIOPERONEAL_TRUNK,
    VesselField,
)
from extensions.humanoid.sex import MALE
from math.vector3 import Vector3
from std.math import max, min


@fieldwise_init
struct _SkinSection(ImplicitlyCopyable):
    """One fitted cross-section of the modeled anatomy."""

    var center: Vector3
    var ml: Float32
    var ap: Float32


@fieldwise_init
struct _EnvelopePoint(ImplicitlyCopyable):
    """One anatomical cross-section used to fit the skin."""

    var center: Vector3
    var ml: Float32
    var ap: Float32


struct SkinField(DistanceField, ImplicitlyCopyable):
    """The outer skin surface around the modeled leg anatomy."""

    var femur: FemurField
    var tibia: TibiaField
    var fibula: FibulaField
    var patella: PatellaField
    var femur_origin: Vector3
    var tibia_origin: Vector3
    var fibula_origin: Vector3
    var patella_origin: Vector3
    var cartilage: CartilageField
    var medial_meniscus: MeniscusField
    var lateral_meniscus: MeniscusField
    var medial_collateral: CollateralField
    var lateral_collateral: CollateralField
    var gluteus_maximus: MuscleField
    var gluteus_medius: MuscleField
    var tensor_fasciae_latae: MuscleField
    var iliotibial_tract: MuscleField
    var sartorius: MuscleField
    var rectus_femoris: MuscleField
    var vastus_lateralis: MuscleField
    var vastus_medialis: MuscleField
    var vastus_intermedius: MuscleField
    var pectineus: MuscleField
    var adductor_longus: MuscleField
    var adductor_magnus: MuscleField
    var gracilis: MuscleField
    var biceps_femoris: MuscleField
    var semitendinosus: MuscleField
    var semimembranosus: MuscleField
    var gastrocnemius: MuscleField
    var soleus: MuscleField
    var tibialis_anterior: MuscleField
    var tibialis_posterior: MuscleField
    var extensor_digitorum_longus: MuscleField
    var peroneus_longus: MuscleField
    var peroneus_brevis: MuscleField
    var achilles_tendon: MuscleField
    var patellar_tendon: MuscleField
    var femoral_artery: VesselField
    var popliteal_artery: VesselField
    var anterior_tibial_artery: VesselField
    var tibioperoneal_trunk: VesselField
    var posterior_tibial_artery: VesselField
    var fibular_artery: VesselField
    var femoral_vein: VesselField
    var popliteal_vein: VesselField
    var great_saphenous_vein: VesselField
    var small_saphenous_vein: VesselField
    var inguinal_nodes: LymphField
    var popliteal_nodes: LymphField
    var superficial_lymphatics: LymphField
    var deep_lymphatics: LymphField
    var femoral_nerve: NerveField
    var sciatic_nerve: NerveField
    var tibial_nerve: NerveField
    var common_fibular_nerve: NerveField
    var saphenous_nerve: NerveField
    var sural_nerve: NerveField
    var subcutaneous: Float32
    var knee_subcutaneous: Float32
    var calf_subcutaneous: Float32
    var dermis: Float32
    var s0: _SkinSection
    var s1: _SkinSection
    var s2: _SkinSection
    var s3: _SkinSection
    var s4: _SkinSection
    var s5: _SkinSection
    var s6: _SkinSection
    var s7: _SkinSection
    var s8: _SkinSection
    var s9: _SkinSection
    var skin_blend: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: MuscleDimensions) raises:
        """Build skin around the actual modeled structures.

        Args:
            dimensions: Muscle landmarks and the spec for the other parts.

        Raises:
            Error: If any underlying anatomical field refuses its inputs.
        """
        dimensions.validate()
        var S = dimensions.stature.value
        var femur_dimensions_ = femur_dimensions(
            dimensions.stature, dimensions.sex, dimensions.side
        )
        var tibia_dimensions_ = tibia_dimensions(
            dimensions.stature, dimensions.sex, dimensions.side
        )
        var fibula_dimensions_ = fibula_dimensions(
            dimensions.stature, dimensions.sex, dimensions.side
        )
        var patella_dimensions_ = patella_dimensions(
            dimensions.stature, dimensions.sex, dimensions.side
        )
        var knee = knee_dimensions_from_bones(
            femur_dimensions_,
            tibia_dimensions_,
            fibula_dimensions_,
            patella_dimensions_,
        )
        self.femur_origin = femur_origin(
            femur_dimensions_, knee.femoral_thickness
        )
        self.tibia_origin = tibia_origin(
            tibia_dimensions_, knee.tibial_thickness
        )
        self.fibula_origin = fibula_origin(
            tibia_dimensions_, self.tibia_origin, fibula_dimensions_
        )
        self.patella_origin = patella_origin(
            femur_dimensions_,
            self.femur_origin,
            patella_dimensions_,
            knee.patellar_thickness,
        )
        self.femur = FemurField(femur_dimensions_)
        self.tibia = TibiaField(tibia_dimensions_)
        self.fibula = FibulaField(fibula_dimensions_)
        self.patella = PatellaField(patella_dimensions_)
        self.cartilage = CartilageField(knee)
        self.medial_meniscus = MeniscusField(knee, MEDIAL_MENISCUS)
        self.lateral_meniscus = MeniscusField(knee, LATERAL_MENISCUS)
        self.medial_collateral = CollateralField(knee, MEDIAL_COLLATERAL)
        self.lateral_collateral = CollateralField(knee, LATERAL_COLLATERAL)
        self.gluteus_maximus = MuscleField(dimensions, GLUTEUS_MAXIMUS)
        self.gluteus_medius = MuscleField(dimensions, GLUTEUS_MEDIUS)
        self.tensor_fasciae_latae = MuscleField(
            dimensions, TENSOR_FASCIAE_LATAE
        )
        self.iliotibial_tract = MuscleField(dimensions, ILIOTIBIAL_TRACT)
        self.sartorius = MuscleField(dimensions, SARTORIUS)
        self.rectus_femoris = MuscleField(dimensions, RECTUS_FEMORIS)
        self.vastus_lateralis = MuscleField(dimensions, VASTUS_LATERALIS)
        self.vastus_medialis = MuscleField(dimensions, VASTUS_MEDIALIS)
        self.vastus_intermedius = MuscleField(dimensions, VASTUS_INTERMEDIUS)
        self.pectineus = MuscleField(dimensions, PECTINEUS)
        self.adductor_longus = MuscleField(dimensions, ADDUCTOR_LONGUS)
        self.adductor_magnus = MuscleField(dimensions, ADDUCTOR_MAGNUS)
        self.gracilis = MuscleField(dimensions, GRACILIS)
        self.biceps_femoris = MuscleField(dimensions, BICEPS_FEMORIS)
        self.semitendinosus = MuscleField(dimensions, SEMITENDINOSUS)
        self.semimembranosus = MuscleField(dimensions, SEMIMEMBRANOSUS)
        self.gastrocnemius = MuscleField(dimensions, GASTROCNEMIUS)
        self.soleus = MuscleField(dimensions, SOLEUS)
        self.tibialis_anterior = MuscleField(dimensions, TIBIALIS_ANTERIOR)
        self.tibialis_posterior = MuscleField(dimensions, TIBIALIS_POSTERIOR)
        self.extensor_digitorum_longus = MuscleField(
            dimensions, EXTENSOR_DIGITORUM_LONGUS
        )
        self.peroneus_longus = MuscleField(dimensions, PERONEUS_LONGUS)
        self.peroneus_brevis = MuscleField(dimensions, PERONEUS_BREVIS)
        self.achilles_tendon = MuscleField(dimensions, ACHILLES_TENDON)
        self.patellar_tendon = MuscleField(dimensions, PATELLAR_TENDON)
        self.femoral_artery = VesselField(dimensions, FEMORAL_ARTERY)
        self.popliteal_artery = VesselField(dimensions, POPLITEAL_ARTERY)
        self.anterior_tibial_artery = VesselField(
            dimensions, ANTERIOR_TIBIAL_ARTERY
        )
        self.tibioperoneal_trunk = VesselField(dimensions, TIBIOPERONEAL_TRUNK)
        self.posterior_tibial_artery = VesselField(
            dimensions, POSTERIOR_TIBIAL_ARTERY
        )
        self.fibular_artery = VesselField(dimensions, FIBULAR_ARTERY)
        self.femoral_vein = VesselField(dimensions, FEMORAL_VEIN)
        self.popliteal_vein = VesselField(dimensions, POPLITEAL_VEIN)
        self.great_saphenous_vein = VesselField(
            dimensions, GREAT_SAPHENOUS_VEIN
        )
        self.small_saphenous_vein = VesselField(
            dimensions, SMALL_SAPHENOUS_VEIN
        )
        self.inguinal_nodes = LymphField(dimensions, INGUINAL_NODES)
        self.popliteal_nodes = LymphField(dimensions, POPLITEAL_NODES)
        self.superficial_lymphatics = LymphField(
            dimensions, SUPERFICIAL_LYMPHATICS
        )
        self.deep_lymphatics = LymphField(dimensions, DEEP_LYMPHATICS)
        self.femoral_nerve = NerveField(dimensions, FEMORAL_NERVE)
        self.sciatic_nerve = NerveField(dimensions, SCIATIC_NERVE)
        self.tibial_nerve = NerveField(dimensions, TIBIAL_NERVE)
        self.common_fibular_nerve = NerveField(dimensions, COMMON_FIBULAR_NERVE)
        self.saphenous_nerve = NerveField(dimensions, SAPHENOUS_NERVE)
        self.sural_nerve = NerveField(dimensions, SURAL_NERVE)
        if dimensions.sex == MALE:
            self.subcutaneous = Float32(0.0073)
            self.calf_subcutaneous = Float32(0.0055)
        else:
            self.subcutaneous = Float32(0.0150)
            self.calf_subcutaneous = Float32(0.0111)
        self.knee_subcutaneous = Float32(0.5) * (
            self.subcutaneous + self.calf_subcutaneous
        )
        self.dermis = Float32(0.0018)
        self.skin_blend = 0.0020 * S
        self.epsilon = dimensions.epsilon
        var dummy = _SkinSection(dimensions.femur_mid, 0.010 * S, 0.010 * S)
        self.s0 = dummy
        self.s1 = dummy
        self.s2 = dummy
        self.s3 = dummy
        self.s4 = dummy
        self.s5 = dummy
        self.s6 = dummy
        self.s7 = dummy
        self.s8 = dummy
        self.s9 = dummy
        self.low = dimensions.plafond
        self.high = dimensions.hip
        var points = List[_EnvelopePoint]()
        _append_femur(points, self.femur, self.femur_origin)
        _append_tibia(points, self.tibia, self.tibia_origin)
        _append_fibula(points, self.fibula, self.fibula_origin)
        _append_patella(points, self.patella, self.patella_origin)
        _append_cartilage(points, self.cartilage)
        _append_circular(points, self.medial_meniscus)
        _append_circular(points, self.lateral_meniscus)
        _append_pair(
            points,
            self.medial_collateral.a,
            self.medial_collateral.ra,
            self.medial_collateral.b,
            self.medial_collateral.rb,
        )
        _append_pair(
            points,
            self.lateral_collateral.a,
            self.lateral_collateral.ra,
            self.lateral_collateral.b,
            self.lateral_collateral.rb,
        )
        _append_muscle(points, self.gluteus_maximus)
        _append_muscle(points, self.gluteus_medius)
        _append_muscle(points, self.tensor_fasciae_latae)
        _append_muscle(points, self.iliotibial_tract)
        _append_muscle(points, self.sartorius)
        _append_muscle(points, self.rectus_femoris)
        _append_muscle(points, self.vastus_lateralis)
        _append_muscle(points, self.vastus_medialis)
        _append_muscle(points, self.vastus_intermedius)
        _append_muscle(points, self.pectineus)
        _append_muscle(points, self.adductor_longus)
        _append_muscle(points, self.adductor_magnus)
        _append_muscle(points, self.gracilis)
        _append_muscle(points, self.biceps_femoris)
        _append_muscle(points, self.semitendinosus)
        _append_muscle(points, self.semimembranosus)
        _append_muscle(points, self.gastrocnemius)
        _append_muscle(points, self.soleus)
        _append_muscle(points, self.tibialis_anterior)
        _append_muscle(points, self.tibialis_posterior)
        _append_muscle(points, self.extensor_digitorum_longus)
        _append_muscle(points, self.peroneus_longus)
        _append_muscle(points, self.peroneus_brevis)
        _append_muscle(points, self.achilles_tendon)
        _append_muscle(points, self.patellar_tendon)
        _append_tube(points, self.femoral_artery.chain)
        _append_tube(points, self.popliteal_artery.chain)
        _append_tube(points, self.anterior_tibial_artery.chain)
        _append_tube(points, self.tibioperoneal_trunk.chain)
        _append_tube(points, self.posterior_tibial_artery.chain)
        _append_tube(points, self.fibular_artery.chain)
        _append_tube(points, self.femoral_vein.chain)
        _append_tube(points, self.popliteal_vein.chain)
        _append_tube(points, self.great_saphenous_vein.chain)
        _append_tube(points, self.small_saphenous_vein.chain)
        _append_nodes(points, self.inguinal_nodes)
        _append_nodes(points, self.popliteal_nodes)
        _append_tube(points, self.superficial_lymphatics.chain)
        _append_tube(points, self.superficial_lymphatics.chain2)
        _append_tube(points, self.deep_lymphatics.chain)
        _append_tube(points, self.deep_lymphatics.chain2)
        _append_tube(points, self.deep_lymphatics.chain3)
        _append_tube(points, self.deep_lymphatics.chain4)
        _append_tube(points, self.femoral_nerve.chain)
        _append_tube(points, self.sciatic_nerve.chain)
        _append_tube(points, self.tibial_nerve.chain)
        _append_tube(points, self.common_fibular_nerve.chain)
        _append_tube(points, self.saphenous_nerve.chain)
        _append_tube(points, self.sural_nerve.chain)
        var knee_center = mix_point(
            dimensions.med_condyle, dimensions.lat_condyle, 0.50
        )
        var ankle_center = mix_point(
            dimensions.med_mal, dimensions.lat_mal, 0.50
        )
        var p1 = mix_point(dimensions.hip, dimensions.femur_mid, 0.12)
        var p2 = mix_point(dimensions.hip, dimensions.femur_mid, 0.38)
        var p3 = mix_point(dimensions.hip, dimensions.femur_mid, 0.68)
        var p4 = mix_point(dimensions.femur_mid, knee_center, 0.72)
        var p6 = mix_point(knee_center, dimensions.tibia_mid, 0.32)
        var p8 = mix_point(dimensions.tibia_mid, ankle_center, 0.62)
        self.s0 = _fit_section(points, dimensions.iliac, S, self.subcutaneous)
        self.s1 = _fit_section(points, p1, S, self.subcutaneous)
        self.s2 = _fit_section(points, p2, S, self.subcutaneous)
        self.s3 = _fit_section(points, p3, S, self.subcutaneous)
        self.s4 = _fit_section(points, p4, S, self.subcutaneous)
        self.s5 = _fit_section(points, knee_center, S, self.knee_subcutaneous)
        self.s6 = _fit_section(points, p6, S, self.calf_subcutaneous)
        self.s7 = _fit_section(
            points, dimensions.tibia_mid, S, self.calf_subcutaneous
        )
        self.s8 = _fit_section(points, p8, S, self.calf_subcutaneous)
        self.s9 = _fit_section(points, ankle_center, S, self.calf_subcutaneous)
        self.s0.ml = max(self.s0.ml, Float32(0.90) * self.s1.ml)
        self.s0.ap = max(self.s0.ap, Float32(0.90) * self.s1.ap)
        var box = empty_bounds()
        box.include_ellipsoid(
            self.s0.center, Vector3(self.s0.ml, self.s0.ml, self.s0.ap)
        )
        box.include_ellipsoid(
            self.s1.center, Vector3(self.s1.ml, self.s1.ml, self.s1.ap)
        )
        box.include_ellipsoid(
            self.s2.center, Vector3(self.s2.ml, self.s2.ml, self.s2.ap)
        )
        box.include_ellipsoid(
            self.s3.center, Vector3(self.s3.ml, self.s3.ml, self.s3.ap)
        )
        box.include_ellipsoid(
            self.s4.center, Vector3(self.s4.ml, self.s4.ml, self.s4.ap)
        )
        box.include_ellipsoid(
            self.s5.center, Vector3(self.s5.ml, self.s5.ml, self.s5.ap)
        )
        box.include_ellipsoid(
            self.s6.center, Vector3(self.s6.ml, self.s6.ml, self.s6.ap)
        )
        box.include_ellipsoid(
            self.s7.center, Vector3(self.s7.ml, self.s7.ml, self.s7.ap)
        )
        box.include_ellipsoid(
            self.s8.center, Vector3(self.s8.ml, self.s8.ml, self.s8.ap)
        )
        box.include_ellipsoid(
            self.s9.center, Vector3(self.s9.ml, self.s9.ml, self.s9.ap)
        )
        var padded = box.padded(Float32(0.004))
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        var ml = Vector3(1, 0, 0)
        var d = _section_distance(point, self.s0, self.s1, ml)
        d = smin(
            d, _section_distance(point, self.s1, self.s2, ml), self.skin_blend
        )
        d = smin(
            d, _section_distance(point, self.s2, self.s3, ml), self.skin_blend
        )
        d = smin(
            d, _section_distance(point, self.s3, self.s4, ml), self.skin_blend
        )
        d = smin(
            d, _section_distance(point, self.s4, self.s5, ml), self.skin_blend
        )
        d = smin(
            d, _section_distance(point, self.s5, self.s6, ml), self.skin_blend
        )
        d = smin(
            d, _section_distance(point, self.s6, self.s7, ml), self.skin_blend
        )
        d = smin(
            d, _section_distance(point, self.s7, self.s8, ml), self.skin_blend
        )
        return smin(
            d,
            _section_distance(point, self.s8, self.s9, ml),
            self.skin_blend,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def _fit_section(
    points: List[_EnvelopePoint],
    seed: Vector3,
    S: Float32,
    cover: Float32,
) -> _SkinSection:
    """Fit one enclosing ellipse to nearby anatomical stations."""
    var least_x = seed.x
    var most_x = seed.x
    var least_z = seed.z
    var most_z = seed.z
    var half_slab = 0.035 * S
    for index in range(len(points)):  # pragma: no branch
        var sample = points[index]
        var dy = sample.center.y - seed.y
        if dy < 0:
            dy = -dy
        if dy <= half_slab:
            least_x = min(least_x, sample.center.x - sample.ml)
            most_x = max(most_x, sample.center.x + sample.ml)
            least_z = min(least_z, sample.center.z - sample.ap)
            most_z = max(most_z, sample.center.z + sample.ap)
    var center = Vector3(
        Float32(0.5) * (least_x + most_x),
        seed.y,
        Float32(0.5) * (least_z + most_z),
    )
    # 0.72 encloses the corners of the sampled ML/AP bounds.
    var ml = Float32(0.72) * (most_x - least_x) + cover
    var ap = Float32(0.72) * (most_z - least_z) + cover
    return _SkinSection(center, ml, ap)


def _append_elliptic_pair(
    mut points: List[_EnvelopePoint],
    a: Vector3,
    aml: Float32,
    aap: Float32,
    b: Vector3,
    bml: Float32,
    bap: Float32,
):
    """Append one cross-section and the midpoint to the next."""
    points.append(_EnvelopePoint(a, aml, aap))
    points.append(
        _EnvelopePoint(
            mix_point(a, b, 0.50),
            Float32(0.5) * (aml + bml),
            Float32(0.5) * (aap + bap),
        )
    )


def _append_pair(
    mut points: List[_EnvelopePoint],
    a: Vector3,
    ar: Float32,
    b: Vector3,
    br: Float32,
):
    """Append one circular cross-section and its segment midpoint."""
    _append_elliptic_pair(points, a, ar, ar, b, br, br)
    points.append(_EnvelopePoint(b, br, br))


def _append_muscle(mut points: List[_EnvelopePoint], field: MuscleField):
    """Append the nine cross-sections of one muscle field."""
    _append_elliptic_pair(
        points, field.p0, field.r0, field.a0, field.p1, field.r1, field.a1
    )
    _append_elliptic_pair(
        points, field.p1, field.r1, field.a1, field.p2, field.r2, field.a2
    )
    _append_elliptic_pair(
        points, field.p2, field.r2, field.a2, field.p3, field.r3, field.a3
    )
    _append_elliptic_pair(
        points, field.p3, field.r3, field.a3, field.p4, field.r4, field.a4
    )
    points.append(_EnvelopePoint(field.p4, field.r4, field.a4))


def _append_tube(mut points: List[_EnvelopePoint], chain: TubeChain):
    """Append the nine cross-sections of one circular tube."""
    _append_elliptic_pair(
        points, chain.p0, chain.r0, chain.r0, chain.p1, chain.r1, chain.r1
    )
    _append_elliptic_pair(
        points, chain.p1, chain.r1, chain.r1, chain.p2, chain.r2, chain.r2
    )
    _append_elliptic_pair(
        points, chain.p2, chain.r2, chain.r2, chain.p3, chain.r3, chain.r3
    )
    _append_elliptic_pair(
        points, chain.p3, chain.r3, chain.r3, chain.p4, chain.r4, chain.r4
    )
    points.append(_EnvelopePoint(chain.p4, chain.r4, chain.r4))


def _append_circular(mut points: List[_EnvelopePoint], field: MeniscusField):
    """Append the nine cross-sections of one meniscus field."""
    _append_elliptic_pair(
        points, field.p0, field.r0, field.r0, field.p1, field.r1, field.r1
    )
    _append_elliptic_pair(
        points, field.p1, field.r1, field.r1, field.p2, field.r2, field.r2
    )
    _append_elliptic_pair(
        points, field.p2, field.r2, field.r2, field.p3, field.r3, field.r3
    )
    _append_elliptic_pair(
        points, field.p3, field.r3, field.r3, field.p4, field.r4, field.r4
    )
    points.append(_EnvelopePoint(field.p4, field.r4, field.r4))


def _append_femur(
    mut points: List[_EnvelopePoint], field: FemurField, origin: Vector3
):
    """Append femoral shaft, head, trochanter and condyle sections."""
    _append_bone_chain(
        points,
        field.s0 + origin,
        field.ml0,
        field.ap0,
        field.s1 + origin,
        field.ml1,
        field.ap1,
        field.s2 + origin,
        field.ml2,
        field.ap2,
        field.s3 + origin,
        field.ml3,
        field.ap3,
        field.s4 + origin,
        field.ml4,
        field.ap4,
    )
    _append_sphere(points, field.head_center + origin, field.head_r)
    _append_ellipsoid(points, field.gt + origin, field.gt_r)
    _append_ellipsoid(points, field.lt + origin, field.lt_r)
    _append_ellipsoid(points, field.medial + origin, field.medial_r)
    _append_ellipsoid(points, field.lateral + origin, field.lateral_r)
    _append_ellipsoid(
        points, field.distal_metaphysis + origin, field.distal_metaphysis_r
    )


def _append_tibia(
    mut points: List[_EnvelopePoint], field: TibiaField, origin: Vector3
):
    """Append tibial shaft, condyle and ankle sections."""
    _append_bone_chain(
        points,
        field.s0 + origin,
        field.ml0,
        field.ap0,
        field.s1 + origin,
        field.ml1,
        field.ap1,
        field.s2 + origin,
        field.ml2,
        field.ap2,
        field.s3 + origin,
        field.ml3,
        field.ap3,
        field.s4 + origin,
        field.ml4,
        field.ap4,
    )
    _append_ellipsoid(points, field.medial + origin, field.medial_r)
    _append_ellipsoid(points, field.lateral + origin, field.lateral_r)
    _append_ellipsoid(points, field.plateau + origin, field.plateau_r)
    _append_ellipsoid(points, field.tuberosity + origin, field.tuberosity_r)
    _append_ellipsoid(points, field.plafond + origin, field.plafond_r)
    _append_ellipsoid(points, field.malleolus + origin, field.malleolus_r)


def _append_fibula(
    mut points: List[_EnvelopePoint], field: FibulaField, origin: Vector3
):
    """Append fibular shaft, head and ankle sections."""
    _append_bone_chain(
        points,
        field.s0 + origin,
        field.ml0,
        field.ap0,
        field.s1 + origin,
        field.ml1,
        field.ap1,
        field.s2 + origin,
        field.ml2,
        field.ap2,
        field.s3 + origin,
        field.ml3,
        field.ap3,
        field.s4 + origin,
        field.ml4,
        field.ap4,
    )
    _append_ellipsoid(points, field.head + origin, field.head_r)
    _append_ellipsoid(points, field.styloid + origin, field.styloid_r)
    _append_ellipsoid(points, field.malleolus + origin, field.malleolus_r)


def _append_patella(
    mut points: List[_EnvelopePoint], field: PatellaField, origin: Vector3
):
    """Append patellar body, apex, base and facet sections."""
    _append_ellipsoid(points, field.body + origin, field.body_r)
    _append_ellipsoid(points, field.apex + origin, field.apex_r)
    _append_ellipsoid(points, field.base + origin, field.base_r)
    _append_ellipsoid(points, field.medial + origin, field.medial_r)
    _append_ellipsoid(points, field.lateral + origin, field.lateral_r)


def _append_cartilage(mut points: List[_EnvelopePoint], field: CartilageField):
    """Append the articular-cartilage cross-sections."""
    _append_ellipsoid(points, field.fem_med, field.fem_med_r)
    _append_ellipsoid(points, field.fem_lat, field.fem_lat_r)
    _append_ellipsoid(points, field.troch, field.troch_r)
    _append_ellipsoid(points, field.tib_med, field.tib_med_r)
    _append_ellipsoid(points, field.tib_lat, field.tib_lat_r)
    _append_ellipsoid(points, field.pat, field.pat_r)


def _append_nodes(mut points: List[_EnvelopePoint], field: LymphField):
    """Append all five representative nodes."""
    _append_sphere(points, field.c0, field.n0)
    _append_sphere(points, field.c1, field.n1)
    _append_sphere(points, field.c2, field.n2)
    _append_sphere(points, field.c3, field.n3)
    _append_sphere(points, field.c4, field.n4)


def _append_bone_chain(
    mut points: List[_EnvelopePoint],
    p0: Vector3,
    ml0: Float32,
    ap0: Float32,
    p1: Vector3,
    ml1: Float32,
    ap1: Float32,
    p2: Vector3,
    ml2: Float32,
    ap2: Float32,
    p3: Vector3,
    ml3: Float32,
    ap3: Float32,
    p4: Vector3,
    ml4: Float32,
    ap4: Float32,
):
    """Append the nine cross-sections of one bone shaft."""
    _append_elliptic_pair(points, p0, ml0, ap0, p1, ml1, ap1)
    _append_elliptic_pair(points, p1, ml1, ap1, p2, ml2, ap2)
    _append_elliptic_pair(points, p2, ml2, ap2, p3, ml3, ap3)
    _append_elliptic_pair(points, p3, ml3, ap3, p4, ml4, ap4)
    points.append(_EnvelopePoint(p4, ml4, ap4))


def _append_sphere(
    mut points: List[_EnvelopePoint], center: Vector3, radius: Float32
):
    """Append one spherical anatomical cross-section."""
    points.append(_EnvelopePoint(center, radius, radius))


def _append_ellipsoid(
    mut points: List[_EnvelopePoint], center: Vector3, radii: Vector3
):
    """Append one ellipsoidal anatomical cross-section."""
    points.append(_EnvelopePoint(center, radii.x, radii.z))


struct SkinLayerField(DistanceField, ImplicitlyCopyable):
    """The dermal shell immediately inside a `SkinField`."""

    var outer: SkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: MuscleDimensions) raises:
        """Build the dermal shell around the modeled anatomy.

        Args:
            dimensions: Muscle landmarks and the spec for the other parts.

        Raises:
            Error: If the outer field refuses an anatomical input.
        """
        self.outer = SkinField(dimensions)
        self.thickness = self.outer.dermis
        self.low = self.outer.low
        self.high = self.outer.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the dermal shell, in meters.

        Negative is inside the dermis. Deep anatomy and exterior space
        are both outside this shell.
        """
        var d = self.outer.distance(point)
        return max(d, -d - self.thickness)


def _section_distance(
    point: Vector3, a: _SkinSection, b: _SkinSection, ml: Vector3
) -> Float32:
    """Return distance to one fitted skin segment."""
    return sd_ellipse_segment(
        point, a.center, b.center, a.ml, a.ap, b.ml, b.ap, ml
    )


def skin_distance(
    dimensions: MuscleDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the skin envelope, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        point: A point in the leg frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return SkinField(dimensions).distance(point)
