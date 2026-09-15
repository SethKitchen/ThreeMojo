# Why types and checks both exist

Every id, mode and kind is a struct around one integer, and every boundary that reads one still checks its value. The type stops a transposition at compile time. The check stops nonsense at run time. They are different jobs.

## The types

A `Mesh` takes a geometry id, a material id and a node id in a row. As plain integers, any two could be swapped and the program would render nonsense. As `GeometryId`, `MaterialId` and `NodeId`, a swap does not compile. `tests/compile_fail/` holds one file per type that proves it.

The same discipline covers `Side`, `Blending`, `MaterialKind`, `LightKind`, `ShadeMode`, `Wrap`, `Filter` and `ColorSpace`. It covers the units too: `rotation_z(90.0)` does not compile, because the compiler cannot tell degrees from radians.

## What a type does not do

A struct's fields are open in Mojo. `Blending(7)` constructs, and so does `changed.value = 7` after the fact. For a while the runtime checks had been dropped on the strength of the types. The two rasterizers could then read a value neither knew in opposite directions. The CPU asked "is it `BLEND`?" and the GPU asked "is it `OPAQUE`?", so a 7 was opaque on one and blended on the other.

## The checks

Every enum-like type has `is_valid`, and every boundary asks:

| Boundary | Checks |
|---|---|
| `Material` constructor | `side`, `blending`, `kind` |
| `Texture` constructor and `validate` | `wrap`, `filter`, `color_space` |
| `Lighting` resolution | The light's kind |
| `Renderer.set_shading` | The mode |
| `check_triangle_state`, on both backends | The blend policy and the texture id |
| `rasterize_all` and `GpuRenderer.draw` | Every triangle, before any work |
| `flatten_textures` | Every texture again, at upload |

The kernel's remaining fallthrough branches ask the host's question, so a value that slips past everything falls the same way on both sides.

## Before any band starts

`rasterize_all` validates every triangle before it hands work to a thread. A band skips triangles outside its rows, so without that step an off-screen malformed triangle raised on one worker and passed on four. The answer must not depend on visibility or on the worker count.
