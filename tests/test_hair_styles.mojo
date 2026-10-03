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
    HairBody,
    HairGroom,
    groom_hair,
)
from extensions.humanoid.skeleton.head.hair.styles import (
    BOB,
    BRAID,
    BUN,
    GROWN,
    HALF_UP,
    HIGH_PONYTAIL,
    LONG,
    PIGTAILS,
    PIXIE,
    PONYTAIL,
    SPACE_BUNS,
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
from test_scratch import TestScratch, temporary_path
from std.pathlib import Path
from std.math import max
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


def _file(
    name: String, version: Int, strands: Int, body: Int, points: Int = 2
) raises -> String:
    """Write a style file's header and `body` zero bytes; return its
    path."""
    var bytes: List[UInt8] = [84, 72, 82, 83]
    _u32(bytes, version)
    _u32(bytes, strands)
    _u32(bytes, points)
    _u32(bytes, 0)
    for _ in range(body):  # pragma: no branch
        bytes.append(0)
    var path = temporary_path("threemojo_style_") + name + ".bin"
    Path(path).write_bytes(bytes)
    return path


def test_a_hair_style_is_named() raises:
    assert_true(MOHAWK.is_valid())
    assert_false(HairStyle(-1).is_valid())
    assert_false(HairStyle(13).is_valid())
    assert_equal(len(named_hair_styles()), 13)
    assert_equal(hair_style_label(HIGH_PONYTAIL), "high ponytail")
    assert_equal(hair_style_label(PIXIE), "pixie")
    assert_true(BOB.is_designed() and not GROWN.is_designed())
    assert_true(not MOHAWK.is_designed() and not HairStyle(99).is_designed())
    assert_equal(PIGTAILS.ties(), 2)
    assert_equal(SPACE_BUNS.ties(), 2)
    assert_equal(BRAID.ties(), 1)
    assert_equal(HALF_UP.ties(), 1)
    assert_equal(BOB.ties(), 0)
    assert_true(HALF_UP.is_designed() and not HALF_UP.is_tied())
    assert_equal(hair_style_label(LONG), "long")
    assert_equal(hair_style_label(PONYTAIL), "ponytail")
    assert_equal(hair_style_label(BUN), "bun")
    assert_true(LAYERED.is_scanned() and not LONG.is_scanned())
    assert_true(BUN.is_tied() and PONYTAIL.is_tied() and not LONG.is_tied())
    assert_equal(hair_style_label(GROWN), "grown")
    assert_equal(hair_style_label(LAYERED), "layered")
    assert_equal(hair_style_label(MOHAWK), "mohawk")
    assert_equal(hair_style_label(HairStyle(99)), "hair style")
    assert_equal(hair_style_path(LAYERED), "assets/hair/layered.bin")
    with assert_raises(contains="no file"):
        _ = hair_style_path(GROWN)
    with assert_raises(contains="no file"):
        _ = hair_style_path(PONYTAIL)
    with assert_raises(contains="named style"):
        _ = hair_style_path(HairStyle(99))


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
    var short = temporary_path("threemojo_style_short.bin")
    Path(short).write_bytes(junk)
    with assert_raises(contains="Not a hair style"):
        _ = HairStyleFile(short)
    var wrong = _file("wrong", 1, 1, 20)
    var bytes = Path(wrong).read_bytes()
    for index in range(1, 4):
        var invalid = bytes.copy()
        invalid[index] = 88
        Path(wrong).write_bytes(invalid)
        with assert_raises(contains="Not a hair style"):
            _ = HairStyleFile(wrong)
    bytes[0] = 88
    Path(wrong).write_bytes(bytes)
    with assert_raises(contains="Not a hair style"):
        _ = HairStyleFile(wrong)
    with assert_raises(contains="another version"):
        _ = HairStyleFile(_file("version", 2, 1, 20))
    with assert_raises(contains="no strands"):
        _ = HairStyleFile(_file("empty", 1, 0, 20))
    with assert_raises(contains="no strands"):
        _ = HairStyleFile(_file("point", 1, 1, 20, 1))
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
    # The center has no normal: up is left as nothing.
    var center = cranium_frame(Vector3(0, 0, 0), Vector3(1, 1, 1))
    assert_true(center[1] == Vector3(0, 0, 0))


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
        _ = groom_hair(dims, spec, 1, HairStyle(99))


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


def test_long_tied_and_bunned_hair_is_designed() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var spec = GroomSpec(dims, 12, 0)
    # Long hair falls well past the chin.
    var long = groom_hair(dims, spec, 1, LONG)
    assert_equal(len(long), 12)
    var lowest = Float32(1.0e9)
    for index in range(len(long.points)):  # pragma: no branch
        lowest = min(lowest, long.points[index].y)
    assert_true(lowest < h.at(0, 55.0, 0).y)
    # A ponytail's tail falls from the back of the head.
    var tail = groom_hair(dims, spec, 1, PONYTAIL)
    var tip = tail.points[tail.starts[1] - 1]
    assert_true(tip.y < h.at(0, 70.0, 0).y and tip.z < h.at(0, 0, -8.0).z)
    # Hair from the brow is combed up over the crown to the tie, not
    # down the forehead.
    for strand in range(len(tail)):  # pragma: no branch
        var root = tail.points[tail.starts[strand]]
        if root.z < h.at(0, 0, 4.0).z:
            continue
        var highest = root.y
        for k in range(tail.starts[strand], tail.starts[strand] + 6):
            highest = max(highest, tail.points[k].y)
        assert_true(highest > root.y)
    # A bun's strands end round the ball on its tie.
    var bun = groom_hair(dims, spec, 1, BUN)
    var tie = h.at(0, 83.0, -6.5)
    for strand in range(len(bun)):  # pragma: no branch
        var end = bun.points[bun.starts[strand + 1] - 1]
        assert_true((end - tie).length() < h.cm(9.0))
    # Tied and long hair lie close on the scalp.
    var skin = HeadSkinField(dims)
    var grown = HairShape(dims, SCALP_HAIR, RIGHT, skin)
    assert_true(
        HairShape(dims, SCALP_HAIR, RIGHT, skin, LONG).crown_depth
        < grown.crown_depth
    )
    var none = GroomSpec(dims, 4, 0)
    none.root_tries = 0
    with assert_raises(contains="root"):
        _ = groom_hair(dims, none, 1, BUN)


def _tips(groom: HairGroom) -> List[Vector3]:
    """Return the last point of every strand."""
    var tips = List[Vector3]()
    for strand in range(len(groom)):  # pragma: no branch
        tips.append(groom.points[groom.starts[strand + 1] - 1])
    return tips^


def test_hair_is_tied_on_both_sides() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var spec = GroomSpec(dims, 16, 0)
    # Pigtails fall on both sides, below the ears.
    var left = 0
    var right = 0
    for tip in _tips(groom_hair(dims, spec, 1, PIGTAILS)):  # pragma: no branch
        assert_true(tip.y < h.at(0, 70.0, 0).y)
        if tip.x > 0:
            right += 1
        else:
            left += 1
    assert_true(left > 0 and right > 0)
    # Space buns coil on both sides of the crown.
    var sides = 0
    var other = 0
    for tip in _tips(
        groom_hair(dims, spec, 1, SPACE_BUNS)
    ):  # pragma: no branch
        assert_true(tip.y > h.at(0, 78.0, 0).y)
        if tip.x > 0:
            sides += 1
        else:
            other += 1
    assert_true(sides > 0 and other > 0)


def test_a_braid_and_a_high_ponytail_hang_behind() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var spec = GroomSpec(dims, 12, 0)
    for tip in _tips(groom_hair(dims, spec, 1, BRAID)):  # pragma: no branch
        assert_true(tip.y < h.at(0, 50.0, 0).y)
        assert_true(tip.z < h.at(0, 0, -8.0).z)
    # The high ponytail's tail springs from high on the crown.
    var high = groom_hair(dims, spec, 1, HIGH_PONYTAIL)
    var top = Float32(-1e9)
    for p in high.points:  # pragma: no branch
        top = max(top, p.y)
    assert_true(top > h.at(0, 82.0, 0).y)


def test_cut_styles_end_where_they_are_cut() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var spec = GroomSpec(dims, 16, 0)
    # A bob is cut level at the jaw: no hair falls far below it.
    var bob = groom_hair(dims, spec, 1, BOB)
    for p in bob.points:  # pragma: no branch
        assert_true(p.y > h.at(0, 61.0, 0).y)
    # A pixie's strands are a few centimeters long.
    var pixie = groom_hair(dims, spec, 1, PIXIE)
    for strand in range(len(pixie)):  # pragma: no branch
        var root = pixie.points[pixie.starts[strand]]
        var tip = pixie.points[pixie.starts[strand + 1] - 1]
        assert_true((tip - root).length() < h.cm(8.0))
    # Half up: the top is tied short at the back, the rest falls long.
    var half = groom_hair(dims, spec, 1, HALF_UP)
    var long = 0
    var short = 0
    for tip in _tips(half):  # pragma: no branch
        if tip.y < h.at(0, 58.0, 0).y:
            long += 1
        else:
            short += 1
    assert_true(long > 0 and short > 0)


def test_hair_falls_against_the_head_and_the_body() raises:
    var dims = _dims()
    var h = dims.head.copy()
    var body = HairBody(dims)
    # Over the crown the head's own grid counts: just above it, the hair
    # is just outside.
    var crown = h.at(0, 86.0, -1.0)
    var above = body.distance(crown)
    assert_true(above > 0 and above < h.cm(3.0))
    assert_equal(body.distance(crown), body.head.distance(crown))
    # Above the chin the body's grid is pushed away.
    assert_equal(body.joined(Float32(0.5), crown), Float32(0.5))
    # Over the shoulder, past the head's box, the body's grid counts.
    var shoulder = h.at(-17.0, 50.0, 0)
    assert_true(body.distance(shoulder) < h.cm(6.0))
    assert_true(body.distance(shoulder) < body.head.distance(shoulder))


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
        _ = HairShape(dims, SCALP_HAIR, RIGHT, skin, HairStyle(99))
    var shell = head_hair_from_dimensions(dims, SCALP_HAIR, RIGHT, 8, 1, MOHAWK)
    assert_true(shell.triangle_count() > 0)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
