# Node materials

`materials/nodes.mojo`. A node material replaces parts of a surface's shading with a small graph of nodes: three.js's node materials and its Three Shading Language (TSL). You build a `NodeGraph`, compile it to a `NodeProgram`, add the program to `assets.programs`, and give its id to a `Material`.

three.js: `NodeMaterial`, `colorNode`, `opacityNode`, `emissiveNode`, `normalNode`, `positionNode`, `outputNode`, `uniform`, `ShaderMaterial` as far as a node graph can express it.

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

## Outputs

A graph sets one to six outputs. Each output replaces one part of the material's own shading. The material keeps every part that the graph does not set.

| Output | Type | three.js | What it replaces |
|---|---|---|---|
| `COLOR_NODE` | `vec3` | `colorNode` | The diffuse color: the material's color, its vertex colors and its map. The lights multiply it. |
| `OPACITY_NODE` | `float` | `opacityNode` | The alpha: the opacity, the map's alpha and the alpha map. The alpha test reads it. |
| `EMISSIVE_NODE` | `vec3` | `emissiveNode` | The light the surface gives off: the emissive color and the emissive map. |
| `NORMAL_NODE` | `vec3` | `normalNode` | Nothing. It is an offset added to the world-space normal before the lights read it. |
| `POSITION_NODE` | `vec3` | `positionNode` | Nothing. It is an offset added to each vertex's local position. |
| `OUTPUT_NODE` | `vec3` | `outputNode` | The finished color, after the lights, the reflection and the fog. The `lit` node reads that color. |

The alpha of the finished color stays what the fragment had. An output node changes only its color.

## Nodes

| Method | Type | three.js | Value |
|---|---|---|---|
| `float(x)`, `vec2`, `vec3`, `vec4` | as named | `float()`, `vec2()` and the rest | A constant. |
| `color(Color)` | `vec3` | `color()` | A constant color, decoded from sRGB to linear. |
| `uniform(name, value)` | as the value | `uniform()` | A named value the caller can change between frames. The value is a `Float32`, a `Vector2`, a `Vector3` or a `Color`. |
| `uv()` | `vec2` | `uv()` | The coordinate the material's `map` is read at, through its transform. |
| `position_world()` | `vec3` | `positionWorld` | The fragment's position in world space, in meters. |
| `position_view()` | `vec3` | `positionView` | The fragment's position in the camera's space. The camera looks down minus z. |
| `normal_world()` | `vec3` | `normalWorld` | The fragment's unit normal in world space, after any normal or bump map. |
| `normal_view()` | `vec3` | `normalView` | The fragment's unit normal in the camera's space. |
| `vertex_color()` | `vec3` | `materialColor` times `vertexColor()` | The interpolated corner color: the material's color times the vertex colors. |
| `position_local()` | `vec3` | `positionLocal` | The vertex's position in the model's space. A position node only. |
| `normal_local()` | `vec3` | `normalLocal` | The vertex's normal in the model's space. Zero if the geometry has no normals. A position node only. |
| `time()` | `float` | `time` | `Renderer.time`, in seconds. |
| `texture(map, uv)` | `vec4` | `texture(map, uv)` | A texture read at a `vec2` coordinate, linear, with straight alpha. |
| `lit()` | `vec3` | `output` | The color that the material's own shading made. An output node only. |
| `add`, `sub`, `mul`, `div` | the wider operand | same names | Component by component. |
| `mix(a, b, t)` | the widest operand | `mix` | `a * (1 - t) + b * t`. |
| `clamp(x, low, high)` | the widest operand | `clamp` | `min(max(x, low), high)`. |
| `smoothstep(low, high, x)` | the widest operand | `smoothstep` | GLSL's smooth rise from zero to one. |
| `step(edge, x)` | the wider operand | `step` | Zero where `x` is below `edge`, one elsewhere. |
| `pow(a, b)` | the wider operand | `pow` | `a` raised to `b`. |
| `sin`, `cos`, `fract` | the operand | same names | Component by component. The angle is in radians. |
| `dot(a, b)` | `float` | `dot` | The dot product of two vectors of one size. |
| `length(a)` | `float` | `length` | The length of a vector. |
| `normalize(a)` | the operand | `normalize` | The vector at a length of one. A zero vector stays zero. |
| `swizzle(a, "zyx")` | as long as the string | `a.zyx` | Components picked and reordered. The letters are `xyzw` or `rgba`. |

A `float` next to a vector is repeated into every component, as in GLSL. `set_input(node, slot, source)` rewires one input of a node, as a node editor does.

## What a graph refuses

The graph refuses a type error when you build the node:

- two vectors of different sizes in one operation, for example a `vec3` added to a `vec2`;
- a texture read at a coordinate that is not a `vec2`, or with `NO_TEXTURE`;
- a swizzle of a component that the value does not have;
- an output given a node of the wrong type;
- a uniform with no name, or with the name of another uniform;
- a `NodeRef` that names no node of this graph;
- a rewire that changes an input's type or makes a cycle.

`compile` refuses these:

- a graph with no output;
- a cycle, or an input that names no node, in a graph whose fields were edited;
- a position node that reads a fragment's attribute, a texture or the lit color;
- a fragment output that reads the local position or the local normal;
- a `lit` node in an output other than `OUTPUT_NODE`;
- an output that needs more than `MAX_REGISTERS` (32) nodes.

`NodeProgram.set_uniform` refuses a name that no uniform has, and a value of the wrong type.

## Shader material

`shader_material(fragment)` is three.js's `ShaderMaterial` as this port has it. The fragment program is a compiled node graph. Its `COLOR_NODE` is `gl_FragColor.rgb`, and its `OPACITY_NODE` is the alpha. Its uniforms are three.js's `uniforms`. The material is `BASIC`, so no light reaches it. Its `fog` is off, as three.js's is.

```mojo
var graph = NodeGraph()
var stripes = graph.step(graph.float(0.5), graph.fract(graph.mul(graph.uv(), graph.float(8))))
graph.set_output(COLOR_NODE, graph.swizzle(stripes, "xyx"))
var card = assets.materials.add(shader_material(assets.programs.add(graph.compile())))
```

## How it runs

`compile` lays out each output as a list of instructions, one per node and one register per node. The constants and the uniforms follow the instructions, each stored once. A header holds where each output starts, the frame's time and the camera's view matrix. `Renderer.prepare_frame` copies `assets.programs` and writes the time and the view into the copy.

Both rasterizers run the program with one function, `run_nodes`. The CPU reads the program from its list. The GPU kernel reads it from the fog buffer, after the fog's six floats, because the kernel has no free argument. A triangle's state column `STATE_NODES` tells the kernel where its program starts. The parity tests in `tests/test_gpu.mojo` hold the two backends to the same pixels. See [GPU backend](GPU-backend).

A fragment runs the outputs in this order:

1. The normal node, after any normal or bump map. The sum is made unit length again.
2. The lights, with the bent normal.
3. The color, the opacity and the emissive nodes, after the maps. The color is multiplied by the arriving light.
4. The alpha test, the lights' sums, the reflection and the fog.
5. The output node.

The position node runs on the host, once per vertex, after the morph targets, the bones and the displacement map. So both rasterizers draw the same moved triangles, and the shadow pass casts them. A mesh with a position node is not culled by the bound of its geometry.

## What a node material refuses

- A `NORMALS`, `DEPTH`, `DISTANCE` or `SHADOW` material refuses a node program. These kinds show data or a shadow, not a surface's color.
- A wireframe refuses a node program. A line has no surface.
- A line, a wide line, a point and a sprite refuse a node material.
- A program id that is not in `assets.programs` is refused when the mesh is drawn. A program that reads a texture that is not in `assets.textures` is refused too.
- The uv view (`SHADE_UV`) runs no program. `SHADE_LIT` runs it, and a texture node reads opaque white there.

## Where this port differs

- three.js compiles a node graph to a GPU shader. This port interprets a bytecode per fragment, on both backends.
- `normalNode` and `positionNode` replace the normal and the position in three.js. Here they are offsets. Add `normal_world()` or `position_local()` to get a replacement.
- The position node runs before the instance matrix. three.js runs it after the instance matrix.
- The position node reads the geometry's own normal, before the morph targets and the bones.
- A texture node reads its image at the mip level that the surface's own coordinates select. WebGPU measures the derivatives of the coordinate that the node computes.
- The raycaster picks the geometry without the position node, as three.js's raycaster does.

## What is not ported

- GLSL source. A `ShaderMaterial`'s `vertexShader` and `fragmentShader` strings, `RawShaderMaterial`, `onBeforeCompile` and shader chunks cannot be compiled here.
- Compute nodes, storage buffers and `instancedArray`.
- `Fn` functions, `If`, `Loop`, `Var`, `varying` and `discard`.
- Derivatives: `dFdx`, `dFdy` and `fwidth`.
- The rest of the node library: `abs`, `min`, `max`, `atan`, `cross`, `reflect`, `remap`, noise and the other functions.
- Other outputs: `backdropNode`, `aoNode`, `lightsNode`, `shadowNode`, `maskNode`, `depthNode` and `fragmentNode`.
- Uniforms of type `vec4`, `mat3` or `mat4`, and texture uniforms. A texture node names its texture when you build it.
- Post-processing nodes.
- Reading and writing node materials in files.
