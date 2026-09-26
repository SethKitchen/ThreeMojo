# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `renderers.projector`, the parts the SVG scene does not reach.

The camera stands five meters up +z and looks at the origin, with a field
of view of 90 degrees: at the origin, the view is ten meters across.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, MaterialIndex
from core.morph import MorphInfluences
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, point_light
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    Material,
    MaterialId,
)
from math.matrix4 import Matrix4, scaling
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color
from renderers.projector import (
    Matrix,
    RENDERABLE_FACE,
    RENDERABLE_LINE,
    RENDERABLE_SPRITE,
    RenderData,
    Vec,
    _clip_line,
    apply_normal,
    project_scene,
)
from std.math import isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length


def _camera() raises -> PerspectiveCamera:
    """Return the module docstring's camera."""
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.position = Vector3(0, 0, 5)
    camera.target = Vector3(0, 0, 0)
    return camera^


def _project(
    mut scene: Scene, assets: Assets, sort: Bool = True
) raises -> RenderData:
    """Project a scene through the module docstring's camera."""
    var camera = _camera()
    return project_scene(
        scene,
        assets,
        camera.projection_matrix(),
        camera.view_matrix(),
        sort,
        sort,
    )


def _through(points: List[Vector3]) raises -> BufferGeometry:
    """Return a geometry of positions only."""
    var geometry = BufferGeometry()
    geometry.set_from_points(points)
    return geometry^


def _plain(mut assets: Assets, side: Int = 0) raises -> MaterialId:
    """Add a white basic material, front-sided or of another side."""
    var material = Material(Color(255, 255, 255), kind=BASIC)
    if side == 1:
        material.side = BACK_SIDE
    elif side == 2:
        material.side = DOUBLE_SIDE
    return assets.materials.add(material^)


def _node(mut scene: Scene) raises -> NodeId:
    """Add a node at the origin."""
    return scene.add(Object3D())


def test_a_face_turned_away_is_culled_unless_double_sided() raises:
    var scene = Scene()
    var assets = Assets()
    # Counterclockwise from the camera, then clockwise.
    var toward = assets.geometries.add(
        _through([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
    )
    var away = assets.geometries.add(
        _through([Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)])
    )
    scene.add_mesh(Mesh(toward, _plain(assets), _node(scene)))
    scene.add_mesh(Mesh(away, _plain(assets), _node(scene)))
    scene.add_mesh(Mesh(away, _plain(assets, 1), _node(scene)))
    scene.add_mesh(Mesh(away, _plain(assets, 2), _node(scene)))
    var data = _project(scene, assets)
    assert_equal(len(data.elements), 2)
    ref face = data.elements[0]
    assert_true(face.kind == RENDERABLE_FACE)
    # The normal faces the camera, and with no normals or texture
    # coordinates, the corners read NaN.
    assert_almost_equal(face.normal[2], 1)
    assert_true(isnan(face.vertex_normals[0][0]))
    assert_true(isnan(face.uvs[2][1]))
    assert_equal(face.colors[0][0], 1)
    assert_equal(len(face.vertices), 3)


def test_a_face_off_screen_is_dropped_and_one_around_it_is_kept() raises:
    var scene = Scene()
    var assets = Assets()
    var aside = assets.geometries.add(
        _through([Vector3(20, 0, 0), Vector3(21, 0, 0), Vector3(20, 1, 0)])
    )
    var around = assets.geometries.add(
        _through([Vector3(-50, -50, 0), Vector3(50, -50, 0), Vector3(0, 50, 0)])
    )
    var paint = _plain(assets)
    var far = scene.add(Object3D())
    scene.add_mesh(Mesh(aside, paint, far, frustum_culled=False))
    scene.add_mesh(Mesh(around, paint, _node(scene)))
    var data = _project(scene, assets)
    assert_equal(len(data.elements), 1)
    # A corner outside the view is not visible, but the box is.
    assert_true(data.elements[0].vertices[0].screen[0] < -1)


def test_morph_targets_groups_and_materials() raises:
    var scene = Scene()
    var assets = Assets()
    var geometry = _through(
        [
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
        ]
    )
    var moved: List[Float32] = [
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        2,
        0,
    ]
    geometry.add_morph_target(BufferAttribute(moved.copy(), 3))
    geometry.add_morph_target(BufferAttribute(moved^, 3))
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(4))
    var shape = assets.geometries.add(geometry^)
    var mesh = Mesh(shape, _plain(assets), _node(scene))
    mesh.materials = [_plain(assets)]
    mesh.morph_influences = MorphInfluences(count=2)
    mesh.morph_influences.weights[0] = 0.5
    scene.add_mesh(mesh)
    var data = _project(scene, assets)
    # The second group names a fifth material, which is not there.
    assert_equal(len(data.elements), 1)
    # Halfway to twice as big: x reaches 1.5.
    assert_almost_equal(data.elements[0].vertices[1].world[0], 1.5)
    # Relative targets add.
    var relative = assets.geometries.get(shape).clone()
    relative.morph_relative = True
    var nudged = assets.geometries.add(relative^)
    var again = Scene()
    var tilted = Mesh(nudged, _plain(assets), _node(again))
    tilted.morph_influences = MorphInfluences(count=2)
    tilted.morph_influences.weights[1] = 1
    again.add_mesh(tilted)
    var added = _project(again, assets)
    assert_almost_equal(added.elements[0].vertices[1].world[0], 3)


def test_an_indexed_mesh_and_one_without_positions() raises:
    var scene = Scene()
    var assets = Assets()
    var geometry = _through(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
    )
    geometry.set_index([0, 1, 2])
    var colors: List[Float32] = [0.5, 0.25, 1, 0, 0, 0, 0, 0, 0]
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var shaded = Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(shaded^),
            _node(scene),
        )
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(BufferGeometry()),
            _plain(assets),
            _node(scene),
            frustum_culled=False,
        )
    )
    var data = _project(scene, assets)
    assert_equal(len(data.elements), 1)
    assert_equal(data.elements[0].colors[0][1], 0.25)


def test_a_face_past_its_vertices_is_refused() raises:
    var scene = Scene()
    var assets = Assets()
    var geometry = _through(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]
    )
    scene.add_mesh(
        Mesh(assets.geometries.add(geometry^), _plain(assets), _node(scene))
    )
    with assert_raises(contains="must name a vertex"):
        _ = _project(scene, assets)


def test_lines_pair_by_index_and_are_clipped() raises:
    var scene = Scene()
    var assets = Assets()
    var pairs = _through([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
    pairs.index = [0, 1, 1, 2, 2]
    var colors: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    pairs.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var colored = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
    )
    scene.add_line(Line(assets.geometries.add(pairs^), colored, _node(scene)))
    with assert_raises(contains="must name a vertex"):
        _ = _project(scene, assets)
    var again = Scene()
    var through = _through(
        [
            Vector3(0, 0, 0),
            Vector3(0, 0, 10),
            Vector3(0, 0, 20),
            Vector3(0, 0, 30),
            Vector3(1, 0, 0),
        ]
    )
    through.index = [0, 1, 2, 3, 1, 4]
    through.set_attribute(
        String(COLOR), BufferAttribute(List[Float32](length=15, fill=0.5), 3)
    )
    again.add_line(Line(assets.geometries.add(through^), colored, _node(again)))
    var data = _project(again, assets)
    # Through the camera: cut at the near plane. Behind it: gone. The
    # last runs from behind the camera to in front, cut at the near plane.
    assert_equal(len(data.elements), 2)
    for element in data.elements:
        assert_true(element.kind == RENDERABLE_LINE)
        assert_true(element.vertices[1].screen[2] <= 1)
        assert_equal(element.colors[1][0], 0.5)


def test_points_and_sprites_near_the_camera() raises:
    var scene = Scene()
    var assets = Assets()
    var dots = assets.geometries.add(
        _through([Vector3(0, 0, 0), Vector3(0, 0, 6)])
    )
    scene.add_points(Points(dots, _plain(assets), _node(scene)))
    # A sprite behind the camera, one kept by its moved center, one not
    # culled at all, and one of a hidden material.
    var behind = Object3D()
    behind.set_position(0, 0, 6)
    var behind_node = scene.add(behind^)
    scene.add_sprite(Sprite(_plain(assets), behind_node))
    var edge = Object3D()
    edge.set_position(0, 5.5, 0)
    var edge_node = scene.add(edge^)
    var shifted = Sprite(_plain(assets), edge_node)
    shifted.center = Vector2(0.5, 2)
    scene.add_sprite(shifted)
    var gone = Object3D()
    gone.set_position(0, 7, 0)
    var gone_node = scene.add(gone^)
    scene.add_sprite(Sprite(_plain(assets), gone_node))
    var unculled = Sprite(_plain(assets), gone_node)
    unculled.frustum_culled = False
    scene.add_sprite(unculled)
    var hidden = Material(Color(255, 255, 255), kind=BASIC)
    hidden.visible = False
    scene.add_sprite(Sprite(assets.materials.add(hidden^), _node(scene)))
    var data = _project(scene, assets)
    var points = 0
    var sprites = 0
    for element in data.elements:
        assert_true(element.kind == RENDERABLE_SPRITE)
        if element.is_point:
            points += 1
        else:
            sprites += 1
    assert_equal(points, 1)
    assert_equal(sprites, 2)


def test_order_lights_and_hidden_nodes() raises:
    var scene = Scene()
    var assets = Assets()
    var cover = Object3D()
    cover.visible = False
    var hidden = scene.add(cover^)
    scene.add_light(point_light(Color(255, 255, 255), hidden))
    scene.add_light(ambient_light(Color(255, 255, 255)))
    var lamp = _node(scene)
    scene.add_light(point_light(Color(255, 255, 255), lamp))
    var near = assets.geometries.add(
        _through([Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1)])
    )
    var far = assets.geometries.add(
        _through([Vector3(0, 0, -1), Vector3(1, 0, -1), Vector3(0, 1, -1)])
    )
    var first = Object3D()
    first.render_order = 1
    scene.add_mesh(Mesh(far, _plain(assets), scene.add(first^)))
    scene.add_mesh(Mesh(near, _plain(assets), _node(scene)))
    scene.add_mesh(Mesh(far, _plain(assets), _node(scene)))
    scene.add_mesh(Mesh(far, _plain(assets), _node(scene)))
    var data = _project(scene, assets)
    assert_equal(len(data.lights), 2)
    assert_equal(data.lights[0], 1)
    assert_equal(data.lights[1], 2)
    # Render order first, then far to near, then by node.
    assert_equal(data.elements[0].render_order, 0)
    assert_true(data.elements[0].z > data.elements[2].z)
    assert_true(data.elements[0].id < data.elements[1].id)
    assert_equal(data.elements[3].render_order, 1)
    # Unsorted, the scene's order stands.
    var unsorted = _project(scene, assets, sort=False)
    assert_equal(unsorted.elements[0].render_order, 1)


def test_the_double_matrix() raises:
    var m = Matrix(Matrix4())
    var twice = Matrix(scaling(2, 2, 2))
    assert_equal(m.times(twice).max_scale(), 2)
    var flat = Matrix(scaling(0, 1, 1))
    assert_equal(flat.normal_matrix()[0], 0)
    assert_equal(flat.normal_matrix()[8], 0)
    var copied = Matrix(copy=twice)
    assert_equal(copied.e[5], 2)
    var zero = apply_normal(twice.normal_matrix(), Vec(0))
    assert_equal(zero[0], 0)
    # A length of NaN divides by one, as JavaScript's `length || 1` does.
    var lost = apply_normal(
        twice.normal_matrix(), Vec(Float64.MAX * 2, 0, 0, 0)
    )
    assert_true(isnan(lost[1]))


def test_a_segment_is_clipped_at_the_far_plane() raises:
    # Past the far plane, then back in; both past it.
    var a = Vec(0, 0, 2, 1)
    var b = Vec(0, 0, 0, 1)
    assert_true(_clip_line(a, b))
    assert_almost_equal(a[2], 1)
    var c = Vec(0, 0, 2, 1)
    var d = Vec(0, 0, 3, 1)
    assert_false(_clip_line(c, d))
    # In, then past the far plane.
    var e = Vec(0, 0, 0, 1)
    var f = Vec(0, 0, 2, 1)
    assert_true(_clip_line(e, f))
    assert_almost_equal(f[2], 1)
    # Behind the near plane at one end and past the far plane at the
    # other, the cuts cross: three.js's check that a camera never meets.
    var g = Vec(0, 0, -2, -1)
    var h = Vec(0, 0, 2, -1)
    assert_false(_clip_line(g, h))


def test_an_empty_scene_and_a_child() raises:
    var scene = Scene()
    var assets = Assets()
    assert_equal(len(_project(scene, assets).elements), 0)
    var parent = _node(scene)
    var dots = assets.geometries.add(_through([Vector3(0, 0, 0)]))
    scene.add_points(
        Points(dots, _plain(assets), scene.attach(Object3D(), parent))
    )
    # A line of one point has no segment.
    scene.add_line(Line(dots, _plain(assets), parent))
    var data = _project(scene, assets)
    assert_equal(len(data.elements), 1)
    assert_true(data.elements[0].is_point)


def test_a_face_is_kept_by_any_corner_on_screen() raises:
    var scene = Scene()
    var assets = Assets()
    var paint = _plain(assets, 2)
    # Only the second corner on screen; only the third; all to the left.
    var shapes: List[List[Vector3]] = [
        [Vector3(-20, 0, 0), Vector3(0, 0, 0), Vector3(-20, 1, 0)],
        [Vector3(-20, 0, 0), Vector3(-21, 0, 0), Vector3(0, 0, 0)],
        [Vector3(-20, 0, 0), Vector3(-21, 0, 0), Vector3(-20, 1, 0)],
    ]
    for shape in shapes:
        scene.add_mesh(
            Mesh(
                assets.geometries.add(_through(shape.copy())),
                paint,
                _node(scene),
                frustum_culled=False,
            )
        )
    # A point nearer than the near plane is not drawn, even unculled.
    var near = Points(
        assets.geometries.add(_through([Vector3(0, 0, 4.99)])),
        _plain(assets),
        _node(scene),
    )
    near.frustum_culled = False
    scene.add_points(near)
    assert_equal(len(_project(scene, assets).elements), 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
