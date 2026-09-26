# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.computation`, on the host.

three.js's `GPUComputationRenderer` needs WebGL, which Node has not, so
the expected images here are worked out by hand from the shaders: a
position moved by a velocity that halves and gains one each step, a
neighbor read across a wrapped edge, a texel thrown away, and data whose
alpha is zero. `tests/test_gpu.mojo` holds the device to these images.
"""

from materials.nodes import (
    AT_FRAGMENT,
    AT_RIGHT,
    AT_UP,
    CORNER_A,
    CORNER_B,
    CORNER_C,
)
from postprocessing.sampling import Untracked
from render.computation import ComputeNodes, GPUComputationRenderer
from render.texture import MIRROR, REPEAT
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime SIZE_X = 4
comptime SIZE_Y = 2

comptime MOVE = """
void main() {
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    vec4 p = texture2D( position, uv );
    vec4 v = texture2D( velocity, uv );
    gl_FragColor = vec4( p.xyz + v.xyz, p.w );
}
"""

comptime SLOW = """
void main() {
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    vec4 v = texture2D( velocity, uv );
    gl_FragColor = v * 0.5 + vec4( 1.0, 0.0, 0.0, 0.0 );
}
"""


def _texel(image: List[Float32], x: Int, y: Int, lane: Int) -> Float32:
    """Return one number of a texel, rows from the bottom."""
    return image[(y * SIZE_X + x) * 4 + lane]


def _starting_positions(computation: GPUComputationRenderer) -> List[Float32]:
    """Return an image whose texel (x, y) holds (x, y, 0, 1)."""
    var image = computation.create_texture()
    for y in range(SIZE_Y):
        for x in range(SIZE_X):
            var at = (y * SIZE_X + x) * 4
            image[at] = Float32(x)
            image[at + 1] = Float32(y)
            image[at + 3] = 1
    return image^


def test_a_position_moves_by_a_velocity() raises:
    var computation = GPUComputationRenderer(SIZE_X, SIZE_Y)
    var position = computation.add_variable(
        "position", MOVE, _starting_positions(computation)
    )
    var velocity = computation.add_variable(
        "velocity", SLOW, computation.create_texture()
    )
    computation.set_variable_dependencies(position, [position, velocity])
    computation.set_variable_dependencies(velocity, [velocity])
    computation.init()
    # Each step reads the velocity from before it: 0, then 1, then 1.5.
    computation.compute()
    computation.compute()
    computation.compute()
    var moved = computation.current_image(position)
    var speed = computation.current_image(velocity)
    for y in range(SIZE_Y):
        for x in range(SIZE_X):
            assert_almost_equal(_texel(moved, x, y, 0), Float32(x) + 2.5)
            assert_almost_equal(_texel(moved, x, y, 1), Float32(y))
            assert_almost_equal(_texel(moved, x, y, 3), 1)
            assert_almost_equal(_texel(speed, x, y, 0), 1.75)
    # The other image is the one before the last step.
    assert_almost_equal(
        _texel(computation.alternate_image(velocity), 0, 0, 0), 1.5
    )
    # A texture of the image reads the bottom row last.
    var shown = computation.current_texture(position)
    assert_equal(shown.width, SIZE_X)
    assert_equal(shown.height, SIZE_Y)


def test_a_neighbor_is_read_across_a_wrapped_edge() raises:
    var computation = GPUComputationRenderer(SIZE_X, SIZE_Y)
    var shift = computation.add_variable(
        "field",
        """
void main() {
    vec2 uv = ( gl_FragCoord.xy + vec2( 1.0, 0.0 ) ) / resolution.xy;
    gl_FragColor = texture2D( field, uv );
}
""",
        _starting_positions(computation),
    )
    computation.set_variable_dependencies(shift, [shift])
    computation.variables[shift].wrap_s = REPEAT
    computation.init()
    computation.compute()
    var image = computation.current_image(shift)
    # Each texel takes its right neighbor's, the last the first's.
    assert_equal(_texel(image, 0, 0, 0), 1)
    assert_equal(_texel(image, 3, 0, 0), 0)
    assert_equal(_texel(image, 3, 1, 1), 1)


def test_a_thrown_texel_keeps_its_value_and_data_keeps_its_alpha() raises:
    var computation = GPUComputationRenderer(SIZE_X, SIZE_Y)
    var cut = computation.add_variable(
        "cut",
        """
void main() {
    if ( gl_FragCoord.x > 2.0 ) discard;
    gl_FragColor = vec4( 3.0, -2.0, 0.25, 0.0 );
}
""",
        _starting_positions(computation),
    )
    computation.init()
    computation.compute()
    var image = computation.current_image(cut)
    # Written, with an alpha of zero and nothing premultiplied.
    assert_equal(_texel(image, 0, 0, 0), 3)
    assert_equal(_texel(image, 1, 1, 1), -2)
    assert_equal(_texel(image, 1, 0, 3), 0)
    # Thrown away: the texel keeps what the other image held.
    assert_equal(_texel(image, 3, 1, 0), 3)
    assert_equal(_texel(image, 3, 1, 3), 1)


def test_a_mirrored_edge_reads_back_inward() raises:
    var computation = GPUComputationRenderer(SIZE_X, SIZE_Y)
    var shift = computation.add_variable(
        "field",
        """
void main() {
    vec2 uv = ( gl_FragCoord.xy + vec2( 2.0, -3.0 ) ) / resolution.xy;
    gl_FragColor = texture2D( field, uv );
}
""",
        _starting_positions(computation),
    )
    computation.set_variable_dependencies(shift, [shift])
    computation.variables[shift].wrap_s = MIRROR
    computation.variables[shift].wrap_t = MIRROR
    computation.init()
    computation.compute()
    var image = computation.current_image(shift)
    # Across, x 3 reads x 5, which mirrors to 2. Up, y 0 reads y -3,
    # which mirrors to 1, and y 1 reads y -2, which mirrors to 1 too.
    assert_equal(_texel(image, 3, 0, 0), 2)
    assert_equal(_texel(image, 0, 0, 1), 1)
    assert_equal(_texel(image, 0, 1, 1), 1)


def test_the_texel_source_answers_for_its_neighbors() raises:
    var code = List[Float32](length=4, fill=0)
    var images = List[Float32](length=4, fill=0)
    var wraps = List[Int32](length=2, fill=0)
    var source = ComputeNodes(
        code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked](),
        images.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked](),
        wraps.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked](),
        4,
        2,
        1,
        0,
    )
    assert_equal(source.frag_coord(AT_RIGHT)[0], 2.5)
    assert_equal(source.frag_coord(AT_UP)[1], 1.5)
    assert_equal(source.frag_coord(AT_FRAGMENT)[0], 1.5)
    var here = source.shares(AT_FRAGMENT)
    var right = source.shares(AT_RIGHT)
    var up = source.shares(AT_UP)
    assert_almost_equal(right[1] - here[1], Float32(0.25))
    assert_almost_equal(up[2] - here[2], Float32(0.5))
    assert_equal(source.corner(CORNER_A).u, 0)
    assert_equal(source.corner(CORNER_B).u, 1)
    assert_equal(source.corner(CORNER_C).v, 1)
    _ = code^
    _ = images^
    _ = wraps^


def test_a_computation_of_nothing_steps_nothing() raises:
    var computation = GPUComputationRenderer(SIZE_X, SIZE_Y)
    computation.init()
    computation.compute()
    var a = computation.add_variable("a", SLOW, computation.create_texture())
    computation.set_variable_dependencies(a, [])
    assert_equal(len(computation.variables[a].dependencies), 0)


def test_a_computation_refuses_what_it_cannot_run() raises:
    with assert_raises(contains="need a size"):
        _ = GPUComputationRenderer(0, 2)
    with assert_raises(contains="need a size"):
        _ = GPUComputationRenderer(2, 0)
    var computation = GPUComputationRenderer(SIZE_X, SIZE_Y)
    with assert_raises(contains="computation's size"):
        _ = computation.add_variable("a", SLOW, List[Float32]())
    var a = computation.add_variable("a", SLOW, computation.create_texture())
    with assert_raises(contains="no variable"):
        computation.set_variable_dependencies(a, [5])
    with assert_raises(contains="no variable"):
        computation.set_variable_dependencies(-1, [a])
    with assert_raises(contains="initialized"):
        computation.compute()
    with assert_raises(contains="no variable"):
        _ = computation.current_image(3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
