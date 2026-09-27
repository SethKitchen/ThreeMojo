# Node materials

`materials/nodes.mojo` and `materials/glsl.mojo`. A node material replaces parts of a surface's shading with a small graph of nodes: three.js's node materials and its Three Shading Language (TSL). You build a `NodeGraph`, or you compile GLSL source to one. You compile the graph to a `NodeProgram`, add the program to `assets.programs`, and give its id to a `Material`.

![A node graph shifts a sphere from orange to blue and back](out/nodes.png)

`examples/graph.mojo` draws this picture.

three.js: `NodeMaterial` and its outputs, from `colorNode` to `depthNode`. TSL's `uniform`, `If`, `Loop`, `Fn`, `Discard`, `varying`, `dFdx`, `dFdy` and its math. MaterialX's noise. `ShaderMaterial` and `RawShaderMaterial` in a subset of GLSL.

## Build one

```mojo
var graph = NodeGraph()
var tint = graph.uniform("tint", Color(255, 120, 40))
var wave = graph.sin(graph.mul(graph.time(), graph.float(2)))
var mixed = graph.mix(graph.vertex_color(), tint, graph.mul(wave, graph.float(0.5)))
graph.set_output(COLOR_NODE, mixed)
graph.set_output(OUTPUT_NODE, graph.mul(graph.lit(), graph.vec3(1, 0.9, 0.8)))
var program = assets.programs.add(graph.compile())
var paint = assets.materials.add(
    Material(Color(255, 255, 255), kind=STANDARD, roughness=0.4, nodes=program)
)
```

Every node method returns a `NodeRef`. Give the refs to the next node. `set_output` connects a node to one output. `compile` refuses a graph it cannot run, and returns the program.

Change a uniform between frames, as three.js changes `uniform.value`:

```mojo
assets.programs.get(program).set_uniform("tint", Color(40, 120, 255))
renderer.time = Duration(1.5, SECOND)
```

`Renderer.time` is the value of the `time` node, three.js's `NodeFrame.time`. It is zero by default. The caller moves it on between frames.

## Write it in GLSL

`compile_shader_material(vertex, fragment)` compiles a `ShaderMaterial`'s two shaders to one program. Give the program's id to `shader_material`.

```mojo
var program = compile_shader_material(
    """
    uniform float lift;
    varying vec2 vUv;
    void main() {
        vUv = uv;
        vec3 moved = position + normal * lift;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(moved, 1.0);
    }
    """,
    """
    uniform sampler2D map;
    varying vec2 vUv;
    void main() {
        if (vUv.x > 0.9) discard;
        gl_FragColor = texture2D(map, vUv * 2.0);
    }
    """,
)
program.set_uniform("lift", Float32(0.1))
program.set_texture("map", texture)
var card = assets.materials.add(shader_material(assets.programs.add(program^)))
```

Pass three.js's `material.defines` as `defines`, a list of `NAME` or `NAME value`. Each is a `#define` in both shaders before their first line, so an error still names the author's line.

The compiler lexes, parses and type checks the source, and builds the graph as it parses. `shader_graph(vertex, fragment)` returns the graph before it is compiled. `compile_raw_shader_material` reads the shaders as three.js's `RawShaderMaterial` does. See [GLSL source](#glsl-source) for the subset.

### Draw a ShaderToy shader

`compile_shader_toy(source)` compiles a ShaderToy shader, as three.js's `ShaderToyDecoder` does. Its `mainImage` colors each pixel of the surface.

```mojo
var toy = compile_shader_toy(
    """
    void mainImage(out vec4 fragColor, in vec2 fragCoord) {
        vec2 uv = fragCoord / iResolution.xy;
        vec3 col = 0.5 + 0.5 * cos(iTime + uv.xyx + vec3(0, 2, 4));
        fragColor = vec4(col, 1.0);
    }
    """
)
toy.set_uniform("iResolution", Vector3(800, 600, 1))
var screen = assets.materials.add(shader_material(assets.programs.add(toy^)))
```

`fragCoord` is the pixel's center, in pixels from the bottom left. `iTime` is `Renderer.time`. Set the other inputs yourself: `iResolution`, `iTimeDelta`, `iFrameRate`, `iFrame`, `iMouse`, `iDate`, `iSampleRate`, `iChannelResolution[i]` and `iChannelTime[i]` with `set_uniform`. Set `iChannel0` to `iChannel3` with `set_texture`. The source must fit the [subset](#the-subset), and an error names the line of the source.

## Outputs

A graph sets one to thirteen outputs. Each output replaces one part of the material's own shading. The material keeps every part that the graph does not set.

| Output | Type | three.js | What it replaces |
|---|---|---|---|
| `COLOR_NODE` | `vec3` | `colorNode` | The diffuse color: the material's color, its vertex colors and its map. The lights multiply it. |
| `OPACITY_NODE` | `float` | `opacityNode` | The alpha: the opacity, the map's alpha and the alpha map. The alpha test reads it. |
| `EMISSIVE_NODE` | `vec3` | `emissiveNode` | The light the surface gives off: the emissive color and the emissive map. |
| `NORMAL_NODE` | `vec3` | `normalNode` | Nothing. It is an offset added to the world-space normal before the lights read it. |
| `POSITION_NODE` | `vec3` | `positionNode` | Nothing. It is an offset added to each vertex's local position. |
| `OUTPUT_NODE` | `vec3` | `outputNode` | The finished color, after the lights, the reflection and the fog. The `lit` node reads that color. |
| `MASK_NODE` | `float` | `maskNode` | Nothing. A fragment where it is zero is thrown away, before the alpha test. |
| `AO_NODE` | `float` | `aoNode` | The ambient occlusion map's value. It dims the indirect light. |
| `DEPTH_NODE` | `float` | `depthNode` | The fragment's depth: zero at the near plane, one at the far plane. The depth test reads it. |
| `BACKDROP_NODE` | `vec3` | `backdropNode` | The diffuse light, mixed by `BACKDROP_ALPHA_NODE` where that is set. The specular light and the glow are added after it. See [The scene behind](#the-scene-behind). |
| `BACKDROP_ALPHA_NODE` | `float` | `backdropAlphaNode` | Nothing. It is how much of the backdrop replaces the diffuse light, zero to one. |
| `FRAGMENT_NODE` | `vec4` | `fragmentNode` | All of the material's shading: the color and the alpha. The fog veils it. The alpha test, the alpha hash and the output node do not run. |
| `SIZE_NODE` | `float` | `sizeNode` | A point's width in pixels: the material's size and its attenuation. Only a point reads it. See [Points and lines](#points-and-lines). |

The alpha of the finished color stays what the fragment had. An output node changes only its color.

## Nodes

A `float` next to a vector is repeated into every component, as in GLSL. A condition is a `float`: zero is false and every other value is true. `set_input(node, slot, source)` rewires one input of a node, as a node editor does.

### Values and attributes

| Method | Type | three.js | Value |
|---|---|---|---|
| `float(x)`, `vec2`, `vec3`, `vec4` | as named | `float()`, `vec2()` and the rest | A constant. |
| `color(Color)` | `vec3` | `color()` | A constant color, decoded from sRGB to linear. |
| `uniform(name, value)` | as the value | `uniform()` | A named value the caller can change between frames. The value is a `Float32`, a `Vector2`, a `Vector3`, a `Vector4`, a `Color`, a `Matrix3` or a `Matrix4`. |
| `texture_uniform(name, map)` | `texture` | `texture(map)` | A named texture the caller can change with `set_texture`. |
| `uv()` | `vec2` | `uv()` | The coordinate the material's `map` is read at, through its transform. |
| `position_world()` | `vec3` | `positionWorld` | The fragment's position in world space, in meters. |
| `position_view()` | `vec3` | `positionView` | The fragment's position in the camera's space. The camera looks down minus z. |
| `normal_world()` | `vec3` | `normalWorld` | The fragment's unit normal in world space, after any normal or bump map. |
| `normal_view()` | `vec3` | `normalView` | The fragment's unit normal in the camera's space. |
| `vertex_color()` | `vec3` | `materialColor` times `vertexColor()` | The interpolated corner color: the material's color times the vertex colors. |
| `position_local()` | `vec3` | `positionLocal` | The vertex's position in the model's space. A position node only. |
| `normal_local()` | `vec3` | `normalLocal` | The vertex's normal in the model's space. Zero if the geometry has no normals. A position node only. |
| `camera_position()` | `vec3` | `cameraPosition` | The camera's position in world space, from the frame's view. |
| `camera_view_matrix()` | `mat4` | `cameraViewMatrix` | The frame's world-to-camera matrix. |
| `time()` | `float` | `time` | `Renderer.time`, in seconds. |
| `attribute(name, type)` | as named | `attribute(name)` | A custom attribute of the geometry, a `float` or a vector, interpolated at the fragment. See [Custom attributes](#custom-attributes). |
| `front_facing()` | `float` | `frontFacing` | One where the triangle is seen from its front, and zero where it is seen from its back. A fragment only. |
| `face_direction()` | `float` | `faceDirection` | One where the triangle is seen from its front, and minus one where it is seen from its back. A fragment only. |
| `gl_front_facing()` | `float` | GLSL's `gl_FrontFacing` | As `front_facing()`, but one on every face that a `BACK_SIDE` material draws. See [Facing](#facing). A fragment only. |
| `frag_coord()` | `vec4` | GLSL's `gl_FragCoord` | The pixel's center in pixels from the bottom left, the depth from zero to one, and one. A fragment only. |
| `screen_uv()` | `vec2` | `screenUV` | Where the pixel is on the target: zero to one across from the left edge and up from the bottom edge, at the pixel's center. A fragment only. |
| `viewport_texture(uv)` | `vec4` | `viewportSharedTexture(uv)` | The opaque scene behind the surface at a place on the target, linear, with straight alpha. See [The scene behind](#the-scene-behind). A fragment only. |
| `point_coord()` | `vec2` | GLSL's `gl_PointCoord` | Where the pixel is in its point: zero to one across from the left edge and down from the top edge. Zeros on a triangle and a line. A fragment only. |
| `texture(map, uv)` | `vec4` | `texture(map, uv)` | A texture read at a `vec2` coordinate, linear, with straight alpha. `map` is a `TextureId` or a texture uniform. |
| `cube_uniform(name, map)` | `cubeTexture` | `cubeTexture(map)` | A named cube texture the caller can change with `set_cube`. |
| `texture_cube(sampler, direction)` | `vec4` | `cubeTexture(map, dir)` | A cube texture read in a `vec3` direction of any length, linear, with straight alpha. The face the direction points at is read where it points. |
| `volume_uniform(name, map)` | `texture3D` | `texture3D(map)` | A named 3D texture from `Assets.data_3d_textures`. The caller can change it with `set_volume`. |
| `texture_3d(sampler, at)` | `vec4` | `texture3D(map, uvw)` | A 3D texture read at a `vec3` from zero to one on each axis, linear, with straight alpha. The texture's own wrap modes and filter apply. |
| `array_uniform(name, map)` | `textureArray` | GLSL's `sampler2DArray` | A named array texture from `Assets.data_array_textures`. The caller can change it with `set_array`. |
| `texture_array(sampler, at)` | `vec4` | GLSL's `texture` of a `sampler2DArray` | An array texture read at a `vec3` of `u`, `v` and the layer. The layer is rounded to the nearest and held inside the stack. Two layers are never blended. |
| `texture_level(map, uv, level)` | `vec4` | `texture(map, uv).level(n)` | As `texture`, at the mip level that a `float` gives. Level zero is the full-size image. A texture with one level reads it at every level. |
| `texture_load(map, at, level)` | `vec4` | `textureLoad(map, at, level)` | The texel of a texture uniform at a column and a row, counted as `uv` counts. A coordinate outside the image wraps, and a level outside the chain is held inside it. |
| `texture_size(map, level)` | `vec2` | `textureSize(map, level)` | A texture uniform's width and height at a level, held inside the chain. |
| `lit()` | `vec3` | `output` | The color that the material's own shading made. An output node only. |

### Math

| Method | Type | three.js |
|---|---|---|
| `add`, `sub`, `mul`, `div` | the wider operand | same names |
| `min`, `max`, `mod`, `pow`, `step`, `atan2(y, x)` | the wider operand | same names; `atan(y, x)` |
| `mix(a, b, t)`, `clamp(x, low, high)`, `smoothstep(low, high, x)` | the widest operand | same names |
| `abs`, `sign`, `floor`, `ceil`, `round`, `trunc`, `fract` | the operand | same names |
| `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `radians`, `degrees` | the operand | same names |
| `exp`, `exp2`, `log`, `log2`, `sqrt`, `inverse_sqrt`, `reciprocal` | the operand | `inverseSqrt` for the sixth |
| `negate`, `one_minus`, `saturate` | the operand | `negate`, `oneMinus`, `saturate` |
| `dot(a, b)`, `distance(a, b)`, `length(a)` | `float` | same names |
| `normalize(a)`, `reflect(i, n)`, `refract(i, n, eta)`, `faceforward(n, i, nref)` | the operand | `faceForward` for the last |
| `cross(a, b)` | `vec3` | `cross` |
| `remap(x, in_low, in_high, out_low, out_high)` | the widest operand | `remap` |
| `swizzle(a, "zyx")` | as long as the string | `a.zyx` |
| `join([a, b])` | the sum of the widths | `vec3(a, b)` of nodes |
| `integer(a)`, `unsigned(a)` | the operand | `int`, `uint` |
| `bit_and`, `bit_or`, `bit_xor`, `shift_left`, `shift_right` | the wider operand | `bitAnd`, `bitOr`, `bitXor`, `shiftLeft`, `shiftRight` |
| `bit_not(a)` | the operand | `bitNot` |

A value here is a float, and TSL's `int` and `uint` are floats that hold whole numbers. `integer` truncates toward zero. `unsigned` also wraps a negative number up by 2 ** 32.

A bit operation truncates each component to a 32-bit integer, operates on it, and holds the result as a float again. A shift reads the low five bits of its count, as a GPU does. NaN is zero, and a number past 32 bits is held at the end of the range. A float holds a whole number exactly up to 2 ** 24.

`round` takes a half to the even whole number. `normalize` leaves a zero vector at zero, where GLSL leaves it undefined. A division by zero gives what IEEE 754 gives, as a GPU does. `mul` of a `mat3` or a `mat4` and a vector of its width multiplies the matrix and the vector, on either side.

### Matrices

| Method | Type | three.js |
|---|---|---|
| `mat3(c0, c1, c2)`, `mat4(c0, c1, c2, c3)` | `mat3`, `mat4` | same names, of column nodes |
| `column(m, i)` | `vec3` or `vec4` | `m[i]` in GLSL |
| `transpose(m)`, `inverse(m)` | the operand | same names |
| `determinant(m)` | `float` | `determinant` |

`mul` also multiplies two matrices of one size. A register holds four floats, so a matrix is not a value an instruction writes. A matrix that the graph builds is a list of its columns, and `mul` expands it into vector operations. A uniform's columns are the uniform times each unit vector. `inverse` makes each row at right angles to every column but one, and scales it so that its dot with that one is one. A singular matrix gives what the divisions by zero give.

### Comparisons, logic and selection

| Method | three.js |
|---|---|
| `less_than`, `less_than_equal`, `greater_than`, `greater_than_equal`, `equal`, `not_equal` | `lessThan` and the rest |
| `logical_and`, `logical_or`, `logical_xor`, `logical_not` | `and`, `or`, `xor`, `not` |
| `select(condition, a, b)` | `select` |

Each gives one or zero per component. `select` gives `a` where the condition is not zero and `b` where it is.

### Noise

| Method | three.js |
|---|---|
| `perlin_noise(p)` | `mx_perlin_noise_float` |
| `mx_noise_float(texcoord, amplitude, pivot)` | `mx_noise_float` |
| `mx_fractal_noise_float(position, octaves, lacunarity, diminish, amplitude)` | `mx_fractal_noise_float` |
| `perlin_noise_vec3(p)` | `mx_perlin_noise_vec3` |
| `mx_noise_vec3(texcoord, amplitude, pivot)`, `mx_noise_vec4(texcoord, amplitude, pivot)` | `mx_noise_vec3`, `mx_noise_vec4` |
| `cell_noise_float(p)`, `cell_noise_vec3(p)` | `mx_cell_noise_float`, `mx_cell_noise_vec3` |
| `worley_noise(p, jitter, width)` | `mx_worley_noise_float`, `_vec2` and `_vec3` for a `width` of 1, 2 and 3 |

The noise is MaterialX's gradient noise, with the same hash and the same order of operations as three.js. The point is a `vec2` or a `vec3`. The fractal noise adds a zero to a `vec2`, as three.js converts it.

- `perlin_noise_vec3` grades each component by one byte of each corner's hash. `mx_noise_vec4` adds the Perlin noise of one component at the point moved by (19, 73). A `vec3` point moves by (19, 73, 0).
- Cell noise gives one value from zero to one for each cell of whole numbers. The point is a `float` to a `vec4`.
- Worley noise gives the squared distances to the nearest points that jitter each cell, nearest first. `MaterialXNodes` always asks for this metric, so the others are not ported.

`assets/noise/mx_noise.py` transcribes three.js's functions in 32-bit floats and gives the values the tests check.

## Control flow

`If`, `ElseIf`, `Else`, `Loop`, `End`, `Break`, `Continue`, `Return`, `Var` and `Discard` are TSL's statements. The builder records them in the order you call them.

```mojo
var sum = graph.Var(graph.float(0))
var index = graph.Loop(4)
graph.If(graph.greater_than(index, graph.float(1)))
graph.assign(sum, graph.add(graph.get(sum), index))
graph.Else()
graph.Discard()
graph.End()
graph.End()
graph.set_output(OPACITY_NODE, graph.get(sum))
```

- `Var(value)` makes a variable. `assign(v, value)` changes it, and `get(v)` reads what it holds at that point.
- `If(condition)` opens a branch. `ElseIf` and `Else` follow, and one `End` closes the chain.
- `Loop(count, start, step)` runs its body `count` times and returns the index, a `float`. `End` closes it.
- `Discard()` throws the fragment away where the open branches run. Every discard joins the mask.
- `Fn(name, inputs, output, body)` is TSL's `Fn` with its `setLayout`. `graph.call(fn, args)` checks the arguments and the answer against the layout, and inlines the body.
- `Break()` leaves the innermost loop where the open branches run. `Continue()` skips the rest of this time through it.
- `Return(value)` gives the answer of the `Fn` that is being built, where the open branches run. The loops that it is in stop.

```mojo
def first_square_over(mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    var i = graph.Loop(8)
    graph.If(graph.greater_than(graph.mul(i, i), args[0]))
    graph.Return(i)
    graph.End()
    graph.End()
    return graph.float(-1)
```

The bytecode has no jumps. An `If` computes both branches, and each variable that a branch changes becomes a `select` of the two values. `End` unrolls a loop: it copies the body once for each run after the first. So every output stays a graph with no cycle.

`Break`, `Continue` and `Return` are flags, not jumps. Each loop holds two hidden variables: `live`, which a `Break` clears, and `skip`, which a `Continue` sets until the next time through. A `Fn` call holds `returned` and its answer. After one of these statements, each assignment and each discard takes effect only where the flags allow it. At its `End`, a loop keeps each variable as it was where a time through starts after a `Break`.

## Varyings and derivatives

`varying(a)` computes `a` at each corner of the triangle and interpolates the three values with the fragment's perspective-correct weights. A varying of a node that is not linear across the triangle differs from the node itself. The value can read the world and view position and normal, the coordinates, the vertex color, the time, uniforms and math of them.

`dfdx(a)` and `dfdy(a)` are exact per triangle. The compiler lays out `a` again for the pixel to the right, or the pixel above, with the attributes that the triangle's plane gives there. The derivative is the value there less the value here. A hardware quad takes the difference inside a two by two block instead. `fwidth(a)` is `abs(dfdx(a)) + abs(dfdy(a))`.

A derivative reads the fragment's interpolated normal, before any normal map, bump map or normal node. `dfdy` looks up, as GLSL's window rows count upward.

## GLSL source

The GLSL compiler takes a subset of GLSL ES 3.0. It refuses everything outside the subset with the shader, the line and the reason.

### ShaderMaterial and RawShaderMaterial

`compile_shader_material` declares what three.js's prefix declares:

- the uniforms `modelMatrix`, `modelViewMatrix`, `projectionMatrix`, `viewMatrix`, `normalMatrix` and `cameraPosition`;
- the attributes `position`, `normal`, `uv` and `color`;
- both spellings: `attribute`, `varying`, `texture2D` and `gl_FragColor`, and `in`, `out`, `texture` and `pc_fragColor`.

`compile_raw_shader_material` declares nothing. Each shader declares the built-ins it reads, with three.js's names and types. A raw shader is GLSL ES 1.0 unless its first line is `#version 300 es`.

### The vertex shader

The host places each vertex, so the vertex shader must write `gl_Position` as three.js's own shaders do:

- `gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);`, or
- the same through `projectionMatrix * viewMatrix * modelMatrix`, through a local variable, or through a function.

It writes `gl_Position` once, in `main`, outside every branch and loop. The point `p` becomes the position node, an offset from `position`. `p` reads `position`, `normal`, uniforms, constants and math of them.

A varying that the vertex shader writes becomes a `varying` node. A corner keeps the world position and normal, the coordinates and the color. So a varying reads these forms:

| GLSL | Node |
|---|---|
| `uv`, `color` | `uv()`, `vertex_color()` |
| `(modelMatrix * vec4(position, 1.0)).xyz` | `position_world()` |
| `(modelViewMatrix * vec4(position, 1.0)).xyz` | `position_view()` |
| `normalMatrix * normal` | `normal_view()`, made unit length |
| `modelMatrix * vec4(normal, 0.0)` | `normal_world()` with a zero `w` |
| `mat3(modelMatrix) * normal`, and the same through `mat3(modelMatrix[0].xyz, modelMatrix[1].xyz, modelMatrix[2].xyz)` | `normal_world()` |
| `viewMatrix * v`, `cameraPosition` | `camera_view_matrix()`, `camera_position()` |

The world and view positions are of the point that `gl_Position` draws.

### The fragment shader

`gl_FragColor`, `pc_fragColor` or the one `out vec4` is the color and the opacity. `gl_FragDepth` is the depth node. `discard` throws the fragment away. `gl_FragCoord` is where the fragment is: the pixel's center in pixels from the bottom left, its depth from zero to one, and one for `w`. three.js's `w` is one over the clip-space `w`.

`gl_FrontFacing` is `gl_front_facing()`. It is true on every face that a `BACK_SIDE` material draws. See [Facing](#facing).

`gl_PointCoord` is `point_coord()`, where the pixel is in its point. `gl_PointSize` in the vertex shader is the size node. It can read the world and view position, the coordinates, the color and the custom attributes. It cannot read `position` or `normal`. See [Points and lines](#points-and-lines).

### Facing

TSL's `frontFacing` and GLSL's `gl_FrontFacing` differ for a `BACK_SIDE` material. three.js's WebGL renderer turns the front face round for such a material, so `gl_FrontFacing` is true on the faces that it draws. TSL's `frontFacing` is false on those faces, because they are seen from their back. For `FRONT_SIDE` and `DOUBLE_SIDE`, the two agree. A mirrored mesh keeps the same rule, as [Side](Materials#side) states.

### The subset

- Types: `void`, `bool`, `int`, `float`, `vec2` to `vec4`, `ivec2` to `ivec4`, `bvec2` to `bvec4`, `mat2`, `mat3` and `mat4`. Uniforms can also be `sampler2D`, `samplerCube`, `sampler3D` and `sampler2DArray`. `sampler3D` and `sampler2DArray` are GLSL ES 3.0 only.
- Uniforms: every type above but `void`. An `int`, a `bool` or a vector of them is a uniform of floats that you set. An `int` drops the fraction toward zero, and a `bool` is true where it is not zero. Set a `mat2` uniform with a `Vector4` of its two columns.
- Declarations: `uniform`, `attribute`, `varying`, `in`, `out`, `const` globals with constant values, `precision` statements, and `layout(...)` on an output.
- Attributes: `position`, `normal`, `uv` and `color`, and custom attributes of a `float` or a vector. See [Custom attributes](#custom-attributes).
- Functions: functions with `in`, `out` and `inout` parameters. A call inlines the body. A `return` can come before the end of its function. An `out` or `inout` argument must be a variable, and it gets the parameter's value when the call ends.
- Statements: local variables, `if` and `else`, `switch`, blocks, `discard`, `break`, `continue`, assignments, `+=`, `-=`, `*=`, `/=`, `++` and `--`.
- Loops: `for (int i = a; i < b; i++)` with constant `a`, `b` and step. The condition is `<`, `<=`, `>`, `>=` or `!=`. The step is `++`, `--`, `+=` or `-=`. A loop runs at most 1024 times.
- `while (c)` and `do { ... } while (c);`. The body of a `do` is a block in braces. See [While and do](#while-and-do).
- Expressions: the arithmetic, comparison and logical operators, `?:`, swizzles of `xyzw`, `rgba` and `stpq`, indexes, and constructors of scalars, vectors and matrices.
- Structs: `struct S { ... };` at the top of a shader, of the types above but samplers and of other structs. A struct can be a local variable, a `const`, a uniform, an array element, a parameter and a result. `S(...)` takes one value for each field. A uniform struct's fields are uniforms named `s.a`, as three.js names them.
- Arrays: local, `const` and uniform arrays of one dimension, of at most 256 elements. An initializer is `T[n](...)` or `T[](...)`. `a.length()` is the size. A uniform array's elements are uniforms named `a[0]`, `a[1]` and on, as three.js names them.
- Matrices: a matrix times a vector or a matrix of its size, a column `m[i]`, `transpose`, `determinant` and `inverse`. A `mat2` also takes `+`, `-`, `*` and `/` of each component with a `mat2` or a `float`.
- Built-ins of one value: `radians`, `degrees`, the trigonometry, `exp`, `log`, `exp2`, `log2`, `sqrt`, `inversesqrt`, `abs`, `sign`, `floor`, `ceil`, `trunc`, `round`, `roundEven` and `fract`.
- Built-ins of more values: `pow`, `mod`, `min`, `max`, `clamp`, `mix`, `step`, `smoothstep`, `length`, `distance`, `dot`, `cross` and `normalize`.
- Built-ins of comparison: `lessThan`, `lessThanEqual`, `greaterThan`, `greaterThanEqual`, `equal` and `notEqual` give a `bvec`. `any`, `all` and `not` take a `bvec`. `mix` takes a `bool` or a `bvec` to choose by.
- Built-ins of light and surfaces: `faceforward`, `reflect`, `refract`, `dFdx`, `dFdy`, `fwidth`, `texture`, `texture2D`, `textureProj`, `texture2DProj`, `textureLod`, `texelFetch`, `textureSize` and `textureCube`. `texture` of a `samplerCube` reads it in a direction, as `textureCube` does. `texture` of a `sampler3D` or a `sampler2DArray` reads it at a `vec3`.
- The preprocessor: `#version` in a raw shader, object-like `#define`, `#undef`, and `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else` and `#endif`.
- An `#if` condition: whole numbers, macros that are one whole number, `defined`, `!`, `&&`, `||`, the six comparisons and parentheses. A name that is not a macro is zero, as in the C preprocessor.

A local `mat3` or `mat4` gets its value where you declare it, and keeps that value. A register holds four floats, so such a local is a name for the matrix that its initializer builds. A `mat2` is a `vec4` of its two columns, so it is a variable like a vector. `break` must be in a loop or a `switch` of the same function, and `continue` in a loop.

An index can be a loop's index or another value that is not constant. A chain of selects then picks the element, the component or the column. An index outside the array reads the first element and writes no element. GLSL leaves both undefined. You can write an array's element through such an index, but not a vector's component.

An `int` is a whole number that a float holds, and a `bool` is one or zero. An `int` division drops the fraction toward zero. A constructor of `ivec` drops each fraction, and a constructor of `bvec` is true where a number is not zero. GLSL ES has no conversion between `int` and `float`, and this compiler has none either. Write `float(i)`.

### While and do

A `while` or a `do` loop runs at most `MAX_WHILE_COUNT` times, 64. A loop that would run longer stops there, and the shader must not depend on more. The bytecode has no jumps, so the compiler unrolls such a loop 64 times. A false condition leaves it, as a `break` does.

- A `while` asks its condition at the top of each time through.
- A `do` runs its body once. It asks its condition at the top of each later time, so a `continue` in it still reaches the condition.
- A `while` inside another `while` unrolls 64 times 64. That is past the limit of a graph, so write the inner loop as a `for` with a constant count.

### What the GLSL compiler refuses

- A `#include`, `#pragma`, `#extension`, `#error`, `#line`, and a `#define` with arguments. A `#version` in a `ShaderMaterial`, as three.js writes its own.
- `onBeforeCompile` and shader chunks: see [Why no chunks](#why-no-chunks).
- The types `uint` and `uvec`, the non-square matrices, and the samplers other than `sampler2D`, `samplerCube`, `sampler3D` and `sampler2DArray`.
- Arrays of arrays, arrays of `mat3` or `mat4`, arrays as varyings, attributes, parameters or fields, and an array read whole.
- A struct declared in a function or with its variables, a struct as a varying, and a sampler in a struct.
- A struct's field written through an index that is not constant.
- Global variables that are not `const`, and the qualifiers `flat`, `centroid` and `invariant`.
- A custom attribute of `int`, `bool` or a matrix, and custom attributes of more than 8 floats in all.
- `position`, `normal`, `uv` or `color` declared in a `ShaderMaterial`: three.js declares them.
- Recursion. A call inlines its function, so a function that calls itself has no end.
- A `do` whose body is not a block in braces.
- A `switch` of a value that is not an `int`, and a `case` label that is not a constant.
- A declaration directly in a `switch`, outside a block.
- A `return` before the end of a function that returns a matrix, a struct or a transform, or of a vertex shader's `main`.
- Prototypes, overloads, and functions named like GLSL's own.
- The bit operators, `%` of floats, `%=`, and an assignment or `++` inside an expression.
- A for loop that does not declare its index, reads a bound that is not constant, or runs more than 1024 times.
- A matrix times a matrix of another size, and an assignment to a local matrix.
- A sampler in a local variable, and a sampler array's index that is not a constant.
- `modelMatrix`, `modelViewMatrix`, `projectionMatrix` and `normalMatrix` in any form but the ones above, and in a fragment shader.
- A column of one of these or of `viewMatrix`, and a matrix constructor that reads one, but for the forms of `mat3(modelMatrix)` above.
- A `gl_Position` in any other form, written twice, in a branch or in a function.
- A varying that reads `position` or `normal`, and a texture read in a vertex shader.
- Every `gl_` variable but `gl_Position`, `gl_PointSize`, `gl_FragCoord`, `gl_FrontFacing`, `gl_PointCoord`, the color outputs and `gl_FragDepth`. `gl_FrontFacing` and `gl_PointCoord` in a vertex shader, and `gl_PointSize` in a fragment shader.
- A `gl_PointSize` that reads `position` or `normal`. A point keeps its world and view position, not its local one.
- The built-ins outside the list above, for example `sinh`, `isnan`, `outerProduct`, `textureGrad` and `textureOffset`.
- A vector compared with `<`, and a scalar swizzled.

### Custom attributes

A custom attribute is a geometry attribute that a program reads by its name. A graph declares one with `attribute(name, type)`, and a vertex shader with `attribute` or `in`. Each corner carries 8 floats for the custom attributes, so all of them together can hold at most 8 floats.

The renderer reads each attribute from the geometry for each vertex. A missing component is zero, and a missing fourth component is one. A geometry without the attribute gives zeros and one. WebGL fills a missing attribute in the same way.

A custom attribute is carried through a cut at the near plane, as the other attributes are. A position node cannot read one: the host moves each vertex before the corners are made.

### Why no chunks

`onBeforeCompile` edits the GLSL of three.js's built-in materials, chunk by chunk. This port's materials are Mojo code, not GLSL chunks. So there is no source for a callback to edit. Write the change as a node graph on the material instead: the outputs replace the parts that the chunks compute.

## What a graph refuses

The graph refuses a type error when you build the node:

- two vectors of different sizes in one operation, for example a `vec3` added to a `vec2`;
- a matrix or a texture in an operation other than `mul` and `texture`;
- a texture read at a coordinate that is not a `vec2`, or with `NO_TEXTURE`;
- a swizzle of a component that the value does not have;
- a join of more than four components;
- an output given a node of the wrong type;
- a uniform with no name, or with the name of another uniform;
- a `NodeRef` or a `NodeVar` that names nothing in this graph;
- an `If` whose condition is not a `float`, an `Else` or an `End` with no block, and a `Loop` count outside zero to 1024;
- a `Fn` call whose arguments or answer are not its layout's;
- a rewire that changes an input's type or makes a cycle.

`compile` refuses these:

- a graph with no output and no discard, and a graph with a block that `End` never closed;
- a cycle, or an input that names no node, in a graph whose fields were edited;
- a position node that reads a fragment's attribute, a texture, a varying, a derivative or the lit color;
- a fragment output that reads the local position or the local normal;
- a `lit` node in an output other than `OUTPUT_NODE`;
- a varying that reads a texture, a derivative or the lit color, and a derivative of a derivative;
- an output of more than `MAX_INSTRUCTIONS` (4096) instructions, or that needs more than `MAX_REGISTERS` (32) values at once.

A loop that would grow the graph past `MAX_GRAPH_NODES` (65536) nodes is refused at its `End`. `NodeProgram.set_uniform` refuses a name that no uniform has, and a value of the wrong type. `set_texture` refuses `NO_TEXTURE`.

## Shader material

`shader_material(program)` is three.js's `ShaderMaterial` as this port has it. The program is a node graph, compiled from GLSL or built by hand. Its `COLOR_NODE` is `gl_FragColor.rgb`, and its `OPACITY_NODE` is the alpha. Its uniforms are three.js's `uniforms`. The material is `BASIC`, so no light reaches it. Its `fog` is off, as three.js's is.

```mojo
var graph = NodeGraph()
var stripes = graph.step(graph.float(0.5), graph.fract(graph.mul(graph.uv(), graph.float(8))))
graph.set_output(COLOR_NODE, graph.swizzle(stripes, "xyx"))
var card = assets.materials.add(shader_material(assets.programs.add(graph.compile())))
```

## Materials from three.js's examples

Two of the materials in three.js's `examples/jsm/materials` come as node programs on a `PHYSICAL` material.

### Wood

`materials.wood` is three.js's `WoodNodeMaterial`: procedural wood, from rings of warped distance around the trunk, noise and a smooth Voronoi of cells.

```mojo
var params = wood_preset(WALNUT, GLOSS)
var plank = assets.materials.add(wood_material(assets.programs.add(wood_program(params)), params))
```

- `wood_preset(genus, finish)` is three.js's `GetWoodPreset`. The ten genuses are `TEAK`, `WALNUT`, `WHITE_OAK`, `PINE`, `POPLAR`, `MAPLE`, `RED_OAK`, `CHERRY`, `CEDAR` and `MAHOGANY`. The finishes are `RAW`, `MATTE`, `SEMIGLOSS` and `GLOSS`, each a clear coat.
- `wood_program(params)` is the color node. Its uniforms have three.js's names, from `centerSize` to `transformationMatrix`. Change them with `set_uniform`.
- `wood_material(id, params)` is the physical material with the finish's clear coat.

A fragment here has no local position, so the program reads the world position through `transformationMatrix`. For a mesh at the origin, the two are the same. Otherwise, set `transformationMatrix` to the inverse of the mesh's world matrix. three.js darkens the color by the darkening of the preset that it loads first, which is one. This port does the same.

### Ambient occlusion from a pass

`materials.post_processing_material` is three.js's `MeshPostProcessingMaterial`: the ambient occlusion of a physical surface, read from a post-processing pass's target at the fragment's own pixel.

```mojo
var occlusion = assets.programs.add(mesh_post_processing_program(gtao_target))
var wall = assets.materials.add(Material(Color(200, 200, 200), kind=PHYSICAL, nodes=occlusion))
```

The program reads the target's texel at `gl_FragCoord.xy * aoPassMapScale`. With an ambient occlusion map, it takes the lower of the two values and applies `aoMapIntensity`, as three.js does. The result is the `AO_NODE`, so the physical shading dims the indirect light with it.

## In a file

`object_to_json` writes a node material's program in the material's `nodes` field, and `read_object_json` reads it back into `assets.programs`. three.js's loaders read the other fields of the material and ignore this one.

three.js writes each node of the graph with its type and its inputs. This port writes the compiled program instead: its floats, its uniforms and its custom attributes. It also writes where the program keeps the id of each texture and cube that it reads. Each texture and cube goes to the file's `textures` or `images` list, and the program names it by its uuid. So the loader gives the program the ids that the textures get in its own store. A texture uniform that names no texture is written as `null`.

The writer refuses a program that reads a 3D or an array texture, because object JSON has no form for those textures.

## How it runs

`compile` lays out each output as a list of instructions. A node is one instruction in each context it runs in. The contexts are the fragment, the pixel beside it for a derivative, and a corner for a varying. Each instruction writes one of `MAX_REGISTERS` registers of four floats. The compiler gives a register back when the last reader of its value has run.

The compiler lays out each node's inputs in their order. When that needs more than `MAX_REGISTERS` registers, it tries the input that needs the most registers first, and then the oldest input first. A chain of selects, as `Break` and `Return` make, can need either.

The uniforms, and the constants that an instruction reads, follow the instructions, each stored once. A header holds where each output starts, the frame's time and the camera's view matrix. `Renderer.prepare_frame` copies `assets.programs` and writes the time and the view into the copy.

Both rasterizers run the program with one function, `run_nodes`. The CPU reads the program from its list. The GPU kernel reads it from the fog buffer, after the fog's six floats, because the kernel has no free argument. A triangle's state column `STATE_NODES` tells the kernel where its program starts. Each backend gives the corners' attributes, and the weights at a pixel from the triangle's edge functions.

The parity tests in `tests/test_gpu.mojo` hold the two backends to the same pixels. See [GPU backend](GPU-backend).

A fragment runs the outputs in this order:

1. The depth node, from the fragment's own interpolated attributes, before the depth and stencil tests.
2. The normal node, after any normal or bump map. The sum is made unit length again.
3. The lights, with the bent normal, and the ambient occlusion node where the indirect light is dimmed.
4. The color, the opacity and the emissive nodes, after the maps. The color is multiplied by the arriving light.
5. The mask, then the alpha test, the lights' sums, the reflection and the fog.
6. The output node.

A fragment that the mask can throw away claims no depth until it survives, as a GPU does for a shader that can discard. The position node runs on the host, once per vertex, after the morph targets, the bones and the displacement map. So both rasterizers draw the same moved triangles, and the shadow pass casts them. A mesh with a position node is not culled by the bound of its geometry.

### The scene behind

`viewport_texture(screen_uv())` reads the opaque scene behind the fragment, as three.js's `viewportSharedTexture()` does. A backdrop node usually reads it, to filter what is behind a surface:

```mojo
var behind = graph.viewport_texture(graph.screen_uv())
graph.set_output(BACKDROP_NODE, graph.mul(graph.swizzle(behind, "rgb"), graph.vec3(0.8, 1, 0.8)))
```

The renderer draws the opaque scene first for a program that reads it, as it does for a transmissive surface. It uses the same target, three.js's `transmissionRenderTarget`. The triangle is drawn after that pass and is not in it.

- Only the texture view (`SHADE_TEXTURE`) reads the scene. `SHADE_LIT` reads opaque white, as it reads every texture.
- A call to `rasterize_all` or `GpuRenderer.draw` that runs such a program in the texture view must pass a `TransmissionTarget`. A call without one is refused.
- The read is the target's full-size level, bilinear. three.js reads the same level by default.
- A point and a line read opaque white.

### Points and lines

A point and a `Line` run a node material too, as three.js runs a `ShaderMaterial` or a `PointsNodeMaterial` on them. The material must be `BASIC`. Each pixel runs the color, the opacity and the mask, then the fog and the output node. The lights, the emissive, the normal, the ambient occlusion and the depth nodes do not run, because a point and a line are unlit.

- A point is every corner of its program. Its attributes are the same at each of its pixels. `point_coord()` is where the pixel is in the point, and a derivative of it is one over the point's width.
- A line's two ends are its first two corners. A pixel weighs them as the line's color is weighed, with the perspective correction.
- The size node runs on the host, once per point, with the frame's time and view. It replaces the material's size and its attenuation. A size that is not above zero is refused.
- The position node moves a point or a line's vertices, as it moves a mesh's. It reads zero as the normal.
- A texture read on a point reads the level that the point's width chooses. On a line it reads the full-size level.
- A light's view runs no program on a point or a line: it draws their depth alone. The position node still moves them.

## What a node material refuses

- A `NORMALS`, `DEPTH`, `DISTANCE` or `SHADOW` material refuses a node program. These kinds show data or a shadow, not a surface's color.
- A wireframe refuses a node program. A line has no surface.
- A wide line refuses a node material. three.js draws it with its own `LineMaterial` shader.
- A sprite runs a node material on its square, as three.js's `SpriteNodeMaterial` does. It refuses a position node, because a sprite has no vertices of its own to move.
- A program id that is not in `assets.programs` is refused when the mesh is drawn. A program that reads a texture that is not in `assets.textures` is refused too, and so is a texture uniform that names no texture.
- The uv view (`SHADE_UV`) runs no program. `SHADE_LIT` runs it, and a texture node reads opaque white there.

## Where this port differs

- three.js compiles a node graph to a GPU shader. This port interprets a bytecode per fragment, on both backends.
- `normalNode` and `positionNode` replace the normal and the position in three.js. Here they are offsets. Add `normal_world()` or `position_local()` to get a replacement.
- `If` and `Loop` run as selects and unrolled copies, not as jumps. Both branches of an `If` run, and a texture that a branch reads is read.
- `dFdx` and `dFdy` are exact per triangle. A GPU takes them from the pixel quad, and a quad at a triangle's edge reads its neighbors' helper values.
- A `Discard` joins the mask, so it acts before the alpha test, whichever output its branch builds.
- The position node runs before the instance matrix. three.js runs it after the instance matrix.
- The position node reads the geometry's own normal, before the morph targets and the bones.
- A texture node reads its image at the mip level that the surface's own coordinates select. WebGPU measures the derivatives of the coordinate that the node computes.
- A GLSL uniform starts at zero until the caller sets it. three.js starts it at the value in `uniforms`.
- `normalMatrix * normal` is made unit length, and a varying reads the world position of the moved vertex.
- The shadow pass runs no mask, no discard and no depth node. A fragment that the mask throws away still casts a shadow.
- The raycaster picks the geometry without the position node, as three.js's raycaster does.

## What is not ported

- Compute nodes, storage buffers and `instancedArray`.
- Other outputs: `lightsNode`, `receivedShadowNode` and `castShadowNode`.
- Post-processing nodes as nodes. Several of three.js's display nodes run as composer passes instead; see [Post-processing](Post-processing#display-nodes).
