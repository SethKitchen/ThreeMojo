# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`exporters.usdz` against three.js's `USDZExporter`.

`assets/usdz/three.json` holds the `.usda` texts that three.js 0.180
writes for one scene with two sets of options. The scene here is the
same scene. three.js makes a few objects of its own when it loads, so
its first ids are not zero: the scene here starts with as many unused
geometries, materials, textures and nodes.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    UV1,
    BufferGeometry,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.usdz import (
    UsdzOptions,
    export_usdz,
    usd_name,
    usda_geometry,
    usdz_files,
)
from loaders.json import parse_json
from loaders.object_loader import ObjectCameras
from loaders.zip import unzip
from materials.material import (
    BASIC,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
)
from math.matrix4 import translation
from math.quaternion import Quaternion
from math.vector2 import Vector2
from objects.mesh import Mesh
from render.framebuffer import Color
from render.png import decode as decode_png
from render.srgb import LINEAR, SRGB
from render.texture import BILINEAR, CLAMP, MIRROR, REPEAT, Texture, Wrap
from render.texture_store import TextureId
from units.si import DEGREE, METER, Angle, Length


def _texture(
    wrap: Wrap,
    channel: Int,
    srgb: Bool,
    repeat: Vector2,
    offset: Vector2,
    rotation: Float32,
) raises -> Texture:
    """Return a 2 by 2 texture with a transform."""
    var pixels = List[UInt8]()
    for i in range(16):
        pixels.append(UInt8(i * 16))
    var space = SRGB if srgb else LINEAR
    var texture = Texture(2, 2, pixels^, REPEAT, BILINEAR, space, False)
    # Set after, so that a test can make one that is not valid.
    texture.wrap = wrap
    texture.channel.value = channel
    texture.repeat = repeat
    texture.offset = offset
    texture.rotation = Angle(rotation)
    return texture^


struct _World(Movable):
    """The scene of the fixture's script, with its assets and cameras."""

    var scene: Scene
    var assets: Assets
    var cameras: ObjectCameras

    def __init__(out self, channel: Int = 1, wrap: Wrap = CLAMP) raises:
        """Build the scene, with `t1`'s channel and wrap."""
        self.scene = Scene()
        self.assets = Assets()
        self.cameras = ObjectCameras()
        # Unused ids, as three.js has made its own by the time it starts.
        for _ in range(2):
            _ = self.assets.geometries.add(BufferGeometry())
            _ = self.assets.materials.add(Material(Color(0, 0, 0)))
        for _ in range(5):
            _ = self.assets.textures.add(
                _texture(REPEAT, 0, True, Vector2(1, 1), Vector2(0, 0), 0)
            )
            var unused = self.scene.add(Object3D())
            self.scene.remove(unused)
        var t0 = self.assets.textures.add(
            _texture(REPEAT, 0, True, Vector2(2, 1), Vector2(0.5, 0.25), 0)
        )
        var t1 = self.assets.textures.add(
            _texture(wrap, channel, False, Vector2(1, 1), Vector2(0, 0), 0.5)
        )
        var t2 = self.assets.textures.add(
            _texture(MIRROR, 0, True, Vector2(0.5, 3), Vector2(0.1, 0.2), 0.25)
        )
        var m0 = Material(Color(hex=0x8040FF), kind=STANDARD)
        m0.roughness = 0.5
        m0.metalness = 0.25
        var m1 = Material(Color(hex=0xC0FFEE), kind=PHYSICAL)
        m1.map = t0
        m1.transparent = True
        m1.emissive = Color(hex=0xFF8000)
        m1.emissive_intensity = 2
        m1.emissive_map = t1
        m1.normal_map = t2
        m1.ao_map = t0
        m1.ao_map_intensity = 0.5
        m1.roughness_map = t1
        m1.metalness_map = t2
        m1.alpha_map = t0
        m1.clearcoat = 0.5
        m1.clearcoat_map = t1
        m1.clearcoat_roughness = 0.25
        m1.ior = 1.5
        var m2 = Material(Color(hex=0xFFFFFF), kind=BASIC)
        var m3 = Material(Color(hex=0x123456), kind=STANDARD)
        m3.map = t1
        m3.alpha_test = 0.5
        m3.emissive = Color(hex=0x010000)
        var m4 = Material(Color(hex=0xFFFFFF), kind=PHYSICAL)
        m4.clearcoat_roughness_map = t2
        m4.clearcoat = 0.75
        m4.opacity = 0.3
        m4.ior = 1.25
        var id0 = self.assets.materials.add(m0)
        var id1 = self.assets.materials.add(m1)
        var id2 = self.assets.materials.add(m2)
        var id3 = self.assets.materials.add(m3)
        var id4 = self.assets.materials.add(m4)
        var g0 = BufferGeometry()
        g0.set_attribute(
            String(POSITION),
            BufferAttribute(
                [
                    Float32(-1),
                    -1,
                    0,
                    1,
                    -1,
                    0,
                    1,
                    1,
                    0.1,
                    -1,
                    1,
                    Float32(1.0 / 3.0),
                ],
                3,
            ),
        )
        g0.set_attribute(
            String(NORMAL),
            BufferAttribute(
                [Float32(0), 0, 1, 0, 0, 1, 0, 0.6, 0.8, 1e-8, 0, 1], 3
            ),
        )
        g0.set_attribute(
            String(UV),
            BufferAttribute(
                [Float32(0), 0, 1, 0, 1, 1, 0.123456789, 0.987654321], 2
            ),
        )
        g0.set_attribute(
            String(COLOR),
            BufferAttribute(
                [Float32(1), 0, 0, 0, 1, 0, 0, 0, 1, 0.5, 0.25, 12345678], 3
            ),
        )
        g0.set_index([0, 1, 2, 0, 2, 3])
        var g1 = BufferGeometry()
        g1.set_attribute(
            String(POSITION),
            BufferAttribute([Float32(0), 0, 0, 2, 0, 0, 0, 3, -0.000001], 3),
        )
        g1.set_attribute(
            String(UV1), BufferAttribute([Float32(0), 0, 0.5, 0, 0, 1e-9], 2)
        )
        var box = self.assets.geometries.add(g0^)
        var tri = self.assets.geometries.add(g1^)
        var n0 = Object3D()
        n0.name = "Box"
        n0.set_position(1, 2, 3)
        n0.set_scale(2, 2, 2)
        var box0 = self.scene.add(n0^)
        var n1 = Object3D()
        n1.name = "Box"
        n1.quaternion = Quaternion(0, 1, 0, 0)
        var box1 = self.scene.attach(n1^, box0)
        var n2 = Object3D()
        n2.name = "9 lives!"
        n2.set_position(0.1, -0.5, 0)
        var lives = self.scene.add(n2^)
        var n3 = Object3D()
        n3.name = "Hidden"
        n3.visible = False
        var hidden = self.scene.add(n3^)
        var n4 = Object3D()
        n4.name = "Basic"
        var basic = self.scene.add(n4^)
        var n5 = Object3D()
        n5.name = "Under"
        _ = self.scene.attach(n5^, basic)
        var n6 = Object3D()
        n6.name = "Eye"
        n6.set_position(0, 0, 5)
        var eye = self.scene.add(n6^)
        var n7 = Object3D()
        var plan = self.scene.add(n7^)
        var n8 = Object3D()
        n8.matrix_auto_update = False
        n8.matrix = translation(4, 5, 6)
        var fixed = self.scene.add(n8^)
        var n9 = Object3D()
        n9.name = "Box"
        var last = self.scene.attach(n9^, fixed)
        self.scene.add_mesh(Mesh(box, id0, box0))
        self.scene.add_mesh(Mesh(box, id1, box1))
        self.scene.add_mesh(Mesh(tri, id3, lives))
        self.scene.add_mesh(Mesh(box, id0, hidden))
        self.scene.add_mesh(Mesh(box, id2, basic))
        self.scene.add_mesh(Mesh(tri, id4, last))
        var camera = PerspectiveCamera(
            Angle(50.0, DEGREE), 2, Length(0.1, METER), Length(100, METER)
        )
        camera.attach(eye)
        self.cameras.perspective.append(camera)
        var flat = OrthographicCamera(
            Length(-2, METER),
            Length(2, METER),
            Length(1, METER),
            Length(-1, METER),
            Length(0.5, METER),
            Length(50, METER),
        )
        flat.attach(plan)
        self.cameras.orthographic.append(flat^)


def _check(key: String, options: UsdzOptions) raises:
    """Assert that the files of the scene are three.js's."""
    var text = String(
        unsafe_from_utf8=open("assets/usdz/three.json", "r").read_bytes()
    )
    var doc = parse_json(text)
    var expected = doc.get(doc.root(), key)
    var world = _World()
    var files = usdz_files(world.scene, world.assets, world.cameras, options)
    var names = doc.get(expected, "names")
    assert_equal(len(files.names), doc.length(names))
    for i in range(len(files.names)):
        var name = doc.string(doc.at(names, i))
        assert_equal(files.names[i], name)
        if name.endswith(".usda"):
            assert_equal(files.text(name), doc.string(doc.get(expected, name)))


def test_files_match_three_js() raises:
    _check("default", UsdzOptions())
    var options = UsdzOptions()
    options.quick_look_compatible = True
    options.include_anchoring_properties = False
    options.only_visible = False
    options.anchoring_type = "image"
    options.plane_alignment = "vertical"
    _check("quick_look", options)


def test_archive() raises:
    var world = _World()
    var archive = export_usdz(world.scene, world.assets, world.cameras)
    var entries = unzip(archive)
    var files = usdz_files(world.scene, world.assets, world.cameras)
    assert_equal(len(entries), len(files.names))
    for i in range(len(entries)):
        assert_equal(entries[i].name, files.names[i])
        assert_true(entries[i].data == files.data[i])
    # Each texture is its own pixels, upside down as three.js draws them.
    var image = decode_png(files.data[len(files.data) - 1])
    assert_equal(image.width, 2)
    assert_equal(Int(image.pixels[0]), 8 * 16)
    # Each file's data starts at a multiple of 64 bytes.
    var at = 0
    for i in range(len(entries)):
        var name_length = Int(archive[at + 26]) | (Int(archive[at + 27]) << 8)
        var extra = Int(archive[at + 28]) | (Int(archive[at + 29]) << 8)
        var data = at + 30 + name_length + extra
        assert_equal(data % 64, 0)
        at = data + len(entries[i].data)


def test_a_node_of_several_things() raises:
    var scene = Scene()
    var assets = Assets()
    var cameras = ObjectCameras()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 0, 1, 0], 3),
    )
    var shape = assets.geometries.add(geometry^)
    var shiny = assets.materials.add(
        Material(Color(hex=0xFFFFFF), kind=STANDARD)
    )
    var plain = assets.materials.add(Material(Color(hex=0xFFFFFF), kind=BASIC))
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, shiny, node))
    scene.add_mesh(Mesh(shape, plain, node))
    var eye = PerspectiveCamera(
        Angle(90.0, DEGREE), 0.5, Length(1, METER), Length(10, METER)
    )
    eye.attach(node)
    cameras.perspective.append(eye)
    var flat = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(1, METER),
        Length(2, METER),
    )
    flat.attach(node)
    cameras.orthographic.append(flat^)
    # A map with neither transparency nor an alpha test.
    var pixels = List[UInt8](length=16, fill=255)
    var picture = assets.textures.add(
        Texture(2, 2, pixels^, REPEAT, BILINEAR, SRGB, False)
    )
    var mapped = Material(Color(hex=0xFFFFFF), kind=STANDARD)
    mapped.map = picture
    var painted = assets.materials.add(mapped)
    var other = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, painted, other))
    var text = usdz_files(scene, assets, cameras).text("model.usda")
    assert_true("inputs:diffuseColor.connect" in text)
    assert_false("opacityThreshold" in text)
    assert_false("outputs:a" in text)
    # The node is an Xform, with a mesh and two cameras under it; the
    # basic material's mesh is left out.
    assert_true('def Xform "Object"' in text)
    assert_true('def Xform "Object_0"' in text)
    assert_true('def Camera "Camera"' in text)
    assert_true('def Camera "Camera_0"' in text)
    assert_true("float horizontalAperture = 17.50000" in text)
    assert_false("Material_1" in text)
    # A hidden node's mesh is written when `only_visible` is off, and an
    # anchoring of no properties.
    var options = UsdzOptions()
    options.include_anchoring_properties = False
    assert_false(
        "anchoring"
        in usdz_files(scene, assets, cameras, options).text("model.usda")
    )


def test_empty() raises:
    # A scene with nothing in it, and a geometry with no vertices.
    var files = usdz_files(Scene(), Assets())
    assert_equal(len(files.names), 1)
    assert_true('def "Materials"\n{\n\n}' in files.text("model.usda"))
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    var text = usda_geometry(empty)
    assert_true("int[] faceVertexCounts = []" in text)
    assert_true("normal3f[] normals = []" in text)
    assert_true("texCoord2f[] primvars:st = []" in text)


def test_names() raises:
    assert_equal(usd_name("a b-c_1", "Object"), "abc_1")
    assert_equal(usd_name("7up", "Object"), "_7up")
    assert_equal(usd_name("日本", "Camera"), "Camera")


def test_refusals() raises:
    var scene = Scene()
    var assets = Assets()
    var two = BufferGeometry()
    two.set_attribute(
        String(POSITION), BufferAttribute([Float32(0), 0, 0, 1, 0, 0], 3)
    )
    with assert_raises(contains="whole triangles"):
        _ = usda_geometry(two)
    with assert_raises(contains="position attribute"):
        _ = usda_geometry(BufferGeometry())
    var shape = assets.geometries.add(two^)
    var shiny = assets.materials.add(
        Material(Color(hex=0xFFFFFF), kind=STANDARD)
    )
    scene.meshes.append(Mesh(shape, shiny, NodeId(3)))
    with assert_raises(contains="not in the scene"):
        _ = usdz_files(scene, assets)
    var before = Scene()
    var lost = Mesh(shape, shiny, NodeId(0))
    lost.node = NodeId(-1)
    before.meshes.append(lost)
    with assert_raises(contains="not in the scene"):
        _ = usdz_files(before, assets)
    var world = _World()
    with assert_raises(contains="no file named"):
        _ = usdz_files(world.scene, world.assets).text("nothing.usda")
    # A texture whose channel or wrap is not valid.
    var bad = _World(channel=9)
    with assert_raises(contains="channel is not valid"):
        _ = usdz_files(bad.scene, bad.assets)
    var odd = _World(wrap=Wrap(9))
    with assert_raises(contains="wrap is none"):
        _ = usdz_files(odd.scene, odd.assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
