# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What an outfit weighs, where it weighs, what it costs to walk in, what
it covers, and what it stops.

These are template estimates for a game. Each constant cites where it
comes from, with an `Evidence` grade. The humanoid's engineering use
stays refused; nothing here is a validated engineering result.

- `garment_mass` is a garment's area times its fabric's areal density.
  Mail's areal density is set so a hauberk on the six-foot template
  weighs what the 15th-century hauberk of the Cleveland Museum of Art
  weighs, 9.3 kg.
- `worn_tallies` splits each triangle's mass among the joints by its
  skin weights, into one `InertiaTally` per joint. A caller adds them to
  the body's own segments.
- `locomotion_cost` estimates the metabolic cost of walking in an
  outfit, as a multiple of walking unloaded. A load on the legs costs
  more than one on the trunk (Askew, Formenti and Minetti 2012). The
  coefficients are a design choice, set so a 40 kg harness on a 75 kg
  man, 30 percent of it on the legs, costs about 2.1 times as much, the
  low end of that study's 2.1 to 2.3 for walking.
- `coverage` gives the share of each body region's skin an outfit
  covers.
- `protection` passes a blow's energy through the layers over one point
  of the body, from the outside in. Each layer takes the energy it needs to be
  pierced. The blow stops in the first layer that takes all it has
  left. The energies follow Alan Williams's tests: a hand blow carries
  60 to 130 J; mail over a padded jack needs about 120 J; mild steel
  plate needs about 55 J at 1 mm and 175 J at 2 mm. Plate's energy goes
  with the square of its thickness.
- `attire_report` gathers every estimate for one dressed outfit into one
  record. `tools/attire_report.mojo` prints it.
- `noise` and `visibility` are zero-through-one hooks for a game's
  stealth, as Kingdom Come: Deliverance has them: plate rings, mail
  rattles, and bright, polished gear is seen from farther away.

This is not a three.js port. See Extensions.

    var kilograms = garment_mass(dressed.shells[0], fabric(MAIL))
    var stop = protection(outfit, rig, CHEST, 0.5, Energy(110, JOULE))
"""

from core.buffer_geometry import POSITION, BufferGeometry
from core.ordinal import ordinal_label, ordinal_valid, require_valid
from core.user_data import UserData
from extensions.anatomy.evidence import DESIGN, FROM_TEXT, Cited, evidence_label
from extensions.anatomy.inertia import InertiaTally
from extensions.attire.cover import cover_values, dominant_joints, joint_cover
from extensions.attire.fabric import Fabric, fabric
from extensions.attire.garment import Garment
from extensions.attire.kinds import (
    LEATHER,
    MAIL,
    PADDING,
    PLATE,
    SILK,
    SLOT_COUNT,
    VELVET,
    WOOL,
    FabricKind,
    fabric_label,
    require_fabric_kind,
)
from extensions.attire.outfit import Dressed, Outfit
from extensions.humanoid.canonical import REGION_COUNT, BodyRegion, region_label
from extensions.humanoid.correspondence import joint_region
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    JOINT_COUNT,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    HumanoidRig,
    Joint,
    joint_label,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from units.si import JOULE, KILOGRAM, MILLIMETER, Energy, Mass

comptime TRUNK_LOAD_COST = Float32(1.0)
"""The locomotion cost of a load, per unit of its share of body mass, on the
trunk, on the arms, and on the legs."""
comptime ARM_LOAD_COST = Float32(1.0)
"""The locomotion cost of a load on the arms, per unit of its share of body
mass."""
comptime LEG_LOAD_COST = Float32(4.5)
"""The locomotion cost of a load on the legs, per unit of its share of body
mass."""
comptime PLATE_REFERENCE_MM = Float32(2.0)
"""The thickness plate's piercing energy is given for, in millimeters."""


@fieldwise_init
struct BlowOutcome(Equatable, ImplicitlyCopyable, Writable):
    """What became of a blow."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named outcome.

        Returns:
            True for `STOPPED` and `PIERCED`.
        """
        return ordinal_valid(self.value, 1)


comptime STOPPED = BlowOutcome(0)
"""A layer took all the blow's energy."""
comptime PIERCED = BlowOutcome(1)
"""The blow went through every layer."""


def outcome_label(outcome: BlowOutcome) -> String:
    """Return the name of an outcome.

    Args:
        outcome: An outcome, named or not.

    Returns:
        `"stopped"`, `"pierced"`, or `"outcome"` when it is not named.
    """
    return ordinal_label(
        outcome.is_valid(), outcome.value, ["stopped", "pierced"], "outcome"
    )


def require_outcome(outcome: BlowOutcome) raises:
    """Refuse an outcome that is not named.

    Args:
        outcome: The outcome.

    Raises:
        Error: If the outcome is not named.
    """
    require_valid(outcome.is_valid(), "A blow's outcome must be named")


struct Protection(Copyable, Movable):
    """What a blow did against an outfit."""

    var outcome: BlowOutcome
    """Whether it was stopped or pierced every layer."""
    var stopped_by: String
    """The name of the garment that stopped it, or empty."""
    var left: Energy
    """The energy it had left past the last layer it pierced."""

    def __init__(
        out self, outcome: BlowOutcome, var stopped_by: String, left: Energy
    ):
        """Hold a blow's outcome.

        Args:
            outcome: Stopped or pierced.
            stopped_by: The garment that stopped it, or empty.
            left: The energy it had left.
        """
        self.outcome = outcome
        self.stopped_by = stopped_by^
        self.left = left


def triangle_area(geometry: BufferGeometry, triangle: Int) raises -> Float32:
    """Return the area of one triangle of a mesh.

    Args:
        geometry: The mesh.
        triangle: The triangle.

    Returns:
        Its area, in square meters.

    Raises:
        Error: If the triangle is out of range.
    """
    var a = geometry.corner(triangle, 0)
    var b = geometry.corner(triangle, 1)
    var c = geometry.corner(triangle, 2)
    var n = b - a
    n.cross(c - a)
    return n.length() / 2


def garment_mass(piece: BufferGeometry, cloth: Fabric) raises -> Mass:
    """Return a garment's mass: its area times its fabric's areal density.

    Args:
        piece: The garment's mesh.
        cloth: Its fabric.

    Returns:
        Its mass. A mesh with no positions weighs nothing.

    Raises:
        Error: If the mesh is malformed.
    """
    var area = Float32(0)
    if not piece.has_attribute(String(POSITION)):
        return Mass(0, KILOGRAM)
    for t in range(piece.triangle_count()):
        area += triangle_area(piece, t)
    return Mass(area * Float32(cloth.areal_density.value), KILOGRAM)


def worn_tallies(outfit: Outfit, dressed: Dressed) raises -> List[InertiaTally]:
    """Split a dressed outfit's mass among the joints it rides.

    Each garment weighs its whole shell, the parts the garments over it
    hide too. Each triangle's mass sits at its centroid, at rest, in the
    pelvis frame. It is shared among the joints by the mean of its
    corners' skin weights.

    Args:
        outfit: The outfit.
        dressed: What `dress` made for it.

    Returns:
        One tally per joint, in the order of the joints.

    Raises:
        Error: If the outfit and what was dressed do not match, or a mesh
            is malformed.
    """
    if len(dressed.shells) != len(outfit.garments):
        raise Error("The dressed shells must be one per garment")
    var tallies = List[InertiaTally]()
    for _ in range(JOINT_COUNT):  # pragma: no branch
        tallies.append(InertiaTally())
    for g in range(len(outfit.garments)):
        ref piece = dressed.shells[g]
        if not piece.has_attribute(String(POSITION)):
            continue
        var cloth = fabric(outfit.garments[g].fabric)
        var density = Float32(cloth.areal_density.value)
        ref bones = piece.attribute_view(String(SKIN_INDEX))
        ref weights = piece.attribute_view(String(SKIN_WEIGHT))
        for t in range(piece.triangle_count()):
            var m = triangle_area(piece, t) * density
            var center = (
                piece.corner(t, 0) + piece.corner(t, 1) + piece.corner(t, 2)
            ) * (Float32(1) / 3)
            var shares = List[Float32](length=JOINT_COUNT, fill=0)
            for c in range(3):  # pragma: no branch
                var v = piece.corner_index(t, c)
                for k in range(4):  # pragma: no branch
                    var bone = Int(bones.component(v, k))
                    if bone < 0 or bone >= JOINT_COUNT:
                        raise Error("A garment weight names no joint")
                    shares[bone] += weights.component(v, k) / 3
            for j in range(JOINT_COUNT):  # pragma: no branch
                if shares[j] > 0:
                    tallies[j].add_cell(
                        Float64(m * shares[j]), center, Vector3(0, 0, 0)
                    )
    return tallies^


def outfit_mass(tallies: List[InertiaTally]) -> Mass:
    """Return the total mass in a set of tallies.

    Args:
        tallies: One tally per joint.

    Returns:
        Their mass.
    """
    var total = Float64(0)
    for tally in tallies:
        total += tally.mass
    return Mass(Float32(total), KILOGRAM)


def _is_trunk(joint: Int) -> Bool:
    """Return whether a joint is of the trunk or the head."""
    return joint <= HEAD.value


def _is_leg(joint: Int) -> Bool:
    """Return whether a joint is of a leg."""
    return joint >= RIGHT_THIGH.value


def locomotion_cost(tallies: List[InertiaTally], body: Mass) raises -> Float32:
    """Return the cost of walking in an outfit, as a multiple of walking
    unloaded.

    Args:
        tallies: The outfit's mass, one tally per joint.
        body: The body's own mass.

    Returns:
        One plus each load's share of the body's mass, weighted by where
        it is carried: `TRUNK_LOAD_COST` on the trunk and the head,
        `ARM_LOAD_COST` on the arms, and `LEG_LOAD_COST` on the legs.

    Raises:
        Error: If there is not one tally per joint, or the body's mass is
            not positive.
    """
    if len(tallies) != JOINT_COUNT:
        raise Error("A locomotion cost needs one tally per joint")
    var m = Float32(body.value)
    if not (m > 0 and m < 1e6):
        raise Error("A body's mass must be positive")
    var cost = Float32(1)
    for j in range(JOINT_COUNT):  # pragma: no branch
        var share = Float32(tallies[j].mass) / m
        if _is_trunk(j):
            cost += TRUNK_LOAD_COST * share
        elif _is_leg(j):
            cost += LEG_LOAD_COST * share
        else:
            cost += ARM_LOAD_COST * share
    return cost


def locomotion_source() -> Cited:
    """Return where the locomotion cost's calibration comes from.

    Returns:
        A design choice, set against Askew, Formenti and Minetti 2012.
    """
    return Cited(DESIGN, "Askew2012")


def coverage(
    skin: BufferGeometry, rig: HumanoidRig, outfit: Outfit
) raises -> List[Float32]:
    """Return the share of each body region's skin an outfit covers.

    A skin triangle is covered when the mean of its corners' greatest
    cover value is at least one half. A triangle belongs to the region
    of the joint that weighs most on its first corner.

    Args:
        skin: A person's skin, undressed, with skin weights.
        rig: The rig it is bound to.
        outfit: The outfit.

    Returns:
        One share per region, zero through one, by area. A region with
        no skin on this mesh has zero.

    Raises:
        Error: If the skin is malformed or the outfit does not check.
    """
    outfit.check()
    var count = skin.vertex_count()
    var most = List[Float32](length=count, fill=0)
    for garment in outfit.garments:
        var values = cover_values(skin, rig, garment.cover)
        for v in range(count):
            most[v] = max(most[v], values[v])
    var joints = dominant_joints(skin)
    var area = List[Float32](length=REGION_COUNT, fill=0)
    var covered = List[Float32](length=REGION_COUNT, fill=0)
    for t in range(skin.triangle_count()):
        var mean = Float32(0)
        for c in range(3):  # pragma: no branch
            mean += most[skin.corner_index(t, c)] / 3
        var region = joint_region(joints[skin.corner_index(t, 0)]).value
        var a = triangle_area(skin, t)
        area[region] += a
        if mean >= 0.5:
            covered[region] += a
    var shares = List[Float32](capacity=REGION_COUNT)
    for r in range(REGION_COUNT):  # pragma: no branch
        if area[r] > 0:
            shares.append(covered[r] / area[r])
        else:
            shares.append(0)
    return shares^


def piercing_energy(cloth: Fabric) raises -> Energy:
    """Return the energy a blow needs to pierce one layer of a fabric.

    Args:
        cloth: The fabric.

    Returns:
        The energy. Plate's goes with the square of its thickness.

    Raises:
        Error: If the fabric's kind is not named.
    """
    require_fabric_kind(cloth.kind)
    var joules = Float32(5)
    if cloth.kind == WOOL or cloth.kind == SILK:
        joules = 6
    elif cloth.kind == VELVET:
        joules = 8
    elif cloth.kind == LEATHER:
        joules = 20
    elif cloth.kind == PADDING:
        joules = 40
    elif cloth.kind == MAIL:
        joules = 80
    elif cloth.kind == PLATE:
        var t = Float32(cloth.thickness.to(MILLIMETER)) / PLATE_REFERENCE_MM
        joules = 175 * t * t
    return Energy(joules, JOULE)


def piercing_source(kind: FabricKind) raises -> Cited:
    """Return where a fabric's piercing energy comes from.

    Args:
        kind: A named fabric kind.

    Returns:
        Williams's tests for mail, padding and plate, quoted; a design
        choice for the rest.

    Raises:
        Error: If the kind is not named.
    """
    require_fabric_kind(kind)
    if kind == MAIL or kind == PADDING or kind == PLATE:
        return Cited(FROM_TEXT, "Williams2003")
    return Cited(DESIGN, "TextilePractice")


def protection(
    outfit: Outfit,
    rig: HumanoidRig,
    joint: Joint,
    along: Float32,
    blow: Energy,
) raises -> Protection:
    """Pass a blow through the layers over one point, from the outside in.

    The blow lands on a joint's bone, a fraction of the way along it. A
    garment is a layer there when it covers that point at least by
    half, by its cover's span on that joint.

    Args:
        outfit: The outfit.
        rig: The rig the outfit is worn on.
        joint: The bone the blow lands on.
        along: Where on the bone, zero at the joint through one at its
            end.
        blow: The blow's energy.

    Returns:
        Stopped by the first layer that takes all the energy left, or
        pierced, with the energy left past the last layer.

    Raises:
        Error: If the outfit does not check, the joint is not named, or
            the blow's energy is negative.
    """
    outfit.check()
    if not joint.is_valid():
        raise Error("A blow must land on a named joint")
    if not (blow.value >= 0 and blow.value < 1e12):
        raise Error("A blow's energy must be zero or more")
    var at = (
        rig.joints[joint.value]
        + (rig.ends[joint.value] - rig.joints[joint.value]) * along
    )
    var order = outfit.order()
    var left = Float32(blow.value)
    var k = len(order) - 1
    while k >= 0:
        ref garment = outfit.garments[order[k]]
        k -= 1
        if joint_cover(rig, garment.cover, joint.value, at) < 0.5:
            continue
        var need = Float32(piercing_energy(fabric(garment.fabric)).value)
        if left <= need:
            return Protection(STOPPED, garment.name, Energy(0, JOULE))
        left -= need
    return Protection(PIERCED, "", Energy(left, JOULE))


def noise(outfit: Outfit) raises -> Float32:
    """Return how much noise an outfit makes as its wearer moves.

    Plate rings at 0.5, mail rattles at 0.3, leather creaks at 0.06 and
    padding at 0.03; cloth is nearly silent at 0.01. The sum is held to
    one.

    Args:
        outfit: The outfit.

    Returns:
        Zero through one.

    Raises:
        Error: If the outfit does not check.
    """
    outfit.check()
    var total = Float32(0)
    for garment in outfit.garments:
        var kind = garment.fabric
        if kind == PLATE:
            total += 0.5
        elif kind == MAIL:
            total += 0.3
        elif kind == LEATHER:
            total += 0.06
        elif kind == PADDING:
            total += 0.03
        else:
            total += 0.01
    return min(Float32(1), total)


def visibility(outfit: Outfit) raises -> Float32:
    """Return how far off an outfit is seen, zero through one.

    The outermost garment of each slot shows. Its primary dye's
    brightness counts, and polished plate adds its shine.

    Args:
        outfit: The outfit.

    Returns:
        The mean over the slots it fills: zero for black cloth, near one
        for white or polished plate.

    Raises:
        Error: If the outfit does not check.
    """
    outfit.check()
    var order = outfit.order()
    var seen = List[Bool](length=SLOT_COUNT, fill=False)
    var total = Float32(0)
    var slots = 0
    var k = len(order) - 1
    while k >= 0:
        ref garment = outfit.garments[order[k]]
        k -= 1
        if seen[garment.slot.value]:
            continue
        seen[garment.slot.value] = True
        slots += 1
        var dye = garment.dyes[0]
        var light = (
            0.2126 * Float32(dye.r)
            + 0.7152 * Float32(dye.g)
            + 0.0722 * Float32(dye.b)
        ) / 255
        if garment.fabric == PLATE:
            light = min(Float32(1), light + 0.3)
        total += light
    if slots == 0:
        return 0
    return total / Float32(slots)


# Where `attire_report` lands its blows: a joint and a share of its bone.
comptime _REPORT_JOINTS: List[Int] = [
    CHEST.value,
    HEAD.value,
    RIGHT_UPPER_ARM.value,
    RIGHT_FOREARM.value,
    RIGHT_THIGH.value,
    RIGHT_SHIN.value,
]
# The blows it lands: the low and the high end of Williams's hand blows.
comptime _REPORT_BLOWS: List[Float32] = [60, 130]


def attire_report(
    bare_skin: BufferGeometry,
    rig: HumanoidRig,
    outfit: Outfit,
    dressed: Dressed,
    body: Mass,
) raises -> UserData:
    """Return every estimate for one dressed outfit, as one record.

    The record says it is a template estimate, and gives the grade and
    the source of each estimate.

    Args:
        bare_skin: The person's body skin before it was dressed.
        rig: The person's rig.
        outfit: The outfit.
        dressed: What `dress` made for it.
        body: The body's own mass.

    Returns:
        A record of the garments' masses, the total, the locomotion
        cost, the coverage of each region, the protection at six points
        against two blows, the noise and the visibility.

    Raises:
        Error: If an estimate is refused.
    """
    var record = UserData()
    record.set_boolean("template_estimate", True)
    var garments = String("[")
    for g in range(len(outfit.garments)):
        ref garment = outfit.garments[g]
        var cloth = fabric(garment.fabric)
        var mass = Float64(garment_mass(dressed.shells[g], cloth).value)
        var row = UserData()
        row.set_string("name", garment.name)
        row.set_string("fabric", fabric_label(garment.fabric))
        row.set_number("mass_kg", mass)
        row.set_string("evidence", evidence_label(cloth.source.evidence))
        row.set_string("source", cloth.source.source)
        if g > 0:
            garments += ","
        garments += row.to_json()
    record.set_json("garments", garments + "]")
    var tallies = worn_tallies(outfit, dressed)
    record.set_number("total_mass_kg", Float64(outfit_mass(tallies).value))
    record.set_number(
        "locomotion_cost", Float64(locomotion_cost(tallies, body))
    )
    var source = locomotion_source()
    record.set_string("locomotion_source", source.source)
    var covered = coverage(bare_skin, rig, outfit)
    var shares = UserData()
    for r in range(REGION_COUNT):  # pragma: no branch
        shares.set_number(region_label(BodyRegion(r)), Float64(covered[r]))
    record.set_json("coverage", shares.to_json())
    var blows = String("[")
    var first = True
    for j in materialize[_REPORT_JOINTS]():  # pragma: no branch
        for energy in materialize[_REPORT_BLOWS]():  # pragma: no branch
            var hit = protection(
                outfit, rig, Joint(j), 0.5, Energy(energy, JOULE)
            )
            var row = UserData()
            row.set_string("joint", joint_label(Joint(j)))
            row.set_number("energy_j", Float64(energy))
            row.set_string("outcome", outcome_label(hit.outcome))
            row.set_string("stopped_by", hit.stopped_by)
            row.set_number("left_j", Float64(hit.left.value))
            if not first:
                blows += ","
            first = False
            blows += row.to_json()
    record.set_json("protection", blows + "]")
    record.set_number("noise", Float64(noise(outfit)))
    record.set_number("visibility", Float64(visibility(outfit)))
    return record^
