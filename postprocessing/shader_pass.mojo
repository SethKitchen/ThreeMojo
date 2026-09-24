# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node program run over the screen: three.js's `ShaderPass`, and
`SavePass`'s image read back.

three.js's `ShaderPass` draws a full-screen quad with a `ShaderMaterial`
and binds the frame to its `tDiffuse` uniform. This port runs a compiled
`materials.nodes.NodeProgram` at every pixel instead: one built with
`NodeGraph`, or one `materials.glsl.compile_shader_material` compiled from
GLSL, with `SCREEN_VERTEX_SHADER` as its vertex shader.

**The quad.** Each pixel is a fragment of one triangle whose corners have
the texture coordinates (0, 0), (1, 0) and (0, 1), and the positions
(-1, -1, 0), (1, -1, 0) and (-1, 1, 0). So `uv` and a varying copied from
it are the pixel's texture coordinate, and the position is the pixel's
place on the screen. The normal is +z, the vertex color white, and `lit`
is the pixel's own straight color.

**The textures.** The sampler uniform named `input`, `tDiffuse` by
default, reads the frame before the pass, bilinear and clamped at the
edges, as a render target's texture reads it. The sampler named `saved`
reads the image a `SavePass` kept. Every other sampler reads a texture in
the assets, through its own wrap and filter.

**The result.** The output node, or else the color node, is the straight
color; the opacity node is the alpha. An output the program leaves out
keeps the pixel's own. A fragment the mask node or a `discard` throws away
keeps the pixel as it was.
"""

from materials.nodes import (
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    MASK_NODE,
    NODE_SAMPLER,
    OPACITY_NODE,
    OUTPUT_NODE,
    PROGRAM_TIME,
    AT_RIGHT,
    AT_UP,
    NodeContext,
    NodeInputs,
    NodeProgram,
    NodeProgramId,
    NodeSource,
    NO_NODES,
    has_output,
    run_nodes,
)
from math.vector3 import Vector3
from postprocessing.sampling import LightView, Untracked, u_of, v_of
from render.framebuffer import FloatColor
from render.target import RenderTarget
from render.texture_store import TextureStore

comptime Lanes = SIMD[DType.float32, 4]

# The vertex shader three.js's screen shaders share. Compile a fragment
# shader against it with `compile_shader_material`.
comptime SCREEN_VERTEX_SHADER = """
varying vec2 vUv;
void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
"""
# The texture slot that reads the frame before the pass.
comptime INPUT_SLOT = -1
# The texture slot that reads the image a save pass kept.
comptime SAVED_SLOT = -2


struct ShaderSettings(Copyable, Movable):
    """What a shader pass reads: three.js's `ShaderPass` constructor
    arguments, less the material, which is a program in the assets."""

    # The program, in the assets' `programs`.
    var program: NodeProgramId
    # The sampler uniform bound to the frame: three.js's `textureID`.
    var input: String
    # A sampler uniform bound to a save pass's image, or empty for none.
    var saved: String
    # Which pass, by index in the composer, is that save pass.
    var saved_pass: Int

    def __init__(out self, program: NodeProgramId = NO_NODES):
        """Start with the frame bound to `tDiffuse` and nothing saved.

        Args:
            program: The program.
        """
        self.program = program
        self.input = "tDiffuse"
        self.saved = ""
        self.saved_pass = -1


def check_shader(settings: ShaderSettings) raises:
    """Refuse shader settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the program is `NO_NODES` or negative, or a saved
            sampler names no pass.
    """
    if settings.program.value < 0:
        raise Error("A shader pass needs a node program to run")
    if settings.saved.byte_length() > 0 and settings.saved_pass < 0:
        raise Error("A saved sampler must name a save pass")


def _bind(
    mut code: List[Float32], program: NodeProgram, name: String, slot: Int
):
    """Point every sampler uniform called `name` at `slot`."""
    for index in range(len(program.uniform_names)):
        var sampler = program.uniform_types[index] == NODE_SAMPLER
        if sampler and program.uniform_names[index] == name:
            code[program.uniform_offsets[index]] = Float32(slot)


def screen_code(
    program: NodeProgram, settings: ShaderSettings, time: Float32
) -> List[Float32]:
    """Return a copy of a program's floats with the input and the saved
    samplers bound to their slots and the time written.

    A name the program does not declare binds nothing, as three.js's
    `ShaderPass` sets `tDiffuse` only when the shader has it.

    Args:
        program: The program.
        settings: The two names.
        time: The seconds the `time` node reads.

    Returns:
        The floats, which a `ScreenNodes` reads.
    """
    var code = program.code.copy()
    _bind(code, program, settings.input, INPUT_SLOT)
    if settings.saved.byte_length() > 0:
        _bind(code, program, settings.saved, SAVED_SLOT)
    code[PROGRAM_TIME] = time
    return code^


def reads_assets(program: NodeProgram, settings: ShaderSettings) -> Bool:
    """Return True if a program reads a texture in the assets: a sampler
    that is neither the input nor the saved one.

    Args:
        program: The program.
        settings: The two names.

    Returns:
        Whether it does. The GPU backend runs such a pass on the host.
    """
    for index in range(len(program.uniform_names)):
        var name = program.uniform_names[index]
        var sampler = program.uniform_types[index] == NODE_SAMPLER
        var bound = name == settings.input or name == settings.saved
        if sampler and not bound:
            return True
    return False


struct ScreenNodes(ImplicitlyCopyable, NodeSource):
    """The `NodeSource` of a pixel on the screen quad: the program's
    floats, the frame, the saved image and the pixel. Both backends build
    one; the GPU backend's floats and images are device buffers.

    A sampler that is neither the input nor the saved one reads opaque
    white here; `HostScreenNodes` reads the assets for it.
    """

    var code: Pointer[Float32, Untracked]
    var input: LightView
    var saved: LightView
    var x: Int
    var y: Int

    def __init__(
        out self,
        code: Pointer[Float32, Untracked],
        input: LightView,
        saved: LightView,
        x: Int,
        y: Int,
    ):
        """Point at a program, the two images and a pixel.

        Args:
            code: The program's floats, from `screen_code`. They must
                outlive the source.
            input: The frame before the pass.
            saved: The saved image, the frame's size, or the frame again
                when there is none.
            x: The column.
            y: The row, down from the top.
        """
        self.code = code
        self.input = input
        self.saved = saved
        self.x = x
        self.y = y

    def word(self, at: Int) -> Float32:
        """Return one float of the program.

        Args:
            at: Its offset.

        Returns:
            The float.
        """
        return self.code[unsafe_offset=at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return the input or the saved image at a coordinate, straight.

        Args:
            slot: `INPUT_SLOT`, `SAVED_SLOT`, or a texture in the assets.
            u: Across.
            v: Up.

        Returns:
            The straight color; opaque white for a texture in the assets.
        """
        if slot == INPUT_SLOT:
            return self.input.sample(u, v).unpremultiplied()
        if slot == SAVED_SLOT:
            return self.saved.sample(u, v).unpremultiplied()
        return FloatColor(1, 1, 1, 1)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the three corners' weights at the pixel, the pixel to its
        right or the pixel above it: one minus u minus v, u and v.

        Args:
            context: Which sample.

        Returns:
            The weights.
        """
        var u = u_of(self.x, self.input.width)
        var v = v_of(self.y, self.input.height)
        if context == AT_RIGHT:
            u += 1 / Float32(self.input.width)
        if context == AT_UP:
            v += 1 / Float32(self.input.height)
        return Lanes(1 - u - v, u, v, 0)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return one corner of the screen quad's triangle.

        Args:
            context: `CORNER_A`, `CORNER_B` or `CORNER_C`.

        Returns:
            The corner's coordinate, position, normal and white color.
        """
        var u = Float32(0)
        var v = Float32(0)
        if context == CORNER_B:
            u = 1
        elif context != CORNER_A:
            v = 1
        var white = Vector3(1, 1, 1)
        return NodeInputs(
            u,
            v,
            Vector3(u * 2 - 1, v * 2 - 1, 0),
            Vector3(0, 0, 1),
            white,
            Vector3(0, 0, 0),
            True,
        )


struct HostScreenNodes[origin: Origin[mut=False]](NodeSource):
    """The host's `NodeSource` for the screen quad: a `ScreenNodes` that
    reads the assets' textures for every other sampler."""

    var screen: ScreenNodes
    var textures: Pointer[TextureStore, Self.origin]

    def __init__(
        out self,
        screen: ScreenNodes,
        textures: Pointer[TextureStore, Self.origin],
    ):
        """Wrap a screen source.

        Args:
            screen: The pixel's source.
            textures: The assets' textures.
        """
        self.screen = screen
        self.textures = textures

    def word(self, at: Int) -> Float32:
        """Return one float of the program.

        Args:
            at: Its offset.

        Returns:
            The float.
        """
        return self.screen.word(at)

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return an image or a texture at a coordinate, straight.

        Args:
            slot: `INPUT_SLOT`, `SAVED_SLOT`, or a texture in the assets.
            u: Across.
            v: Up.

        Returns:
            The straight color.
        """
        if slot < 0:
            return self.screen.sample(slot, u, v)
        return self.textures[].textures[slot].sample(u, v)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the screen quad's weights; see `ScreenNodes.shares`.

        Args:
            context: Which sample.

        Returns:
            The weights.
        """
        return self.screen.shares(context)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return one corner of the screen quad; see `ScreenNodes.corner`.

        Args:
            context: Which corner.

        Returns:
            The corner.
        """
        return self.screen.corner(context)


def screen_pixel[
    S: NodeSource
](source: S, color: FloatColor, u: Float32, v: Float32) -> FloatColor:
    """Return one pixel of a shader pass: what both backends run.

    Args:
        source: The pixel's source.
        color: The pixel's light before the pass, premultiplied.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.

    Returns:
        The light the program writes, premultiplied, or `color` where the
        fragment is thrown away.
    """
    var base = color.unpremultiplied()
    var own = Vector3(base.r, base.g, base.b)
    var inputs = NodeInputs(
        u,
        v,
        Vector3(u * 2 - 1, v * 2 - 1, 0),
        Vector3(0, 0, 1),
        Vector3(1, 1, 1),
        own,
        True,
    )
    if has_output(source, MASK_NODE):
        if run_nodes(source, MASK_NODE, inputs)[0] == 0:
            return color
    var shown = base
    if has_output(source, OUTPUT_NODE):
        var out = run_nodes(source, OUTPUT_NODE, inputs)
        shown = FloatColor(out[0], out[1], out[2], base.a)
    elif has_output(source, COLOR_NODE):
        var out = run_nodes(source, COLOR_NODE, inputs)
        shown = FloatColor(out[0], out[1], out[2], base.a)
    if has_output(source, OPACITY_NODE):
        shown.a = run_nodes(source, OPACITY_NODE, inputs)[0]
    return shown.premultiplied()


def shader_light(
    mut frame: RenderTarget,
    program: NodeProgram,
    settings: ShaderSettings,
    saved: List[FloatColor],
    textures: TextureStore,
    time: Float32,
) raises:
    """Run a node program over the frame: three.js's `ShaderPass`.

    Args:
        frame: The frame, changed in place.
        program: The program.
        settings: Which samplers read the frame and the saved image.
        saved: The saved image, the frame's size, or empty.
        textures: The textures every other sampler reads.
        time: The seconds the `time` node reads.

    Raises:
        Error: If the saved image is neither empty nor the frame's size,
            or a texture the program reads is not in the store.
    """
    var width = frame.width
    var height = frame.height
    var count = width * height
    if len(saved) != 0 and len(saved) != count:
        raise Error("A saved image must be the frame's size")
    for index in range(len(program.textures)):
        if program.textures[index].value >= textures.count():
            raise Error("A shader pass reads a texture that is not there")
    var code = screen_code(program, settings, time)
    var source = frame.colors.copy()
    var input = LightView(source, width, height)
    # Before a save pass has run, its image is one transparent black
    # texel, as three.js's target is before it is drawn.
    var kept_colors = saved.copy()
    var kept = LightView(kept_colors, width, height)
    if len(saved) == 0:
        kept_colors = [FloatColor(0, 0, 0, 0)]
        kept = LightView(kept_colors, 1, 1)
    var pointer = (
        code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var store = Pointer(to=textures)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var slot = y * width + x
            var screen = ScreenNodes(pointer, input, kept, x, y)
            frame.colors[slot] = screen_pixel(
                HostScreenNodes(screen, store),
                source[slot],
                u_of(x, width),
                v_of(y, height),
            )
            frame.data[slot] = False
    # The views and the pointer do not keep their lists alive; this does.
    _ = source^
    _ = kept_colors^
    _ = code^
