# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `helpers.csm`.

`assets/csm/three.json` holds what three.js 0.180's `CSMHelper` draws, in
world space, for a `CSM` of three practical cascades out to 120 meters. A
50-degree camera, one and a half times as wide as high and from 0.5 to 200
meters deep, stands at (10, 8, 20) and looks at the origin. The sun shines
along (1, -1, 1), with shadow maps of 1024 texels, lights from 1 to 500
meters deep and a margin of 50 meters.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.scene import Scene
from helpers.csm import (
    CSMHelper,
    CSM_PLANE_OPACITY,
    csm_plane_material,
)
from lights.csm import CSM, PRACTICAL_SPLIT
from loaders.json import JsonDocument, parse_json
from materials.material import BASIC, DOUBLE_SIDE
from math.vector3 import Vector3
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def _camera() raises -> PerspectiveCamera:
    """Return the camera of the module docstring.

    Returns:
        The camera.

    Raises:
        Error: Never.
    """
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.5, Length(0.5, METER), Length(200.0, METER)
    )
    camera.place(Vector3(10, 8, 20), Vector3(0, 0, 0))
    return camera^


def _cascades(mut scene: Scene, camera: PerspectiveCamera) raises -> CSM:
    """Return the cascades of the module docstring, updated.

    Args:
        scene: The scene to add the lights to.
        camera: The camera they slice.

    Returns:
        The cascades.

    Raises:
        Error: Never.
    """
    var sun = Vector3(1, -1, 1)
    sun.normalize()
    var csm = CSM(
        scene,
        camera,
        cascades=3,
        max_far=Length(120.0, METER),
        mode=PRACTICAL_SPLIT,
        shadow_map_size=1024,
        light_direction=sun,
        light_near=Length(1.0, METER),
        light_far=Length(500.0, METER),
        light_margin=Length(50.0, METER),
    )
    csm.update(scene, camera)
    return csm^


def _reference() raises -> JsonDocument:
    """Return what three.js drew.

    Returns:
        The parsed file.

    Raises:
        Error: If the file cannot be read.
    """
    return parse_json(Path("assets/csm/three.json").read_text())


def _assert_points(
    got: List[Float32],
    first: Int,
    doc: JsonDocument,
    want: Int,
    tolerance: Float32,
) raises:
    """Assert a run of floats matches a JSON list, each within a tolerance
    scaled by its size.

    Args:
        got: The floats.
        first: Where the run starts in them.
        doc: The document.
        want: The list's node.
        tolerance: The relative tolerance.

    Raises:
        Error: If a float differs.
    """
    for at in range(doc.length(want)):
        var expected = Float32(doc.number(doc.at(want, at)))
        assert_almost_equal(
            got[first + at],
            expected,
            atol=Float64(tolerance * max(abs(expected), Float32(1))),
        )


def test_the_lines_match_three_js() raises:
    var scene = Scene()
    var camera = _camera()
    var csm = _cascades(scene, camera)
    var lines = CSMHelper().lines(csm, scene, camera)
    ref positions = lines.attribute_view(String(POSITION)).data
    ref colors = lines.attribute_view(String(COLOR)).data
    var doc = _reference()
    var root = doc.root()
    assert_equal(len(positions), 72 * 7)
    _assert_points(positions, 0, doc, doc.get(root, "frustum"), 1e-4)
    for index in range(3):
        var at = 72 + index * 144
        _assert_points(
            positions,
            at,
            doc,
            doc.at(doc.get(root, "cascades"), index),
            1e-4,
        )
        # The lights stand where the texel snapping puts them, which one
        # float's rounding can move by a texel.
        _assert_points(
            positions,
            at + 72,
            doc,
            doc.at(doc.get(root, "shadows"), index),
            1e-3,
        )
        # White boxes, then yellow ones.
        assert_equal(colors[at], 1)
        assert_equal(colors[at + 2], 1)
        assert_equal(colors[at + 72], 1)
        assert_equal(colors[at + 74], 0)
    assert_equal(colors[0], 1)
    assert_equal(colors[2], 1)


def test_the_planes_match_three_js() raises:
    var scene = Scene()
    var camera = _camera()
    var csm = _cascades(scene, camera)
    var planes = CSMHelper().planes(csm, scene, camera)
    assert_equal(len(planes), 3)
    var doc = _reference()
    for index in range(3):
        ref face = planes[index]
        ref data = face.attribute_view(String(POSITION)).data
        # Unfold the index, as three.js's reference is written.
        var corners = List[Float32]()
        for at in range(len(face.index)):
            for axis in range(3):
                corners.append(data[face.index[at] * 3 + axis])
        _assert_points(
            corners, 0, doc, doc.at(doc.get(doc.root(), "planes"), index), 1e-4
        )


def test_the_switches_hide_their_parts() raises:
    var scene = Scene()
    var camera = _camera()
    var csm = _cascades(scene, camera)
    var helper = CSMHelper()
    helper.display_frustum = False
    # Only the shadow boxes: twelve edges each.
    var shadows = helper.lines(csm, scene, camera)
    assert_equal(len(shadows.attribute_view(String(POSITION)).data), 3 * 72)
    # The planes need the frustum too.
    assert_equal(len(helper.planes(csm, scene, camera)), 0)
    helper.display_frustum = True
    helper.display_planes = False
    assert_equal(len(helper.planes(csm, scene, camera)), 0)
    helper.display_shadow_bounds = False
    var frame = helper.lines(csm, scene, camera)
    assert_equal(len(frame.attribute_view(String(POSITION)).data), 4 * 72)


def test_the_plane_material_is_three_js() raises:
    var material = csm_plane_material()
    assert_equal(material.kind, BASIC)
    assert_equal(material.opacity, CSM_PLANE_OPACITY)
    assert_true(material.transparent)
    assert_false(material.depth_write)
    assert_equal(material.side, DOUBLE_SIDE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
