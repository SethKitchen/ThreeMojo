# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for what `exporters.gltf` writes beyond static meshes: lights,
cameras, animations, skins, morph targets, instancing, lines and points.

`assets/gltf/three_export.gltf` is the scene `Rig` builds, exported by
three.js 0.180's `GLTFExporter` in Node with `trs` on;
`assets/gltf/three_export.mjs` writes it. The key tests compare the JSON
this exporter writes with it, load both files and compare what they hold,
and read this exporter's file back to the scene it was written from. The
rest walks every choice the writer makes and every refusal.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    CUBIC_SPLINE,
    MATERIAL_OPACITY,
    MORPH_INFLUENCE,
    POSITION as MOVE,
    QUATERNION,
    SCALE,
    SMOOTH,
    STEP,
    VISIBLE,
    KeyframeTrack,
    MeshIndex,
    SkinnedMeshIndex,
    material_target,
    morph_target,
    node_target,
    skinned_morph_target,
)
from cameras.camera_list import CameraList
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.gltf import (
    GLB,
    GLTF_EMBEDDED,
    GltfContainer,
    export_gltf,
    line_mode_code,
    target_name,
)
from lights.light import (
    DIRECTIONAL,
    POINT,
    SPOT,
    LightKind,
    ambient_light,
    directional_light,
    point_light,
    spot_light,
)
from loaders.gltf import (
    GltfModel,
    MODE_LINES,
    MODE_LINE_LOOP,
    MODE_LINE_STRIP,
    load_gltf,
    split_glb,
)
from loaders.json import NO_NODE, JsonDocument, parse_json
from materials.material import (
    BASIC,
    NO_TEXTURE,
    PHONG,
    PHYSICAL,
    Material,
    MaterialId,
    standard_material,
)
from math.matrix4 import Matrix4, translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import LOOP, SEGMENTS, STRIP, Line
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import Texture
from std.math import sqrt
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, RADIAN, SECOND

comptime TOLERANCE = Float64(1e-5)
comptime HALF_ROOT = Float32(0.70710678)


def seconds(times: List[Float32]) -> List[Duration]:
    """Return times in seconds as durations."""
    var out = List[Duration]()
    for at in times:
        out.append(Duration(at, SECOND))
    return out^


def triangle() raises -> BufferGeometry:
    """Return three.js's triangle of the reference scene."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 0, 1, 0], 3),
    )
    return geometry^


def path(count: Int) raises -> BufferGeometry:
    """Return the reference scene's path of `count` points."""
    var points = List[Float32]()
    for at in range(count):
        points.extend([Float32(at), Float32(at * at), 0])
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    return geometry^


def skinned_triangle() raises -> BufferGeometry:
    """Return the triangle with each corner on one of two bones."""
    var geometry = triangle()
    geometry.set_attribute(
        String(SKIN_INDEX),
        BufferAttribute([Float32(0), 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4),
    )
    geometry.set_attribute(
        String(SKIN_WEIGHT),
        BufferAttribute([Float32(1), 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4),
    )
    return geometry^


def named(
    name: String, x: Float32 = 0, y: Float32 = 0, z: Float32 = 0
) -> Object3D:
    """Return a node with a name, at a position."""
    var node = Object3D()
    node.name = name
    node.set_position(x, y, z)
    return node^


struct Rig(Movable):
    """The scene `three_export.mjs` builds, node for node."""

    var scene: Scene
    var assets: Assets
    var cameras: CameraList
    var clips: List[AnimationClip]
    var white: MaterialId

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        self.cameras = CameraList()
        self.white = self.assets.materials.add(
            Material(Color(255, 255, 255), kind=BASIC)
        )
        var ink = self.assets.materials.add(
            Material(Color(0x33, 0x66, 0x99), kind=BASIC)
        )
        var lamp = self.scene.add(named("lamp", 0, 2, 0))
        self.scene.add_light(
            point_light(Color(255, 128, 0), lamp, 3, distance=10)
        )
        var sun = self.scene.add(named("sun", 0, 1, 0))
        var aim = self.scene.attach(named("", 0, 0, -1), sun)
        self.scene.add_light(
            directional_light(Color(255, 255, 255), sun, 2, target=aim)
        )
        var spot = self.scene.add(named("spot", 0, 1, 0))
        var cone = self.scene.attach(named("", 0, 0, -1), spot)
        self.scene.add_light(
            spot_light(
                Color(0, 255, 0),
                spot,
                5,
                distance=5,
                angle=Angle(0.5, RADIAN),
                penumbra=0.2,
                target=cone,
            )
        )
        var eye = self.scene.add(named("eye", 0, 0, 5))
        var lens = PerspectiveCamera(
            Angle(50.0, DEGREE), 1.5, Length(0.1, METER), Length(100.0, METER)
        )
        lens.attach(eye)
        self.cameras.perspective.append(lens)
        var flat = self.scene.add(named("flat"))
        var box = OrthographicCamera(
            Length(-2.0, METER),
            Length(2.0, METER),
            Length(1.0, METER),
            Length(-1.0, METER),
            Length(0.5, METER),
            Length(20.0, METER),
        )
        box.attach(flat)
        self.cameras.orthographic.append(box^)
        var blob = self.scene.add(named("blob"))
        var shape = triangle()
        shape.add_morph_target(
            BufferAttribute([Float32(0), 1, 0, 0, 0, 0, 0, 0, 0], 3)
        )
        shape.add_morph_target(
            BufferAttribute([Float32(0), 0, 0, 0, -1, 0, 0, 0, 0], 3)
        )
        shape.morph_relative = True
        shape.morph_names = ["smile", "frown"]
        var face = Mesh(self.assets.geometries.add(shape^), self.white, blob)
        face.set_morph_influence(0, 0.25)
        face.set_morph_influence(1, 0.5)
        self.scene.add_mesh(face)
        var root = self.scene.add(named("root"))
        var tip = self.scene.attach(named("tip", 0, 1, 0), root)
        var arm = self.scene.add(named("arm"))
        self.scene.add_skinned_mesh(
            SkinnedMesh(
                self.assets.geometries.add(skinned_triangle()),
                self.white,
                arm,
                Skeleton(
                    [Bone(root, Matrix4()), Bone(tip, translation(0, -1, 0))]
                ),
            )
        )
        var crowd = self.scene.add(named("crowd"))
        var many = InstancedMesh(
            self.assets.geometries.add(triangle()), self.white, crowd, 2
        )
        many.set_matrix_at(0, translation(1, 0, 0))
        var grown = translation(0, 1, 0)
        grown.scale(Vector3(2, 2, 2))
        many.set_matrix_at(1, grown)
        many.set_color_at(0, Color(255, 0, 0))
        many.set_color_at(1, Color(0, 0, 255))
        self.scene.add_instanced_mesh(many^)
        var wire = self.scene.add(named("wire"))
        self.scene.add_line(
            Line(self.assets.geometries.add(path(4)), ink, wire, mode=SEGMENTS)
        )
        var loop = self.scene.add(named("loop"))
        self.scene.add_line(
            Line(self.assets.geometries.add(path(3)), ink, loop, mode=LOOP)
        )
        var strip = self.scene.add(named("strip"))
        self.scene.add_line(
            Line(self.assets.geometries.add(path(3)), ink, strip, mode=STRIP)
        )
        var dots = self.scene.add(named("dots"))
        self.scene.add_points(
            Points(self.assets.geometries.add(path(2)), ink, dots)
        )
        var tracks = List[KeyframeTrack]()
        tracks.append(
            KeyframeTrack(
                lamp, MOVE, seconds([0, 1, 2]), [0, 2, 0, 1, 2, 0, 1, 3, 0]
            )
        )
        tracks.append(
            KeyframeTrack(
                root,
                QUATERNION,
                seconds([0, 1]),
                [0, 0, 0, 1, 0, 0, HALF_ROOT, HALF_ROOT],
                STEP,
            )
        )
        tracks.append(
            KeyframeTrack(tip, SCALE, seconds([0, 2]), [1, 1, 1, 2, 2, 2])
        )
        tracks.append(
            KeyframeTrack(
                morph_target(MeshIndex(0), 1), seconds([0, 1]), [0, 1]
            )
        )
        tracks.append(
            KeyframeTrack(
                morph_target(MeshIndex(0), 0), seconds([0.5, 1.5]), [1, 0]
            )
        )
        self.clips = [AnimationClip("move", tracks^)]

    def export(self, container: GltfContainer = GLTF_EMBEDDED) raises -> String:
        """Return the rig's `.gltf` text, or a `.glb`'s JSON chunk."""
        var files = export_gltf(
            self.scene,
            self.assets,
            container,
            cameras=self.cameras,
            animations=self.clips,
        )
        if container == GLB:
            return split_glb(files.document)[0]
        return String(unsafe_from_utf8=files.document)


struct Loaded(Movable):
    """A file read into a scene of its own."""

    var scene: Scene
    var assets: Assets
    var model: GltfModel

    def __init__(
        out self, text: String, bin: List[UInt8] = List[UInt8]()
    ) raises:
        self.scene = Scene()
        self.assets = Assets()
        self.model = load_gltf(text, bin, "", self.scene, self.assets)


def reference() raises -> String:
    """Return three.js's file."""
    return String(
        unsafe_from_utf8=Path("assets/gltf/three_export.gltf").read_bytes()
    )


# --- small readers of a parsed document -------------------------------------


def at(document: JsonDocument, node: Int, path: List[String]) raises -> Int:
    """Return the node a path of keys and indices leads to, or `NO_NODE`."""
    var here = node
    for step in path:
        if here == NO_NODE:
            return NO_NODE
        var first = step.as_bytes()[0]
        if first >= 48 and first <= 57:
            here = document.at(here, Int(step))
        else:
            here = document.get(here, step)
    return here


def number(
    document: JsonDocument, node: Int, path: List[String]
) raises -> Float64:
    """Return the number a path leads to."""
    return document.number(at(document, node, path))


def has_keys(document: JsonDocument, node: Int, expected: List[String]) raises:
    """Assert an object has exactly these keys, in any order."""
    assert_equal(document.length(node), len(expected))
    for key in expected:
        assert_true(document.has(node, key), key)


def assert_close(got: Float64, expected: Float64) raises:
    """Assert two numbers agree to within rounding."""
    assert_almost_equal(got, expected, atol=TOLERANCE)


def numbers(document: JsonDocument, node: Int) raises -> List[Float64]:
    """Return an array of numbers."""
    var out = List[Float64]()
    for slot in range(document.length(node)):
        out.append(document.number(document.at(node, slot)))
    return out^


def assert_numbers(
    ours: JsonDocument, one: Int, theirs: JsonDocument, two: Int
) raises:
    """Assert two arrays of numbers agree, number by number."""
    var got = numbers(ours, one)
    var expected = numbers(theirs, two)
    assert_equal(len(got), len(expected))
    for slot in range(len(got)):
        assert_close(got[slot], expected[slot])


# --- three.js's file --------------------------------------------------------


def test_the_json_matches_three_js() raises:
    var rig = Rig()
    var ours = parse_json(rig.export())
    var theirs = parse_json(reference())
    var one = ours.root()
    var two = theirs.root()
    # Node for node: names, transforms, what each carries, and children.
    var mine = ours.get(one, "nodes")
    var three = theirs.get(two, "nodes")
    assert_equal(ours.length(mine), 16)
    assert_equal(theirs.length(three), 16)
    for slot in range(16):
        var a = ours.at(mine, slot)
        var b = theirs.at(three, slot)
        for key in [
            String("name"),
            String("mesh"),
            String("camera"),
            String("skin"),
            String("children"),
            String("translation"),
            String("rotation"),
            String("scale"),
        ]:
            assert_equal(ours.has(a, key), theirs.has(b, key), key)
        if ours.has(a, "name"):
            assert_equal(
                ours.string(ours.get(a, "name")),
                theirs.string(theirs.get(b, "name")),
            )
        if ours.has(a, "translation"):
            assert_numbers(
                ours,
                ours.get(a, "translation"),
                theirs,
                theirs.get(b, "translation"),
            )
        if ours.has(a, "children"):
            assert_numbers(
                ours, ours.get(a, "children"), theirs, theirs.get(b, "children")
            )
        var lit = at(ours, a, ["extensions", "KHR_lights_punctual", "light"])
        var lamp = at(theirs, b, ["extensions", "KHR_lights_punctual", "light"])
        assert_equal(lit == NO_NODE, lamp == NO_NODE)
        if lit != NO_NODE:
            assert_equal(ours.integer(lit), theirs.integer(lamp))
        var crowd = at(
            ours, a, ["extensions", "EXT_mesh_gpu_instancing", "attributes"]
        )
        var many = at(
            theirs, b, ["extensions", "EXT_mesh_gpu_instancing", "attributes"]
        )
        assert_equal(crowd == NO_NODE, many == NO_NODE)
        if crowd != NO_NODE:
            has_keys(
                ours, crowd, ["TRANSLATION", "ROTATION", "SCALE", "_COLOR_0"]
            )
    # The lights, field by field.
    var lights = at(ours, one, ["extensions", "KHR_lights_punctual", "lights"])
    var lamps = at(theirs, two, ["extensions", "KHR_lights_punctual", "lights"])
    assert_equal(ours.length(lights), 3)
    for slot in range(3):
        var a = ours.at(lights, slot)
        var b = theirs.at(lamps, slot)
        assert_equal(ours.length(a), theirs.length(b))
        assert_equal(
            ours.string(ours.get(a, "type")),
            theirs.string(theirs.get(b, "type")),
        )
        assert_equal(
            ours.string(ours.get(a, "name")),
            theirs.string(theirs.get(b, "name")),
        )
        assert_numbers(
            ours, ours.get(a, "color"), theirs, theirs.get(b, "color")
        )
        assert_close(
            number(ours, a, ["intensity"]), number(theirs, b, ["intensity"])
        )
        assert_equal(ours.has(a, "range"), theirs.has(b, "range"))
        if ours.has(a, "range"):
            assert_close(
                number(ours, a, ["range"]), number(theirs, b, ["range"])
            )
        if ours.has(a, "spot"):
            for key in [String("innerConeAngle"), String("outerConeAngle")]:
                assert_close(
                    number(ours, a, ["spot", key]),
                    number(theirs, b, ["spot", key]),
                )
    # The cameras. three.js names a camera by its type and writes twice the
    # orthographic half-width; this names it by its node and writes the
    # half-width the specification asks for.
    var lens = at(ours, one, ["cameras", "0", "perspective"])
    var eye = at(theirs, two, ["cameras", "0", "perspective"])
    for key in [
        String("aspectRatio"),
        String("yfov"),
        String("zfar"),
        String("znear"),
    ]:
        assert_close(number(ours, lens, [key]), number(theirs, eye, [key]))
    assert_equal(ours.string(at(ours, one, ["cameras", "0", "name"])), "eye")
    assert_equal(
        theirs.string(at(theirs, two, ["cameras", "0", "name"])),
        "PerspectiveCamera",
    )
    var box = at(ours, one, ["cameras", "1", "orthographic"])
    var flat = at(theirs, two, ["cameras", "1", "orthographic"])
    assert_close(
        number(ours, box, ["xmag"]) * 2, number(theirs, flat, ["xmag"])
    )
    assert_close(
        number(ours, box, ["ymag"]) * 2, number(theirs, flat, ["ymag"])
    )
    assert_close(number(ours, box, ["zfar"]), number(theirs, flat, ["zfar"]))
    assert_close(number(ours, box, ["znear"]), number(theirs, flat, ["znear"]))
    # The meshes: weights, target names, modes and attributes.
    var meshes = ours.get(one, "meshes")
    var others = theirs.get(two, "meshes")
    assert_equal(ours.length(meshes), theirs.length(others))
    for slot in range(ours.length(meshes)):
        var a = ours.at(meshes, slot)
        var b = theirs.at(others, slot)
        assert_equal(ours.has(a, "weights"), theirs.has(b, "weights"))
        if ours.has(a, "weights"):
            assert_numbers(
                ours, ours.get(a, "weights"), theirs, theirs.get(b, "weights")
            )
            var names = at(ours, a, ["extras", "targetNames"])
            var labels = at(theirs, b, ["extras", "targetNames"])
            assert_equal(ours.length(names), theirs.length(labels))
            for target in range(ours.length(names)):
                assert_equal(
                    ours.string(ours.at(names, target)),
                    theirs.string(theirs.at(labels, target)),
                )
        var p = at(ours, a, ["primitives", "0"])
        var q = at(theirs, b, ["primitives", "0"])
        assert_equal(number(ours, p, ["mode"]), number(theirs, q, ["mode"]))
        var attributes = theirs.get(q, "attributes")
        assert_equal(
            ours.length(ours.get(p, "attributes")), theirs.length(attributes)
        )
        for key in range(theirs.length(attributes)):
            assert_true(
                ours.has(ours.get(p, "attributes"), theirs.key(attributes, key))
            )
        assert_equal(ours.has(p, "targets"), theirs.has(q, "targets"))
    # The skin.
    var skin = at(ours, one, ["skins", "0"])
    var bones = at(theirs, two, ["skins", "0"])
    assert_numbers(
        ours, ours.get(skin, "joints"), theirs, theirs.get(bones, "joints")
    )
    assert_equal(
        number(ours, skin, ["skeleton"]), number(theirs, bones, ["skeleton"])
    )
    # The animation: one channel a node track, and the two morph tracks of
    # the blob merged into one, where the first of them was.
    var clip = at(ours, one, ["animations", "0"])
    var move = at(theirs, two, ["animations", "0"])
    assert_equal(ours.string(ours.get(clip, "name")), "move")
    assert_equal(ours.length(ours.get(clip, "channels")), 4)
    for slot in range(4):
        var a = at(ours, clip, ["channels", String(slot)])
        var b = at(theirs, move, ["channels", String(slot)])
        assert_equal(
            number(ours, a, ["target", "node"]),
            number(theirs, b, ["target", "node"]),
        )
        assert_equal(
            ours.string(at(ours, a, ["target", "path"])),
            theirs.string(at(theirs, b, ["target", "path"])),
        )
        var s = ours.integer(ours.get(a, "sampler"))
        var t = theirs.integer(theirs.get(b, "sampler"))
        assert_equal(
            ours.string(
                at(ours, clip, ["samplers", String(s), "interpolation"])
            ),
            theirs.string(
                at(theirs, move, ["samplers", String(t), "interpolation"])
            ),
        )
    # What is used and what is required.
    assert_numbers_of_strings(
        ours,
        ours.get(one, "extensionsUsed"),
        theirs,
        theirs.get(two, "extensionsUsed"),
    )
    assert_numbers_of_strings(
        ours,
        ours.get(one, "extensionsRequired"),
        theirs,
        theirs.get(two, "extensionsRequired"),
    )


def assert_numbers_of_strings(
    ours: JsonDocument, one: Int, theirs: JsonDocument, two: Int
) raises:
    """Assert two arrays hold the same strings, in any order."""
    assert_equal(ours.length(one), theirs.length(two))
    for slot in range(ours.length(one)):
        var name = ours.string(ours.at(one, slot))
        var found = False
        for other in range(theirs.length(two)):
            found = found or theirs.string(theirs.at(two, other)) == name
        assert_true(found, name)


def assert_same_track(got: KeyframeTrack, expected: KeyframeTrack) raises:
    """Assert two tracks drive one kind of thing with the same keys."""
    assert_equal(got.target.kind, expected.target.kind)
    assert_equal(got.target.slot, expected.target.slot)
    assert_equal(got.interpolation, expected.interpolation)
    assert_equal(len(got.times), len(expected.times))
    for key in range(len(got.times)):
        assert_close(Float64(got.times[key]), Float64(expected.times[key]))
    assert_equal(len(got.values), len(expected.values))
    for key in range(len(got.values)):
        assert_close(Float64(got.values[key]), Float64(expected.values[key]))


def test_both_files_read_to_the_same_scene() raises:
    var rig = Rig()
    var ours = Loaded(rig.export())
    var theirs = Loaded(reference())
    # The lights.
    assert_equal(len(ours.scene.lights), 3)
    assert_equal(len(theirs.scene.lights), 3)
    for slot in range(3):
        ref a = ours.scene.lights[slot]
        ref b = theirs.scene.lights[slot]
        assert_equal(a.kind, b.kind)
        assert_equal(a.color.r, b.color.r)
        assert_equal(a.color.g, b.color.g)
        assert_equal(a.color.b, b.color.b)
        assert_equal(a.intensity, b.intensity)
        assert_equal(a.distance, b.distance)
        assert_close(Float64(a.angle.to(RADIAN)), Float64(b.angle.to(RADIAN)))
        assert_close(Float64(a.penumbra), Float64(b.penumbra))
    # The perspective camera is the same; three.js's orthographic box
    # reads back twice as wide as it was.
    var eye = ours.model.cameras[0].perspective()
    var lens = theirs.model.cameras[0].perspective()
    assert_close(Float64(eye.fov.to(DEGREE)), Float64(lens.fov.to(DEGREE)))
    assert_equal(eye.aspect, lens.aspect)
    assert_equal(eye.far.to(METER), lens.far.to(METER))
    var box = ours.model.cameras[1].orthographic()
    var flat = theirs.model.cameras[1].orthographic()
    assert_equal(box.right.to(METER) * 2, flat.right.to(METER))
    assert_equal(box.top.to(METER) * 2, flat.top.to(METER))
    # The morph targets, their names and the weights.
    ref face = ours.scene.meshes[0]
    ref other = theirs.scene.meshes[0]
    assert_equal(face.morph_influence(0), other.morph_influence(0))
    assert_equal(face.morph_influence(1), other.morph_influence(1))
    ref shape = ours.assets.geometries.get(face.geometry)
    ref form = theirs.assets.geometries.get(other.geometry)
    assert_equal(shape.morph_names[0], form.morph_names[0])
    assert_equal(shape.morph_names[1], "frown")
    for target in range(2):
        for lane in range(9):
            assert_equal(
                shape.morph_positions[target].data[lane],
                form.morph_positions[target].data[lane],
            )
    # The skin.
    ref arm = ours.scene.skinned_meshes[0]
    ref limb = theirs.scene.skinned_meshes[0]
    assert_equal(arm.skeleton.bone_count(), 2)
    for bone in range(2):
        assert_true(
            arm.skeleton.bones[bone].inverse_bind
            == limb.skeleton.bones[bone].inverse_bind
        )
    # The instances.
    ref crowd = ours.scene.instanced_meshes[0]
    ref many = theirs.scene.instanced_meshes[0]
    for slot in range(2):
        for element in range(16):
            assert_close(
                Float64(crowd.matrices[slot].elements[element]),
                Float64(many.matrices[slot].elements[element]),
            )
        assert_equal(crowd.color_at(slot).r, many.color_at(slot).r)
        assert_equal(crowd.color_at(slot).b, many.color_at(slot).b)
    # The lines and the points.
    assert_equal(len(ours.scene.lines), 3)
    for slot in range(3):
        assert_equal(ours.scene.lines[slot].mode, theirs.scene.lines[slot].mode)
    assert_equal(len(ours.scene.points), len(theirs.scene.points))
    # The animation, track by track, the merged weights among them.
    ref got = ours.model.animations[0]
    ref expected = theirs.model.animations[0]
    assert_equal(len(got.tracks), 5)
    assert_equal(len(expected.tracks), 5)
    for slot in range(5):
        assert_same_track(got.tracks[slot], expected.tracks[slot])


def test_a_round_trip_keeps_what_was_written() raises:
    for container in [GLTF_EMBEDDED, GLB]:
        check_round_trip(container)


def check_round_trip(container: GltfContainer) raises:
    """Assert the rig written in a container reads back as it was."""
    var rig = Rig()
    var files = export_gltf(
        rig.scene,
        rig.assets,
        container,
        cameras=rig.cameras,
        animations=rig.clips,
    )
    var text = String(unsafe_from_utf8=files.document)
    var bin = List[UInt8]()
    if container == GLB:
        var parts = split_glb(files.document)
        text = parts[0]
        bin = parts[1].copy()
    var back = Loaded(text, bin)
    ref scene = back.scene
    # Every light as it was, the spot light's cone and penumbra too.
    for slot in range(3):
        ref a = scene.lights[slot]
        ref b = rig.scene.lights[slot]
        assert_equal(a.kind, b.kind)
        assert_equal(a.color.r, b.color.r)
        assert_equal(a.color.g, b.color.g)
        assert_equal(a.intensity, b.intensity)
        assert_equal(a.distance, b.distance)
    assert_close(Float64(scene.lights[2].penumbra), 0.2)
    assert_close(Float64(scene.lights[2].angle.to(RADIAN)), 0.5)
    # The cameras.
    var eye = back.model.cameras[0].perspective()
    assert_close(Float64(eye.fov.to(DEGREE)), 50)
    assert_equal(eye.aspect, 1.5)
    assert_equal(back.model.cameras[0].name, "eye")
    var box = back.model.cameras[1].orthographic()
    assert_equal(box.left.to(METER), -2)
    assert_equal(box.top.to(METER), 1)
    assert_equal(box.far.to(METER), 20)
    # The morph targets and their weights.
    assert_equal(scene.meshes[0].morph_influence(1), 0.5)
    ref shape = back.assets.geometries.get(scene.meshes[0].geometry)
    assert_equal(shape.morph_names[0], "smile")
    assert_equal(shape.morph_positions[1].data[4], -1)
    # The skin: the tip bone's inverse bind moves down one meter.
    ref bones = scene.skinned_meshes[0].skeleton.bones
    assert_equal(bones[1].inverse_bind.elements[13], -1)
    ref limb = back.assets.geometries.get(scene.skinned_meshes[0].geometry)
    assert_equal(limb.attribute_view(String(SKIN_INDEX)).data[4], 1)
    assert_equal(limb.attribute_view(String(SKIN_WEIGHT)).data[0], 1)
    # The instances.
    ref crowd = scene.instanced_meshes[0]
    assert_close(Float64(crowd.matrices[1].elements[0]), 2)
    assert_close(Float64(crowd.matrices[1].elements[13]), 1)
    assert_equal(crowd.color_at(1).b, 255)
    # The lines and the points.
    assert_equal(scene.lines[0].mode, SEGMENTS)
    assert_equal(scene.lines[1].mode, LOOP)
    assert_equal(scene.lines[2].mode, STRIP)
    assert_equal(len(scene.points), 1)
    ref wire = back.assets.geometries.get(scene.lines[0].geometry)
    assert_equal(wire.attribute_view(String(POSITION)).data[10], 9)
    # The animation: the node tracks as written, and the morph tracks
    # merged at every key of either.
    ref clip = back.model.animations[0]
    assert_equal(clip.name, "move")
    assert_same_track(clip.tracks[0], rig.clips[0].tracks[0])
    assert_same_track(clip.tracks[1], rig.clips[0].tracks[1])
    assert_same_track(clip.tracks[2], rig.clips[0].tracks[2])
    ref smile = clip.tracks[3]
    assert_equal(len(smile.times), 4)
    assert_close(Float64(smile.times[1]), 0.5)
    assert_close(Float64(smile.values[0]), 1)
    assert_close(Float64(smile.values[2]), 0.5)
    ref frown = clip.tracks[4]
    assert_close(Float64(frown.values[1]), 0.5)
    assert_close(Float64(frown.values[3]), 1)


# --- choices and refusals ---------------------------------------------------


struct Small(Movable):
    """A scene of a few nodes, and what they draw with."""

    var scene: Scene
    var assets: Assets
    var white: MaterialId
    var shape: GeometryId
    var morphed: GeometryId
    var bendy: GeometryId
    var first: NodeId
    var second: NodeId

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        self.white = self.assets.materials.add(
            Material(Color(255, 255, 255), kind=BASIC)
        )
        self.shape = self.assets.geometries.add(triangle())
        var morph = triangle()
        morph.add_morph_target(
            BufferAttribute([Float32(0), 1, 0, 1, 1, 0, 0, 1, 0], 3)
        )
        morph.add_morph_target(
            BufferAttribute([Float32(1), 0, 0, 1, 0, 0, 0, 1, 1], 3)
        )
        self.morphed = self.assets.geometries.add(morph^)
        self.bendy = self.assets.geometries.add(skinned_triangle())
        self.first = self.scene.add(named("first"))
        self.second = self.scene.add(named("second"))

    def mesh(mut self, var node: NodeId, var geometry: GeometryId) raises:
        """Draw a geometry at a node."""
        self.scene.add_mesh(Mesh(geometry, self.white, node))

    def json(
        self,
        cameras: CameraList = CameraList(),
        animations: List[AnimationClip] = List[AnimationClip](),
    ) raises -> JsonDocument:
        """Return the scene's file, parsed."""
        var files = export_gltf(
            self.scene,
            self.assets,
            cameras=cameras,
            animations=animations,
        )
        return parse_json(String(unsafe_from_utf8=files.document))

    def refuses(
        self,
        expected: String,
        cameras: CameraList = CameraList(),
        animations: List[AnimationClip] = List[AnimationClip](),
    ) raises:
        """Assert the scene is refused with a message holding `expected`."""
        try:
            _ = export_gltf(
                self.scene,
                self.assets,
                cameras=cameras,
                animations=animations,
            )
        except reason:
            assert_true(expected in String(reason), String(reason))
            return
        raise Error("the scene was written")


def clip(
    var tracks: List[KeyframeTrack], name: String = ""
) raises -> List[AnimationClip]:
    """Return one clip of the tracks."""
    return [AnimationClip(name, tracks^)]


def weights_output(document: JsonDocument) raises -> Int:
    """Return the accessor of the first animation's first sampler output."""
    return document.integer(
        at(
            document,
            document.root(),
            ["animations", "0", "samplers", "0", "output"],
        )
    )


def test_morph_targets_are_written_as_offsets_with_names() raises:
    var small = Small()
    var absolute = triangle()
    absolute.set_attribute(
        String(NORMAL),
        BufferAttribute([Float32(0), 0, 1, 0, 0, 1, 0, 0, 1], 3),
    )
    absolute.add_morph_target(
        BufferAttribute([Float32(0), 2, 0, 1, 0, 0, 0, 1, 0], 3),
        BufferAttribute([Float32(0), 1, 1, 0, 0, 1, 0, 0, 1], 3),
    )
    absolute.morph_names = [""]
    var id = small.assets.geometries.add(absolute^)
    small.mesh(small.first, id)
    var files = export_gltf(small.scene, small.assets)
    var back = Loaded(String(unsafe_from_utf8=files.document))
    ref read = back.assets.geometries.get(back.scene.meshes[0].geometry)
    assert_true(read.morph_relative)
    # The target less the base, positions and normals.
    assert_equal(read.morph_positions[0].data[1], 2)
    assert_equal(read.morph_positions[0].data[3], 0)
    assert_equal(read.morph_normals[0].data[1], 1)
    assert_equal(read.morph_normals[0].data[2], 0)
    # A target with no name is named by its index, as three.js names it.
    assert_equal(read.morph_names[0], "0")
    assert_equal(target_name(read, 3), "3")
    # Normals to take the base off need normals.
    var bare = Small()
    var loose = triangle()
    loose.add_morph_target(
        BufferAttribute([Float32(0), 2, 0, 1, 0, 0, 0, 1, 0], 3),
        BufferAttribute([Float32(0), 1, 1, 0, 0, 1, 0, 0, 1], 3),
    )
    var lost = bare.assets.geometries.add(loose^)
    bare.mesh(bare.first, lost)
    bare.refuses("morph normals need its normals")


def test_meshes_on_one_node_share_their_morph_targets() raises:
    # Two meshes that wear one set of weights are one glTF mesh.
    var small = Small()
    small.mesh(small.first, small.morphed)
    small.mesh(small.first, small.morphed)
    small.scene.meshes[0].set_morph_influence(1, 0.5)
    small.scene.meshes[1].set_morph_influence(1, 0.5)
    var document = small.json()
    var weights = at(document, document.root(), ["meshes", "0", "weights"])
    assert_equal(document.number(document.at(weights, 1)), 0.5)
    # Two sets of weights, or two numbers of targets, are refused.
    small.scene.meshes[1].set_morph_influence(0, 0.25)
    small.refuses("one set of morph")
    var mixed = Small()
    mixed.mesh(mixed.first, mixed.morphed)
    mixed.mesh(mixed.first, mixed.shape)
    mixed.refuses("as many morph")
    # A line on a node of morph targets writes zero weights.
    var drawn = Small()
    drawn.scene.add_line(Line(drawn.morphed, drawn.white, drawn.first))
    var lined = drawn.json()
    var zero = at(lined, lined.root(), ["meshes", "0", "weights"])
    assert_equal(lined.number(lined.at(zero, 0)), 0)


def test_morph_tracks_merge_as_three_js_merges_them() raises:
    # Steps merge as steps; a key within a millisecond is the same key.
    var small = Small()
    small.mesh(small.first, small.morphed)
    var tracks = List[KeyframeTrack]()
    tracks.append(
        KeyframeTrack(
            morph_target(MeshIndex(0), 0), seconds([1, 2]), [1, 0], STEP
        )
    )
    tracks.append(
        KeyframeTrack(
            morph_target(MeshIndex(0), 1), seconds([0, 1.0005, 3]), [0.5, 1, 0]
        )
    )
    var document = small.json(animations=clip(tracks^))
    var sampler = at(
        document, document.root(), ["animations", "0", "samplers", "0"]
    )
    assert_equal(
        document.string(document.get(sampler, "interpolation")), "STEP"
    )
    var input = document.integer(document.get(sampler, "input"))
    var times = at(document, document.root(), ["accessors", String(input)])
    assert_equal(document.integer(document.get(times, "count")), 4)
    assert_equal(document.number(at(document, times, ["min", "0"])), 0)
    assert_equal(document.number(at(document, times, ["max", "0"])), 3)
    var back = Loaded(
        String(
            unsafe_from_utf8=export_gltf(
                small.scene,
                small.assets,
                animations=clip(
                    [
                        KeyframeTrack(
                            morph_target(MeshIndex(0), 0),
                            seconds([1, 2]),
                            [1, 0],
                            STEP,
                        ),
                        KeyframeTrack(
                            morph_target(MeshIndex(0), 1),
                            seconds([0, 1.0005, 3]),
                            [0.5, 1, 0],
                        ),
                    ]
                ),
            ).document
        )
    )
    ref first = back.model.animations[0].tracks[0]
    ref second = back.model.animations[0].tracks[1]
    # Keys at 0, 1, 2 and 3: the step track's value before its first key
    # is its first, and the linear track's at 2 lies between its keys.
    assert_equal(len(first.times), 4)
    assert_equal(first.values[0], 1)
    assert_equal(first.values[3], 0)
    assert_close(Float64(second.values[1]), 1)
    assert_almost_equal(Float64(second.values[2]), 0.5, atol=1e-3)
    # A smooth track is written linear; cubic splines at one set of times
    # merge with their tangents.
    var smooth = Small()
    smooth.mesh(smooth.first, smooth.morphed)
    var curves = List[KeyframeTrack]()
    curves.append(
        KeyframeTrack(
            morph_target(MeshIndex(0), 0), seconds([0, 1]), [0, 1], SMOOTH
        )
    )
    var written = smooth.json(animations=clip(curves^))
    assert_equal(
        written.string(
            at(
                written,
                written.root(),
                ["animations", "0", "samplers", "0", "interpolation"],
            )
        ),
        "LINEAR",
    )
    var cubic = Small()
    cubic.mesh(cubic.first, cubic.morphed)
    var splines = List[KeyframeTrack]()
    for target in range(2):
        splines.append(
            KeyframeTrack(
                morph_target(MeshIndex(0), target),
                seconds([0, 1]),
                in_tangents=[Float32(target), 1],
                values=[Float32(0), 1],
                out_tangents=[Float32(2), 3],
            )
        )
    var spline = cubic.json(animations=clip(splines^))
    var output = weights_output(spline)
    var values = at(spline, spline.root(), ["accessors", String(output)])
    # Each key: two in-tangents, two weights, two out-tangents.
    assert_equal(spline.integer(spline.get(values, "count")), 12)
    assert_equal(
        spline.string(
            at(
                spline,
                spline.root(),
                ["animations", "0", "samplers", "0", "interpolation"],
            )
        ),
        "CUBICSPLINE",
    )


def test_a_cubic_spline_merges_only_with_cubic_splines_at_its_times() raises:
    var small = Small()
    small.mesh(small.first, small.morphed)
    var curve = KeyframeTrack(
        morph_target(MeshIndex(0), 0),
        seconds([0, 1]),
        in_tangents=[Float32(0), 0],
        values=[Float32(0), 1],
        out_tangents=[Float32(0), 0],
    )
    var late = KeyframeTrack(
        morph_target(MeshIndex(0), 1),
        seconds([0, 2]),
        in_tangents=[Float32(0), 0],
        values=[Float32(0), 1],
        out_tangents=[Float32(0), 0],
    )
    var plain = KeyframeTrack(
        morph_target(MeshIndex(0), 1), seconds([0, 1]), [0, 1]
    )
    var first = List[KeyframeTrack]()
    first.append(curve.copy())
    first.append(plain.copy())
    small.refuses("cubic spline merges", animations=clip(first^))
    var second = List[KeyframeTrack]()
    second.append(plain.copy())
    second.append(curve.copy())
    small.refuses("cubic spline merges", animations=clip(second^))
    var third = List[KeyframeTrack]()
    third.append(curve.copy())
    third.append(late.copy())
    small.refuses("cubic spline merges", animations=clip(third^))


def test_node_tracks_are_written_and_the_rest_left_out() raises:
    var small = Small()
    small.mesh(small.first, small.morphed)
    var hidden = Object3D()
    hidden.visible = False
    var gone = small.scene.add(hidden^)
    small.mesh(gone, small.morphed)
    var tracks = List[KeyframeTrack]()
    tracks.append(KeyframeTrack(small.first, VISIBLE, seconds([0, 1]), [1, 1]))
    tracks.append(
        KeyframeTrack(
            node_target(small.first, SCALE),
            seconds([0, 1]),
            in_tangents=[Float32(0), 0, 0, 0, 0, 0],
            values=[Float32(1), 1, 1, 2, 2, 2],
            out_tangents=[Float32(0), 0, 0, 1, 1, 1],
        )
    )
    tracks.append(
        KeyframeTrack(gone, MOVE, seconds([0, 1]), [1, 2, 3, 1, 2, 3])
    )
    tracks.append(
        KeyframeTrack(morph_target(MeshIndex(1), 0), seconds([0, 1]), [1, 1])
    )
    tracks.append(
        KeyframeTrack(
            material_target(small.white, MATERIAL_OPACITY),
            seconds([0, 1]),
            [1, 1],
        )
    )
    var document = small.json(animations=clip(tracks^))
    var animation = at(document, document.root(), ["animations", "0"])
    # An unnamed clip is named by its place, as three.js names it.
    assert_equal(document.string(document.get(animation, "name")), "clip_0")
    assert_equal(document.length(document.get(animation, "channels")), 1)
    var sampler = at(document, animation, ["samplers", "0"])
    assert_equal(
        document.string(document.get(sampler, "interpolation")), "CUBICSPLINE"
    )
    var output = document.integer(document.get(sampler, "output"))
    var values = at(document, document.root(), ["accessors", String(output)])
    assert_equal(document.integer(document.get(values, "count")), 6)
    assert_equal(document.string(document.get(values, "type")), "VEC3")
    # A clip left with no channel is not written.
    var empty = List[KeyframeTrack]()
    empty.append(KeyframeTrack(gone, MOVE, seconds([0, 1]), [1, 2, 3, 1, 2, 3]))
    var none = small.json(animations=clip(empty^, "nothing"))
    assert_false(none.has(none.root(), "animations"))
    # A morph track of a skinned mesh is a weights channel at its node.
    var bent = Small()
    var body = skinned_triangle()
    body.add_morph_target(
        BufferAttribute([Float32(0), 1, 0, 0, 0, 0, 0, 0, 0], 3)
    )
    var id = bent.assets.geometries.add(body^)
    bent.scene.add_skinned_mesh(
        SkinnedMesh(
            id,
            bent.white,
            bent.first,
            Skeleton(
                [Bone(bent.first, Matrix4()), Bone(bent.second, Matrix4())]
            ),
        )
    )
    var skinned = List[KeyframeTrack]()
    skinned.append(
        KeyframeTrack(
            skinned_morph_target(SkinnedMeshIndex(0), 0),
            seconds([0, 1]),
            [1, 1],
        )
    )
    var flexed = bent.json(animations=clip(skinned^))
    assert_equal(
        flexed.string(
            at(
                flexed,
                flexed.root(),
                ["animations", "0", "channels", "0", "target", "path"],
            )
        ),
        "weights",
    )


def test_bad_tracks_are_refused() raises:
    var small = Small()
    small.mesh(small.first, small.morphed)
    var far = List[KeyframeTrack]()
    far.append(
        KeyframeTrack(NodeId(9), MOVE, seconds([0, 1]), [1, 2, 3, 1, 2, 3])
    )
    small.refuses("a track names a node", animations=clip(far^))
    var missing = List[KeyframeTrack]()
    missing.append(
        KeyframeTrack(morph_target(MeshIndex(5), 0), seconds([0, 1]), [1, 1])
    )
    small.refuses("names a mesh that is not there", animations=clip(missing^))
    var negative = List[KeyframeTrack]()
    negative.append(
        KeyframeTrack(morph_target(MeshIndex(0), 0), seconds([0, 1]), [1, 1])
    )
    negative[0].target.index = -1
    small.refuses("names a mesh that is not there", animations=clip(negative^))
    var skin = List[KeyframeTrack]()
    skin.append(
        KeyframeTrack(
            skinned_morph_target(SkinnedMeshIndex(3), 0),
            seconds([0, 1]),
            [1, 1],
        )
    )
    small.refuses("names a mesh that is not there", animations=clip(skin^))
    var unskinned = List[KeyframeTrack]()
    unskinned.append(
        KeyframeTrack(
            skinned_morph_target(SkinnedMeshIndex(0), 0),
            seconds([0, 1]),
            [1, 1],
        )
    )
    unskinned[0].target.index = -2
    small.refuses("names a mesh that is not there", animations=clip(unskinned^))
    var past = List[KeyframeTrack]()
    past.append(
        KeyframeTrack(morph_target(MeshIndex(0), 4), seconds([0, 1]), [1, 1])
    )
    small.refuses("names a target", animations=clip(past^))


def test_lights_are_written_as_three_js_writes_them() raises:
    var small = Small()
    # An ambient light has no place in glTF, and is left out.
    small.scene.add_light(ambient_light(Color(10, 10, 10)))
    small.scene.add_light(point_light(Color(255, 255, 255), small.first))
    var hidden = Object3D()
    hidden.visible = False
    var gone = small.scene.add(hidden^)
    small.scene.add_light(point_light(Color(255, 255, 255), gone))
    var document = small.json()
    var lights = at(
        document,
        document.root(),
        ["extensions", "KHR_lights_punctual", "lights"],
    )
    assert_equal(document.length(lights), 1)
    var lamp = document.at(lights, 0)
    # No cutoff writes no range.
    assert_false(document.has(lamp, "range"))
    assert_equal(document.string(document.get(lamp, "name")), "first")
    var unnamed = Small()
    var plain = unnamed.scene.add(Object3D())
    unnamed.scene.add_light(point_light(Color(255, 255, 255), plain))
    var bare = unnamed.json()
    assert_false(
        bare.has(
            at(
                bare,
                bare.root(),
                ["extensions", "KHR_lights_punctual", "lights", "0"],
            ),
            "name",
        )
    )
    # Two lights on one node, a light on no node, and a light its own
    # checks refuse.
    small.scene.add_light(spot_light(Color(255, 255, 255), small.first))
    small.refuses("two ride one")
    var lost = Small()
    lost.scene.add_light(directional_light(Color(255, 255, 255), NO_PARENT))
    lost.refuses("a light names a node")
    var odd = Small()
    var broken = point_light(Color(255, 255, 255), odd.first)
    broken.kind = LightKind(99)
    odd.scene.add_light(broken)
    odd.refuses("none of the named")
    var dim = Small()
    var dark = point_light(Color(255, 255, 255), dim.first)
    dark.intensity = -1
    dim.scene.add_light(dark)
    dim.refuses("intensity")


def test_cameras_are_written_as_three_js_writes_them() raises:
    var small = Small()
    var cameras = CameraList()
    var lens = PerspectiveCamera(
        Angle(60.0, DEGREE), 2, Length(1.0, METER), Length(9.0, METER)
    )
    var box = OrthographicCamera(
        Length(-1.0, METER),
        Length(1.0, METER),
        Length(1.0, METER),
        Length(-1.0, METER),
        Length(0.0, METER),
        Length(9.0, METER),
    )
    var hidden = Object3D()
    hidden.visible = False
    var gone = small.scene.add(hidden^)
    var plain = small.scene.add(Object3D())
    lens.attach(gone)
    cameras.perspective.append(lens)
    box.attach(gone)
    cameras.orthographic.append(box.copy())
    box.attach(plain)
    cameras.orthographic.append(box.copy())
    var unnamed = small.scene.add(Object3D())
    var seen = lens
    seen.attach(unnamed)
    cameras.perspective.append(seen)
    var document = small.json(cameras)
    # The hidden node's cameras are left out, and an unnamed node writes an
    # unnamed camera.
    var written = document.get(document.root(), "cameras")
    assert_equal(document.length(written), 2)
    assert_false(document.has(document.at(written, 0), "name"))
    assert_false(document.has(document.at(written, 1), "name"))
    _ = cameras.perspective.pop()
    # Two cameras on one node, whichever kinds they are.
    var two = cameras.copy()
    lens.attach(plain)
    two.perspective.append(lens)
    small.refuses("two ride one", two)
    var three = CameraList()
    three.perspective.append(lens)
    three.perspective.append(lens)
    small.refuses("two ride one", three)
    # A camera on no node, and a box off its axis.
    var nowhere = CameraList()
    var loose = PerspectiveCamera(
        Angle(60.0, DEGREE), 2, Length(1.0, METER), Length(9.0, METER)
    )
    nowhere.perspective.append(loose)
    small.refuses("a camera names a node", nowhere)
    var drifting = CameraList()
    var wide = OrthographicCamera(
        Length(-1.0, METER),
        Length(2.0, METER),
        Length(1.0, METER),
        Length(-1.0, METER),
        Length(0.0, METER),
        Length(9.0, METER),
    )
    wide.attach(plain)
    drifting.orthographic.append(wide^)
    small.refuses("centered on its axis", drifting)
    var tall = CameraList()
    var high = OrthographicCamera(
        Length(-1.0, METER),
        Length(1.0, METER),
        Length(2.0, METER),
        Length(-1.0, METER),
        Length(0.0, METER),
        Length(9.0, METER),
    )
    high.attach(plain)
    tall.orthographic.append(high^)
    small.refuses("centered on its axis", tall)


def crowd(small: Small, count: Int) raises -> InstancedMesh:
    """Return an instanced triangle at the first node."""
    return InstancedMesh(small.shape, small.white, small.first, count)


def test_instanced_meshes_on_one_node_are_one_mesh() raises:
    var small = Small()
    var one = crowd(small, 2)
    one.set_matrix_at(1, translation(0, 3, 0))
    var two = crowd(small, 2)
    two.set_matrix_at(1, translation(0, 3, 0))
    small.scene.add_instanced_mesh(one.copy())
    small.scene.add_instanced_mesh(two.copy())
    var document = small.json()
    var primitives = at(
        document, document.root(), ["meshes", "0", "primitives"]
    )
    assert_equal(document.length(primitives), 2)
    var attributes = at(
        document,
        document.root(),
        ["nodes", "0", "extensions", "EXT_mesh_gpu_instancing", "attributes"],
    )
    # No instance colors write no `_COLOR_0`.
    has_keys(document, attributes, ["TRANSLATION", "ROTATION", "SCALE"])
    var required = document.get(document.root(), "extensionsRequired")
    assert_equal(
        document.string(document.at(required, 0)), "EXT_mesh_gpu_instancing"
    )
    # Instances placed, counted or colored otherwise are refused.
    var moved = Small()
    moved.scene.add_instanced_mesh(one.copy())
    var other = two.copy()
    other.set_matrix_at(0, translation(1, 0, 0))
    moved.scene.add_instanced_mesh(other^)
    moved.refuses("place their instances alike")
    var counted = Small()
    counted.scene.add_instanced_mesh(one.copy())
    counted.scene.add_instanced_mesh(crowd(counted, 3))
    counted.refuses("place their instances alike")
    var tinted = Small()
    tinted.scene.add_instanced_mesh(one.copy())
    var painted = two.copy()
    painted.set_color_at(0, Color(255, 255, 255))
    tinted.scene.add_instanced_mesh(painted^)
    tinted.refuses("place their instances alike")
    var colored = Small()
    var red = one.copy()
    red.set_color_at(0, Color(255, 0, 0))
    var blue = one.copy()
    blue.set_color_at(0, Color(0, 0, 255))
    colored.scene.add_instanced_mesh(red^)
    colored.scene.add_instanced_mesh(blue^)
    colored.refuses("place their instances alike")
    # No instances at all, even two alike.
    var empty = Small()
    empty.scene.add_instanced_mesh(crowd(empty, 0))
    empty.scene.add_instanced_mesh(crowd(empty, 0))
    empty.refuses("no instances")
    # An instanced mesh and anything else on one node.
    var shared = Small()
    shared.scene.add_instanced_mesh(one.copy())
    shared.mesh(shared.first, shared.shape)
    shared.refuses("carries an instanced mesh carries nothing else")


def bent(
    small: Small, var skeleton: Skeleton, bind: Matrix4 = Matrix4()
) raises -> SkinnedMesh:
    """Return a skinned triangle at the first node."""
    return SkinnedMesh(
        small.bendy,
        small.white,
        small.first,
        skeleton^,
        Matrix4(copy=bind),
    )


def two_bones(small: Small) raises -> Skeleton:
    """Return a skeleton of the two nodes."""
    return Skeleton(
        [
            Bone(small.first, Matrix4()),
            Bone(small.second, translation(0, -1, 0)),
        ]
    )


def test_skinned_meshes_on_one_node_share_one_skin() raises:
    var small = Small()
    var bind = translation(0, 0, 2)
    small.scene.add_skinned_mesh(bent(small, two_bones(small), bind))
    small.scene.add_skinned_mesh(bent(small, two_bones(small), bind))
    var files = export_gltf(small.scene, small.assets)
    var back = Loaded(String(unsafe_from_utf8=files.document))
    assert_equal(len(back.scene.skinned_meshes), 2)
    # Each inverse bind matrix times the bind matrix, as three.js writes it.
    ref bones = back.scene.skinned_meshes[0].skeleton.bones
    assert_equal(bones[0].inverse_bind.elements[14], 2)
    assert_equal(bones[1].inverse_bind.elements[13], -1)
    # Another skeleton, another bind matrix or another bone count.
    var moved = Small()
    moved.scene.add_skinned_mesh(bent(moved, two_bones(moved)))
    moved.scene.add_skinned_mesh(bent(moved, two_bones(moved), bind))
    moved.refuses("share one skeleton")
    var fewer = Small()
    fewer.scene.add_skinned_mesh(bent(fewer, two_bones(fewer)))
    fewer.scene.add_skinned_mesh(
        bent(
            fewer,
            Skeleton(
                [
                    Bone(fewer.first, Matrix4()),
                    Bone(fewer.second, translation(0, -1, 0)),
                    Bone(fewer.first, Matrix4()),
                ]
            ),
        )
    )
    fewer.refuses("share one skeleton")
    var swapped = Small()
    swapped.scene.add_skinned_mesh(bent(swapped, two_bones(swapped)))
    swapped.scene.add_skinned_mesh(
        bent(
            swapped,
            Skeleton(
                [
                    Bone(swapped.second, Matrix4()),
                    Bone(swapped.second, translation(0, -1, 0)),
                ]
            ),
        )
    )
    swapped.refuses("share one skeleton")
    var turned = Small()
    turned.scene.add_skinned_mesh(bent(turned, two_bones(turned)))
    turned.scene.add_skinned_mesh(
        bent(
            turned,
            Skeleton(
                [Bone(turned.first, Matrix4()), Bone(turned.second, Matrix4())]
            ),
        )
    )
    turned.refuses("share one skeleton")


def test_a_skinned_node_carries_nothing_else() raises:
    var meshed = Small()
    meshed.scene.add_skinned_mesh(bent(meshed, two_bones(meshed)))
    meshed.mesh(meshed.first, meshed.shape)
    meshed.refuses("carries a skinned mesh carries nothing else")
    var crowded = Small()
    crowded.scene.add_skinned_mesh(bent(crowded, two_bones(crowded)))
    crowded.scene.add_instanced_mesh(crowd(crowded, 1))
    crowded.refuses("carries a skinned mesh carries nothing else")


def test_a_skin_glTF_cannot_hold_is_refused() raises:
    # A bone on a node that is not written, or not there.
    var hidden = Small()
    var gone = Object3D()
    gone.visible = False
    var away = hidden.scene.add(gone^)
    hidden.scene.add_skinned_mesh(
        bent(
            hidden,
            Skeleton([Bone(hidden.first, Matrix4()), Bone(away, Matrix4())]),
        )
    )
    hidden.refuses("a bone rides a node that is not written")
    var nowhere = Small()
    nowhere.scene.add_skinned_mesh(bent(nowhere, two_bones(nowhere)))
    nowhere.scene.skinned_meshes[0].skeleton.bones[1].node = NodeId(40)
    nowhere.refuses("a bone names a node")
    # Skin indices and weights glTF cannot hold.
    for trial in range(6):
        var small = Small()
        var shape = skinned_triangle()
        if trial == 0:
            shape.set_attribute(
                String(SKIN_INDEX),
                BufferAttribute(
                    [Float32(0), 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0], 4
                ),
            )
        elif trial == 1:
            shape.set_attribute(
                String(SKIN_INDEX),
                BufferAttribute(
                    [Float32(0), 0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0], 4
                ),
            )
        elif trial == 2:
            shape.set_attribute(
                String(SKIN_INDEX),
                BufferAttribute(
                    [Float32(0), 0, 0, 0, 0.5, 0, 0, 0, 1, 0, 0, 0], 4
                ),
            )
        elif trial == 3:
            shape.set_attribute(
                String(SKIN_INDEX),
                BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 1, 0, 0], 3),
            )
        elif trial == 4:
            shape.set_attribute(
                String(SKIN_WEIGHT),
                BufferAttribute([Float32(1), 0, 0, 1, 0, 0, 1, 0, 0], 3),
            )
        var id = small.assets.geometries.add(shape^)
        var mesh = SkinnedMesh(id, small.white, small.first, two_bones(small))
        small.scene.add_skinned_mesh(mesh^)
        if trial == 5:
            var bare = triangle()
            bare.set_attribute(
                String(SKIN_INDEX),
                BufferAttribute(
                    [Float32(0), 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4
                ),
            )
            small.scene.skinned_meshes[
                0
            ].geometry = small.assets.geometries.add(bare^)
            small.refuses("needs skinIndex and skinWeight")
            var empty = triangle()
            small.scene.skinned_meshes[
                0
            ].geometry = small.assets.geometries.add(empty^)
            small.refuses("needs skinIndex and skinWeight")
        elif trial >= 3:
            small.refuses("four bones a vertex")
        else:
            small.refuses("whole number that names a bone")


def test_lines_and_points_write_their_modes() raises:
    assert_equal(line_mode_code(SEGMENTS), MODE_LINES)
    assert_equal(line_mode_code(LOOP), MODE_LINE_LOOP)
    assert_equal(line_mode_code(STRIP), MODE_LINE_STRIP)
    # An indexed geometry is a triangle list here, not a line's.
    var small = Small()
    var indexed = triangle()
    indexed.set_index([0, 1, 2])
    small.scene.add_line(
        Line(small.assets.geometries.add(indexed^), small.white, small.first)
    )
    small.refuses("has no index")


def test_what_rides_a_node_that_is_not_there_is_refused() raises:
    # Each kind on a hidden node is left out with it.
    var small = Small()
    var hidden = Object3D()
    hidden.visible = False
    var gone = small.scene.add(hidden^)
    small.mesh(gone, small.shape)
    small.scene.add_skinned_mesh(
        SkinnedMesh(
            small.assets.geometries.add(skinned_triangle()),
            small.white,
            gone,
            two_bones(small),
        )
    )
    small.scene.add_instanced_mesh(
        InstancedMesh(small.shape, small.white, gone, 1)
    )
    small.scene.add_line(Line(small.shape, small.white, gone))
    small.scene.add_points(Points(small.shape, small.white, gone))
    var document = small.json()
    assert_false(document.has(document.root(), "meshes"))
    assert_false(document.has(document.root(), "skins"))
    # Each kind on a node that is not in the scene.
    small.scene.skinned_meshes[0].node = NodeId(50)
    small.refuses("a mesh names a node")
    small.scene.skinned_meshes[0].node = gone
    small.scene.instanced_meshes[0].node = NodeId(50)
    small.refuses("a mesh names a node")
    small.scene.instanced_meshes[0].node = gone
    small.scene.lines[0].node = NodeId(50)
    small.refuses("a line names a node")
    small.scene.lines[0].node = gone
    small.scene.points[0].node = NodeId(50)
    small.refuses("points names a node")


def test_a_bump_map_is_written_for_a_standard_or_physical_material() raises:
    var small = Small()
    var pixels = List[UInt8](length=16, fill=128)
    var bumps = small.assets.textures.add(
        Texture(2, 2, pixels^, color_space=SRGB)
    )
    var standard = small.assets.materials.add(
        standard_material(Color(255, 255, 255), bump_map=bumps, bump_scale=0.5)
    )
    var physical = standard_material(Color(255, 255, 255), bump_map=bumps)
    physical.kind = PHYSICAL
    var shiny = small.assets.materials.add(physical)
    var dull = small.assets.materials.add(
        Material(Color(255, 255, 255), kind=PHONG, bump_map=bumps)
    )
    small.scene.add_mesh(Mesh(small.shape, standard, small.first))
    small.scene.add_mesh(Mesh(small.shape, dull, small.second))
    var third = small.scene.add(Object3D())
    small.scene.add_mesh(Mesh(small.shape, shiny, third))
    var document = small.json()
    var materials = document.get(document.root(), "materials")
    var bump = at(
        document,
        document.at(materials, 0),
        ["extensions", "EXT_materials_bump"],
    )
    assert_equal(document.number(document.get(bump, "bumpFactor")), 0.5)
    assert_true(document.has(bump, "bumpTexture"))
    assert_false(document.has(document.at(materials, 1), "extensions"))
    assert_true(
        at(
            document,
            document.at(materials, 2),
            ["extensions", "EXT_materials_bump"],
        )
        != NO_NODE
    )
    # It reads back as three.js reads it: physical, with the map as data.
    var files = export_gltf(small.scene, small.assets)
    var back = Loaded(String(unsafe_from_utf8=files.document))
    var read = back.assets.materials.get(back.scene.meshes[0].material)
    assert_equal(read.kind, PHYSICAL)
    assert_equal(read.bump_scale, 0.5)
    assert_true(read.bump_map != NO_TEXTURE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def test_two_nodes_of_each_kind_are_written_apart() raises:
    var small = Small()
    small.scene.add_instanced_mesh(crowd(small, 1))
    small.scene.add_instanced_mesh(
        InstancedMesh(small.shape, small.white, small.second, 1)
    )
    var document = small.json()
    assert_equal(
        document.length(document.get(document.root(), "extensionsRequired")), 1
    )
    # Morph tracks of two nodes are two weights channels, and a key just
    # before one the channel has is that key.
    var morphs = Small()
    morphs.mesh(morphs.first, morphs.morphed)
    morphs.mesh(morphs.second, morphs.morphed)
    var tracks = List[KeyframeTrack]()
    tracks.append(
        KeyframeTrack(morph_target(MeshIndex(0), 0), seconds([0, 1]), [0, 1])
    )
    tracks.append(
        KeyframeTrack(morph_target(MeshIndex(1), 0), seconds([0, 1]), [1, 0])
    )
    tracks.append(
        KeyframeTrack(
            morph_target(MeshIndex(0), 1), seconds([0, 0.9995]), [1, 1]
        )
    )
    var written = morphs.json(animations=clip(tracks^))
    var animation = at(written, written.root(), ["animations", "0"])
    assert_equal(written.length(written.get(animation, "channels")), 2)
    var input = written.integer(
        at(written, animation, ["samplers", "0", "input"])
    )
    var times = at(written, written.root(), ["accessors", String(input)])
    assert_equal(written.integer(written.get(times, "count")), 2)
