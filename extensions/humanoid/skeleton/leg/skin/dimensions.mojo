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
    var fascia_blend: Float32
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
        self.fascia_blend = 0.0060 * S
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
        self.s0 = self._fit_section(dimensions.iliac, S, self.subcutaneous)
        self.s1 = self._fit_section(p1, S, self.subcutaneous)
        self.s2 = self._fit_section(p2, S, self.subcutaneous)
        self.s3 = self._fit_section(p3, S, self.subcutaneous)
        self.s4 = self._fit_section(p4, S, self.subcutaneous)
        self.s5 = self._fit_section(knee_center, S, self.knee_subcutaneous)
        self.s6 = self._fit_section(p6, S, self.calf_subcutaneous)
        self.s7 = self._fit_section(
            dimensions.tibia_mid, S, self.calf_subcutaneous
        )
        self.s8 = self._fit_section(p8, S, self.calf_subcutaneous)
        self.s9 = self._fit_section(ankle_center, S, self.calf_subcutaneous)
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
        self, seed: Vector3, S: Float32, cover: Float32
    ) -> _SkinSection:
        """Fit one enclosing ellipse to a thin anatomical slab."""
        var least_x = seed.x
        var most_x = seed.x
        var least_z = seed.z
        var most_z = seed.z
        var half_slab = 0.010 * S
        for ix in range(41):
            var x = (
                seed.x
                + (Float32(ix) / Float32(40) * Float32(0.28) - Float32(0.14))
                * S
            )
            for iz in range(41):
                var z = (
                    seed.z
                    + (
                        Float32(iz) / Float32(40) * Float32(0.28)
                        - Float32(0.14)
                    )
                    * S
                )
                var d = self._anatomy_distance(
                    Vector3(x, seed.y - half_slab, z)
                )
                d = min(d, self._anatomy_distance(Vector3(x, seed.y, z)))
                d = min(
                    d,
                    self._anatomy_distance(Vector3(x, seed.y + half_slab, z)),
                )
                if d <= 0:
                    least_x = min(least_x, x)
                    most_x = max(most_x, x)
                    least_z = min(least_z, z)
                    most_z = max(most_z, z)
        var center = Vector3(
            Float32(0.5) * (least_x + most_x),
            seed.y,
            Float32(0.5) * (least_z + most_z),
        )
        # 0.72 encloses the corners of the sampled ML/AP bounds.
        var ml = Float32(0.72) * (most_x - least_x) + cover
        var ap = Float32(0.72) * (most_z - least_z) + cover
        return _SkinSection(center, ml, ap)

    def _anatomy_distance(self, point: Vector3) -> Float32:
        """Return distance to every modeled structure below the skin."""
        return min(self._support_distance(point), self._system_distance(point))

    def _support_distance(self, point: Vector3) -> Float32:
        """Return distance to the bones, knee tissues and muscles."""
        var d = self.femur.distance(point - self.femur_origin)
        d = smin(
            d,
            self.tibia.distance(point - self.tibia_origin),
            self.fascia_blend,
        )
        d = smin(
            d,
            self.fibula.distance(point - self.fibula_origin),
            self.fascia_blend,
        )
        d = smin(
            d,
            self.patella.distance(point - self.patella_origin),
            self.fascia_blend,
        )
        d = smin(d, self.cartilage.distance(point), self.fascia_blend)
        d = smin(d, self.medial_meniscus.distance(point), self.fascia_blend)
        d = smin(d, self.lateral_meniscus.distance(point), self.fascia_blend)
        d = smin(d, self.medial_collateral.distance(point), self.fascia_blend)
        d = smin(d, self.lateral_collateral.distance(point), self.fascia_blend)
        d = smin(d, self.gluteus_maximus.distance(point), self.fascia_blend)
        d = smin(d, self.gluteus_medius.distance(point), self.fascia_blend)
        d = smin(
            d, self.tensor_fasciae_latae.distance(point), self.fascia_blend
        )
        d = smin(d, self.iliotibial_tract.distance(point), self.fascia_blend)
        d = smin(d, self.sartorius.distance(point), self.fascia_blend)
        d = smin(d, self.rectus_femoris.distance(point), self.fascia_blend)
        d = smin(d, self.vastus_lateralis.distance(point), self.fascia_blend)
        d = smin(d, self.vastus_medialis.distance(point), self.fascia_blend)
        d = smin(d, self.vastus_intermedius.distance(point), self.fascia_blend)
        d = smin(d, self.pectineus.distance(point), self.fascia_blend)
        d = smin(d, self.adductor_longus.distance(point), self.fascia_blend)
        d = smin(d, self.adductor_magnus.distance(point), self.fascia_blend)
        d = smin(d, self.gracilis.distance(point), self.fascia_blend)
        d = smin(d, self.biceps_femoris.distance(point), self.fascia_blend)
        d = smin(d, self.semitendinosus.distance(point), self.fascia_blend)
        d = smin(d, self.semimembranosus.distance(point), self.fascia_blend)
        d = smin(d, self.gastrocnemius.distance(point), self.fascia_blend)
        d = smin(d, self.soleus.distance(point), self.fascia_blend)
        d = smin(d, self.tibialis_anterior.distance(point), self.fascia_blend)
        d = smin(d, self.tibialis_posterior.distance(point), self.fascia_blend)
        d = smin(
            d,
            self.extensor_digitorum_longus.distance(point),
            self.fascia_blend,
        )
        d = smin(d, self.peroneus_longus.distance(point), self.fascia_blend)
        d = smin(d, self.peroneus_brevis.distance(point), self.fascia_blend)
        d = smin(d, self.achilles_tendon.distance(point), self.fascia_blend)
        return smin(d, self.patellar_tendon.distance(point), self.fascia_blend)

    def _system_distance(self, point: Vector3) -> Float32:
        """Return distance to the vessels, lymphatics and nerves."""
        var d = self.femoral_artery.distance(point)
        d = min(d, self.popliteal_artery.distance(point))
        d = min(d, self.anterior_tibial_artery.distance(point))
        d = min(d, self.posterior_tibial_artery.distance(point))
        d = min(d, self.fibular_artery.distance(point))
        d = min(d, self.femoral_vein.distance(point))
        d = min(d, self.popliteal_vein.distance(point))
        d = min(d, self.great_saphenous_vein.distance(point))
        d = min(d, self.small_saphenous_vein.distance(point))
        d = min(d, self.inguinal_nodes.distance(point))
        d = min(d, self.popliteal_nodes.distance(point))
        d = min(d, self.superficial_lymphatics.distance(point))
        d = min(d, self.deep_lymphatics.distance(point))
        d = min(d, self.femoral_nerve.distance(point))
        d = min(d, self.sciatic_nerve.distance(point))
        d = min(d, self.tibial_nerve.distance(point))
        d = min(d, self.common_fibular_nerve.distance(point))
        d = min(d, self.saphenous_nerve.distance(point))
        return min(d, self.sural_nerve.distance(point))


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
