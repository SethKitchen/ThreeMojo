# Meshes and assets

`objects/mesh.mojo` and `core/assets.mojo`. A `Mesh` is three ids: a geometry, a material and a scene node. `Assets` owns the geometry, materials and textures that meshes name.

three.js: `Mesh`. three.js has no assets store. A JavaScript mesh holds references; a Mojo mesh holds ids.

## Assets

```mojo
var assets = Assets()
var box = assets.geometries.add(cube(Length(1.0, METER)))
var paint = assets.materials.add(Material(Color(255, 140, 40)))
var board = assets.textures.add(checkerboard(64, 8, white, blue))
```

| Store | Id type | Holds |
|---|---|---|
| `assets.geometries` | `GeometryId` | `BufferGeometry` |
| `assets.materials` | `MaterialId` | `Material` |
| `assets.textures` | `TextureId` | `Texture` |

Each store is append-only. `add` returns the id. `get(id)` returns the item, or raises for an unknown id. `count()` returns how many items there are.

## Mesh

```mojo
scene.add_mesh(Mesh(box, paint, node))
```

`Mesh(geometry, material, node)`. Each argument is a typed id. Swapping two arguments does not compile.

A mesh holds no transform. The node holds it. One geometry can be drawn at many nodes without a copy.

## Rules

- The node must exist in the scene when `add_mesh` is called.
- The geometry and material are checked when the scene renders. The scene does not see the assets.
- A material's texture id is checked when the scene renders too.

## Ids

Every id wraps one integer in a struct. The wrapper costs nothing at run time. The compiler refuses a bare integer, and `tests/compile_fail/` proves it. See [Why types and checks both exist](Why-types-and-checks-both-exist).
