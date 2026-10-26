# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A masked cutoff of 0.2 keeps red and a cutoff of 0.4 clears it."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tools._process import run_program
from tools.carla_town_bake import bake_text
from tools.carla_town_tree import tree_text
from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage
from render.png import decode as decode_png


def test_a_higher_cutoff_clears_the_masked_picture() raises:
    """The low cutoff keeps red, and the high cutoff stores black."""
    var root = mkdtemp(prefix="town cutoff ")
    try:
        var low_tree = _tree(root, 0.2)
        var high_tree = _tree(root, 0.4)
        assert_true(_mean(low_tree, 0) > 40.0)
        assert_true(_max(low_tree, 3) > 0)
        assert_equal(_max_rgb(high_tree), 0)
        assert_equal(_max(high_tree, 3), 0)
        var low_bake = _bake(root, 0.2)
        var high_bake = _bake(root, 0.4)
        assert_true(_mean(low_bake, 0) > 40.0)
        assert_equal(_max_rgb(high_bake), 0)
    finally:
        _ = run_program(["rm", "-rf", root], 10.0)


def test_a_clear_mask_clears_the_picture() raises:
    """An opaque red mask stays red, and a clear mask stores black."""
    var root = mkdtemp(prefix="town mask ")
    try:
        var solid = _masked_tree(root, 1.0)
        var clear = _masked_tree(root, 0.0)
        assert_true(_mean(solid, 0) > 100.0)
        assert_equal(_max(solid, 3), 255)
        assert_equal(_max_rgb(clear), 0)
        assert_equal(_max(clear, 3), 0)
        var solid_bake = _masked_bake(root, 1.0)
        var clear_bake = _masked_bake(root, 0.0)
        assert_true(_mean(solid_bake, 0) > 100.0)
        assert_equal(_max_rgb(clear_bake), 0)
    finally:
        _ = run_program(["rm", "-rf", root], 10.0)


def _masked_tree(root: String, alpha: Float64) raises -> DecodedImage:
    """Draw one far tree through a one-pixel mask."""
    var path = root + "/mask-tree-" + String(alpha) + ".png"
    _ = tree_text(
        '{"size":16,"samples":1,"out":"'
        + path
        + '","parts":['
        + _masked_quad(alpha)
        + "]}"
    )
    return decode_png(Path(path).read_bytes())


def _masked_bake(root: String, alpha: Float64) raises -> DecodedImage:
    """Draw one far building through a one-pixel mask."""
    var path = root + "/mask-bake-" + String(alpha) + ".jpg"
    _ = bake_text(
        '{"out":"'
        + path
        + '","density":6,"most":32,"whole":{"positions":[[0,0,0],[1,0,0],[0,1,1]]},'
        + '"far":{"positions":[[0,0,0],[1,0,0],[0,1,1]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1]]},'
        + '"parts":['
        + _masked_triangle(alpha)
        + '],"views":[{"forward":[0,0,1],"right":[1,0,0],"up":[0,1,0]}]}'
    )
    return decode_jpeg(Path(path).read_bytes())


def _masked_quad(alpha: Float64) -> String:
    """Return one quad textured by a red pixel of `alpha`."""
    return (
        '{"positions":[[0,0,0],[1,0,0],[1,1,1],[0,1,0]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1],[0,0,1]],'
        + '"uvs":[[0,0],[1,0],[1,1],[0,1]],"triangles":[[0,1,2],[0,2,3]],'
        + '"factor":[1,1,1,1],"cut":0.5,"masked":true,"image":{"width":1,'
        + '"height":1,"rgba":[1,0,0,'
        + String(alpha)
        + "]}}"
    )


def _masked_triangle(alpha: Float64) -> String:
    """Return one triangle textured by a red pixel of `alpha`."""
    return (
        '{"positions":[[0,0,0],[1,0,0],[0,1,1]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1]],'
        + '"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
        + '"factor":[1,1,1,1],"cut":0.5,"masked":true,"image":{"width":1,'
        + '"height":1,"rgba":[1,0,0,'
        + String(alpha)
        + "]}}"
    )


def _tree(root: String, cut: Float64) raises -> DecodedImage:
    """Draw one far tree at `cut` and return its picture."""
    var path = root + "/tree-" + String(cut) + ".png"
    _ = tree_text(
        '{"size":16,"samples":1,"out":"'
        + path
        + '","parts":['
        + _tree_part(cut)
        + "]}"
    )
    return decode_png(Path(path).read_bytes())


def _bake(root: String, cut: Float64) raises -> DecodedImage:
    """Draw one far building at `cut` and return its picture."""
    var path = root + "/bake-" + String(cut) + ".jpg"
    _ = bake_text(
        '{"out":"'
        + path
        + '","density":6,"most":32,"whole":{"positions":[[0,0,0],[1,0,0],[0,1,1]]},'
        + '"far":{"positions":[[0,0,0],[1,0,0],[0,1,1]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1]]},'
        + '"parts":['
        + _bake_part(cut)
        + '],"views":[{"forward":[0,0,1],"right":[1,0,0],"up":[0,1,0]}]}'
    )
    return decode_jpeg(Path(path).read_bytes())


def _tree_part(cut: Float64) -> String:
    """Return one quad that has extent on every axis."""
    return (
        '{"positions":[[0,0,0],[1,0,0],[1,1,1],[0,1,0]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1],[0,0,1]],'
        + '"uvs":[[0,0],[1,0],[1,1],[0,1]],"triangles":[[0,1,2],[0,2,3]],'
        + '"factor":[0.6,0,0,0.3],"cut":'
        + String(cut)
        + ',"masked":true}'
    )


def _bake_part(cut: Float64) -> String:
    """Return one triangle for the building bake."""
    return (
        '{"positions":[[0,0,0],[1,0,0],[0,1,1]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1]],'
        + '"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
        + '"factor":[0.6,0,0,0.3],"cut":'
        + String(cut)
        + ',"masked":true}'
    )


def _mean(image: DecodedImage, channel: Int) -> Float64:
    """Return the mean of one channel."""
    var total = 0.0
    var count = image.width * image.height
    for index in range(count):
        total += Float64(Int(image.pixels[index * 4 + channel]))
    return total / Float64(count)


def _max(image: DecodedImage, channel: Int) -> Int:
    """Return the largest sample in one channel."""
    var best = 0
    var count = image.width * image.height
    for index in range(count):
        var sample = Int(image.pixels[index * 4 + channel])
        if sample > best:
            best = sample
    return best


def _max_rgb(image: DecodedImage) -> Int:
    """Return the largest red, green, or blue sample."""
    var best = _max(image, 0)
    var green = _max(image, 1)
    var blue = _max(image, 2)
    if green > best:
        best = green
    if blue > best:
        best = blue
    return best


def main() raises:
    """Run the masked cutoff tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
