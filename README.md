<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

```
   ████████╗██╗  ██╗██████╗ ███████╗███████╗
   ╚══██╔══╝██║  ██║██╔══██╗██╔════╝██╔════╝
      ██║   ███████║██████╔╝█████╗  █████╗
      ██║   ██╔══██║██╔══██╗██╔══╝  ██╔══╝
      ██║   ██║  ██║██║  ██║███████╗███████╗
      ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝
   ███╗   ███╗ ██████╗      ██╗ ██████╗
   ████╗ ████║██╔═══██╗     ██║██╔═══██╗
   ██╔████╔██║██║   ██║     ██║██║   ██║
   ██║╚██╔╝██║██║   ██║██   ██║██║   ██║
   ██║ ╚═╝ ██║╚██████╔╝╚█████╔╝╚██████╔╝
   ╚═╝     ╚═╝ ╚═════╝  ╚════╝  ╚═════╝

                      █
                    █████                  three.js, ported to Mojo.
                  █████████                Zero dependencies.
                █████████████              Software rasterized.
              █████████████████
            █████████████████████          ▲ rendered by this repo,
          █████████████████████████          by the same edge function
        █████████████████████████████        the rasterizer uses
      █████████████████████████████████
    █████████████████████████████████████
  █████████████████████████████████████████
```

[![license](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-orange)](LICENSE)
[![mojo](https://img.shields.io/badge/Mojo-1.0.0-fe5c1c)](https://mojolang.org)
[![coverage](https://img.shields.io/badge/coverage-100%25%20line%20%7C%20branch%20%7C%20condition%20%7C%20MC%2FDC-brightgreen)](#coverage)

A port of [three.js](https://threejs.org) to [Mojo](https://mojolang.org), built
to learn both graphics and the language from first principles. No third-party
libraries — only the Mojo standard library.

> **Status: early.** The math and rasterizer foundations are in place and fully
> tested. There is no `Matrix4`, camera, or mesh pipeline yet. This is a
> learning project in the open, not a drop-in three.js replacement.

## Rendering a scene

```mojo
var scene = Scene()
var node = scene.add(spinning_object)
scene.update()

var meshes = List[Mesh]()
meshes.append(Mesh(cube(Length(1.0, METRE)), Color(255, 140, 40), node))

var renderer = Renderer(260, 200)
var image = renderer.render(scene, meshes, camera)
```

A `Mesh` names the scene node it is drawn at rather than owning a transform.
three.js has `Mesh` inherit from `Object3D`; Mojo has no inheritance and the
transforms already live in the scene's flat array. The split is worth keeping
anyway — not every node has geometry (the pivot a cube orbits is a node and
nothing else), and one geometry can be drawn at many nodes without copying.

Shading is flat Lambert against one directional light plus ambient. The normal
comes from the triangle's own world-space corners via a cross product, since
there is no `normal` attribute yet — a *geometric* normal, faceted by
construction. Right for a cube, wrong for a sphere, which needs per-vertex
normals smoothed across the surface.

Colour lives on the mesh rather than in a `Material`. A material with one
field would be ceremony; it earns a type when there is a second property.

## Geometry

A `BufferGeometry` is named attributes — `position` at minimum — plus an
optional index buffer. Flat float arrays rather than lists of `Vector3`,
because that is the layout a GPU wants and can be uploaded without
rearranging. Indexing means a vertex shared by several triangles is stored
once.

```mojo
var geometry = cube(Length(1.0, METRE))
geometry.vertex_count()          # 24
geometry.triangle_count()        # 12
geometry.corner(0, 1)            # a corner position
geometry.corner_index(0, 1)      # which vertex that was, to project once
```

A box uses twenty-four vertices, not eight. Sharing corners would be smaller,
but a corner shared between three faces can carry only one normal and one
texture coordinate, so the faces could never be shaded separately — which is
why three.js splits them too.

## Scene graph and depth

`rasterize_depth` interpolates NDC depth across the triangle and keeps a
fragment only when it is nearer than what is there, so geometry can be
submitted in any order. Worth being explicit about why linear interpolation is
correct here: *world* depth and attributes like texture coordinates need
perspective-correct interpolation through 1/w, but NDC depth does not, because
the perspective divide has already happened. That is exactly why hardware
depth buffers store this value rather than distance.

three.js gives every object a `children` array. **Mojo cannot express that** —
a struct may not contain a `List` of itself, which the compiler rejects with
*"field 'children' has non-'Deinitable' type"*. So the tree is stored inverted:
each node records its parent's index and `Scene` owns the flat array.

That turns out better than a workaround. `add` refuses a parent that does not
already exist, so a parent always precedes its children, so updating every
world matrix is a single forward pass — no recursion, no visited set, and
cycles are impossible by construction rather than by checking.

```mojo
var scene = Scene()
var pivot = scene.add(spinning_node)
var moon  = scene.attach(node_at(1.6, 0, 0), pivot)   # orbits for free
scene.update()
scene.world_matrix(moon)
```

`make animation` renders `out/cubes.png`, where a small cube orbits a large one and
passes behind it. There is no backface culling at all in that example — the
depth buffer carries the whole result, which the earlier `cube.png` could not
have done.

## Camera

Three matrices take a scene from world space onto a screen, and the middle
ground between them is deliberately unitless:

```
look_at      where the camera is and which way it faces
perspective  how distance shrinks things          -> normalized device coords
viewport     where a normalized point lands       -> pixels
```

World space is **metres** — the camera's `near` and `far` are `Length`, which
is where this project pins down what three.js leaves to the application. The
field of view is an `Angle`, so `PerspectiveCamera(50.0, ...)` does not
compile; you have to say degrees or radians. NDC in the middle is
dimensionless, which is exactly right: it is the neutral ground where neither
metres nor pixels apply.

```mojo
var camera = PerspectiveCamera(
    Angle(50.0, DEGREE), 4.0 / 3.0, Length(0.1, METRE), Length(100.0, METRE)
)
camera.place(Vector3(0, 0, 2.5), Vector3(0, 0, 0))
camera.project(Vector3(0, 0, 0), 240, 180)   # -> pixels, plus NDC depth
```

`make animation` renders `out/cube.png`, the first example that draws a *scene*:
world-space corners in metres, turned by a model matrix, projected, and
rasterized where they land. There is no depth buffer yet, so hidden faces are
removed by backface culling — a face whose screen-space winding has reversed
is pointing away. For a convex solid that is exactly right and costs one sign
test that `Triangle.area2` already computes.

## Matrix4

Column-major storage, as three.js and OpenGL both are — element (row, col)
lives at `col * 4 + row`, and the translation sits in `e[12..14]` where a GPU
expects it. `set()` nevertheless takes **row-major** arguments, so a matrix
written in source reads the way it would on paper while landing transposed in
memory. That asymmetry is three.js's, kept deliberately, and asserted by tests
in both directions because it is exactly the sort of thing that silently
transposes a scene.

```mojo
var m = translation(10, 0, 0)
m.multiply(rotation_z(Angle(90.0, DEGREE)))   # right-hand matrix applies first
m.multiply(translation(-10, 0, 0))            # rotation about (10, 0, 0)

m.transform_point(Vector3(11, 0, 0))          # (10, 1, 0)
m.transform_direction(v)                      # ignores translation
```

Rotations take an `Angle`, so `rotation_z(90.0)` does not compile — there is
no way to be unsure whether a rotation is in degrees or radians. Matrices
themselves are not unit-tagged: a transform mixes dimensions by nature, with a
dimensionless rotation part and a translation column in length units, and
expressing that needs per-element dimensions rather than per-value.

A singular matrix inverts to all zeros, as in three.js — deliberately
conspicuous, since everything transformed by it collapses to the origin
rather than quietly coming back unchanged.

## Units

Every measurement carries its dimension, checked at compile time and erased
before runtime — a `Quantity` is exactly the size of the `Float32` inside it.

```mojo
var height = Length(1.0, METRE)
print(height.to(FOOT))              # 3.2808399
print(height.to(INCH))              # 39.37008

var area = height * Length(2.0, METRE)   # Area: length exponent 2
var side = area.sqrt()                   # back to a Length
var speed = Length(100.0) / Duration(9.58)   # Velocity: [1, 0, -1, 0]

var total = Length(1.0, METRE) + Length(1.0, FOOT)   # 1.3048 m
```

Values are stored canonically (metres, kilograms, seconds, radians), so units
mix freely in one expression and comparisons are always right. Mistakes are
compile errors, not runtime checks:

```mojo
Length(1.0, METRE) + Duration(1.0, SECOND)   # error
Length(1.0, METRE).to(SECOND)                # error
Volume(8.0).sqrt()                           # error: odd exponent
rotate(90.0)                                 # error: needs an Angle
```

Angle is carried as a base dimension, which strict SI does not do — a radian
is properly dimensionless. It earns its place by making degrees-for-radians a
compile error, which is a common enough graphics bug to be worth the deviation.

Because those failures cannot be exercised from inside a test suite — a file
containing one would not build — each lives in `tests/compile_fail/` and
`make compile-fail` asserts every one still fails to compile.

## GPU

`render/gpu.mojo` runs the same edge test as the CPU rasterizer with one thread
per pixel, and its output is asserted **pixel-identical** to the CPU path.

```
$ make bench
320x240   (76k px)   CPU   513 us   GPU   485 us
640x480  (307k px)   CPU  2032 us   GPU   611 us    GPU wins by 3x
1280x720 (921k px)   CPU  6302 us   GPU  1107 us    GPU wins by 5x
1920x1080 (2M px)    CPU 14593 us   GPU  1892 us    GPU wins by 7x
3840x2160 (8M px)    CPU 56479 us   GPU 11360 us    GPU wins by 4x
```

GPU timings include device allocation and the copy back, because that is what
it costs to get a usable image. Timing the kernel alone would flatter it: at
1080p the kernel is ~600 us and the transfer is the rest.

Requires the Mojo GPU libraries (`uv pip install max`). On macOS it also needs
Apple's Metal toolchain, which Xcode does **not** install by default:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Without it every kernel fails with `Metal Compiler failed to compile metallib`,
which looks like a code error and is not.

## Why it isn't a WebGL renderer

Mojo's GPU support is compute-only, in the CUDA sense: kernels, buffers, and
thread indexing. There is no rasterization pipeline, no vertex or fragment
shaders, no window or swapchain. So three.js's `WebGLRenderer` cannot be ported
directly.

Instead ThreeMojo rasterizes in software into a plain RGBA byte buffer. That
turns out to be the more instructive version: you write the inside-triangle
test yourself, and the per-pixel loop is exactly the shape that later maps to
one GPU thread per pixel.

The buffer is the product. Displaying it belongs to whatever is presenting —
a canvas, an NSWindow, a DIB, a texture upload — so `Framebuffer` knows nothing
about file formats, and the encoders read it rather than the other way round.

## Requirements

| | Supported | Notes |
|---|---|---|
| **macOS** | Yes | Apple Silicon (M-series). Intel Macs are not supported by Mojo. |
| **Linux** | Yes | x86-64 and aarch64. |
| **Windows** | Via WSL 2 | Mojo has no native Windows build; run inside a WSL 2 Linux distro. |

You also need Python 3.9+ (to install Mojo from PyPI) and `make`.

## Setup

ThreeMojo pins its toolchain in a local `.venv`, so nothing is installed
system-wide. [`uv`](https://docs.astral.sh/uv/) is the quickest way in, but
plain `venv` works identically.

### macOS

```bash
# Install uv and make (make ships with the Xcode command line tools)
brew install uv
xcode-select --install          # if `make` is missing

git clone https://github.com/sethkitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install mojo
```

### Linux

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y build-essential curl git
# Fedora:  sudo dnf install -y make gcc git curl
# Arch:    sudo pacman -S --needed base-devel git curl

curl -LsSf https://astral.sh/uv/install.sh | sh

git clone https://github.com/sethkitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install mojo
```

### Windows (WSL 2)

Mojo does not run natively on Windows. Install WSL 2 first, from PowerShell
**as Administrator**:

```powershell
wsl --install -d Ubuntu
```

Reboot, open the Ubuntu terminal, then follow the **Linux** steps above.

> Clone into the Linux filesystem (`~/ThreeMojo`), **not** `/mnt/c/...`.
> Building across the Windows/Linux filesystem boundary is dramatically slower.

### Without uv

```bash
python3 -m venv .venv
.venv/bin/pip install mojo          # Windows-in-WSL uses this same path
```

### Verify

```bash
.venv/bin/mojo --version            # Mojo 1.0.0 (...)
make check                          # should print "All suites passed."
```

The `Makefile` calls `.venv/bin/mojo` by path, so **you never need to activate
the virtualenv**. If you prefer to anyway:

| Shell | Command |
|---|---|
| bash / zsh (macOS, Linux, WSL) | `source .venv/bin/activate` |
| fish | `source .venv/bin/activate.fish` |
| PowerShell | `.venv\Scripts\Activate.ps1` |

## Commands

Every command below is identical on macOS, Linux, and WSL.

| Command | What it does |
|---|---|
| `make help` | List the tasks and the current input hash. |
| `make check` | Format check + lint + tests. **Run this before committing.** |
| `make test` | Run every `tests/test_*.mojo` suite. |
| `make lint` | Compile everything with warnings promoted to errors. |
| `make fmt` | Reformat all sources in place. |
| `make fmt-check` | Verify formatting without modifying anything. |
| `make coverage` | Line, branch, condition and MC/DC coverage, ~5s. Exits non-zero on any gap or if it exceeds one second per suite. |
| `make docstrings` | Strict docstring audit (`Args:`/`Returns:`/`Raises:` on every public symbol). |
| `make example` | Render `out/triangle.png`. |
| `make animation` | Render the animated examples into `out/`. |
| `make bench` | CPU vs GPU rasterization across image sizes. |
| `make compile-fail` | Assert every unit error is still rejected by the compiler. |
| `make clean` | Remove the coverage build and the task cache. Keeps `out/`. |
| `make clean-images` | Remove the rendered images in `out/`. |

Task results are cached on a SHA-256 of the source contents, so a task whose
inputs have not changed is skipped entirely — a warm `make check` is instant.
Because the key is content and not modification time, `make fmt` rewriting a
file byte-identically keeps the cache warm, and a fresh clone does not throw it
away. Force a re-run with `make -B <task>`.

### Running something directly

Mojo needs the repo root on its import path, which is what `-I .` does. Without
it you get `unable to locate module 'math'`.

```bash
.venv/bin/mojo run -I . tests/test_vector3.mojo
.venv/bin/mojo run -I . examples/triangle.mojo out/triangle.png
.venv/bin/mojo run -I . examples/triangle.mojo out/triangle.ppm  # text
```

### Image formats

| | Alpha | Previews in VS Code | Notes |
|---|---|---|---|
| **PNG** (`render/png.mojo`) | Yes, 8-bit | Yes | The default. Written with no compression library — see below. |
| **APNG** (`render/apng.mojo`) | Yes, 8-bit | Yes, animated | Several frames in one file, for watching a sequence. |
| **PPM** (`render/ppm.mojo`) | No | No | Plain text, so you can read pixel values in an editor. Debugging only. |

APNG is a plain PNG with three extra chunks (`acTL`, `fcTL`, `fdAT`), so it
reuses the still encoder untouched, and the first frame stays in the ordinary
`IDAT` — a viewer that has never heard of APNG just shows frame one. GIF would
be the obvious alternative and is a worse fit: 1-bit transparency only, and a
256-colour palette per frame that rendered output would have to be quantized
into.

PNG normally implies zlib, which would be a dependency. It is avoidable:
DEFLATE (RFC 1951) defines a *stored* block that holds raw bytes, so a valid
zlib stream needs only a two-byte header, a run of stored blocks, and an
Adler-32 checksum. Files are larger than a real encoder's and legal everywhere
— `zlib.decompress` accepts them, which the test suite relies on.

## Editor setup

The Mojo language server resolves imports with its own search path and does
**not** inherit `-I .`, so project imports show red squiggles until you tell it
about the repo root. This repo ships `.vscode/settings.json` with:

```json
{ "mojo.lsp.includeDirs": ["."] }
```

It has to be `"."`, not `"${workspaceFolder}"` — the extension performs no
variable substitution, so it would pass that string to the server as a literal
directory name and the imports would still fail. `"."` resolves because the
server runs with the workspace folder as its working directory.

Install the **Mojo** extension by Modular, then reload the window
(`Ctrl/Cmd+Shift+P` → *Developer: Reload Window*). The setting is only read at
language-server startup.

## Layout

```
units/       Quantity, Unit                      compile-time dimensions
             si                                  metres, feet, degrees, ...
math/        Vector2, Vector3                    ported from three.js
             Matrix4                             4x4 transforms, column-major
             projection                          perspective, look_at, viewport
cameras/     PerspectiveCamera                   fov in Angle, planes in Length
core/        Object3D, Scene                     transform hierarchy
             BufferGeometry, BufferAttribute     vertex data
geometries/  box                                 a box, four vertices per face
objects/     Mesh                                geometry + colour at a node
renderers/   Renderer                            scene + camera -> image
render/      Framebuffer, Color                  RGBA plus a depth buffer
             rasterizer                          software rasterization
             gpu                                 the same rasterizer, on the GPU
             png, apng, ppm                      encoders that read the buffer
examples/    triangle.mojo                       renders triangle.png
             spin.mojo                           renders spin.png, animated
             cube.mojo                           a 3D cube, animated
             cubes.mojo                          two cubes, depth + hierarchy
bench/       raster_bench.mojo                   CPU vs GPU timings
out/         rendered images, gitignored
tests/       one suite per module
             compile_fail/                       files that must NOT compile
coverage/    line / branch / condition / MC-DC coverage tooling
```

## Coverage

Mojo 1.0 ships no coverage tool, and there is no `llvm-cov` or `llvm-profdata`
in the toolchain to build one on. It also has **no global variables at all**, so
a probe has nowhere to accumulate counts.

ThreeMojo works around this by rewriting sources into instrumented copies whose
probes write one record per event to *stderr*, which the report then groups and
deduplicates. `stdout` stays byte-for-byte identical, so an instrumented run
still produces a valid PPM.

Four metrics, all gating:

| Metric | Question it answers |
|---|---|
| **Line** | Did this statement ever run? |
| **Branch** | Did this decision go both ways? (`for` loops included — did it ever run zero times?) |
| **Condition** | Did each `and`/`or` operand take both values? |
| **MC/DC** | Was each operand shown to change the outcome *on its own*? |

```
$ make coverage
math/vector3        lines 16/16 100%   branches 2/2   100%   mcdc 0/0 100%
render/ppm          lines 10/10 100%   branches 0/0   100%   mcdc 0/0 100%
render/rasterizer   lines 16/16 100%   branches 6/6   100%   mcdc 0/0 100%
render/apng         lines 44/44 100%   branches 10/10 100%   mcdc 2/2 100%
render/framebuffer  lines 22/22 100%   branches 16/16 100%   mcdc 6/6 100%
TOTAL               150/150 100%
```

A decision whose second outcome is genuinely unreachable — a loop over a length
an invariant already proves non-zero — is opted out explicitly, so it is visible
in review rather than silently dropped from the denominator:

```mojo
for y in range(self.height):  # pragma: no branch
```

One module is excluded, `render/gpu.mojo`, and for a structural reason: the
probes write to stderr, and a GPU kernel has no stderr. Device code cannot be
instrumented under this design at all. It is covered instead by tests
asserting its output matches the CPU rasterizer pixel for pixel.

Everything else — including the rasterizer, the renderer, the PNG encoder and
`Matrix4` — is measured, and the whole run takes about five seconds. The
Makefile gives it a budget of one second per test suite and fails it loudly
past that, on the principle that slow coverage means something is being
instrumented that should not be.

For a while four more modules were excluded because instrumenting them made
compilation take minutes. That turned out to be a **Mojo compiler issue**
triggered by one construct the instrumenter emitted — a `Bool` loop flag read
after nested loops — not anything about those modules. The bisection, the
one-line workaround, a standalone reproducer and a draft upstream report are
in [`docs/mojo-compiler-issue/`](docs/mojo-compiler-issue/README.md).

Known limits. MC/DC is the **masking** variant, since short-circuit evaluation
makes strict unique-cause MC/DC unreachable for most compound decisions. The
coverage tool does not measure itself, so a bug in it cannot flatter its own
numbers. And `render/png.mojo` is listed in `COVERAGE_EXCLUDE` in the Makefile:
instrumenting a module full of byte-level loops multiplies its statement count
enough that *compiling* the instrumented copy takes minutes. It is still fully
tested — it is the measurement that is impractical — and the exclusion is
spelled out in the Makefile so the gap stays visible.

## Contributing

Open an issue before a large change — the project is following a deliberate
port order and welcomes company, but not surprise rewrites.

`make check` must pass and `make coverage` must stay at 100% before anything
merges. New code needs tests covering every branch and condition, not just
every line.

By contributing you agree your contribution is licensed on the same terms as
the project, including the commercial-licensing arrangement described below.

## License

ThreeMojo is **free for noncommercial use** under the
[PolyForm Noncommercial License 1.0.0](LICENSE) — personal projects, study,
research, and use by charities, schools, and government bodies.

**Commercial use requires a paid license.** See
[LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md).

Copyright © 2026 Seth Kitchen, PE

`math/` and `render/` are ported from three.js, which is MIT licensed. Those
notices are preserved in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
Nothing here restricts your rights in three.js itself, which you may always use
under the MIT License directly. `coverage/` is entirely original work with no
three.js lineage.
