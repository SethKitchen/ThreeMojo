# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the hairstyles artists groomed, laid on any head."""

from extensions.humanoid.genome import Expression, Genome, HAIR_CURL
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    SCALP_HAIR,
    HairShape,
)
from extensions.humanoid.skeleton.head.hair.geometry import (
    head_hair_from_dimensions,
)
from extensions.humanoid.skeleton.head.hair.groom import (
    GroomSpec,
    groom_hair,
)
from extensions.humanoid.skeleton.head.hair.styles import (
    GROWN,
    LAYERED,
    MOHAWK,
    HairStyle,
    HairStyleFile,
    cranium_frame,
    hair_style_label,
    hair_style_path,
    named_hair_styles,
)
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def _dims() raises -> HeadMuscleDimensions:
    """Return the six-foot male template's head."""
    return head_muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))


def _u32(mut bytes: List[UInt8], value: Int):
    """Append `value` as a little-endian 32-bit integer."""
    for k in range(4):  # pragma: no branch
        bytes.append(UInt8((value >> (8 * k)) & 0xFF))


def _file(name: String, version: Int, strands: Int, body: Int) raises -> String:
    """Write a style file's header and `body` zero bytes; return its
    path."""
    var bytes: List[UInt8] = [84, 72, 82, 83]
    _u32(bytes, version)
    _u32(bytes, strands)
    _u32(bytes, 2)
    _u32(bytes, 0)
    for _ in range(body):  # pragma: no branch
        bytes.append(0)
    var path = String("/tmp/threemojo_style_") + name + ".bin"
    Path(path).write_bytes(bytes)
    return path


def test_a_hair_style_is_named() raises:
    assert_true(MOHAWK.is_valid())
    assert_false(HairStyle(-1).is_valid())
    assert_false(HairStyle(3).is_valid())
    assert_equal(len(named_hair_styles()), 3)
    assert_equal(hair_style_label(GROWN), "grown")
    assert_equal(hair_style_label(LAYERED), "layered")
    assert_equal(hair_style_label(MOHAWK), "mohawk")
    assert_equal(hair_style_label(HairStyle(9)), "hair style")
    assert_equal(hair_style_path(LAYERED), "assets/hair/layered.bin")
    with assert_raises(contains="no file"):
        _ = hair_style_path(GROWN)
    with assert_raises(contains="named style"):
        _ = hair_style_path(HairStyle(9))


def test_a_style_file_is_read() raises:
    var style = HairStyleFile(hair_style_path(LAYERED))
    assert_true(style.count > 1000)
    assert_equal(style.points, 16)
    var dims = _dims()
    var strand = style.strand(dims.head, 0)
    assert_equal(len(strand), 16)
    # Its root lies near the scalp, within a couple of centimeters of
    # the skin.
    var skin = HeadSkinField(dims)
    assert_true(abs(skin.distance(strand[0])) < dims.head.cm(2.0))
    with assert_raises(contains="no such strand"):
        _ = style.strand(dims.head, -1)
    with assert_raises(contains="no such strand"):
        _ = style.strand(dims.head, style.count)


def test_a_bad_style_file_is_refused() raises:
    var junk: List[UInt8] = [1, 2, 3]
    var short = String("/tmp/threemojo_style_short.bin")
    Path(short).write_bytes(junk)
    with assert_raises(contains="Not a hair style"):
        _ = HairStyleFile(short)
    var wrong = _file("wrong", 1, 1, 20)
    var bytes = Path(wrong).read_bytes()
    bytes[0] = 88
    Path(wrong).write_bytes(bytes)
    with assert_raises(contains="Not a hair style"):
        _ = HairStyleFile(wrong)
    with assert_raises(contains="another version"):
        _ = HairStyleFile(_file("version", 2, 1, 20))
    with assert_raises(contains="no strands"):
        _ = HairStyleFile(_file("empty", 1, 0, 20))
    with assert_raises(contains="ends early"):
        _ = HairStyleFile(_file("cut", 1, 1, 4))
    # One strand of two points, all at its root.
    var still = HairStyleFile(_file("still", 1, 1, 20))
    assert_equal(still.count, 1)


def test_the_cranium_frame() raises:
    var top = cranium_frame(Vector3(0, 1, 0), Vector3(1, 1, 1))
    assert_true(top[0] == Vector3(1, 0, 0))
    assert_true(top[1] == Vector3(0, 1, 0))
    assert_true(abs(top[2].z + 1) < 1e-6)
    # At the side's pole plus x is the normal: across is plus z.
    var side = cranium_frame(Vector3(1, 0, 0), Vector3(1, 1, 1))
    assert_true(side[0] == Vector3(0, 0, 1))


def test_a_style_is_laid_on_the_head() raises:
    var dims = _dims()
    var skin = HeadSkinField(dims)
    var spec = GroomSpec(dims, 40, 1)
    for style in [LAYERED, MOHAWK]:  # pragma: no branch
        var groom = groom_hair(dims, spec, 1, style)
        assert_equal(len(groom), 80)
        # Every guide's root is on the skin, and no point of it passes
        # under the skin.
        for strand in range(0, len(groom), 2):  # pragma: no branch
            var first = groom.starts[strand]
            assert_true(abs(skin.distance(groom.points[first])) < 1e-3)
            for index in range(
                first + 1, groom.starts[strand + 1]
            ):  # pragma: no branch
                assert_true(skin.distance(groom.points[index]) > 0)
    with assert_raises(contains="named style"):
        _ = groom_hair(dims, spec, 1, HairStyle(5))


def _curled(curl: Float32) raises -> HeadMuscleDimensions:
    """Return the template's head with hair of `curl`."""
    var genome = Genome().with_gene(HAIR_CURL, Expression(curl))
    return head_muscle_dimensions(
        HumanoidSpec(Length(6.0, FOOT), MALE, genome=genome)
    )


def test_curled_hair_winds_round_its_line() raises:
    var straight = _dims()
    var coiled = _curled(1)
    assert_equal(GroomSpec(straight, 8, 0).curl, 0)
    var spec = GroomSpec(coiled, 8, 0)
    assert_true(spec.curl > 0)
    assert_true(spec.curl_length < GroomSpec(_curled(0.3), 8, 0).curl_length)
    # A curled guide is sampled finer, to hold its turns, and every style
    # curls.
    var plain = groom_hair(straight, GroomSpec(straight, 8, 0), 1)
    var curly = groom_hair(coiled, spec, 1)
    assert_true(len(curly.points) > 2 * len(plain.points))
    var laid = groom_hair(coiled, spec, 1, LAYERED)
    assert_true(len(laid.points) > 8 * 16)
    # Curled hair stands fuller off the scalp.
    var skin = HeadSkinField(straight)
    var flat = HairShape(straight, SCALP_HAIR, RIGHT, skin)
    var full = HairShape(coiled, SCALP_HAIR, RIGHT)
    assert_true(full.crown_depth > flat.crown_depth)


def test_a_mohawk_shaves_the_sides() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var skin = HeadSkinField(dims)
    var grown = HairShape(dims, SCALP_HAIR, RIGHT, skin)
    var mohawk = HairShape(dims, SCALP_HAIR, RIGHT, skin, MOHAWK)
    # Over the ear the grown hair covers the scalp; the mohawk's side is
    # bare. On the crown both cover it.
    var side = h.at(7.8, 78.0, -1.0)
    side = side + skin.gradient(side) * (h.cm(0.3) - skin.distance(side))
    assert_true(grown.distance(side) < 0)
    assert_true(mohawk.distance(side) > 0)
    var crown = h.at(0, 84.4, -1.0)
    crown = crown + skin.gradient(crown) * (h.cm(0.3) - skin.distance(crown))
    assert_true(mohawk.distance(crown) < 0)
    with assert_raises(contains="named style"):
        _ = HairShape(dims, SCALP_HAIR, RIGHT, skin, HairStyle(5))
    var shell = head_hair_from_dimensions(dims, SCALP_HAIR, RIGHT, 8, 1, MOHAWK)
    assert_true(shell.triangle_count() > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
