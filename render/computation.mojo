# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fragment programs run over float images, step by step, from three.js
`examples/jsm/misc/GPUComputationRenderer.js`.

A `GPUComputationRenderer` holds variables. Each variable is an image of
`size_x` by `size_y` texels, four floats each, and a GLSL fragment shader
that works out the image's next state. `compute` runs every variable's
shader once, at every texel, and the new images replace the old: three.js
ping-pongs two render targets a variable, and so does this.

A shader reads its dependencies as `sampler2D` uniforms named after them,
which `init` declares, and finds its texel as three.js's shaders do:
`gl_FragCoord.xy / resolution.xy`, `resolution` a `#define` of the size.
It writes `gl_FragColor`, all four numbers as they are: no clamp, and no
premultiplying. A dependency is read at the texel its coordinate falls
in, three.js's `NearestFilter`, and wrapped by its variable's `wrap_s`
and `wrap_t`.

Every variable reads the images as they were before the step: a variable
computed after another in the same step still reads the other's old
image, as three.js's does.

**The images.** An image lies row by row from the bottom, as a texture's
texels do in GLSL: texel (x, y) starts at `(y * size_x + x) * 4`.

**The GPU.** `render.gpu.GpuComputation.compute` runs a step on the
device. Both backends call `compute_texel` on a `ComputeNodes`, so the two
agree to the float.

**Where this differs from three.js.** The images are float lists, and
`current_texture` makes a texture of one for a material to read. Only
`FloatType` and `NearestFilter` are there: `set_data_type` and a linear
filter are not ported. A shader's other uniforms are set on
`programs[variable]` after `init`, which compiles the shaders.
"""

from materials.glsl import compile_shader_material
from materials.nodes import (
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    MASK_NODE,
    NodeContext,
    NodeInputs,
    NodeProgram,
    NodeSource,
    OPACITY_NODE,
    has_output,
    run_nodes,
)
from math.vector3 import Vector3
from postprocessing.shader_pass import SCREEN_VERTEX_SHADER
from postprocessing.sampling import Untracked
from render.framebuffer import FloatColor
from render.texture_store import TextureId
from render.texture import (
    CLAMP,
    MIRROR,
    NEAREST,
    REPEAT,
    Texture,
    Wrap,
    float_texture,
)
from std.math import floor

comptime Lanes = SIMD[DType.float32, 4]


def _wrapped(index: Int, size: Int, wrap: Int) -> Int:
    """Return a texel index kept on an image by a wrap mode: `CLAMP`,
    `REPEAT` or `MIRROR`, as their values."""
    # Mojo's `%` takes the sign of the divisor, so neither remainder is
    # negative.
    if wrap == REPEAT.value:
        return index % size
    if wrap == MIRROR.value:
        var period = 2 * size
        var kept = index % period
        return kept if kept < size else period - 1 - kept
    return max(0, min(size - 1, index))


struct ComputeNodes(ImplicitlyCopyable, NodeSource):
    """The `NodeSource` of one texel of a step: the program's floats, every
    variable's image before the step, and the texel. Both backends build
    one.

    A sampler's slot is a variable's place: `images` holds each variable's
    image in turn, `size_x` by `size_y` texels, and `wraps` its two wrap
    modes.
    """

    var code: Pointer[Float32, Untracked]
    var images: Pointer[Float32, Untracked]
    var wraps: Pointer[Int32, Untracked]
    var size_x: Int
    var size_y: Int
    # The texel, from the left and from the bottom.
    var x: Int
    var y: Int

    def __init__(
        out self,
        code: Pointer[Float32, Untracked],
        images: Pointer[Float32, Untracked],
        wraps: Pointer[Int32, Untracked],
        size_x: Int,
        size_y: Int,
        x: Int,
        y: Int,
    ):
        """Point at a program, the images and a texel.

        Args:
            code: The program's floats.
            images: Every variable's image, one after another.
            wraps: Every variable's two wrap modes, across then up.
            size_x: How many texels across an image is.
            size_y: How many texels up.
            x: The texel's column, from the left.
            y: The texel's row, from the bottom.
        """
        self.code = code
        self.images = images
        self.wraps = wraps
        self.size_x = size_x
        self.size_y = size_y
        self.x = x
        self.y = y

    def word(self, at: Int) -> Float32:
        """Return one float of the program.

        Args:
            at: Which float.

        Returns:
            The float.
        """
        return self.code[unsafe_offset=at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return the texel of a variable's image that a coordinate falls in,
        three.js's `NearestFilter`, wrapped by the variable's modes.

        Args:
            slot: Which variable.
            u: Across, from zero to one.
            v: Up, from zero to one.

        Returns:
            The texel's four floats, as they are.
        """
        var ix = Int(floor(u * Float32(self.size_x)))
        var iy = Int(floor(v * Float32(self.size_y)))
        ix = _wrapped(ix, self.size_x, Int(self.wraps[unsafe_offset=slot * 2]))
        iy = _wrapped(
            iy, self.size_y, Int(self.wraps[unsafe_offset=slot * 2 + 1])
        )
        var at = (slot * self.size_x * self.size_y + iy * self.size_x + ix) * 4
        return FloatColor(
            self.images[unsafe_offset=at],
            self.images[unsafe_offset=at + 1],
            self.images[unsafe_offset=at + 2],
            self.images[unsafe_offset=at + 3],
        )

    def shares(self, context: NodeContext) -> Lanes:
        """Return the screen quad's weights at the texel, the texel to its
        right or the texel above it.

        Args:
            context: Which sample.

        Returns:
            The weights: one minus u minus v, u and v.
        """
        var u = (Float32(self.x) + 0.5) / Float32(self.size_x)
        var v = (Float32(self.y) + 0.5) / Float32(self.size_y)
        if context == AT_RIGHT:
            u += 1 / Float32(self.size_x)
        if context == AT_UP:
            v += 1 / Float32(self.size_y)
        return Lanes(1 - u - v, u, v, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return where the texel is, GLSL's `gl_FragCoord`: its center, or
        its neighbor's for a derivative, from the bottom left; the quad's
        depth of one half; and one.

        Args:
            context: Which sample.

        Returns:
            The four numbers.
        """
        var x = self.x + (1 if context == AT_RIGHT else 0)
        var y = self.y + (1 if context == AT_UP else 0)
        return Lanes(Float32(x) + 0.5, Float32(y) + 0.5, 0.5, 1)

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
        return NodeInputs(
            u,
            v,
            Vector3(u * 2 - 1, v * 2 - 1, 0),
            Vector3(0, 0, 1),
            Vector3(1, 1, 1),
            Vector3(0, 0, 0),
            True,
        )


def compute_texel[
    S: NodeSource
](source: S, u: Float32, v: Float32) -> Tuple[Lanes, Bool]:
    """Return what a program writes at one texel, `gl_FragColor` as it is,
    and whether it writes the texel: what both backends run.

    Args:
        source: The texel's source.
        u: The texel's coordinate across.
        v: Its coordinate up.

    Returns:
        The four floats, and whether the texel is written: False where
        the shader throws it away.
    """
    var inputs = NodeInputs(
        u,
        v,
        Vector3(u * 2 - 1, v * 2 - 1, 0),
        Vector3(0, 0, 1),
        Vector3(1, 1, 1),
        Vector3(0, 0, 0),
        True,
    )
    if has_output(source, MASK_NODE):
        if run_nodes(source, MASK_NODE, inputs)[0] == 0:
            return (Lanes(0), False)
    # A computation's program is GLSL, which always writes a color and its
    # alpha, or is refused.
    var out = run_nodes(source, COLOR_NODE, inputs)
    out[3] = run_nodes(source, OPACITY_NODE, inputs)[0]
    return (out, True)


struct ComputeVariable(Copyable, Movable):
    """One image and the shader that steps it, three.js's variable."""

    var name: String
    var fragment_shader: String
    # The variable's other variables, by place, whose images its shader
    # reads by their names.
    var dependencies: List[Int]
    # How the shader's reads of this image wrap, three.js's `wrapS` and
    # `wrapT`: clamped unless set.
    var wrap_s: Wrap
    var wrap_t: Wrap
    # The two images, three.js's `renderTargets`, row by row from the
    # bottom.
    var images: List[List[Float32]]

    def __init__(
        out self,
        name: String,
        fragment_shader: String,
        var initial: List[Float32],
    ):
        """Hold a variable before `init`: both images start at `initial`.

        Args:
            name: Its name, the sampler its dependents read it by.
            fragment_shader: The GLSL that steps it.
            initial: Its first image.
        """
        self.name = name
        self.fragment_shader = fragment_shader
        self.dependencies = List[Int]()
        self.wrap_s = CLAMP
        self.wrap_t = CLAMP
        self.images = List[List[Float32]]()
        self.images.append(initial.copy())
        self.images.append(initial^)


struct GPUComputationRenderer(Movable):
    """Float images stepped by fragment shaders, three.js's
    `GPUComputationRenderer`."""

    var size_x: Int
    var size_y: Int
    var variables: List[ComputeVariable]
    # Each variable's compiled program, after `init`.
    var programs: List[NodeProgram]
    # Which of each variable's two images is current, three.js's
    # `currentTextureIndex`.
    var current: Int

    def __init__(out self, size_x: Int, size_y: Int) raises:
        """Create a computation over images of one size.

        Args:
            size_x: How many texels across.
            size_y: How many texels up.

        Raises:
            Error: If either size is not positive.
        """
        if size_x <= 0 or size_y <= 0:
            raise Error("A computation's images need a size")
        self.size_x = size_x
        self.size_y = size_y
        self.variables = List[ComputeVariable]()
        self.programs = List[NodeProgram]()
        self.current = 0

    def create_texture(self) -> List[Float32]:
        """Return an image of zeros, three.js's `createTexture`, for a
        variable's first image.

        Returns:
            Four zeros a texel.
        """
        return List[Float32](length=self.size_x * self.size_y * 4, fill=0)

    def add_variable(
        mut self,
        name: String,
        fragment_shader: String,
        var initial: List[Float32],
    ) raises -> Int:
        """Add a variable, three.js's `addVariable`.

        Args:
            name: Its name, the sampler its dependents read it by.
            fragment_shader: The GLSL that steps it.
            initial: Its first image, four floats a texel.

        Returns:
            Its place, for `set_variable_dependencies` and the rest.

        Raises:
            Error: If the image is not the computation's size.
        """
        if len(initial) != self.size_x * self.size_y * 4:
            raise Error("A variable's image must be the computation's size")
        self.variables.append(ComputeVariable(name, fragment_shader, initial^))
        return len(self.variables) - 1

    def set_variable_dependencies(
        mut self, variable: Int, var dependencies: List[Int]
    ) raises:
        """Set which variables a variable's shader reads, three.js's
        `setVariableDependencies`.

        Args:
            variable: The variable.
            dependencies: The variables it reads, itself among them if it
                reads its own last image.

        Raises:
            Error: If a variable is not there.
        """
        self._check(variable)
        for at in range(len(dependencies)):
            self._check(dependencies[at])
        self.variables[variable].dependencies = dependencies^

    def _check(self, variable: Int) raises:
        """Refuse a variable that is not there."""
        if variable < 0 or variable >= len(self.variables):
            raise Error("A computation has no variable " + String(variable))

    def init(mut self) raises:
        """Compile each shader with its dependencies' samplers and the
        `resolution` define, three.js's `init`, and start at the first
        images.

        Raises:
            Error: If a shader is refused by the GLSL subset.
        """
        self.programs = List[NodeProgram]()
        var resolution = (
            "#define resolution vec2( "
            + String(Float32(self.size_x))
            + ", "
            + String(Float32(self.size_y))
            + " )\n"
        )
        for at in range(len(self.variables)):
            ref variable = self.variables[at]
            var shader = variable.fragment_shader
            for d in range(len(variable.dependencies)):
                shader = (
                    "\nuniform sampler2D "
                    + self.variables[variable.dependencies[d]].name
                    + ";\n"
                    + shader
                )
            var program = compile_shader_material(
                SCREEN_VERTEX_SHADER, resolution + shader
            )
            for d in range(len(variable.dependencies)):
                var slot = variable.dependencies[d]
                program.set_texture(self.variables[slot].name, TextureId(slot))
            self.programs.append(program^)
        self.current = 0

    def packed(self) -> Tuple[List[Float32], List[Int32]]:
        """Return every variable's current image one after another, and
        their wrap modes: what a step reads.

        Returns:
            The images, and two wrap modes a variable.
        """
        var images = List[Float32]()
        var wraps = List[Int32]()
        for at in range(len(self.variables)):
            images.extend(self.variables[at].images[self.current].copy())
            wraps.append(Int32(self.variables[at].wrap_s.value))
            wraps.append(Int32(self.variables[at].wrap_t.value))
        return (images^, wraps^)

    def compute(mut self) raises:
        """Step every variable once, three.js's `compute`.

        Raises:
            Error: If `init` has not compiled the shaders.
        """
        if len(self.programs) != len(self.variables):
            raise Error("A computation must be initialized before it runs")
        var packed = self.packed()
        var next = 1 - self.current
        for at in range(len(self.variables)):
            var step = step_image(
                self.programs[at].code,
                packed[0],
                packed[1],
                self.size_x,
                self.size_y,
                self.variables[at].images[next],
            )
            self.variables[at].images[next] = step^
        self.current = next

    def current_image(self, variable: Int) raises -> List[Float32]:
        """Return a variable's image now, three.js's
        `getCurrentRenderTarget( variable ).texture`.

        Args:
            variable: The variable.

        Returns:
            A copy of its four floats a texel.

        Raises:
            Error: If the variable is not there.
        """
        self._check(variable)
        return self.variables[variable].images[self.current].copy()

    def alternate_image(self, variable: Int) raises -> List[Float32]:
        """Return a variable's other image, three.js's
        `getAlternateRenderTarget`: its image before the last step.

        Args:
            variable: The variable.

        Returns:
            A copy of its four floats a texel.

        Raises:
            Error: If the variable is not there.
        """
        self._check(variable)
        return self.variables[variable].images[1 - self.current].copy()

    def current_texture(self, variable: Int) raises -> Texture:
        """Return a variable's image now as a float texture, read at its
        nearest texel, for a material to draw with.

        Args:
            variable: The variable.

        Returns:
            The texture, rows from the top as a texture holds them.

        Raises:
            Error: If the variable is not there.
        """
        var image = self.current_image(variable)
        var rows = List[Float32](capacity=len(image))
        for y in range(self.size_y - 1, -1, -1):  # pragma: no branch
            var start = y * self.size_x * 4
            rows.extend(image[start : start + self.size_x * 4])
        return float_texture(
            self.size_x,
            self.size_y,
            rows^,
            wrap=self.variables[variable].wrap_s,
            filter=NEAREST,
        )


def step_image(
    code: List[Float32],
    images: List[Float32],
    wraps: List[Int32],
    size_x: Int,
    size_y: Int,
    before: List[Float32],
) -> List[Float32]:
    """Return one variable's next image on the host: `compute_texel` at
    every texel, and a texel a shader throws away keeps `before`'s value.

    Args:
        code: The program's floats.
        images: Every variable's image before the step.
        wraps: Every variable's wrap modes.
        size_x: How many texels across.
        size_y: How many texels up.
        before: The image the step writes over.

    Returns:
        The image.
    """
    var out = before.copy()
    var code_at = (
        code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var images_at = (
        images.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    var wraps_at = (
        wraps.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )
    for y in range(size_y):  # pragma: no branch
        for x in range(size_x):  # pragma: no branch
            var source = ComputeNodes(
                code_at, images_at, wraps_at, size_x, size_y, x, y
            )
            var texel = compute_texel(
                source,
                (Float32(x) + 0.5) / Float32(size_x),
                (Float32(y) + 0.5) / Float32(size_y),
            )
            if not texel[1]:
                continue
            var at = (y * size_x + x) * 4
            for lane in range(4):  # pragma: no branch
                out[at + lane] = texel[0][lane]
    # The pointers do not keep their lists alive; this does.
    _ = code
    _ = images
    _ = wraps
    return out^
