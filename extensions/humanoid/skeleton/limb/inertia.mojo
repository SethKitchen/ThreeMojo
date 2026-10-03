# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mass, center of mass and inertia tensor of a thigh, a shank or a foot.

A rigid-body model of a limb needs each segment's inertial properties.
This file integrates them over the one skin of a limb: every grid cell
inside the skin takes the density of what fills it.

| Fill | Density |
|---|---|
| Dermis, the skin's outer shell | `skin_tissue` |
| Cortical or trabecular bone | The bone's apparent density |
| Marrow | `adipose_tissue`: adult yellow marrow is mostly fat |
| A muscle belly or a tendon | `muscle_tissue` or `tendon_tissue` |
| Everything else | `adipose_tissue` |

Knee tissues, foot ligaments, vessels, lymphatics and nerves have no
separate density assignment. A higher-priority overlapping region wins;
otherwise they use the adipose proxy. No uncertainty bound is asserted.
Bone pore-fluid and pore-marrow mass is not added to apparent bone mass.

De Leva (1996) provides context for these authored segment cuts.
Horizontal planes through the hip center, femoral-condyle midpoint
and lateral malleolus divide thigh, shank and foot.

    var thigh = segment_inertia(person, THIGH)
    thigh.mass.to(KILOGRAM)

The results live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import mix_point
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootBoneField,
    named_foot_bones,
)
from extensions.humanoid.skeleton.foot.bones.mass import (
    foot_bone_field_occupancy,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleField,
    foot_muscle_dimensions,
    named_foot_muscles,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    is_tendon as is_foot_tendon,
)
from extensions.humanoid.skeleton.leg.assembly import LegAssembly, assemble_leg
from extensions.humanoid.skeleton.leg.femur.dimensions import FemurField
from extensions.humanoid.skeleton.leg.femur.mass import femur_field_occupancy
from extensions.humanoid.skeleton.leg.fibula.dimensions import FibulaField
from extensions.humanoid.skeleton.leg.fibula.mass import (
    fibula_field_occupancy,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleField,
    is_tendon,
    named_muscle_parts,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import PatellaField
from extensions.humanoid.skeleton.leg.patella.mass import (
    patella_field_occupancy,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import TibiaField
from extensions.humanoid.skeleton.leg.tibia.mass import tibia_field_occupancy
from extensions.humanoid.skeleton.limb.skin import LimbSkinField
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    MARROW,
    BoneOccupancy,
    check_mass_step,
)
from extensions.humanoid.skeleton.soft_tissue import (
    adipose_tissue,
    muscle_tissue,
    skin_tissue,
    tendon_tissue,
)
from extensions.humanoid.skeleton.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.limb.sampling import SampleGrid
from extensions.humanoid.skeleton.limb.regions import (
    LimbRegion,
    DERMIS_REGION,
    CORTICAL_REGION,
    TRABECULAR_REGION,
    MARROW_PROXY_REGION,
    MUSCLE_REGION,
    TENDON_REGION,
    FAT_PROXY_REGION,
)
from math.vector3 import Vector3
from std.math import isfinite, sqrt
from units.si import (
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    Length,
    METER,
    MILLIMETER,
    Mass,
    MomentOfInertia,
    Volume,
)

# Default maximum grid-cell width. Convergence depends on the spec and
# reported quantity; no universal sampling-error claim is made.
comptime INERTIA_STEP = Length(5.0, MILLIMETER)


@fieldwise_init
struct LimbSegment(Equatable, ImplicitlyCopyable, Writable):
    """Which segment of a limb `segment_inertia` integrates.

    The type stops a bare integer at compile time. A value that is not a
    named segment is still constructible, and `segment_inertia` refuses
    it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named segment."""
        return self == THIGH or self == SHANK or self == FOOT_SEGMENT


# From the hip joint's center to the knee's.
comptime THIGH = LimbSegment(0)
# From the knee joint's center to the lateral malleolus.
comptime SHANK = LimbSegment(1)
# Below the lateral malleolus.
comptime FOOT_SEGMENT = LimbSegment(2)


@fieldwise_init
struct SegmentInertia(ImplicitlyCopyable):
    """The inertial properties of one segment.

    The inertia tensor is about the center of mass, along the leg
    frame's axes: `xx`, `yy` and `zz` on the diagonal and the products
    `xy`, `xz` and `yz` off it, with the sign convention of a tensor,
    so an off-diagonal entry is minus the product of inertia.
    """

    var mass: Mass
    # The center of mass in the leg frame, in meters.
    var center: Vector3
    var xx: MomentOfInertia
    var yy: MomentOfInertia
    var zz: MomentOfInertia
    var xy: MomentOfInertia
    var xz: MomentOfInertia
    var yz: MomentOfInertia
    # The segment's length, joint center to joint center, or heel to toe.
    var length: Length

    def gyration(self, moment: MomentOfInertia) -> Length:
        """Return the radius of gyration of one principal moment.

        Args:
            moment: `xx`, `yy` or `zz`.

        Returns:
            The square root of the moment over the mass.
        """
        return Length(sqrt(moment.value / self.mass.value), METER)


@fieldwise_init
struct SegmentEstimate(ImplicitlyCopyable):
    """One segment estimate with exclusive region accounting.

    `region_volumes` are in cubic meters; `region_masses` are in kilograms.
    Their first seven entries follow `LimbRegion`; the last is padding.
    Bounds are meters in the canonical leg frame. They are integration
    cut planes, not a measured anatomical tissue partition.
    """

    var inertia: SegmentInertia
    """Mass, center and full tensor about the center of mass."""
    var region_volumes: SIMD[DType.float64, 8]
    """Exclusive region volumes in cubic meters; entry seven is padding."""
    var region_masses: SIMD[DType.float64, 8]
    """Assigned region masses in kilograms; entry seven is padding."""
    var low: Vector3
    """Minimum canonical integration corner, in meters."""
    var high: Vector3
    """Maximum canonical integration corner, in meters."""
    var step: Length
    """Maximum requested grid-cell width."""

    def region_volume(self, region: LimbRegion) raises -> Volume:
        """Return one exclusive density region's sampled volume.

        Args:
            region: A named density assignment.

        Returns:
            The region volume.

        Raises:
            Error: If the region is not named.
        """
        if not region.is_valid():
            raise Error("A limb region must be named")
        return Volume(Float32(self.region_volumes[region.value]))

    def region_mass(self, region: LimbRegion) raises -> Mass:
        """Return one exclusive density region's assigned mass.

        Args:
            region: A named density assignment.

        Returns:
            The mass assigned to that region.

        Raises:
            Error: If the region is not named.
        """
        if not region.is_valid():
            raise Error("A limb region must be named")
        return Mass(Float32(self.region_masses[region.value]))


@fieldwise_init
struct _Box(ImplicitlyCopyable):
    """The region a segment's cells are drawn from."""

    var low: Vector3
    var high: Vector3


def segment_inertia(
    spec: HumanoidSpec,
    segment: LimbSegment,
    side: BodySide = RIGHT,
    step: Length = INERTIA_STEP,
) raises -> SegmentInertia:
    """Return the mass, center of mass and inertia of one segment.

    Args:
        spec: Standing height, osteological sex and athleticism.
        segment: `THIGH`, `SHANK` or `FOOT_SEGMENT`.
        side: `RIGHT` or `LEFT`. A right limb is the default.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        The segment's inertial properties in the leg frame.

    Raises:
        Error: If `spec` or `side` is refused, if `segment` is not
            named, or if `step` is out of range.
    """
    return segment_estimate(spec, segment, side, step).inertia


def segment_estimate(
    spec: HumanoidSpec,
    segment: LimbSegment,
    side: BodySide = RIGHT,
    step: Length = INERTIA_STEP,
) raises -> SegmentEstimate:
    """Return a canonical segment estimate and its exclusive density regions.

    Args:
        spec: Standing height, osteological sex and athleticism.
        segment: `THIGH`, `SHANK` or `FOOT_SEGMENT`.
        side: The named side. A right limb is the default.
        step: Maximum cell width, 2 mm through 20 mm.

    Returns:
        Inertia, exact sampling bounds and per-region accounting.

    Raises:
        Error: If the spec, side, segment or step is invalid, or the
            sampling box exceeds the bounded grid work limit.
    """
    if not segment.is_valid():
        raise Error("A limb segment must be the thigh, the shank or the foot")
    check_mass_step(step, "limb segment")
    var pose = assemble_leg(spec, side)
    var skin = LimbSkinField(spec, side)
    var ankle = pose.ankle_center()
    var hip = pose.hip_center()
    var knee = mix_point(
        pose.muscles.med_condyle, pose.muscles.lat_condyle, 0.5
    )
    var malleolus = pose.fibula_origin + pose.fibula.lateral_malleolus
    var box = _Box(skin.low, skin.high)
    var length: Float32
    if segment == THIGH:
        box.low.y = knee.y
        box.high.y = hip.y
        length = (hip - knee).length()
    elif segment == SHANK:
        box.low.y = malleolus.y
        box.high.y = knee.y
        length = (knee - malleolus).length()
    else:
        box.high.y = malleolus.y
        var foot = foot_muscle_dimensions(spec, side)
        length = foot.foot.length.value
    var femur = FemurField(pose.femur)
    var tibia = TibiaField(pose.tibia)
    var fibula = FibulaField(pose.fibula)
    var patella = PatellaField(pose.patella)
    var muscles = List[MuscleField]()
    var tendons = List[Bool]()
    for part in named_muscle_parts():  # pragma: no branch
        muscles.append(MuscleField(pose.muscles, part))
        tendons.append(is_tendon(part))
    var foot_dims = foot_muscle_dimensions(spec, side)
    var foot_bones = List[FootBoneField]()
    for part in named_foot_bones():  # pragma: no branch
        foot_bones.append(FootBoneField(foot_dims.foot, part))
    var foot_muscles = List[FootMuscleField]()
    var foot_tendons = List[Bool]()
    for part in named_foot_muscles():  # pragma: no branch
        foot_muscles.append(FootMuscleField(foot_dims, part))
        foot_tendons.append(is_foot_tendon(part))
    var dermis = skin.leg.dermis
    var cortical = cortical_tissue().apparent_density().value
    var trabecular = trabecular_tissue().apparent_density().value
    var fat = adipose_tissue().wet_density.value
    var dermal = skin_tissue().wet_density.value
    var flesh = muscle_tissue().wet_density.value
    var cord = tendon_tissue().wet_density.value
    var grid = SampleGrid(box.low, box.high, step)
    var mass = Float64(0)
    var first = SIMD[DType.float64, 4](0)
    var second = SIMD[DType.float64, 8](0)
    var volumes = SIMD[DType.float64, 8](0)
    var masses = SIMD[DType.float64, 8](0)
    var densities = SIMD[DType.float32, 8](
        dermal, cortical, trabecular, fat, flesh, cord, fat, 0
    )
    for iz in range(grid.nz):  # pragma: no branch
        for iy in range(grid.ny):  # pragma: no branch
            for ix in range(grid.nx):  # pragma: no branch
                var p, widths = grid._cell(ix, iy, iz)
                var d = skin.distance(p)
                if d >= 0:
                    continue
                var region = DERMIS_REGION
                if d <= -dermis:
                    var fill = _bone_fill(
                        p,
                        pose,
                        femur,
                        tibia,
                        fibula,
                        patella,
                        foot_bones,
                        ankle,
                    )
                    var soft = FAT_PROXY_REGION
                    # Marrow is assigned its documented fat proxy before
                    # checking overlapping muscle or tendon solids.
                    if fill == EMPTY:
                        soft = _soft_region(
                            p,
                            muscles,
                            tendons,
                            foot_muscles,
                            foot_tendons,
                            ankle,
                        )
                    region = _occupied_region(fill, soft)
                var cell = (
                    Float64(widths.x) * Float64(widths.y) * Float64(widths.z)
                )
                var m = Float64(densities[region.value]) * cell
                volumes[region.value] += cell
                masses[region.value] += m
                _add_cell(mass, first, second, m, p, widths)
    return SegmentEstimate(
        _inertia(mass, first, second, length),
        volumes,
        masses,
        box.low,
        box.high,
        step,
    )


def _occupied_region(
    fill: BoneOccupancy, soft: LimbRegion
) raises -> LimbRegion:
    """Choose one assignment; a bone or marrow excludes a soft-tissue hit."""
    if not fill.is_valid() or not soft.is_valid():
        raise Error("An occupancy and its soft region must be named")
    if fill == CORTICAL_FILL:
        return CORTICAL_REGION
    if fill == MARROW:
        return MARROW_PROXY_REGION
    if fill == EMPTY:
        return soft
    return TRABECULAR_REGION


def _add_cell(
    mut mass: Float64,
    mut first: SIMD[DType.float64, 4],
    mut second: SIMD[DType.float64, 8],
    m: Float64,
    p: Vector3,
    widths: Vector3,
):
    """Accumulate a constant-density cuboid, including its own inertia."""
    var r = SIMD[DType.float64, 4](Float64(p.x), Float64(p.y), Float64(p.z), 0)
    var w = SIMD[DType.float64, 4](
        Float64(widths.x), Float64(widths.y), Float64(widths.z), 0
    )
    mass += m
    first += r * m
    second += (
        SIMD[DType.float64, 8](
            r[0] * r[0] + w[0] * w[0] / 12,
            r[1] * r[1] + w[1] * w[1] / 12,
            r[2] * r[2] + w[2] * w[2] / 12,
            r[0] * r[1],
            r[0] * r[2],
            r[1] * r[2],
            0,
            0,
        )
        * m
    )


def _inertia(
    mass: Float64,
    first: SIMD[DType.float64, 4],
    second: SIMD[DType.float64, 8],
    length: Float32,
) raises -> SegmentInertia:
    """Return the tensor about the center of mass from raw moments."""
    if not isfinite(mass) or mass <= 0:
        raise Error("A sampled segment must have finite positive mass")
    var c = first / mass
    # Second moments about the center, by the parallel-axis theorem.
    var sxx = second[0] - mass * c[0] * c[0]
    var syy = second[1] - mass * c[1] * c[1]
    var szz = second[2] - mass * c[2] * c[2]
    var sxy = second[3] - mass * c[0] * c[1]
    var sxz = second[4] - mass * c[0] * c[2]
    var syz = second[5] - mass * c[1] * c[2]
    return SegmentInertia(
        Mass(Float32(mass), KILOGRAM),
        Vector3(Float32(c[0]), Float32(c[1]), Float32(c[2])),
        MomentOfInertia(Float32(syy + szz), KILOGRAM_SQUARE_METER),
        MomentOfInertia(Float32(sxx + szz), KILOGRAM_SQUARE_METER),
        MomentOfInertia(Float32(sxx + syy), KILOGRAM_SQUARE_METER),
        MomentOfInertia(Float32(-sxy), KILOGRAM_SQUARE_METER),
        MomentOfInertia(Float32(-sxz), KILOGRAM_SQUARE_METER),
        MomentOfInertia(Float32(-syz), KILOGRAM_SQUARE_METER),
        Length(length, METER),
    )


def _bone_fill(
    p: Vector3,
    pose: LegAssembly,
    femur: FemurField,
    tibia: TibiaField,
    fibula: FibulaField,
    patella: PatellaField,
    foot_bones: List[FootBoneField],
    ankle: Vector3,
) -> BoneOccupancy:
    """Return which bone fill `p` lies in, or `EMPTY`.

    A bone is sampled only where its box holds the point.
    """
    var at = p - pose.femur_origin
    if _inside(femur.low, femur.high, at):
        var fill = femur_field_occupancy(femur, at)
        if fill != EMPTY:
            return fill
    at = p - pose.tibia_origin
    if _inside(tibia.low, tibia.high, at):
        var fill = tibia_field_occupancy(tibia, at)
        if fill != EMPTY:
            return fill
    at = p - pose.fibula_origin
    if _inside(fibula.low, fibula.high, at):
        var fill = fibula_field_occupancy(fibula, at)
        if fill != EMPTY:
            return fill
    at = p - pose.patella_origin
    if _inside(patella.low, patella.high, at):
        var fill = patella_field_occupancy(patella, at)
        if fill != EMPTY:
            return fill
    var local = p - ankle
    for index in range(len(foot_bones)):  # pragma: no branch
        if _inside(foot_bones[index].low, foot_bones[index].high, local):
            var fill = foot_bone_field_occupancy(foot_bones[index], local)
            if fill != EMPTY:
                return fill
    return EMPTY


def _soft_region(
    p: Vector3,
    muscles: List[MuscleField],
    tendons: List[Bool],
    foot_muscles: List[FootMuscleField],
    foot_tendons: List[Bool],
    ankle: Vector3,
) -> LimbRegion:
    """Return the first soft-tissue assignment, or the unresolved fat proxy."""
    for index in range(len(muscles)):  # pragma: no branch
        if _inside(muscles[index].low, muscles[index].high, p):
            if muscles[index].distance(p) < 0:
                return TENDON_REGION if tendons[index] else MUSCLE_REGION
    var local = p - ankle
    for index in range(len(foot_muscles)):  # pragma: no branch
        if _inside(foot_muscles[index].low, foot_muscles[index].high, local):
            if foot_muscles[index].distance(local) < 0:
                return TENDON_REGION if foot_tendons[index] else MUSCLE_REGION
    return FAT_PROXY_REGION


def _inside(low: Vector3, high: Vector3, p: Vector3) -> Bool:
    """Return whether `p` lies in the box from `low` to `high`."""
    return (
        p.x >= low.x
        and p.x <= high.x
        and p.y >= low.y
        and p.y <= high.y
        and p.z >= low.z
        and p.z <= high.z
    )
