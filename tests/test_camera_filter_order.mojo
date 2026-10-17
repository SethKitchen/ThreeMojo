# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Custom cameras are queried only after the historical caster filter."""

from cameras.camera import Camera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NodeId
from core.scene import Scene
from materials.material import MaterialId
from math.bounds import Sphere
from math.frustum import Frustum
from math.matrix4 import Matrix4
from renderers.renderer import _object_place
from std.testing import TestSuite, assert_equal, assert_false, assert_true


@fieldwise_init
struct _CountingCamera[origin: Origin[mut=True]](Camera, ImplicitlyCopyable):
    var calls: MutPointer[Int, Self.origin]

    def view_matrix(self) raises -> Matrix4:
        return Matrix4()

    def view_matrix_in(self, scene: Scene) raises -> Matrix4:
        return Matrix4()

    def projection_matrix(self) raises -> Matrix4:
        return Matrix4()

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        return Matrix4()

    def near_distance(self) -> Float32:
        return 0.1

    def far_distance(self) -> Float32:
        return 10

    def visible_layers(self) -> Layers:
        self.calls[unsafe_offset=0] += 1
        return Layers()


def test_excluded_caster_does_not_query_custom_camera() raises:
    var calls = List[Int](length=1, fill=0)
    var camera = _CountingCamera(calls.unsafe_ptr())
    var scene = Scene()
    var assets = Assets()
    var bounds = List[Sphere]()
    var known = List[Bool]()
    var frustum = Frustum.from_projection_matrix(Matrix4())
    # No node or resources exist. The caster filter must run before both
    # camera.visible_layers and scene/resource validation.
    var kept, _, _ = _object_place(
        scene,
        assets,
        NodeId(-1),
        MaterialId(-1),
        GeometryId(-1),
        True,
        False,
        False,
        True,
        False,
        camera,
        Matrix4(),
        frustum,
        0,
        bounds,
        known,
    )
    assert_false(kept)
    assert_equal(calls[0], 0)
    var raised = False
    try:
        _ = _object_place(
            scene,
            assets,
            NodeId(-1),
            MaterialId(-1),
            GeometryId(-1),
            True,
            True,
            False,
            True,
            False,
            camera,
            Matrix4(),
            frustum,
            0,
            bounds,
            known,
        )
    except:
        raised = True
    assert_true(raised)
    assert_equal(calls[0], 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
