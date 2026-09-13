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
to learn both graphics and the language from first principles.

**Dependencies: the Mojo standard library, and nothing else** — for everything
except one file. `render/gpu.mojo` imports `max.gpu.host`, so the optional GPU
backend needs MAX installed; every other module, and every other test, builds
and runs against the toolchain alone. The split is enforced rather than
promised: `make check-cpu` builds and tests the standard-library-only half, and
`make check-gpu` the rest.

> **Status: early but no longer a toybox.** Scene graph, transforms, camera,
> geometry, meshes, depth buffering, per-vertex normals, near and far clipping,
> perspective-correct shading, and both a CPU and a GPU rasterizer are in place
> and fully tested, along with texture coordinates, backface culling and an
> orthographic camera. Missing, among much else: texture *sampling* (the
> coordinates are carried and interpolated, but nothing reads an image with
> them yet), materials, quaternions, and any kind of windowing. This is a learning project in the open, not a
> drop-in three.js replacement.

## Rendering a scene

```mojo
var scene = Scene()
var node = scene.add(spinning_object)
scene.update()

var geometries = GeometryStore()
var box = geometries.add(cube(Length(1.0, METRE)))

var meshes = List[Mesh]()
meshes.append(Mesh(box, Color(255, 140, 40), node))
meshes.append(Mesh(box, Color(90, 190, 255), other_node))   # same vertices

var renderer = Renderer(260, 200)
var image = renderer.render(scene, geometries, meshes, camera)
```

A `Mesh` names the scene node it is drawn at rather than owning a transform.
three.js has `Mesh` inherit from `Object3D`; Mojo has no inheritance and the
transforms already live in the scene's flat array. The split is worth keeping
anyway — not every node has geometry (the pivot a cube orbits is a node and
nothing else), and one geometry can be drawn at many nodes without copying.

A mesh names its *geometry* by id too, into a `GeometryStore` that owns it.
That is what makes the second half of that sentence true: a mesh is two indices
and a colour, so the two meshes above share one copy of the box's vertices
rather than holding one each.

Shading is Lambert against one directional light plus ambient, evaluated per
vertex and interpolated across the face — Gouraud shading. A geometry's
`normal` attribute decides how it looks: a box gives each of a face's four
corners that face's own normal, so the face comes out flat with a crisp edge;
a sphere gives each vertex the direction it points from the centre, so
neighbouring triangles agree along their shared edge and the facets vanish.
A geometry with no normals falls back to the triangle's *geometric* normal,
which is faceted by construction and the honest result for geometry that never
said which way it faces.

Normals are carried by the world matrix's **normal matrix** — the inverse
transpose of its rotation and scale — not by the world matrix itself. Under a
uniform scale the two agree up to a length that normalizing removes; under a
non-uniform scale they do not, and `Object3D.set_scale` takes three separate
factors.

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

## Rasterization

Coverage is decided in fixed point. Two triangles sharing an edge test it from
opposite corner orderings — one asks `edge(A, B, p)`, the other `edge(B, A, p)`
— and in floating point those need not negate exactly, so a pixel almost on
the edge could come out negative for *both* and be drawn by neither. That left
one-pixel cracks along the shared diagonal of a quad: two in a large quad,
forty-four with the camera inside a cube.

Snapping vertices to a 1/16-pixel grid makes the edge function exact integer
arithmetic, where the orderings do negate exactly and no pixel can be missed.
The **top-left fill rule** then handles the opposite problem, giving a pixel
lying exactly on a shared edge to one triangle rather than both. Drawing twice
is invisible under an opaque depth test but doubles every shared edge once
anything is blended.

The GPU kernel applies the same rule by calling the same code: it lives in
`render/fillrule.mojo`, which allocates nothing, prints nothing and raises
nothing, so it compiles for a device as readily as for the host. It was
duplicated for a while under a comment explaining that a kernel cannot call
into a module that prints — true of the rasterizer, which writes pixels, and
not of arithmetic.

That closes one failure mode and opens another: a CPU/GPU parity test can no
longer catch a bug *inside* the shared rule, because both sides would be wrong
together and agree perfectly. `tests/test_fillrule.mojo` therefore pins it
against values derived from the definitions — and caught exactly that, once:
the horizontal half of the top-left rule was reversed, which is invisible to
parity and to any crack-or-double-draw test (swapping top for bottom is still
a consistent tie-break) and showed up as a triangle silently losing its top
row when that edge landed on pixel centres.

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

`make animation` renders `out/cubes.png`, where a small cube orbits a large one
and passes behind it. The depth buffer carries that result on its own, which
the earlier `cube.png` could not have done.

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
rasterized where they land. Hidden surfaces are removed by the depth buffer,
which is what lets geometry be submitted in any order and what makes a
non-convex scene come out right.

Backface culling sits on top of that as an optimization rather than a
substitute for it. It is on by default, as three.js's default `FrontSide`
material is, and discards roughly half the triangles of a closed mesh before
they are rasterized — the same ones the depth buffer was already hiding, so
the image is unchanged. It has to be switchable, because a camera inside a
closed mesh sees nothing *but* back faces:

```mojo
renderer.set_cull_backfaces(False)   # both windings: three.js's DoubleSide
```

True is three.js's `FrontSide` and False its `DoubleSide`. `BackSide` — only
the faces pointing away — is a third state rather than the other value of a
flag, and it belongs with `Material` alongside the rest of this, per mesh,
rather than on the renderer.

A mesh whose world transform reflects it — `set_scale(-1, 1, 1)`, or any odd
number of reflections inherited from parents — has its winding reversed, so
the convention inverts with it. The sign of the world matrix's determinant is
what says so, asked once per mesh; three.js asks the same question of the same
quantity. Without it a mirrored single-sided mesh is culled exactly when it
should be drawn, and disappears.

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

## Texture coordinates, and why interpolation is not obvious

`box` and `sphere` carry a `uv` attribute, and it travels to the *fragment* —
through clipping, through the perspective divide — rather than being folded
into a colour at the vertex. That is what sampling a texture will need, and it
is already enough to see the thing the rasterizer works hardest at.

Screen-space barycentric weights are not the weights the surface sees:
perspective squeezes the far half of a triangle into fewer pixels. Interpolate
an attribute straight across the screen and it drifts from what the geometry
says. The correction weights by `inv_w` and divides by the interpolated
`inv_w`. Depth is deliberately *not* corrected — the projection makes it linear
in screen space precisely so a depth buffer can work that way.

`make animation` renders `out/uv.png`: two frames of one floor plane, drawn as
two large triangles at a grazing angle with its texture coordinates written out
as red and green. The first is correct, the second has every `inv_w` forced to
one. Every covered pixel differs between them, by up to 142 levels of 255 —
the warped, sliding textures of a PlayStation 1 game.

Both frames come from a single `Renderer.prepare` call, which is why that seam
is public: the affine frame is the same prepared triangles with the perspective
thrown away, so nothing but the correction can account for the difference.

```mojo
var corners = renderer.prepare(scene, geometries, meshes, camera)
```

A floor plane is the worst case on purpose. The error grows with how much
perspective one triangle spans, so it is invisible on a subdivided sphere and
unmissable on two triangles running to the horizon.

## Cameras

`PerspectiveCamera` and `OrthographicCamera` are interchangeable because the
renderer asks for neither. `cameras/camera.mojo` declares a `Camera` trait with
the four things a renderer actually needs — a view matrix, a camera-to-pixels
matrix, and the two clipping distances — and `Renderer.render` is generic over
it. three.js reaches the same place by having both extend a `Camera` base
class; Mojo has no inheritance, and the trait describes the relationship
better anyway.

```mojo
var flat = centred(
    Length(6.0, METRE), aspect, Length(0.1, METRE), Length(100.0, METRE)
)
```

Orthographic projection leaves the transformed `w` at one, so every `inv_w` is
one and the perspective correction divides by one. It is not special-cased
anywhere: the maths already collapses, and a backend that branched on it would
be two code paths where there is one. A happy consequence is that the CPU and
GPU rasterizers agree bit-for-bit on an orthographic scene, interpolated
colour included — affine interpolation leaves no room for a fused multiply-add
to round differently.

`near` may be zero here, as in three.js: nothing divides by depth, so the
perspective camera's reason for forbidding it does not apply. The volume's
edges must be properly ordered, though — right beyond left, top above bottom —
because a reversed pair mirrors the projection, and mirrored winding is
exactly what backface culling reads.

## GPU

`render/gpu.mojo` runs the same edge test as the CPU rasterizer — the same
module, not a copy — with one thread per pixel owning that pixel for the whole
draw, so depth needs no synchronization. Colour and depth both come back.

Its output is asserted **pixel-identical to the CPU path for coverage**, which
is integer arithmetic and admits no disagreement. *Shading* is held to one
level per channel instead: a GPU contracts `a * b + c` into a fused
multiply-add that rounds once where the CPU rounds twice, and an interpolated
channel whose exact value lands on a quantization midpoint can fall either
side. The tests say which standard they are applying and why at each
assertion.

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

Requires the Mojo GPU libraries (`uv pip install "max==26.5.0"`), which are
**not** needed for anything else — see `make check-cpu`. On macOS it also
needs
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

git clone https://github.com/SethKitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install "mojo==1.0.0"          # the pinned toolchain
```

### Linux

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y build-essential curl git
# Fedora:  sudo dnf install -y make gcc git curl
# Arch:    sudo pacman -S --needed base-devel git curl

curl -LsSf https://astral.sh/uv/install.sh | sh

git clone https://github.com/SethKitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install "mojo==1.0.0"          # the pinned toolchain
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
.venv/bin/pip install "mojo==1.0.0"   # same pin as the uv path above
```

### Verify

```bash
.venv/bin/mojo --version            # Mojo 1.0.0 (ed45d567)
make check-cpu                      # no MAX needed
make check                          # adds the GPU half
```

### Pinned versions

| Component | Version | Needed for |
|---|---|---|
| Mojo | `1.0.0` (`ed45d567`) | everything |
| MAX | `26.5.0` | `render/gpu.mojo` and its tests only |
| Metal toolchain | Xcode component, macOS only | running GPU kernels on a Mac |

The toolchain version is part of the build cache key, so upgrading Mojo
invalidates every cached result rather than letting a stale pass count for the
new compiler. `make help` prints the version it is hashing.

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
cameras/     Camera                              the trait a renderer needs
             PerspectiveCamera                   fov in Angle, planes in Length
             OrthographicCamera                  no perspective; w stays 1
core/        Object3D, Scene                     transform hierarchy
             BufferGeometry, BufferAttribute     vertex data, borrowed on read
             GeometryStore                       owns geometry; meshes share it
geometries/  box                                 a box, four vertices per face
             sphere                              latitude/longitude, smooth
objects/     Mesh                                geometry id + colour at a node
renderers/   Renderer                            scene + camera -> triangles
             clip                                near and far plane clipping
render/      Framebuffer, Color, FloatColor      RGBA, depth, and linear colour
             fillrule                            coverage maths, CPU *and* GPU
             rasterizer                          software rasterization
             gpu                                 the same rasterizer, on the GPU
             png, apng, ppm                      encoders that read the buffer
examples/    triangle.mojo                       renders triangle.png
             spin.mojo                           renders spin.png, animated
             cube.mojo                           a 3D cube, animated
             cubes.mojo                          two cubes, depth + hierarchy
             uv.mojo                             perspective-correct vs affine
bench/       raster_bench.mojo                   CPU vs GPU timings
tools/       gpu_status.mojo                     is there an accelerator?
out/         rendered images, gitignored
tests/       one suite per module
             compile_fail/                       files that must NOT compile
coverage/    line / branch / condition / MC-DC coverage tooling
```

`Renderer.prepare` is the seam between the two halves of rendering. It turns a
scene into screen-space triangles — transforms, lighting, clipping, projection
— and both rasterizers consume that same list, which is what makes the CPU/GPU
parity tests mean something:

```
scene + geometries + meshes + camera
                |
        Renderer.prepare
                |
        List[RasterVertex]        <- screen x/y, NDC z, 1/w, linear colour
           /           \
   rasterize_shaded   GpuRenderer.draw
           |                |
      Framebuffer      device target -> read_back()
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
Instrumented 23 files: 913 lines, 117 decisions, 59 conditions.
math/matrix4        lines 169/169 100%  branches 28/28 100%  mcdc 8/8   100%
render/rasterizer   lines  97/97  100%  branches 40/40 100%  mcdc 0/0   100%
render/fillrule     lines   9/9   100%  branches  4/4  100%  mcdc 0/0   100%
render/framebuffer  lines  57/57  100%  branches 50/50 100%  mcdc 16/16 100%
core/scene          lines  47/47  100%  branches 52/52 100%  mcdc 12/12 100%
renderers/renderer  lines  83/83  100%  branches 30/30 100%  mcdc 4/4   100%
TOTAL               1324/1324 100%
```

(Abridged — the run covers twenty-one modules.)

A decision whose second outcome is genuinely unreachable — a loop over a length
an invariant already proves non-zero — is opted out explicitly, so it is visible
in review rather than silently dropped from the denominator:

```mojo
for y in range(self.height):  # pragma: no branch
```

One module is excluded, `render/gpu.mojo`, and for a structural reason: the
probes write to stderr, and a GPU kernel has no stderr. Device code cannot be
instrumented under this design at all. It is covered instead by tests
asserting its output matches the CPU rasterizer — exactly for coverage, and
within one level per channel for interpolated shading.

Everything else — including the rasterizer, the renderer, the PNG encoder and
`Matrix4` — is measured, and the whole run takes about five seconds. The
Makefile gives it a budget of one second per test suite and fails it loudly
past that, on the principle that slow coverage means something is being
instrumented that should not be.

For a while five more modules were excluded — the PNG encoder among them —
because instrumenting them made compilation take minutes. That turned out to be a **Mojo compiler issue**
triggered by one construct the instrumenter emitted — a `Bool` loop flag read
after nested loops — not anything about those modules. The bisection, the
one-line workaround, a standalone reproducer and a draft upstream report are
in [`docs/mojo-compiler-issue/`](docs/mojo-compiler-issue/README.md).

Known limits. MC/DC is the **masking** variant, since short-circuit evaluation
makes strict unique-cause MC/DC unreachable for most compound decisions. The
coverage tool does not measure itself, so a bug in it cannot flatter its own
numbers.

And now that the CPU and GPU rasterizers share `render/fillrule.mojo` rather
than each carrying a copy of it, a CPU/GPU parity test can no longer catch a
bug inside it — both sides would be wrong together and agree perfectly. So
`tests/test_fillrule.mojo` pins that module against values worked out from the
definitions instead, and asserts the two properties the design rests on: that
reversing an edge negates it *exactly*, and that a shared edge is claimed by
exactly one of the two triangles meeting along it.

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
