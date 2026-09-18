# Model files

`loaders/obj.mojo`. `read_obj` reads a Wavefront OBJ file into named objects, each with a `BufferGeometry`. `parse_obj` reads the text of one.

![A cube loaded from an OBJ file turns under a lamp](out/model.png)

three.js: `OBJLoader`.

## Read a file

```mojo
var model = read_obj("assets/cube.obj")
for index in range(model.count()):
    print(model.objects[index].name, model.objects[index].material)
var shape = assets.geometries.add(model.objects[0].take_geometry())
```

| Function | Meaning |
|---|---|
| `read_obj(path) -> ObjModel` | Read a file. |
| `parse_obj(text) -> ObjModel` | Read the text of one. |

## ObjModel and ObjObject

`ObjModel.objects` holds one `ObjObject` per object, in file order. `count()` says how many.

| Field | Meaning |
|---|---|
| `name` | From `o` or `g`. Empty before either. |
| `material` | The name from `usemtl`. Empty before one. The material library is not read. |
| `geometry` | A non-indexed `BufferGeometry` with `position`, and with `normal` and `uv` when the faces name them. |

`take_geometry()` swaps the geometry out for an empty one, so it can go into a store. A `BufferGeometry` moves and does not copy.

## What is read

| Line | Meaning |
|---|---|
| `v x y z` | A position. A fourth number is ignored. |
| `vt u v` | A texture coordinate. |
| `vn x y z` | A normal. |
| `f a b c ...` | A face of three or more corners, cut into a fan of triangles. A polygon must be convex. Each corner is `v`, `v/vt`, `v//vn` or `v/vt/vn`. |
| `o name`, `g name` | A new object. One with no faces is dropped. |
| `usemtl name` | A new object under that material, with the same name. |
| `#` | A comment, to the end of the line. |

An index counts from one. A negative index counts back from the last entry so far. `mtllib`, `s`, `l`, `p` and unknown lines are skipped.

Every face of one object must agree about normals and texture coordinates. A geometry without normals shades flat. See [Renderer](Renderer).

## Errors

The parser raises, naming the line, for:

- A `v`, `vt` or `vn` line with too few coordinates. A coordinate that is not a number, or is not finite as a `Float32`.
- A face with fewer than three corners, or a corner with more than three parts.
- A face of four or more corners that is not convex, or has no area. A fan covers a convex polygon and only that.
- An index that is not a whole number, is zero, or names an entry the file does not have.
- A face that names a normal or a texture coordinate where an earlier face of the object did not, or the other way round.

`read_obj` raises for a file it cannot read.

## Example

`assets/cube.obj` is a unit cube with normals and texture coordinates. `tests/test_obj.mojo` reads it and draws it.
