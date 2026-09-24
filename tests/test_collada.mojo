# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.collada` and `loaders.model_nodes`: one scene
checked against what three.js r180's `ColladaLoader` builds from it, and
small documents written inline for every branch and every refusal.

The expected numbers of `test_scene` were printed by running the same
document through `ColladaLoader.parse` in Node, with `@xmldom/xmldom` as
the `DOMParser`. Two numbers differ, on purpose: three.js keeps a
three-wide texture coordinate where this keeps two, and it decodes the
wrong slots of a vertex color; see the wiki.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from lights.light import AMBIENT, DIRECTIONAL, POINT, SPOT
from loaders.collada import (
    UpAxis,
    X_UP,
    Y_UP,
    Z_UP,
    load_collada,
    read_collada,
    up_axis_rotation,
)
from loaders.model_nodes import (
    authored_color,
    compose,
    decompose_onto,
    texture_from_file,
)
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    FRONT_SIDE,
    LAMBERT,
    NO_TEXTURE,
    PHONG,
    Material,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.line import SEGMENTS
from render.srgb import LINEAR, SRGB
from render.texture import CLAMP, COVERAGE, IGNORED, REPEAT
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER

# Where the tests' one image is: a two-by-two checker.
comptime HERE = "assets/gltf/"

# The scene three.js was run on: three materials, two geometries, two
# cameras, four lights, a node library, and a Z_UP asset of half a meter.
comptime SCENE = (
    '<?xml version="1.0" encoding="utf-8"?>\n<COLLADA'
    ' xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">\n '
    ' <asset><unit name="half" meter="0.5"/><up_axis>Z_UP</up_axis></asset>\n '
    ' <library_effects>\n    <effect id="shiny-fx"><profile_COMMON><technique'
    ' sid="common"><phong>\n      <emission><color>0.1 0.2 0.3'
    " 1</color></emission>\n      <diffuse><color>0.8 0.4 0.2"
    " 1</color></diffuse>\n      <specular><color>0.5 0.5 0.5"
    " 1</color></specular>\n      <shininess><float>12</float></shininess>\n   "
    '   <transparent opaque="A_ONE"><color>1 1 1 0.5</color></transparent>\n   '
    "   <transparency><float>0.8</float></transparency>\n   "
    " </phong><extra><technique"
    ' profile="MAX3D"><double_sided>1</double_sided></technique></extra></technique></profile_COMMON></effect>\n'
    '    <effect id="matte-fx"><profile_COMMON><technique'
    ' sid="common"><lambert>\n      <diffuse><color>0.2 0.6 0.4'
    " 1</color></diffuse>\n      <emission><color>0 0 0.5"
    ' 1</color></emission>\n      <transparent opaque="RGB_ZERO"><color>0.25'
    " 0.25 0.25 1</color></transparent>\n   "
    " </lambert></technique></profile_COMMON></effect>\n    <effect"
    ' id="flat-fx"><profile_COMMON><technique sid="common"><constant>\n     '
    " <emission><color>1 0 0 1</color></emission>\n      <diffuse><color>0 1 0"
    " 1</color></diffuse>\n   "
    " </constant></technique></profile_COMMON></effect>\n  </library_effects>\n"
    '  <library_materials>\n    <material id="shiny"'
    ' name="Shiny"><instance_effect url="#shiny-fx"/></material>\n    <material'
    ' id="matte" name="Matte"><instance_effect url="#matte-fx"/></material>\n  '
    '  <material id="flat"><instance_effect url="#flat-fx"/></material>\n '
    ' </library_materials>\n  <library_geometries>\n    <geometry id="tri"'
    ' name="Tri"><mesh>\n      <source id="tri-pos"><float_array id="tri-pos-a"'
    ' count="9">0 0 0 1 0 0 0 1 0</float_array>\n       '
    ' <technique_common><accessor source="#tri-pos-a" count="3"'
    ' stride="3"/></technique_common></source>\n      <source'
    ' id="tri-nrm"><float_array count="3">0 0 1</float_array>\n       '
    ' <technique_common><accessor count="1"'
    ' stride="3"/></technique_common></source>\n      <source'
    ' id="tri-uv"><float_array count="9">0 0 9 1 0 9 0 1 9</float_array>\n     '
    '   <technique_common><accessor count="3"'
    ' stride="3"/></technique_common></source>\n      <source'
    ' id="tri-rgb"><float_array count="4">0.5 0.25 1 0.5</float_array>\n       '
    ' <technique_common><accessor count="1"'
    ' stride="4"/></technique_common></source>\n      <vertices'
    ' id="tri-v"><input semantic="POSITION" source="#tri-pos"/></vertices>\n   '
    '   <triangles count="1" material="sym-a">\n        <input'
    ' semantic="VERTEX" source="#tri-v" offset="0"/>\n        <input'
    ' semantic="NORMAL" source="#tri-nrm" offset="1"/>\n        <input'
    ' semantic="TEXCOORD" source="#tri-uv" offset="2" set="0"/>\n        <input'
    ' semantic="COLOR" source="#tri-rgb" offset="1"/>\n        <p>0 0 0 1 0 1 2'
    " 0 2</p>\n      </triangles>\n    </mesh></geometry>\n    <geometry"
    ' id="poly" name="Poly"><mesh>\n      <source id="poly-pos"><float_array'
    ' count="21">0 0 0 2 0 0 2 2 0 0 2 0 3 0 0 3 1 0 2 3 0</float_array>\n     '
    '   <technique_common><accessor count="7"'
    ' stride="3"/></technique_common></source>\n      <source'
    ' id="poly-nrm"><float_array count="21">0 0 1 0 0 1 0 0 1 0 0 1 0 0 1 0 0 1'
    ' 0 0 1</float_array>\n        <technique_common><accessor count="7"'
    ' stride="3"/></technique_common></source>\n      <vertices'
    ' id="poly-v"><input semantic="POSITION" source="#poly-pos"/><input'
    ' semantic="NORMAL" source="#poly-nrm"/></vertices>\n      <polylist'
    ' count="2" material="sym-b">\n        <input semantic="VERTEX"'
    ' source="#poly-v" offset="0"/>\n        <vcount>4 5</vcount>\n        <p>0'
    ' 1 2 3 1 4 5 6 2</p>\n      </polylist>\n      <lines count="2"'
    ' material="sym-a">\n        <input semantic="VERTEX" source="#poly-v"'
    ' offset="0"/>\n        <p>0 1 1 2</p>\n      </lines>\n   '
    " </mesh></geometry>\n  </library_geometries>\n  <library_cameras>\n   "
    ' <camera id="eye" name="Eye"><optics><technique_common><perspective>\n    '
    "  <yfov>45</yfov><aspect_ratio>1.5</aspect_ratio><znear>0.5</znear><zfar>100</zfar>\n"
    "    </perspective></technique_common></optics></camera>\n    <camera"
    ' id="flat-eye"><optics><technique_common><orthographic>\n     '
    " <xmag>4</xmag><aspect_ratio>2</aspect_ratio><znear>0</znear><zfar>10</zfar>\n"
    "    </orthographic></technique_common></optics></camera>\n "
    " </library_cameras>\n  <library_lights>\n    <light"
    ' id="bulb"><technique_common><point><color>1 0.5'
    " 0.25</color><quadratic_attenuation>0.25</quadratic_attenuation></point></technique_common></light>\n"
    '    <light id="sun"><technique_common><directional><color>1 1'
    " 1</color></directional></technique_common></light>\n    <light"
    ' id="cone"><technique_common><spot><color>0.5 0.5'
    " 0.5</color><falloff_angle>30</falloff_angle></spot></technique_common></light>\n"
    '    <light id="sky"><technique_common><ambient><color>0.2 0.2'
    " 0.2</color></ambient></technique_common></light>\n  </library_lights>\n "
    ' <library_nodes>\n    <node id="shared" name="Shared"><translate>0 0'
    ' 5</translate><instance_geometry url="#tri"/></node>\n  </library_nodes>\n'
    '  <library_visual_scenes>\n    <visual_scene id="vs" name="World">\n     '
    ' <node id="a" name="Alpha">\n        <translate sid="t">1 2'
    ' 3</translate>\n        <rotate sid="r">0 0 1 90</rotate>\n        <scale'
    ' sid="s">2 2 2</scale>\n        <instance_geometry'
    ' url="#tri"><bind_material><technique_common>\n         '
    ' <instance_material symbol="sym-a" target="#shiny"/>\n       '
    " </technique_common></bind_material></instance_geometry>\n        <node"
    ' id="b" name="Beta">\n          <matrix>1 0 0 4  0 1 0 5  0 0 1 6  0 0 0'
    ' 1</matrix>\n          <instance_light url="#sun"/>\n         '
    ' <instance_camera url="#eye"/>\n        </node>\n      </node>\n     '
    ' <node id="c" name="Gamma">\n        <instance_geometry'
    ' url="#poly"><bind_material><technique_common>\n         '
    ' <instance_material symbol="sym-b" target="#matte"/>\n         '
    ' <instance_material symbol="sym-a" target="#shiny"/>\n       '
    " </technique_common></bind_material></instance_geometry>\n      </node>\n "
    '     <node id="d" name="Delta"><translate>0 3 0</translate><instance_light'
    ' url="#cone"/></node>\n      <node id="e" name="Epsilon"><instance_light'
    ' url="#bulb"/><instance_light url="#sky"/></node>\n      <node id="f"'
    ' name="Zeta"><instance_node url="#shared"/></node>\n      <node id="g"'
    ' name="Eta" sid="joint-g" type="JOINT"><instance_camera'
    ' url="#flat-eye"/><instance_node url="#shared"/></node>\n      <node'
    ' id="h" name="Theta"><instance_geometry'
    ' url="#tri"><bind_material><technique_common>\n         '
    ' <instance_material symbol="sym-a" target="#flat"/>\n       '
    " </technique_common></bind_material></instance_geometry></node>\n   "
    " </visual_scene>\n  </library_visual_scenes>\n "
    ' <scene><instance_visual_scene url="#vs"/></scene>\n</COLLADA>\n'
)


def dae(libraries: String, nodes: String, asset: String = "") -> String:
    """Return a Collada document of some libraries and one visual scene of
    some nodes."""
    return (
        "<COLLADA>"
        + asset
        + libraries
        + '<library_visual_scenes><visual_scene id="vs">'
        + nodes
        + "</visual_scene></library_visual_scenes><scene><instance_visual_scene"
        ' url="#vs"/></scene></COLLADA>'
    )


# One triangle, positions only, for the documents that need a geometry.
comptime TRI = (
    '<library_geometries><geometry id="g"><mesh><source id="p"><float_array>0 0'
    " 0 1 0 0 0 1 0</float_array><technique_common><accessor"
    ' stride="3"/></technique_common></source><vertices id="v"><input'
    ' semantic="POSITION" source="#p"/></vertices><triangles count="1"'
    ' material="m"><input semantic="VERTEX" source="#v" offset="0"/><p>0 1'
    " 2</p></triangles></mesh></geometry></library_geometries>"
)


def effect(body: String, extra: String = "", newparams: String = "") -> String:
    """Return a material `m` of an effect with a shading body."""
    return (
        "<library_images><image"
        ' id="img"><init_from>checker.png</init_from></image>'
        + '<image id="bare"></image><image'
        ' id="far"><init_from>file:///x.png</init_from></image>'
        + "</library_images>"
        + '<library_effects><effect id="fx"><profile_COMMON>'
        + newparams
        + '<technique sid="t">'
        + body
        + extra
        + "</technique></profile_COMMON></effect></library_effects>"
        + '<library_materials><material id="mat" name="Mat"><instance_effect'
        ' url="#fx"/></material></library_materials>'
    )


def bound(material: String = "mat") -> String:
    """Return a node that instances `TRI` with its symbol bound."""
    return (
        '<node name="n"><instance_geometry'
        ' url="#g"><bind_material><technique_common>'
        + '<instance_material symbol="m" target="#'
        + material
        + '"/></technique_common></bind_material></instance_geometry></node>'
    )


def material_of(libraries: String) raises -> Material:
    """Return the material `TRI` draws with when bound to `mat`."""
    var scene = Scene()
    var assets = Assets()
    _ = load_collada(dae(libraries + TRI, bound()), HERE, scene, assets)
    return assets.materials.get(scene.meshes[0].material)


def refused(text: String) raises:
    """Assert that `load_collada` refuses a document."""
    var scene = Scene()
    var assets = Assets()
    try:
        _ = load_collada(text, HERE, scene, assets)
    except:
        return
    print("load_collada read what it should refuse: " + text)
    raise Error("not refused")


def values(
    assets: Assets, id: GeometryId, name: String
) raises -> List[Float32]:
    """Return a copy of one attribute's numbers."""
    return assets.geometries.get(id).clone_attribute(name).data.copy()


def assert_near(actual: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert that a vector is close to (x, y, z)."""
    assert_almost_equal(actual.x, x, atol=1e-5)
    assert_almost_equal(actual.y, y, atol=1e-5)
    assert_almost_equal(actual.z, z, atol=1e-5)


def assert_list(actual: List[Float32], expected: List[Float32]) raises:
    """Assert that two lists of numbers are close, entry by entry."""
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_almost_equal(actual[index], expected[index], atol=1e-5)


def test_scene() raises:
    """The fixture, against what three.js r180's `ColladaLoader` gives."""
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(SCENE, "", scene, assets)
    assert_equal(model.up_axis, Z_UP)
    assert_almost_equal(model.unit.to(METER), 0.5)
    var root = scene.get(model.root)
    assert_equal(root.name, "World")
    assert_near(root.scale, 0.5, 0.5, 0.5)
    assert_almost_equal(root.quaternion.x, -0.70711, atol=1e-5)
    assert_almost_equal(root.quaternion.w, 0.70711, atol=1e-5)
    scene.update()
    var names: List[String] = [
        "Alpha",
        "Beta",
        "Gamma",
        "Delta",
        "Epsilon",
        "Zeta",
        "joint-g",
        "Shared",
        "Theta",
    ]
    assert_equal(len(model.nodes), len(names))
    for index in range(len(names)):
        assert_equal(model.node_names[index], names[index])
        assert_equal(scene.get(model.nodes[index]).name, names[index])
    var alpha = scene.get(model.nodes[0])
    assert_near(alpha.position, 1, 2, 3)
    assert_near(alpha.scale, 2, 2, 2)
    assert_almost_equal(alpha.quaternion.z, 0.70711, atol=1e-5)
    assert_near(scene.world_position(model.nodes[0]), 0.5, 1.5, -1)
    assert_near(scene.world_position(model.nodes[1]), -4.5, 7.5, -5)
    assert_near(scene.world_position(model.nodes[3]), 0, 0, -1.5)
    assert_near(scene.world_position(model.nodes[7]), 0, 2.5, 0)
    # Four lights: the sun one unit up Beta's y, as one object of two; the
    # cone at Delta, its one object; the bulb and the sky at Epsilon.
    assert_equal(model.first_light, 0)
    assert_equal(model.light_count, 4)
    var sun = scene.lights[0]
    assert_equal(sun.kind, DIRECTIONAL)
    assert_near(scene.world_position(sun.node), -5.5, 7.5, -5)
    assert_equal(sun.target, NO_PARENT)
    var cone = scene.lights[1]
    assert_equal(cone.kind, SPOT)
    assert_equal(cone.node, model.nodes[3])
    assert_almost_equal(cone.angle.value, 1.0471976, atol=1e-6)
    assert_equal(cone.color.r, 128)
    var bulb = scene.lights[2]
    assert_equal(bulb.kind, POINT)
    assert_almost_equal(bulb.distance, 2)
    assert_equal(bulb.color.g, 128)
    assert_equal(bulb.color.b, 64)
    assert_equal(scene.lights[3].kind, AMBIENT)
    assert_equal(scene.lights[3].color.r, 51)
    # Two cameras, each riding its node.
    assert_equal(len(model.perspective_cameras), 1)
    var eye = model.perspective_cameras[0]
    assert_equal(eye.node, model.nodes[1])
    assert_almost_equal(eye.fov.to(DEGREE), 45, atol=1e-4)
    assert_almost_equal(eye.aspect, 1.5)
    assert_almost_equal(eye.near.value, 0.5)
    assert_almost_equal(eye.far.value, 100)
    assert_equal(len(model.orthographic_cameras), 1)
    var flat = model.orthographic_cameras[0].copy()
    assert_equal(flat.node, model.nodes[6])
    assert_almost_equal(flat.left.value, -2)
    assert_almost_equal(flat.right.value, 2)
    assert_almost_equal(flat.top.value, 1)
    assert_almost_equal(flat.bottom.value, -1)
    assert_almost_equal(flat.far.value, 10)
    # Materials, in file order.
    assert_equal(len(model.materials), 3)
    assert_equal(model.material_ids[0], "shiny")
    assert_equal(model.material_names[0], "Shiny")
    assert_equal(model.material_names[2], "")
    assert_equal(model.material("matte"), model.materials[1])
    with assert_raises():
        _ = model.material("none")
    var shiny = assets.materials.get(model.materials[0])
    assert_equal(shiny.kind, PHONG)
    assert_equal(shiny.color.r, 204)
    assert_equal(shiny.color.g, 102)
    assert_equal(shiny.color.b, 51)
    assert_equal(shiny.specular.r, 128)
    assert_equal(shiny.emissive.r, 26)
    assert_equal(shiny.emissive.g, 51)
    assert_equal(shiny.emissive.b, 77)
    assert_almost_equal(shiny.shininess, 12)
    assert_almost_equal(shiny.opacity, 0.4, atol=1e-6)
    assert_true(shiny.transparent)
    assert_equal(shiny.side, DOUBLE_SIDE)
    var matte = assets.materials.get(model.materials[1])
    assert_equal(matte.kind, LAMBERT)
    assert_equal(matte.color.g, 153)
    assert_equal(matte.emissive.b, 128)
    assert_almost_equal(matte.opacity, 0.75)
    assert_equal(matte.side, FRONT_SIDE)
    var constant = assets.materials.get(model.materials[2])
    assert_equal(constant.kind, BASIC)
    assert_equal(constant.color.g, 255)
    assert_equal(constant.emissive.r, 0)
    # Five meshes: Alpha's triangle, Gamma's polylist, the shared triangle
    # twice with the magenta fallback, and Theta's with the constant.
    assert_equal(model.mesh_count, 5)
    assert_equal(scene.meshes[0].node, model.nodes[0])
    assert_equal(scene.meshes[0].material, model.materials[0])
    var tri = scene.meshes[0].geometry
    assert_list(values(assets, tri, POSITION), [0, 0, 0, 1, 0, 0, 0, 1, 0])
    assert_list(values(assets, tri, NORMAL), [0, 0, 1, 0, 0, 1, 0, 0, 1])
    assert_list(values(assets, tri, UV), [0, 0, 1, 0, 0, 1])
    var linear: List[Float32] = [0.21404, 0.05088, 1, 0.5]
    var colors = List[Float32]()
    for _ in range(3):
        colors.extend(linear.copy())
    assert_list(values(assets, tri, COLOR), colors)
    assert_equal(scene.meshes[1].node, model.nodes[2])
    assert_equal(scene.meshes[1].material, model.materials[1])
    assert_list(
        values(assets, scene.meshes[1].geometry, POSITION),
        [
            0,
            0,
            0,
            2,
            0,
            0,
            0,
            2,
            0,
            2,
            0,
            0,
            2,
            2,
            0,
            0,
            2,
            0,
            2,
            0,
            0,
            3,
            0,
            0,
            3,
            1,
            0,
            2,
            0,
            0,
            3,
            1,
            0,
            2,
            3,
            0,
            2,
            0,
            0,
            2,
            3,
            0,
            2,
            2,
            0,
        ],
    )
    assert_equal(
        assets.geometries.get(scene.meshes[1].geometry).vertex_count(), 15
    )
    assert_true(
        assets.geometries.get(scene.meshes[1].geometry).has_attribute(
            String(NORMAL)
        )
    )
    # The shared triangle is one geometry, whichever node draws it.
    assert_equal(scene.meshes[2].geometry, tri)
    assert_equal(scene.meshes[2].node, model.nodes[5])
    assert_equal(scene.meshes[3].node, model.nodes[7])
    var fallback = assets.materials.get(scene.meshes[2].material)
    assert_equal(fallback.kind, BASIC)
    assert_equal(fallback.color.g, 0)
    assert_equal(scene.meshes[3].material, scene.meshes[2].material)
    assert_equal(scene.meshes[4].material, model.materials[2])
    # The lines, in a basic copy of the phong material.
    assert_equal(model.line_count, 1)
    var line = scene.lines[0]
    assert_equal(line.mode, SEGMENTS)
    assert_list(
        values(assets, line.geometry, POSITION),
        [0, 0, 0, 2, 0, 0, 2, 0, 0, 2, 2, 0],
    )
    var copy = assets.materials.get(line.material)
    assert_equal(copy.kind, BASIC)
    assert_equal(copy.color.r, 204)
    assert_almost_equal(copy.opacity, 0.4, atol=1e-6)
    assert_true(copy.transparent)
    assert_equal(len(model.geometries), 3)
    assert_equal(len(model.textures), 0)


def test_up_axis() raises:
    assert_true(X_UP.is_valid())
    assert_false(UpAxis(3).is_valid())
    with assert_raises():
        _ = up_axis_rotation(UpAxis(3))
    assert_almost_equal(up_axis_rotation(Y_UP).w, 1)
    assert_almost_equal(up_axis_rotation(X_UP).w, 1)
    assert_almost_equal(up_axis_rotation(Z_UP).x, -0.70710677, atol=1e-6)
    var scene = Scene()
    var assets = Assets()
    var x = load_collada(
        dae("", "", "<asset><up_axis> X_UP </up_axis></asset>"),
        "",
        scene,
        assets,
    )
    assert_equal(x.up_axis, X_UP)
    var y = load_collada(
        dae("", "", "<asset><up_axis>Y_UP</up_axis><unit/></asset>"),
        "",
        scene,
        assets,
    )
    assert_equal(y.up_axis, Y_UP)
    assert_almost_equal(y.unit.to(METER), 1)
    var plain = load_collada(
        dae("<library_materials/>", "", "<asset/>"), "", scene, assets
    )
    assert_equal(plain.up_axis, Y_UP)
    with assert_raises():
        _ = plain.material("none")
    refused(dae("", "", "<asset><up_axis>W_UP</up_axis></asset>"))
    refused(dae("", "", '<asset><unit meter="0"/></asset>'))
    refused(dae("", "", '<asset><unit meter="1 2"/></asset>'))
    refused(dae("", "", '<asset><unit meter="x"/></asset>'))


def test_materials() raises:
    # A blinn is a phong; a zero shininess keeps three.js's thirty.
    var blinn = material_of(
        effect(
            "<blinn><shininess><float>0</float></shininess><specular>"
            "<float>1</float></specular><bump/></blinn>"
        )
    )
    assert_equal(blinn.kind, PHONG)
    assert_almost_equal(blinn.shininess, 30)
    assert_equal(blinn.specular.r, 17)
    # A lambert has no highlight, and a constant no emissive term.
    var lambert = material_of(
        effect(
            "<lambert><specular><color>1 1 1 1</color></specular>"
            "<shininess><float>5</float></shininess></lambert>"
        )
    )
    assert_equal(lambert.specular.r, 0)
    assert_almost_equal(lambert.shininess, 0)
    var constant = material_of(
        effect(
            "<constant><emission><color>1 1 1 1</color></emission>"
            "<ambient><color>1 1 1 1</color></ambient></constant>"
        )
    )
    assert_equal(constant.emissive.r, 0)
    # The last shading element wins.
    assert_equal(material_of(effect("<phong/><lambert/>")).kind, LAMBERT)
    # The four opaque modes.
    var modes: List[String] = ["A_ONE", "RGB_ZERO", "A_ZERO", "RGB_ONE"]
    var opacities: List[Float32] = [0.2, 0.9, 0.8, 0.1]
    for index in range(4):
        var built = material_of(
            effect(
                '<phong><transparent opaque="'
                + modes[index]
                + '"><color>0.2 0.5 0.5 0.4</color></transparent>'
                + "<transparency><float>0.5</float></transparency></phong>"
            )
        )
        assert_almost_equal(built.opacity, opacities[index], atol=1e-6)
        assert_true(built.transparent)
    # `transparency` alone is a white of alpha one in A_ONE; `transparent`
    # alone has a transparency of one.
    assert_almost_equal(
        material_of(
            effect(
                "<phong><transparency><float>0.25</float></transparency></phong>"
            )
        ).opacity,
        0.25,
    )
    var whole = material_of(
        effect(
            "<phong><transparent><color>1 1 1 1</color></transparent></phong>"
        )
    )
    assert_almost_equal(whole.opacity, 1)
    assert_false(whole.transparent)
    assert_almost_equal(
        material_of(
            effect('<phong><transparent opaque="RGB_ZERO"/></phong>')
        ).opacity,
        0,
    )
    # A transparent texture blends and sets no alpha map.
    var textured = material_of(
        effect(
            '<phong><transparent><texture texture="img"/></transparent></phong>'
        )
    )
    assert_true(textured.transparent)
    assert_almost_equal(textured.opacity, 1)
    assert_equal(textured.alpha_map, NO_TEXTURE)
    # `double_sided` of anything but one is the front.
    var front = material_of(
        effect(
            "<phong/>",
            (
                "<extra><technique><double_sided>0</double_sided><other/>"
                "</technique></extra>"
            ),
        )
    )
    assert_equal(front.side, FRONT_SIDE)
    assert_equal(material_of(effect("<phong/>", "<extra/>")).side, FRONT_SIDE)
    assert_equal(
        material_of(
            effect(
                "<phong/>",
                (
                    "<extra><technique/><technique><double_sided>1 1"
                    "</double_sided></technique></extra>"
                ),
            )
        ).side,
        FRONT_SIDE,
    )
    refused(dae(effect(""), ""))
    refused(
        dae(
            effect(
                '<phong><transparent opaque="RGB"><color>1 1 1 1</color>'
                "</transparent></phong>"
            )
            + TRI,
            bound(),
        )
    )
    refused(
        dae(
            effect(
                "<phong><transparency><float>2</float></transparency></phong>"
            )
            + TRI,
            bound(),
        )
    )
    refused(
        dae(
            effect(
                "<phong><transparency><float>-1</float></transparency></phong>"
            )
            + TRI,
            bound(),
        )
    )
    refused(
        dae(
            effect(
                "<phong><transparent><color>1 1 1</color></transparent></phong>"
            )
            + TRI,
            bound(),
        )
    )
    refused(
        dae(effect("<phong><diffuse><color>1 1</color></diffuse></phong>"), "")
    )
    refused(
        dae(
            effect("<phong><diffuse><color>2 1 1</color></diffuse></phong>"), ""
        )
    )
    refused(
        dae(
            effect("<phong><shininess><float>1 2</float></shininess></phong>"),
            "",
        )
    )
    refused(dae(effect("<extra/>"), ""))
    # A material with no effect, an effect that is not there, and an
    # effect without what three.js reads.
    refused(
        dae('<library_materials><material id="a"/></library_materials>', "")
    )
    refused(
        dae(
            (
                '<library_materials><material id="a"><instance_effect'
                ' url="#x"/></material></library_materials>'
            ),
            "",
        )
    )
    refused(
        dae(
            (
                '<library_materials><material id="a"><instance_effect'
                ' url="fx"/></material></library_materials>'
            ),
            "",
        )
    )
    refused(
        dae(
            (
                "<library_effects><effect"
                ' id="fx"/></library_effects><library_materials><material'
                ' id="a"><instance_effect'
                ' url="#fx"/></material></library_materials>'
            ),
            "",
        )
    )
    refused(
        dae(
            (
                "<library_effects><effect"
                ' id="fx"><profile_COMMON/></effect></library_effects><library_materials><material'
                ' id="a"><instance_effect'
                ' url="#fx"/></material></library_materials>'
            ),
            "",
        )
    )


def test_textures() raises:
    var sampled = (
        '<newparam sid="surf"><surface type="2D"><init_from>img</init_from>'
        + '</surface></newparam><newparam sid="samp"><sampler2D>'
        + "<source>surf</source></sampler2D></newparam>"
        + '<newparam sid="lonely"><sampler2D/></newparam>'
        + '<newparam sid="naked"><surface/></newparam>'
        + '<newparam sid="bare-samp"><sampler2D><source>naked</source>'
        + "</sampler2D></newparam>"
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(
        dae(
            effect(
                '<phong><diffuse><texture texture="samp" texcoord="uv"/>'
                + "</diffuse>"
                + '<emission><texture texture="img"><extra><technique>'
                + "<wrapU>FALSE</wrapU><wrapV>TRUE</wrapV><repeatU>2</repeatU>"
                + "<repeatV>0</repeatV><offsetU>0.5</offsetU><offsetV>0.25</offsetV>"
                + "<blend>x</blend></technique></extra></texture></emission>"
                + "<bump><texture"
                ' texture="img"><extra><technique><wrapU>true</wrapU>'
                + "</technique></extra></texture></bump>"
                + '<specular><texture texture="img"/></specular>'
                + '<ambient><texture texture="img"/></ambient>'
                + "</phong>",
                "",
                sampled,
            )
            + TRI,
            bound(),
        ),
        HERE,
        scene,
        assets,
    )
    assert_equal(len(model.textures), 3)
    var built = assets.materials.get(model.materials[0])
    assert_equal(built.map, model.textures[0])
    assert_equal(built.emissive_map, model.textures[1])
    assert_equal(built.normal_map, model.textures[2])
    ref color = assets.textures.get(built.map)
    assert_equal(color.color_space, SRGB)
    assert_equal(color.wrap_s, REPEAT)
    assert_equal(color.alpha, COVERAGE)
    ref glow = assets.textures.get(built.emissive_map)
    assert_equal(glow.wrap_s, CLAMP)
    assert_equal(glow.alpha, IGNORED)
    assert_almost_equal(glow.repeat.x, 2)
    assert_almost_equal(glow.repeat.y, 1)
    assert_almost_equal(glow.offset.x, 0.5)
    assert_almost_equal(glow.offset.y, 0.25)
    ref bump = assets.textures.get(built.normal_map)
    assert_equal(bump.color_space, LINEAR)
    assert_equal(bump.wrap_s, REPEAT)
    # A number turns wrapping on when it is not zero; the extra `bump`
    # replaces the parameter's; an image the file does not have is left out.
    var other = material_of(
        effect(
            '<phong><diffuse><texture texture="img"><extra><technique>'
            + "<wrapU>1</wrapU></technique><technique><repeatV>3</repeatV>"
            + "</technique></extra></texture></diffuse>"
            + '<bump><texture texture="none"/></bump>'
            + '<emission><texture texture="img"><extra/><extra><technique/>'
            + "</extra></texture></emission></phong>",
            '<extra><technique><bump><texture texture="img"/></bump>'
            + "</technique></extra>",
        )
    )
    assert_true(other.normal_map != NO_TEXTURE)
    var missing = material_of(
        effect('<phong><diffuse><texture texture="none"/></diffuse></phong>')
    )
    assert_equal(missing.map, NO_TEXTURE)
    # A constant material takes a map and no normal map.
    var flat = material_of(
        effect(
            '<constant><diffuse><texture texture="img"/></diffuse>'
            + '<bump><texture texture="img"/></bump></constant>',
            '<extra><technique><bump><texture texture="img"/></bump>'
            + "</technique></extra>",
        )
    )
    assert_true(flat.map != NO_TEXTURE)
    assert_equal(flat.normal_map, NO_TEXTURE)
    # What is refused: a sampler with no surface, a surface or an image
    # with no init_from, a path that is not relative, and a setting that
    # is not a number.
    for texture in ["lonely", "bare-samp", "bare", "far"]:
        refused(
            dae(
                effect(
                    '<phong><diffuse><texture texture="'
                    + texture
                    + '"/></diffuse></phong>',
                    "",
                    sampled,
                )
                + TRI,
                bound(),
            )
        )
    refused(
        dae(
            effect(
                '<phong><diffuse><texture texture="img"><extra><technique>'
                + "<wrapU>maybe</wrapU></technique></extra></texture></diffuse></phong>"
            )
            + TRI,
            bound(),
        )
    )
    # A file that is not there.
    var elsewhere = Scene()
    var into = Assets()
    with assert_raises():
        _ = load_collada(
            dae(
                effect(
                    '<phong><diffuse><texture texture="img"/></diffuse></phong>'
                )
                + TRI,
                bound(),
            ),
            "assets/none/",
            elsewhere,
            into,
        )


def test_geometry() raises:
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(
        dae(
            '<library_geometries><geometry id="g"><mesh>'
            + '<source id="p"><float_array>0 0 0 1 0 0 1 1 0 0 1'
            " 0</float_array>"
            + "<technique_common><accessor"
            ' stride="3"/></technique_common></source>'
            + '<source id="t"><float_array>0 0 1 0 1 1 0 1</float_array>'
            + "<technique_common><accessor"
            ' stride="2"/></technique_common></source>'
            + '<source id="names"><Name_array>a b</Name_array>'
            + "<technique_common/></source>"
            + '<vertices id="v"><input semantic="POSITION" source="#p"/>'
            + '<input semantic="TEXBINORMAL" source="#p"/></vertices>'
            + '<polygons count="2"><input semantic="VERTEX" source="#v"'
            ' offset="0"/>'
            + '<input semantic="TEXCOORD" source="#t" offset="1" set="1"/>'
            + '<input semantic="TEXCOORD" source="#t" offset="1" set="0"/>'
            + "<p>0 0 1 1 2 2 3 3</p><p>0 0 1 1 2 2</p></polygons>"
            + '<linestrips count="2"><input semantic="VERTEX" source="#v"'
            ' offset="0"/>'
            + "<p>0 1 2</p><p>3</p></linestrips>"
            + '<polylist count="3"><input semantic="VERTEX" source="#v"'
            ' offset="0"/>'
            + "<vcount>1 2 3</vcount><p>0 0 1 0 1 2</p></polylist>"
            + '<triangles count="0"><input semantic="VERTEX" source="#v"'
            ' offset="0"/>'
            + "</triangles><trifans/><extra/>"
            + "</mesh></geometry></library_geometries>",
            '<node><instance_geometry url="#g"/><instance_geometry url="#g"/>'
            + '<instance_light url="#none"/>'
            + '<instance_camera url="#none"/><lookat/></node>',
        ),
        "",
        scene,
        assets,
    )
    # Polygons, the polylist's one triangle, and the strips, built once
    # and drawn twice.
    assert_equal(len(model.geometries), 3)
    assert_equal(model.mesh_count, 4)
    assert_equal(model.line_count, 2)
    var polygons = scene.meshes[0].geometry
    assert_list(
        values(assets, polygons, POSITION),
        [
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1,
            0,
            1,
            0,
            0,
            1,
            1,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            1,
            1,
            0,
        ],
    )
    assert_list(
        values(assets, polygons, UV),
        [0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1],
    )
    assert_equal(scene.meshes[2].geometry, polygons)
    var strips = scene.lines[0]
    assert_list(
        values(assets, strips.geometry, POSITION),
        [0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0],
    )
    assert_false(
        assets.geometries.get(strips.geometry).has_attribute(String(UV))
    )
    # With no symbol, a mesh draws a white phong and a line a white basic.
    var mesh_default = assets.materials.get(scene.meshes[0].material)
    assert_equal(mesh_default.kind, PHONG)
    assert_equal(mesh_default.color.b, 255)
    assert_almost_equal(mesh_default.shininess, 30)
    assert_equal(assets.materials.get(scene.lines[0].material).kind, BASIC)
    assert_equal(scene.meshes[3].material, scene.meshes[1].material)
    assert_equal(scene.lines[1].material, scene.lines[0].material)
    # An empty node and a node that holds nothing it can draw.
    assert_equal(len(model.perspective_cameras), 0)
    assert_equal(model.light_count, 0)


def test_primitives_of_one_kind_are_one_mesh_with_groups() raises:
    """A group per primitive, as three.js's `buildGeometryType` adds, and group
    `i` wears material `i` of the symbols the primitives name."""
    var geometry = String(
        '<library_geometries><geometry id="g"><mesh><source id="p">'
        + "<float_array>0 0 0 1 0 0 0 1 0</float_array><technique_common>"
        + '<accessor stride="3"/></technique_common></source><vertices'
        + ' id="v"><input semantic="POSITION" source="#p"/></vertices>'
    )
    var triangle = String(
        '<input semantic="VERTEX" source="#v" offset="0"/><p>0 1 2</p>'
    )
    var library = (
        geometry
        + '<triangles material="a">'
        + triangle
        + "</triangles><triangles>"
        + triangle
        + '</triangles><triangles material="b">'
        + triangle
        + "</triangles></mesh></geometry></library_geometries>"
    )
    var materials = String(
        '<library_effects><effect id="fx"><profile_COMMON><technique'
        ' sid="t"><constant/></technique></profile_COMMON></effect>'
        + '</library_effects><library_materials><material id="one">'
        + '<instance_effect url="#fx"/></material><material id="two">'
        + '<instance_effect url="#fx"/></material></library_materials>'
    )
    var node = String(
        '<node><instance_geometry url="#g"><bind_material><technique_common>'
        + '<instance_material symbol="a" target="#one"/>'
        + '<instance_material symbol="b" target="#two"/>'
        + "</technique_common></bind_material></instance_geometry></node>"
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(dae(materials + library, node), "", scene, assets)
    assert_equal(model.mesh_count, 1)
    ref mesh = scene.meshes[0]
    assert_equal(len(mesh.materials), 2)
    assert_equal(mesh.materials[0], model.material("one"))
    assert_equal(mesh.materials[1], model.material("two"))
    ref groups = assets.geometries.get(mesh.geometry).groups
    assert_equal(len(groups), 3)
    assert_equal(groups[1].start, 3)
    assert_equal(groups[2].start, 6)
    # The primitive with no symbol adds a group and no material, so the
    # last group names a material the list does not have.
    assert_equal(groups[2].material_index.value, 2)
    assert_false(Bool(mesh.group_material(groups[2].material_index)))
    # One symbol makes a plain mesh, and a symbol bound to nothing is
    # the fallback.
    var single = (
        geometry
        + '<triangles material="a">'
        + triangle
        + "</triangles><triangles>"
        + triangle
        + '</triangles><lines><input semantic="VERTEX" source="#v"'
        + ' offset="0"/></lines>'
        + "</mesh></geometry></library_geometries>"
    )
    var plain = Scene()
    var plain_assets = Assets()
    _ = load_collada(dae(materials + single, node), "", plain, plain_assets)
    assert_false(plain.meshes[0].is_multi_material())
    # A line primitive of no corners draws nothing.
    assert_equal(len(plain.lines), 0)
    # A line primitive with no positions is refused.
    refused(
        dae(
            geometry
            + '<lines><input semantic="NORMAL" source="#p" offset="0"/>'
            + "<p>0 1</p></lines></mesh></geometry></library_geometries>",
            '<node><instance_geometry url="#g"/></node>',
        )
    )
    # Two primitives that disagree about normals are refused.
    refused(
        dae(
            geometry
            + '<source id="n"><float_array>0 0 1</float_array>'
            + '<technique_common><accessor stride="3"/></technique_common>'
            + '</source><triangles><input semantic="VERTEX" source="#v"'
            + ' offset="0"/><input semantic="NORMAL" source="#n"'
            + ' offset="1"/><p>0 0 1 0 2 0</p></triangles><triangles>'
            + triangle
            + "</triangles></mesh></geometry></library_geometries>",
            '<node><instance_geometry url="#g"/></node>',
        )
    )


def test_cameras_and_lights() raises:
    var libraries = String(
        "<library_cameras>"
        '<camera id="plain"/>'
        '<camera id="bare"><optics/></camera>'
        "<camera"
        ' id="odd"><optics><technique_common><other/></technique_common></optics></camera>'
        "<camera"
        ' id="wide"><optics><technique_common><perspective><xfov>90</xfov></perspective></technique_common></optics></camera>'
        "<camera"
        ' id="tall"><optics><technique_common><orthographic><ymag>2</ymag><aspect_ratio>2</aspect_ratio></orthographic></technique_common></optics></camera>'
        "<camera"
        ' id="box"><optics><technique_common><orthographic><xmag>2</xmag><ymag>6</ymag></orthographic></technique_common></optics></camera>'
        "</library_cameras>"
        "<library_lights>"
        "<light"
        ' id="sun"><technique_common><directional/></technique_common></light>'
        "<light"
        ' id="cone"><technique_common><spot><quadratic_attenuation>4</quadratic_attenuation></spot></technique_common></light>'
        "<light"
        ' id="bulb"><technique_common><other/><point/></technique_common></light>'
        "</library_lights>"
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(
        dae(
            libraries,
            '<node><instance_camera url="#plain"/><instance_camera'
            ' url="#bare"/>'
            + '<instance_camera url="#odd"/><instance_camera url="#wide"/>'
            + '<instance_camera url="#tall"/><instance_camera'
            ' url="#box"/></node>'
            + '<node><instance_light url="#sun"/></node>'
            + '<node><instance_light url="#cone"/><node/></node>'
            + '<node><instance_light url="#bulb"/><instance_light'
            ' url="#bulb"/></node>',
        ),
        "",
        scene,
        assets,
    )
    assert_equal(len(model.perspective_cameras), 4)
    for index in range(4):
        var camera = model.perspective_cameras[index]
        assert_almost_equal(camera.fov.to(DEGREE), 50, atol=1e-4)
        assert_almost_equal(camera.aspect, 1)
        assert_almost_equal(camera.near.value, 0.1)
        assert_almost_equal(camera.far.value, 2000)
    assert_equal(len(model.orthographic_cameras), 2)
    assert_almost_equal(model.orthographic_cameras[0].right.value, 2)
    assert_almost_equal(model.orthographic_cameras[0].top.value, 1)
    assert_almost_equal(model.orthographic_cameras[1].right.value, 1)
    assert_almost_equal(model.orthographic_cameras[1].top.value, 3)
    assert_equal(model.light_count, 4)
    assert_equal(scene.lights[0].node, model.nodes[1])
    assert_equal(scene.lights[0].color.r, 255)
    # The cone is one object beside a child node: one unit up its y.
    var cone = scene.lights[1]
    assert_true(cone.node != model.nodes[2])
    assert_almost_equal(cone.distance, 0.5)
    scene.update()
    assert_near(scene.world_position(cone.node), 0, 1, 0)
    assert_equal(scene.lights[2].node, model.nodes[4])
    refused(
        dae(
            '<library_lights><light id="x"/></library_lights>',
            '<node><instance_light url="#x"/></node>',
        )
    )
    for camera in [
        "<orthographic/>",
        "<orthographic><xmag>2</xmag></orthographic>",
        "<orthographic><ymag>2</ymag></orthographic>",
        "<perspective><yfov>0</yfov></perspective>",
    ]:
        refused(
            dae(
                '<library_cameras><camera id="x"><optics><technique_common>'
                + camera
                + "</technique_common></optics></camera></library_cameras>",
                '<node><instance_camera url="#x"/></node>',
            )
        )


def test_nodes() raises:
    # Steps in order: a matrix, then a scale; a node without a name.
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(
        dae(
            TRI
            + '<library_nodes><node id="lib"><translate>1 0 0</translate>'
            + '<instance_geometry url="#g"/><node'
            ' id="inner"/></node></library_nodes>',
            "<node><matrix>0 -1 0 0 1 0 0 0 0 0 1 0 0 0 0 1</matrix>"
            + "<scale>1 2 3</scale><skew/></node>"
            + '<node id="dup"><instance_node url="#lib"/></node>'
            + '<node id="dup"><instance_node url="#lib"/><node/></node>',
        ),
        "",
        scene,
        assets,
    )
    var turned = scene.get(model.nodes[0])
    assert_near(turned.scale, 1, 2, 3)
    assert_almost_equal(turned.quaternion.z, 0.70710677, atol=1e-6)
    assert_equal(model.node_names[0], "")
    # A node whose one object is an instanced node takes the copy's
    # contents at its own transform, as three.js takes the copy's place;
    # beside a child node, the copy keeps its own transform.
    assert_equal(len(model.nodes), 7)
    assert_near(scene.get(model.nodes[1]).position, 0, 0, 0)
    assert_equal(scene.get(model.nodes[2]).parent, model.nodes[1])
    assert_equal(scene.meshes[0].node, model.nodes[1])
    assert_equal(scene.get(model.nodes[4]).parent, model.nodes[3])
    assert_near(scene.get(model.nodes[5]).position, 1, 0, 0)
    assert_equal(scene.get(model.nodes[6]).parent, model.nodes[5])
    assert_equal(scene.meshes[1].node, model.nodes[5])
    # What is refused.
    refused(dae(TRI, '<node><instance_geometry url="#none"/></node>'))
    refused(dae("", '<node><instance_node url="#none"/></node>'))
    refused(
        dae(
            "",
            (
                '<node><instance_node url="#loop"/></node><node'
                ' id="loop"><instance_node url="#loop"/></node>'
            ),
        )
    )
    refused(dae("", "<node><translate>1 2</translate></node>"))
    refused(dae("", "<node><rotate>1 0 0</rotate></node>"))
    refused(dae("", "<node><scale>0 1 1</scale></node>"))
    refused(dae("", "<node><matrix>1 0 0 0</matrix></node>"))
    refused(dae("", "<node><translate>1 2 1e39</translate></node>"))
    refused(dae("", "<node><translate>1 2 x</translate></node>"))


def test_refused() raises:
    refused("<scene/>")
    refused("not xml")
    refused("<COLLADA/>")
    refused("<COLLADA><scene/></COLLADA>")
    refused(
        '<COLLADA><scene><instance_visual_scene url="#none"/></scene></COLLADA>'
    )
    refused(
        dae(
            TRI,
            "<node><instance_geometry"
            ' url="#g"><bind_material><technique_common>'
            + '<instance_material symbol="m"'
            ' target="#none"/></technique_common>'
            + "</bind_material></instance_geometry></node>",
        )
    )
    var mesh = (
        '<source id="p"><float_array>0 0 0 1 0 0 0 1 0</float_array>'
        + '<technique_common><accessor stride="3"/></technique_common></source>'
        + '<source id="n"><float_array>0 0 1</float_array></source>'
        + '<source id="c"><float_array>1 1 1 1 1</float_array>'
        + '<technique_common><accessor stride="5"/></technique_common></source>'
        + '<vertices id="v"><input semantic="POSITION" source="#p"/></vertices>'
    )
    for primitive in [
        "<triangles><p>0 1 2</p></triangles>",
        (
            '<triangles><input semantic="VERTEX" source="#v"/><p>0 1'
            " 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="-1"/><p>0'
            " 1 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><p>0'
            " 1</p></triangles>"
        ),
        (
            '<lines><input semantic="VERTEX" source="#v" offset="0"/><p>0 1'
            " 2</p></lines>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><input'
            ' semantic="NORMAL" source="#p" offset="1"/><p>0 1'
            " 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><p>0 1'
            " 3</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><p>0 1'
            " -1</p></triangles>"
        ),
        (
            '<triangles><input semantic="NORMAL" source="#n" offset="0"/><p>0 0'
            " 0</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><input'
            ' semantic="NORMAL" source="#none" offset="0"/><p>0 1'
            " 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><input'
            ' semantic="NORMAL" source="#n" offset="0"/><p>0 1'
            " 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><input'
            ' semantic="COLOR" source="#c" offset="0"/><p>0 0 0</p></triangles>'
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><input'
            ' semantic="TEXCOORD" source="#n" offset="0"/><p>0 1'
            " 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><input'
            ' semantic="NORMAL" source="#p" offset="0"/><input'
            ' semantic="NORMAL" source="#p" offset="0"/><p>0 1'
            " 2</p></triangles>"
        ),
        (
            '<triangles><input semantic="VERTEX" source="#v" offset="0"/><p>0 1'
            " x</p></triangles>"
        ),
        (
            '<polylist><input semantic="VERTEX" source="#v"'
            ' offset="0"/><vcount>4</vcount><p>0 1 2</p></polylist>'
        ),
        (
            '<polylist><input semantic="VERTEX" source="#v" offset="0"/><p>0 1'
            " 2</p></polylist>"
        ),
        (
            '<polygons><input semantic="VERTEX" source="#v"'
            ' offset="0"/><ph><p>0 1 2</p></ph></polygons>'
        ),
    ]:
        refused(
            dae(
                '<library_geometries><geometry id="g"><mesh>'
                + mesh
                + primitive
                + "</mesh></geometry></library_geometries>",
                '<node><instance_geometry url="#g"/></node>',
            )
        )
    refused(
        dae(
            (
                "<library_geometries><geometry"
                ' id="g"><convex_mesh/></geometry></library_geometries>'
            ),
            '<node><instance_geometry url="#g"/></node>',
        )
    )
    refused(
        dae(
            '<library_geometries><geometry id="g"><mesh><source id="z">'
            + "<technique_common><accessor"
            ' stride="0"/></technique_common></source>'
            + "</mesh></geometry></library_geometries>",
            '<node><instance_geometry url="#g"/></node>',
        )
    )


def test_read_file() raises:
    var scene = Scene()
    var assets = Assets()
    Path("out/scene.dae").write_text(SCENE)
    var model = read_collada("out/scene.dae", scene, assets)
    assert_equal(model.mesh_count, 5)
    with assert_raises():
        _ = read_collada("out/none.dae", scene, assets)


def test_model_nodes() raises:
    var node = Object3D()
    var flip = Matrix4()
    flip.set(-1, 0, 0, 1, 0, 1, 0, 2, 0, 0, 1, 3, 0, 0, 0, 1)
    decompose_onto(node, flip, "test")
    assert_near(node.scale, -1, 1, 1)
    assert_near(node.position, 1, 2, 3)
    var back = compose(node)
    for index in range(16):
        assert_almost_equal(
            back.elements[index], flip.elements[index], atol=1e-6
        )
    for column in [0, 4, 8]:
        var flat = Matrix4()
        flat.elements[column] = 0
        flat.elements[column + 1] = 0
        flat.elements[column + 2] = 0
        with assert_raises():
            decompose_onto(node, flat, "test")
    var infinite = Matrix4()
    infinite.elements[12] = Float32.MAX * 2
    with assert_raises():
        decompose_onto(node, infinite, "test")
    assert_equal(authored_color(1, 0.5, 0, "test").g, 128)
    for bad in [Float64(-0.5), Float64(1.5), Float64.MAX * 2 - Float64.MAX * 2]:
        with assert_raises():
            _ = authored_color(bad, 0, 0, "test")
    with assert_raises():
        _ = texture_from_file("assets/none.png", SRGB, REPEAT, COVERAGE)
    var image = texture_from_file(HERE + "checker.png", LINEAR, CLAMP, IGNORED)
    assert_equal(image.width, 2)


def test_edges() raises:
    """Documents that are thin in every way a loop can be: empty lists,
    empty meshes, a primitive's positions given directly, and lines bound
    to a basic and to a lit material."""
    var libraries = String(
        "<library_effects><effect"
        ' id="lit"><profile_COMMON><technique><phong/></technique></profile_COMMON></effect><effect'
        ' id="plain"><profile_COMMON><technique><constant/></technique></profile_COMMON></effect></library_effects><library_materials><material'
        ' id="lit"><instance_effect url="#lit"/></material><material'
        ' id="plain"><instance_effect'
        ' url="#plain"/></material></library_materials><library_cameras><camera'
        ' id="c"><optics><technique_common/></optics></camera></library_cameras><library_geometries><geometry'
        ' id="empty"><mesh/></geometry><geometry id="direct"><mesh><source'
        ' id="p"><float_array>0 0 0 1 0 0 0 1'
        " 0</float_array><technique_common><accessor"
        ' stride="3"/></technique_common></source><source'
        ' id="none"><float_array></float_array></source><triangles><input'
        ' semantic="POSITION" source="#p" offset="0" set="1 2"/><p>0 1'
        ' 2</p></triangles><triangles><input semantic="POSITION" source="#p"'
        ' offset="0"/><p></p></triangles><polylist><input semantic="POSITION"'
        ' source="#p" offset="0"/><vcount></vcount></polylist><linestrips'
        ' material="a"><input semantic="POSITION" source="#p"'
        ' offset="0"/></linestrips><lines material="a"><input'
        ' semantic="POSITION" source="#p" offset="0"/><p>0 1</p></lines><lines'
        ' material="b"><input semantic="POSITION" source="#p" offset="0"/><p>1'
        ' 2</p></lines><lines material="c"><input semantic="POSITION"'
        ' source="#p" offset="0"/><p>0'
        " 2</p></lines></mesh></geometry></library_geometries>"
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_collada(
        dae(
            libraries,
            '<node><instance_geometry url="#empty"><bind_material/>'
            + '</instance_geometry><instance_camera url="#c"/></node>'
            + '<node><instance_geometry url="#direct"><bind_material>'
            + '<technique_common><instance_material symbol="a" target="#lit"/>'
            + '<instance_material symbol="b" target="#lit"/>'
            + '<instance_material symbol="c" target="#plain"/>'
            + "</technique_common></bind_material></instance_geometry></node>",
        ),
        "",
        scene,
        assets,
    )
    assert_equal(model.mesh_count, 1)
    assert_equal(model.line_count, 3)
    assert_equal(len(model.perspective_cameras), 1)
    # Both lines of the lit material share one basic copy of it; the
    # line of the basic material draws with it as it is.
    assert_equal(scene.lines[0].material, scene.lines[1].material)
    assert_true(scene.lines[0].material != model.materials[0])
    assert_equal(scene.lines[2].material, model.materials[1])
    refused(
        dae(
            (
                "<library_lights><light"
                ' id="x"><technique_common/></light></library_lights>'
            ),
            '<node><instance_light url="#x"/></node>',
        )
    )
    for input in [
        '<input semantic="POSITION" source="#p" offset="1 2"/>',
        '<input semantic="VERTEX" source="#v" offset="0"/>',
    ]:
        refused(
            dae(
                '<library_geometries><geometry id="g"><mesh>'
                + '<source id="p"><float_array>0 0 0</float_array></source>'
                + '<vertices id="v"/><triangles>'
                + input
                + "<p>0 0"
                " 0</p></triangles></mesh></geometry></library_geometries>",
                '<node><instance_geometry url="#g"/></node>',
            )
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
