# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `animation.animation_json` and for the `animations` of the
JSON Object format: `exporters.object_json` writes a scene's clips as
three.js's `Object3D.toJSON` does, and `loaders.object_loader` reads them
as `ObjectLoader.parseAnimations` does, binding each track below the
object that names the clip as `PropertyBinding.findNode` finds it.

The parsed track names are three.js's, from `PropertyBinding.parseTrackName`
in r180 run in node, and the JSON of a clip is the shape
`AnimationClip.toJSON` writes.
"""

from animation.animation_clip import (
    ADDITIVE_BLEND_MODE,
    AnimationBlendMode,
    AnimationClip,
)
from animation.animation_json import (
    parse_track_name,
    property_kind,
    property_path,
    read_clip,
    read_track,
    track_names,
    write_clip,
    write_track,
)
from animation.keyframe_track import (
    BEZIER,
    CAMERA_FOV,
    CAMERA_ZOOM,
    KeyframeTrack,
    LIGHT_ANGLE,
    LIGHT_COLOR,
    LIGHT_DISTANCE,
    LIGHT_INTENSITY,
    LightIndex,
    MATERIAL_OPACITY,
    MATERIAL_WIREFRAME,
    MORPH_INFLUENCE,
    MeshIndex,
    NODE_NAME,
    OrthographicCameraIndex,
    POSITION,
    PerspectiveCameraIndex,
    QUATERNION,
    SCALE,
    SKINNED_MORPH_INFLUENCE,
    SMOOTH,
    STEP,
    SkinnedMeshIndex,
    TrackKind,
    TrackTarget,
    VISIBLE,
    light_target,
    material_target,
    morph_target,
    node_target,
    orthographic_camera_target,
    perspective_camera_target,
    skinned_morph_target,
)
from cameras.camera_list import CameraList
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.json_writer import JsonWriter
from exporters.object_json import object_to_json
from geometries.box import box
from lights.light import point_light
from loaders.json import parse_json
from loaders.object_loader import read_object_json
from materials.material import Material, MaterialId
from math.matrix4 import Matrix4
from objects.mesh import Mesh
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime TOLERANCE = Float64(1e-5)


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


# --- track names ------------------------------------------------------------


def check_path(
    name: String,
    node: String,
    object: String,
    index: String,
    property: String,
    property_index: String,
) raises:
    """Assert a name parses into three.js's parts."""
    var path = parse_track_name(name)
    assert_equal(path.node_name, node)
    assert_equal(path.object_name, object)
    assert_equal(path.object_index, index)
    assert_equal(path.property_name, property)
    assert_equal(path.property_index, property_index)


def test_track_names_parse_as_three_js_parses_them() raises:
    check_path("Cube.position", "Cube", "", "", "position", "")
    check_path(".material.opacity", "", "material", "", "opacity", "")
    check_path(".bones[hip].quaternion", "", "bones", "hip", "quaternion", "")
    check_path(
        ".morphTargetInfluences[2]", "", "", "", "morphTargetInfluences", "2"
    )
    check_path("a.b.c.position", "a.b.c", "", "", "position", "")
    check_path("a.material.color", "a", "material", "", "color", "")
    check_path("dir/sub:Node.scale", "Node", "", "", "scale", "")
    check_path(
        "uuid-1.material.opacity", "uuid-1", "material", "", "opacity", ""
    )
    check_path(
        "Node.materials[0].opacity", "Node", "materials", "0", "opacity", ""
    )
    check_path("a.b[x.y]", "a", "", "", "b", "x.y")
    check_path("bones[hip].position", "", "bones", "hip", "position", "")


def test_a_name_three_js_cannot_parse_is_refused() raises:
    with assert_raises(contains="property after a dot"):
        _ = parse_track_name("position")
    with assert_raises(contains="property after a dot"):
        _ = parse_track_name("")
    with assert_raises(contains="property must be a word"):
        _ = parse_track_name("a.b]")
    with assert_raises(contains="property must be a word"):
        _ = parse_track_name("a.[0]")
    with assert_raises(contains="must close"):
        _ = parse_track_name("a.b[0")
    with assert_raises(contains="must close"):
        _ = parse_track_name("a.b[]")
    with assert_raises(contains="directory must be a word"):
        _ = parse_track_name("/Node.position")
    with assert_raises(contains="object must be a word"):
        _ = parse_track_name(".[x].position")
    with assert_raises(contains="node cannot hold"):
        _ = parse_track_name("a[1].b.position")
    with assert_raises(contains="node cannot hold"):
        _ = parse_track_name("a.b/c.position")


def test_a_property_is_a_kind_and_back() raises:
    assert_equal(property_kind(parse_track_name("a.position")), POSITION)
    assert_equal(property_kind(parse_track_name("a.name")), NODE_NAME)
    assert_equal(property_kind(parse_track_name("a.color")), LIGHT_COLOR)
    assert_equal(property_kind(parse_track_name("a.fov")), CAMERA_FOV)
    assert_equal(
        property_kind(parse_track_name("a.material.wireframe")),
        MATERIAL_WIREFRAME,
    )
    assert_equal(
        property_kind(parse_track_name(".bones[hip].quaternion")), QUATERNION
    )
    assert_equal(
        property_kind(parse_track_name(".morphTargetInfluences[1]")),
        MORPH_INFLUENCE,
    )
    with assert_raises(contains="not its map"):
        _ = property_kind(parse_track_name("a.map.offset"))
    with assert_raises(contains="property named"):
        _ = property_kind(parse_track_name("a.bones[hip].intensity"))
    with assert_raises(contains="one part of"):
        _ = property_kind(parse_track_name("a.position[x]"))
    assert_equal(
        property_path(morph_target(MeshIndex(0), 3)),
        ".morphTargetInfluences[3]",
    )
    assert_equal(
        property_path(material_target(MaterialId(0), MATERIAL_OPACITY)),
        ".material.opacity",
    )
    assert_equal(
        property_path(light_target(LightIndex(0), LIGHT_ANGLE)), ".angle"
    )
    assert_equal(property_path(node_target(NodeId(0), SCALE)), ".scale")
    assert_equal(property_path(TrackTarget(TrackKind(9), 0, 0)), "")


# --- writing and reading one clip -------------------------------------------


def written(clip: AnimationClip, names: List[String]) raises -> String:
    """Return a clip written with a uuid of `u`."""
    var writer = JsonWriter()
    write_clip(writer, clip, names, "u")
    return writer.finish()


def test_a_clip_is_written_as_three_js_writes_it() raises:
    var node = NodeId(0)
    var clip = AnimationClip(
        "walk",
        [
            KeyframeTrack(node, POSITION, seconds([0, 1]), [0, 0, 0, 1, 2, 3]),
            KeyframeTrack(node, VISIBLE, seconds([0, 1]), [1, 0]),
            KeyframeTrack(
                node_target(node, NODE_NAME), seconds([0, 1]), ["a", "b"]
            ),
            KeyframeTrack(
                material_target(MaterialId(0), MATERIAL_OPACITY),
                seconds([0, 2]),
                [0, 1],
                SMOOTH,
            ),
        ],
    )
    var text = written(
        clip, ["Cube.position", "Cube.visible", "Cube.name", ".x"]
    )
    # The shape three.js's `toJSON` writes, and its numbers, each written
    # so that it reads back to the same `Float32`.
    assert_equal(
        text,
        '{"name":"walk","duration":2.0,"tracks":[{"name":"Cube.position",'
        + '"times":[0.0,1.0],"values":[0.0,0.0,0.0,1.0,2.0,3.0],'
        + '"type":"vector"},{"name":"Cube.visible","times":[0.0,1.0],'
        + '"values":[true,false],"type":"bool"},{"name":"Cube.name",'
        + '"times":[0.0,1.0],"values":["a","b"],"type":"string"},'
        + '{"name":".x","times":[0.0,2.0],"values":[0.0,1.0],'
        + '"interpolation":2302,"type":"number"}],"uuid":"u",'
        + '"blendMode":2500,"userData":"{}"}',
    )


def test_a_bezier_track_writes_its_control_points() raises:
    var curve = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        seconds([0, 2]),
        in_tangents=[0, 0, 1.5, 1],
        values=[0, 1],
        out_tangents=[0.5, 0, 2, 1],
        interpolation=BEZIER,
    )
    var clip = AnimationClip("b", [curve^], ADDITIVE_BLEND_MODE)
    var text = written(clip, [".material.opacity"])
    assert_true(text.find('"interpolation":2303') >= 0)
    assert_true(
        text.find(
            '"settings":{"inTangents":[0.0,0.0,1.5,1.0],"outTangents":'
            + "[0.5,0.0,2.0,1.0]}"
        )
        >= 0
    )
    assert_true(text.find('"blendMode":2501') >= 0)
    var held = AnimationClip(
        "s",
        [
            KeyframeTrack(
                material_target(MaterialId(0), MATERIAL_OPACITY),
                seconds([0, 1]),
                [0, 1],
                STEP,
            )
        ],
    )
    assert_true(written(held, ["a"]).find('"interpolation":2300') >= 0)


def test_what_three_js_json_cannot_hold_is_not_written() raises:
    var spline = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        seconds([0, 1]),
        in_tangents=[0, 0],
        values=[0, 1],
        out_tangents=[0, 0],
    )
    var writer = JsonWriter()
    with assert_raises(contains="cubic spline"):
        write_track(writer, spline, "a")
    var broken = KeyframeTrack(NodeId(0), POSITION, seconds([0]), [0, 0, 0])
    broken.values = List[Float32]()
    with assert_raises(contains="constructors build"):
        write_track(writer, broken, "a")
    var clip = AnimationClip(
        "c", [KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0])]
    )
    with assert_raises(contains="one name a track"):
        _ = written(clip, List[String]())
    clip.blend_mode = AnimationBlendMode(5)
    with assert_raises(contains="blend mode"):
        _ = written(clip, ["a.visible"])


def read_one(
    clip_json: String, targets: List[Optional[TrackTarget]]
) raises -> Optional[AnimationClip]:
    """Read a clip from its JSON."""
    var document = parse_json(clip_json)
    return read_clip(document, document.root(), targets)


def track_json(fields: String) -> String:
    """Return a clip of one track whose fields are given."""
    return '{"name":"c","tracks":[{"name":"a.x",' + fields + "}]}"


def test_a_clip_reads_back_what_it_wrote() raises:
    var node = NodeId(0)
    var name = node_target(node, NODE_NAME)
    var clip = AnimationClip(
        "walk",
        [
            KeyframeTrack(node, POSITION, seconds([0, 1]), [0, 0, 0, 1, 2, 3]),
            KeyframeTrack(node, VISIBLE, seconds([0, 1]), [1, 0]),
            KeyframeTrack(name, seconds([0, 1]), ["a", "b"]),
            KeyframeTrack(
                material_target(MaterialId(0), MATERIAL_OPACITY),
                seconds([0, 2]),
                in_tangents=[0, 0, 1.5, 1],
                values=[0, 1],
                out_tangents=[0.5, 0, 2, 1],
                interpolation=BEZIER,
            ),
        ],
        duration=Duration(3, SECOND),
    )
    var text = written(clip, ["a.position", "a.visible", "a.name", "a.x"])
    var document = parse_json(text)
    var names = track_names(document, document.root())
    assert_equal(names[2], "a.name")
    var targets: List[Optional[TrackTarget]] = [
        node_target(node, POSITION),
        node_target(node, VISIBLE),
        name,
        material_target(MaterialId(0), MATERIAL_OPACITY),
    ]
    var back = read_clip(document, document.root(), targets).value().copy()
    assert_equal(back.name, "walk")
    assert_equal(back.duration().to(SECOND), 3)
    assert_equal(back.tracks[0].values[5], 3)
    assert_equal(back.tracks[1].values[1], 0)
    assert_equal(back.tracks[2].sample_string(Duration(1, SECOND)), "b")
    assert_equal(back.tracks[3].interpolation, BEZIER)
    assert_equal(back.tracks[3].in_tangents[2], 1.5)
    # A track that names nothing is left out, and a clip of none is none.
    var none: List[Optional[TrackTarget]] = [None, None, None, None]
    assert_false(Bool(read_clip(document, document.root(), none)))


def test_a_clip_with_fps_divides_its_times() raises:
    var target = material_target(MaterialId(0), MATERIAL_OPACITY)
    var clip = (
        read_one(
            '{"fps":10,"duration":-1,"blendMode":2501,"tracks":[{"name":"a",'
            + '"type":"number","times":[0,10],"values":[0,1],'
            + '"interpolation":2303,"settings":{"inTangents":[0,0,5,1],'
            + '"outTangents":[5,0,10,1]}}]}',
            [target],
        )
        .value()
        .copy()
    )
    assert_equal(clip.name, "")
    assert_equal(clip.blend_mode, ADDITIVE_BLEND_MODE)
    assert_almost_equal(clip.duration().to(SECOND), 1, atol=TOLERANCE)
    assert_almost_equal(
        Float64(clip.tracks[0].in_tangents[2]), 0.5, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(clip.tracks[0].out_tangents[0]), 0.5, atol=TOLERANCE
    )
    var stepped = (
        read_one(
            track_json(
                '"type":"Float","times":[0,1],"values":[0,1],"interpolation":2300'
            ),
            [target],
        )
        .value()
        .copy()
    )
    assert_equal(stepped.tracks[0].interpolation, STEP)
    var linear = (
        read_one(
            track_json(
                '"type":"scalar","times":[0,1],"values":[0,1],"interpolation":2301'
            ),
            [target],
        )
        .value()
        .copy()
    )
    assert_equal(linear.tracks[0].interpolation.value, 1)
    var smooth = (
        read_one(
            track_json(
                '"type":"number","times":[0,1],"values":[0,1],"interpolation":2302'
            ),
            [target],
        )
        .value()
        .copy()
    )
    assert_equal(smooth.tracks[0].interpolation, SMOOTH)
    var nothing = read_one('{"tracks":[]}', List[Optional[TrackTarget]]())
    assert_false(Bool(nothing))
    var empty = parse_json('{"tracks":[]}')
    assert_equal(len(track_names(empty, empty.root())), 0)


def test_every_three_js_type_name_is_read() raises:
    var number = material_target(MaterialId(0), MATERIAL_OPACITY)
    var fields = '"times":[0,1],"values":[0,1]'
    for name in ["double", "integer", "number"]:
        _ = (
            read_one(track_json('"type":"' + name + '",' + fields), [number])
            .value()
            .copy()
        )
    var vector = node_target(NodeId(0), POSITION)
    var three = '"times":[0,1],"values":[0,0,0,1,1,1]'
    for name in ["Vector", "vector2", "vector3", "vector4"]:
        _ = (
            read_one(track_json('"type":"' + name + '",' + three), [vector])
            .value()
            .copy()
        )
    with assert_raises(contains="type must be"):
        _ = read_one(track_json('"type":"vectorX",' + three), [vector])
    var flag = node_target(NodeId(0), VISIBLE)
    _ = (
        read_one(
            track_json('"type":"boolean","times":[0,1],"values":[true,false]'),
            [flag],
        )
        .value()
        .copy()
    )
    var turn = node_target(NodeId(0), QUATERNION)
    _ = (
        read_one(
            track_json(
                '"type":"quaternion","times":[0,1],"values":[0,0,0,1,0,0,0,1]'
            ),
            [turn],
        )
        .value()
        .copy()
    )
    with assert_raises(contains="type must be"):
        _ = read_one(track_json('"type":"color",' + fields), [number])
    with assert_raises(contains="type must be"):
        _ = read_one(track_json('"type":"number",' + fields), [flag])


def test_a_malformed_clip_is_refused() raises:
    var number = material_target(MaterialId(0), MATERIAL_OPACITY)
    var fields = '"times":[0,1],"values":[0,1]'
    with assert_raises(contains="needs a type"):
        _ = read_one(track_json(fields), [number])
    with assert_raises(contains="keys form"):
        _ = read_one(track_json('"type":"number","keys":[]'), [number])
    with assert_raises(contains="needs a times array"):
        _ = read_one(
            track_json('"type":"number","keys":[],"times":1'), [number]
        )
    with assert_raises(contains="needs a values array"):
        _ = read_one(track_json('"type":"number","times":[0]'), [number])
    with assert_raises(contains="needs a values array"):
        _ = read_one(
            track_json('"type":"number","times":[0],"values":1'), [number]
        )
    with assert_raises(contains="needs a times array"):
        _ = read_one(track_json('"type":"number","values":[0]'), [number])
    with assert_raises(contains="at least one key"):
        _ = read_one(
            track_json('"type":"number","times":[],"values":[]'), [number]
        )
    with assert_raises(contains="at least one key"):
        _ = read_one(
            track_json('"type":"string","times":[],"values":[]'),
            [node_target(NodeId(0), NODE_NAME)],
        )
    with assert_raises(contains="needs its settings"):
        _ = read_one(
            track_json(
                '"type":"number",'
                + fields
                + ',"interpolation":2303,"settings":1'
            ),
            [number],
        )
    with assert_raises(contains="two control points"):
        _ = read_one(
            track_json(
                '"type":"number",'
                + fields
                + ',"interpolation":2303,"settings":{"inTangents":[],'
                + '"outTangents":[]}'
            ),
            [number],
        )
    with assert_raises(contains="three.js's four"):
        _ = read_one(
            track_json('"type":"number",' + fields + ',"interpolation":2299'),
            [number],
        )
    with assert_raises(contains="needs its settings"):
        _ = read_one(
            track_json('"type":"number",' + fields + ',"interpolation":2303'),
            [number],
        )
    with assert_raises(contains="true or false"):
        _ = read_one(
            track_json('"type":"bool","times":[0],"values":[1]'),
            [node_target(NodeId(0), VISIBLE)],
        )
    with assert_raises(contains="one target a track"):
        _ = read_one(track_json('"type":"number",' + fields), [])
    with assert_raises(contains="fps must be above zero"):
        _ = read_one(
            '{"fps":0,"tracks":[{"name":"a","type":"number",' + fields + "}]}",
            [number],
        )
    with assert_raises(contains="normal or additive"):
        _ = read_one(
            '{"blendMode":2502,"tracks":[{"name":"a","type":"number",'
            + fields
            + "}]}",
            [number],
        )
    var document = parse_json('{"tracks":[1]}')
    with assert_raises(contains="must be an object"):
        _ = track_names(document, document.root())
    document = parse_json("[]")
    with assert_raises(contains="must be an object"):
        _ = track_names(document, document.root())
    document = parse_json('{"tracks":{}}')
    with assert_raises(contains="needs a tracks array"):
        _ = track_names(document, document.root())
    document = parse_json("{}")
    with assert_raises(contains="needs a tracks array"):
        _ = track_names(document, document.root())
    document = parse_json('{"tracks":[{}]}')
    with assert_raises(contains="needs a name"):
        _ = track_names(document, document.root())


def test_a_track_on_every_morph_target_is_split() raises:
    var every = TrackTarget(MORPH_INFLUENCE, 0, -1)
    var clip = (
        read_one(
            track_json('"type":"number","times":[0,1],"values":[0,1,1,0]'),
            [every],
        )
        .value()
        .copy()
    )
    assert_equal(clip.track_count(), 2)
    assert_equal(clip.tracks[1].target.slot, 1)
    assert_equal(clip.tracks[1].values[0], 1)
    assert_equal(clip.tracks[1].values[1], 0)
    with assert_raises(contains="same number of values a key"):
        _ = read_one(
            track_json('"type":"number","times":[0,1],"values":[0,1,1]'),
            [every],
        )
    with assert_raises(contains="same number of values a key"):
        _ = read_one(
            track_json('"type":"number","times":[],"values":[]'), [every]
        )
    with assert_raises(contains="one to eight"):
        _ = read_one(
            track_json('"type":"number","times":[0],"values":[]'), [every]
        )
    with assert_raises(contains="one to eight"):
        _ = read_one(
            track_json(
                '"type":"number","times":[0],"values":[0,0,0,0,0,0,0,0,0]'
            ),
            [every],
        )
    # A Bezier track on every target takes each target's control points.
    var curve = (
        read_one(
            track_json(
                '"type":"number","times":[0,1],"values":[0,1,1,0],'
                + '"interpolation":2303,"settings":{"inTangents":'
                + '[0,0,0,1,1,1,1,0],"outTangents":[0,0,0,1,1,1,1,0]}'
            ),
            [every],
        )
        .value()
        .copy()
    )
    assert_equal(curve.tracks[1].in_tangents[1], 1)
    assert_equal(curve.tracks[1].in_tangents[3], 0)


# --- a scene's animations in the JSON Object format -------------------------


def wrap(document: String) -> String:
    """Return an Object document around libraries and an `object`."""
    return (
        '{"metadata":{"version":4.6,"type":"Object","generator":'
        + '"Object3D.toJSON"},"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        + '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
        + document
        + "}"
    )


def track(name: String, type: String, values: String) -> String:
    """Return a two-key track's JSON."""
    return (
        '{"name":"'
        + name
        + '","type":"'
        + type
        + '","times":[0,1],"values":'
        + values
        + "}"
    )


def clip(uuid: String, tracks: List[String]) -> String:
    """Return a clip's JSON."""
    var out = '{"uuid":"' + uuid + '","name":"' + uuid + '","tracks":['
    for index in range(len(tracks)):
        if index > 0:
            out += ","
        out += tracks[index]
    return out + "]}"


comptime WORLD = (
    '"object":{"uuid":"s","type":"Scene","animations":[ANIMATIONS],'
    '"children":[{"uuid":"n1","type":"Mesh","name":"Box","geometry":"g",'
    '"material":"m"},{"uuid":"n2","type":"Object3D","name":"Holder",'
    '"children":[{"uuid":"n3","type":"PointLight","name":"Lamp"}]},'
    '{"uuid":"n4","type":"PerspectiveCamera","name":"Eye"},'
    '{"uuid":"n5","type":"OrthographicCamera","name":"Plan"}]}'
)


def load(
    animations: String, named: String, var scene: Scene
) raises -> Tuple[Scene, Assets, List[AnimationClip], List[NodeId]]:
    """Read the world with an animations library and the uuids its scene
    names."""
    var assets = Assets()
    var text = wrap(
        '"animations":['
        + animations
        + "],"
        + String(WORLD).replace("ANIMATIONS", named)
    )
    var model = read_object_json(text, scene, assets)
    return (
        scene^,
        assets^,
        model.animations.copy(),
        model.animation_roots.copy(),
    )


def test_a_scene_reads_the_clips_it_names() raises:
    var tracks: List[String] = [
        track("Box.position", "vector", "[0,0,0,1,2,3]"),
        track("Box.material.opacity", "number", "[1,0]"),
        track("Box.morphTargetInfluences[1]", "number", "[0,1]"),
        track("Box.morphTargetInfluences", "number", "[0,1,1,0]"),
        track("Lamp.intensity", "number", "[1,2]"),
        track("n3.distance", "number", "[1,2]"),
        track("Eye.fov", "number", "[50,60]"),
        track("Plan.zoom", "number", "[1,2]"),
        track("Box.visible", "bool", "[true,false]"),
        track("Box.name", "string", '["a","b"]'),
        track("Ghost.position", "vector", "[0,0,0,1,1,1]"),
        track("Plan.fov", "number", "[50,60]"),
        track("Holder.intensity", "number", "[1,2]"),
        track("Holder.fov", "number", "[1,2]"),
        track("Holder.material.opacity", "number", "[1,2]"),
        track("Holder.morphTargetInfluences[0]", "number", "[1,2]"),
        track("Holder.bones[hip].position", "vector", "[0,0,0,1,1,1]"),
    ]
    var ghost: List[String] = [
        track("Nobody.position", "vector", "[0,0,0,1,1,1]")
    ]
    var read = load(
        clip("c", tracks) + "," + clip("d", ghost), '"c","d"', Scene()
    )
    ref clips = read[2]
    assert_equal(len(clips), 1)
    assert_equal(read[3][0], NO_PARENT)
    ref walk = clips[0]
    assert_equal(walk.name, "c")
    assert_equal(walk.track_count(), 11)
    assert_equal(walk.tracks[0].target, node_target(NodeId(0), POSITION))
    assert_equal(
        walk.tracks[1].target, material_target(MaterialId(0), MATERIAL_OPACITY)
    )
    assert_equal(walk.tracks[2].target, morph_target(MeshIndex(0), 1))
    assert_equal(walk.tracks[3].target, morph_target(MeshIndex(0), 0))
    assert_equal(walk.tracks[4].target, morph_target(MeshIndex(0), 1))
    assert_equal(
        walk.tracks[5].target, light_target(LightIndex(0), LIGHT_INTENSITY)
    )
    assert_equal(
        walk.tracks[6].target, light_target(LightIndex(0), LIGHT_DISTANCE)
    )
    assert_equal(
        walk.tracks[7].target,
        perspective_camera_target(PerspectiveCameraIndex(0), CAMERA_FOV),
    )
    assert_equal(
        walk.tracks[8].target,
        orthographic_camera_target(OrthographicCameraIndex(0), CAMERA_ZOOM),
    )
    assert_equal(walk.tracks[10].sample_string(Duration(1, SECOND)), "b")


def test_a_track_the_loader_cannot_bind_is_refused() raises:
    var own: List[String] = [track(".position", "vector", "[0,0,0,1,1,1]")]
    with assert_raises(contains="scene itself"):
        _ = load(clip("c", own), '"c"', Scene())
    with assert_raises(contains="no animation has the uuid"):
        _ = load(clip("c", own), '"x"', Scene())
    var far: List[String] = [
        track("Box.morphTargetInfluences[9]", "number", "[0,1]")
    ]
    with assert_raises(contains="eight morph influences"):
        _ = load(clip("c", far), '"c"', Scene())
    var below: List[String] = [
        track("Box.morphTargetInfluences[-1]", "number", "[0,1]")
    ]
    with assert_raises(contains="eight morph influences"):
        _ = load(clip("c", below), '"c"', Scene())
    # A scene naming no clip, and a clip of no track, read nothing.
    assert_equal(len(load(clip("c", own), "", Scene())[2]), 0)
    assert_equal(len(load(clip("c", List[String]()), '"c"', Scene())[2]), 0)
    # Read below nodes already in the scene, the indices move with them.
    var ahead = Scene()
    _ = ahead.add(Object3D())
    var moved: List[String] = [track("Box.position", "vector", "[0,0,0,1,1,1]")]
    var read = load(clip("c", moved), '"c"', ahead^)
    assert_equal(read[2][0].tracks[0].target.index, 1)


comptime RIG = (
    '"skeletons":[{"uuid":"k","bones":["b"]}],"animations":[ANIMATIONS],'
    '"object":{"uuid":"o","type":"SkinnedMesh","name":"Body","geometry":"g",'
    '"material":"m","skeleton":"k","animations":["c"],'
    '"children":[{"uuid":"b","type":"Bone","name":"hip"},'
    '{"uuid":"x","type":"Object3D","name":"Other"}]}'
)


def test_a_skinned_mesh_binds_its_bones_and_its_own_properties() raises:
    var tracks: List[String] = [
        track(".bones[hip].quaternion", "quaternion", "[0,0,0,1,0,0,0,1]"),
        track("hip.position", "vector", "[0,0,0,1,1,1]"),
        track(".morphTargetInfluences[0]", "number", "[0,1]"),
        track(".material.opacity", "number", "[1,0]"),
        track("Body.scale", "vector", "[1,1,1,2,2,2]"),
        track("o.visible", "bool", "[true,false]"),
        track(".bones[nobody].position", "vector", "[0,0,0,1,1,1]"),
        track("Other.position", "vector", "[0,0,0,1,1,1]"),
    ]
    var scene = Scene()
    var assets = Assets()
    var model = read_object_json(
        wrap(String(RIG).replace("ANIMATIONS", clip("c", tracks))),
        scene,
        assets,
    )
    assert_equal(len(model.animations), 1)
    assert_equal(model.animation_roots[0], model.node("o"))
    ref walk = model.animations[0]
    assert_equal(walk.track_count(), 7)
    var hip = model.node("b")
    assert_equal(walk.tracks[0].target, node_target(hip, QUATERNION))
    assert_equal(walk.tracks[1].target, node_target(hip, POSITION))
    assert_equal(
        walk.tracks[2].target, skinned_morph_target(SkinnedMeshIndex(0), 0)
    )
    assert_equal(
        walk.tracks[3].target, material_target(MaterialId(0), MATERIAL_OPACITY)
    )
    assert_equal(walk.tracks[4].target, node_target(model.node("o"), SCALE))
    assert_equal(walk.tracks[5].target.kind, VISIBLE)
    assert_equal(walk.tracks[6].target, node_target(model.node("x"), POSITION))


def test_a_root_that_is_not_a_scene_binds_below_itself() raises:
    var tracks: List[String] = [
        track("Child.position", "vector", "[0,0,0,1,1,1]"),
    ]
    var scene = Scene()
    var assets = Assets()
    var model = read_object_json(
        wrap(
            '"animations":['
            + clip("c", tracks)
            + '],"object":{"uuid":"r","type":"Object3D","animations":["c"],'
            + '"children":[{"uuid":"k","type":"Object3D","name":"Child"}]}'
        ),
        scene,
        assets,
    )
    assert_equal(model.animation_roots[0], model.node("r"))
    assert_equal(
        model.animations[0].tracks[0].target,
        node_target(model.node("k"), POSITION),
    )
    # A scene with no objects binds nothing below it.
    var empty = Scene()
    var stored = Assets()
    var none = read_object_json(
        wrap(
            '"animations":['
            + clip("c", tracks)
            + '],"object":{"uuid":"s","type":"Scene","animations":["c"]}'
        ),
        empty,
        stored,
    )
    assert_equal(len(none.animations), 0)


def test_a_material_no_mesh_draws_with_is_not_written() raises:
    var scene = Scene()
    var assets = Assets()
    _ = scene.add(Object3D())
    var clips: List[AnimationClip] = [
        AnimationClip(
            "lost",
            [
                KeyframeTrack(
                    material_target(MaterialId(0), MATERIAL_OPACITY),
                    seconds([0, 1]),
                    [1, 0],
                )
            ],
        )
    ]
    with assert_raises(contains="does not hold"):
        _ = object_to_json(scene, assets, CameraList(), clips)


def test_a_scene_writes_its_clips_and_reads_them_back() raises:
    var scene = Scene()
    var assets = Assets()
    var geometry = assets.geometries.add(
        box(Length(1, METER), Length(1, METER), Length(1, METER))
    )
    _ = assets.materials.add(Material(Color(255, 0, 0)))
    _ = assets.materials.add(Material(Color(0, 255, 0)))
    _ = assets.materials.add(Material(Color(0, 0, 255)))
    var both = scene.add(Object3D())
    var eye_node = scene.add(Object3D())
    var plan_node = scene.add(Object3D())
    var body = scene.add(Object3D())
    var hip = scene.attach(Object3D(), body)
    scene.add_mesh(Mesh(geometry, MaterialId(0), both))
    scene.add_light(point_light(Color(255, 255, 255), both, 1))
    scene.add_skinned_mesh(
        SkinnedMesh(
            geometry, MaterialId(1), body, Skeleton([Bone(hip, Matrix4())])
        )
    )
    var lenses = CameraList()
    var eye = PerspectiveCamera(
        Angle(50, DEGREE), 1, Length(0.1, METER), Length(100, METER)
    )
    eye.attach(eye_node)
    lenses.perspective.append(eye)
    var plan = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(0.1, METER),
        Length(10, METER),
    )
    plan.attach(plan_node)
    lenses.orthographic.append(plan^)
    var times = seconds([0, 1])
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(both, POSITION, times, [0, 0, 0, 1, 2, 3]),
        KeyframeTrack(morph_target(MeshIndex(0), 1), times, [0, 1]),
        KeyframeTrack(
            skinned_morph_target(SkinnedMeshIndex(0), 2), times, [0, 1]
        ),
        KeyframeTrack(
            light_target(LightIndex(0), LIGHT_INTENSITY), times, [1, 2]
        ),
        KeyframeTrack(
            perspective_camera_target(PerspectiveCameraIndex(0), CAMERA_FOV),
            times,
            [50, 60],
        ),
        KeyframeTrack(
            orthographic_camera_target(OrthographicCameraIndex(0), CAMERA_ZOOM),
            times,
            [1, 2],
        ),
        KeyframeTrack(
            material_target(MaterialId(0), MATERIAL_OPACITY), times, [1, 0]
        ),
        KeyframeTrack(
            material_target(MaterialId(1), MATERIAL_OPACITY), times, [1, 0]
        ),
        KeyframeTrack(hip, QUATERNION, times, [0, 0, 0, 1, 0, 0, 0, 1]),
        KeyframeTrack(node_target(hip, NODE_NAME), times, ["a", "b"]),
    ]
    var clips: List[AnimationClip] = [AnimationClip("all", tracks^)]
    var text = object_to_json(scene, assets, lenses, clips)
    assert_true(text.find('"animations":[{"name":"all"') >= 0)
    var back = Scene()
    var stored = Assets()
    var model = read_object_json(text, back, stored)
    assert_equal(len(model.animations), 1)
    ref read = model.animations[0]
    assert_equal(read.track_count(), 10)
    assert_equal(read.tracks[0].target, node_target(model.nodes[0], POSITION))
    assert_equal(read.tracks[1].target, morph_target(MeshIndex(0), 1))
    assert_equal(
        read.tracks[2].target, skinned_morph_target(SkinnedMeshIndex(0), 2)
    )
    assert_equal(
        read.tracks[3].target, light_target(LightIndex(0), LIGHT_INTENSITY)
    )
    assert_equal(read.tracks[4].target.kind, CAMERA_FOV)
    assert_equal(read.tracks[5].target.kind, CAMERA_ZOOM)
    assert_equal(read.tracks[6].target.kind, MATERIAL_OPACITY)
    assert_equal(read.tracks[7].target.kind, MATERIAL_OPACITY)
    assert_equal(read.tracks[9].sample_string(Duration(1, SECOND)), "b")
    # A material no mesh draws with, and a light the scene does not have,
    # are not objects of the document.
    var lost: List[AnimationClip] = [
        AnimationClip(
            "lost",
            [
                KeyframeTrack(
                    material_target(MaterialId(2), MATERIAL_OPACITY),
                    times,
                    [1, 0],
                )
            ],
        )
    ]
    with assert_raises(contains="does not hold"):
        _ = object_to_json(scene, assets, lenses, lost)
    var dark: List[AnimationClip] = [
        AnimationClip(
            "dark",
            [
                KeyframeTrack(
                    light_target(LightIndex(4), LIGHT_INTENSITY), times, [1, 0]
                )
            ],
        )
    ]
    with assert_raises(contains="does not hold"):
        _ = object_to_json(scene, assets, lenses, dark)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
