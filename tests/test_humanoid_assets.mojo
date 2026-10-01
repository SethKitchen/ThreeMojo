# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bundled humanoid assets can use an explicit root from any directory."""

from extensions.humanoid.assets import humanoid_asset_path
from extensions.humanoid.genome import FACE_SHAPES
from extensions.humanoid.skeleton.head.hair.styles import (
    LAYERED,
    HairStyleFile,
    hair_style_path,
)
from extensions.humanoid.skeleton.head.skin.scan import scan_model
from std.os import getenv, setenv
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_asset_root_selection_and_path_validation() raises:
    var saved = getenv("THREEMOJO_ASSET_ROOT", "")
    _ = setenv("THREEMOJO_ASSET_ROOT", "")
    assert_equal(
        humanoid_asset_path("assets/face/ict_face.bin"),
        "assets/face/ict_face.bin",
    )
    _ = setenv("THREEMOJO_ASSET_ROOT", "/explicit asset root")
    assert_equal(
        humanoid_asset_path("assets/face/ict_face.bin"),
        "/explicit asset root/face/ict_face.bin",
    )
    assert_equal(
        hair_style_path(LAYERED), "/explicit asset root/hair/layered.bin"
    )
    _ = setenv("THREEMOJO_ASSET_ROOT", saved)
    with assert_raises(contains="must start with assets/"):
        _ = humanoid_asset_path("other/face.bin")


def test_high_level_face_and_hair_load_from_the_selected_root() raises:
    var model = scan_model()
    assert_equal(model.identities(), FACE_SHAPES)
    assert_true(model.vertex_count() > 0)
    var style = HairStyleFile(hair_style_path(LAYERED))
    assert_true(style.count > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
