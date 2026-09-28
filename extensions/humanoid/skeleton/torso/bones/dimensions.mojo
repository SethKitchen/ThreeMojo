# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bones of the torso, as implicit solids.

The set is the twelve thoracic and five lumbar vertebrae, the twelve
pairs of ribs and the sternum. The shoulder girdle belongs to the arm
and is not modeled here.

The torso shares the pelvis frame: the origin is the midpoint of the
two hip joint centers, plus y is proximal, plus x is body-right and plus
z is anterior. The column stands on the pelvis's sacral promontory, so
it meets the sacrum for either sex.

Every landmark is authored in centimeters on the six-foot male template
and scaled by stature. The column climbs in a lumbar lordosis and a
thoracic kyphosis. Each rib is a spline through its head, its tubercle,
its angle and its turn around the chest to the costal cartilage. The
values are template parameters. They are not a cited osteometric
table. A female template is narrower and shallower through the chest.

    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    var d = torso_bone_distance(dims, T7, RIGHT, dims.centers[6])
"""

from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    check_spec,
    finite_point,
    mix_point,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    TEMPLATE_CM,
    pelvis_dimensions,
)
from extensions.humanoid.skeleton.torso.sweep import (
    floats,
    Dome,
    Sweep,
    SweepField,
    spline_points,
    tube,
)
from math.vector3 import Vector3
from std.math import max, min
from units.si import Length

# The female template against the male one: narrower and shallower
# through the chest, the same height.
comptime FEMALE_WIDTH = Float32(0.92)
comptime FEMALE_DEPTH = Float32(0.95)

# Where the male template's sacral promontory lies, in centimeters. The
# torso is authored from it.
comptime PROMONTORY_Y = Float32(6.2)
comptime PROMONTORY_Z = Float32(-1.1)

# Vertebrae, from T1 down to L5.
comptime VERTEBRAE = 17
# Ribs a side.
comptime RIBS = 12
# Cortical shell, as a ratio of stature.
comptime TORSO_SHELL = Float32(0.0008)


@fieldwise_init
struct TorsoBone(Equatable, ImplicitlyCopyable, Writable):
    """Which bone of the torso a caller asks for.

    `T1` through `L5` are the vertebrae, then the sternum, then the
    ribs. The type stops a bare integer at compile time. A value that is
    not one of the named bones is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named torso bone."""
        if self.value < 0:
            return False
        return self.value <= RIB_12.value


comptime T1 = TorsoBone(0)
comptime T2 = TorsoBone(1)
comptime T3 = TorsoBone(2)
comptime T4 = TorsoBone(3)
comptime T5 = TorsoBone(4)
comptime T6 = TorsoBone(5)
comptime T7 = TorsoBone(6)
comptime T8 = TorsoBone(7)
comptime T9 = TorsoBone(8)
comptime T10 = TorsoBone(9)
comptime T11 = TorsoBone(10)
comptime T12 = TorsoBone(11)
comptime L1 = TorsoBone(12)
comptime L2 = TorsoBone(13)
comptime L3 = TorsoBone(14)
comptime L4 = TorsoBone(15)
comptime L5 = TorsoBone(16)
comptime STERNUM = TorsoBone(17)
comptime RIB_1 = TorsoBone(18)
comptime RIB_2 = TorsoBone(19)
comptime RIB_3 = TorsoBone(20)
comptime RIB_4 = TorsoBone(21)
comptime RIB_5 = TorsoBone(22)
comptime RIB_6 = TorsoBone(23)
comptime RIB_7 = TorsoBone(24)
comptime RIB_8 = TorsoBone(25)
comptime RIB_9 = TorsoBone(26)
comptime RIB_10 = TorsoBone(27)
comptime RIB_11 = TorsoBone(28)
comptime RIB_12 = TorsoBone(29)


@fieldwise_init
struct TorsoFrame(ImplicitlyCopyable):
    """Turns template centimeters into points in the torso frame.

    A point is authored against the male template's sacral promontory
    and placed against this pelvis's.
    """

    var stature: Float32
    var wide: Float32
    var deep: Float32
    var anchor: Vector3

    def at(self, x: Float32, y: Float32, z: Float32) -> Vector3:
        """Return one point authored on the six-foot template.

        Args:
            x: Centimeters to the right of the midline.
            y: Centimeters above the hip joint centers.
            z: Centimeters in front of them.

        Returns:
            The point, in meters.
        """
        var unit = TEMPLATE_CM * self.stature
        return self.anchor + Vector3(
            x * unit * self.wide,
            (y - PROMONTORY_Y) * unit,
            (z - PROMONTORY_Z) * unit * self.deep,
        )

    def cm(self, value: Float32) -> Float32:
        """Return a template length in meters, scaled by stature.

        Args:
            value: Centimeters on the six-foot template.

        Returns:
            Meters.
        """
        return value * TEMPLATE_CM * self.stature


struct TorsoDimensions(Copyable, Movable):
    """Size and landmarks of one torso in the pelvis frame.

    Positions are in meters. The lists run from T1 down to L5. Rib
    landmarks are those of the right side.
    """

    var stature: Length
    var sex: Sex
    var frame: TorsoFrame
    # Vertebral body centers and their half-width, half-depth and height.
    var centers: List[Vector3]
    var widths: List[Float32]
    var depths: List[Float32]
    var heights: List[Float32]
    var notch: Vector3
    var sternal_angle: Vector3
    var xiphisternal: Vector3
    var xiphoid: Vector3

    def __init__(
        out self,
        stature: Length,
        sex: Sex,
        frame: TorsoFrame,
        var centers: List[Vector3],
        var widths: List[Float32],
        var depths: List[Float32],
        var heights: List[Float32],
        notch: Vector3,
        sternal_angle: Vector3,
        xiphisternal: Vector3,
        xiphoid: Vector3,
    ):
        """Store a torso's size and landmarks.

        Args:
            stature: Standing height.
            sex: Osteological template.
            frame: The frame that authored the landmarks.
            centers: Vertebral body centers, T1 to L5, in meters.
            widths: Their half-widths, in meters.
            depths: Their half-depths, in meters.
            heights: Their heights, in meters.
            notch: The jugular notch of the sternum.
            sternal_angle: The joint of the manubrium and the body.
            xiphisternal: The joint of the body and the xiphoid.
            xiphoid: The tip of the xiphoid process.
        """
        self.stature = stature
        self.sex = sex
        self.frame = frame
        self.centers = centers^
        self.widths = widths^
        self.depths = depths^
        self.heights = heights^
        self.notch = notch
        self.sternal_angle = sternal_angle
        self.xiphisternal = xiphisternal
        self.xiphoid = xiphoid

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or stature is refused, if a list does not hold
                seventeen vertebrae, if a size is not positive, or if a
                landmark is not finite.
        """
        check_spec(self.stature, self.sex, RIGHT, "torso")
        if (
            len(self.centers) != VERTEBRAE
            or len(self.widths) != VERTEBRAE
            or len(self.depths) != VERTEBRAE
            or len(self.heights) != VERTEBRAE
        ):
            raise Error("A torso needs seventeen vertebrae, T1 to L5")
        for index in range(VERTEBRAE):
            finite_point(self.centers[index], "vertebral body", "torso")
            if not (
                self.widths[index] > 0
                and self.depths[index] > 0
                and self.heights[index] > 0
            ):
                raise Error("A torso vertebra's size must be positive")
        finite_point(self.notch, "jugular notch", "torso")
        finite_point(self.sternal_angle, "sternal angle", "torso")
        finite_point(self.xiphisternal, "xiphisternal joint", "torso")
        finite_point(self.xiphoid, "xiphoid", "torso")


def torso_dimensions(stature: Length, sex: Sex) raises -> TorsoDimensions:
    """Return the landmarks of a torso for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.

    Returns:
        Vertebral and sternal landmarks in the pelvis frame.

    Raises:
        Error: If `sex` is not valid, or stature is not finite or is
            outside the software range.
    """
    check_spec(stature, sex, RIGHT, "torso")
    var pelvis = pelvis_dimensions(stature, sex)
    var wide = FEMALE_WIDTH
    var deep = FEMALE_DEPTH
    if sex == MALE:
        wide = Float32(1)
        deep = Float32(1)
    var f = TorsoFrame(stature.value, wide, deep, pelvis.promontory)
    # Body centers (y, z), half-width, half-depth and height, T1 to L5.
    var y = floats(
        51.9,
        49.9,
        47.9,
        45.8,
        43.7,
        41.5,
        39.2,
        36.8,
        34.3,
        31.7,
        29.0,
        26.2,
        23.3,
        19.9,
        16.4,
        12.9,
        9.4,
    )
    var z = floats(
        -3.6,
        -4.3,
        -4.9,
        -5.3,
        -5.6,
        -5.7,
        -5.6,
        -5.3,
        -4.8,
        -4.1,
        -3.3,
        -2.3,
        -1.2,
        -0.4,
        -0.1,
        -0.6,
        -1.8,
    )
    var w = floats(
        1.55,
        1.5,
        1.45,
        1.45,
        1.5,
        1.55,
        1.6,
        1.7,
        1.8,
        1.9,
        2.0,
        2.1,
        2.3,
        2.4,
        2.5,
        2.6,
        2.7,
    )
    var d = floats(
        1.0,
        1.05,
        1.1,
        1.15,
        1.2,
        1.25,
        1.3,
        1.35,
        1.4,
        1.45,
        1.5,
        1.6,
        1.65,
        1.7,
        1.75,
        1.8,
        1.8,
    )
    var h = floats(
        1.4,
        1.45,
        1.5,
        1.55,
        1.6,
        1.65,
        1.7,
        1.8,
        1.9,
        2.0,
        2.1,
        2.2,
        2.55,
        2.6,
        2.6,
        2.6,
        2.5,
    )
    var centers = List[Vector3]()
    var widths = List[Float32]()
    var depths = List[Float32]()
    var heights = List[Float32]()
    for index in range(VERTEBRAE):
        centers.append(f.at(0, y[index], z[index]))
        widths.append(f.cm(w[index]) * wide)
        depths.append(f.cm(d[index]) * deep)
        heights.append(f.cm(h[index]))
    return TorsoDimensions(
        stature,
        sex,
        f,
        centers^,
        widths^,
        depths^,
        heights^,
        f.at(0, 48.8, 3.5),
        f.at(0, 44.0, 5.2),
        f.at(0, 33.5, 9.3),
        f.at(0, 29.8, 9.0),
    )


def is_paired_bone(part: TorsoBone) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named torso bone.

    Returns:
        True for the ribs. The vertebrae and the sternum lie on the
        midline.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso bone must be a named vertebra, rib or sternum")
    return part.value >= RIB_1.value


def torso_bone_label(part: TorsoBone) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A torso bone, named or not.

    Returns:
        A short label such as `"T7"`, `"L3"`, `"sternum"` or `"rib 5"`,
        or `"torso bone"` when `part` is not named.
    """
    if not part.is_valid():
        return "torso bone"
    if part.value <= T12.value:
        return "T" + String(part.value + 1)
    if part.value <= L5.value:
        return "L" + String(part.value - L1.value + 1)
    if part == STERNUM:
        return "sternum"
    return "rib " + String(part.value - RIB_1.value + 1)


def named_torso_bones() -> List[TorsoBone]:
    """Return every named torso bone in a stable order.

    Returns:
        T1 to L5, the sternum, then ribs one to twelve.
    """
    var parts = List[TorsoBone]()
    for index in range(RIB_12.value + 1):
        parts.append(TorsoBone(index))
    return parts^


def torso_bone_field(
    dimensions: TorsoDimensions, part: TorsoBone, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one torso bone.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: A named bone.
        side: `RIGHT` or `LEFT`. A midline bone ignores it.

    Returns:
        The bone's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not side.is_valid():
        raise Error("A torso side must be RIGHT or LEFT")
    var placed = RIGHT
    if is_paired_bone(part):
        placed = side
    var sweeps = List[Sweep]()
    if part == STERNUM:
        sweeps.append(_sternum(dimensions))
    elif part.value >= RIB_1.value:
        sweeps.append(_rib(dimensions, part.value - RIB_1.value))
    else:
        _vertebra(sweeps, dimensions, part.value)
    var f = dimensions.frame
    return SweepField(
        sweeps^, List[Dome](), placed, f.cm(0.25), f.cm(0.05), 0.004
    )


def torso_bone_distance(
    dimensions: TorsoDimensions,
    part: TorsoBone,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which bone to sample.
        side: `RIGHT` or `LEFT`. A midline bone ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return torso_bone_field(dimensions, part, side).distance(point)


def rib_path(dimensions: TorsoDimensions, rib: Int) -> List[Vector3]:
    """Return the centerline of one right rib, head to front end.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        rib: Zero for the first rib through eleven for the twelfth.

    Returns:
        A smooth curve through the head, the tubercle, the angle, the
        side of the chest and the costochondral junction, in meters.
    """
    var f = dimensions.frame
    var i = min(max(rib, 0), RIBS - 1)
    var c = dimensions.centers[i]
    var w = dimensions.widths[i]
    var dd = dimensions.depths[i]
    # Half-width of the chest at this rib, the front end's x and z, and
    # how far the rib falls from its head to its front, in template cm.
    var reach = floats(
        5.8, 8.5, 10.3, 11.6, 12.5, 13.2, 13.6, 13.8, 13.7, 13.3, 12.4, 10.8
    )
    var end_x = floats(
        3.5, 6.0, 7.2, 8.2, 9.2, 10.0, 10.8, 11.5, 11.8, 11.8, 11.5, 9.5
    )
    var end_z = floats(
        2.5, 4.8, 6.5, 7.8, 8.8, 9.4, 9.6, 9.2, 8.3, 6.8, 2.0, -3.0
    )
    var fall = floats(
        3.0, 5.0, 6.5, 7.5, 8.3, 9.0, 9.5, 9.5, 9.0, 8.0, 5.5, 3.5
    )
    var unit = f.cm(1)
    var head = c + Vector3(w + f.cm(0.3), f.cm(0.3), -f.cm(0.2))
    var drop = f.cm(fall[i])
    var back_z = c.z - f.cm(3.8)
    var front = Vector3(
        f.cm(end_x[i]) * f.wide, head.y - drop, f.at(0, 0, end_z[i]).z
    )
    var tubercle = Vector3(
        w + f.cm(2.1), head.y - f.cm(0.1), c.z - dd - f.cm(1.4)
    )
    var angle_x = min(
        w + f.cm(3.6 + 0.25 * Float32(i)), 0.72 * f.cm(reach[i]) * f.wide
    )
    var angle = Vector3(angle_x, head.y - 0.2 * drop, back_z)
    var side = Vector3(
        f.cm(reach[i]) * f.wide,
        head.y - 0.55 * drop,
        0.5 * (back_z + front.z) - unit,
    )
    var points = List[Vector3]()
    points.append(head)
    points.append(tubercle)
    points.append(angle)
    points.append(side)
    # The floating ribs end at the side; the others turn to the front.
    if i < 10:
        points.append(
            Vector3(
                0.55 * side.x + 0.45 * front.x + 0.4 * unit,
                head.y - 0.82 * drop,
                front.z - 2.8 * unit,
            )
        )
    points.append(front)
    return spline_points(points, 4)


def cartilage_end(dimensions: TorsoDimensions, rib: Int) -> Vector3:
    """Return where one right costal cartilage meets the sternum or the
    cartilage above.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        rib: Zero for the first rib through nine for the tenth.

    Returns:
        The medial end of the cartilage, in meters.
    """
    var f = dimensions.frame
    var ends = List[Vector3]()
    ends.append(f.at(2.2, 47.8, 3.9))
    ends.append(f.at(1.8, 44.0, 5.3))
    ends.append(f.at(1.6, 41.0, 6.4))
    ends.append(f.at(1.7, 38.3, 7.4))
    ends.append(f.at(1.8, 36.0, 8.3))
    ends.append(f.at(1.6, 34.2, 9.0))
    ends.append(f.at(1.2, 33.3, 9.4))
    # The eighth to tenth cartilages join the one above along the
    # costal margin.
    ends.append(f.at(6.5, 31.2, 9.8))
    ends.append(f.at(9.5, 28.8, 9.4))
    ends.append(f.at(11.0, 26.8, 8.6))
    return ends[min(max(rib, 0), 9)]


def _rib(dimensions: TorsoDimensions, rib: Int) -> Sweep:
    """Return one right rib as a tapering tube."""
    var f = dimensions.frame
    var first = f.cm(0.45)
    var last = f.cm(0.36)
    if rib == 0:
        first = f.cm(0.62)
        last = f.cm(0.5)
    elif rib >= 10:
        first = f.cm(0.38)
        last = f.cm(0.24)
    return tube(rib_path(dimensions, rib), first, last)


def _sternum(dimensions: TorsoDimensions) -> Sweep:
    """Return the manubrium, the body and the xiphoid as one plate."""
    var f = dimensions.frame
    # Thickness runs front to back; width runs across.
    var plate = Sweep(Vector3(0, 0, 1))
    plate.add(dimensions.notch, f.cm(0.6), f.cm(2.6) * f.wide)
    plate.add(f.at(0, 46.5, 4.4), f.cm(0.65), f.cm(2.8) * f.wide)
    plate.add(dimensions.sternal_angle, f.cm(0.55), f.cm(1.6) * f.wide)
    plate.add(f.at(0, 40.0, 6.7), f.cm(0.55), f.cm(1.5) * f.wide)
    plate.add(f.at(0, 36.5, 8.1), f.cm(0.6), f.cm(1.8) * f.wide)
    plate.add(dimensions.xiphisternal, f.cm(0.5), f.cm(1.4) * f.wide)
    plate.add(dimensions.xiphoid, f.cm(0.25), f.cm(0.4) * f.wide)
    return plate^


def _vertebra(mut sweeps: List[Sweep], dimensions: TorsoDimensions, index: Int):
    """Append one vertebra: its body, arch and processes."""
    var f = dimensions.frame
    var c = dimensions.centers[index]
    var w = dimensions.widths[index]
    var d = dimensions.depths[index]
    var h = dimensions.heights[index]
    var lumbar = index >= L1.value
    var body = Sweep(Vector3(1, 0, 0))
    body.add(c - Vector3(0, 0.5 * h, 0), w, d)
    body.add(c + Vector3(0, 0.5 * h, 0), w, d)
    sweeps.append(body^)
    var root = c.z - d
    var joint = spinous_root(dimensions, index)
    var tip = spinous_tip(dimensions, index)
    var spine = Sweep(Vector3(1, 0, 0))
    if lumbar:
        spine.add(joint, f.cm(0.4), f.cm(0.9))
        spine.add(tip, f.cm(0.35), f.cm(0.8))
    else:
        spine.add(joint, f.cm(0.4), f.cm(0.5))
        spine.add(tip, f.cm(0.35), f.cm(0.4))
    sweeps.append(spine^)
    for s in range(2):
        var sign = Float32(1)
        if s == 1:
            sign = Float32(-1)
        var pedicle = Vector3(
            sign * (0.5 * w + f.cm(0.35)), c.y, root - f.cm(1.0)
        )
        var arch = List[Vector3]()
        arch.append(Vector3(sign * 0.6 * w, c.y, root + 0.3 * d))
        arch.append(pedicle)
        arch.append(joint)
        sweeps.append(tube(arch, f.cm(0.42), f.cm(0.4)))
        var process = List[Vector3]()
        process.append(pedicle)
        if lumbar:
            process.append(
                Vector3(
                    sign * (w + f.cm(2.8)), c.y + f.cm(0.1), root - f.cm(0.9)
                )
            )
        else:
            process.append(
                Vector3(
                    sign * (w + f.cm(2.1)), c.y + f.cm(0.3), root - f.cm(1.6)
                )
            )
        sweeps.append(tube(process, f.cm(0.4), f.cm(0.38)))


def spinous_root(dimensions: TorsoDimensions, index: Int) -> Vector3:
    """Return where a vertebra's laminae meet behind its canal.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        index: Zero for T1 through sixteen for L5.

    Returns:
        The root of the spinous process, in meters.
    """
    var f = dimensions.frame
    var i = min(max(index, 0), VERTEBRAE - 1)
    var c = dimensions.centers[i]
    return Vector3(0, c.y - f.cm(0.2), c.z - dimensions.depths[i] - f.cm(2.0))


def spinous_tip(dimensions: TorsoDimensions, index: Int) -> Vector3:
    """Return the tip of a vertebra's spinous process.

    The thoracic spines slope down steeply, most in the mid-thorax. The
    lumbar spines run straight back.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        index: Zero for T1 through sixteen for L5.

    Returns:
        The tip, in meters.
    """
    var f = dimensions.frame
    var i = min(max(index, 0), VERTEBRAE - 1)
    var drops = floats(
        1.0,
        1.3,
        1.6,
        1.9,
        2.2,
        2.5,
        2.6,
        2.6,
        2.4,
        2.0,
        1.5,
        1.0,
        0.5,
        0.4,
        0.4,
        0.4,
        0.4,
    )
    var root = spinous_root(dimensions, i)
    return Vector3(
        0, dimensions.centers[i].y - f.cm(drops[i]), root.z - f.cm(2.6)
    )


def canal_center(dimensions: TorsoDimensions, index: Int) -> Vector3:
    """Return the center of a vertebra's canal, where the cord runs.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        index: Zero for T1 through sixteen for L5.

    Returns:
        The canal's center, in meters.
    """
    var f = dimensions.frame
    var i = min(max(index, 0), VERTEBRAE - 1)
    var c = dimensions.centers[i]
    return Vector3(0, c.y, c.z - dimensions.depths[i] - f.cm(0.85))


def template_points(f: TorsoFrame, coords: List[Float32]) -> List[Vector3]:
    """Return points authored as x, y, z triples of template centimeters.

    Args:
        f: The frame that places them.
        coords: A flat list of triples.

    Returns:
        One point per triple, in meters.
    """
    var out = List[Vector3]()
    for index in range(len(coords) // 3):
        out.append(
            f.at(
                coords[3 * index], coords[3 * index + 1], coords[3 * index + 2]
            )
        )
    return out^


def torso_cm(dimensions: TorsoDimensions, value: Float32) -> Float32:
    """Return a template length in meters for this torso.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        value: Centimeters on the six-foot template.

    Returns:
        Meters.
    """
    return dimensions.frame.cm(value)


def torso_side_point(point: Vector3, side: BodySide) -> Vector3:
    """Return a right-side torso point moved to `side`.

    Args:
        point: A point authored on the right, in meters.
        side: `RIGHT` or `LEFT`.

    Returns:
        The point, mirrored on x on the left.
    """
    if side == LEFT:
        return Vector3(-point.x, point.y, point.z)
    return point


def midpoint_path(
    a: List[Vector3], b: List[Vector3], start: Float32, end: Float32, n: Int
) -> List[Vector3]:
    """Return points halfway between two curves, over part of their run.

    Both curves are sampled at the same fractions of their point lists.

    Args:
        a: One curve.
        b: The other curve.
        start: First fraction, zero through one.
        end: Last fraction, zero through one.
        n: How many points.

    Returns:
        The midpoints, in meters.
    """
    var out = List[Vector3]()
    for k in range(n):
        var t = start + (end - start) * Float32(k) / Float32(max(n - 1, 1))
        out.append(mix_point(_along(a, t), _along(b, t), 0.5))
    return out^


def _along(points: List[Vector3], t: Float32) -> Vector3:
    """Return the point `t` of the way along a polyline's samples."""
    var last = len(points) - 1
    var at = min(max(t, 0), 1) * Float32(last)
    var index = min(Int(at), last - 1)
    return mix_point(points[index], points[index + 1], at - Float32(index))


def along_path(points: List[Vector3], t: Float32) -> Vector3:
    """Return the point `t` of the way along a polyline's samples.

    Args:
        points: At least two points.
        t: Zero at the first point through one at the last.

    Returns:
        The interpolated point, in meters.
    """
    return _along(points, t)
