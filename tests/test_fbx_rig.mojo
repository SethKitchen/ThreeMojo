# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the skins, blend shapes and animation stacks of
`loaders.fbx` and `loaders.fbx_animation`.

`assets/fbx/rig.fbx` is a mesh of a quad and a triangle on a chain of five
bones, with two blend shape channels, a bind pose and two animation
stacks. The expected numbers were printed by running the file through
three.js r180's `FBXLoader.parse` and `AnimationMixer` in Node. The quad
is cut into other triangles here, as `test_fbx` explains, so a corner's
values are checked by the position it names.
"""

from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.keyframe_track import (
    MORPH_INFLUENCE,
    POSITION as TRACK_POSITION,
    QUATERNION,
    SCALE,
    SKINNED_MORPH_INFLUENCE,
)
from core.assets import Assets
from core.buffer_geometry import POSITION
from core.deform import morphed_positions, skin_carriers, skin_pose
from core.object3d import NodeId
from core.scene import Scene
from loaders.fbx import FbxModel, load_fbx, read_fbx
from loaders.fbx_animation import js_key_order
from loaders.fbx_tree import parse_fbx_text
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration

comptime RIG = "assets/fbx/rig.fbx"


def rig() raises -> String:
    """Return the text of the rig."""
    return Path(RIG).read_text()


def swap(text: String, old: String, new: String) raises -> String:
    """Return the text with one piece replaced, which must be there."""
    if text.find(old) < 0:
        raise Error("the fixture has no " + old)
    return text.replace(old, new)


def load(text: String, mut scene: Scene, mut assets: Assets) raises -> FbxModel:
    """Read an ASCII FBX text."""
    return load_fbx(parse_fbx_text(text), "", scene, assets)


def refused(text: String, message: String) raises:
    """Assert that reading a text raises an error that says `message`."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains=message):
        _ = load(text, scene, assets)


def assert_list(actual: List[Float32], expected: List[Float64]) raises:
    """Assert that two lists of numbers are close, entry by entry."""
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_almost_equal(actual[index], Float32(expected[index]), atol=2e-5)


def per_corner(rows: List[Float64], width: Int) -> List[Float64]:
    """Return one row per vertex laid out per corner: the quad and the
    triangle as the port cuts them, (0, 1, 2), (0, 2, 3) and (1, 4, 2)."""
    var out = List[Float64]()
    for vertex in [0, 1, 2, 0, 2, 3, 1, 4, 2]:
        for lane in range(width):
            out.append(rows[vertex * width + lane])
    return out^


def flat(matrix: Matrix4) -> List[Float32]:
    """Return a matrix's sixteen numbers, column by column."""
    var out = List[Float32]()
    for at in range(16):
        out.append(matrix.elements[at])
    return out^


def test_skin_matches_three() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_fbx(RIG, scene, assets)
    assert_equal(model.first_skinned_mesh, 0)
    assert_equal(model.skinned_mesh_count, 1)
    assert_equal(model.mesh_count, 0)
    ref skinned = scene.skinned_meshes[0]
    ref shape = assets.geometries.get(skinned.geometry)
    # Vertex four has five weights: the four largest are kept, largest
    # first, and scaled to sum to one.
    assert_list(
        shape.attribute_view(String(SKIN_INDEX)).data,
        per_corner(
            [0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 3, 2, 4], 4
        ),
    )
    assert_list(
        shape.attribute_view(String(SKIN_WEIGHT)).data,
        per_corner(
            [
                1,
                0,
                0,
                0,
                0.5,
                0.5,
                0,
                0,
                0.5,
                0.5,
                0,
                0,
                1,
                0,
                0,
                0,
                0.333333,
                0.277778,
                0.222222,
                0.166667,
            ],
            4,
        ),
    )
    # The bind pose's matrix of the mesh model.
    assert_list(
        flat(skinned.bind_matrix),
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1],
    )
    var names: List[String] = ["Hip", "Knee", "Ankle", "Toe", "Tip"]
    var inverses: List[List[Float64]] = [
        [0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -1, 0, 0, 1],
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -1, -1, 0, 1],
        [0.5, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 0.5, 0, -1, -0.5, 0, 1],
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -3, -1, 0, 1],
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -3.5, -1, 0, 1],
    ]
    assert_equal(skinned.bone_count(), 5)
    for bone in range(5):
        assert_equal(scene.get(skinned.skeleton.node(bone)).name, names[bone])
        assert_list(
            flat(skinned.skeleton.bones[bone].inverse_bind),
            inverses[bone],
        )


def test_blend_shapes_match_three() raises:
    var scene = Scene()
    var assets = Assets()
    _ = read_fbx(RIG, scene, assets)
    ref shape = assets.geometries.get(scene.skinned_meshes[0].geometry)
    assert_true(shape.morph_relative)
    assert_equal(shape.morph_count(), 2)
    assert_list(
        shape.morph_positions[0].data,
        per_corner([0, 0, 0, 0, 0.5, 0, 0, 0, 0, 0, 0, 0, 0.25, 0, 1], 3),
    )
    assert_list(
        shape.morph_positions[1].data,
        per_corner([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -0.5, 0, 0, 0, 0], 3),
    )


def test_clips_match_three() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_fbx(RIG, scene, assets)
    assert_equal(len(model.animations), 2)
    ref walk = model.animations[0]
    assert_equal(walk.name, "Walk")
    assert_almost_equal(walk.length, 2)
    assert_equal(walk.track_count(), 4)
    # Hip's position: every time either axis has a key, z held at the
    # model's own.
    ref moved = walk.tracks[0]
    assert_true(moved.kind() == TRACK_POSITION)
    assert_equal(moved.target.index, model.model("Hip").value)
    assert_list(moved.times, [0, 0.5, 1, 2])
    assert_list(moved.values, [0, 1, 0, 0, 3, 0, 2, 3, 0, 4, 3, 0])
    # Knee's rotation, turned by its post-rotation, and a turn of 290
    # degrees cut by a slerp key, the key at the end of it dropped.
    ref turned = walk.tracks[1]
    assert_true(turned.kind() == QUATERNION)
    assert_equal(turned.target.index, model.model("Knee").value)
    assert_list(turned.times, [0, 1, 1.62069])
    assert_list(
        turned.values,
        [
            -0.061394,
            0.061394,
            0.26419,
            0.960555,
            0.640342,
            -0.066765,
            0.056023,
            0.763129,
            0.818359,
            -0.224464,
            -0.105846,
            0.518363,
        ],
    )
    assert_list(
        turned.sample(Duration(0.25, SECOND)),
        [0.128583, 0.029821, 0.223142, 0.965808],
    )
    ref grown = walk.tracks[2]
    assert_true(grown.kind() == SCALE)
    assert_equal(grown.target.index, model.model("Tip").value)
    assert_list(grown.values, [1, 1, 1, 3, 1, 1])
    # Smile's influence, on the skinned mesh.
    ref smiled = walk.tracks[3]
    assert_true(smiled.kind() == SKINNED_MORPH_INFLUENCE)
    assert_equal(smiled.target.index, 0)
    assert_equal(smiled.target.slot, 0)
    assert_list(smiled.times, [0, 0.5, 1])
    assert_list(smiled.values, [0, 0.5, 1])
    ref idle = model.animations[1]
    assert_equal(idle.name, "Idle")
    assert_list(idle.tracks[0].values, [1, 0, 0, 1.5, 0, 0])


def test_the_pose_matches_three() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_fbx(RIG, scene, assets)
    var mixer = AnimationMixer()
    var action = mixer.add(AnimationAction(model.animations[0].copy()))
    mixer.action(action).play()
    mixer.update(scene, assets, Duration(0.75, SECOND))
    scene.update()
    ref skinned = scene.skinned_meshes[0]
    assert_almost_equal(skinned.morph_influence(0), 0.75)
    ref shape = assets.geometries.get(skinned.geometry)
    var points = morphed_positions(shape, skinned.morph_influences)
    var carriers = skin_carriers(shape, skin_pose(scene, 0), len(points))
    var world = scene.world_matrix(skinned.node)
    var expected: List[Float64] = [
        1,
        3,
        0,
        1.40635,
        3.643062,
        0.156241,
        1.250267,
        3.8815,
        0.416642,
        1,
        4,
        0,
        1.545438,
        3.969749,
        1.185046,
    ]
    var placed = List[Float32]()
    for corner in range(len(points)):
        var at = world.transform_point(
            carriers[corner].transform_point(points[corner])
        )
        placed.extend([at.x, at.y, at.z])
    assert_list(placed, per_corner(expected, 3))


def test_lenient_skins_and_shapes() raises:
    # A cluster with no indices, one whose indices name no position, a
    # skin holding a model and a blend shape, a cluster holding a shape,
    # a pose that is not a bind pose, and a channel whose first child is
    # named: none of them is refused, as three.js refuses none.
    var text = swap(
        rig(),
        "Indexes: *1 {\n\t\t\ta: 4\n\t\t}\n\t\tWeights: *1 {\n\t\t\ta: 0.15",
        (
            "Indexes: *2 {\n\t\t\ta: 9,-1\n\t\t}\n\t\tWeights: *2 {\n\t\t\ta:"
            " 0.15,0.2"
        ),
    )
    text = swap(
        text,
        (
            "Indexes: *1 {\n\t\t\ta: 4\n\t\t}\n\t\tWeights: *1 {\n\t\t\ta: 0.25"
            "\n\t\t}"
        ),
        "Version: 1",
    )
    text = swap(
        text,
        '\tC: "OO",5000000000002,4000000000003\n',
        (
            '\tC: "OO",2000000000001,3000000000001\n\tC:'
            ' "OO",4000000000001,3000000000001\n\tC:'
            ' "OO",5000000000002,3000000000002\n\tC:'
            ' "OP",8000000000009,4000000000003, "Other"\n\tC:'
            ' "OO",5000000000002,4000000000003\n'
        ),
    )
    text = swap(
        text,
        "\tAnimationStack: 7000000000001",
        '\tPose: 6000000000002, "Pose::Rest", "RestPose" {\n\t}\n'
        + '\tPose: 6000000000003, "Pose::Empty", "BindPose" {\n\t}\n'
        + '\tDeformer: 4000000000004, "SubDeformer::Blink",'
        + ' "BlendShapeChannel" {\n\t}\n'
        + '\tDeformer: 4000000000005, "Deformer::None", "BlendShape" {\n\t}\n'
        + '\tAnimationCurveNode: 8000000000020, "AnimCurveNode::DeformPercent",'
        + ' "" {\n\t}\n'
        + '\tAnimationCurve: 9000000000020, "AnimCurve::", "" {\n'
        + "\t\tKeyTime: *1 {\n\t\t\ta: 0\n\t\t}\n\t\tKeyValueFloat: *1"
        + " {\n\t\t\ta: 5\n\t\t}\n\t}\n"
        + "\tAnimationStack: 7000000000001",
    )
    # A third channel whose shape is a model, which three.js leaves out
    # and whose influence curve drives nothing, and a blend shape with no
    # channel.
    text = swap(
        text,
        '\tC: "OO",7000000000002,7000000000001\n',
        '\tC: "OO",7000000000002,7000000000001\n'
        + '\tC: "OO",4000000000004,4000000000001\n'
        + '\tC: "OO",2000000000006,4000000000004\n'
        + '\tC: "OO",4000000000005,1000000000001\n'
        + '\tC: "OO",8000000000020,7000000000002\n'
        + '\tC: "OP",8000000000020,4000000000004, "DeformPercent"\n'
        + '\tC: "OP",9000000000020,8000000000020, "d|DeformPercent"\n',
    )
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(model.skinned_mesh_count, 1)
    ref shape = assets.geometries.get(scene.skinned_meshes[0].geometry)
    # Position four, the triangle's second corner, the eighth: three
    # weights left, scaled to sum to one.
    var expected: List[Float64] = [0.1 / 0.6, 0.3 / 0.6, 0.2 / 0.6, 0]
    ref weights = shape.attribute_view(String(SKIN_WEIGHT)).data
    for lane in range(4):
        assert_almost_equal(
            weights[7 * 4 + lane], Float32(expected[lane]), atol=1e-6
        )
    assert_equal(shape.morph_count(), 2)


def test_a_mesh_without_a_skin_wears_its_blend_shapes() raises:
    var text = swap(
        rig(), '"Deformer::Skin", "Skin"', '"Deformer::Skin", "Skinny"'
    )
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(model.skinned_mesh_count, 0)
    assert_equal(model.mesh_count, 1)
    assert_equal(
        assets.geometries.get(scene.meshes[0].geometry).morph_count(), 2
    )
    ref smiled = model.animations[0].tracks[3]
    assert_true(smiled.kind() == MORPH_INFLUENCE)
    assert_equal(smiled.target.index, 0)


def test_no_bind_pose_binds_at_the_identity() raises:
    var text = swap(
        rig(),
        '"Pose::BIND_POSES", "BindPose"',
        '"Pose::BIND_POSES", "RestPose"',
    )
    var scene = Scene()
    var assets = Assets()
    _ = load(text, scene, assets)
    assert_list(
        flat(scene.skinned_meshes[0].bind_matrix),
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    )


def test_refused_skins_and_shapes() raises:
    var text = rig()
    refused(
        swap(text, '\tC: "OO",3000000000001,1000000000001\n', ""),
        "a skin deforms no geometry",
    )
    var link = String("*16 {\n\t\t\ta: 1,0,0,0,0,1,0,0,0,0,1,0,1,1,0,1")
    refused(
        swap(text, "TransformLink: " + link, "Transformlink: " + link),
        "has no TransformLink",
    )
    refused(
        swap(text, link, "*15 {\n\t\t\ta: 1,0,0,0,0,1,0,0,0,0,1,0,1,1,0"),
        "needs sixteen numbers",
    )
    refused(
        swap(
            text,
            "Weights: *3 {\n\t\t\ta: 0.5,0.5,0.3",
            "Weights: *2 {\n\t\t\ta: 0.5,0.5",
        ),
        "one weight per index",
    )
    refused(
        swap(text, "Weights: *3 {", "Weightz: *3 {"), "one weight per index"
    )
    refused(
        swap(text, '\tC: "OO",2000000000006,3000000000006\n', ""),
        "a cluster has no bone",
    )
    var lone = text
    for cluster in range(2, 7):
        lone = swap(
            lone,
            '\tC: "OO",300000000000' + String(cluster) + ",3000000000001\n",
            "",
        )
    refused(lone, "A skeleton needs at least one bone")
    refused(
        swap(
            text,
            '\tC: "OO",4000000000002,4000000000001\n',
            '\tC: "OO",3000000000006,4000000000001\n',
        ),
        "not a BlendShapeChannel",
    )
    refused(
        swap(text, '\tC: "OO",5000000000002,4000000000003\n', ""),
        "has no shape",
    )
    refused(
        swap(
            text,
            "Vertices: *3 {\n\t\t\ta: 0,-0.5,0",
            "Vertices: *2 {\n\t\t\ta: 0,-0.5",
        ),
        "three numbers per index",
    )
    refused(
        swap(text, "Indexes: *1 {\n\t\t\ta: 3", "Indexes: *1 {\n\t\t\ta: 7"),
        "names a position that is not there",
    )


def test_too_many_blend_shapes_are_refused() raises:
    # Seven channels more than the rig's two: nine, and a mesh wears
    # eight.
    var objects = String()
    var links = String()
    for extra in range(7):
        var channel = String(4000000000010 + extra)
        var shape = String(5000000000010 + extra)
        objects += (
            "\tDeformer: "
            + channel
            + ', "SubDeformer::More", "BlendShapeChannel" {\n\t}\n'
            + "\tGeometry: "
            + shape
            + ', "Geometry::More", "Shape" {\n\t}\n'
        )
        links += '\tC: "OO",' + channel + ",4000000000001\n"
        links += '\tC: "OO",' + shape + "," + channel + "\n"
    var text = swap(
        rig(),
        "\tAnimationStack: 7000000000001",
        objects + "\tAnimationStack: 7000000000001",
    )
    text = swap(
        text,
        '\tC: "OO",5000000000002,4000000000003\n',
        '\tC: "OO",5000000000002,4000000000003\n' + links,
    )
    refused(text, "a mesh wears at most 8")


def test_lenient_animation() raises:
    # A curve node three.js does not read, curves it skips, a layer child
    # that is no curve node, a curve node on a cluster, one with no
    # curves, one on no transform and a rotation with one axis: the clip
    # is the same, and a stack with no track is no clip.
    var nodes = String(
        '\tAnimationCurveNode: 8000000000006, "AnimCurveNode::Visibility",'
        ' "" {\n\t}\n'
    )
    nodes += (
        '\tAnimationCurveNode: 8000000000007, "AnimCurveNode::T", "" {\n\t}\n'
    )
    nodes += (
        '\tAnimationCurveNode: 8000000000008, "AnimCurveNode::S", "" {\n\t}\n'
    )
    nodes += (
        '\tAnimationCurveNode: 8000000000010, "AnimCurveNode::Transparency",'
        ' "" {\n\t}\n'
    )
    nodes += (
        '\tAnimationCurveNode: 8000000000012, "AnimCurveNode::R", "" {\n\t}\n'
    )
    var curve = String(
        ', "AnimCurve::", "" {\n\t\tKeyTime: *1 {\n\t\t\ta: 0\n\t\t}\n'
        "\t\tKeyValueFloat: *1 {\n\t\t\ta: 5\n\t\t}\n\t}\n"
    )
    for id in range(9000000000009, 9000000000015):
        nodes += "\tAnimationCurve: " + String(id) + curve
    var text = swap(
        rig(),
        "\tAnimationStack: 7000000000003",
        nodes + "\tAnimationStack: 7000000000003",
    )
    text = swap(text, '\tC: "OO",8000000000005,7000000000004\n', "")
    var links = String('\tC: "OO",7000000000004,7000000000003\n')
    for id in [6, 7, 8, 10, 12]:
        links += '\tC: "OO",' + String(8000000000000 + id)
        links += ",7000000000002\n"
    links += '\tC: "OP",8000000000007,3000000000002, "Lcl Translation"\n'
    links += '\tC: "OP",8000000000008,2000000000005, "Lcl Scaling"\n'
    links += '\tC: "OP",8000000000010,2000000000006, "Transparency"\n'
    links += '\tC: "OP",8000000000012,2000000000002, "Lcl Rotation"\n'
    links += '\tC: "OP",9000000000009,8000000000006, "d|DeformPercent"\n'
    links += '\tC: "OP",9000000000010,8000000000001, "d|W"\n'
    links += '\tC: "OP",9000000000012,8000000000007, "d|X"\n'
    links += '\tC: "OP",9000000000013,8000000000010, "d|X"\n'
    links += '\tC: "OP",9000000000014,8000000000012, "d|X"\n'
    text = swap(text, '\tC: "OO",7000000000004,7000000000003\n', links)
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(len(model.animations), 1)
    assert_equal(model.animations[0].track_count(), 4)


def test_a_file_with_no_curves_has_no_clips() raises:
    var text = rig().replace("AnimationCurve: ", "AnimationCurvy: ")
    var scene = Scene()
    var assets = Assets()
    assert_equal(len(load(text, scene, assets).animations), 0)
    # A curve and no connections at all.
    var alone = String(
        "; FBX 7.4.0 project file\nFBXHeaderExtension:  {\n\tFBXVersion:"
        ' 7400\n}\nObjects:  {\n\tAnimationCurve: 9, "AnimCurve::", "" {\n'
        "\t\tKeyTime: *1 {\n\t\t\ta: 0\n\t\t}\n\t\tKeyValueFloat: *1"
        " {\n\t\t\ta: 0\n\t\t}\n\t}\n}\n"
    )
    assert_equal(len(load(alone, scene, assets).animations), 0)
    # And a Connections with no connection in it.
    assert_equal(
        len(load(alone + "Connections:  {\n}\n", scene, assets).animations), 0
    )


def test_refused_animation() raises:
    var text = rig()
    var visible = swap(
        text,
        '\tC: "OP",9000000000008,8000000000005, "d|X"\n',
        '\tC: "OP",9000000000008,8000000000006, "d|X"\n',
    )
    refused(
        swap(
            visible,
            "\tAnimationStack: 7000000000003",
            (
                "\tAnimationCurveNode: 8000000000006,"
                ' "AnimCurveNode::Visibility", "" {\n\t}\n\tAnimationStack:'
                " 7000000000003"
            ),
        ),
        "drives no curve node",
    )
    refused(
        swap(
            text,
            "KeyValueFloat: *2 {\n\t\t\ta: 1,1.5",
            "KeyValueFloaty: *2 {\n\t\t\ta: 1,1.5",
        ),
        "needs KeyTime and KeyValueFloat",
    )
    refused(
        swap(
            text,
            "KeyTime: *3 {\n\t\t\ta: 0,23093079000,46186158000",
            "KeyTimes: *3 {\n\t\t\ta: 0,23093079000,46186158000",
        ),
        "needs KeyTime and KeyValueFloat",
    )
    refused(
        swap(
            text,
            "KeyValueFloat: *2 {\n\t\t\ta: 1,1.5",
            "KeyValueFloat: *1 {\n\t\t\ta: 1",
        ),
        "one value per key time",
    )
    refused(
        swap(
            text,
            '\tC: "OP",8000000000003,2000000000006, "Lcl Scaling"',
            '\tC: "OO",8000000000003,2000000000006',
        ),
        "drives nothing",
    )
    refused(
        swap(
            text, '\tC: "OP",8000000000003,2000000000006, "Lcl Scaling"\n', ""
        ),
        "drives nothing",
    )
    refused(
        swap(
            text,
            "KeyTime: *3 {\n\t\t\ta: 0,23093079000,46186158000\n\t\t}\n"
            + "\t\tKeyValueFloat: *3 {\n\t\t\ta: 0,50,100\n\t\t}",
            "KeyTime: *0 {\n\t\t}\n\t\tKeyValueFloat: *0 {\n\t\t}",
        ),
        "at least one key",
    )
    refused(
        swap(text, '\tC: "OO",4000000000001,1000000000001\n', ""),
        "not connected to a model",
    )
    refused(
        swap(text, '\tC: "OO",7000000000004,7000000000003\n', ""),
        "has no layer",
    )
    refused(
        swap(
            text,
            (
                "KeyTime: *3 {\n\t\t\ta: 0,46186158000,92372316000\n\t\t}\n"
                "\t\tKeyValueFloat: *3 {\n\t\t\ta: 10,20,30\n\t\t}"
            ),
            "KeyTime: *0 {\n\t\t}\n\t\tKeyValueFloat: *0 {\n\t\t}",
        ),
        "a rotation curve has no keys",
    )


def knee_turns(text: String) raises -> List[Float32]:
    """Return the values of the Walk clip's rotation track."""
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    return model.animations[0].tracks[1].values.copy()


def test_rotation_keys_three_skips() raises:
    # A y curve with no third key: the third key is skipped.
    var short = knee_turns(
        swap(
            rig(),
            (
                "KeyTime: *3 {\n\t\t\ta: 0,46186158000,92372316000\n\t\t}\n"
                "\t\tKeyValueFloat: *3 {\n\t\t\ta: 10,20,30"
            ),
            (
                "KeyTime: *2 {\n\t\t\ta: 0,46186158000\n\t\t}\n"
                "\t\tKeyValueFloat: *2 {\n\t\t\ta: 10,20"
            ),
        )
    )
    assert_equal(len(short), 8)
    # A value that is not a number: the keys on either side of it are
    # skipped.
    var broken = knee_turns(swap(rig(), "a: 30,30,45", "a: 30,nan,45"))
    assert_equal(len(broken), 4)
    # Three turns of -170 degrees at once point the rotation away from the
    # one before, which three.js's `setFromEuler` gives a dot product of
    # -0.988 with, and the key is negated to stay beside it.
    var turned = swap(rig(), "a: 0,90,-200", "a: 0,-170,-170")
    turned = swap(turned, "a: 10,20,30", "a: 0,-170,-170")
    turned = swap(turned, "a: 30,30,45", "a: 0,-170,-170")
    var flipped = knee_turns(turned)
    assert_equal(len(flipped), 12)
    for key in range(1, 3):
        var dot = Float32(0)
        for lane in range(4):
            dot += flipped[key * 4 + lane] * flipped[key * 4 - 4 + lane]
        assert_true(dot >= 0)
    # One key on each axis: one key.
    var once = rig()
    for values in ["0,90,-200", "10,20,30", "30,30,45"]:
        once = swap(
            once,
            "KeyTime: *3 {\n\t\t\ta: 0,46186158000,92372316000\n\t\t}\n"
            + "\t\tKeyValueFloat: *3 {\n\t\t\ta: "
            + values,
            "KeyTime: *1 {\n\t\t\ta: 0\n\t\t}\n\t\tKeyValueFloat: *1"
            + " {\n\t\t\ta: "
            + String(values).split(",")[0],
        )
    assert_equal(len(knee_turns(once)), 4)


def test_edge_rigs() raises:
    # A geometry with no positions: its skin and its shapes, which give
    # neither indices nor offsets, have no rows, and the morph track has
    # no mesh to drive.
    var text = swap(rig(), "Vertices: *15", "Verticez: *15")
    text = swap(text, "PolygonVertexIndex", "PolygonVertexIndez")
    text = swap(
        text, "Indexes: *2 {\n\t\t\ta: 1,4", "Indexez: *2 {\n\t\t\ta: 1,4"
    )
    text = swap(text, "Vertices: *6", "Verticez: *6")
    text = swap(text, "Indexes: *1 {\n\t\t\ta: 3", "Indexez: *1 {\n\t\t\ta: 3")
    text = swap(
        text,
        "Vertices: *3 {\n\t\t\ta: 0,-0.5",
        "Verticez: *3 {\n\t\t\ta: 0,-0.5",
    )
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(model.skinned_mesh_count, 0)
    assert_equal(model.mesh_count, 0)
    assert_equal(model.animations[0].track_count(), 3)
    # A blend shape whose channels are gone, and no influence curve.
    var bare = swap(rig(), '\tC: "OO",4000000000002,4000000000001\n', "")
    bare = swap(bare, '\tC: "OO",4000000000003,4000000000001\n', "")
    bare = swap(bare, '\tC: "OO",8000000000004,7000000000002\n', "")
    var other = Scene()
    _ = load(bare, other, assets)
    assert_equal(
        assets.geometries.get(other.skinned_meshes[0].geometry).morph_count(),
        0,
    )
    # A y curve with no keys: the x curve's keys, y held.
    var empty = swap(
        rig(),
        "\tAnimationStack: 7000000000003",
        '\tAnimationCurve: 9000000000030, "AnimCurve::", "" {\n'
        + "\t\tKeyTime: *0 {\n\t\t}\n\t\tKeyValueFloat: *0 {\n\t\t}\n\t}\n"
        + "\tAnimationStack: 7000000000003",
    )
    empty = swap(
        empty,
        '\tC: "OP",9000000000008,8000000000005, "d|X"\n',
        '\tC: "OP",9000000000008,8000000000005, "d|X"\n'
        + '\tC: "OP",9000000000030,8000000000005, "d|Y"\n',
    )
    var third = Scene()
    var held = load(empty, third, assets)
    assert_list(held.animations[1].tracks[0].values, [1, 0, 0, 1.5, 0, 0])
    # Two material indices: two meshes, and a morph track on each.
    var split = swap(
        rig(), '"Deformer::Skin", "Skin"', '"Deformer::Skin", "Skinny"'
    )
    split = swap(
        split,
        "\t\t\t\ta: 0,0,1,0,0,1,0,0,1,0,0,1,0,0,1\n\t\t\t}\n\t\t}\n",
        "\t\t\t\ta: 0,0,1,0,0,1,0,0,1,0,0,1,0,0,1\n\t\t\t}\n\t\t}\n"
        + "\t\tLayerElementMaterial: 0 {\n\t\t\tMappingInformationType:"
        + ' "ByPolygon"\n\t\t\tReferenceInformationType: "IndexToDirect"\n'
        + "\t\t\tMaterials: *2 {\n\t\t\t\ta: 0,1\n\t\t\t}\n\t\t}\n",
    )
    var fourth = Scene()
    var two = load(split, fourth, assets)
    assert_equal(two.mesh_count, 2)
    assert_equal(two.animations[0].track_count(), 5)


def test_js_key_order() raises:
    var order = js_key_order([5, 9000000000, 3, -1, 4294967294, 4294967295])
    var expected: List[Int] = [2, 0, 4, 1, 3, 5]
    assert_equal(len(order), 6)
    for at in range(6):
        assert_equal(order[at], expected[at])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
