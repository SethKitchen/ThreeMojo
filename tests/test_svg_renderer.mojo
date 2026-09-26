# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `renderers.svg_renderer` and `renderers.projector`.

`assets/svg_renderer/svg.json` holds what three.js 0.180's `SVGRenderer`
writes for one scene, three times: plain; at a precision of two, low
quality, a blue clear color and no overdraw; and unsorted. It was made in
Node by `three_svg.mjs` beside it, and the scene here is the same one. A
path's commands must match exactly and its numbers to a small part of a
pixel: the camera's matrices here are single precision, where three.js's
are double.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import color_background
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from lights.light import (
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
)
from loaders.js_number import js_string_to_number
from loaders.json import JsonDocument, parse_json
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    LAMBERT,
    Material,
    MaterialId,
    PointSize,
    TOON,
    normal_material,
)
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color
from renderers.projector import (
    RENDERABLE_FACE,
    RENDERABLE_LINE,
    RENDERABLE_SPRITE,
    RenderableKind,
    project_scene,
)
from renderers.svg_renderer import (
    HIGH_QUALITY,
    LOW_QUALITY,
    SVGRenderer,
    SvgImage,
    SvgQuality,
    color_style,
)
from renderers.projector import Vec
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, RADIAN, Angle, Length


def _node(
    mut scene: Scene, x: Float32, y: Float32, z: Float32
) raises -> NodeId:
    """Add a node at a place."""
    var node = Object3D()
    node.set_position(x, y, z)
    return scene.add(node^)


def _through(points: List[Vector3]) raises -> BufferGeometry:
    """Return a geometry of positions only, three.js's `setFromPoints`."""
    var geometry = BufferGeometry()
    geometry.set_from_points(points)
    return geometry^


def _scene(mut scene: Scene, mut assets: Assets) raises:
    """Build the scene of `three_svg.mjs`."""
    scene.add_light(ambient_light(Color(0x20, 0x20, 0x40), 3))
    scene.add_light(
        directional_light(Color(0xFF, 0xEE, 0xCC), _node(scene, 2, 4, 3), 2)
    )
    scene.add_light(
        point_light(
            Color(0x88, 0xCC, 0xFF),
            _node(scene, -3, 1, 2),
            1.5,
            distance=12,
        )
    )
    var side = Length(1.0, METER)
    var cube = assets.geometries.add(box(side, side, side))
    var lit = Object3D()
    lit.set_position(-1.5, 0, 0)
    lit.set_euler(Angle(0.0, RADIAN), Angle(0.5, RADIAN), Angle(0.0, RADIAN))
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(
                    Color(0xCC, 0x88, 0x44),
                    kind=LAMBERT,
                    emissive=Color(0x10, 0, 0),
                )
            ),
            scene.add(lit^),
        )
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(normal_material()),
            _node(scene, 0, 0, -1),
        )
    )
    var flat = plane(Length(2.0, METER), Length(1.0, METER))
    var colors: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0]
    flat.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(flat^),
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    kind=BASIC,
                    vertex_colors=True,
                    side=DOUBLE_SIDE,
                    opacity=0.75,
                    transparent=True,
                )
            ),
            _node(scene, 1.5, 0.5, 0.5),
        )
    )
    var wire = Object3D()
    wire.set_position(1.5, -1, 0)
    wire.set_scale(0.5, 0.5, 0.5)
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(Color(0x33, 0xFF, 0x33), kind=BASIC, wireframe=True)
            ),
            scene.add(wire^),
        )
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    kind=BASIC,
                    opacity=0,
                    transparent=True,
                )
            ),
            _node(scene, 0, 0, 0),
        )
    )
    var plain = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var hidden = Object3D()
    hidden.visible = False
    var cover = scene.add(hidden^)
    scene.add_mesh(Mesh(cube, plain, cover))
    scene.add_mesh(Mesh(cube, plain, scene.attach(Object3D(), cover)))
    scene.add_line(
        Line(
            assets.geometries.add(
                _through(
                    [Vector3(-2, 1.5, 0), Vector3(-1, 2, 0), Vector3(0, 1.5, 0)]
                )
            ),
            assets.materials.add(Material(Color(0xFF, 0, 0xFF), kind=BASIC)),
            _node(scene, 0, 0, 0),
        )
    )
    scene.add_line(
        Line(
            assets.geometries.add(
                _through(
                    [
                        Vector3(0.5, -1.5, 0),
                        Vector3(1, -2, 0),
                        Vector3(2, -1.5, 0),
                        Vector3(2.5, -2, 0),
                    ]
                )
            ),
            assets.materials.add(
                Material(Color(0, 0xFF, 0xFF), kind=BASIC, opacity=0.5)
            ),
            _node(scene, 0, 0, 0),
            mode=SEGMENTS,
        )
    )
    scene.add_line(
        Line(
            assets.geometries.add(
                _through([Vector3(-0.5, -0.5, 0), Vector3(0.25, -0.25, 12)])
            ),
            assets.materials.add(
                Material(
                    Color(0xFF, 0xFF, 0),
                    kind=BASIC,
                    dash_size=Length(2.0, METER),
                    gap_size=Length(0.5, METER),
                )
            ),
            _node(scene, 0, 0, 0),
        )
    )
    scene.add_points(
        Points(
            assets.geometries.add(
                _through([Vector3(-2, -1, 1), Vector3(-1.5, -1.5, 1)])
            ),
            assets.materials.add(
                Material(
                    Color(0xFF, 0x88, 0),
                    kind=BASIC,
                    point_size=PointSize(0.2),
                )
            ),
            _node(scene, 0, 0, 0),
        )
    )
    var card = Object3D()
    card.set_position(0, 2.25, 1)
    card.set_scale(0.5, 0.25, 1)
    scene.add_sprite(
        Sprite(
            assets.materials.add(
                Material(
                    Color(0x44, 0x44, 0xFF),
                    kind=BASIC,
                    opacity=0.5,
                    transparent=True,
                )
            ),
            scene.add(card^),
        )
    )


def _camera() raises -> PerspectiveCamera:
    """Return the reference's camera."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(400) / 300,
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.position = Vector3(0, 1, 8)
    camera.target = Vector3(0, 0, 0)
    return camera^


def _tokens(d: String) raises -> List[String]:
    """Split a path's outline into its commands and its numbers."""
    var out = List[String]()
    var number = String()
    for byte in d.as_bytes():
        var c = chr(Int(byte))
        if c == "M" or c == "L" or c == "h" or c == "v" or c == "z" or c == ",":
            if number.byte_length() > 0:
                out.append(number)
                number = String()
            if c != ",":
                out.append(c)
        else:
            number += c
    if number.byte_length() > 0:
        out.append(number)
    return out^


def _same_outline(got: String, want: String) raises:
    """Check two outlines: the same commands, and numbers near."""
    var a = _tokens(got)
    var b = _tokens(want)
    assert_equal(len(a), len(b))
    for k in range(len(a)):
        var letter = (
            b[k] == "M"
            or b[k] == "L"
            or b[k] == "h"
            or b[k] == "v"
            or b[k] == "z"
        )
        if letter:
            assert_equal(a[k], b[k])
        else:
            var x = js_string_to_number(a[k])
            var y = js_string_to_number(b[k])
            assert_almost_equal(x, y, atol=0.02 + 2e-5 * abs(y))


def _same_image(image: SvgImage, doc: JsonDocument, name: String) raises:
    """Check a render against one of the reference's renders."""
    var want = doc.get(doc.root(), name)
    var attributes = doc.get(want, "attributes")
    assert_equal(image.view_box, doc.string(doc.get(attributes, "viewBox")))
    assert_equal(String(image.width), doc.string(doc.get(attributes, "width")))
    assert_equal(image.background, doc.string(doc.get(want, "background")))
    var paths = doc.get(want, "paths")
    assert_equal(len(image.paths), doc.length(paths))
    for at in range(len(image.paths)):
        var path = doc.at(paths, at)
        assert_equal(image.paths[at].style, doc.string(doc.get(path, "style")))
        assert_equal(image.paths[at].crisp, doc.has(path, "shape-rendering"))
        _same_outline(image.paths[at].d, doc.string(doc.get(path, "d")))


def _reference() raises -> JsonDocument:
    """Return what three.js wrote."""
    return parse_json(Path("assets/svg_renderer/svg.json").read_text())


def test_a_scene_is_drawn_as_three_js_draws_it() raises:
    var doc = _reference()
    var scene = Scene()
    var assets = Assets()
    _scene(scene, assets)
    var renderer = SVGRenderer(400, 300)
    var image = renderer.render(scene, assets, _camera())
    _same_image(image, doc, "plain")
    var info = doc.get(doc.get(doc.root(), "plain"), "info")
    assert_equal(renderer.faces, doc.integer(doc.get(info, "faces")))
    assert_equal(renderer.vertices, doc.integer(doc.get(info, "vertices")))


def test_precision_quality_clear_color_and_overdraw() raises:
    var doc = _reference()
    var scene = Scene()
    var assets = Assets()
    _scene(scene, assets)
    var renderer = SVGRenderer()
    renderer.set_size(400, 300)
    renderer.set_precision(2)
    renderer.set_quality(LOW_QUALITY)
    renderer.set_clear_color(Color(0x33, 0x66, 0x99))
    renderer.overdraw = 0
    _same_image(renderer.render(scene, assets, _camera()), doc, "precise")


def test_an_unsorted_render_keeps_the_scene_order() raises:
    var doc = _reference()
    var scene = Scene()
    var assets = Assets()
    _scene(scene, assets)
    var renderer = SVGRenderer(400, 300)
    renderer.sort_objects = False
    renderer.sort_elements = False
    _same_image(renderer.render(scene, assets, _camera()), doc, "unsorted")


def test_the_settings_are_checked() raises:
    var renderer = SVGRenderer(4, 2)
    with assert_raises(contains="precision"):
        renderer.set_precision(101)
    with assert_raises(contains="precision"):
        renderer.set_precision(-2)
    renderer.set_precision(-1)
    with assert_raises(contains="quality"):
        renderer.set_quality(SvgQuality(2))
    assert_true(HIGH_QUALITY.is_valid())
    assert_false(SvgQuality(-1).is_valid())
    assert_equal(String(LOW_QUALITY), "LOW_QUALITY")
    assert_equal(String(HIGH_QUALITY), "HIGH_QUALITY")
    assert_equal(String(SvgQuality(5)), "SvgQuality(5)")
    assert_true(RenderableKind(2).is_valid())
    assert_false(RenderableKind(3).is_valid())
    assert_false(RenderableKind(-1).is_valid())
    assert_equal(String(RENDERABLE_FACE), "RENDERABLE_FACE")
    assert_equal(String(RENDERABLE_LINE), "RENDERABLE_LINE")
    assert_equal(String(RENDERABLE_SPRITE), "RENDERABLE_SPRITE")
    assert_equal(String(RenderableKind(7)), "RenderableKind(7)")
    # An odd size puts the origin between pixels.
    renderer.set_size(5, 3)
    assert_equal(renderer.view_box(), "-2.5 -1.5 5 3")


def test_a_color_is_written_as_three_js_writes_it() raises:
    assert_equal(color_style(Vec(0, 1, 0.5, 0)), "rgb(0,255,188)")
    # Past one is not clamped, and nothing is NaN.
    assert_equal(color_style(Vec(2, 0.001, -1, 0)), "rgb(345,3,-3295)")


def _small(mut scene: Scene, mut assets: Assets, material: Material) raises:
    """Add one triangle of a material in front of `_near_camera`."""
    var shape = BufferGeometry()
    shape.set_from_points(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(shape^),
            assets.materials.add(material.copy()),
            scene.add(Object3D()),
        )
    )


def _near_camera() raises -> PerspectiveCamera:
    """Return a camera five meters up +z, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.position = Vector3(0, 0, 5)
    camera.target = Vector3(0, 0, 0)
    return camera^


def test_a_background_a_kept_image_and_the_text() raises:
    var scene = Scene()
    var assets = Assets()
    _small(scene, assets, Material(Color(255, 0, 0), kind=BASIC))
    var renderer = SVGRenderer(10, 10)
    renderer.auto_clear = False
    var first = renderer.render(scene, assets, _near_camera())
    # Not cleared: no background, and the paths pile up.
    assert_equal(first.background, "")
    var second = renderer.render(scene, assets, _near_camera())
    assert_equal(len(second.paths), 2)
    scene.background = color_background(Color(0, 0, 255))
    var third = renderer.render(scene, assets, _near_camera())
    assert_equal(third.background, "rgb(0,0,255)")
    assert_equal(len(third.paths), 1)
    renderer.set_quality(LOW_QUALITY)
    renderer.clear()
    var text = renderer.render(scene, assets, _near_camera()).text()
    assert_true(text.startswith('<svg xmlns="http://www.w3.org/2000/svg"'))
    assert_true('style="background-color:rgb(0,0,255)"' in text)
    # The path was made at high quality, and is not crisp.
    assert_false("crispEdges" in text)
    assert_true("fill:rgb(255,0,0);fill-opacity:1" in text)
    var bare = SvgImage(1, 1, "0 0 1 1", "", [])
    assert_false("background" in bare.text())


def test_a_face_of_another_material_keeps_the_last_color() raises:
    var scene = Scene()
    var assets = Assets()
    _small(scene, assets, Material(Color(255, 255, 255), kind=TOON))
    var renderer = SVGRenderer(10, 10)
    var image = renderer.render(scene, assets, _near_camera())
    assert_equal(image.paths[0].style, "fill:rgb(255,255,255);fill-opacity:1")


def test_lines_and_sprites_of_other_materials() raises:
    var scene = Scene()
    var assets = Assets()
    var lit = assets.materials.add(Material(Color(255, 0, 0), kind=LAMBERT))
    var path = BufferGeometry()
    path.set_from_points([Vector3(0, 0, 0), Vector3(1, 0, 0)])
    var aside = BufferGeometry()
    aside.set_from_points([Vector3(40, 0, 0), Vector3(41, 0, 0)])
    var node = scene.add(Object3D())
    scene.add_line(Line(assets.geometries.add(path^), lit, node))
    var far = Line(assets.geometries.add(aside^), lit, node)
    far.frustum_culled = False
    scene.add_line(far)
    scene.add_sprite(Sprite(lit, node))
    var renderer = SVGRenderer(10, 10)
    var image = renderer.render(scene, assets, _near_camera())
    # No stroke for a lit line; a sprite with no style.
    assert_equal(len(image.paths), 1)
    assert_equal(image.paths[0].style, "")
    assert_true(image.paths[0].d.startswith("M"))


def test_the_flat_lighting_rule() raises:
    var scene = Scene()
    var assets = Assets()
    var lamp = scene.add(Object3D())
    var behind = Object3D()
    behind.set_position(0, 0, -5)
    var back = scene.add(behind^)
    var close = Object3D()
    close.set_position(0.3, 0.3, 0.001)
    var touching = scene.add(close^)
    var over = Object3D()
    over.set_position(0, 0, 3)
    var above = scene.add(over^)
    # Behind the face, and so dark; at the face, with a distance that
    # leaves nothing; with no distance; and a hemisphere light, which
    # the rule does not read.
    scene.add_light(point_light(Color(255, 255, 255), back, 1))
    scene.add_light(directional_light(Color(255, 255, 255), back, 1))
    scene.add_light(
        point_light(Color(255, 255, 255), touching, 1, distance=0.5)
    )
    scene.add_light(point_light(Color(0, 255, 0), above, 1))
    scene.add_light(
        hemisphere_light(Color(255, 255, 255), Color(0, 0, 0), lamp)
    )
    _small(scene, assets, Material(Color(255, 255, 255), kind=LAMBERT))
    var renderer = SVGRenderer(10, 10)
    var image = renderer.render(scene, assets, _near_camera())
    # Only the green light above reaches the face.
    assert_true(image.paths[0].style.startswith("fill:rgb(0,25"))
    assert_true(image.paths[0].style.endswith(",0);fill-opacity:1"))


def test_a_face_past_the_far_plane_or_of_one_point_is_skipped() raises:
    var scene = Scene()
    var assets = Assets()
    var shape = BufferGeometry()
    # One corner past the far plane, and a face whose corners meet.
    shape.set_from_points(
        [
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, -200),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
        ]
    )
    var paint = Material(Color(255, 255, 255), kind=BASIC)
    paint.side = DOUBLE_SIDE
    scene.add_mesh(
        Mesh(
            assets.geometries.add(shape^),
            assets.materials.add(paint^),
            scene.add(Object3D()),
        )
    )
    var renderer = SVGRenderer(10, 10)
    var image = renderer.render(scene, assets, _near_camera())
    assert_equal(renderer.faces, 1)
    assert_equal(len(image.paths), 1)


def test_a_crisp_path_an_empty_scene_and_a_near_corner() raises:
    var scene = Scene()
    var assets = Assets()
    var renderer = SVGRenderer(10, 10)
    renderer.set_quality(LOW_QUALITY)
    assert_equal(len(renderer.render(scene, assets, _near_camera()).paths), 0)
    # Lit by nothing, with vertex colors.
    var shaded = BufferGeometry()
    shaded.set_from_points(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
    )
    var colors: List[Float32] = [1, 1, 1, 1, 1, 1, 1, 1, 1]
    shaded.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(shaded^),
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    kind=LAMBERT,
                    vertex_colors=True,
                    emissive=Color(255, 0, 0),
                )
            ),
            scene.add(Object3D()),
        )
    )
    # A face with a corner between the camera and the near plane.
    var close = BufferGeometry()
    close.set_from_points(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 4.99)]
    )
    var both = Material(Color(0, 0, 255), kind=BASIC)
    both.side = DOUBLE_SIDE
    scene.add_mesh(
        Mesh(
            assets.geometries.add(close^),
            assets.materials.add(both^),
            scene.add(Object3D()),
        )
    )
    var image = renderer.render(scene, assets, _near_camera())
    assert_equal(renderer.faces, 1)
    assert_equal(image.paths[0].style, "fill:rgb(255,0,0);fill-opacity:1")
    assert_true('shape-rendering="crispEdges"' in image.text())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
