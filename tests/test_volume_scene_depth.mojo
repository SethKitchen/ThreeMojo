# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent scene-depth checks for issue 616.

The reference is three.js r186's `VolumetricLightingModel.scatteringLight`:
the scene's linear depth must be at least the sample's linear depth. Its
`ViewportDepthNode` converts perspective depth through view z. These tests
use analytic plane depths and explicit sample counts, not the native marcher
to calculate an expected value. The native, previously accepted
`1 - transmittance` output is tested separately from that r186 depth gate;
this suite does not claim r186 rendered-color parity.

Source blobs inspected for the gate and depth conversion:
`VolumetricLightingModel.js`: d37d3a6c2362170e043b8624958afbe16ae87137.
`ViewportDepthNode.js`: 7e96a52c22bbc0bc356a241b38c2e409da0740fc.
Both are under https://github.com/mrdoob/three.js/tree/r186/src/nodes/.
`tools/reference_volume_lighting.py` also records these analytic scenes in
`assets/volume_lighting/r186.json`, independently of the native marcher.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import point_light
from materials.material import BASIC, DOUBLE_SIDE, OPAQUE, PHYSICAL, Material
from materials.nodes import (
    DEPTH_NODE,
    EMISSIVE_NODE,
    MASK_NODE,
    NO_NODES,
    NodeGraph,
    NodeInputs,
    NodeProgram,
    NodeProgramId,
    ProgramSource,
)
from materials.volume_node_material import (
    RayLights,
    volume_node_material,
    volumetric_light,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.raster_state import (
    LOGARITHMIC_DEPTH,
    REVERSED_DEPTH,
    STANDARD_DEPTH,
    DepthMode,
)
from render.rasterizer import (
    SHADE_LIT,
    SHADE_UV,
    check_triangle_state,
    rasterize_shaded,
)
from render.rect import Rect
from render.target import RenderTarget
from render.transmission import TransmissionTarget
from renderers.draw_filter import ONE_OIT_DRAW
from renderers.renderer import Renderer
from std.math import exp, inf, log2, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 15
comptime MID = SIZE // 2
comptime BLACK = Color(0, 0, 0)


@fieldwise_init
struct _ConstantRay(ImplicitlyCopyable, RayLights):
    """A constant density that makes each admitted sample countable."""

    def light_at(self, position: Vector3) -> Vector3:
        """Return density (100, 50, 0), independent of position.

        Args:
            position: The sample position, unused.

        Returns:
            A constant density.
        """
        return Vector3(100, 50, 0)


def _program() raises -> NodeProgram:
    """Return a program with no scattering output."""
    var graph = NodeGraph()
    graph.set_output(EMISSIVE_NODE, graph.vec3(0, 0, 0))
    return graph.compile()


def _surface() -> NodeInputs:
    """Return a fragment at the origin."""
    var zero = Vector3(0, 0, 0)
    return NodeInputs(0, 0, zero, Vector3(0, 0, 1), zero, zero, False)


def _expect_ray(ray: Vector3, optical_depth: Float32) raises:
    """Check the analytic Beer result for a counted sample distance."""
    assert_almost_equal(ray.x, 1 - exp(-optical_depth), atol=1e-6)
    assert_almost_equal(ray.y, 1 - exp(-optical_depth * 0.5), atol=1e-6)
    assert_equal(ray.z, Float32(0))


def _camera(z: Float32 = 4) raises -> PerspectiveCamera:
    """Return the common axial perspective camera."""
    var camera = PerspectiveCamera(
        Angle(45, DEGREE), 1, Length(0.1, METER), Length(100, METER)
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, z - 1))
    return camera^


def _add_plane(
    mut scene: Scene,
    mut assets: Assets,
    z: Float32,
    material: Material,
) raises:
    """Add a large front-facing plane at an exact axial distance."""
    var node = Object3D()
    node.set_position(0, 0, z)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plane(Length(20, METER), Length(20, METER))),
            assets.materials.add(material),
            scene.add(node^),
        )
    )


def _scene(
    mut assets: Assets,
    material: Material,
    blocker_z: Float32 = 0.5,
    blocker: Bool = True,
    blocker_nodes: NodeProgramId = NO_NODES,
) raises -> Scene:
    """Build a two-meter volume and a constant-intensity point light."""
    var scene = Scene()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(2, METER))),
            assets.materials.add(material),
            scene.add(Object3D()),
        )
    )
    var light = Object3D()
    light.set_position(0, 5, 0)
    scene.add_light(
        point_light(Color(255, 255, 255), scene.add(light^), 10, decay=0)
    )
    if blocker:
        _add_plane(
            scene,
            assets,
            blocker_z,
            Material(BLACK, kind=BASIC, nodes=blocker_nodes),
        )
    scene.update()
    return scene^


def _expect_pixel(pixel: Color, optical_depth: Float32) raises:
    """Compare with an analytic constant-density color, within one byte."""
    var light = 1 - exp(-optical_depth)
    var expected = FloatColor(light, light, light).encode()
    assert_true(abs(Int(pixel.r) - Int(expected.r)) <= 1)
    assert_true(abs(Int(pixel.g) - Int(expected.g)) <= 1)
    assert_true(abs(Int(pixel.b) - Int(expected.b)) <= 1)


def test_a_far_ray_uses_an_inclusive_per_sample_gate() raises:
    # Original samples have depths 0, .5, 1, 1.5 and step size .5.
    # A bound of .5 admits two. Truncating and redividing the ray would
    # produce a different optical depth and cannot pass this check.
    var program = _program()
    var ray = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 2),
        0.5,
        4,
        0,
        Length(0.5, METER),
    )
    _expect_ray(ray, 1)
    var none = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 2),
        0.5,
        4,
        0,
        Length(-0.1, METER),
    )
    _expect_ray(none, 0)


def test_a_near_ray_keeps_its_direction_and_offset() raises:
    # Back-to-front depths 2, 1.5, 1, .5 admit one sample at .5.
    # An offset of one preserves the .5-meter steps but adds the eye
    # sample, so two now pass. The gate must not terminate this ray early.
    var program = _program()
    var ray = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 2),
        2,
        4,
        0,
        Length(0.5, METER),
    )
    _expect_ray(ray, 0.5)
    var offset = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 2),
        2,
        4,
        1,
        Length(0.5, METER),
    )
    _expect_ray(offset, 1)


def test_a_depth_is_axial_not_euclidean_and_uses_camera_rotation() raises:
    # A 3-4-5 ray has one-meter steps at axial depths 0, .8, 1.6, 2.4,
    # 3.2. A 1.7-meter bound admits three, not the two of a radial test.
    var program = _program()
    var slant = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(3, 0, 4),
        1,
        5,
        0,
        Length(1.7, METER),
    )
    _expect_ray(slant, 3)
    var turned = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(2, 0, 0),
        0.5,
        4,
        0,
        Length(0.5, METER),
        Vector3(1, 0, 0),
    )
    _expect_ray(turned, 1)


def test_an_absent_depth_keeps_the_accepted_ungated_ray() raises:
    var program = _program()
    var ray = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 2),
        0.5,
        4,
        0,
    )
    _expect_ray(ray, 2)
    assert_false(volume_node_material().volume_scene_depth)
    var material = volume_node_material(scene_depth=True)
    assert_true(material.volume_scene_depth)
    material.set_volume_scene_depth(False)
    assert_false(material.volume_scene_depth)


def test_only_volumes_can_request_scene_depth() raises:
    var ordinary = Material(BLACK, kind=BASIC)
    with assert_raises(contains="Only a VOLUME"):
        ordinary.set_volume_scene_depth(True)
    with assert_raises(contains="Only a VOLUME"):
        ordinary.set_volume_scene_depth(False)
    # Open fields are checked again when the renderer reads them.
    ordinary.volume_scene_depth = True
    var assets = Assets()
    var scene = _scene(assets, ordinary, blocker=False)
    with assert_raises(contains="Only a VOLUME"):
        _ = Renderer(SIZE, SIZE).prepare(scene, assets, _camera())


def test_triangle_depth_flags_must_agree() raises:
    var assets = Assets()
    var scene = _scene(assets, volume_node_material(scene_depth=True))
    var corners = Renderer(SIZE, SIZE).prepare(scene, assets, _camera())
    # Find a volume without depending on the opaque/transparent sort.
    var index = 0
    while not corners[index].volume_scene_depth:
        index += 3
    var a = corners[index]
    var b = corners[index + 1]
    var c = corners[index + 2]
    check_triangle_state(a, b, c)
    b.volume_scene_depth = False
    with assert_raises(contains="disagree about volume scene depth"):
        check_triangle_state(a, b, c)
    b.volume_scene_depth = True
    c.volume_scene_depth = False
    with assert_raises(contains="disagree about volume scene depth"):
        check_triangle_state(a, b, c)


def _encoded_depth(distance: Float32, mode: DepthMode) -> Float32:
    """Encode near=1, far=9 independently of the native depth helpers."""
    # r186 viewZToPerspectiveDepth, converted to native NDC storage:
    # (far + near)/(far - near) - 2*near*far/((far-near)*distance).
    var ndc = Float32(1.25) - Float32(2.25) / distance
    if mode == REVERSED_DEPTH:
        return (1 - ndc) * 0.5
    if mode == LOGARITHMIC_DEPTH:
        return 2 * log2(1 + distance) / log2(Float32(10)) - 1
    return ndc


def test_snapshot_decodes_depth_modes_and_is_independent_of_later_writes() raises:
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1.5, Length(1, METER), Length(9, METER)
    )
    for mode in [STANDARD_DEPTH, REVERSED_DEPTH, LOGARITHMIC_DEPTH]:
        var target = RenderTarget(3, 2, BLACK)
        target.depth_mode = mode
        for x in range(3):
            var distance = Float32(2 << x)
            target.depth[x] = _encoded_depth(distance, mode)
        var clear = inf[DType.float32]()
        if mode == REVERSED_DEPTH:
            clear = -clear
        for x in range(3, 6):
            target.depth[x] = clear
        var captured = TransmissionTarget(target, Matrix4())
        captured.capture_volume_depth(
            target, camera.view_to_screen_matrix(3, 2), Length(9, METER)
        )
        captured.check_volume_depth(True, 3, 2)
        for x in range(3):
            assert_almost_equal(
                captured.volume_depth_at(x, 0).value,
                Float32(2 << x),
                atol=2e-5,
            )
            assert_equal(captured.volume_depth_at(x, 1).value, Float32(9))
        target.depth[0] = _encoded_depth(8, mode)
        assert_almost_equal(captured.volume_depth_at(0, 0).value, 2, atol=2e-5)


def test_orthographic_depth_can_be_signed() raises:
    var camera = OrthographicCamera(
        Length(-2, METER),
        Length(2, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(-2, METER),
        Length(6, METER),
    )
    for mode in [STANDARD_DEPTH, REVERSED_DEPTH]:
        var target = RenderTarget(2, 1, BLACK)
        target.depth_mode = mode
        # d=-1 gives normalized depth 1/8; d=3 gives 5/8.
        target.depth[0] = -0.75
        target.depth[1] = 0.25
        if mode == REVERSED_DEPTH:
            target.depth[0] = 0.875
            target.depth[1] = 0.375
        var captured = TransmissionTarget(target, Matrix4())
        captured.capture_volume_depth(
            target, camera.view_to_screen_matrix(2, 1), Length(6, METER)
        )
        assert_almost_equal(captured.volume_depth_at(0, 0).value, -1, atol=1e-6)
        assert_almost_equal(captured.volume_depth_at(1, 0).value, 3, atol=1e-6)


def test_orthographic_gate_corrects_the_upstream_mixed_depth_spaces() raises:
    # r186 always projects the sample with viewZToPerspectiveDepth, but
    # linearDepth leaves that value unchanged for an orthographic camera.
    # With near=1, far=9, a sample at 2 has .5625 while an opaque surface
    # at 3 has orthographic depth .25. The literal upstream gate rejects
    # this visible sample. Signed axial ordering correctly admits it.
    var camera = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(1, METER),
        Length(9, METER),
    )
    var target = RenderTarget(1, 1, BLACK)
    target.depth[0] = -0.5
    var captured = TransmissionTarget(target, Matrix4())
    captured.capture_volume_depth(
        target, camera.view_to_screen_matrix(1, 1), Length(9, METER)
    )
    assert_almost_equal(captured.volume_depth_at(0, 0).value, 3, atol=1e-6)
    var upstream_scene = Float32(3 - 1) / Float32(9 - 1)
    var upstream_sample = Float32((1 - 2) * 9) / Float32((9 - 1) * -2)
    assert_equal(upstream_scene, Float32(0.25))
    assert_equal(upstream_sample, Float32(0.5625))
    assert_true(upstream_scene < upstream_sample)
    # One four-meter step with offset .5 samples exactly two meters from
    # the eye; its full original step size remains in Beer's law.
    var program = _program()
    var ray = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 4),
        1,
        1,
        0.5,
        captured.volume_depth_at(0, 0),
    )
    _expect_ray(ray, 4)


def test_reversed_gate_corrects_the_upstream_mixed_depth_spaces() raises:
    # r186 projects a sample with the forward perspective formula and
    # then applies reversed perspective inversion. With near=1, far=9,
    # a sample at 3 has forward depth .75 and is incorrectly read as
    # distance 9/7. A nearer opaque surface at 2 would admit it upstream.
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(1, METER), Length(9, METER)
    )
    var target = RenderTarget(1, 1, BLACK)
    target.depth_mode = REVERSED_DEPTH
    target.depth[0] = 0.4375
    var captured = TransmissionTarget(target, Matrix4())
    captured.capture_volume_depth(
        target, camera.view_to_screen_matrix(1, 1), Length(9, METER)
    )
    assert_almost_equal(captured.volume_depth_at(0, 0).value, 2, atol=1e-6)
    var forward_sample = Float32((1 - 3) * 9) / Float32((9 - 1) * -3)
    assert_equal(forward_sample, Float32(0.75))
    var reversed_sample = Float32(9) / (1 + 8 * forward_sample)
    assert_almost_equal(reversed_sample, Float32(9) / 7, atol=1e-6)
    assert_true(Float32(2) >= reversed_sample)
    # The native gate reads the real sample distance, three meters.
    var program = _program()
    var ray = volumetric_light(
        _ConstantRay(),
        ProgramSource(Pointer(to=program)),
        False,
        _surface(),
        Vector3(0, 0, 4),
        1,
        1,
        0.75,
        captured.volume_depth_at(0, 0),
    )
    _expect_ray(ray, 0)


def test_a_requested_snapshot_must_exist_and_match_the_raster_size() raises:
    var empty = TransmissionTarget()
    empty.check_volume_depth(False, 3, 2)
    with assert_raises(contains="raster target size"):
        empty.check_volume_depth(True, 3, 2)
    var target = RenderTarget(3, 2, BLACK)
    var captured = TransmissionTarget(target, Matrix4())
    with assert_raises(contains="raster target size"):
        captured.check_volume_depth(True, 3, 2)
    captured.capture_volume_depth(target, Matrix4(), Length(10, METER))
    with assert_raises(contains="raster target size"):
        captured.check_volume_depth(True, 2, 3)
    captured.volume_depth[0] = nan[DType.float32]()
    with assert_raises(contains="finite"):
        captured.check_volume_depth(True, 3, 2)


def test_snapshot_capture_refuses_invalid_inputs() raises:
    var target = RenderTarget(2, 1, BLACK)
    var captured = TransmissionTarget(target, Matrix4())
    captured.capture_volume_depth(target, Matrix4(), Length(10, METER))
    var wrong = RenderTarget(1, 2, BLACK)
    with assert_raises(contains="match"):
        captured.capture_volume_depth(wrong, Matrix4(), Length(10, METER))
    with assert_raises(contains="finite"):
        captured.capture_volume_depth(
            target, Matrix4(), Length(inf[DType.float32](), METER)
        )
    target.depth[0] = nan[DType.float32]()
    with assert_raises(contains="NaN"):
        captured.capture_volume_depth(target, Matrix4(), Length(10, METER))
    target.depth[0] = 0
    target.depth_mode = DepthMode(17)
    with assert_raises(contains="depth mode"):
        captured.capture_volume_depth(target, Matrix4(), Length(10, METER))
    target.depth_mode = STANDARD_DEPTH
    _ = target.depth.pop()
    with assert_raises():
        captured.capture_volume_depth(target, Matrix4(), Length(10, METER))
    target.depth.append(0)
    var invalid = Matrix4()
    invalid.elements[0] = nan[DType.float32]()
    with assert_raises():
        captured.capture_volume_depth(target, invalid, Length(10, METER))
    var singular = Matrix4()
    singular.elements[0] = 0
    with assert_raises():
        captured.capture_volume_depth(target, singular, Length(10, METER))
    # Every failed capture leaves the previous immutable snapshot intact.
    assert_equal(captured.volume_depth_at(0, 0).value, Float32(10))
    assert_equal(captured.volume_depth_at(1, 0).value, Float32(10))


def test_a_low_level_volume_without_its_snapshot_fails_before_drawing() raises:
    var assets = Assets()
    var scene = _scene(
        assets, volume_node_material(scene_depth=True), blocker=False
    )
    var corners = Renderer(SIZE, SIZE).prepare(scene, assets, _camera())
    var target = RenderTarget(SIZE, SIZE, BLACK)
    with assert_raises(contains="raster target size"):
        rasterize_shaded(corners[0], corners[1], corners[2], target)
    assert_equal(target.straight_at(MID * SIZE + MID).r, Float32(0))


def test_opaque_planes_before_inside_and_behind_gate_the_original_samples() raises:
    # Camera z=4, volume back face z=-1, five one-meter steps. Depths
    # are 0, 1, 2, 3, 4. The planes admit 2, 4 and 5 samples, respectively.
    var planes: List[Float32] = [2.5, 0.5, -2]
    var expected: List[Float32] = [0.2, 0.4, 0.5]
    for mode in [STANDARD_DEPTH, REVERSED_DEPTH, LOGARITHMIC_DEPTH]:
        for index in range(len(planes)):
            var assets = Assets()
            var scene = _scene(
                assets,
                volume_node_material(steps=5, scene_depth=True),
                planes[index],
            )
            var renderer = Renderer(SIZE, SIZE)
            renderer.set_background(BLACK)
            renderer.set_depth_mode(mode)
            var pixel = renderer.render(scene, assets, _camera()).get_pixel(
                MID, MID
            )
            _expect_pixel(pixel, expected[index])


def test_a_camera_inside_a_volume_keeps_only_nearer_samples() raises:
    # From z=.5 to the far face at -1, the backwards ray has .3-meter
    # steps and depths 1.5, 1.2, .9, .6, .3. A plane at z=0 admits one.
    var assets = Assets()
    var scene = _scene(
        assets, volume_node_material(steps=5, scene_depth=True), 0
    )
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    _expect_pixel(
        renderer.render(scene, assets, _camera(0.5)).get_pixel(MID, MID), 0.03
    )


def test_clear_pixels_and_disabled_depth_preserve_ungated_scattering() raises:
    var assets = Assets()
    var scene = _scene(
        assets, volume_node_material(steps=5, scene_depth=True), blocker=False
    )
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var captured = renderer.transmission_target(scene, assets, _camera())
    assert_equal(captured.volume_depth_at(MID, MID).value, Float32(100))
    _expect_pixel(
        renderer.render(scene, assets, _camera()).get_pixel(MID, MID), 0.5
    )
    var disabled_assets = Assets()
    var disabled = _scene(disabled_assets, volume_node_material(steps=5), 2.5)
    var absent = renderer.transmission_target(
        disabled, disabled_assets, _camera()
    )
    assert_equal(len(absent.volume_depth), 0)
    _expect_pixel(
        renderer.render(disabled, disabled_assets, _camera()).get_pixel(
            MID, MID
        ),
        0.5,
    )


def test_clipped_occluders_do_not_enter_the_snapshot() raises:
    # One plane lies before the near clip and the other beyond far.
    for z in [Float32(3.95), Float32(-97)]:
        var assets = Assets()
        var scene = _scene(
            assets, volume_node_material(steps=5, scene_depth=True), z
        )
        var renderer = Renderer(SIZE, SIZE)
        renderer.set_background(BLACK)
        var captured = renderer.transmission_target(scene, assets, _camera())
        assert_equal(captured.volume_depth_at(MID, MID).value, Float32(100))
        _expect_pixel(
            renderer.render(scene, assets, _camera()).get_pixel(MID, MID), 0.5
        )


def test_discarded_opaque_fragments_leave_clear_depth() raises:
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(MASK_NODE, graph.float(0))
    var node = assets.programs.add(graph.compile())
    var scene = _scene(
        assets,
        volume_node_material(steps=5, scene_depth=True),
        2.5,
        blocker_nodes=node,
    )
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var captured = renderer.transmission_target(scene, assets, _camera())
    assert_equal(captured.volume_depth_at(MID, MID).value, Float32(100))
    _expect_pixel(
        renderer.render(scene, assets, _camera()).get_pixel(MID, MID), 0.5
    )


def test_generic_depth_node_still_sets_the_opaque_fragment_depth() raises:
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(DEPTH_NODE, graph.float(0.25))
    var nodes = assets.programs.add(graph.compile())
    var scene = _scene(
        assets,
        volume_node_material(steps=5, scene_depth=True),
        0.5,
        blocker_nodes=nodes,
    )
    var renderer = Renderer(SIZE, SIZE)
    var frame = renderer.render(scene, assets, _camera())
    assert_almost_equal(frame.depth[MID * SIZE + MID], -0.5, atol=1e-6)
    var captured = renderer.transmission_target(scene, assets, _camera())
    # Independent perspective inverse: near*far/(far-depth*(far-near)).
    var expected = Float32(10) / (100 - Float32(0.25) * Float32(99.9))
    assert_almost_equal(
        captured.volume_depth_at(MID, MID).value, expected, atol=1e-6
    )


def test_no_volume_can_write_into_the_opaque_snapshot() raises:
    var assets = Assets()
    var requested = volume_node_material(scene_depth=True)
    requested.depth_test = True
    requested.depth_write = True
    requested.transparent = False
    requested.blending = OPAQUE
    var scene = _scene(assets, requested, blocker=False)
    var unrequested = volume_node_material()
    unrequested.depth_test = True
    unrequested.depth_write = True
    unrequested.transparent = False
    unrequested.blending = OPAQUE
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(1, METER))),
            assets.materials.add(unrequested),
            scene.add(Object3D()),
        )
    )
    scene.update()
    var captured = Renderer(SIZE, SIZE).transmission_target(
        scene, assets, _camera()
    )
    for index in range(len(captured.volume_depth)):
        assert_equal(captured.volume_depth[index], Float32(100))


def test_opt_out_keeps_forced_opaque_volumes_in_transmission_colors() raises:
    # No scene-depth request: retain the existing color-capture behavior
    # for a caller that deliberately made its volume opaque. The physical
    # front-facing plane requires the capture but adds no back-face pass.
    var assets = Assets()
    var material = volume_node_material(steps=5)
    material.transparent = False
    material.blending = OPAQUE
    material.depth_test = True
    material.depth_write = True
    var scene = _scene(assets, material, blocker=False)
    _add_plane(
        scene,
        assets,
        2,
        Material(Color(255, 255, 255), kind=PHYSICAL, transmission=1),
    )
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var before = renderer.transmission_target(scene, assets, _camera())
    var color_at = (MID * SIZE + MID) * 4
    assert_almost_equal(
        before.image.data[color_at], 1 - exp(Float32(-0.5)), atol=1e-6
    )
    assert_equal(len(before.volume_depth), 0)
    # An explicit depth request now excludes every volume from both the
    # opaque colors and the immutable opaque depth snapshot.
    assets.materials.materials[0].set_volume_scene_depth(True)
    var after = renderer.transmission_target(scene, assets, _camera())
    assert_equal(after.image.data[color_at], Float32(0))
    assert_equal(after.volume_depth_at(MID, MID).value, Float32(100))


def test_transmissive_back_faces_do_not_replace_the_opaque_snapshot() raises:
    var assets = Assets()
    var scene = _scene(assets, volume_node_material(scene_depth=True), -2)
    var glass = Material(
        Color(255, 255, 255), kind=PHYSICAL, side=DOUBLE_SIDE, transmission=1
    )
    var node = Object3D()
    node.set_position(0, 0, 2)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(0.5, METER))),
            assets.materials.add(glass),
            scene.add(node^),
        )
    )
    scene.update()
    var captured = Renderer(SIZE, SIZE).transmission_target(
        scene, assets, _camera()
    )
    assert_almost_equal(captured.volume_depth_at(MID, MID).value, 6, atol=2e-4)


def test_scene_depth_requests_do_not_change_volume_shadow_maps() raises:
    # The camera's scene-depth input does not belong in a light's shadow
    # pass. In particular, that pass has no opaque camera-depth snapshot.
    var assets = Assets()
    var scene = _scene(assets, volume_node_material(steps=5), blocker=False)
    scene.meshes[0].cast_shadow = True
    scene.lights[0].cast_shadow = True
    scene.lights[0].shadow.map_size = 4
    var light_node = scene.lights[0].node
    scene.node(light_node).set_position(0, 3, 0)
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    for transmitted in [False, True]:
        renderer.shadow_map_transmitted = transmitted
        assets.materials.materials[0].set_volume_scene_depth(False)
        var ordinary = renderer.shadow_maps(scene, assets)
        assets.materials.materials[0].set_volume_scene_depth(True)
        var requested = renderer.shadow_maps(scene, assets)
        assert_equal(len(ordinary), 1)
        assert_equal(len(requested), 1)
        assert_equal(len(ordinary[0].depths), 6 * 4 * 4)
        assert_equal(len(requested[0].depths), len(ordinary[0].depths))
        var occupied = 0
        for index in range(len(ordinary[0].depths)):
            assert_equal(requested[0].depths[index], ordinary[0].depths[index])
            if ordinary[0].depths[index] < 1:
                occupied += 1
        assert_true(occupied > 0, "the baseline volume cast no shadow")
        assert_equal(len(requested[0].colors), len(ordinary[0].colors))
        for index in range(len(ordinary[0].colors)):
            assert_equal(requested[0].colors[index], ordinary[0].colors[index])


def test_depth_capture_runs_in_lit_mode_and_is_unused_in_uv_mode() raises:
    var assets = Assets()
    var scene = _scene(assets, volume_node_material(steps=5, scene_depth=True))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    renderer.set_shading(SHADE_LIT)
    var captured = renderer.transmission_target(scene, assets, _camera())
    assert_almost_equal(
        captured.volume_depth_at(MID, MID).value, 3.5, atol=1e-4
    )
    _expect_pixel(
        renderer.render(scene, assets, _camera()).get_pixel(MID, MID), 0.4
    )
    renderer.set_shading(SHADE_UV)
    var unused = renderer.transmission_target(scene, assets, _camera())
    assert_equal(len(unused.volume_depth), 0)
    _ = renderer.render(scene, assets, _camera())


def test_a_filtered_volume_still_reads_unfiltered_opaque_depth() raises:
    # The OIT draw filter removes the black opaque plane from the beauty
    # draw. It must remain in the separate scene-depth capture.
    var assets = Assets()
    var scene = _scene(assets, volume_node_material(steps=5, scene_depth=True))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    renderer.draw_filter = ONE_OIT_DRAW
    renderer.oit_draw = 0
    _expect_pixel(
        renderer.render(scene, assets, _camera()).get_pixel(MID, MID), 0.4
    )
    # Opting out retains the pre-existing ungated filtered path.
    var plain_assets = Assets()
    var plain = _scene(plain_assets, volume_node_material(steps=5))
    _expect_pixel(
        renderer.render(plain, plain_assets, _camera()).get_pixel(MID, MID), 0.5
    )


def test_resize_viewport_and_supersampling_use_current_raster_dimensions() raises:
    var assets = Assets()
    var scene = _scene(assets, volume_node_material(steps=5, scene_depth=True))
    var camera = _camera()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(BLACK)
    var resized = renderer.resized(21, 11)
    resized.set_viewport(Rect(3, 2, 15, 7))
    var captured = resized.transmission_target(scene, assets, camera)
    captured.check_volume_depth(True, 21, 11)
    assert_almost_equal(captured.volume_depth_at(10, 5).value, 3.5, atol=1e-4)
    assert_equal(captured.volume_depth_at(0, 0).value, Float32(100))
    resized.set_scissor(Rect(8, 4, 5, 3))
    resized.set_scissor_test(True)
    var clipped = resized.transmission_target(scene, assets, camera)
    assert_almost_equal(clipped.volume_depth_at(10, 5).value, 3.5, atol=1e-4)
    # This pixel is inside the visible volume and viewport, but outside
    # the scissor, so the capture must retain its clear far distance.
    assert_equal(clipped.volume_depth_at(7, 5).value, Float32(100))
    var big = renderer.supersampled()
    var sampled = big.transmission_target(scene, assets, camera)
    sampled.check_volume_depth(True, big.width, big.height)
    assert_equal(len(sampled.volume_depth), big.width * big.height)
    assert_almost_equal(
        sampled.volume_depth_at(big.width // 2, big.height // 2).value,
        3.5,
        atol=1e-4,
    )
    renderer.set_antialias(True)
    var antialiased = renderer.render(scene, assets, camera)
    _expect_pixel(antialiased.get_pixel(MID, MID), 0.4)
    var target = RenderTarget(SIZE, SIZE, BLACK, samples=4)
    renderer.render_into(target, scene, assets, camera)
    _expect_pixel(target.resolve().get_pixel(MID, MID), 0.4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
