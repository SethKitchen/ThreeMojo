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

The compiler lexes, parses and type checks the source, and builds the graph as it parses. `shader_graph(vertex, fragment)` returns the graph before it is compiled. `compile_raw_shader_material` reads the shaders as three.js's `RawShaderMaterial` does. See [GLSL source](#glsl-source) for the subset.

## Outputs

A graph sets one to nine outputs. Each output replaces one part of the material's own shading. The material keeps every part that the graph does not set.

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
| `texture(map, uv)` | `vec4` | `texture(map, uv)` | A texture read at a `vec2` coordinate, linear, with straight alpha. `map` is a `TextureId` or a texture uniform. |
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

`round` takes a half to the even whole number. `normalize` leaves a zero vector at zero, where GLSL leaves it undefined. A division by zero gives what IEEE 754 gives, as a GPU does. `mul` of a `mat3` or a `mat4` and a vector of its width multiplies the matrix and the vector, on either side.

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

The noise is MaterialX's gradient noise, with the same hash and the same order of operations as three.js. The point is a `vec2` or a `vec3`. The fractal noise adds a zero to a `vec2`, as three.js converts it.

## Control flow

`If`, `ElseIf`, `Else`, `Loop`, `End`, `Var` and `Discard` are TSL's statements. The builder records them in the order you call them.

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

The bytecode has no jumps. An `If` computes both branches, and each variable that a branch changes becomes a `select` of the two values. `End` unrolls a loop: it copies the body once for each run after the first. So every output stays a graph with no cycle.

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
| `viewMatrix * v`, `cameraPosition` | `camera_view_matrix()`, `camera_position()` |

The world and view positions are of the point that `gl_Position` draws.

### The fragment shader

`gl_FragColor`, `pc_fragColor` or the one `out vec4` is the color and the opacity. `gl_FragDepth` is the depth node. `discard` throws the fragment away.

### The subset

- Types: `void`, `bool`, `int`, `float`, `vec2`, `vec3`, `vec4`, and `mat3`, `mat4` and `sampler2D` uniforms.
- Declarations: `uniform`, `attribute`, `varying`, `in`, `out`, `const` globals with constant values, `precision` statements, and `layout(...)` on an output.
- Functions: functions with `in` parameters. A call inlines the body. A `return` is the last statement of its function.
- Statements: local variables, `if` and `else`, blocks, `discard`, assignments, `+=`, `-=`, `*=`, `/=`, `++` and `--`.
- Loops: `for (int i = a; i < b; i++)` with constant `a`, `b` and step. The condition is `<`, `<=`, `>`, `>=` or `!=`. The step is `++`, `--`, `+=` or `-=`. A loop runs at most 1024 times.
- Expressions: the arithmetic, comparison and logical operators, `?:`, swizzles of `xyzw`, `rgba` and `stpq`, constant indexes, and constructors of scalars and vectors.
- Built-ins of one value: `radians`, `degrees`, the trigonometry, `exp`, `log`, `exp2`, `log2`, `sqrt`, `inversesqrt`, `abs`, `sign`, `floor`, `ceil`, `trunc`, `round`, `roundEven` and `fract`.
- Built-ins of more values: `pow`, `mod`, `min`, `max`, `clamp`, `mix`, `step`, `smoothstep`, `length`, `distance`, `dot`, `cross` and `normalize`.
- Built-ins of light and surfaces: `faceforward`, `reflect`, `refract`, `dFdx`, `dFdy`, `fwidth`, `texture` and `texture2D`.
- The preprocessor: `#version` in a raw shader, and object-like `#define`.

An `int` is a whole number that a float holds. An `int` division drops the fraction toward zero. GLSL ES has no conversion between `int` and `float`, and this compiler has none either. Write `float(i)`.

### What the GLSL compiler refuses

- A `#include`, and every directive but `#version` and an object-like `#define`. A `#version` in a `ShaderMaterial`, as three.js writes its own.
- `onBeforeCompile` and shader chunks: see [Why no chunks](#why-no-chunks).
- The types `uint`, `ivec`, `uvec`, `bvec`, `mat2`, the non-square matrices, `samplerCube`, `sampler3D` and the other samplers, structs and arrays.
- Uniforms of type `int` or `bool`, global variables that are not `const`, and the qualifiers `flat`, `centroid` and `invariant`.
- Custom attributes: only `position`, `normal`, `uv` and `color`.
- `while`, `do`, `switch`, `break`, `continue`, a `return` before the end of its function, and recursion.
- `out` and `inout` parameters, prototypes, overloads, and functions named like GLSL's own.
- The bit operators, `%` of floats, `%=`, and an assignment or `++` inside an expression.
- A for loop that does not declare its index, reads a bound that is not constant, or runs more than 1024 times.
- A matrix times a matrix, a matrix constructor, and a matrix or a sampler in a local variable.
- `modelMatrix`, `modelViewMatrix`, `projectionMatrix` and `normalMatrix` in any form but the ones above, and in a fragment shader.
- A `gl_Position` in any other form, written twice, in a branch or in a function.
- A varying that reads `position` or `normal`, and a texture read in a vertex shader.
- `gl_FragCoord`, `gl_FrontFacing`, `gl_PointCoord`, `gl_PointSize` and every other `gl_` variable.
- The built-ins outside the list above, for example `sinh`, `isnan`, `transpose`, `inverse`, `lessThan`, `textureLod` and `texelFetch`.
- A vector compared with `<`, and a scalar swizzled.

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

## How it runs

`compile` lays out each output as a list of instructions. A node is one instruction in each context it runs in. The contexts are the fragment, the pixel beside it for a derivative, and a corner for a varying. Each instruction writes one of `MAX_REGISTERS` registers of four floats. The compiler gives a register back when the last reader of its value has run.

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

## What a node material refuses

- A `NORMALS`, `DEPTH`, `DISTANCE` or `SHADOW` material refuses a node program. These kinds show data or a shadow, not a surface's color.
- A wireframe refuses a node program. A line has no surface.
- A line, a wide line, a point and a sprite refuse a node material.
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
- `Break`, `Continue` and `Return` inside a loop.
- Integer types and the bit operations, and the matrix functions `transpose`, `determinant` and `inverse`.
- The Worley and cell noises, `mx_noise_vec3` and `mx_noise_vec4`.
- Other outputs: `backdropNode`, `lightsNode`, `shadowNode`, `castShadowNode` and `fragmentNode`.
- Post-processing nodes as nodes. Several of three.js's display nodes run as composer passes instead; see [Post-processing](Post-processing#display-nodes).
- Reading and writing node materials in files.
