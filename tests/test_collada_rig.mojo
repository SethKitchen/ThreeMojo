# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the skins of `loaders.collada` and for
`loaders.collada_animation`.

`assets/collada/rig.dae` is a mesh of a quad and a triangle skinned to a
chain of `JOINT` nodes, with a joint the controller does not name, three
animations and two clips. The expected numbers were printed by running
the file through three.js r180's `ColladaLoader.parse` and
`AnimationMixer` in Node.
"""

from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.keyframe_track import (
    POSITION as TRACK_POSITION,
    QUATERNION,
    SCALE,
)
from core.assets import Assets
from core.deform import morphed_positions, skin_carriers, skin_pose
from core.object3d import NodeId
from core.scene import Scene
from loaders.collada import ColladaModel, load_collada, read_collada
from math.matrix4 import Matrix4
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration

comptime RIG = "assets/collada/rig.dae"


def rig() raises -> String:
    """Return the text of the rig."""
    return Path(RIG).read_text()


def swap(text: String, old: String, new: String) raises -> String:
    """Return the text with one piece replaced, which must be there."""
    if text.find(old) < 0:
        raise Error("the fixture has no " + old)
    return text.replace(old, new)


def load(
    text: String, mut scene: Scene, mut assets: Assets
) raises -> ColladaModel:
    """Read a Collada text."""
    return load_collada(text, "", scene, assets)


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
    """Return one row per vertex laid out per corner: the quad cut into
    (0, 1, 3) and (1, 2, 3), and the triangle (1, 4, 2), as three.js cuts
    them."""
    var out = List[Float64]()
    for vertex in [0, 1, 3, 1, 2, 3, 1, 4, 2]:
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
    var model = read_collada(RIG, scene, assets)
    assert_equal(model.skinned_mesh_count, 1)
    assert_equal(model.mesh_count, 0)
    ref skinned = scene.skinned_meshes[0]
    ref shape = assets.geometries.get(skinned.geometry)
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
                0.6,
                0.4,
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
    assert_list(
        flat(skinned.bind_matrix),
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0.5, 0, 1],
    )
    # The controller's joints in its order, then the joint it does not
    # name, at the identity.
    var names: List[String] = ["Hip", "Knee", "Root", "Toe", "Tip", "Spare"]
    var shifts: List[List[Float64]] = [
        [1, 0, -1],
        [1, -1, -1],
        [1, 0, 0],
        [0.5, -1, -0.5],
        [1, -3, -1],
        [1, 0, 0],
    ]
    assert_equal(skinned.bone_count(), 6)
    for bone in range(6):
        assert_equal(scene.get(skinned.skeleton.node(bone)).name, names[bone])
        var s = shifts[bone][0]
        var x = shifts[bone][1]
        var y = shifts[bone][2]
        assert_list(
            flat(skinned.skeleton.bones[bone].inverse_bind),
            [s, 0, 0, 0, 0, s, 0, 0, 0, 0, s, 0, x, y, 0, 1],
        )


def test_clips_match_three() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_collada(RIG, scene, assets)
    # `Spin` drives a `<rotate>`, which makes no track, so it is no clip.
    assert_equal(len(model.animations), 1)
    ref wave = model.animations[0]
    assert_equal(wave.name, "Wave")
    assert_almost_equal(wave.length, 2.5)
    assert_equal(wave.track_count(), 6)
    var knee = model.nodes[3].value
    var root = model.nodes[1].value
    assert_equal(scene.get(model.nodes[3]).name, "Knee")
    assert_equal(scene.get(model.nodes[1]).name, "Root")
    assert_true(wave.tracks[0].kind() == TRACK_POSITION)
    assert_equal(wave.tracks[0].target.index, knee)
    assert_list(wave.tracks[0].times, [0, 1, 2])
    assert_list(wave.tracks[0].values, [1, 0, 0, 1, 0, 0, 1, 0, 0.5])
    assert_true(wave.tracks[1].kind() == QUATERNION)
    assert_list(
        wave.tracks[1].values,
        [0, 0, 0, 1, 0, 0, 0.707107, 0.707107, 0, 0, 0, 1],
    )
    assert_true(wave.tracks[2].kind() == SCALE)
    assert_list(wave.tracks[2].values, [1, 1, 1, 1, 1, 1, 2, 2, 2])
    # One entry of Root's matrix, its y translation; the rest its own.
    assert_equal(wave.tracks[3].target.index, root)
    assert_list(wave.tracks[3].times, [0.5, 1.5])
    assert_list(wave.tracks[3].values, [0, 2, 0, 0, 3, 0])
    assert_list(wave.tracks[4].values, [0, 0, 0, 1, 0, 0, 0, 1])
    assert_list(wave.tracks[5].values, [1, 1, 1, 1, 1, 1])


def test_the_pose_matches_three() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_collada(RIG, scene, assets)
    var mixer = AnimationMixer()
    var action = mixer.add(AnimationAction(model.animations[0].copy()))
    mixer.action(action).play()
    mixer.update(scene, assets, Duration(0.75, SECOND))
    scene.update()
    ref skinned = scene.skinned_meshes[0]
    ref shape = assets.geometries.get(skinned.geometry)
    var points = morphed_positions(shape, skinned.morph_influences)
    var carriers = skin_carriers(shape, skin_pose(scene, 0), len(points))
    var world = scene.world_matrix(skinned.node)
    var placed = List[Float32]()
    for corner in range(len(points)):
        var at = world.transform_point(
            carriers[corner].transform_point(points[corner])
        )
        placed.extend([at.x, at.y, at.z])
    assert_list(
        placed,
        per_corner(
            [
                0,
                1.75,
                0,
                1.23097,
                1.904329,
                0,
                0.815224,
                2.626537,
                0,
                0,
                2.75,
                0,
                1.519865,
                3.190795,
                0,
            ],
            3,
        ),
    )


def test_lenient_skins() raises:
    # A second instance of the controller, a line in the skinned
    # geometry, a controller with no id, no bind shape matrix, a joint
    # that is one object alone, a node under the skeleton that is no
    # joint, a skeleton of the visual scene, and bones in copies of a
    # library node: none is refused.
    var text = swap(
        rig(),
        (
            "<bind_shape_matrix>1 0 0 0 0 1 0 0.5 0 0 1 0 0 0 0"
            " 1</bind_shape_matrix>"
        ),
        "",
    )
    text = swap(
        text,
        "</polylist>",
        (
            '</polylist><lines count="1"><input semantic="VERTEX"'
            ' source="#Blob-vertices" offset="0"/><p>0 1</p></lines>'
        ),
    )
    text = swap(
        text,
        "</library_controllers>",
        '<controller name="Nameless"/></library_controllers>'
        + '<library_nodes><node id="Lib" sid="Lib" type="JOINT"/>'
        + "</library_nodes>",
    )
    text = swap(
        text,
        '<node id="Armature" name="Armature" type="NODE">',
        '<node id="Armature" name="Armature" sid="Arm" type="JOINT">',
    )
    text = swap(
        text,
        '<translate sid="location">0 0 1</translate>',
        '<translate sid="location">0 0 1</translate><node id="Leaf"'
        ' sid="Leaf" type="JOINT"><instance_node url="#Lib"/>'
        + '</node><node id="Plain" type="NODE"/>',
    )
    text = swap(
        text, "<skeleton>#Root-node</skeleton>", "<skeleton>#Scene</skeleton>"
    )
    text = swap(
        text,
        "</visual_scene>",
        '<node id="Again"><instance_controller url="#Blob-skin">'
        + "<skeleton>#Root-node</skeleton><bind_material><technique_common>"
        + '<instance_material symbol="unused" target="#nothing"/>'
        + "</technique_common></bind_material></instance_controller>"
        + '<instance_node url="#Lib"/><instance_node url="#Lib"/></node>'
        + '<node id="Hollow"><instance_controller url="#Hollow-a">'
        + "<skeleton>#Root-node</skeleton></instance_controller>"
        + '<instance_controller url="#Hollow-b">'
        + "<skeleton>#Root-node</skeleton></instance_controller></node>"
        + "</visual_scene>",
    )
    # Two skins of a geometry with no primitive: one of no joint, a vertex
    # of no weight and no `<v>`, one with no `<vcount>`, and sources
    # with no array, no technique or no accessor.
    var hollow = String(
        '<source id="H-j"><Name_array></Name_array></source>'
        + '<source id="H-b"><technique_common/></source>'
        + '<source id="H-w"/>'
        + '<joints><input semantic="JOINT" source="#H-j"/>'
        + '<input semantic="INV_BIND_MATRIX" source="#H-b"/></joints>'
    )
    var inputs = String(
        '<input semantic="JOINT" source="#H-j" offset="0"/>'
        + '<input semantic="WEIGHT" source="#H-w" offset="1"/>'
    )
    text = swap(
        text,
        "</library_controllers>",
        '<controller id="Hollow-a"><skin source="#Hollow-mesh">'
        + hollow
        + "<vertex_weights>"
        + inputs
        + "<vcount>0</vcount></vertex_weights></skin></controller>"
        + '<controller id="Hollow-b"><skin source="#Hollow-mesh">'
        + hollow
        + "<vertex_weights>"
        + inputs
        + "<v></v></vertex_weights></skin></controller>"
        + "</library_controllers>",
    )
    text = swap(
        text,
        "</library_geometries>",
        '<geometry id="Hollow-mesh"><mesh/></geometry></library_geometries>',
    )
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(model.skinned_mesh_count, 2)
    # The line of each skinned instance.
    assert_equal(model.line_count, 2)
    ref first = scene.skinned_meshes[0]
    ref second = scene.skinned_meshes[1]
    # One skinned geometry for the controller, drawn twice.
    assert_equal(first.geometry.value, second.geometry.value)
    assert_list(
        flat(first.bind_matrix),
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    )
    # Arm, from the visual scene, follows the named joints; Leaf and
    # Plain are no bones.
    assert_equal(first.bone_count(), 7)
    assert_equal(second.bone_count(), 6)


def test_refused_skins() raises:
    var text = rig()
    refused(
        swap(
            text,
            'instance_controller url="#Blob-skin"',
            'instance_controller url="#Nope"',
        ),
        "names nothing",
    )
    var others = swap(
        text,
        "</library_controllers>",
        '<controller id="M"><morph source="#Blob-mesh"/></controller>'
        + '<controller id="E"/></library_controllers>',
    )
    refused(
        swap(
            others,
            'instance_controller url="#Blob-skin"',
            'instance_controller url="#M"',
        ),
        "a morph controller is not read",
    )
    refused(
        swap(
            others,
            'instance_controller url="#Blob-skin"',
            'instance_controller url="#E"',
        ),
        "has no <skin>",
    )
    refused(
        swap(swap(text, "<joints>", "<jointz>"), "</joints>", "</jointz>"),
        "needs <joints>",
    )
    refused(
        swap(
            swap(text, "<vertex_weights", "<vertex_weightz"),
            "</vertex_weights>",
            "</vertex_weightz>",
        ),
        "needs <vertex_weights>",
    )
    refused(
        swap(text, 'semantic="INV_BIND_MATRIX"', 'semantic="INV"'),
        "needs INV_BIND_MATRIX",
    )
    refused(
        swap(
            text,
            'semantic="WEIGHT" source="#Blob-weights"',
            'semantic="W" source="#Blob-weights"',
        ),
        "needs WEIGHT",
    )
    refused(
        swap(
            text,
            '<input semantic="JOINT" source="#Blob-joints"/>',
            '<input semantic="JOINT" source="#Nope"/>',
        ),
        "names no source",
    )
    refused(
        swap(
            text,
            'source="#Blob-weights" offset="1"',
            'source="#Blob-weights" offset="1 2"',
        ),
        "needs one offset",
    )
    refused(
        swap(
            swap(text, "<Name_array", "<IDREF_array"),
            "</Name_array>",
            "</IDREF_array>",
        ),
        "must be a Name_array",
    )
    refused(
        swap(
            text,
            'source="#Blob-bind-array" count="5" stride="16"',
            'source="#Blob-bind-array" count="5" stride="17"',
        ),
        "no inverse bind matrix",
    )
    refused(
        swap(
            text,
            'source="#Blob-bind-array" count="5" stride="16"',
            'source="#Blob-bind-array" count="5" stride="0"',
        ),
        "stride must be positive",
    )
    refused(
        swap(text, "<vcount>1 2 2 1 5</vcount>", "<vcount>1 2 2 1 6</vcount>"),
        "shorter than <vcount>",
    )
    refused(swap(text, "<v>0 0 0 1", "<v>9 0 0 1"), "outside the joints")
    refused(swap(text, "<v>0 0 0 1", "<v>-1 0 0 1"), "outside the joints")
    refused(swap(text, "<v>0 0 0 1", "<v>0 9 0 1"), "outside the weights")
    refused(
        swap(text, "<vcount>1 2 2 1 5</vcount>", "<vcount>1 2 2 1</vcount>"),
        "has no skin weights",
    )
    refused(
        swap(
            text,
            "<skeleton>#Root-node</skeleton>",
            "<skeleton>#Nope</skeleton>",
        ),
        "names no node",
    )
    refused(
        swap(text, "<skeleton>#Root-node</skeleton>", ""),
        "a joint names no bone",
    )
    var jointless = swap(text, "Hip Knee Root Toe Tip", "")
    jointless = swap(jointless, "<vcount>1 2 2 1 5</vcount>", "")
    refused(
        swap(jointless, "<skeleton>#Root-node</skeleton>", ""),
        "A skeleton needs at least one bone",
    )
    refused(
        swap(
            swap(
                text,
                "<skeleton>#Root-node</skeleton>",
                "<skeleton>#Void</skeleton>",
            ),
            "</library_visual_scenes>",
            '<visual_scene id="Void"/></library_visual_scenes>',
        ),
        "a joint names no bone",
    )
    refused(
        swap(
            text,
            '<input semantic="JOINT" source="#Blob-joints"/>\n'
            + '          <input semantic="INV_BIND_MATRIX"'
            ' source="#Blob-bind"/>',
            "",
        ),
        "<joints> needs JOINT",
    )
    refused(
        swap(
            text,
            '<skin source="#Blob-mesh">',
            '<skin source="#Blob-mesh"><joints><input semantic="JOINT"'
            + ' source="#x"/><input semantic="INV_BIND_MATRIX" source="#x"/>'
            + '</joints><vertex_weights><input semantic="JOINT" source="#x"'
            + ' offset="0"/><input semantic="WEIGHT" source="#x" offset="1"/>'
            + '</vertex_weights></skin></controller><controller id="No">'
            + '<skin source="#Blob-mesh">',
        )
        .replace('url="#Blob-skin"', 'url="#Blob-skin2"')
        .replace(
            '<controller id="Blob-skin" name="Blob-skin">',
            '<controller id="Blob-skin2">',
        ),
        "names no source",
    )
    refused(
        swap(text, "Hip Knee Root Toe Tip", "Hip Knee Root Toe Nope"),
        "a joint names no bone",
    )
    refused(
        swap(
            swap(
                text,
                "</library_controllers>",
                (
                    '</library_controllers><library_nodes><node id="Lib"'
                    ' sid="Hip" type="JOINT"/></library_nodes>'
                ),
            ),
            "<skeleton>#Root-node</skeleton>",
            "<skeleton>#Lib</skeleton><skeleton>#Root-node</skeleton>",
        ),
        "a bone is not in the scene",
    )


def test_a_file_with_no_clips_plays_every_animation() raises:
    var start = rig().find("<library_animation_clips>")
    var end = rig().find("</library_animation_clips>")
    var text = String(rig()[byte=0:start]) + String(
        rig()[byte = end + String("</library_animation_clips>").byte_length() :]
    )
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(len(model.animations), 1)
    assert_equal(model.animations[0].name, "default")
    assert_equal(model.animations[0].track_count(), 6)
    # And none at all when no animation makes a track.
    start = text.find("<library_animations>")
    end = text.find("</library_animations>")
    var none = (
        String(text[byte=0:start])
        + "<library_animations/>"
        + String(
            text[byte = end + String("</library_animations>").byte_length() :]
        )
    )
    var bare = Scene()
    assert_equal(len(load(none, bare, assets).animations), 0)


def test_lenient_animations() raises:
    # A clip with no id and no start or end, a channel on a node the
    # scene does not reach, a channel replaced by a later one of its
    # target, one on a step no transform has, a member of the matrix, and
    # keys out of order with values missing.
    var text = swap(
        rig(),
        '<animation_clip id="Wave" start="0" end="2.5">',
        "<animation_clip>",
    )
    text = swap(
        text,
        '<channel source="#Knee-sampler" target="Knee-node/transform"/>',
        '<channel source="#Knee-sampler" target="Lib/transform"/>'
        + '<channel source="#Knee-sampler" target="Knee-node/transform"/>'
        + '<channel source="#Knee-sampler" target="Knee-node/nothing"/>'
        + '<channel source="#Knee-sampler" target="Knee-node/transform"/>',
    )
    text = swap(
        text,
        '<channel source="#Root-sampler" target="Root-node/transform(3)(1)"/>',
        '<channel source="#Root-sampler" target="Root-node/transform(3)(1)"/>'
        + '<channel source="#Root-sampler" target="Knee-node/transform.M"/>',
    )
    text = swap(
        text,
        "</library_controllers>",
        '</library_controllers><library_nodes><node id="Lib"><matrix'
        ' sid="transform">1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix></node>'
        + "</library_nodes>",
    )
    # Knee's keys at 0, 3, 1, 2 and 2 again, the last three left out:
    # filled between the keys at 0 and 3. Toe's keys at 0 and 1, the
    # second left out: held from the first. Root's keys at 1.5 and 0.5,
    # the second left out: taken from the one after it.
    text = swap(
        text,
        '<float_array id="Knee-input-array" count="3">0 1 2</float_array>',
        '<float_array id="Knee-input-array" count="5">0 3 1 2 2</float_array>',
    )
    text = swap(
        text,
        " 2 0 0 1 0 2 0 0 0 0 2 0.5 0 0 0 1</float_array>",
        "</float_array>",
    )
    text = swap(
        text, 'count="2">0 45</float_array>', 'count="1">0.25</float_array>'
    )
    text = swap(
        text,
        '<float_array id="Root-input-array" count="2">0.5 1.5</float_array>',
        '<float_array id="Root-input-array" count="2">1.5 0.5</float_array>',
    )
    text = swap(
        text, 'count="2">2 3</float_array>', 'count="1">2</float_array>'
    )
    text = swap(
        text,
        '<channel source="#Tip-sampler" target="Tip-node/spin.ANGLE"/>',
        '<channel source="#Tip-sampler" target="Tip-node/spin.ANGLE"/>'
        + '<channel source="#Tip-sampler" target="Toe-node/transform"/>'
        + '<channel source="#Tip-sampler" target="Bare/transform"/>',
    )
    # An animation of no keys, from sources of no array and no technique,
    # and an animation of nothing.
    text = swap(
        text,
        "</library_animations>",
        '<animation id="Empty-anim"><source id="E-in"/><source id="E-out">'
        + '<float_array count="0"></float_array><technique_common/></source>'
        + '<sampler id="E"><input semantic="INPUT" source="#E-in"/>'
        + '<input semantic="OUTPUT" source="#E-out"/></sampler>'
        + '<channel source="#E" target="Toe-node/transform"/><extra/>'
        + '</animation><animation id="Hollow-anim"/></library_animations>',
    )
    text = swap(
        text,
        '<animation_clip id="Spin" start="0" end="1">',
        '<animation_clip id="Spin" start="1" end="0">'
        + '<instance_animation url="#Empty-anim"/>'
        + '<instance_animation url="#Hollow-anim"/>',
    )
    text = swap(
        text,
        "</library_animation_clips>",
        '<animation_clip id="Nothing"/></library_animation_clips>',
    )
    text = swap(text, "</visual_scene>", '<node id="Bare"/></visual_scene>')
    var scene = Scene()
    var assets = Assets()
    var model = load(text, scene, assets)
    assert_equal(len(model.animations), 2)
    ref wave = model.animations[0]
    assert_equal(wave.name, "default")
    # Knee's set, Root's set and Knee's member set.
    assert_equal(wave.track_count(), 9)
    assert_almost_equal(wave.length, 3)
    assert_list(wave.tracks[0].times, [0, 1, 2, 3])
    assert_list(wave.tracks[0].values, [1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0])
    # A third and two thirds of the way from no turn to a quarter turn,
    # entry by entry.
    assert_list(
        wave.tracks[2].values,
        [1, 1, 1, 0.745356, 0.745356, 1, 0.745356, 0.745356, 1, 1, 1, 1],
    )
    assert_list(wave.tracks[3].times, [0.5, 1.5])
    assert_list(wave.tracks[3].values, [0, 2, 0, 0, 2, 0])
    ref spin = model.animations[1]
    assert_equal(spin.name, "Spin")
    assert_almost_equal(spin.length, 1)
    # Toe's keys at 0 and 1, both a quarter wide along x.
    assert_equal(spin.track_count(), 3)
    assert_list(spin.tracks[0].times, [0, 1])
    assert_list(spin.tracks[2].values, [0.25, 0.5, 0.5, 0.25, 0.5, 0.5])


def test_refused_animations() raises:
    var text = rig()
    refused(
        swap(
            text,
            '<instance_animation url="#Knee-anim"/>',
            '<instance_animation url="Knee-anim"/>',
        ),
        "must be #id",
    )
    var start = text.find("<library_animations>")
    var end = text.find("</library_animations>")
    refused(
        String(text[byte=0:start])
        + "<library_animations/>"
        + String(
            text[byte = end + String("</library_animations>").byte_length() :]
        ),
        "names no animation",
    )
    refused(
        swap(
            text,
            '<input semantic="INPUT" source="#Knee-input"/>\n'
            + '        <input semantic="OUTPUT" source="#Knee-output"/>\n'
            + '        <input semantic="INTERPOLATION" source="#Knee-input"/>',
            "",
        ),
        "names no source",
    )
    refused(
        swap(
            text,
            '<instance_animation url="#Knee-anim"/>',
            '<instance_animation url="#Nope"/>',
        ),
        "names no animation",
    )
    refused(
        swap(
            text,
            '<instance_animation url="#Knee-anim"/>',
            '<instance_animation url="#"/>',
        ),
        "names no animation",
    )
    refused(
        swap(text, 'channel source="#Knee-sampler"', 'channel source="#Nope"'),
        "names no sampler",
    )
    refused(
        swap(
            text,
            '<input semantic="OUTPUT" source="#Knee-output"/>',
            '<input semantic="OUTPUT" source="#Nope"/>',
        ),
        "names no source",
    )
    refused(
        swap(text, 'target="Knee-node/transform"', 'target="Knee-node"'),
        "has no sid",
    )
    refused(
        swap(text, "Root-node/transform(3)(1)", "Root-node/transform(3)"),
        "needs two indices",
    )
    refused(
        swap(text, "Root-node/transform(3)(1)", "Root-node/transform(3)(5)"),
        "outside the matrix",
    )
    refused(
        swap(text, "Root-node/transform(3)(1)", "Root-node/transform(-1)(0)"),
        "outside the matrix",
    )
    refused(
        swap(text, 'target="Knee-node/transform"', 'target="Nope/transform"'),
        "names no node",
    )
    refused(
        swap(text, 'count="48">1 0 0 1', 'count="48">0 0 0 1'),
        "no extent",
    )
    refused(
        swap(
            text,
            'source="#Knee-output-array" count="3" stride="16"',
            'source="#Knee-output-array" count="3" stride="0"',
        ),
        "stride must be positive",
    )
    refused(
        swap(
            text,
            'source="#Knee-output-array" count="3" stride="16"',
            'source="#Knee-output-array" count="3" stride="a"',
        ),
        "not a whole number",
    )
    refused(
        swap(text, 'count="48">1 0 0 1', 'count="48">x 0 0 1'),
        "not a number",
    )
    refused(
        swap(text, 'count="48">1 0 0 1', 'count="48">1e99 0 0 1'),
        "must be finite",
    )
    refused(
        swap(text, 'start="0" end="2.5"', 'start="x" end="2.5"'),
        "not a number",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
