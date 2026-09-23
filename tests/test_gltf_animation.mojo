# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the parts of `loaders.gltf` beyond static meshes: skins,
morph targets and weights, cameras, animations and sparse accessors.

Every document is built here by hand. A `Bin` packs the numbers into one
buffer, gives each run of numbers its own buffer view and accessor, and
writes the buffer as a base64 data URI.
"""

from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.keyframe_track import (
    CUBIC_SPLINE,
    LINEAR,
    MORPH_INFLUENCE,
    POSITION as TRANSLATION,
    QUATERNION,
    SCALE,
    STEP,
)
from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import directional_light
from loaders.gltf import (
    GLTF_ORTHOGRAPHIC,
    GLTF_PERSPECTIVE,
    GltfCameraKind,
    GltfModel,
    load_gltf,
)
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.math import pi
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import DEGREE, METER, RADIAN, SECOND, Duration

comptime TOLERANCE = Float64(1e-5)
comptime ALPHABET = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
)
comptime FLOAT = 5126
comptime UBYTE = 5121
comptime USHORT = 5123
comptime UINT = 5125
comptime BYTE = 5120


# --- building documents -----------------------------------------------------


def encode_base64(bytes: List[UInt8]) -> String:
    """Return the standard, padded base64 text of some bytes."""
    var table = String(ALPHABET).as_bytes()
    var out = List[UInt8]()
    var at = 0
    while at < len(bytes):
        var left = len(bytes) - at
        var n = Int(bytes[at]) << 16
        if left > 1:
            n |= Int(bytes[at + 1]) << 8
        if left > 2:
            n |= Int(bytes[at + 2])
        out.append(table[(n >> 18) & 63])
        out.append(table[(n >> 12) & 63])
        out.append(table[(n >> 6) & 63] if left > 1 else UInt8(61))
        out.append(table[n & 63] if left > 2 else UInt8(61))
        at += 3
    return String(unsafe_from_utf8=out)


def width_of(kind: String) -> Int:
    """Return how many numbers an accessor type holds."""
    if kind == "VEC2":
        return 2
    if kind == "VEC3":
        return 3
    if kind == "VEC4":
        return 4
    if kind == "MAT4":
        return 16
    return 1


def size_of(component: Int) -> Int:
    """Return how many bytes a component takes."""
    if component == UBYTE or component == BYTE:
        return 1
    if component == USHORT:
        return 2
    return 4


def doc(body: String) -> String:
    """Return a glTF 2 document around `body`."""
    return '{"asset":{"version":"2.0"}' + body + "}"


struct Bin(Movable):
    """One buffer, built a run of numbers at a time, each run its own view
    and accessor."""

    var bytes: List[UInt8]
    var views: String
    var accessors: String
    var view_count: Int
    var accessor_count: Int

    def __init__(out self):
        """Start empty."""
        self.bytes = List[UInt8]()
        self.views = String()
        self.accessors = String()
        self.view_count = 0
        self.accessor_count = 0

    def view(mut self, data: List[UInt8]) -> Int:
        """Add bytes as a buffer view of their own and return its index."""
        var offset = len(self.bytes)
        for index in range(len(data)):
            self.bytes.append(data[index])
        while len(self.bytes) % 4 != 0:
            self.bytes.append(0)
        if self.view_count > 0:
            self.views += ","
        self.views += (
            '{"buffer":0,"byteOffset":'
            + String(offset)
            + ',"byteLength":'
            + String(len(data))
            + "}"
        )
        self.view_count += 1
        return self.view_count - 1

    def accessor(mut self, json: String) -> Int:
        """Add an accessor written out and return its index."""
        if self.accessor_count > 0:
            self.accessors += ","
        self.accessors += json
        self.accessor_count += 1
        return self.accessor_count - 1

    def floats(
        mut self, values: List[Float32], kind: String, extra: String = ""
    ) -> Int:
        """Add floats as an accessor of `kind` and return its index."""
        var view = self.view(float_bytes(values))
        return self.accessor(
            '{"bufferView":'
            + String(view)
            + ',"componentType":5126,"count":'
            + String(len(values) // width_of(kind))
            + ',"type":"'
            + kind
            + '"'
            + extra
            + "}"
        )

    def ints(
        mut self,
        values: List[Int],
        component: Int,
        kind: String,
        extra: String = "",
    ) -> Int:
        """Add whole numbers as an accessor of `kind` and return its
        index."""
        var view = self.view(int_bytes(values, size_of(component)))
        return self.accessor(
            '{"bufferView":'
            + String(view)
            + ',"componentType":'
            + String(component)
            + ',"count":'
            + String(len(values) // width_of(kind))
            + ',"type":"'
            + kind
            + '"'
            + extra
            + "}"
        )

    def document(self, body: String) -> String:
        """Return the document: this buffer, its views and accessors, and
        `body` after them."""
        return doc(
            ',"buffers":[{"byteLength":'
            + String(len(self.bytes))
            + ',"uri":"data:application/octet-stream;base64,'
            + encode_base64(self.bytes)
            + '"}],"bufferViews":['
            + self.views
            + '],"accessors":['
            + self.accessors
            + "]"
            + body
        )


def float_bytes(values: List[Float32]) -> List[UInt8]:
    """Return floats as little-endian bytes."""
    var out = List[UInt8]()
    for index in range(len(values)):
        var bits = Int(bitcast[DType.uint32](values[index]))
        for shift in range(4):
            out.append(UInt8((bits >> (shift * 8)) & 0xFF))
    return out^


def int_bytes(values: List[Int], size: Int) -> List[UInt8]:
    """Return whole numbers as little-endian bytes of `size` each."""
    var out = List[UInt8]()
    for index in range(len(values)):
        for shift in range(size):
            out.append(UInt8((values[index] >> (shift * 8)) & 0xFF))
    return out^


def triangle() -> List[Float32]:
    """Return a triangle's three corners, facing +z."""
    return [0, 0, 0, 1, 0, 0, 0, 1, 0]


def identity() -> List[Float32]:
    """Return the identity as sixteen numbers."""
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def loaded(
    text: String, mut scene: Scene, mut assets: Assets
) raises -> GltfModel:
    """Load an inline document with no binary chunk."""
    return load_gltf(text, List[UInt8](), "", scene, assets)


def refused(text: String) raises -> String:
    """Return the message an inline document is refused with."""
    var scene = Scene()
    var assets = Assets()
    try:
        _ = loaded(text, scene, assets)
    except reason:
        return String(reason)
    raise Error("the document was accepted")


def refuses(text: String, expected: String) raises:
    """Assert that a document is refused with a message holding
    `expected`."""
    var reason = refused(text)
    assert_true(expected in reason, reason)


# --- skins ------------------------------------------------------------------


def rig(mut bin: Bin, skin: String, extra: String = "") -> String:
    """Return a skinned triangle's document: a root holding a bone, the
    skinned mesh, and a camera looking at it, with `skin` as the skins and
    `extra` after the attributes."""
    _ = bin.floats(triangle(), "VEC3")
    _ = bin.ints([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], UBYTE, "VEC4")
    _ = bin.floats([2, 0, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0, 0], "VEC4")
    _ = bin.floats(identity(), "MAT4")
    return bin.document(
        ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"JOINTS_0":1,"WEIGHTS_0":2'
        + extra
        + '}}]}],"skins":'
        + skin
        + ',"cameras":[{"type":"perspective","name":"Eye","perspective":{"yfov":1.0,"aspectRatio":1,"znear":0.1,"zfar":10}}]'
        + ',"nodes":[{"name":"Root","children":[1,2,3]},{"name":"Bone"},{"mesh":0,"skin":0},{"camera":0,"translation":[0.3,0.3,2]}]'
        + ',"scenes":[{"nodes":[0]}]'
    )


def lit_pixels(
    mut scene: Scene, assets: Assets, model: GltfModel
) raises -> Int:
    """Render the scene through the file's camera and count the lit
    pixels."""
    scene.update()
    var renderer = Renderer(24, 24)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, model.cameras[0].perspective())
    var drawn = 0
    for y in range(24):
        for x in range(24):
            if image.get_pixel(x, y).r > 0:
                drawn += 1
    return drawn


def test_a_skinned_triangle_follows_its_bone() raises:
    var bin = Bin()
    var text = rig(bin, '[{"joints":[1],"inverseBindMatrices":3}]')
    var scene = Scene()
    var assets = Assets()
    var lamp = Object3D()
    lamp.set_position(0, 0, 5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    var model = loaded(text, scene, assets)
    assert_equal(model.mesh_count, 0)
    assert_equal(model.skinned_mesh_count, 1)
    assert_equal(model.first_skinned_mesh, 0)
    ref skinned = scene.skinned_meshes[0]
    assert_equal(skinned.bone_count(), 1)
    assert_equal(skinned.skeleton.node(0), model.nodes[1])
    assert_equal(skinned.node, model.nodes[2])
    assert_equal(skinned.skeleton.bones[0].inverse_bind.elements[0], 1)
    assert_equal(skinned.skeleton.bones[0].inverse_bind.elements[1], 0)
    # The node takes the file's name, as three.js's does.
    assert_equal(scene.get(model.nodes[1]).name, "Bone")
    # The weights are normalized: two alone becomes one, and none at all
    # goes to the first bone.
    ref geometry = assets.geometries.get(skinned.geometry)
    ref weights = geometry.attribute_view(String(SKIN_WEIGHT))
    assert_equal(weights.data[0], 1)
    assert_equal(weights.data[4], 1)
    assert_equal(weights.data[8], 0.5)
    assert_equal(weights.data[9], 0.5)
    assert_equal(geometry.attribute_view(String(SKIN_INDEX)).item_size, 4)
    assert_true(lit_pixels(scene, assets, model) > 0, "nothing drew")
    # Carry the bone far off and the triangle goes with it.
    var bone = scene.get(model.nodes[1])
    bone.set_position(100, 0, 0)
    scene.set(model.nodes[1], bone^)
    assert_equal(lit_pixels(scene, assets, model), 0)


def test_a_skin_without_inverse_binds_binds_at_the_identity() raises:
    # Short joints, normalized byte weights, two primitives, one of them
    # colored, and a morph target worn by the skinned mesh.
    var bin = Bin()
    _ = bin.floats(triangle(), "VEC3")
    _ = bin.ints([0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0], USHORT, "VEC4")
    _ = bin.ints(
        [255, 0, 0, 0, 0, 255, 0, 0, 128, 127, 0, 0],
        UBYTE,
        "VEC4",
        ',"normalized":true',
    )
    _ = bin.floats([1, 1, 1, 1, 1, 1, 1, 1, 1], "VEC3")
    _ = bin.floats([0, 0, 1, 0, 0, 1, 0, 0, 1], "VEC3")
    var text = bin.document(
        ',"meshes":[{"primitives":['
        + '{"attributes":{"POSITION":0,"JOINTS_0":1,"WEIGHTS_0":2},"targets":[{"POSITION":4}]},'
        + '{"attributes":{"POSITION":0,"JOINTS_0":1,"WEIGHTS_0":2,"COLOR_0":3},"targets":[{"POSITION":4}]}'
        + '],"weights":[0.75]}],"skins":[{"joints":[1,2]}]'
        + ',"nodes":[{"mesh":0,"skin":0},{"name":"A"},{"name":"B","translation":[1,0,0]}]'
        + ',"scenes":[{"nodes":[1,2,0]}]'
    )
    var scene = Scene()
    var assets = Assets()
    var model = loaded(text, scene, assets)
    assert_equal(model.skinned_mesh_count, 2)
    ref first = scene.skinned_meshes[0]
    assert_equal(first.bone_count(), 2)
    assert_equal(first.skeleton.bones[1].inverse_bind.elements[12], 0)
    assert_equal(first.skeleton.bones[1].inverse_bind.elements[15], 1)
    assert_almost_equal(first.morph_influence(0), 0.75, atol=TOLERANCE)
    ref weights = assets.geometries.get(first.geometry).attribute_view(
        String(SKIN_WEIGHT)
    )
    assert_almost_equal(weights.data[8], 128.0 / 255.0, atol=1e-3)
    assert_false(assets.materials.get(first.material).vertex_colors)
    assert_true(
        assets.materials.get(scene.skinned_meshes[1].material).vertex_colors
    )
    assert_equal(
        assets.geometries.get(first.geometry)
        .attribute_view(String(SKIN_INDEX))
        .data[1],
        1,
    )


def test_a_skinned_mesh_of_no_primitives_adds_nothing() raises:
    var bin = Bin()
    _ = bin.floats(triangle(), "VEC3")
    var text = bin.document(
        ',"meshes":[{"primitives":[]}],"skins":[{"joints":[1]}]'
        + ',"nodes":[{"mesh":0,"skin":0},{}],"scenes":[{"nodes":[1,0]}]'
    )
    var scene = Scene()
    var assets = Assets()
    var model = loaded(text, scene, assets)
    assert_equal(model.skinned_mesh_count, 0)


def test_a_malformed_skin_is_refused() raises:
    var bin = Bin()
    refuses(rig(bin, '[{"inverseBindMatrices":3}]'), "joints must be an array")
    bin = Bin()
    refuses(rig(bin, '[{"joints":{}}]'), "joints must be an array")
    bin = Bin()
    refuses(rig(bin, '[{"joints":[]}]'), "at least one bone")
    bin = Bin()
    refuses(rig(bin, '[{"joints":[-1]}]'), "joint that is not there")
    bin = Bin()
    refuses(rig(bin, '[{"joints":[9]}]'), "joint that is not there")
    # The inverse binds: not a MAT4, and not one per joint.
    bin = Bin()
    refuses(
        rig(bin, '[{"joints":[1],"inverseBindMatrices":0}]'), "one MAT4 per"
    )
    bin = Bin()
    refuses(
        rig(bin, '[{"joints":[1,1],"inverseBindMatrices":3}]'), "one MAT4 per"
    )
    # A skin the file does not have.
    bin = Bin()
    refuses(rig(bin, "[]"), "no skins entry")
    # A primitive without its weights or without its joints.
    bin = Bin()
    _ = bin.floats(triangle(), "VEC3")
    _ = bin.ints([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], UBYTE, "VEC4")
    _ = bin.floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], "VEC4")
    var skins = ',"skins":[{"joints":[1]}],"nodes":[{"mesh":0,"skin":0},{}],"scenes":[{"nodes":[1,0]}]'
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"JOINTS_0":1}}]}]'
            + skins
        ),
        "needs JOINTS_0 and WEIGHTS_0",
    )
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"WEIGHTS_0":2}}]}]'
            + skins
        ),
        "needs JOINTS_0 and WEIGHTS_0",
    )
    # A joint the loaded scene does not reach.
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"JOINTS_0":1,"WEIGHTS_0":2}}]}]'
            + ',"skins":[{"joints":[1]}],"nodes":[{"mesh":0,"skin":0},{}],"scenes":[{"nodes":[0]}]'
        ),
        "does not reach",
    )
    # A skinned node naming a mesh the file does not have.
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"JOINTS_0":1,"WEIGHTS_0":2}}]}]'
            + ',"skins":[{"joints":[1]}],"nodes":[{"mesh":4,"skin":0},{}],"scenes":[{"nodes":[1,0]}]'
        ),
        "a mesh that is not there",
    )


def test_malformed_skin_attributes_are_refused() raises:
    var bin = Bin()
    _ = bin.floats(triangle(), "VEC3")
    _ = bin.floats([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "VEC4")
    _ = bin.ints([0, 0, 0, 0, 0, 0], UBYTE, "VEC2")
    _ = bin.floats([1, 0, 1, 0, 1, 0], "VEC2")
    _ = bin.floats(List[Float32](), "VEC4")
    var tail = '}}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    var head = ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,'
    refuses(bin.document(head + '"JOINTS_0":1' + tail), "unsigned bytes or")
    refuses(
        bin.document(head + '"JOINTS_0":2' + tail), "JOINTS_0 must be a VEC4"
    )
    refuses(
        bin.document(head + '"WEIGHTS_0":3' + tail), "WEIGHTS_0 must be a VEC4"
    )
    # Weights of no vertices are read as none; the renderer checks them
    # against the positions.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        bin.document(head + '"WEIGHTS_0":4' + tail), scene, assets
    )
    assert_equal(
        len(
            assets.geometries.get(model.geometries[0])
            .attribute_view(String(SKIN_WEIGHT))
            .data
        ),
        0,
    )


# --- morph targets ----------------------------------------------------------


def morph_bin(mut bin: Bin):
    """Add a triangle, its normals, and three sets of offsets."""
    _ = bin.floats(triangle(), "VEC3")
    _ = bin.floats([0, 0, 1, 0, 0, 1, 0, 0, 1], "VEC3")
    _ = bin.floats([0, 0, 1, 0, 0, 2, 0, 0, 3], "VEC3")
    _ = bin.floats([1, 0, 0, 1, 0, 0, 1, 0, 0], "VEC3")
    _ = bin.floats([0, 0, 0, 0, 0, 0], "VEC2")


def test_morph_targets_are_read_as_offsets_with_their_weights() raises:
    var bin = Bin()
    morph_bin(bin)
    var text = bin.document(
        ',"meshes":['
        + '{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"targets":[{"POSITION":2,"NORMAL":3},{"POSITION":3}]}],"weights":[0.25,0.5]},'
        + '{"primitives":[{"attributes":{"POSITION":0},"targets":[{"NORMAL":3}]}]},'
        + '{"primitives":[{"attributes":{"POSITION":0},"targets":[]}]},'
        + '{"primitives":[{"attributes":{"POSITION":0},"targets":[{"POSITION":2},{"TANGENT":2}]}]}'
        + "]"
        + ',"nodes":[{"mesh":0},{"mesh":0,"weights":[1,0]},{"mesh":1},{"mesh":2},{"mesh":3}]'
        + ',"scenes":[{"nodes":[0,1,2,3,4]}]'
    )
    var scene = Scene()
    var assets = Assets()
    var model = loaded(text, scene, assets)
    ref face = assets.geometries.get(model.geometries[0])
    assert_equal(face.morph_count(), 2)
    assert_true(face.morph_relative)
    assert_true(face.has_morph_normals())
    assert_equal(face.morph_positions[0].data[8], 3)
    assert_equal(face.morph_positions[1].data[0], 1)
    assert_equal(face.morph_normals[0].data[0], 1)
    # The second target names no normals: they do not move.
    assert_equal(face.morph_normals[1].data[0], 0)
    # The mesh's weights, and the second node's own.
    assert_almost_equal(
        scene.meshes[0].morph_influence(0), 0.25, atol=TOLERANCE
    )
    assert_almost_equal(scene.meshes[0].morph_influence(1), 0.5, atol=TOLERANCE)
    assert_almost_equal(scene.meshes[1].morph_influence(0), 1, atol=TOLERANCE)
    assert_almost_equal(scene.meshes[1].morph_influence(1), 0, atol=TOLERANCE)
    # A target of normals alone moves no position.
    ref turned = assets.geometries.get(model.geometries[1])
    assert_equal(turned.morph_count(), 1)
    assert_equal(turned.morph_positions[0].data[0], 0)
    assert_equal(turned.morph_normals[0].data[0], 1)
    assert_equal(assets.geometries.get(model.geometries[2]).morph_count(), 0)
    ref plain = assets.geometries.get(model.geometries[3])
    assert_equal(plain.morph_count(), 2)
    assert_false(plain.has_morph_normals())
    assert_equal(scene.meshes[4].morph_influence(0), 0)


def test_malformed_morph_targets_are_refused() raises:
    var bin = Bin()
    morph_bin(bin)
    var nodes = ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":{}}]}]'
            + nodes
        ),
        "targets must be an array",
    )
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[1]}]}]'
            + nodes
        ),
        "must be an object",
    )
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[{"COLOR_0":2}]}]}]'
            + nodes
        ),
        "morph target of colors",
    )
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[{"POSITION":4}]}]}]'
            + nodes
        ),
        "POSITION must be a VEC3",
    )
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[{"NORMAL":4}]}]}]'
            + nodes
        ),
        "NORMAL must be a VEC3",
    )
    # Two primitives that disagree about how many targets there are.
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[{"POSITION":2}]},{"attributes":{"POSITION":0}}]}]'
            + nodes
        ),
        "as many morph targets",
    )
    # Nine targets, one past what a geometry holds.
    var nine = String()
    for index in range(9):
        if index > 0:
            nine += ","
        nine += '{"POSITION":2}'
    refuses(
        bin.document(
            ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":['
            + nine
            + "]}]}]"
            + nodes
        ),
        "at most eight",
    )
    # Weights that are not one per target, on the mesh or on the node.
    var one = ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[{"POSITION":2}]}]'
    refuses(bin.document(one + ',"weights":[1,2]}]' + nodes), "one number per")
    refuses(
        bin.document(
            one
            + '}],"nodes":[{"mesh":0,"weights":[1,2]}],"scenes":[{"nodes":[0]}]'
        ),
        "one number per",
    )
    refuses(
        bin.document(
            one + '}],"nodes":[{"mesh":0,"weights":1}],"scenes":[{"nodes":[0]}]'
        ),
        "array of numbers",
    )
    refuses(
        bin.document(
            one
            + '}],"nodes":[{"mesh":0,"weights":[1e300]}],"scenes":[{"nodes":[0]}]'
        ),
        "weights must be finite",
    )
    # Empty weights leave every influence at zero.
    var scene = Scene()
    var assets = Assets()
    _ = loaded(
        bin.document(
            one
            + '}],"nodes":[{"mesh":0,"weights":[]}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    assert_equal(scene.meshes[0].morph_influence(0), 0)


# --- cameras ----------------------------------------------------------------


def camera_doc(cameras: String) -> String:
    """Return a document of one node carrying camera zero."""
    return doc(
        ',"cameras":'
        + cameras
        + ',"nodes":[{"camera":0,"translation":[0,0,5]}],"scenes":[{"nodes":[0]}]'
    )


def test_cameras_ride_their_nodes() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        doc(
            ',"cameras":['
            + '{"type":"perspective","name":"Lens","perspective":{"yfov":0.5,"aspectRatio":2,"znear":0.25,"zfar":50}},'
            + '{"type":"perspective","perspective":{"yfov":1,"znear":0.5}},'
            + '{"type":"orthographic","orthographic":{"xmag":3,"ymag":2,"znear":0,"zfar":9}}]'
            + ',"nodes":[{"camera":0,"children":[1]},{"camera":1},{"camera":2},{"camera":2}]'
            + ',"scenes":[{"nodes":[0,2,3]}]'
        ),
        scene,
        assets,
    )
    assert_equal(len(model.cameras), 4)
    var lens = model.cameras[0].perspective()
    assert_equal(model.cameras[0].kind, GLTF_PERSPECTIVE)
    assert_equal(model.cameras[0].name, "Lens")
    assert_equal(model.cameras[0].index, 0)
    assert_equal(model.cameras[0].node, model.nodes[0])
    assert_equal(lens.node, model.nodes[0])
    assert_almost_equal(lens.fov.to(RADIAN), 0.5, atol=TOLERANCE)
    assert_equal(lens.aspect, 2)
    assert_almost_equal(lens.near.to(METER), 0.25, atol=TOLERANCE)
    assert_almost_equal(lens.far.to(METER), 50, atol=TOLERANCE)
    # three.js's defaults: square, and ending at two million meters.
    var plain = model.cameras[1].perspective()
    assert_equal(plain.aspect, 1)
    assert_almost_equal(plain.far.to(METER), 2e6, atol=1)
    assert_equal(plain.node, model.nodes[1])
    # One camera on two nodes is one camera on each.
    var box = model.cameras[2].orthographic()
    assert_equal(model.cameras[2].kind, GLTF_ORTHOGRAPHIC)
    assert_equal(box.left.to(METER), -3)
    assert_equal(box.right.to(METER), 3)
    assert_equal(box.top.to(METER), 2)
    assert_equal(box.bottom.to(METER), -2)
    assert_equal(box.near.to(METER), 0)
    assert_equal(box.far.to(METER), 9)
    assert_equal(box.node, model.nodes[2])
    assert_equal(model.cameras[3].orthographic().node, model.nodes[3])


def test_a_camera_is_read_only_as_its_own_kind() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        camera_doc(
            '[{"type":"perspective","perspective":{"yfov":1,"znear":0.5}}]'
        ),
        scene,
        assets,
    )
    var camera = model.cameras[0].copy()
    var reason = String()
    try:
        _ = camera.orthographic()
    except error:
        reason = String(error)
    assert_true("not an orthographic" in reason, reason)
    # A kind that names the other camera, which is not held.
    camera.kind = GLTF_ORTHOGRAPHIC
    try:
        _ = camera.orthographic()
    except error:
        reason = String(error)
    assert_true("holds no orthographic" in reason, reason)
    try:
        _ = camera.perspective()
    except error:
        reason = String(error)
    assert_true("not a perspective" in reason, reason)
    # A kind that is none of the two.
    camera.kind = GltfCameraKind(9)
    assert_false(camera.kind.is_valid())
    try:
        _ = camera.perspective()
    except error:
        reason = String(error)
    assert_true("kind that is not known" in reason, reason)
    try:
        _ = camera.orthographic()
    except error:
        reason = String(error)
    assert_true("kind that is not known" in reason, reason)
    # And the orthographic one, asked for as a perspective one.
    model = loaded(
        camera_doc(
            '[{"type":"orthographic","orthographic":{"xmag":1,"ymag":1,"znear":0,"zfar":2}}]'
        ),
        scene,
        assets,
    )
    camera = model.cameras[0].copy()
    camera.kind = GLTF_PERSPECTIVE
    try:
        _ = camera.perspective()
    except error:
        reason = String(error)
    assert_true("holds no perspective" in reason, reason)


def test_a_malformed_camera_is_refused() raises:
    refuses(camera_doc("[]"), "no cameras entry")
    refuses(camera_doc('[{"type":"fisheye"}]'), "perspective or orthographic")
    refuses(camera_doc('[{"type":"perspective"}]'), "needs a perspective")
    refuses(
        camera_doc('[{"type":"perspective","perspective":1}]'),
        "needs a perspective",
    )
    refuses(
        camera_doc('[{"type":"perspective","perspective":{"znear":1}}]'),
        "yfov is required",
    )
    refuses(
        camera_doc('[{"type":"perspective","perspective":{"yfov":1}}]'),
        "znear is required",
    )
    # What the camera itself refuses: no near plane.
    refuses(
        camera_doc(
            '[{"type":"perspective","perspective":{"yfov":1,"znear":0}}]'
        ),
        "near plane",
    )
    refuses(camera_doc('[{"type":"orthographic"}]'), "needs an orthographic")
    refuses(
        camera_doc('[{"type":"orthographic","orthographic":[]}]'),
        "needs an orthographic",
    )
    refuses(
        camera_doc(
            '[{"type":"orthographic","orthographic":{"xmag":0,"ymag":1,"znear":0,"zfar":1}}]'
        ),
        "right beyond left",
    )


# --- animations -------------------------------------------------------------


def animated(mut bin: Bin, animations: String) -> String:
    """Return a document of a morphed mesh at node zero, a plain node one,
    a node two no scene reaches, and `animations`.

    The accessors: 0 positions, 1 and 2 offsets, 3 two times, 4 two
    positions, 5 two rotations, 6 two cubic spline scales, 7 two keys of
    two weights, 8 two cubic spline keys of two weights, 9 three times,
    10 two rotations of cubic spline keys, 11 a VEC2 run, 12 one time,
    13 four positions, 14 nothing.
    """
    _ = bin.floats(triangle(), "VEC3")
    _ = bin.floats([0, 0, 1, 0, 0, 1, 0, 0, 1], "VEC3")
    _ = bin.floats([1, 0, 0, 1, 0, 0, 1, 0, 0], "VEC3")
    _ = bin.floats([0, 2], "SCALAR")
    _ = bin.floats([0, 0, 0, 4, 0, 0], "VEC3")
    _ = bin.floats([0, 0, 0, 1, 0, 0.7071068, 0, 0.7071068], "VEC4")
    _ = bin.floats(
        [
            9, 9, 9, 1, 1, 1, 0, 0, 0,
            3, 3, 3, 2, 2, 2, 9, 9, 9,
        ],
        "VEC3",
    )  # fmt: skip
    _ = bin.floats([0, 1, 1, 0], "SCALAR")
    _ = bin.floats([9, 9, 1, 2, 0, 0, 0, 0, 3, 4, 9, 9], "SCALAR")
    _ = bin.floats([0, 1, 2], "SCALAR")
    _ = bin.floats(
        [
            0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0.7071068, 0.7071068, 0, 0, 0, 0,
        ],
        "VEC4",
    )  # fmt: skip
    _ = bin.floats([0, 0, 1, 1], "VEC2")
    _ = bin.floats([0], "SCALAR")
    _ = bin.floats([0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0], "VEC3")
    _ = bin.floats(List[Float32](), "SCALAR")
    return bin.document(
        ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"targets":[{"POSITION":1},{"POSITION":2}]}]},'
        + '{"primitives":[{"attributes":{"POSITION":0}}]}]'
        + ',"nodes":[{"mesh":0},{"mesh":1},{}],"scenes":[{"nodes":[0,1]}]'
        + ',"animations":'
        + animations
    )


def test_animations_become_clips() raises:
    var bin = Bin()
    var text = animated(
        bin,
        '[{"name":"Walk","samplers":['
        + '{"input":3,"output":4},'
        + '{"input":3,"output":5,"interpolation":"STEP"},'
        + '{"input":3,"output":6,"interpolation":"CUBICSPLINE"},'
        + '{"input":3,"output":7,"interpolation":"LINEAR"},'
        + '{"input":3,"output":8,"interpolation":"CUBICSPLINE"}],"channels":['
        + '{"sampler":0,"target":{"node":1,"path":"translation"}},'
        + '{"sampler":1,"target":{"node":1,"path":"rotation"}},'
        + '{"sampler":2,"target":{"node":1,"path":"scale"}},'
        + '{"sampler":3,"target":{"node":0,"path":"weights"}},'
        + '{"sampler":4,"target":{"node":0,"path":"weights"}},'
        + '{"sampler":3,"target":{"node":1,"path":"weights"}},'
        + '{"sampler":3,"target":{"node":2,"path":"weights"}},'
        + '{"sampler":0,"target":{"path":"translation"}}]},'
        + '{"samplers":[{"input":3,"output":10,"interpolation":"CUBICSPLINE"}],'
        + '"channels":[{"sampler":0,"target":{"node":1,"path":"rotation"}}]},'
        + '{"samplers":[{"input":3,"output":4}],'
        + '"channels":[{"sampler":0,"target":{"node":2,"path":"translation"}}]}]',
    )
    var scene = Scene()
    var assets = Assets()
    var model = loaded(text, scene, assets)
    # The third animation drives only a node the scene does not reach.
    assert_equal(len(model.animations), 2)
    ref walk = model.animations[0]
    assert_equal(walk.name, "Walk")
    assert_equal(model.animations[1].name, "animation_1")
    # Three node tracks, and two weights channels of two targets each.
    assert_equal(walk.track_count(), 7)
    assert_almost_equal(walk.duration().to(SECOND), 2, atol=TOLERANCE)
    ref slide = walk.tracks[0]
    assert_equal(slide.kind(), TRANSLATION)
    assert_equal(slide.interpolation, LINEAR)
    assert_equal(slide.target.index, model.nodes[1].value)
    assert_almost_equal(
        slide.sample_vector3(Duration(1, SECOND)).x, 2, atol=TOLERANCE
    )
    ref turn = walk.tracks[1]
    assert_equal(turn.kind(), QUATERNION)
    assert_equal(turn.interpolation, STEP)
    assert_almost_equal(
        turn.sample_quaternion(Duration(1, SECOND)).w, 1, atol=TOLERANCE
    )
    ref grow = walk.tracks[2]
    assert_equal(grow.kind(), SCALE)
    assert_equal(grow.interpolation, CUBIC_SPLINE)
    # In-tangent, value and out-tangent, split out of each key.
    assert_equal(grow.in_tangents[0], 9)
    assert_equal(grow.values[0], 1)
    assert_equal(grow.out_tangents[0], 0)
    assert_equal(grow.in_tangents[3], 3)
    assert_equal(grow.values[3], 2)
    assert_equal(grow.out_tangents[3], 9)
    # Half way, the Hermite cubic of 1 and 2 with slopes 0 and 3 over two
    # seconds: 0.5 + 0.5 * 2 - 0.125 * 3 * 2.
    assert_almost_equal(
        grow.sample_vector3(Duration(1, SECOND)).x, 0.75, atol=TOLERANCE
    )
    ref first = walk.tracks[3]
    assert_equal(first.kind(), MORPH_INFLUENCE)
    assert_equal(first.target.index, 0)
    assert_equal(first.target.slot, 0)
    assert_equal(first.values[0], 0)
    assert_equal(first.values[1], 1)
    ref second = walk.tracks[4]
    assert_equal(second.target.slot, 1)
    assert_equal(second.values[0], 1)
    assert_equal(second.values[1], 0)
    ref smooth = walk.tracks[6]
    assert_equal(smooth.interpolation, CUBIC_SPLINE)
    assert_equal(smooth.target.slot, 1)
    assert_equal(smooth.in_tangents[0], 9)
    assert_equal(smooth.values[0], 2)
    assert_equal(smooth.values[1], 4)
    assert_equal(smooth.out_tangents[1], 9)
    ref spun = model.animations[1].tracks[0]
    assert_equal(spun.interpolation, CUBIC_SPLINE)
    assert_almost_equal(spun.values[7], 0.7071068, atol=TOLERANCE)
    # The mixer plays the clip onto the loaded meshes and nodes.
    var mixer = AnimationMixer()
    var action = mixer.add(AnimationAction(model.animations[0].copy()))
    mixer.action(action).play()
    mixer.update(scene, assets, Duration(0.5, SECOND))
    assert_almost_equal(scene.get(model.nodes[1]).position.x, 1, atol=TOLERANCE)


def test_a_malformed_animation_is_refused() raises:
    var bin = Bin()
    refuses(animated(bin, "{}"), "animations must be an array")
    bin = Bin()
    refuses(animated(bin, '[{"samplers":[]}]'), "channels must be an array")
    bin = Bin()
    refuses(animated(bin, '[{"channels":[]}]'), "samplers must be an array")
    bin = Bin()
    refuses(
        animated(bin, '[{"samplers":[],"channels":[1]}]'), "must be an object"
    )
    bin = Bin()
    refuses(
        animated(bin, '[{"samplers":[],"channels":[{"sampler":0}]}]'),
        "a sampler that is not there",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            '[{"samplers":[{"input":3,"output":4}],"channels":[{"sampler":-1}]}]',
        ),
        "a sampler that is not there",
    )
    var one = '[{"samplers":[{"input":3,"output":4}],"channels":[{"sampler":0'
    bin = Bin()
    refuses(animated(bin, one + "}]}]"), "needs a target object")
    bin = Bin()
    refuses(animated(bin, one + ',"target":1}]}]'), "needs a target object")
    bin = Bin()
    refuses(
        animated(bin, one + ',"target":{"node":7,"path":"scale"}}]}]'),
        "a node that is not there",
    )
    bin = Bin()
    refuses(
        animated(bin, one + ',"target":{"node":1,"path":"pointer"}}]}]'),
        "channel path must be",
    )
    # A sampler: its input, its interpolation and its output.
    var sampler = '[{"channels":[{"sampler":0,"target":{"node":1,"path":"'
    bin = Bin()
    refuses(
        animated(
            bin,
            sampler + 'translation"}}],"samplers":[{"input":4,"output":4}]}]',
        ),
        "input must be a SCALAR",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            sampler
            + 'translation"}}],"samplers":[{"input":3,"output":4,"interpolation":"SMOOTH"}]}]',
        ),
        "LINEAR, STEP or CUBICSPLINE",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            sampler + 'rotation"}}],"samplers":[{"input":3,"output":4}]}]',
        ),
        "rotation output must be a VEC4",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            sampler + 'translation"}}],"samplers":[{"input":9,"output":4}]}]',
        ),
        "one value per key",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            sampler
            + 'translation"}}],"samplers":[{"input":3,"output":4,"interpolation":"CUBICSPLINE"}]}]',
        ),
        "one value per key",
    )
    # A track of no keys, and times that do not rise.
    bin = Bin()
    refuses(
        animated(
            bin,
            '[{"channels":[{"sampler":0,"target":{"node":0,"path":"weights"}}],"samplers":[{"input":14,"output":14}]}]',
        ),
        "at least one key",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            sampler + 'scale"}}],"samplers":[{"input":7,"output":13}]}]',
        ),
        "must rise",
    )
    # A weights channel: its output, and one on a node whose mesh has no
    # targets, which makes no track.
    var weights = '[{"channels":[{"sampler":0,"target":{"node":'
    bin = Bin()
    refuses(
        animated(
            bin,
            weights
            + '0,"path":"weights"}}],"samplers":[{"input":3,"output":4}]}]',
        ),
        "weights output must be a SCALAR",
    )
    bin = Bin()
    refuses(
        animated(
            bin,
            weights
            + '0,"path":"weights"}}],"samplers":[{"input":3,"output":3}]}]',
        ),
        "one value per key",
    )
    var scene = Scene()
    var assets = Assets()
    bin = Bin()
    var model = loaded(
        animated(
            bin,
            weights
            + '1,"path":"weights"}}],"samplers":[{"input":3,"output":3}]},{"channels":[],"samplers":[]}]',
        ),
        scene,
        assets,
    )
    assert_equal(len(model.animations), 0)
    # A clip of one key lasts no time, which a clip refuses.
    bin = Bin()
    refuses(
        animated(
            bin,
            weights
            + '0,"path":"weights"}}],"samplers":[{"input":12,"output":3}]}]',
        ),
        "longer than no time",
    )


def test_a_document_without_a_scene_places_no_animation() raises:
    var bin = Bin()
    _ = bin.floats([0, 1], "SCALAR")
    _ = bin.floats([0, 0, 0, 1, 0, 0], "VEC3")
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        bin.document(
            ',"nodes":[{}],"animations":[{"samplers":[{"input":0,"output":1}],"channels":[{"sampler":0,"target":{"node":0,"path":"translation"}}]}]'
        ),
        scene,
        assets,
    )
    assert_equal(len(model.animations), 0)
    assert_equal(model.skinned_mesh_count, 0)
    # A weights channel on a node that draws no plain mesh makes no track.
    scene = Scene()
    model = loaded(
        bin.document(
            ',"nodes":[{}],"scenes":[{"nodes":[0]}],"animations":[{"samplers":[{"input":0,"output":0}],"channels":[{"sampler":0,"target":{"node":0,"path":"weights"}}]}]'
        ),
        scene,
        assets,
    )
    assert_equal(len(model.animations), 0)


# --- sparse accessors -------------------------------------------------------


def sparse(
    base: String,
    count: Int,
    index_view: Int,
    index_type: Int,
    value_view: Int,
    extra: String = "",
) -> String:
    """Return a VEC3 float accessor of `count` elements over `base` with a
    sparse part."""
    return (
        '{"componentType":5126,"count":'
        + String(count)
        + ',"type":"VEC3"'
        + base
        + ',"sparse":{"count":1,"indices":{"bufferView":'
        + String(index_view)
        + ',"componentType":'
        + String(index_type)
        + '},"values":{"bufferView":'
        + String(value_view)
        + extra
        + "}}}"
    )


def sparse_bin(mut bin: Bin):
    """Add a triangle's view, indices of each unsigned width naming vertex
    one, and one position to put there. Views: 0 the triangle, 1 a byte
    index, 2 a short index, 3 a word index, 4 the value, 5 two byte
    indices of one and zero."""
    _ = bin.view(float_bytes(triangle()))
    _ = bin.view(int_bytes([1], 1))
    _ = bin.view(int_bytes([1], 2))
    _ = bin.view(int_bytes([1], 4))
    _ = bin.view(float_bytes([5, 6, 7]))
    _ = bin.view(int_bytes([1, 0], 1))


def sparse_doc(mut bin: Bin, accessor: String) -> String:
    """Return a document whose one triangle's positions are `accessor`."""
    _ = bin.accessor(accessor)
    return bin.document(
        ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )


def positions_of(text: String) raises -> List[Float32]:
    """Return the positions a one-triangle document loads."""
    var scene = Scene()
    var assets = Assets()
    var model = loaded(text, scene, assets)
    return (
        assets.geometries.get(model.geometries[0])
        .attribute_view(String(POSITION))
        .data.copy()
    )


def test_sparse_values_replace_the_elements_they_name() raises:
    for index_view in range(1, 4):
        var bin = Bin()
        sparse_bin(bin)
        var found = positions_of(
            sparse_doc(
                bin,
                sparse(
                    ',"bufferView":0',
                    3,
                    index_view,
                    UBYTE + (index_view - 1) * 2,
                    4,
                ),
            )
        )
        assert_equal(found[3], 5)
        assert_equal(found[4], 6)
        assert_equal(found[5], 7)
        assert_equal(found[6], 0)
        assert_equal(found[7], 1)
    # With no view under it, the rest are zeros.
    var bin = Bin()
    sparse_bin(bin)
    var found = positions_of(sparse_doc(bin, sparse("", 3, 1, UBYTE, 4)))
    assert_equal(found[0], 0)
    assert_equal(found[3], 5)
    assert_equal(found[7], 0)


def test_a_malformed_sparse_accessor_is_refused() raises:
    var bin = Bin()
    sparse_bin(bin)
    var view = ',"bufferView":0'
    var head = (
        '{"componentType":5126,"count":3,"type":"VEC3","bufferView":0,"sparse":'
    )
    refuses(sparse_doc(bin, head + "1}"), "sparse must be an object")
    bin = Bin()
    sparse_bin(bin)
    refuses(sparse_doc(bin, head + "{}}"), "count is required")
    bin = Bin()
    sparse_bin(bin)
    refuses(sparse_doc(bin, head + '{"count":0}}'), "at least one")
    bin = Bin()
    sparse_bin(bin)
    refuses(sparse_doc(bin, head + '{"count":4}}'), "at least one")
    # Indices and values: absent, and not objects.
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(bin, head + '{"count":1,"values":{"bufferView":4}}}'),
        "indices and values objects",
    )
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(
            bin,
            head
            + '{"count":1,"indices":{"bufferView":1,"componentType":5121}}}',
        ),
        "indices and values objects",
    )
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(
            bin, head + '{"count":1,"indices":1,"values":{"bufferView":4}}}'
        ),
        "indices and values objects",
    )
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(
            bin,
            head
            + '{"count":1,"indices":{"bufferView":1,"componentType":5121},"values":1}}',
        ),
        "indices and values objects",
    )
    # Indices of a signed or a float type.
    bin = Bin()
    sparse_bin(bin)
    refuses(sparse_doc(bin, sparse(view, 3, 1, BYTE, 4)), "unsigned integers")
    bin = Bin()
    sparse_bin(bin)
    refuses(sparse_doc(bin, sparse(view, 3, 1, FLOAT, 4)), "unsigned integers")
    # Views that are too short, or begin before themselves.
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(bin, sparse(view, 3, 1, UBYTE, 1)), "runs past its buffer"
    )
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(bin, sparse(view, 3, 1, UBYTE, 4, ',"byteOffset":-4')),
        "runs past its buffer",
    )
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(bin, sparse(view, 3, 1, UINT, 4)), "runs past its buffer"
    )
    # An index past the accessor, and indices that do not rise.
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(bin, sparse(view, 1, 1, UBYTE, 4)), "inside the accessor"
    )
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(
            bin,
            '{"componentType":5126,"count":3,"type":"SCALAR","bufferView":0,"sparse":{"count":2,"indices":{"bufferView":5,"componentType":5121},"values":{"bufferView":4}}}',
        ),
        "must rise",
    )
    # A negative count.
    bin = Bin()
    sparse_bin(bin)
    refuses(
        sparse_doc(bin, '{"componentType":5126,"count":-1,"type":"VEC3"}'),
        "must not be negative",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
