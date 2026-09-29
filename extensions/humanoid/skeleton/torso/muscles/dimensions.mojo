# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named muscles of the torso, as implicit solids in the pelvis frame.

The set is the abdominal wall, the deep back, the diaphragm, the
intercostals, and the muscles that hold the shoulder girdle to the
trunk: the serratus anterior, the trapezius, the rhomboids, the
pectoralis minor and the subclavius. The pectoralis major and the
latissimus dorsi cross to the humerus, and end on it in a tendon. The
neck is not modeled, so the trapezius ends at the base of the neck.

Every muscle but the diaphragm is paired, authored on the right and
mirrored on x for the left. A muscle is one or more sweeps of
elliptical stations; a sheet lies thin across the body wall whichever
way its fibers run. Radii are authored in centimeters on the six-foot
male template, scaled by stature and by athleticism. They are template
parameters. They are not a cited cross-section table.

    var dims = torso_muscle_dimensions(person)
    var d = torso_muscle_distance(dims, ERECTOR_SPINAE, RIGHT, p)
"""

from extensions.humanoid.athleticism import Athleticism, radius_scale
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoDimensions,
    TorsoFrame,
    midpoint_path,
    rib_path,
    torso_dimensions,
    upper_arm_point,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    tube,
)
from math.vector3 import Vector3


@fieldwise_init
struct TorsoMuscle(Equatable, ImplicitlyCopyable, Writable):
    """Which named torso muscle a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named muscles is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named torso muscle."""
        if self.value < 0:
            return False
        return self.value <= SUBCLAVIUS.value


comptime RECTUS_ABDOMINIS = TorsoMuscle(0)
comptime EXTERNAL_OBLIQUE = TorsoMuscle(1)
# The internal oblique and the transversus abdominis, drawn as one layer.
comptime INTERNAL_OBLIQUE = TorsoMuscle(2)
comptime ERECTOR_SPINAE = TorsoMuscle(3)
comptime QUADRATUS_LUMBORUM = TorsoMuscle(4)
comptime PSOAS_MAJOR = TorsoMuscle(5)
comptime DIAPHRAGM = TorsoMuscle(6)
# The external and internal intercostals of every space, drawn as one.
comptime INTERCOSTALS = TorsoMuscle(7)
comptime SERRATUS_ANTERIOR = TorsoMuscle(8)
comptime PECTORALIS_MAJOR = TorsoMuscle(9)
comptime LATISSIMUS_DORSI = TorsoMuscle(10)
comptime TRAPEZIUS = TorsoMuscle(11)
# The rhomboid minor and major, drawn as one sheet.
comptime RHOMBOIDS = TorsoMuscle(12)
comptime PECTORALIS_MINOR = TorsoMuscle(13)
comptime SUBCLAVIUS = TorsoMuscle(14)


struct TorsoMuscleDimensions(Copyable, Movable):
    """Torso landmarks plus the athleticism scale for muscle radii."""

    var torso: TorsoDimensions
    var athleticism: Athleticism
    var scale: Float32

    def __init__(
        out self, var torso: TorsoDimensions, athleticism: Athleticism
    ) raises:
        """Pair torso landmarks with an athleticism.

        Args:
            torso: Landmarks from `torso_dimensions`.
            athleticism: `UNTONED` or `TONED`.

        Raises:
            Error: If `athleticism` is not named.
        """
        self.torso = torso^
        self.athleticism = athleticism
        self.scale = radius_scale(athleticism)

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If the torso fails `validate`, if athleticism is not
                named, or if the scale is not positive.
        """
        self.torso.validate()
        if not self.athleticism.is_valid():
            raise Error("A torso muscle needs a toned or untoned athleticism")
        if self.scale <= 0:
            raise Error("A torso muscle radius scale must be positive")


def torso_muscle_dimensions(spec: HumanoidSpec) raises -> TorsoMuscleDimensions:
    """Return torso landmarks and the radius scale for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.

    Returns:
        The landmarks and the scale.

    Raises:
        Error: If `spec` is refused, or athleticism is not named.
    """
    if not spec.athleticism.is_valid():
        raise Error("A torso muscle needs a toned or untoned athleticism")
    return TorsoMuscleDimensions(
        torso_dimensions(spec.stature, spec.sex), spec.athleticism
    )


def is_paired_muscle(part: TorsoMuscle) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named muscle.

    Returns:
        True for every muscle but the diaphragm.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso muscle must be a named muscle")
    return part != DIAPHRAGM


def torso_muscle_field(
    dimensions: TorsoMuscleDimensions, part: TorsoMuscle, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one torso muscle.

    Args:
        dimensions: Landmarks and the radius scale.
        part: A named muscle.
        side: `RIGHT` or `LEFT`. The diaphragm ignores it.

    Returns:
        The muscle's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not side.is_valid():
        raise Error("A torso side must be RIGHT or LEFT")
    var placed = RIGHT
    if is_paired_muscle(part):
        placed = side
    var t = dimensions.torso.copy()
    var f = t.frame
    var s = dimensions.scale
    var sweeps = List[Sweep]()
    var domes = List[Dome]()
    if part == RECTUS_ABDOMINIS:
        var strap = Sweep(Vector3(1, 0, 0))
        _station(strap, f, s, 3.8, 12.0, 7.4, 3.2, 0.55)
        _station(strap, f, s, 4.2, 18.0, 8.0, 3.4, 0.6)
        _station(strap, f, s, 4.5, 24.0, 8.6, 3.4, 0.6)
        _station(strap, f, s, 4.8, 29.0, 9.4, 3.5, 0.55)
        _station(strap, f, s, 5.0, 33.5, 10.2, 3.6, 0.5)
        sweeps.append(strap^)
    elif part == EXTERNAL_OBLIQUE:
        var flank = Sweep(Vector3(1, 0, 0))
        _station(flank, f, s, 13.0, 14.0, 1.4, 0.9, 4.8)
        _station(flank, f, s, 12.4, 19.0, 1.0, 0.9, 5.0)
        _station(flank, f, s, 12.7, 24.0, 0.6, 0.8, 5.2)
        _station(flank, f, s, 14.2, 29.0, 0.4, 0.7, 5.0)
        _station(flank, f, s, 14.9, 34.0, 0.8, 0.6, 4.5)
        sweeps.append(flank^)
        var front = Sweep(Vector3(1, 0, 0))
        _station(front, f, s, 10.3, 14.0, 7.0, 1.3, 1.3)
        _station(front, f, s, 10.8, 20.0, 7.8, 1.4, 1.4)
        _station(front, f, s, 11.2, 26.0, 8.2, 1.4, 1.4)
        _station(front, f, s, 11.3, 30.5, 8.0, 1.2, 1.2)
        _station(front, f, s, 11.0, 34.0, 7.5, 0.9, 0.9)
        sweeps.append(front^)
    elif part == INTERNAL_OBLIQUE:
        var deep = Sweep(Vector3(1, 0, 0))
        _station(deep, f, s, 12.0, 14.0, 1.0, 0.7, 4.5)
        _station(deep, f, s, 11.6, 19.0, 0.7, 0.7, 4.6)
        _station(deep, f, s, 11.9, 24.0, 0.4, 0.6, 4.4)
        _station(deep, f, s, 13.0, 28.0, 0.3, 0.5, 3.8)
        sweeps.append(deep^)
        var inner = Sweep(Vector3(1, 0, 0))
        _station(inner, f, s, 9.6, 14.0, 6.5, 1.0, 1.0)
        _station(inner, f, s, 10.1, 20.0, 7.2, 1.0, 1.0)
        _station(inner, f, s, 10.5, 26.0, 7.5, 0.9, 0.9)
        sweeps.append(inner^)
    elif part == ERECTOR_SPINAE:
        var column = Sweep(Vector3(1, 0, 0))
        _station(column, f, s, 3.6, 14.0, -8.7, 2.8, 2.5)
        _station(column, f, s, 3.9, 20.0, -7.6, 3.0, 2.6)
        _station(column, f, s, 4.1, 26.0, -8.2, 2.9, 2.4)
        _station(column, f, s, 4.2, 32.0, -9.6, 2.5, 2.0)
        _station(column, f, s, 4.0, 38.0, -10.8, 2.1, 1.7)
        _station(column, f, s, 3.6, 44.0, -11.4, 1.7, 1.4)
        _station(column, f, s, 3.2, 50.0, -10.8, 1.3, 1.1)
        sweeps.append(column^)
    elif part == QUADRATUS_LUMBORUM:
        var sheet = Sweep(Vector3(1, 0, 0))
        _station(sheet, f, s, 7.2, 16.0, -5.1, 2.1, 1.1)
        _station(sheet, f, s, 6.6, 20.0, -4.7, 2.2, 1.1)
        _station(sheet, f, s, 6.0, 23.5, -4.8, 1.8, 1.0)
        _station(sheet, f, s, 5.6, 26.0, -5.4, 1.2, 0.8)
        sweeps.append(sheet^)
    elif part == PSOAS_MAJOR:
        var belly = Sweep(Vector3(1, 0, 0))
        _station(belly, f, s, 3.2, 26.0, -1.3, 0.9, 0.9)
        _station(belly, f, s, 3.8, 22.5, -0.8, 1.4, 1.4)
        _station(belly, f, s, 4.2, 19.0, -0.9, 1.8, 1.8)
        _station(belly, f, s, 4.4, 16.0, -1.4, 2.0, 2.0)
        sweeps.append(belly^)
    elif part == DIAPHRAGM:
        # The dome over the liver and the stomach, and the two crura
        # down the front of the upper lumbar bodies.
        domes.append(
            Dome(
                f.at(0, 25.0, -0.5),
                Vector3(f.cm(12.5) * f.wide, f.cm(11.0), f.cm(9.5) * f.deep),
                f.cm(0.25) * s,
                f.at(0, 25.0, 0).y,
            )
        )
        for k in range(2):
            var sign = Float32(1)
            if k == 1:
                sign = Float32(-1)
            var crus = Sweep(Vector3(1, 0, 0))
            _station(crus, f, s, sign * 1.8, 19.0, 0.9, 0.8, 0.8)
            _station(crus, f, s, sign * 1.6, 23.0, 0.6, 0.7, 0.7)
            _station(crus, f, s, sign * 1.2, 27.0, -0.2, 0.6, 0.6)
            sweeps.append(crus^)
    elif part == INTERCOSTALS:
        for gap in range(11):
            var mid = midpoint_path(
                rib_path(t, gap), rib_path(t, gap + 1), 0.12, 0.96, 8
            )
            sweeps.append(tube(mid, f.cm(0.5) * s, f.cm(0.4) * s))
    elif part == SERRATUS_ANTERIOR:
        # Slips from the side of the upper ribs back around the chest
        # wall, under the scapula, to its medial border.
        # fmt: off
        _slip(sweeps, f, s, 11.0, 44.0, 3.5, 13.0, 44.5, -2.0, 10.4, 45.3, -6.0,
              7.9, 46.0, -9.4)
        _slip(sweeps, f, s, 13.0, 38.0, 4.5, 14.5, 39.5, -1.5, 11.2, 40.8, -6.4,
              8.1, 41.5, -9.4)
        _slip(sweeps, f, s, 14.3, 33.0, 4.0, 15.2, 35.5, -1.0, 11.8, 36.8, -6.6,
              8.7, 37.6, -9.2)
        # fmt: on
    elif part == PECTORALIS_MAJOR:
        # From the sternum, the cartilages and the clavicle's line toward
        # the humerus, which ends it at the front fold of the armpit. It
        # is a thick belly over the upper ribs.
        _sheet(
            sweeps,
            f,
            s,
            2.0,
            36.0,
            10.8,
            8.0,
            38.5,
            11.0,
            13.0,
            42.0,
            8.3,
            15.8,
            43.5,
            4.0,
            1.8,
            1.2,
        )
        _sheet(
            sweeps,
            f,
            s,
            2.2,
            42.0,
            8.4,
            8.5,
            43.5,
            9.2,
            13.5,
            44.2,
            7.8,
            16.0,
            44.5,
            4.2,
            2.0,
            1.2,
        )
        _sheet(
            sweeps,
            f,
            s,
            5.0,
            48.7,
            5.0,
            10.0,
            48.6,
            5.8,
            14.0,
            47.0,
            5.8,
            16.2,
            45.5,
            4.0,
            1.4,
            1.2,
        )
        # The tendon: a flat band across the front of the armpit to the
        # lateral lip of the humerus's groove.
        var tendon = Sweep(Vector3(0, 0, 1))
        _station(tendon, f, s, 16.0, 44.2, 4.1, 1.2, 1.6)
        tendon.add(upper_arm_point(t, 1.6, -6.2, 2.2), f.cm(0.35), f.cm(1.4))
        sweeps.append(tendon^)
    elif part == LATISSIMUS_DORSI:
        # From the spines and the thoracolumbar fascia toward the humerus,
        # which ends it at the back fold of the armpit.
        _sheet(
            sweeps,
            f,
            s,
            1.5,
            40.0,
            -12.0,
            7.0,
            40.5,
            -12.2,
            12.5,
            41.5,
            -9.5,
            15.5,
            42.5,
            -5.5,
            1.0,
            1.8,
        )
        _sheet(
            sweeps,
            f,
            s,
            2.5,
            30.0,
            -11.5,
            8.5,
            32.5,
            -11.8,
            13.5,
            37.0,
            -8.5,
            15.8,
            41.5,
            -5.5,
            1.0,
            1.8,
        )
        _sheet(
            sweeps,
            f,
            s,
            7.5,
            16.0,
            -9.5,
            11.5,
            22.0,
            -9.0,
            14.2,
            30.5,
            -6.5,
            15.8,
            40.0,
            -5.0,
            1.0,
            1.8,
        )
        # The tendon twists under the arm, around the teres major, to the
        # floor of the humerus's groove.
        var twist = Sweep(Vector3(1, 0, 0))
        _station(twist, f, s, 15.6, 42.2, -5.4, 0.6, 1.4)
        twist.add(upper_arm_point(t, -1.4, -5.2, -0.8), f.cm(0.45), f.cm(1.3))
        twist.add(upper_arm_point(t, 0.5, -5.6, 1.4), f.cm(0.3), f.cm(1.1))
        sweeps.append(twist^)
    elif part == TRAPEZIUS:
        # From the thoracic spines and the base of the neck over the
        # rhomboids to the scapular spine, the acromion and the lateral
        # clavicle: the lower, middle and upper fibers.
        # fmt: off
        _sheet(sweeps, f, s, 0.6, 27.0, -12.0, 4.0, 34.0, -12.8,
               7.0, 41.0, -13.0, 8.6, 47.2, -11.8, 1.0, 1.4)
        _sheet(sweeps, f, s, 0.6, 44.0, -12.9, 5.5, 46.0, -14.3,
               10.0, 48.2, -12.2, 14.5, 49.4, -10.4, 1.0, 1.4)
        _sheet(sweeps, f, s, 0.6, 52.5, -10.4, 6.0, 53.0, -9.8,
               11.5, 51.8, -6.8, 16.6, 50.6, -3.0, 1.0, 1.4)
        _sheet(sweeps, f, s, 0.6, 54.0, -8.6, 6.5, 53.8, -7.0,
               11.0, 52.2, -3.8, 14.5, 50.9, -0.2, 1.0, 1.2)
        # fmt: on
    elif part == RHOMBOIDS:
        # The rhomboid minor and major, drawn as one sheet from the
        # spines of the upper thorax over the erector spinae down and out
        # to the medial border of the scapula.
        # fmt: off
        _band(sweeps, f, s, 0.5, 52.0, -10.2, 3.8, 50.6, -12.0,
              7.4, 48.6, -10.6)
        _band(sweeps, f, s, 0.5, 48.5, -11.2, 3.9, 45.8, -13.2,
              7.5, 43.5, -10.9)
        _band(sweeps, f, s, 0.5, 44.5, -11.4, 4.0, 41.5, -13.4,
              8.2, 38.2, -10.5)
        # fmt: on
    elif part == PECTORALIS_MINOR:
        # From the third to fifth ribs under the pectoralis major up to
        # the coracoid.
        var fan = Sweep(Vector3(0.3, 0, 1))
        _station(fan, f, s, 8.0, 39.0, 9.2, 0.5, 2.8)
        _station(fan, f, s, 11.5, 42.6, 7.0, 0.7, 1.8)
        _station(fan, f, s, 14.4, 46.0, 2.4, 0.45, 0.6)
        sweeps.append(fan^)
    else:
        # The subclavius, under the clavicle from the first rib out.
        var strap = Sweep(Vector3(1, 0, 0))
        _station(strap, f, s, 4.2, 48.3, 3.3, 0.4, 0.4)
        _station(strap, f, s, 9.0, 48.4, 3.2, 0.6, 0.5)
        _station(strap, f, s, 13.4, 48.8, 1.0, 0.35, 0.35)
        sweeps.append(strap^)
    return SweepField(sweeps^, domes^, placed, f.cm(0.5), f.cm(0.15), 0.006)


def _station(
    mut sweep: Sweep,
    f: TorsoFrame,
    scale: Float32,
    x: Float32,
    y: Float32,
    z: Float32,
    ml: Float32,
    ap: Float32,
):
    """Append one station authored in template centimeters."""
    sweep.add(f.at(x, y, z), f.cm(ml) * scale, f.cm(ap) * scale)


def _slip(
    mut sweeps: List[Sweep],
    f: TorsoFrame,
    scale: Float32,
    x0: Float32,
    y0: Float32,
    z0: Float32,
    x1: Float32,
    y1: Float32,
    z1: Float32,
    x2: Float32,
    y2: Float32,
    z2: Float32,
    x3: Float32,
    y3: Float32,
    z3: Float32,
):
    """Append one serratus slip: thin across the chest wall, tall along
    y, narrowing to the scapula's medial border."""
    var slip = Sweep(Vector3(1, 0, 0))
    _station(slip, f, scale, x0, y0, z0, 0.5, 1.6)
    _station(slip, f, scale, x1, y1, z1, 0.6, 2.0)
    _station(slip, f, scale, x2, y2, z2, 0.5, 1.6)
    _station(slip, f, scale, x3, y3, z3, 0.4, 1.0)
    sweeps.append(slip^)


def _band(
    mut sweeps: List[Sweep],
    f: TorsoFrame,
    scale: Float32,
    x0: Float32,
    y0: Float32,
    z0: Float32,
    x1: Float32,
    y1: Float32,
    z1: Float32,
    x2: Float32,
    y2: Float32,
    z2: Float32,
):
    """Append one rhomboid band: thin front to back, tall along y."""
    var band = Sweep(Vector3(0, 0, 1))
    _station(band, f, scale, x0, y0, z0, 0.35, 1.5)
    _station(band, f, scale, x1, y1, z1, 0.4, 1.7)
    _station(band, f, scale, x2, y2, z2, 0.35, 1.4)
    sweeps.append(band^)


def _sheet(
    mut sweeps: List[Sweep],
    f: TorsoFrame,
    scale: Float32,
    x0: Float32,
    y0: Float32,
    z0: Float32,
    x1: Float32,
    y1: Float32,
    z1: Float32,
    x2: Float32,
    y2: Float32,
    z2: Float32,
    x3: Float32,
    y3: Float32,
    z3: Float32,
    thick: Float32 = 1,
    tall: Float32 = 1,
):
    """Append one band of a broad sheet: thin front to back, tall along y.

    The band thickens toward the arm, where the fibers gather into a
    tendon. `thick` scales its thickness: the pectoralis major is a
    thick belly, the latissimus and the trapezius thin sheets. `tall`
    scales its breadth, so neighboring bands overlap into one sheet.
    """
    var band = Sweep(Vector3(0, 0, 1))
    _station(band, f, scale, x0, y0, z0, 0.6 * thick, 2.6 * tall)
    _station(band, f, scale, x1, y1, z1, 0.8 * thick, 2.8 * tall)
    _station(band, f, scale, x2, y2, z2, 1.1 * thick, 2.4 * tall)
    _station(band, f, scale, x3, y3, z3, 1.4, 1.4)
    sweeps.append(band^)


def torso_muscle_distance(
    dimensions: TorsoMuscleDimensions,
    part: TorsoMuscle,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        part: Which muscle to sample.
        side: `RIGHT` or `LEFT`. The diaphragm ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return torso_muscle_field(dimensions, part, side).distance(point)


def torso_muscle_label(part: TorsoMuscle) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A torso muscle, named or not.

    Returns:
        A short American English label, or `"torso muscle"` when `part`
        is not named.
    """
    if part == RECTUS_ABDOMINIS:
        return "rectus abdominis"
    if part == EXTERNAL_OBLIQUE:
        return "external oblique"
    if part == INTERNAL_OBLIQUE:
        return "internal oblique"
    if part == ERECTOR_SPINAE:
        return "erector spinae"
    if part == QUADRATUS_LUMBORUM:
        return "quadratus lumborum"
    if part == PSOAS_MAJOR:
        return "psoas major"
    if part == DIAPHRAGM:
        return "diaphragm"
    if part == INTERCOSTALS:
        return "intercostals"
    if part == SERRATUS_ANTERIOR:
        return "serratus anterior"
    if part == PECTORALIS_MAJOR:
        return "pectoralis major"
    if part == LATISSIMUS_DORSI:
        return "latissimus dorsi"
    if part == TRAPEZIUS:
        return "trapezius"
    if part == RHOMBOIDS:
        return "rhomboids"
    if part == PECTORALIS_MINOR:
        return "pectoralis minor"
    if part == SUBCLAVIUS:
        return "subclavius"
    return "torso muscle"


def named_torso_muscles() -> List[TorsoMuscle]:
    """Return every named torso muscle in a stable order.

    Returns:
        The abdominal wall, the deep back, the diaphragm, the
        intercostals, the four sheets that reach the arm, then the
        rhomboids, the pectoralis minor and the subclavius.
    """
    var parts = List[TorsoMuscle]()
    for index in range(SUBCLAVIUS.value + 1):
        parts.append(TorsoMuscle(index))
    return parts^
