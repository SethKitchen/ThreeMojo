# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skeleton shaped like Mixamo's, written as ASCII FBX text.

A real Mixamo download needs an Adobe account and cannot ship in the
repository. This file writes a smaller skeleton with the same bone names,
the same T-pose and the same kind of animation: `mixamorig:` bones in
centimeters, with a rotation curve on each axis and a translation curve for the
hips. Each bone stands at its parent plus an offset. Nothing is turned at
rest.

    var motions = List[Motion]()
    motions.append(
        Motion("LeftArm", "R", [0.0, 1.0], [0.0, 0.0], [0.0, 0.0], [0.0, -90.0])
    )
    var text = mixamo_text(motions)
"""

comptime TICKS = 46186158000.0

# One bone per line: its name, its parent's name (or `-`), and its offset
# from the parent in centimeters. The T-pose has the arms along x. A Mixamo
# left bone stands at +x.
comptime SKELETON: List[String] = [
    "Hips - 0 100 0",
    "Spine Hips 0 10 0",
    "Spine1 Spine 0 12 0",
    "Spine2 Spine1 0 12 0",
    "Neck Spine2 0 13 0",
    "Head Neck 0 10 0",
    "HeadTop_End Head 0 22 0",
    "LeftShoulder Spine2 4 10 0",
    "LeftArm LeftShoulder 12 0 0",
    "LeftForeArm LeftArm 28 0 0",
    "LeftHand LeftForeArm 25 0 0",
    "LeftHandMiddle1 LeftHand 9 0 0",
    "RightShoulder Spine2 -4 10 0",
    "RightArm RightShoulder -12 0 0",
    "RightForeArm RightArm -28 0 0",
    "RightHand RightForeArm -25 0 0",
    "RightHandMiddle1 RightHand -9 0 0",
    "LeftUpLeg Hips 8 -5 0",
    "LeftLeg LeftUpLeg 0 -44 0",
    "LeftFoot LeftLeg 0 -44 0",
    "LeftToeBase LeftFoot 0 -8 13",
    "LeftToe_End LeftToeBase 0 0 9",
    "RightUpLeg Hips -8 -5 0",
    "RightLeg RightUpLeg 0 -44 0",
    "RightFoot RightLeg 0 -44 0",
    "RightToeBase RightFoot 0 -8 13",
    "RightToe_End RightToeBase 0 0 9",
]


@fieldwise_init
struct Motion(Copyable, Movable):
    """One property of one bone, keyed in seconds on all three axes."""

    var bone: String
    """The bone's name without the prefix, as `LeftArm`."""
    var property: String
    """`T` for the translation in centimeters, `R` for the rotation in
    degrees, or `S` for the scale."""
    var seconds: List[Float64]
    """When each key is."""
    var x: List[Float64]
    """The x value of each key."""
    var y: List[Float64]
    """The y value of each key."""
    var z: List[Float64]
    """The z value of each key."""


struct _Bone(Copyable, Movable):
    """One row of the skeleton table."""

    var name: String
    var parent: Int
    var x: Float64
    var y: Float64
    var z: Float64

    def __init__(
        out self, name: String, parent: Int, x: Float64, y: Float64, z: Float64
    ):
        self.name = name
        self.parent = parent
        self.x = x
        self.y = y
        self.z = z


def _bones() raises -> List[_Bone]:
    """Read the skeleton table."""
    var table = materialize[SKELETON]()
    var names = List[String]()
    for row in table:
        names.append(String(row.split(" ")[0]))
    var bones = List[_Bone]()
    for row in table:
        var parts = row.split(" ")
        var parent = -1
        for index in range(len(names)):
            if names[index] == String(parts[1]):
                parent = index
        bones.append(
            _Bone(
                String(parts[0]),
                parent,
                Float64(String(parts[2])),
                Float64(String(parts[3])),
                Float64(String(parts[4])),
            )
        )
    return bones^


def bone_place(name: String) raises -> Int:
    """Return a bone's place in the table, or minus one.

    Args:
        name: The bone's name without the prefix.

    Returns:
        The place, or minus one.

    Raises:
        Error: If the table cannot be read.
    """
    var bones = _bones()
    for index in range(len(bones)):
        if bones[index].name == name:
            return index
    return -1


def _numbers(values: List[Float64]) -> String:
    """Return numbers separated by commas."""
    var text = String()
    for index in range(len(values)):
        if index > 0:
            text += ","
        text += String(values[index])
    return text^


def _ticks(seconds: List[Float64]) -> String:
    """Return times as FBX ticks separated by commas."""
    var text = String()
    for index in range(len(seconds)):
        if index > 0:
            text += ","
        text += String(Int(seconds[index] * TICKS))
    return text^


def _curve(id: Int, seconds: List[Float64], values: List[Float64]) -> String:
    """Return one animation curve."""
    var count = String(len(seconds))
    return (
        "\tAnimationCurve: "
        + String(id)
        + ', "AnimCurve::", "" {\n\t\tKeyTime: *'
        + count
        + " {\n\t\t\ta: "
        + _ticks(seconds)
        + "\n\t\t}\n\t\tKeyValueFloat: *"
        + count
        + " {\n\t\t\ta: "
        + _numbers(values)
        + "\n\t\t}\n\t}\n"
    )


def mixamo_text(
    motions: List[Motion],
    leave_out: String = "",
    prefix: String = "mixamorig:",
    stack: String = "mixamo.com",
    upside_down: Bool = False,
    duplicate: String = "",
) raises -> String:
    """Return an FBX file of the skeleton with an animation.

    Args:
        motions: The animated properties. None gives a file with no
            animation.
        leave_out: A bone's name to leave out of the file, its children
            hung from the root, or empty to leave none out.
        prefix: What comes before each bone's name.
        stack: The animation's name.
        upside_down: True to turn the hips half a turn about z at rest,
            which puts the feet above them.
        duplicate: A bone's name to write a second time, under the prefix
            `mixamorig1:`, hung from the root. Empty to write none.

    Returns:
        The text.

    Raises:
        Error: If the skeleton table cannot be read.
    """
    var bones = _bones()
    var text = String("; FBX 7.4.0 project file\n")
    text += "FBXHeaderExtension:  {\n\tFBXHeaderVersion: 1003\n"
    text += "\tFBXVersion: 7400\n}\nObjects:  {\n"
    var present = List[Bool]()
    for index in range(len(bones)):
        present.append(bones[index].name != leave_out)
        if not present[index]:
            continue
        text += (
            "\tModel: "
            + String(1000 + index)
            + ', "Model::'
            + prefix
            + bones[index].name
            + '", "LimbNode" {\n\t\tProperties70:  {\n'
        )
        text += (
            '\t\t\tP: "Lcl Translation", "Lcl Translation", "", "A",'
            + String(bones[index].x)
            + ","
            + String(bones[index].y)
            + ","
            + String(bones[index].z)
            + "\n"
        )
        if upside_down and index == 0:
            text += '\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",0,0,180\n'
        text += "\t\t}\n\t}\n"
    if duplicate.byte_length() > 0:
        text += (
            '\tModel: 2000, "Model::mixamorig1:'
            + duplicate
            + '", "LimbNode" {\n\t\tProperties70:  {\n\t\t}\n\t}\n'
        )
    if len(motions) > 0:
        text += (
            '\tAnimationStack: 7000, "AnimStack::' + stack + '", "" {\n\t}\n'
        )
        text += '\tAnimationLayer: 7001, "AnimLayer::Base", "" {\n\t}\n'
    for index in range(len(motions)):
        text += (
            "\tAnimationCurveNode: "
            + String(8000 + index)
            + ', "AnimCurveNode::'
            + motions[index].property
            + '", "" {\n\t}\n'
        )
        text += _curve(
            9000 + 3 * index, motions[index].seconds, motions[index].x
        )
        text += _curve(
            9001 + 3 * index, motions[index].seconds, motions[index].y
        )
        text += _curve(
            9002 + 3 * index, motions[index].seconds, motions[index].z
        )
    text += "}\nConnections:  {\n"
    for index in range(len(bones)):
        if not present[index]:
            continue
        var hung = 0
        if bones[index].parent >= 0 and present[bones[index].parent]:
            hung = 1000 + bones[index].parent
        text += '\tC: "OO",' + String(1000 + index) + "," + String(hung) + "\n"
    if duplicate.byte_length() > 0:
        text += '\tC: "OO",2000,0\n'
    if len(motions) > 0:
        text += '\tC: "OO",7001,7000\n'
    for index in range(len(motions)):
        var property = "Lcl Translation"
        if motions[index].property == "R":
            property = "Lcl Rotation"
        elif motions[index].property == "S":
            property = "Lcl Scaling"
        text += '\tC: "OO",' + String(8000 + index) + ",7001\n"
        text += (
            '\tC: "OP",'
            + String(8000 + index)
            + ","
            + String(1000 + bone_place(motions[index].bone))
            + ', "'
            + property
            + '"\n'
        )
        text += (
            '\tC: "OP",'
            + String(9000 + 3 * index)
            + ","
            + String(8000 + index)
            + ', "d|X"\n'
        )
        text += (
            '\tC: "OP",'
            + String(9001 + 3 * index)
            + ","
            + String(8000 + index)
            + ', "d|Y"\n'
        )
        text += (
            '\tC: "OP",'
            + String(9002 + 3 * index)
            + ","
            + String(8000 + index)
            + ', "d|Z"\n'
        )
    text += "}\n"
    return text^
