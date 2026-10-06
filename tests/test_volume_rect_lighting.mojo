# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rectangle volume light contracts from three.js r186, issue #616.

The constants below come from an independent double-precision evaluation
of the rational edge fit in r186's `src/nodes/functions/BSDF/LTC.js` and
`src/nodes/functions/VolumetricLightingModel.js`, not from these helpers.
The view-space z term and the power 1.5 must both survive CPU/GPU sharing.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import (
    directional_light,
    point_light,
    rect_area_light,
    spot_light,
)
from lights.lighting import Lighting, rect_volume_light
from lights.ltc import load_ltc_tables, ltc_evaluate_volume
from loaders.json import NULL, JsonDocument, parse_json
from materials.nodes import (
    NodeGraph,
    NodeInputs,
    ProgramSource,
    SCATTERING_NODE,
)
from materials.volume_node_material import (
    LitRay,
    volume_node_material,
    volumetric_light,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer
from std.math import inf
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime ORIGIN = Vector3(0, 0, 0)
comptime UP = Vector3(0, 1, 0)
comptime BACK = Vector3(0, 0, 1)
comptime C0 = Vector3(1, -1, 1)
comptime C1 = Vector3(-1, -1, 1)
comptime C2 = Vector3(-1, 1, 1)
comptime C3 = Vector3(1, 1, 1)


def test_the_r186_volume_form_factor_uses_absolute_edges() raises:
    # The edge sum is (0, 0, -0.5541262649761672). Without abs it clips
    # to zero, so the surface LTC path cannot stand in for volume LTC.
    assert_almost_equal(
        ltc_evaluate_volume(ORIGIN, C0, C1, C2, C3),
        Float32(0.5541262649761671),
        atol=2e-6,
    )
    # An off-axis point exercises all three components of the edge sum.
    assert_almost_equal(
        ltc_evaluate_volume(Vector3(0.3, -0.4, -0.2), C0, C1, C2, C3),
        Float32(0.42281059255452924),
        atol=2e-6,
    )
    assert_almost_equal(
        ltc_evaluate_volume(
            ORIGIN,
            Vector3(1, -1, 2),
            Vector3(-1, -1, 0),
            Vector3(-1, 1, 0),
            Vector3(1, 1, 2),
        ),
        Float32(0.6515035352237991),
        atol=2e-6,
    )


def test_a_rectangle_still_shines_on_only_one_side() raises:
    assert_equal(ltc_evaluate_volume(Vector3(0, 0, 2), C0, C1, C2, C3), 0)
    # The emitter plane is included by the upstream >= 0 test.
    assert_almost_equal(
        ltc_evaluate_volume(Vector3(0, 0, 1), C0, C1, C2, C3),
        1,
        atol=2e-6,
    )
    # Opposite edges cancel geometrically. Float32 normalization can leave
    # a first-order x residual; the clipped factor squares that residual.
    var epsilon = Float32(1.1920928955078125e-7)
    assert_almost_equal(
        ltc_evaluate_volume(ORIGIN, C0, C0, C3, C3),
        0,
        atol=Float64(epsilon * epsilon),
    )
    # Reversing the winding turns the emitting side around.
    assert_equal(ltc_evaluate_volume(ORIGIN, C3, C2, C1, C0), 0)
    assert_almost_equal(
        ltc_evaluate_volume(Vector3(0, 0, 2), C3, C2, C1, C0),
        Float32(0.5541262649761671),
        atol=2e-6,
    )


def test_rect_radiance_is_raised_to_one_and_a_half_after_the_factor() raises:
    var light = rect_volume_light(
        ORIGIN,
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        UP,
        Vector3(4, 1, 0),
        UP,
        BACK,
    )
    assert_almost_equal(light.x, Float32(3.299917562347724), atol=1e-5)
    assert_almost_equal(light.y, Float32(0.4124896952934655), atol=2e-6)
    assert_equal(light.z, 0)
    var back = rect_volume_light(
        Vector3(0, 0, 2),
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        UP,
        Vector3(4, 1, 0),
        UP,
        BACK,
    )
    assert_equal(back.x, 0)
    assert_equal(back.y, 0)
    assert_equal(back.z, 0)


def test_view_rotation_changes_the_clipped_sphere_z_term() raises:
    # A camera turned 90 degrees about y sees the edge sum on its x axis.
    # Its magnitude is unchanged, but the form factor becomes l*l/(l+1).
    var turned = rect_volume_light(
        ORIGIN,
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        UP,
        Vector3(4, 1, 0),
        UP,
        Vector3(1, 0, 0),
    )
    assert_almost_equal(turned.x, Float32(0.7025653775827242), atol=3e-6)
    assert_almost_equal(turned.y, Float32(0.08782067219784052), atol=2e-6)
    assert_equal(turned.z, 0)
    # Translating the light and step together leaves their view offsets.
    var moved = rect_volume_light(
        Vector3(2, -3, 4),
        Vector3(2, -3, 5),
        Vector3(1, 0, 0),
        UP,
        Vector3(4, 1, 0),
        UP,
        Vector3(1, 0, 0),
    )
    assert_equal(moved.x, turned.x)
    assert_equal(moved.y, turned.y)


def test_mixed_volume_lights_add_without_a_lambert_scale() raises:
    var scene = Scene()
    var rectangle = scene.add(Object3D())
    scene.node(rectangle).set_position(0, 0, 1)
    scene.add_light(
        rect_area_light(
            Color(255, 0, 0), rectangle, 4, Length(2, METER), Length(2, METER)
        )
    )
    scene.add_light(
        rect_area_light(
            Color(0, 0, 255), rectangle, 1, Length(2, METER), Length(2, METER)
        )
    )
    var bulb = scene.add(Object3D())
    scene.node(bulb).set_position(0, 0, 2)
    scene.add_light(point_light(Color(0, 255, 0), bulb, 2))
    var spot = scene.add(Object3D())
    scene.node(spot).set_position(0, 0, 3)
    scene.add_light(spot_light(Color(255, 255, 255), spot, 9))
    scene.add_light(directional_light(Color(255, 255, 255), bulb, 100))
    scene.update()
    var lighting = Lighting(scene, ltc=load_ltc_tables())
    lighting.scale = 0
    for receives in [False, True]:
        var light = lighting.volume_light_at(ORIGIN, BACK, receives)
        # Point: (0, 0.5, 0). Spot: (1, 1, 1). Rectangles add separately.
        assert_almost_equal(light.x, Float32(4.299917562347724), atol=1e-5)
        assert_almost_equal(light.y, Float32(1.5), atol=2e-6)
        assert_almost_equal(light.z, Float32(1.4124896952934655), atol=3e-6)
    lighting.back = Vector3(1, 0, 0)
    lighting.eye = Vector3(20, 30, 40)
    var turned = lighting.volume_light_at(ORIGIN, Vector3(0, 0, 0), False)
    assert_almost_equal(turned.x, Float32(1.7025653775827242), atol=4e-6)
    assert_almost_equal(turned.y, Float32(1.5), atol=2e-6)
    assert_almost_equal(turned.z, Float32(1.0878206721978405), atol=3e-6)


def rect_volume_scene(mut assets: Assets, mixed: Bool = False) raises -> Scene:
    """Return a box lit by two rectangles for CPU and GPU image tests.

    Args:
        assets: The stores receiving the geometry and material.
        mixed: Add a point, spot, and directional light when True.

    Returns:
        The updated scene, whose first two lights are rectangles.

    Raises:
        Error: If a fixture asset or light cannot be built.
    """
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(2, METER))),
            assets.materials.add(volume_node_material(steps=8)),
            node,
        )
    )
    var first = scene.add(Object3D())
    scene.node(first).set_position(0.2, 0.3, 2)
    scene.add_light(
        rect_area_light(
            Color(255, 120, 40), first, 12, Length(2, METER), Length(1, METER)
        )
    )
    var second = scene.add(Object3D())
    scene.node(second).set_position(-1, -0.5, 1.5)
    scene.add_light(
        rect_area_light(
            Color(40, 140, 255), second, 8, Length(1, METER), Length(2, METER)
        )
    )
    if mixed:
        var bulb = scene.add(Object3D())
        scene.node(bulb).set_position(0.3, -0.2, 0.1)
        scene.add_light(point_light(Color(80, 255, 80), bulb, 2))
        var spot = scene.add(Object3D())
        scene.node(spot).set_position(0, 2.5, 0)
        scene.add_light(spot_light(Color(180, 180, 255), spot, 4))
        scene.add_light(directional_light(Color(255, 255, 255), spot, 100))
    scene.update()
    return scene^


def test_rectangles_change_the_rendered_volume() raises:
    var assets = Assets()
    var scene = rect_volume_scene(assets, mixed=True)
    var renderer = Renderer(24, 18)
    renderer.set_ltc_tables(load_ltc_tables())
    var camera = PerspectiveCamera(
        Angle(50, DEGREE),
        Float32(24) / Float32(18),
        Length(0.1, METER),
        Length(100, METER),
    )
    camera.place(Vector3(3, 0.4, 2), ORIGIN)
    var lit = renderer.render(scene, assets, camera)
    scene.lights[0].intensity = 0
    scene.lights[1].intensity = 0
    var dark = renderer.render(scene, assets, camera)
    var changed = 0
    for y in range(18):
        for x in range(24):
            var a = lit.get_pixel(x, y)
            var b = dark.get_pixel(x, y)
            if (
                abs(Int(a.r) - Int(b.r)) > 1
                or abs(Int(a.g) - Int(b.g)) > 1
                or abs(Int(a.b) - Int(b.b)) > 1
            ):
                changed += 1
    assert_true(changed > 15, "the volume ignored its rectangle lights")


def test_exactly_collapsed_rectangles_have_zero_volume_factor() raises:
    for point in [ORIGIN, Vector3(0, 0, 1), Vector3(0.3, -0.4, -0.2)]:
        assert_equal(ltc_evaluate_volume(point, C0, C0, C3, C3), 0)
        assert_equal(ltc_evaluate_volume(point, C3, C3, C0, C0), 0)
        assert_equal(ltc_evaluate_volume(point, C0, C1, C1, C0), 0)
        assert_equal(ltc_evaluate_volume(point, C0, C0, C0, C0), 0)
    # This nonzero rectangle has an area whose Float32 square underflows.
    # A squared-area or epsilon test must not classify it as collapsed.
    var half = Float32(1e-25)
    assert_true(
        ltc_evaluate_volume(
            ORIGIN,
            Vector3(half, -1, 1),
            Vector3(-half, -1, 1),
            Vector3(-half, 1, 1),
            Vector3(half, 1, 1),
        )
        > 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


# This fixture is checked by tools/reference_volume_lighting.py --check.
# Native tests consume its inputs and results, not recomputed native oracles.


def _reference_vector(doc: JsonDocument, node: Int) raises -> Vector3:
    """Read a three-component fixture vector as Float32."""
    return Vector3(
        Float32(doc.number(doc.at(node, 0))),
        Float32(doc.number(doc.at(node, 1))),
        Float32(doc.number(doc.at(node, 2))),
    )


def _reference_lighting(doc: JsonDocument, scene: Int) raises -> Lighting:
    """Read resolved fixture lights without color-space conversion."""
    var lighting = Lighting(ambient=FloatColor(0, 0, 0, 1))
    var camera = doc.get(scene, "camera")
    lighting.eye = _reference_vector(doc, doc.get(camera, "eye"))
    lighting.up = _reference_vector(doc, doc.get(camera, "up"))
    lighting.back = _reference_vector(doc, doc.get(camera, "back"))
    var lights = doc.get(scene, "lights")
    for index in range(doc.length(lights)):
        var light = doc.at(lights, index)
        var kind = doc.string(doc.get(light, "kind"))
        var radiance = _reference_vector(doc, doc.get(light, "radiance"))
        var color = FloatColor(radiance.x, radiance.y, radiance.z, 1)
        if kind == "rectangle":
            lighting.rect_positions.append(
                _reference_vector(doc, doc.get(light, "position"))
            )
            lighting.rect_half_widths.append(
                _reference_vector(doc, doc.get(light, "half_width"))
            )
            lighting.rect_half_heights.append(
                _reference_vector(doc, doc.get(light, "half_height"))
            )
            lighting.rect_radiances.append(color)
        elif kind == "point":
            lighting.positions.append(
                _reference_vector(doc, doc.get(light, "position"))
            )
            lighting.point_radiances.append(color)
            lighting.decays.append(Float32(doc.number(doc.get(light, "decay"))))
            lighting.cutoffs.append(
                Float32(doc.number(doc.get(light, "cutoff")))
            )
            lighting.point_shadows.append(-1)
        elif kind == "spot":
            lighting.spot_positions.append(
                _reference_vector(doc, doc.get(light, "position"))
            )
            lighting.spot_directions.append(
                _reference_vector(doc, doc.get(light, "toward_light_axis"))
            )
            lighting.spot_radiances.append(color)
            lighting.spot_decays.append(
                Float32(doc.number(doc.get(light, "decay")))
            )
            lighting.spot_cutoffs.append(
                Float32(doc.number(doc.get(light, "cutoff")))
            )
            lighting.cone_cosines.append(
                Float32(doc.number(doc.get(light, "cone_cos")))
            )
            lighting.penumbra_cosines.append(
                Float32(doc.number(doc.get(light, "penumbra_cos")))
            )
            lighting.spot_shadows.append(-1)
            lighting.spot_map_slots.append(-1)
            lighting.spot_profile_slots.append(-1)
        else:
            assert_equal(kind, "directional")
            lighting.directions.append(BACK)
            lighting.radiances.append(color)
            lighting.direction_shadows.append(-1)
    return lighting^


def _check_reference_rgb(
    actual: Vector3, doc: JsonDocument, expected: Int, tolerance: Float64
) raises:
    """Check a native RGB result against the independent fixture."""
    var wanted = _reference_vector(doc, expected)
    assert_almost_equal(actual.x, wanted.x, atol=tolerance)
    assert_almost_equal(actual.y, wanted.y, atol=tolerance)
    assert_almost_equal(actual.z, wanted.z, atol=tolerance)


def test_r186_reference_scenes_keep_depth_gates_and_native_transmittance() raises:
    var doc = parse_json(Path("assets/volume_lighting/r186.json").read_text())
    var scenes = doc.get(doc.root(), "scenes")
    assert_equal(doc.length(scenes), 20)
    for index in range(doc.length(scenes)):
        var scene = doc.at(scenes, index)
        var lighting = _reference_lighting(doc, scene)
        var expected = doc.get(scene, "expected")
        var samples = doc.get(expected, "samples")
        var depth_node = doc.get(scene, "scene_depth_m")
        var depth = inf[DType.float32]()
        if doc.kind(depth_node) != NULL:
            depth = Float32(doc.number(depth_node))
        for sample_index in range(doc.length(samples)):
            var sample = doc.at(samples, sample_index)
            var at = _reference_vector(doc, doc.get(sample, "position"))
            var accepted = (lighting.eye - at).dot(lighting.back) <= depth
            assert_equal(accepted, doc.boolean(doc.get(sample, "depth_gate")))
            _check_reference_rgb(
                lighting.volume_light_at(at, BACK, False),
                doc,
                doc.get(sample, "ungated_light"),
                1e-4,
            )
        var graph = NodeGraph()
        graph.set_output(
            SCATTERING_NODE,
            graph.float(
                Float32(doc.number(doc.get(scene, "scattering_scale")))
            ),
        )
        var program = graph.compile()
        var fragment = _reference_vector(doc, doc.get(scene, "fragment"))
        var gathered = volumetric_light(
            LitRay(Pointer(to=lighting), BACK, False),
            ProgramSource(Pointer(to=program)),
            True,
            NodeInputs(0, 0, fragment, BACK, ORIGIN, ORIGIN, False),
            lighting.eye,
            Float32(doc.number(doc.get(scene, "model_radius"))),
            doc.integer(doc.get(scene, "steps")),
            Float32(doc.number(doc.get(scene, "offset"))),
            Length(depth, METER),
            lighting.back,
        )
        _check_reference_rgb(
            gathered,
            doc,
            doc.get(expected, "native_accepted_output"),
            3e-6,
        )
        _check_reference_rgb(
            Vector3(1 - gathered.x, 1 - gathered.y, 1 - gathered.z),
            doc,
            doc.get(expected, "native_transmittance"),
            3e-6,
        )
