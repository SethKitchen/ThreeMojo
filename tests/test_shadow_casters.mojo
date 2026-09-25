# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the shadows of every kind of object: `Renderer.shadow_maps`
drawing skinned, instanced and batched meshes, LOD levels, lines, points
and translucent surfaces, as three.js's `WebGLShadowMap.renderObject`
draws any mesh, line or points object that casts, and the lights'
shadows falling on each kind that receives.

The reference is a plain `Mesh`: three.js draws a skinned mesh posed, an
instance placed and a level shown exactly where a plain mesh in the same
place is, so each kind must leave the same map, and the same shadow on
the floor, as a mesh standing where it stands.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.object_json import object_to_json
from geometries.box import cube
from geometries.plane import plane
from lights.csm import CSM
from lights.light import directional_light, point_light, spot_light
from lights.shadow import PCF_SHADOW_MAP, VSM_SHADOW_MAP, ShadowMap
from loaders.object_loader import read_object_json
from materials.material import (
    BASIC,
    LAMBERT,
    Material,
    MaterialId,
    PointSize,
    line_dashed_material,
    points_material,
)
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.line import Line, SEGMENTS
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 24
comptime HEIGHT = 18


def kinds() -> List[String]:
    """Return the kinds a caster or a floor can be drawn as."""
    return ["mesh", "skinned", "instanced", "batched", "lod"]


def camera_at(x: Float32, y: Float32, z: Float32) raises -> PerspectiveCamera:
    """Return a camera at a point, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(x, y, z), Vector3(0, 0, 0))
    return camera^


def skinned(var geometry: BufferGeometry) raises -> BufferGeometry:
    """Return a geometry every vertex of which the first bone carries."""
    var count = geometry.attribute_view(String(POSITION)).count()
    var first = List[Float32]()
    var second = List[Float32]()
    for _ in range(count):
        first.extend([Float32(0), 0, 0, 0])
        second.extend([Float32(1), 0, 0, 0])
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(first^, 4))
    geometry.set_attribute(String(SKIN_WEIGHT), BufferAttribute(second^, 4))
    return geometry^


def add_as(
    mut scene: Scene,
    mut assets: Assets,
    kind: String,
    var geometry: BufferGeometry,
    material: MaterialId,
    node: NodeId,
    cast: Bool,
    receive: Bool,
) raises:
    """Add a geometry drawn at a node as one kind of object.

    A skinned mesh stands at the root, carried by one bone at `node`
    whose inverse bind undoes nothing more than where the root is, and an
    instance or a batch member stands at the root, placed at `node` by
    its own matrix. So each kind draws its triangles where a mesh at
    `node` draws them.
    """
    scene.update()
    var world = scene.world_matrix(node)
    if kind == "skinned":
        var id = assets.geometries.add(skinned(geometry^))
        scene.add_skinned_mesh(
            SkinnedMesh(
                id,
                material,
                NodeId(0),
                Skeleton([Bone(node, Matrix4())]),
                cast_shadow=cast,
                receive_shadow=receive,
            )
        )
        return
    var id = assets.geometries.add(geometry^)
    if kind == "instanced":
        var group = InstancedMesh(
            id,
            material,
            NodeId(0),
            1,
            cast_shadow=cast,
            receive_shadow=receive,
        )
        group.set_matrix_at(0, world)
        scene.add_instanced_mesh(group^)
    elif kind == "batched":
        var batch = BatchedMesh(
            material, NodeId(0), cast_shadow=cast, receive_shadow=receive
        )
        _ = batch.add_instance(id, world)
        scene.add_batched_mesh(batch^)
    elif kind == "lod":
        # A level is a node, and casts and receives by the mesh it
        # carries. `add_lod` hangs it under `node`, at the identity.
        var level = scene.add(Object3D())
        scene.add_mesh(
            Mesh(id, material, level, cast_shadow=cast, receive_shadow=receive)
        )
        var lod = Lod(node)
        lod.add_level(level)
        scene.add_lod(lod^)
    else:
        scene.add_mesh(
            Mesh(id, material, node, cast_shadow=cast, receive_shadow=receive)
        )


def shadow_scene(
    mut assets: Assets,
    caster: String,
    floor: String,
    light: String,
    cast: Bool = True,
    receive: Bool = True,
    glass: Bool = False,
) raises -> Scene:
    """Return a floor and a block a meter above it under one light, the
    block drawn as the `caster` kind and the floor as the `floor` kind:
    `"sun"`, `"beam"` or `"bulb"` above and to one side. The block casts
    and the floor receives unless said otherwise. The block is a
    translucent one when `glass`."""
    var scene = Scene()
    # The root, where a skinned mesh, an instance or a batch stands.
    _ = scene.add(Object3D())
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    var lift_node = scene.add(lift^)
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var red = assets.materials.add(
        Material(
            Color(200, 60, 60),
            opacity=Float32(0.5) if glass else Float32(1),
            transparent=glass,
        )
    )
    add_as(
        scene,
        assets,
        floor,
        plane(Length(6.0, METER), Length(6.0, METER)),
        paint,
        ground_node,
        False,
        receive,
    )
    add_as(
        scene,
        assets,
        caster,
        cube(Length(1.0, METER)),
        red,
        lift_node,
        cast,
        False,
    )
    var lamp = Object3D()
    lamp.set_position(-3, 4, 0)
    var node = scene.add(lamp^)
    if light == "beam":
        var beam = spot_light(
            Color(255, 255, 255), node, 16.0, angle=Angle(50.0, DEGREE)
        )
        beam.cast_shadow = True
        beam.shadow.map_size = 64
        beam.shadow.bias = -0.002
        scene.add_light(beam)
    elif light == "bulb":
        var bulb = point_light(Color(255, 255, 255), node, 25.0)
        bulb.cast_shadow = True
        bulb.shadow.map_size = 64
        bulb.shadow.bias = -0.002
        scene.add_light(bulb)
    else:
        var sun = directional_light(Color(255, 255, 255), node, 1.0)
        sun.cast_shadow = True
        sun.shadow.map_size = 64
        sun.shadow.bias = -0.002
        scene.add_light(sun)
    scene.update()
    return scene^


def floor_under_and_beside(image: Framebuffer) raises -> Tuple[UInt8, UInt8]:
    """Return the red of the floor where the block's shadow falls, and the
    red of the floor well away from it, seen from above and in front."""
    return (
        image.get_pixel(WIDTH * 5 // 8, HEIGHT // 2 - 1).r,
        image.get_pixel(WIDTH // 8, HEIGHT * 3 // 4).r,
    )


def drawn(map: ShadowMap) -> Int:
    """Return how many texels of a map something was drawn into."""
    var count = 0
    for texel in range(len(map.depths)):
        if map.depths[texel] < 1:
            count += 1
    return count


def same_depths(a: ShadowMap, b: ShadowMap) -> Bool:
    """Return True if two maps hold the same depths, to a rounding."""
    if len(a.depths) != len(b.depths):
        return False
    for texel in range(len(a.depths)):
        if abs(a.depths[texel] - b.depths[texel]) > 1e-5:
            return False
    return True


def mismatches(a: Framebuffer, b: Framebuffer) raises -> Int:
    """Return how many pixels differ by more than one step."""
    var count = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            var far = (
                abs(Int(p.r) - Int(q.r)) > 1
                or abs(Int(p.g) - Int(q.g)) > 1
                or abs(Int(p.b) - Int(q.b)) > 1
            )
            if far:
                count += 1
    return count


def test_every_kind_casts_the_shadow_a_mesh_in_its_place_casts() raises:
    # A skinned block posed a meter up, an instance and a batch member
    # placed there, and an LOD's shown level there: each leaves the map a
    # plain mesh leaves, from a sun, a spot light and a bulb's six faces.
    # three.js's `renderObject` draws each of them into the map.
    var renderer = Renderer(WIDTH, HEIGHT)
    for light in ["sun", "beam", "bulb"]:
        var assets = Assets()
        var reference = renderer.shadow_maps(
            shadow_scene(assets, "mesh", "mesh", light), assets
        )
        assert_true(drawn(reference[0]) > 0, "the mesh cast nothing")
        for kind in kinds():
            var scene = shadow_scene(assets, kind, "mesh", light)
            var maps = renderer.shadow_maps(scene, assets)
            assert_true(
                same_depths(maps[0], reference[0]),
                String(kind, " cast another shadow from the ", light),
            )
            # Without its flag it casts nothing.
            var bare = shadow_scene(assets, kind, "mesh", light, cast=False)
            assert_equal(drawn(renderer.shadow_maps(bare, assets)[0]), 0)


def test_every_kind_casts_its_shadow_on_the_floor() raises:
    # Seen from above, the floor under each kind of block is darker than
    # the floor beside it, and the frame matches a plain mesh's.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var camera = camera_at(0, 6, 3)
    var assets = Assets()
    var reference = renderer.render(
        shadow_scene(assets, "mesh", "mesh", "sun"), assets, camera
    )
    var seen = floor_under_and_beside(reference)
    assert_true(Int(seen[0]) + 100 < Int(seen[1]), "no shadow fell")
    for kind in kinds():
        var image = renderer.render(
            shadow_scene(assets, kind, "mesh", "sun"), assets, camera
        )
        assert_equal(mismatches(image, reference), 0)


def test_every_kind_receives_the_shadow_a_mesh_receives() raises:
    # The floor drawn as each kind takes the block's shadow as a plain
    # floor does, and takes none when it does not receive.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var camera = camera_at(0, 6, 3)
    for light in ["sun", "bulb"]:
        var assets = Assets()
        var reference = renderer.render(
            shadow_scene(assets, "mesh", "mesh", light), assets, camera
        )
        var plain = renderer.render(
            shadow_scene(assets, "mesh", "mesh", light, receive=False),
            assets,
            camera,
        )
        assert_true(mismatches(reference, plain) > 0, "no shadow fell")
        for kind in kinds():
            var image = renderer.render(
                shadow_scene(assets, "mesh", kind, light), assets, camera
            )
            assert_equal(mismatches(image, reference), 0)
            var ignored = renderer.render(
                shadow_scene(assets, "mesh", kind, light, receive=False),
                assets,
                camera,
            )
            assert_equal(mismatches(ignored, plain), 0)


def test_a_variance_map_draws_every_kind_that_receives() raises:
    # three.js draws every receiver into a variance map, whatever kind it
    # is: the floor, which receives and does not cast, fills the map.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.shadow_map_type = VSM_SHADOW_MAP
    for kind in kinds():
        var assets = Assets()
        var scene = shadow_scene(assets, "mesh", kind, "sun", cast=False)
        var full = renderer.shadow_maps(scene, assets)[0].depths.copy()
        assert_true(full[32 * 64 + 32] < 1, "the receiver was not drawn")
        var none = shadow_scene(
            assets, "mesh", kind, "sun", cast=False, receive=False
        )
        var empty = renderer.shadow_maps(none, assets)[0].depths.copy()
        assert_true(empty[32 * 64 + 32] >= 1, "a bystander was drawn")


def test_a_translucent_surface_casts_a_whole_shadow() raises:
    # three.js draws a caster with its depth material, which writes the
    # depth whatever the caster's opacity: a translucent block leaves the
    # map an opaque one leaves, even with its depth write off.
    var renderer = Renderer(WIDTH, HEIGHT)
    for light in ["sun", "bulb"]:
        var assets = Assets()
        var reference = renderer.shadow_maps(
            shadow_scene(assets, "mesh", "mesh", light), assets
        )
        var scene = shadow_scene(assets, "mesh", "mesh", light, glass=True)
        assert_true(
            same_depths(renderer.shadow_maps(scene, assets)[0], reference[0])
        )
        var glass = assets.materials.get(scene.meshes[1].material)
        glass.depth_write = False
        scene.meshes[1].material = assets.materials.add(glass^)
        assert_true(
            same_depths(renderer.shadow_maps(scene, assets)[0], reference[0])
        )
    # And its shadow falls on the floor.
    var assets = Assets()
    renderer.set_background(Color(0, 0, 0))
    var seen = floor_under_and_beside(
        renderer.render(
            shadow_scene(assets, "mesh", "mesh", "sun", glass=True),
            assets,
            camera_at(0, 6, 3),
        )
    )
    assert_true(Int(seen[0]) + 100 < Int(seen[1]), "no shadow fell")


def test_a_translucent_surface_writes_its_depth_in_the_frame() raises:
    # three.js writes a transparent material's depth while `depthWrite`
    # is on, its default: a near pane drawn first hides a far pane drawn
    # after it. With the depth write off the far pane shows through.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var camera = camera_at(0, 0, 5)
    var results = List[Color]()
    for writes in [True, False]:
        var assets = Assets()
        var scene = Scene()
        var near = Object3D()
        near.set_position(0, 0, 1)
        near.render_order = 0
        var far = Object3D()
        far.render_order = 1
        var near_node = scene.add(near^)
        var far_node = scene.add(far^)
        var pane = assets.geometries.add(
            plane(Length(4.0, METER), Length(4.0, METER))
        )
        var front = Material(
            Color(255, 0, 0), kind=BASIC, opacity=0.5, transparent=True
        )
        front.depth_write = writes
        var back = Material(
            Color(0, 0, 255), kind=BASIC, opacity=0.5, transparent=True
        )
        scene.add_mesh(Mesh(pane, assets.materials.add(front^), near_node))
        scene.add_mesh(Mesh(pane, assets.materials.add(back^), far_node))
        scene.update()
        var image = renderer.render(scene, assets, camera)
        results.append(image.get_pixel(WIDTH // 2, HEIGHT // 2))
    assert_equal(results[0].b, 0)
    assert_true(results[1].b > 0, "the far pane did not show through")


def test_an_lod_casts_the_level_it_shows() raises:
    # three.js updates every LOD for the camera before it draws the maps,
    # and a map draws the level left visible. Here `update_lods` shows
    # one level and hides the others, and a hidden node casts nothing.
    # Near, the casting level shows; far, the level that does not cast.
    var assets = Assets()
    var scene = shadow_scene(assets, "mesh", "mesh", "sun", cast=False)
    var red = scene.meshes[1].material
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var near_level = scene.add(Object3D())
    scene.add_mesh(Mesh(block, red, near_level, cast_shadow=True))
    var far_level = scene.add(Object3D())
    scene.add_mesh(Mesh(block, red, far_level))
    var lod = Lod(NodeId(2))
    lod.add_level(near_level)
    lod.add_level(far_level, Length(20.0, METER))
    scene.add_lod(lod^)
    # An LOD with no levels casts nothing and is not refused.
    scene.add_lod(Lod(NodeId(2)))
    scene.update()
    var renderer = Renderer(WIDTH, HEIGHT)
    # Level zero shows until `update_lods` chooses another.
    assert_true(
        drawn(renderer.shadow_maps(scene, assets)[0]) > 0,
        "the near level cast nothing",
    )
    scene.update_lods(Vector3(0, 60, 30))
    assert_equal(drawn(renderer.shadow_maps(scene, assets)[0]), 0)
    scene.update_lods(Vector3(0, 6, 3))
    assert_true(drawn(renderer.shadow_maps(scene, assets)[0]) > 0)
    # A frame drawn from near shows the near level's shadow.
    renderer.set_background(Color(0, 0, 0))
    var seen = floor_under_and_beside(
        renderer.render(scene, assets, camera_at(0, 6, 3))
    )
    assert_true(Int(seen[0]) + 100 < Int(seen[1]), "no shadow fell")


def a_row() raises -> BufferGeometry:
    """Return four points a meter apart in a row along x, with no index."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([-1.5, 0, 0, -0.5, 0, 0, 0.5, 0, 0, 1.5, 0, 0], 3),
    )
    return geometry^


def line_scene(
    mut assets: Assets, what: String, cast: Bool, receive: Bool
) raises -> Scene:
    """Return a row of four points a meter up under a sun straight above,
    drawn as a `"line"`, a `"dashed"` line, `"points"` or a `"wireframe"`
    block, casting and receiving as said."""
    var scene = Scene()
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    var node = scene.add(lift^)
    var row = assets.geometries.add(a_row())
    if what == "points":
        scene.add_points(
            Points(
                row,
                assets.materials.add(
                    points_material(Color(255, 255, 255), PointSize(12))
                ),
                node,
                cast_shadow=cast,
                receive_shadow=receive,
            )
        )
    elif what == "wireframe":
        var wire = Material(Color(255, 255, 255), kind=BASIC, wireframe=True)
        scene.add_mesh(
            Mesh(
                assets.geometries.add(cube(Length(1.0, METER))),
                assets.materials.add(wire^),
                node,
                cast_shadow=cast,
                receive_shadow=receive,
            )
        )
    else:
        var paint = Material(Color(255, 255, 255), kind=BASIC)
        if what == "dashed":
            paint = line_dashed_material(
                Color(255, 255, 255),
                Length(0.25, METER),
                Length(0.25, METER),
            )
        scene.add_line(
            Line(
                row,
                assets.materials.add(paint^),
                node,
                mode=SEGMENTS,
                cast_shadow=cast,
                receive_shadow=receive,
            )
        )
    var lamp = Object3D()
    lamp.set_position(0, 4, 0)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 255, 255), lamp_node, 1.0)
    sun.cast_shadow = True
    sun.shadow.map_size = 64
    scene.add_light(sun)
    scene.update()
    return scene^


def test_a_line_casts_a_line_one_texel_wide() raises:
    # three.js draws a casting line into the map with its depth material,
    # as lines: two segments a meter long leave a line of texels, and a
    # dashed line leaves the same, as the depth material has no dashes.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var solid = drawn(
        renderer.shadow_maps(line_scene(assets, "line", True, False), assets)[0]
    )
    # Two segments of a meter each, 6.4 texels to the meter.
    assert_true(solid >= 12 and solid <= 16, String(solid, " texels"))
    var dashed = drawn(
        renderer.shadow_maps(line_scene(assets, "dashed", True, False), assets)[
            0
        ]
    )
    assert_equal(dashed, solid)
    assert_equal(
        drawn(
            renderer.shadow_maps(
                line_scene(assets, "line", False, True), assets
            )[0]
        ),
        0,
    )
    # A receiving line is drawn into a variance map, as three.js draws
    # every receiver there.
    renderer.shadow_map_type = VSM_SHADOW_MAP
    var moments = renderer.shadow_maps(
        line_scene(assets, "line", False, True), assets
    )[0].depths.copy()
    var touched = 0
    for texel in range(0, len(moments), 2):
        if moments[texel] < 1:
            touched += 1
    assert_true(touched > 0, "the receiving line was not drawn")


def test_points_cast_one_texel_each() raises:
    # three.js's depth material sets no `gl_PointSize`, so a point casts
    # one texel whatever its own size: four points a meter apart leave
    # four texels.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var cast = renderer.shadow_maps(
        line_scene(assets, "points", True, False), assets
    )
    assert_equal(drawn(cast[0]), 4)
    var bare = renderer.shadow_maps(
        line_scene(assets, "points", False, True), assets
    )
    assert_equal(drawn(bare[0]), 0)
    renderer.shadow_map_type = VSM_SHADOW_MAP
    var moments = renderer.shadow_maps(
        line_scene(assets, "points", False, True), assets
    )[0].depths.copy()
    var touched = 0
    for texel in range(0, len(moments), 2):
        if moments[texel] < 1:
            touched += 1
    assert_true(touched > 0, "the receiving points were not drawn")


def test_a_wireframe_casts_its_edges() raises:
    # three.js copies `wireframe` onto the depth material, so a wireframe
    # block casts its edges and not its faces.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var edges = drawn(
        renderer.shadow_maps(
            line_scene(assets, "wireframe", True, False), assets
        )[0]
    )
    assert_true(edges > 0, "the wireframe cast nothing")
    # A one-meter block seen from above covers 6.4 texels a side; its
    # edges cover fewer than its faces.
    assert_true(edges < 49, String(edges, " texels"))
    assert_equal(
        drawn(
            renderer.shadow_maps(
                line_scene(assets, "wireframe", False, False), assets
            )[0]
        ),
        0,
    )


def test_a_light_view_keeps_a_lines_own_material() raises:
    # The scene's override is the frame's alone, as three.js's shadow map
    # draws `object.material`: a lit override that no line or point can
    # wear refuses the frame, and the light's view does not read it.
    var renderer = Renderer(WIDTH, HEIGHT)
    for what in ["line", "points"]:
        var assets = Assets()
        var scene = line_scene(assets, what, True, False)
        scene.override_material = assets.materials.add(
            Material(Color(255, 255, 255), kind=LAMBERT)
        )
        assert_true(drawn(renderer.shadow_maps(scene, assets)[0]) > 0)


def test_every_kind_casts_into_the_cascades() raises:
    # A cascade is a directional light of its own, so every kind casts
    # into it through the same pass.
    var renderer = Renderer(WIDTH, HEIGHT)
    for kind in kinds():
        for cast in [True, False]:
            var assets = Assets()
            var scene = shadow_scene(assets, kind, "mesh", "sun", cast=cast)
            scene.lights[0].cast_shadow = False
            var camera = camera_at(0, 6, 3)
            var csm = CSM(
                scene,
                camera,
                cascades=2,
                max_far=Length(20.0, METER),
                shadow_map_size=32,
                light_margin=Length(10.0, METER),
            )
            csm.update(scene, camera)
            var total = 0
            for map in renderer.shadow_maps(scene, assets):
                total += drawn(map)
            if cast:
                assert_true(total > 0, String(kind, " cast nothing"))
            else:
                assert_equal(total, 0)


def test_the_flags_ride_in_scene_json() raises:
    # three.js's `Object3D.toJSON` writes `castShadow` and `receiveShadow`
    # on every object, and `ObjectLoader` reads them back: a skinned,
    # instanced and batched mesh, a line and points keep theirs. An LOD's
    # level is a node, and its meshes keep theirs as any mesh does.
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    var node = scene.add(Object3D())
    var red = assets.materials.add(Material(Color(200, 60, 60)))
    var block = cube(Length(1.0, METER))
    add_as(scene, assets, "skinned", block.clone(), red, node, True, False)
    add_as(scene, assets, "instanced", block.clone(), red, node, False, True)
    add_as(scene, assets, "batched", block.clone(), red, node, True, True)
    var row = assets.geometries.add(a_row())
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    scene.add_line(Line(row, paint, node, cast_shadow=True))
    scene.add_points(
        Points(
            row,
            assets.materials.add(points_material(Color(255, 255, 255))),
            node,
            receive_shadow=True,
        )
    )
    scene.update()
    var text = object_to_json(scene, assets)
    var again = Scene()
    var read = Assets()
    _ = read_object_json(text, again, read)
    assert_true(again.skinned_meshes[0].cast_shadow)
    assert_false(again.skinned_meshes[0].receive_shadow)
    assert_false(again.instanced_meshes[0].cast_shadow)
    assert_true(again.instanced_meshes[0].receive_shadow)
    assert_true(again.batched_meshes[0].cast_shadow)
    assert_true(again.batched_meshes[0].receive_shadow)
    assert_true(again.lines[0].cast_shadow)
    assert_false(again.lines[0].receive_shadow)
    assert_false(again.points[0].cast_shadow)
    assert_true(again.points[0].receive_shadow)


def test_every_flag_is_off_by_default() raises:
    # As three.js's `castShadow` and `receiveShadow` are.
    var skin = SkinnedMesh(
        GeometryId(0),
        MaterialId(0),
        NodeId(0),
        Skeleton([Bone(NodeId(0), Matrix4())]),
    )
    assert_false(skin.cast_shadow or skin.receive_shadow)
    var group = InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 1)
    assert_false(group.cast_shadow or group.receive_shadow)
    var batch = BatchedMesh(MaterialId(0), NodeId(0))
    assert_false(batch.cast_shadow or batch.receive_shadow)
    var line = Line(GeometryId(0), MaterialId(0), NodeId(0))
    assert_false(line.cast_shadow or line.receive_shadow)
    var points = Points(GeometryId(0), MaterialId(0), NodeId(0))
    assert_false(points.cast_shadow or points.receive_shadow)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
