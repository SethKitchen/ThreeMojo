# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Editable head/torso size and frame scalars must remain finite."""

from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.torso.bones.dimensions import torso_dimensions
from extensions.humanoid.skeleton.morph import HeadMorph
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import TestSuite, assert_raises
from units.si import Length, METER


def test_spine_sizes_reject_nan_and_both_infinities() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        var torso_dimensions_widths = torso_dimensions(
            Length(1.8288, METER), MALE
        )
        torso_dimensions_widths.widths[2] = bad
        with assert_raises(contains="finite"):
            torso_dimensions_widths.validate()
        var torso_dimensions_depths = torso_dimensions(
            Length(1.8288, METER), MALE
        )
        torso_dimensions_depths.depths[2] = bad
        with assert_raises(contains="finite"):
            torso_dimensions_depths.validate()
        var torso_dimensions_heights = torso_dimensions(
            Length(1.8288, METER), MALE
        )
        torso_dimensions_heights.heights[2] = bad
        with assert_raises(contains="finite"):
            torso_dimensions_heights.validate()
        var head_dimensions_widths = head_dimensions(
            Length(1.8288, METER), MALE
        )
        head_dimensions_widths.widths[2] = bad
        with assert_raises(contains="finite"):
            head_dimensions_widths.validate()
        var head_dimensions_depths = head_dimensions(
            Length(1.8288, METER), MALE
        )
        head_dimensions_depths.depths[2] = bad
        with assert_raises(contains="finite"):
            head_dimensions_depths.validate()
        var head_dimensions_heights = head_dimensions(
            Length(1.8288, METER), MALE
        )
        head_dimensions_heights.heights[2] = bad
        with assert_raises(contains="finite"):
            head_dimensions_heights.validate()


def test_all_editable_frame_values_have_finite_guards() raises:
    var original = head_dimensions(Length(1.8288, METER), MALE)
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        Float32(0),
        Float32(-1),
    ]:
        var stature_frame = original.frame
        stature_frame.stature = bad
        with assert_raises(contains="scale"):
            stature_frame.validate()
        var wide_frame = original.frame
        wide_frame.wide = bad
        with assert_raises(contains="scale"):
            wide_frame.validate()
        var deep_frame = original.frame
        deep_frame.deep = bad
        with assert_raises(contains="scale"):
            deep_frame.validate()
        var shoulders_frame = original.frame
        shoulders_frame.shoulders = bad
        with assert_raises(contains="scale"):
            shoulders_frame.validate()
        var chest_frame = original.frame
        chest_frame.chest = bad
        with assert_raises(contains="scale"):
            chest_frame.validate()
        var head_frame = original.frame
        head_frame.head = bad
        with assert_raises(contains="scale"):
            head_frame.validate()
        var neck_frame = original.frame
        neck_frame.neck = bad
        with assert_raises(contains="scale"):
            neck_frame.validate()
    var lost = original.frame
    lost.anchor = Vector3(0, inf[DType.float32](), 0)
    with assert_raises(contains="finite"):
        lost.validate()


def test_morph_guards_do_not_impose_an_unmeasured_biological_range() raises:
    var fantasy = HeadMorph()
    fantasy.nose_width = 8
    fantasy.validate()
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        var head_width_morph = HeadMorph()
        head_width_morph.head_width = bad
        with assert_raises(contains="finite"):
            head_width_morph.validate()
        var head_length_morph = HeadMorph()
        head_length_morph.head_length = bad
        with assert_raises(contains="finite"):
            head_length_morph.validate()
        var head_height_morph = HeadMorph()
        head_height_morph.head_height = bad
        with assert_raises(contains="finite"):
            head_height_morph.validate()
        var jaw_width_morph = HeadMorph()
        jaw_width_morph.jaw_width = bad
        with assert_raises(contains="finite"):
            jaw_width_morph.validate()
        var chin_morph = HeadMorph()
        chin_morph.chin = bad
        with assert_raises(contains="finite"):
            chin_morph.validate()
        var cheekbones_morph = HeadMorph()
        cheekbones_morph.cheekbones = bad
        with assert_raises(contains="finite"):
            cheekbones_morph.validate()
        var brow_ridge_morph = HeadMorph()
        brow_ridge_morph.brow_ridge = bad
        with assert_raises(contains="finite"):
            brow_ridge_morph.validate()
        var brow_height_morph = HeadMorph()
        brow_height_morph.brow_height = bad
        with assert_raises(contains="finite"):
            brow_height_morph.validate()
        var brow_arch_morph = HeadMorph()
        brow_arch_morph.brow_arch = bad
        with assert_raises(contains="finite"):
            brow_arch_morph.validate()
        var eye_size_morph = HeadMorph()
        eye_size_morph.eye_size = bad
        with assert_raises(contains="finite"):
            eye_size_morph.validate()
        var eye_spacing_morph = HeadMorph()
        eye_spacing_morph.eye_spacing = bad
        with assert_raises(contains="finite"):
            eye_spacing_morph.validate()
        var eye_tilt_morph = HeadMorph()
        eye_tilt_morph.eye_tilt = bad
        with assert_raises(contains="finite"):
            eye_tilt_morph.validate()
        var eye_depth_morph = HeadMorph()
        eye_depth_morph.eye_depth = bad
        with assert_raises(contains="finite"):
            eye_depth_morph.validate()
        var nose_length_morph = HeadMorph()
        nose_length_morph.nose_length = bad
        with assert_raises(contains="finite"):
            nose_length_morph.validate()
        var nose_width_morph = HeadMorph()
        nose_width_morph.nose_width = bad
        with assert_raises(contains="finite"):
            nose_width_morph.validate()
        var nose_projection_morph = HeadMorph()
        nose_projection_morph.nose_projection = bad
        with assert_raises(contains="finite"):
            nose_projection_morph.validate()
        var nose_bridge_morph = HeadMorph()
        nose_bridge_morph.nose_bridge = bad
        with assert_raises(contains="finite"):
            nose_bridge_morph.validate()
        var mouth_width_morph = HeadMorph()
        mouth_width_morph.mouth_width = bad
        with assert_raises(contains="finite"):
            mouth_width_morph.validate()
        var lip_fullness_morph = HeadMorph()
        lip_fullness_morph.lip_fullness = bad
        with assert_raises(contains="finite"):
            lip_fullness_morph.validate()
        var neck_length_morph = HeadMorph()
        neck_length_morph.neck_length = bad
        with assert_raises(contains="finite"):
            neck_length_morph.validate()
        var face = HeadMorph()
        face.face_shapes[3] = bad
        with assert_raises(contains="face-shape"):
            face.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
