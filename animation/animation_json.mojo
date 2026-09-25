# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clips written as JSON and read back, three.js's `AnimationClip.toJSON`,
`AnimationClip.parse`, `KeyframeTrack.toJSON` and
`PropertyBinding.parseTrackName`.

## A track's name is a path

three.js names a track's target with a string: `Cube.position`,
`.material.opacity`, `.bones[hip].quaternion`,
`.morphTargetInfluences[2]`. The part before the property names a node,
by its name or its uuid, below the root the clip is played on. Here a
track holds a `TrackTarget`, so a clip written out needs a name for each
track and a clip read in needs a target for each name. The caller gives
them: `exporters.object_json` names each target by the uuid of the object
it writes, and `loaders.object_loader` finds each name's object as
three.js's `PropertyBinding.findNode` does.

`parse_track_name` splits a name as three.js's `parseTrackName` does.
`property_kind` says which `TrackKind` a property is, and `property_path`
says it the other way.

## What a clip is in JSON

    {"name": "walk", "duration": 2, "blendMode": 2500, "uuid": "...",
     "userData": "{}", "tracks": [
        {"name": "Cube.position", "type": "vector",
         "times": [0, 2], "values": [0, 0, 0, 4, 0, 0]}]}

A track writes its `interpolation` when it is not the default of its
type, and a Bezier track its control points in `settings`. A flag track
writes `true` and `false`, and a string track its strings. `fps`, when a
clip has it, divides every time, as three.js's `parse` divides them.

## What differs from three.js

A cubic spline track is refused: three.js's JSON has no interpolation
for glTF's cubic spline, and writes the tangents as values that read back
as keys. A track in three.js's older `keys` form is refused; three.js
writes `times` and `values`. A track whose `type` is not the type of its
property is refused, where three.js builds a track of the wrong type and
binds it anyway.
"""

from animation.animation_clip import (
    ADDITIVE_BLEND_MODE,
    AnimationBlendMode,
    AnimationClip,
    NORMAL_BLEND_MODE,
)
from animation.keyframe_track import (
    BEZIER,
    CAMERA_FAR,
    CAMERA_FOV,
    CAMERA_NEAR,
    CAMERA_ZOOM,
    CUBIC_SPLINE,
    Interpolation,
    KeyframeTrack,
    LIGHT_ANGLE,
    LIGHT_COLOR,
    LIGHT_DISTANCE,
    LIGHT_INTENSITY,
    LIGHT_PENUMBRA,
    LINEAR,
    MATERIAL_ALPHA_TEST,
    MATERIAL_CLEARCOAT,
    MATERIAL_CLEARCOAT_ROUGHNESS,
    MATERIAL_COLOR,
    MATERIAL_EMISSIVE,
    MATERIAL_EMISSIVE_INTENSITY,
    MATERIAL_ENV_MAP_INTENSITY,
    MATERIAL_IOR,
    MATERIAL_MAP_CENTER,
    MATERIAL_MAP_OFFSET,
    MATERIAL_MAP_REPEAT,
    MATERIAL_MAP_ROTATION,
    MATERIAL_METALNESS,
    MATERIAL_OPACITY,
    MATERIAL_REFLECTIVITY,
    MATERIAL_ROUGHNESS,
    MATERIAL_SHININESS,
    MATERIAL_SPECULAR,
    MATERIAL_SPECULAR_INTENSITY,
    MATERIAL_TRANSPARENT,
    MATERIAL_WIREFRAME,
    MORPH_INFLUENCE,
    NODE_NAME,
    POSITION,
    POSITION_ELEMENT,
    QUATERNION,
    ROTATION_ELEMENT,
    SCALE,
    SCALE_ELEMENT,
    SMOOTH,
    STEP,
    TrackKind,
    TrackTarget,
    VISIBLE,
)
from exporters.json_writer import JsonWriter
from core.user_data import user_data_of
from loaders.json import (
    ARRAY,
    BOOLEAN,
    JsonDocument,
    NO_NODE,
    NUMBER,
    OBJECT,
    parse_json,
)
from units.si import Duration, SECOND

# three.js's interpolation constants, as a track's JSON writes them.
comptime INTERPOLATE_DISCRETE = 2300
comptime INTERPOLATE_LINEAR = 2301
comptime INTERPOLATE_SMOOTH = 2302
comptime INTERPOLATE_BEZIER = 2303
# three.js's blend mode constants, as a clip's JSON writes them.
comptime NORMAL_ANIMATION_BLEND_MODE = 2500
comptime ADDITIVE_ANIMATION_BLEND_MODE = 2501


@fieldwise_init
struct TrackPath(Copyable, Movable, Writable):
    """A track name taken apart, three.js's `parseTrackName` result."""

    # The node the track drives, by name or uuid; empty for the root.
    var node_name: String
    # An object on the node, such as `material` or `bones`; empty for the
    # node itself.
    var object_name: String
    # Which of the objects, such as the bone's name; empty for none.
    var object_index: String
    # The property, such as `position`.
    var property_name: String
    # Which part of the property, such as a morph target's index; empty
    # for the whole property.
    var property_index: String


def _is_reserved(byte: UInt8) -> Bool:
    """Return True for a character three.js reserves in a track name: `[`,
    `]`, `.`, `:` and `/`."""
    return byte == 91 or byte == 93 or byte == 46 or byte == 58 or byte == 47


def _word(text: String) -> Bool:
    """Return True if a part of a name is at least one character and holds
    no reserved character."""
    var bytes = text.as_bytes()
    if len(bytes) == 0:
        return False
    for index in range(len(bytes)):  # pragma: no branch
        if _is_reserved(bytes[index]):
            return False
    return True


def _split_index(part: String) raises -> Tuple[String, String]:
    """Return a part's name and the text in its brackets, or an empty
    index when it has none."""
    var open = part.find("[")
    if open < 0:
        return (part, String(""))
    if not part.endswith("]") or part.byte_length() - open - 2 < 1:
        raise Error("A track name's brackets must close around something")
    return (
        String(part[byte=0:open]),
        String(part[byte = open + 1 : part.byte_length() - 1]),
    )


def parse_track_name(name: String) raises -> TrackPath:
    """Take a track name apart, three.js's `PropertyBinding.parseTrackName`.

    The name is `directory/node.object[index].property[index]`, each part
    but the property optional. The node name can hold dots, so the object
    is taken out of it only when it is one three.js knows: `material`,
    `materials`, `bones` or `map`. Directories before a `/` or a `:` are
    read over, as three.js reads over them.

    Args:
        name: The track's name.

    Returns:
        The parts.

    Raises:
        Error: If the name has no property, a part holds a character three.js
            reserves, or a bracket does not close.
    """
    var bytes = name.as_bytes()
    # Split at each dot outside brackets.
    var parts = List[String]()
    var depth = 0
    var start = 0
    var directory_end = 0
    for index in range(len(bytes)):
        var byte = bytes[index]
        if byte == 91:
            depth += 1
        elif byte == 93:
            depth -= 1
        elif depth == 0 and byte == 46:
            parts.append(String(name[byte=start:index]))
            start = index + 1
        elif depth == 0 and (byte == 47 or byte == 58) and len(parts) == 0:
            # three.js's directories: word characters and then a `/` or a
            # `:`, before the node.
            if not _word(String(name[byte=directory_end:index])):
                raise Error("A track name's directory must be a word")
            directory_end = index + 1
            start = index + 1
    parts.append(String(name[byte=start:]))
    if len(parts) < 2:
        raise Error("A track name needs a property after a dot: " + name)
    var property = _split_index(parts[len(parts) - 1])
    if not _word(property[0]):
        raise Error("A track name's property must be a word: " + name)
    var object_name = String("")
    var object_index = String("")
    var node_end = len(parts) - 1
    var bracketed = _split_index(parts[len(parts) - 2])
    if bracketed[1].byte_length() > 0:
        # A node name holds no bracket, so an object with an index is
        # never part of it.
        if not _word(bracketed[0]):
            raise Error("A track name's object must be a word: " + name)
        object_name = bracketed[0]
        object_index = bracketed[1]
        node_end -= 1
    var node = String("")
    for index in range(node_end):
        if index > 0:
            node += "."
        node += parts[index]
    var node_bytes = node.as_bytes()
    for index in range(len(node_bytes)):
        if _is_reserved(node_bytes[index]) and node_bytes[index] != 46:
            raise Error(
                "A track name's node cannot hold a bracket, a colon or a"
                " slash: "
                + name
            )
    if object_name == "":
        var last_dot = node.rfind(".")
        if last_dot >= 0:
            var tail = String(node[byte = last_dot + 1 :])
            if (
                tail == "material"
                or tail == "materials"
                or tail == "bones"
                or tail == "map"
            ):
                object_name = tail
                var head = String(node[byte=0:last_dot])
                node = head
    return TrackPath(
        node,
        object_name,
        object_index,
        property[0],
        property[1],
    )


def _node_properties() -> List[String]:
    """Return the property names of a node, a mesh, a light and a camera,
    in the order of `_node_kinds`."""
    return [
        "position",
        "scale",
        "quaternion",
        "visible",
        "name",
        "morphTargetInfluences",
        "color",
        "intensity",
        "distance",
        "angle",
        "penumbra",
        "fov",
        "zoom",
        "near",
        "far",
    ]


def _node_kinds() -> List[TrackKind]:
    """Return the kinds `_node_properties` name, in its order."""
    return [
        POSITION,
        SCALE,
        QUATERNION,
        VISIBLE,
        NODE_NAME,
        MORPH_INFLUENCE,
        LIGHT_COLOR,
        LIGHT_INTENSITY,
        LIGHT_DISTANCE,
        LIGHT_ANGLE,
        LIGHT_PENUMBRA,
        CAMERA_FOV,
        CAMERA_ZOOM,
        CAMERA_NEAR,
        CAMERA_FAR,
    ]


def _material_properties() -> List[String]:
    """Return the property names of a material, in the order of
    `_material_kinds`."""
    return [
        "color",
        "emissive",
        "specular",
        "opacity",
        "emissiveIntensity",
        "roughness",
        "metalness",
        "shininess",
        "alphaTest",
        "reflectivity",
        "envMapIntensity",
        "clearcoat",
        "clearcoatRoughness",
        "specularIntensity",
        "ior",
        "transparent",
        "wireframe",
    ]


def _material_kinds() -> List[TrackKind]:
    """Return the kinds `_material_properties` name, in its order."""
    return [
        MATERIAL_COLOR,
        MATERIAL_EMISSIVE,
        MATERIAL_SPECULAR,
        MATERIAL_OPACITY,
        MATERIAL_EMISSIVE_INTENSITY,
        MATERIAL_ROUGHNESS,
        MATERIAL_METALNESS,
        MATERIAL_SHININESS,
        MATERIAL_ALPHA_TEST,
        MATERIAL_REFLECTIVITY,
        MATERIAL_ENV_MAP_INTENSITY,
        MATERIAL_CLEARCOAT,
        MATERIAL_CLEARCOAT_ROUGHNESS,
        MATERIAL_SPECULAR_INTENSITY,
        MATERIAL_IOR,
        MATERIAL_TRANSPARENT,
        MATERIAL_WIREFRAME,
    ]


def property_kind(path: TrackPath) raises -> TrackKind:
    """Return the kind of property a track path names.

    A node's `morphTargetInfluences` is `MORPH_INFLUENCE`, which the
    caller makes `SKINNED_MORPH_INFLUENCE` for a skinned mesh. A `color`
    with no object is a light's; a mesh's color is `material.color`. A
    bone's property is a node's, since a bone is a node here. One number
    of a `position`, a `scale` or a `rotation`, `[x]`, `[y]` or `[z]`, is
    an element kind; `element_axis` says which. A `map`'s `offset`,
    `repeat`, `rotation` and `center` are the map kinds of the node's
    material. `materials` names a material's properties too, though the
    loader binds it to nothing, as three.js does.

    Args:
        path: The parsed name.

    Returns:
        The kind.

    Raises:
        Error: If the object is not a material, a map or a bone, the
            property is not one a track here drives, or a property has
            an index it cannot take: only `morphTargetInfluences`, and
            `position`, `scale` and `rotation` by an axis, take one.
    """
    var names = _node_properties()
    var kinds = _node_kinds()
    if path.object_name == "material" or path.object_name == "materials":
        names = _material_properties()
        kinds = _material_kinds()
    elif path.object_name == "map":
        names = ["offset", "repeat", "rotation", "center"]
        kinds = [
            MATERIAL_MAP_OFFSET,
            MATERIAL_MAP_REPEAT,
            MATERIAL_MAP_ROTATION,
            MATERIAL_MAP_CENTER,
        ]
    elif path.object_name == "bones":
        names = ["position", "scale", "quaternion", "visible", "name"]
    elif path.object_name != "":
        raise Error(
            "A track can drive a node, its material, its map or a bone,"
            " not its "
            + path.object_name
        )
    if path.object_name != "map" and path.property_index != "":
        # One number of a vector, three.js's `ArrayElement` binding.
        if path.property_name == "position":
            _ = element_axis(path)
            return POSITION_ELEMENT
        if path.property_name == "scale":
            _ = element_axis(path)
            return SCALE_ELEMENT
        if path.property_name == "rotation":
            _ = element_axis(path)
            return ROTATION_ELEMENT
    for index in range(len(names)):  # pragma: no branch
        if names[index] != path.property_name:
            continue
        var kind = kinds[index]
        if path.property_index != "" and kind != MORPH_INFLUENCE:
            raise Error(
                "A track cannot drive one part of "
                + path.property_name
                + ": the whole value is driven"
            )
        return kind
    raise Error("A track cannot drive a property named " + path.property_name)


def element_axis(path: TrackPath) raises -> Int:
    """Return the axis an element path names, three.js's `[x]`, `[y]` and
    `[z]` on a vector.

    Args:
        path: The parsed name.

    Returns:
        0 for x, 1 for y and 2 for z.

    Raises:
        Error: If the index is not `x`, `y` or `z`. three.js reads a
            number there as a key of the vector, which it does not have.
    """
    if path.property_index == "x":
        return 0
    if path.property_index == "y":
        return 1
    if path.property_index == "z":
        return 2
    raise Error(
        "A track can drive one number of "
        + path.property_name
        + " by x, y or z, not by "
        + path.property_index
    )


def property_path(target: TrackTarget) -> String:
    """Return the part of a track name after the node, for a target: the
    other way from `property_kind`.

    Args:
        target: What the track drives.

    Returns:
        `.position`, `.material.opacity`, `.morphTargetInfluences[2]`,
        `.position[x]`, `.map.offset` and the like, or an empty string for a kind that is not valid.
    """
    var kind = target.kind
    if kind.is_morph():
        return ".morphTargetInfluences[" + String(target.slot) + "]"
    if kind.is_element():
        var axes: List[String] = ["x", "y", "z"]
        var names: List[String] = ["position", "scale", "rotation"]
        return (
            "."
            + names[kind.value - POSITION_ELEMENT.value]
            + "["
            + axes[target.slot]
            + "]"
        )
    if kind.is_map():
        var names: List[String] = ["offset", "repeat", "rotation", "center"]
        return ".map." + names[kind.value - MATERIAL_MAP_OFFSET.value]
    var kinds = _material_kinds()
    for index in range(len(kinds)):  # pragma: no branch
        if kinds[index] == kind:
            return ".material." + _material_properties()[index]
    kinds = _node_kinds()
    for index in range(len(kinds)):  # pragma: no branch
        if kinds[index] == kind:
            return "." + _node_properties()[index]
    return ""


def _interpolation_code(how: Interpolation) -> Int:
    """Return three.js's constant for an interpolation a track writes: one
    that is not its type's default, so `STEP`, `SMOOTH` or `BEZIER`. A
    `LINEAR` track is never a flag or a string, and so is never written
    with its interpolation, and a `CUBIC_SPLINE` track is refused."""
    if how == STEP:
        return INTERPOLATE_DISCRETE
    if how == SMOOTH:
        return INTERPOLATE_SMOOTH
    return INTERPOLATE_BEZIER


def _interpolation_of(code: Int) raises -> Interpolation:
    """Return the interpolation three.js's constant names."""
    if code == INTERPOLATE_DISCRETE:
        return STEP
    if code == INTERPOLATE_LINEAR:
        return LINEAR
    if code == INTERPOLATE_SMOOTH:
        return SMOOTH
    if code == INTERPOLATE_BEZIER:
        return BEZIER
    raise Error("A track's interpolation must be one of three.js's four")


def write_track(
    mut writer: JsonWriter, track: KeyframeTrack, name: String
) raises:
    """Write a track as three.js's `KeyframeTrack.toJSON` writes it.

    Args:
        writer: Where the track goes, as one object.
        track: The track.
        name: Its name, a path to its target.

    Raises:
        Error: If the track is `CUBIC_SPLINE`, which three.js's JSON has
            no interpolation for, if its lists do not agree, or a number
            is not finite.
    """
    if track.interpolation == CUBIC_SPLINE:
        raise Error(
            "three.js's JSON has no cubic spline interpolation to write a"
            " glTF cubic spline track with"
        )
    if not track.validate():
        raise Error("A track to write must be one its constructors build")
    var kind = track.target.kind
    writer.begin_object()
    writer.key("name")
    writer.string(name)
    writer.key("times")
    writer.begin_array()
    for key in range(len(track.times)):  # pragma: no branch
        writer.number(track.times[key])
    writer.end_array()
    writer.key("values")
    writer.begin_array()
    if kind.is_string():
        var texts = track.key_strings()
        for key in range(len(texts)):  # pragma: no branch
            writer.string(texts[key])
    else:
        for at in range(len(track.values)):  # pragma: no branch
            if kind.is_boolean():
                writer.boolean(track.values[at] != 0)
            else:
                writer.number(track.values[at])
    writer.end_array()
    var default = STEP if kind.is_discrete() else LINEAR
    if track.interpolation != default:
        writer.key("interpolation")
        writer.integer(_interpolation_code(track.interpolation))
    if track.interpolation == BEZIER:
        writer.key("settings")
        writer.begin_object()
        writer.key("inTangents")
        _numbers(writer, track.in_tangents)
        writer.key("outTangents")
        _numbers(writer, track.out_tangents)
        writer.end_object()
    writer.key("type")
    writer.string(kind.value_type_name())
    writer.end_object()


def _numbers(mut writer: JsonWriter, values: List[Float32]) raises:
    """Write a list of numbers as an array."""
    writer.begin_array()
    # A Bezier track's control points, which `validate` has found to be
    # two for each of its values, and a track has at least one value.
    for index in range(len(values)):  # pragma: no branch
        writer.number(values[index])
    writer.end_array()


def write_clip(
    mut writer: JsonWriter,
    clip: AnimationClip,
    names: List[String],
    uuid: String,
) raises:
    """Write a clip as three.js's `AnimationClip.toJSON` writes it.

    Args:
        writer: Where the clip goes, as one object.
        clip: The clip.
        names: Each track's name, one a track.
        uuid: The clip's uuid, which an object's `animations` names it by.

    Raises:
        Error: If there is not one name a track, the blend mode is neither
            of the two, or a track cannot be written.
    """
    if len(names) != len(clip.tracks):
        raise Error("A clip to write needs one name a track")
    if not clip.blend_mode.is_valid():
        raise Error("A clip needs a blend mode that exists")
    writer.begin_object()
    writer.key("name")
    writer.string(clip.name)
    writer.key("duration")
    writer.number(clip.length)
    writer.key("tracks")
    writer.begin_array()
    for index in range(len(clip.tracks)):  # pragma: no branch
        write_track(writer, clip.tracks[index], names[index])
    writer.end_array()
    writer.key("uuid")
    writer.string(uuid)
    writer.key("blendMode")
    writer.integer(
        ADDITIVE_ANIMATION_BLEND_MODE if clip.blend_mode
        == ADDITIVE_BLEND_MODE else NORMAL_ANIMATION_BLEND_MODE
    )
    # three.js writes the user data as the text of a JSON object.
    writer.key("userData")
    writer.string(clip.user_data.to_json())
    writer.end_object()


def track_names(document: JsonDocument, clip: Int) raises -> List[String]:
    """Return the name of each track of a clip in JSON, for the caller to
    find a target for each.

    Args:
        document: The document.
        clip: The clip's object.

    Returns:
        One name a track, in order.

    Raises:
        Error: If the clip is not an object, has no `tracks` array, or a
            track has no name.
    """
    if document.kind(clip) != OBJECT:
        raise Error("A clip in JSON must be an object")
    var tracks = document.get(clip, "tracks")
    if tracks == NO_NODE or document.kind(tracks) != ARRAY:
        raise Error("A clip in JSON needs a tracks array")
    var names = List[String]()
    for index in range(document.length(tracks)):
        var track = document.at(tracks, index)
        if document.kind(track) != OBJECT:
            raise Error("A track in JSON must be an object")
        var name = document.get(track, "name")
        if name == NO_NODE:
            raise Error("A track in JSON needs a name")
        names.append(document.string(name))
    return names^


def _type_fits(type_name: String, kind: TrackKind) -> Bool:
    """Return True if a track's JSON `type` is the type of a kind's value,
    by three.js's `getTrackTypeForValueTypeName`, which ignores case."""
    var lower = type_name.lower()
    var wanted = kind.value_type_name()
    if wanted == "number":
        return (
            lower == "scalar"
            or lower == "double"
            or lower == "float"
            or lower == "number"
            or lower == "integer"
        )
    if wanted == "vector":
        return lower.startswith("vector") and (
            lower == "vector"
            or lower == "vector2"
            or lower == "vector3"
            or lower == "vector4"
        )
    if wanted == "bool":
        return lower == "bool" or lower == "boolean"
    return lower == wanted


def _number_list(
    document: JsonDocument, node: Int, key: String
) raises -> List[Float32]:
    """Return an array of numbers under a key, as `Float32`."""
    var list = document.get(node, key)
    if list == NO_NODE or document.kind(list) != ARRAY:
        raise Error("A track in JSON needs a " + key + " array")
    var out = List[Float32]()
    for index in range(document.length(list)):
        out.append(Float32(document.number(document.at(list, index))))
    return out^


def _lane(
    values: List[Float32], stride: Int, width: Int, lane: Int
) -> List[Float32]:
    """Return one lane of values laid out `stride` lanes of `width`
    numbers at a time."""
    var out = List[Float32]()
    for start in range(lane * width, len(values), stride * width):
        for offset in range(width):  # pragma: no branch
            out.append(values[start + offset])
    return out^


def read_track(
    document: JsonDocument,
    track: Int,
    target: TrackTarget,
    frame: Float32,
    stride: Int = 1,
) raises -> KeyframeTrack:
    """Read one track, three.js's `parseKeyframeTrack` and the `scale` that
    `AnimationClip.parse` gives it.

    Args:
        document: The document.
        track: The track's object.
        target: What its name was found to drive.
        frame: How many seconds a unit of its times is: one over the clip's
            `fps`, or one.
        stride: How many morph targets each key of a morph track holds,
            of which the track takes the one `target.slot` names. One for
            every other track.

    Returns:
        The track.

    Raises:
        Error: If the track has no `type` or one that is not its
            property's, holds `keys` in place of `times` and `values`, has
            an interpolation that is not three.js's or that its kind does
            not have, a Bezier interpolation without `settings`, a value of
            the wrong JSON type, or anything a track's constructor
            refuses.
    """
    var kind = target.kind
    var type_node = document.get(track, "type")
    if type_node == NO_NODE:
        raise Error("A track in JSON needs a type")
    if not _type_fits(document.string(type_node), kind):
        raise Error(
            "A track's type must be its property's: " + kind.value_type_name()
        )
    if document.has(track, "keys") and not document.has(track, "times"):
        raise Error("A track's keys form is not read: write times and values")
    var times = List[Duration]()
    var seconds = _number_list(document, track, "times")
    for key in range(len(seconds)):
        times.append(Duration(seconds[key] * frame, SECOND))
    var how = STEP if kind.is_discrete() else LINEAR
    if document.has(track, "interpolation"):
        how = _interpolation_of(
            document.integer(document.get(track, "interpolation"))
        )
    var values = document.get(track, "values")
    if values == NO_NODE or document.kind(values) != ARRAY:
        raise Error("A track in JSON needs a values array")
    if kind.is_string():
        var texts = List[String]()
        for index in range(document.length(values)):
            texts.append(document.string(document.at(values, index)))
        return KeyframeTrack(target, times, texts)
    var numbers = List[Float32]()
    for index in range(document.length(values)):
        var value = document.at(values, index)
        if kind.is_boolean():
            if document.kind(value) != BOOLEAN:
                raise Error("A flag track's values must be true or false")
            numbers.append(
                Float32(1) if document.boolean(value) else Float32(0)
            )
        else:
            numbers.append(Float32(document.number(value)))
    numbers = _lane(numbers, stride, 1, target.slot if stride > 1 else 0)
    if how != BEZIER:
        return KeyframeTrack(target, times, numbers^, how)
    var settings = document.get(track, "settings")
    if settings == NO_NODE or document.kind(settings) != OBJECT:
        raise Error("A Bezier track in JSON needs its settings")
    var lane = target.slot if stride > 1 else 0
    var ins = _lane(
        _number_list(document, settings, "inTangents"), stride, 2, lane
    )
    var outs = _lane(
        _number_list(document, settings, "outTangents"), stride, 2, lane
    )
    for index in range(0, len(ins), 2):
        ins[index] *= frame
    for index in range(0, len(outs), 2):
        outs[index] *= frame
    return KeyframeTrack(
        target,
        times,
        in_tangents=ins^,
        values=numbers^,
        out_tangents=outs^,
        interpolation=BEZIER,
    )


def _whole_morph(
    document: JsonDocument, track: Int, target: TrackTarget, frame: Float32
) raises -> List[KeyframeTrack]:
    """Return one track per morph target of a track that drives every
    morph target of a mesh, three.js's `.morphTargetInfluences` with no
    index."""
    var keys = document.length(document.get(track, "times"))
    var values = _number_list(document, track, "values")
    if keys == 0 or len(values) % keys != 0:
        raise Error("A morph track needs the same number of values a key")
    var stride = len(values) // keys
    if stride == 0:
        raise Error("A morph track needs one influence a key at least")
    var out = List[KeyframeTrack]()
    for slot in range(stride):  # pragma: no branch
        var one = read_track(
            document,
            track,
            TrackTarget(target.kind, target.index, slot),
            frame,
            stride,
        )
        out.append(one^)
    return out^


def read_clip(
    document: JsonDocument, clip: Int, targets: List[Optional[TrackTarget]]
) raises -> Optional[AnimationClip]:
    """Read a clip, three.js's `AnimationClip.parse`.

    Args:
        document: The document.
        clip: The clip's object.
        targets: What each track's name was found to drive, one a track in
            the order of `track_names`, or None for a name that names no
            node below the root. three.js binds such a track to nothing;
            here it is left out.

    Returns:
        The clip, or None if every track was left out.

    Raises:
        Error: If there is not one target a track, the `fps` is not above
            zero, the blend mode is not one of three.js's two, the
            `duration` is not a number, or a track is refused by
            `read_track`.
    """
    var tracks_node = document.get(clip, "tracks")
    if len(targets) != document.length(tracks_node):
        raise Error("A clip in JSON needs one target a track")
    var frame = Float32(1)
    if document.has(clip, "fps"):
        var fps = Float32(document.number(document.get(clip, "fps")))
        if not (fps > 0):
            raise Error("A clip's fps must be above zero")
        frame = 1 / fps
    var blend = NORMAL_BLEND_MODE
    if document.has(clip, "blendMode"):
        var code = document.integer(document.get(clip, "blendMode"))
        if code == ADDITIVE_ANIMATION_BLEND_MODE:
            blend = ADDITIVE_BLEND_MODE
        elif code != NORMAL_ANIMATION_BLEND_MODE:
            raise Error(
                "A clip's blend mode must be three.js's normal or additive"
            )
    var tracks = List[KeyframeTrack]()
    for index in range(len(targets)):
        if not Bool(targets[index]):
            continue
        var target = targets[index].value()
        var track = document.at(tracks_node, index)
        if not target.kind.is_morph() or target.slot != -1:
            tracks.append(read_track(document, track, target, frame))
            continue
        # Every morph target at once, as a glTF clip's weights track is:
        # each key holds one number per target, and each target gets a
        # track of its own.
        var whole = _whole_morph(document, track, target, frame)
        for part in range(len(whole)):  # pragma: no branch
            tracks.append(whole[part].copy())
    if len(tracks) == 0:
        return None
    var name = String("")
    if document.has(clip, "name"):
        name = document.string(document.get(clip, "name"))
    var length: Optional[Duration] = None
    if document.has(clip, "duration"):
        var seconds = document.number(document.get(clip, "duration"))
        if seconds >= 0:
            # three.js's `parse` hands the duration to the constructor as
            # it is, and a negative one means work it out.
            length = Duration(Float32(seconds), SECOND)
    var made = AnimationClip(name, tracks^, blend, length)
    if document.has(clip, "userData"):
        # three.js's `JSON.parse( json.userData || '{}' )`: the text of an
        # object, and an empty text is none.
        var text = document.string(document.get(clip, "userData"))
        if text != "":
            var data = parse_json(text)
            made.user_data = user_data_of(data, data.root())
    return made^
