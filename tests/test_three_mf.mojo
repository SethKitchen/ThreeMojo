# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.three_mf`.

`assets/3mf/fixture.3mf` holds every kind of mesh three.js's loader
builds: base materials with and without metallic display properties, a
color group, a texture group and the default material, placed by
components and build items with transforms. The values expected here are
what three.js 0.180's `ThreeMFLoader` gives for it in node.
`assets/3mf/prefixed.3mf` is the same model with its material elements
written with an `m:` prefix, and it must read the same. Smaller archives
are written inline with `zip_archive` to reach every refusal.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION, UV
from core.scene import Scene
from loaders.three_mf import (
    DEFAULT_MATERIAL_NAME,
    ThreeMfModel,
    js_key_order,
    parse_3mf,
    read_3mf,
    three_mf_transform,
    three_mf_unit,
    three_mf_wrap,
)
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from materials.material import PHONG, STANDARD
from render.framebuffer import Color
from render.texture import CLAMP, MIRROR, NEAREST, BILINEAR, REPEAT
from render.texture_store import NO_TEXTURE
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CENTIMETER, FOOT, INCH, METER, MILLIMETER

comptime TOLERANCE = Float64(1e-6)


def assert_list(got: List[Float32], want: List[Float64]) raises:
    """Assert two lists of numbers match within tolerance."""
    assert_equal(len(got), len(want))
    for index in range(len(want)):
        assert_almost_equal(Float64(got[index]), want[index], atol=TOLERANCE)


def assert_color(got: Color, r: UInt8, g: UInt8, b: UInt8) raises:
    """Assert an eight-bit color's channels."""
    assert_equal(got.r, r)
    assert_equal(got.g, g)
    assert_equal(got.b, b)


def assert_node(
    scene: Scene,
    model: ThreeMfModel,
    at: Int,
    name: String,
    p: List[Float64],
    q: List[Float64],
    s: List[Float64],
) raises:
    """Assert a placed node's name and transform."""
    var node = scene.get(model.nodes[at])
    assert_equal(node.name, name)
    assert_equal(model.node_names[at], name)
    assert_list([node.position.x, node.position.y, node.position.z], p)
    assert_list(
        [
            node.quaternion.x,
            node.quaternion.y,
            node.quaternion.z,
            node.quaternion.w,
        ],
        q,
    )
    assert_list([node.scale.x, node.scale.y, node.scale.z], s)


def check_fixture(path: String) raises:
    """Check a fixture against what three.js gives for it."""
    var scene = Scene()
    var assets = Assets()
    var model = read_3mf(path, scene, assets)
    assert_true(model.unit.to(METER) == 0.01)
    assert_equal(model.metadata_names, ["Title", "Designer"])
    assert_equal(model.metadata_values, ["Fixture & test", "ThreeMojo"])
    assert_equal(model.mesh_count, 9)
    assert_equal(model.first_mesh, 0)
    assert_equal(len(model.nodes), 13)
    var none: List[Float64] = [0, 0, 0]
    var one: List[Float64] = [1, 1, 1]
    var still: List[Float64] = [0, 0, 0, 1]
    assert_true(scene.get(model.nodes[0]).parent == model.root)
    assert_node(
        scene, model, 0, "assembly", [1, 2, 3], [0, 0, 0.707107, 0.707107], one
    )
    assert_node(scene, model, 1, "plain", [5, 0, 0], still, [2, 1, 1])
    assert_node(scene, model, 2, "plain", none, still, one)
    for at in [3, 8]:
        assert_node(scene, model, at, "multi", none, still, one)
    assert_true(scene.get(model.nodes[8]).parent == model.root)

    # The plain object: the whole mesh, indexed, with the default material.
    ref plain = assets.geometries.get(scene.meshes[0].geometry)
    assert_list(
        plain.clone_attribute(String(POSITION)).packed(),
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0],
    )
    assert_equal(plain.index, [0, 1, 2, 2, 1, 3])
    var default = assets.materials.get(scene.meshes[0].material)
    assert_true(default.kind == PHONG)
    assert_true(default.flat_shading)
    assert_color(default.color, 255, 255, 255)
    assert_equal(
        model.material_names,
        ["Red", "Blue glass", "", "", DEFAULT_MATERIAL_NAME],
    )

    # The multi object, twice: base materials, colors, and a texture.
    for first in [1, 5]:
        ref red = assets.geometries.get(scene.meshes[first].geometry)
        assert_false(red.is_indexed())
        assert_list(
            red.clone_attribute(String(POSITION)).packed(),
            [0, 0, 0, 0, 10, 0, 10, 0, 0, 5, 5, 5, 0, 10, 0, 0, 0, 10],
        )
        var red_material = assets.materials.get(scene.meshes[first].material)
        assert_true(red_material.kind == PHONG)
        assert_color(red_material.color, 255, 0, 0)
        assert_equal(red_material.opacity, 1)
        assert_equal(red_material.shininess, 30)

        ref glass = assets.geometries.get(scene.meshes[first + 1].geometry)
        assert_list(
            glass.clone_attribute(String(POSITION)).packed(),
            [0, 0, 0, 10, 0, 0, 0, 0, 10],
        )
        var glass_material = assets.materials.get(
            scene.meshes[first + 1].material
        )
        assert_true(glass_material.kind == STANDARD)
        assert_color(glass_material.color, 0x33, 0x66, 0xCC)
        assert_almost_equal(glass_material.opacity, 128.0 / 255, atol=1e-6)
        assert_false(glass_material.transparent)
        assert_almost_equal(glass_material.roughness, 0.6, atol=1e-6)
        assert_almost_equal(glass_material.metalness, 0.3, atol=1e-6)
        assert_true(glass_material.flat_shading)

        ref colored = assets.geometries.get(scene.meshes[first + 2].geometry)
        assert_list(
            colored.clone_attribute(String(POSITION)).packed(),
            [0, 0, 0, 0, 0, 10, 0, 10, 0, 10, 0, 0, 5, 5, 5, 0, 0, 10],
        )
        var gray = Float64(0.215861)
        var want: List[Float64] = [1, 0, 0, 0, 1, 0]
        for _ in range(12):
            want.append(gray)
        assert_list(colored.clone_attribute(String(COLOR)).packed(), want)
        var vertex_material = assets.materials.get(
            scene.meshes[first + 2].material
        )
        assert_true(vertex_material.vertex_colors)
        assert_true(vertex_material.kind == PHONG)

        ref textured = assets.geometries.get(scene.meshes[first + 3].geometry)
        assert_list(
            textured.clone_attribute(String(POSITION)).packed(),
            [10, 0, 0, 0, 10, 0, 0, 0, 10],
        )
        assert_list(
            textured.clone_attribute(String(UV)).packed(),
            [0, 0, 1, 0, 0.5, 1],
        )
        var map_material = assets.materials.get(
            scene.meshes[first + 3].material
        )
        assert_true(map_material.map != NO_TEXTURE)
        ref texture = assets.textures.get(map_material.map)
        assert_true(texture.wrap_s == MIRROR)
        assert_true(texture.mag_filter == NEAREST)
        assert_equal(texture.levels, 1)
        assert_equal(texture.width, 2)
        assert_equal(texture.pixels[0], 255)
        assert_equal(texture.pixels[5], 255)
    # Clones share their geometry and material, as three.js's do.
    assert_true(scene.meshes[1].geometry == scene.meshes[5].geometry)
    assert_true(scene.meshes[4].material == scene.meshes[8].material)
    assert_equal(len(model.geometries), 5)
    assert_equal(len(model.materials), 5)
    assert_equal(len(model.textures), 1)


def test_the_fixture_matches_three_js() raises:
    check_fixture("assets/3mf/fixture.3mf")


def test_prefixed_elements_read_by_local_name() raises:
    check_fixture("assets/3mf/prefixed.3mf")


def test_units() raises:
    assert_almost_equal(three_mf_unit("micron").to(METER), 1e-6)
    assert_almost_equal(three_mf_unit("millimeter").to(MILLIMETER), 1)
    assert_almost_equal(three_mf_unit("centimeter").to(CENTIMETER), 1)
    assert_almost_equal(three_mf_unit("inch").to(INCH), 1)
    assert_almost_equal(three_mf_unit("foot").to(FOOT), 1)
    assert_almost_equal(three_mf_unit("meter").to(METER), 1)
    with assert_raises(contains="unit"):
        _ = three_mf_unit("yard")


def test_wraps() raises:
    assert_true(three_mf_wrap("wrap") == REPEAT)
    assert_true(three_mf_wrap("mirror") == MIRROR)
    assert_true(three_mf_wrap("clamp") == CLAMP)
    assert_true(three_mf_wrap("none") == CLAMP)
    assert_true(three_mf_wrap("") == REPEAT)


def test_transform() raises:
    var matrix = three_mf_transform("1 2 3 4 5 6 7 8 9 10 11 12")
    assert_list(
        [
            matrix.elements[0],
            matrix.elements[1],
            matrix.elements[2],
            matrix.elements[3],
            matrix.elements[4],
            matrix.elements[8],
            matrix.elements[12],
            matrix.elements[13],
            matrix.elements[14],
            matrix.elements[15],
        ],
        [1, 2, 3, 0, 4, 7, 10, 11, 12, 1],
    )
    with assert_raises(contains="twelve"):
        _ = three_mf_transform("1 2 3")
    with assert_raises(contains="twelve"):
        _ = three_mf_transform("")
    with assert_raises(contains="not a number"):
        _ = three_mf_transform("1 2 x 4 5 6 7 8 9 10 11 12")
    with assert_raises(contains="not finite"):
        _ = three_mf_transform("1 2 1e99 4 5 6 7 8 9 10 11 12")


def test_javascript_key_order() raises:
    var keys: List[String] = [
        "b",
        "10",
        "2",
        "01",
        "",
        "12345678901",
        "4294967295",
        "4294967294",
        "0",
        "-1",
        "a",
    ]
    assert_equal(
        js_key_order(keys),
        [
            "0",
            "2",
            "10",
            "4294967294",
            "b",
            "01",
            "",
            "12345678901",
            "4294967295",
            "-1",
            "a",
        ],
    )


# ---------------------------------------------------------------------------
# Inline archives.

comptime RELS = (
    '<Relationships><Relationship Target="/3D/3dmodel.model"'
    ' Id="r" Type="t"/></Relationships>'
)


def entry(name: String, text: String) -> ZipEntry:
    """Return a stored entry holding a text."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return ZipEntry(name, ZIP_STORED, bytes^)


def model_text(resources: String, build: String) -> String:
    """Return a model part of some resources and a build."""
    return (
        "<model><resources>"
        + resources
        + "</resources><build>"
        + build
        + "</build></model>"
    )


comptime TRIANGLE_MESH = (
    '<mesh><vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0" z="0"/>'
    '<vertex x="0" y="1" z="0"/></vertices><triangles>'
)


def mesh_object(id: String, attributes: String, triangles: String) -> String:
    """Return an object of one triangle's vertices and some triangles."""
    return (
        '<object id="'
        + id
        + '" '
        + attributes
        + ">"
        + TRIANGLE_MESH
        + triangles
        + "</triangles></mesh></object>"
    )


def load(var entries: List[ZipEntry]) raises -> ThreeMfModel:
    """Read an archive of entries into a fresh scene."""
    var scene = Scene()
    var assets = Assets()
    return parse_3mf(zip_archive(entries), scene, assets)


def load_model(model: String) raises -> ThreeMfModel:
    """Read an archive of one root model."""
    return load([entry("_rels/.rels", RELS), entry("3D/3dmodel.model", model)])


def refused(model: String, message: String) raises:
    """Assert a root model is refused with a message."""
    with assert_raises(contains=message):
        _ = load_model(model)


def test_archive_structure_refusals() raises:
    with assert_raises(contains="relationship file"):
        _ = load([entry("3D/3dmodel.model", model_text("", ""))])
    with assert_raises(contains="no root model"):
        _ = load([entry("_rels/.rels", RELS)])
    with assert_raises(contains="names no model part"):
        _ = load(
            [
                entry(
                    "_rels/.rels",
                    (
                        "<Relationships><Relationship"
                        ' Target="/3D/x.png"/><Relationship'
                        ' Target="/3D/other.model"/></Relationships>'
                    ),
                ),
                entry("3D/3dmodel.model", model_text("", "")),
            ]
        )
    with assert_raises(contains="relationship file"):
        _ = load(List[ZipEntry]())
    with assert_raises(contains="names no model part"):
        _ = load(
            [
                entry("_rels/.rels", "<Relationships/>"),
                entry("3D/3dmodel.model", model_text("", "")),
            ]
        )
    refused("<scene/>", "is not a <model>")
    refused('<model unit="yard"/>', "unit")


def test_paths_are_sorted_by_role() raises:
    # A sub model, texture folders, and names near each pattern.
    var sub = model_text(
        mesh_object("7", "", '<triangle v1="0" v2="1" v3="2"/>'), ""
    )
    var model = load(
        [
            entry(
                "_rels/.rels",
                (
                    "<Relationships><Relationship"
                    ' Target="/3D/3dmodel.model"/><Relationship'
                    ' Target="/3D/sub/part.model"/></Relationships>'
                ),
            ),
            entry("a", ""),
            entry("abcdefghijk", ""),
            entry("_rels/.relx", ""),
            entry("3D/_rels/x", ""),
            entry("3D/_rels/aaaaaaaaaaaaa.txt", ""),
            entry("model.rels", ""),
            entry("3D/x.txt", ""),
            entry("x.model", ""),
            entry("3D/Texture/a.png", ""),
            entry("3D/Textures/b.png", ""),
            entry("3D/Other/c", ""),
            entry("3D/sub/part.model", sub),
            entry("3D/_rels/3dmodel.model.rels", "<Relationships/>"),
            entry(
                "3D/3dmodel.model",
                (
                    '<model unit="inch"><metadata'
                    ' name="Title">a</metadata><metadata'
                    ' name="Title">b</metadata><build><item'
                    ' objectid="7"/></build></model>'
                ),
            ),
        ]
    )
    assert_equal(model.metadata_values, ["b"])
    assert_equal(model.mesh_count, 1)
    assert_true(model.unit.to(INCH) > 0.999)


def test_a_model_with_no_resources_or_build_is_empty() raises:
    var model = load_model("<model/>")
    assert_equal(model.mesh_count, 0)
    assert_equal(len(model.nodes), 0)
    assert_equal(len(load_model(model_text("", "")).nodes), 0)


def test_empty_meshes_and_components_place_bare_nodes() raises:
    var model = load_model(
        model_text(
            (
                '<object id="1"><mesh/></object><object id="2"><components/>'
                "</object>"
            ),
            '<item objectid="1"/><item objectid="2"/>',
        )
    )
    assert_equal(len(model.nodes), 2)
    assert_equal(model.mesh_count, 0)


def test_object_refusals() raises:
    refused(model_text('<object id="1"/>', ""), "neither a <mesh>")
    refused(
        model_text(
            (
                '<object id="1"><mesh><vertices><vertex x="a" y="0" z="0"/>'
                "</vertices></mesh></object>"
            ),
            "",
        ),
        "not a number",
    )
    refused(
        model_text(
            mesh_object("1", "", '<triangle v1="0" v2="1" v3="3"/>'), ""
        ),
        "vertex index 3 is out of range",
    )
    refused(
        model_text(
            mesh_object("1", "", '<triangle v1="-1" v2="1" v3="2"/>'), ""
        ),
        "vertex index -1 is out of range",
    )
    refused(
        model_text(
            mesh_object("1", "", '<triangle v1="0" v2="1" v3="x"/>'), ""
        ),
        "not a whole number",
    )
    refused(
        model_text(
            mesh_object("1", 'pid="9"', '<triangle v1="0" v2="1" v3="2"/>'), ""
        ),
        "names no resource: 9",
    )
    refused(
        model_text(
            mesh_object("1", "", '<triangle v1="0" v2="1" v3="2"/>'),
            '<item objectid="2"/>',
        ),
        "no object has the id `2`",
    )
    refused(
        model_text(
            (
                '<object id="1"><components><component'
                ' objectid="1"/></components></object>'
            ),
            '<item objectid="1"/>',
        ),
        "nest too deep",
    )
    refused(
        model_text(
            mesh_object("1", "", '<triangle v1="0" v2="1" v3="2"/>'),
            '<item objectid="1" transform="1"/>',
        ),
        "twelve",
    )


comptime BASES = (
    '<basematerials id="1"><base name="a" displaycolor="#ff000033"/>'
    '<base name="b" displaycolor="red" displaypropertiesid="5"/>'
    '<base name="c" displaycolor="#123" displaypropertiesid="5"/>'
    '<base name="d" displaycolor="#GG0000"/>'
    '<base name="e" displaycolor="#FF0000Z0"/>'
    '<base name="f" displaycolor="#FF00000z"/>'
    '<base name="g" displaycolor="#FF0000 0"/></basematerials>'
    '<pbmetallicdisplayproperties id="5"><pbmetallic metallicness="1"'
    ' roughness="0"/><pbmetallic metallicness="0.5" roughness="0.25"/>'
    "</pbmetallicdisplayproperties>"
)


def test_base_materials_are_made_once_and_checked() raises:
    var scene = Scene()
    var assets = Assets()
    var text = model_text(
        BASES
        + mesh_object(
            "1", 'pid="1" pindex="0"', '<triangle v1="0" v2="1" v3="2"/>'
        )
        + mesh_object(
            "2",
            'pid="1"',
            '<triangle v1="0" v2="1" v3="2" p1="0"/>'
            + '<triangle v1="0" v2="2" v3="1" p1="1"/>',
        ),
        '<item objectid="1"/><item objectid="2"/>',
    )
    var model = parse_3mf(
        zip_archive(
            [entry("_rels/.rels", RELS), entry("3D/3dmodel.model", text)]
        ),
        scene,
        assets,
    )
    assert_equal(model.mesh_count, 3)
    # Object 2's first material is object 1's, made once.
    assert_true(scene.meshes[0].material == scene.meshes[1].material)
    assert_equal(model.material_names, ["a", "b"])
    var a = assets.materials.get(scene.meshes[0].material)
    assert_almost_equal(a.opacity, 0x33 / 255.0, atol=1e-6)
    var b = assets.materials.get(scene.meshes[2].material)
    assert_true(b.kind == STANDARD)
    assert_color(b.color, 255, 0, 0)
    assert_almost_equal(b.roughness, 0.25)

    refused(
        model_text(
            BASES
            + mesh_object(
                "1", 'pid="1"', '<triangle v1="0" v2="1" v3="2" p1="2"/>'
            ),
            "",
        ),
        "have no entry 2",
    )
    refused(
        model_text(
            BASES
            + mesh_object(
                "1", 'pid="1"', '<triangle v1="0" v2="1" v3="2" p1="3"/>'
            ),
            "",
        ),
        "hexadecimal",
    )
    refused(
        model_text(
            BASES
            + mesh_object(
                "1", 'pid="1"', '<triangle v1="0" v2="1" v3="2" p1="4"/>'
            ),
            "",
        ),
        "not hex",
    )
    refused(
        model_text(
            BASES
            + mesh_object(
                "1", 'pid="1"', '<triangle v1="0" v2="1" v3="2" p1="5"/>'
            ),
            "",
        ),
        "not hex",
    )
    refused(
        model_text(
            BASES
            + mesh_object(
                "1", 'pid="1"', '<triangle v1="0" v2="1" v3="2" p1="7"/>'
            ),
            "",
        ),
        "material index 7 is out of range",
    )
    refused(
        model_text(
            BASES
            + mesh_object(
                "1", 'pid="1"', '<triangle v1="0" v2="1" v3="2" p1="6"/>'
            ),
            "",
        ),
        "not hex",
    )
    refused(
        model_text(
            BASES
            + mesh_object("1", 'pid="1"', '<triangle v1="0" v2="1" v3="2"/>'),
            "",
        ),
        "material index is not a whole number",
    )


def test_a_hex_alpha_reads_every_digit() raises:
    var text = model_text(
        '<basematerials id="1"><base displaycolor="#000000aF"/>'
        '<base displaycolor="#00000009"/></basematerials>'
        + mesh_object(
            "1",
            'pid="1"',
            '<triangle v1="0" v2="1" v3="2" p1="0"/>'
            + '<triangle v1="0" v2="1" v3="2" p1="1"/>',
        ),
        '<item objectid="1"/>',
    )
    var scene = Scene()
    var assets = Assets()
    _ = parse_3mf(
        zip_archive(
            [entry("_rels/.rels", RELS), entry("3D/3dmodel.model", text)]
        ),
        scene,
        assets,
    )
    assert_almost_equal(
        assets.materials.get(scene.meshes[0].material).opacity,
        0xAF / 255.0,
        atol=1e-6,
    )
    assert_almost_equal(
        assets.materials.get(scene.meshes[1].material).opacity,
        9 / 255.0,
        atol=1e-6,
    )


def test_color_groups_fall_back_and_are_checked() raises:
    var colors = (
        '<colorgroup id="2"><color color="#ff0000"/><color color="#0000ff"/>'
        "</colorgroup>"
    )
    var text = model_text(
        colors
        + mesh_object(
            "1", 'pid="2" pindex="1"', '<triangle v1="0" v2="1" v3="2" p2="0"/>'
        ),
        '<item objectid="1"/>',
    )
    var scene = Scene()
    var assets = Assets()
    _ = parse_3mf(
        zip_archive(
            [entry("_rels/.rels", RELS), entry("3D/3dmodel.model", text)]
        ),
        scene,
        assets,
    )
    ref geometry = assets.geometries.get(scene.meshes[0].geometry)
    assert_list(
        geometry.clone_attribute(String(COLOR)).packed(),
        [0, 0, 1, 1, 0, 0, 0, 0, 1],
    )
    refused(
        model_text(
            colors
            + mesh_object(
                "1", 'pid="2"', '<triangle v1="0" v2="1" v3="2" p1="2"/>'
            ),
            "",
        ),
        "color index 2 is out of range",
    )
    refused(
        model_text(
            '<colorgroup id="2"/>'
            + mesh_object(
                "1", 'pid="2"', '<triangle v1="0" v2="1" v3="2" p1="0"/>'
            ),
            "",
        ),
        "color index 0 is out of range",
    )


def texture_archive(
    texture: String, triangles: String, rels: Bool
) raises -> List[ZipEntry]:
    """Return an archive of a textured object and a one-pixel image."""
    var png = Path("assets/brick.png").read_bytes()
    var entries: List[ZipEntry] = [
        entry("_rels/.rels", RELS),
        entry(
            "3D/3dmodel.model",
            model_text(
                texture
                + '<texture2dgroup id="4" texid="3"><tex2coord u="0" v="0"/>'
                + '<tex2coord u="1" v="1"/></texture2dgroup>'
                + mesh_object("1", 'pid="4"', triangles)
                + mesh_object("2", 'pid="4"', triangles),
                '<item objectid="1"/><item objectid="2"/>',
            ),
        ),
        ZipEntry("3D/Texture/t.png", ZIP_STORED, png^),
    ]
    if rels:
        entries.append(
            entry(
                "3D/_rels/3dmodel.model.rels",
                (
                    '<Relationships><Relationship Target="/3D/Texture/t.png"/>'
                    '<Relationship Target="/3D/Texture/none.png"/>'
                    "</Relationships>"
                ),
            )
        )
    return entries^


def test_textures_filters_and_refusals() raises:
    var corners = '<triangle v1="0" v2="1" v3="2" p1="0" p2="1" p3="0"/>'
    for filter in ["linear", "auto"]:
        var scene = Scene()
        var assets = Assets()
        var model = parse_3mf(
            zip_archive(
                texture_archive(
                    '<texture2d id="3" path="/3D/Texture/t.png" filter="'
                    + filter
                    + '"/>',
                    corners,
                    True,
                )
            ),
            scene,
            assets,
        )
        # Both objects share the one texture.
        assert_equal(len(model.textures), 1)
        ref texture = assets.textures.get(model.textures[0])
        assert_true(texture.mag_filter == BILINEAR)
        assert_equal(texture.levels > 1, filter == "auto")
        assert_true(texture.wrap_s == REPEAT)
    # A `texid` that names no texture makes a material with no map.
    var scene = Scene()
    var assets = Assets()
    var bare = parse_3mf(
        zip_archive(texture_archive("", corners, False)), scene, assets
    )
    assert_equal(len(bare.textures), 0)
    assert_true(
        assets.materials.get(scene.meshes[0].material).map == NO_TEXTURE
    )
    with assert_raises(contains="is not in the archive"):
        _ = load(
            texture_archive(
                '<texture2d id="3" path="/3D/Texture/t.png"/>', corners, False
            )
        )
    with assert_raises(contains="texture index 2 is out of range"):
        _ = load(
            texture_archive(
                "",
                '<triangle v1="0" v2="1" v3="2" p1="0" p2="2" p3="0"/>',
                True,
            )
        )


def test_a_texture_group_with_no_coordinates_is_refused() raises:
    refused(
        model_text(
            '<texture2dgroup id="4" texid="3"/>'
            + mesh_object(
                "1", 'pid="4"', '<triangle v1="0" v2="1" v3="2" p1="0"/>'
            ),
            "",
        ),
        "texture index 0 is out of range",
    )


def test_a_duplicate_object_id_keeps_the_last() raises:
    var model = load_model(
        model_text(
            '<object id="1"><components/></object>'
            + mesh_object(
                "1", 'name="last"', '<triangle v1="0" v2="1" v3="2"/>'
            ),
            '<item objectid="1"/>',
        )
    )
    assert_equal(model.node_names[0], "last")
    assert_equal(model.mesh_count, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
