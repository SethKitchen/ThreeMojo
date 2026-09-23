# Geometry

`core/buffer_geometry.mojo`, `core/buffer_attribute.mojo`, `core/interleaved_buffer.mojo`, `core/geometry_store.mojo` and `geometries/`. A `BufferGeometry` holds named vertex attributes and an optional index. It can compute its own normals and bounds.

Builders make boxes, spheres, planes, circles, rings, cylinders, cones, tori, torus knots, the four regular polyhedra, capsules, lathes and tubes. Two more fill a drawn [shape](Curves) in and give it thickness. One sets [text](#text) in a font and gives it thickness. Four [addon builders](#parametric) make parametric surfaces, convex hulls, decals and rounded boxes. Two more read a surface back as the lines of its edges, and [utilities](#merge-weld-and-tangents) merge, weld and compute tangents.

![A torus knot turns under a lamp](out/geometry.png)

three.js: `BufferGeometry`, `BufferAttribute`, `computeVertexNormals`, `computeBoundingBox`, `computeBoundingSphere`, `BoxGeometry`, `SphereGeometry`, `PlaneGeometry`, `CircleGeometry`, `RingGeometry`, `CylinderGeometry`, `ConeGeometry`, `TorusGeometry`, `TorusKnotGeometry`, `PolyhedronGeometry`, `TetrahedronGeometry`, `OctahedronGeometry`, `IcosahedronGeometry`, `DodecahedronGeometry`, `CapsuleGeometry`, `LatheGeometry`, `TubeGeometry`. Also `ShapeGeometry`, `ExtrudeGeometry` and `ShapeUtils.triangulateShape`. From the addons: `TextGeometry`, `ParametricGeometry`, `ParametricFunctions`, `ConvexGeometry`, `ConvexHull`, `DecalGeometry` and `RoundedBoxGeometry`. Also `toNonIndexed`, `center`, `computeTangents`, `addGroup`, `clone`, and `BufferGeometryUtils.mergeGeometries`, `mergeVertices` and `toCreasedNormals`.

## BufferAttribute

A flat `List[Float32]` with an item size. `BufferAttribute(data, 3)` holds vectors of three floats.

| Member | Meaning |
|---|---|
| `count() -> Int` | The number of items. |
| `component(index, offset) -> Float32` | One float of one item. |
| `vector3(index) -> Vector3` | One item as a vector. Item size must be three. |
| `set_component(index, offset, value)` | Replace one float of one item. |
| `gather(index) -> BufferAttribute` | One copy of an item for each entry of `index`. |
| `packed() -> List[Float32]` | Every float, item after item, with no stride. |
| `clone() -> BufferAttribute` | A copy with an array of its own. |
| `is_interleaved() -> Bool` | Whether it reads a shared buffer. See [Interleaved buffers](#interleaved-buffers). |
| `is_instanced() -> Bool` | Whether it advances per instance. See [Instanced buffer geometry](#instanced-buffer-geometry). |

## BufferGeometry

| Member | Meaning |
|---|---|
| `set_attribute(name, attribute)` | Add or replace an attribute. |
| `attribute_view(name) -> ref BufferAttribute` | Borrow an attribute. Bind it with `ref`. |
| `clone_attribute(name) -> BufferAttribute` | Copy an attribute. |
| `has_attribute(name) -> Bool` | Whether the attribute exists. |
| `set_index(index)` | Set the triangle index. An empty list clears it. |
| `vertex_count() -> Int` | The number of vertices in `position`. |
| `triangle_count() -> Int` | The number of triangles. |
| `corner(triangle, corner) -> Vector3` | A corner position. |
| `corner_index(triangle, corner) -> Int` | Which vertex that corner is. |
| `compute_vertex_normals()` | Set `normal` from the triangles. |
| `bounding_box() -> Box3` | The box around the vertices. |
| `bounding_sphere() -> Sphere` | A sphere around the vertices, centered on that box. |
| `clone() -> BufferGeometry` | A copy that shares nothing. |
| `to_non_indexed() -> BufferGeometry` | A copy in which every triangle owns its corners. |
| `center()` | Move the vertices so that their box is centered on the origin. |
| `compute_tangents()` | Set `tangent` from positions, normals and texture coordinates. |
| `add_group(start, count, material_index)` | Add a run of triangles that wears one material. |
| `clear_groups()` | Remove every group. |
| `stream_length() -> Int` | The index entries, or the vertices without an index. |
| `vertex_at(slot) -> Int` | Which vertex one slot of that stream reads. |
| `set_instance_count(count)` | Set how many instances to draw. |
| `drawn_instances() -> Int` | How many instances a mesh draws. |

Attribute names are the constants `POSITION`, `NORMAL`, `UV`, `UV1`, `COLOR` and `TANGENT`. A geometry needs `position`. It needs `normal` for smooth shading and `uv` for a texture. It needs `color`, three or four linear floats per vertex, for a material with `vertex_colors`. See [Materials](Materials#vertex-colors).

A geometry can carry `uv1`, a second set of coordinates, for a baked map. See [Light map](Materials#light-map).

`compute_vertex_normals` averages the normals of the triangles a vertex is in, weighted by their areas. A shared vertex shades smoothly. A vertex used once shades flat. A vertex no triangle uses keeps a zero normal, as in three.js.

Faces are joined by index, not by position. The two vertices on either side of a texture seam keep separate normals, so a recomputed seamed sphere shows its seam, as in three.js. A builder's own normals are better. Replace them only on purpose.

The bounds are computed each time they are asked for. Nothing is cached. See [Math](Math#box3-sphere-and-plane) for `Box3` and `Sphere`.

## GeometryStore

`assets.geometries.add(geometry)` stores a geometry and returns a `GeometryId`. `get(id)` borrows it. Many meshes share one geometry. See [Meshes and assets](Meshes-and-assets).

## Box

```mojo
var solid = cube(Length(1.0, METER))
var brick = box(Length(2.0, METER), Length(1.0, METER), Length(0.5, METER))
```

A box has twenty-four vertices, four per face. Each face carries its own normal and texture coordinates. The whole image covers each face once.

## Sphere

```mojo
var ball = sphere(Length(1.0, METER), 24, 16)   # segments around, rings down
```

A latitude and longitude sphere. Each normal points away from the center, so shading is smooth. `u` runs once around the equator. `v` runs from one at the north pole to zero at the south pole. It needs at least three segments and two rings.

## Plane

```mojo
var sheet = plane(Length(2.0, METER), Length(1.0, METER))        # one quad
var grid = plane(Length(20.0, METER), Length(20.0, METER), 4, 4)  # sixteen quads
```

A rectangle in the xy plane, facing +z, centered on the origin. The vertex order, winding and texture coordinates match three.js. Turn the node a quarter turn about x to make a floor.

The texture coordinates run once across the rectangle. To tile an image, rewrite the `uv` attribute, as `examples/floor.mojo` does.

## Circle

```mojo
var disk = circle(Length(1.0, METER), 32)                                       # a full disk
var slice = circle(Length(1.0, METER), 8, Angle(90.0, DEGREE), Angle(180.0, DEGREE))  # a pie slice
```

A disk in the xy plane, facing +z, centered on the origin. Vertex zero is the center. The rim follows it, one vertex per segment and one more to close the seam. Each triangle runs from a rim vertex to the next one and back to the center.

The third argument is where the rim starts, counter-clockwise from +x. The fourth is how far it sweeps. A full turn is the default. A shorter sweep makes a pie slice.

The texture coordinates map the square around the disk onto the image. The center is `(0.5, 0.5)`. A pie slice shows its part of the image.

## Ring

```mojo
var washer = ring(Length(0.5, METER), Length(1.0, METER), 32, 1)   # segments around, then across
var arc = ring(Length(0.5, METER), Length(1.0, METER), 16, 1, Angle(0.0, DEGREE), Angle(90.0, DEGREE))
```

A flat ring in the xy plane, facing +z, centered on the origin. The first radius is the hole. The second is the outer edge. Vertices run in rows from the inner edge outwards, one per segment around and one more for the seam. The start angle and the sweep work as they do for the circle. A shorter sweep makes an arc.

The texture coordinates map the square around the outer edge onto the image, as the circle's do.

An inner radius of zero makes a disk, as in three.js. The inner row is then every vertex at the center.

## Cylinder

```mojo
var can = cylinder(Length(1.0, METER), Length(1.0, METER), Length(2.0, METER), 32, 1)  # top radius, bottom radius, height
var bucket = cylinder(Length(0.8, METER), Length(1.2, METER), Length(2.0, METER))
var pipe = cylinder(Length(1.0, METER), Length(1.0, METER), Length(2.0, METER), 32, 1, open_ended=True)
```

A cylinder stands on the y axis, centered on the origin. The first radius is at the top and the second at the bottom. Different radii make a frustum. The side comes first, in rows from the top down, one vertex per segment around and one more for the seam. A cap follows at each end unless `open_ended` is true. Each cap has one center vertex per segment, as in three.js.

The side's triangles come column by column, in three.js's order. The caps are the only closing faces. A partial sweep leaves its two cut faces open, as in three.js.

Side normals lean with the side, so a frustum shades smoothly. Cap normals point along the axis. `u` runs once around the side. `v` runs from one at the top to zero at the bottom. Each cap maps the square around it onto the image.

The sweep starts at +z and runs toward +x, as in three.js. The circle starts at +x instead. A shorter sweep makes a section with open sides.

## Cone

```mojo
var spike = cone(Length(1.0, METER), Length(2.0, METER), 32)
```

A cone is a cylinder with a top radius of zero. Its point is at +y. The point has one vertex per segment, each with its own normal. A cylinder with a bottom radius of zero is a cone the other way up. An end with no radius gets no cap.

## Torus

```mojo
var ring = torus(Length(2.0, METER), Length(0.5, METER), 12, 48)   # radius, tube, around the tube, along it
var bend = torus(Length(2.0, METER), Length(0.5, METER), 12, 48, Angle(90.0, DEGREE))
```

A tube bent around a circle in the xy plane, centered on the origin. The first radius runs from the center to the middle of the tube. The second is the tube's own. Vertices run in rows, one row per step around the tube, one vertex per step along it and one more for the seam. Each normal points away from the middle of the tube, so the shading is smooth. `u` runs along the tube and `v` around it.

The arc runs from +x toward +y. A full turn is the default. A shorter arc makes a bent pipe with open ends.

## Torus knot

```mojo
var trefoil = torus_knot(Length(2.0, METER), Length(0.4, METER), 64, 8, 2, 3)   # radius, tube, along, around, p, q
```

A tube bent around a knot that winds `p` times around the axis and `q` times through the hole. The curve is three.js's. It lies between half and one and a half of the radius from the axis. Vertices run in rings along the curve, one vertex per step around the tube and one more for the seam. Each ring is built in three.js's frame, so a texture lands as it does there.

## Polyhedra

```mojo
var die = tetrahedron(Length(1.0, METER))
var gem = octahedron(Length(1.0, METER))
var ball = icosahedron(Length(1.0, METER), 3)       # detail three: a geodesic sphere
var dome = dodecahedron(Length(1.0, METER))
var own = polyhedron(vertices, indices, Length(1.0, METER), detail)
```

A polyhedron is a list of vertices and a list of triangles over them. Every vertex is pushed out to the radius. `detail` cuts each edge that many times, so each face becomes `(detail + 1)` squared triangles, on the way to a sphere. The four regular solids have three.js's vertices and faces in three.js's order.

The geometry is not indexed. Each triangle owns its three vertices. At a detail of zero the normals are flat, one per face. At a detail of one or more each normal points away from the center.

Texture coordinates are longitude and latitude, with the seam repaired per face as three.js repairs it. `v` is one at the top pole and zero at the bottom, as on the sphere. A coordinate can exceed one on a face that straddles the seam.

## Capsule

```mojo
var pill = capsule(Length(0.5, METER), Length(2.0, METER), 4, 16)   # radius, length, cap rows, around
```

A cylinder with a hemisphere on each end, standing on the y axis and centered on the origin. The length is the straight side between the caps. A length of zero is a sphere with one rim, not two. Vertices run in columns, one per step around, from the bottom pole to the top.

`u` runs around. `v` runs up the profile by distance along it, from zero at the bottom pole to one at the top. A texture stays put when the segment counts change.

The normals come from the profile exactly. On a cap they run along its radius, and on the side straight out. The caps and the side meet without a crease. The half of each cell against a pole that has no area is left out.

The sweep starts at +z, as the cylinder's does. three.js's current builder starts at -x and gives its pole vertices a half-step `u`. The shape is the same. A texture lands a quarter turn on.

## Lathe

```mojo
var vase = lathe(points, 24)                                        # a profile of Vector2, cells around
var half = lathe(points, 24, Angle(0.0, DEGREE), Angle(180.0, DEGREE))
```

A profile revolved around the y axis. Each point has `x` out from the axis and `y` along it, in meters. Vertices run in columns, one per step around, one vertex per point.

The normals come from the profile's segments, as in three.js. A corner faces the sum of its two segments' normals, each as long as its segment, made unit length. A longer segment pulls the corner its way. The first and last points face the way their own segment does.

A point on the axis is a pole. The half of each cell against it that has no area is left out. `u` runs around and `v` up the profile, one point per equal step. The sweep starts at +z, as the cylinder's does.

## Tube

```mojo
var pipe = tube(path, Length(0.2, METER), 8)                         # a path of Vector3, cells around
var loop = tube(path, Length(0.2, METER), 8, closed=True)
```

A tube of one radius swept along a path of points. Each point gets a ring, built in a frame that follows the path. The frames are three.js's parallel transport, so the tube does not twist where the path only bends. A closed path is given without repeating its first point. Its last ring repeats its first, and the twist the path built up is spread evenly back along it.

three.js samples its path from a curve. There are no curve types here yet, so the path is the points. `u` runs along the path by distance, the closing segment included. `v` runs around the tube.

## Shape

```mojo
var flat = shape_geometry(plate)                    # twelve runs a curve
var flat = shape_geometry(plate, 32)                # a finer sample
```

A [shape](Curves) filled in: a flat surface in the plane where z is zero, facing the positive z axis. The outline and its holes are sampled into points, and the points are cut into triangles. The texture coordinate of a vertex is the vertex, which is three.js's default generator.

Every other builder here is a grid. A shape is not, and cutting one up is the whole of `geometries/shape.mojo`.

### How it is cut up

By ear clipping. A corner of a loop is an ear when the triangle it makes with its two neighbors lies inside the loop. That triangle must hold no other corner. Clip that triangle off, and the loop has one corner fewer. Every simple loop has an ear at every step, so this always finishes.

A hole is a separate loop, and ear clipping knows one loop. So each hole is seamed into the outline first. Two points that can see each other are joined. The outline then runs out along that line, around the hole and back. Two points see each other when the line between them crosses no edge of the outline and no edge of any hole.

three.js casts a ray from the hole's rightmost point and fixes the cases that go wrong. This takes the shortest pair that can see each other, which has no cases to fix.

### Corners in a line are dropped

A straight edge sampled into eight runs leaves seven corners that turn by nothing. None of them can be an ear, so the clipping would stop with a row of them left. They describe one edge, and `triangulate` says so once.

`triangulate(shape, curve_segments)` returns the points, the triangles and where each contour starts, for a caller that needs more than a flat surface. `extrude` is that caller.

## Extrude

```mojo
var solid = extrude(plate, Length(2, METER))
var solid = extrude(plate, Length(2, METER), steps=4)
var solid = extrude(
    plate,
    Length(2, METER),
    bevel_enabled=True,
    bevel_thickness=Length(0.2, METER),
    bevel_size=Length(0.1, METER),
    bevel_segments=3,
)
```

A shape given thickness along the z axis, from zero to `depth`. The shape is filled in twice, once at each end, and every edge of every contour becomes a wall between them. A hole becomes a shaft through the solid.

The vertices are built in layers, each holding every contour point once at one height. `steps` cuts the walls up without changing the solid.

### The bevel

A bevel rounds the two edges off. It adds `bevel_segments` layers at each end. They reach `bevel_thickness` past the end face, and stand `bevel_size` out from the outline, by the sine and the cosine of a quarter turn.

three.js measures a bevel *out* from the shape drawn, and so does this. The two end faces are the outline itself, and the body between them stands proud of it all the way round. `bevel_offset` moves every layer out before the bevel is measured, the end faces included, which makes a lip rather than rounding an edge.

A corner sharper than a right angle is not drawn out to a spike. three.js's `getBevelVec` keeps the exact miter while it is no longer than the square root of two bevel widths. It shrinks a longer one to that length, and so does this. A corner whose edges fold straight back moves along its incoming edge by the same length.

A corner moves along its miter, the line that keeps both of its edges parallel to where they were.

### The faces are flat

An extrusion has no index buffer, and its normals come from its triangles, so every vertex belongs to one face. A bevel of three segments is three flat bands. three.js does the same, and for the same reason: two walls that meet at a corner do not agree about the texture coordinate there.

A wall is measured along x or along y, whichever it runs further in, and up the negative of z. That is three.js's own generator.

### Along a path

```mojo
var rail = extrude(plate, curve, steps=32)                # a Curve3
var rail = extrude(plate, path, steps=32)                 # a CurvePath3
```

A shape swept along a curve in space. This is the three.js `ExtrudeGeometry` with an `extrudePath`.

The layers stand at `steps + 1` equal distances along the curve. Each layer is placed in the [Frenet frame](Curves#frames) of the curve at that point. The x of a shape point runs along the normal of the frame, and its y runs along the binormal. The back cap is at the start of the curve, and the front cap faces on along the curve at its end.

This form has no bevel and no depth. three.js turns the bevel off when it gets a path, and the curve gives the length. The texture coordinates come from the same world generator, read from the swept vertices.

A wall between two frames that turn is not flat. So the diagonal that splits a quad changes the surface. Both forms split each quad across its second and fourth corners, as the three.js `f4` does.

The tests compare every triangle with the output of three.js 0.180 for a Bezier curve and for a path of two lines.

## Text

```mojo
from geometries.text import text_geometry
from loaders.font import read_font

var font = read_font("assets/fonts/fixture.typeface.json")
var sign = text_geometry("AO i8", font, Length(1, METER), Length(0.2, METER))
var bold = text_geometry(
    "A\nD",
    font,
    Length(1, METER),
    Length(0.2, METER),
    bevel_enabled=True,
    bevel_thickness=Length(0.02, METER),
    bevel_size=Length(0.01, METER),
)
```

`text_geometry` sets text in a [font](Model-files#fonts) and gives it thickness. This is the three.js `TextGeometry`.

The font lays the text out as shapes, with `Font.generate_shapes`. `extrude` gives each shape its depth, with the same options as [Extrude](#extrude). The parts are joined end to end, one shape after another, which is the order three.js writes them in.

`size` is one em, and `depth` runs along z from zero. Both are a `Length`. The defaults are from three.js: a size of 100 meters and a depth of 50 meters. A bevel is 10 meters thick and 8 meters out. Set `size` to the height you want.

A text with nothing to draw, such as spaces, gives a geometry with empty `position`, `normal` and `uv` attributes. The options are checked all the same.

three.js adds two groups to each shape, one for the caps and one for the walls. `extrude` writes no groups, so a text has none.

The tests compare the vertex count and the bounding box with three.js 0.180, with and without a bevel.

## Parametric

```mojo
from geometries.parametric import SurfaceFunction, klein, parametric

var bottle = parametric(SurfaceFunction[klein]())            # 8 slices, 8 stacks
var sheet = parametric(SurfaceFunction[my_function](), 24, 12)
var dome = parametric(Dome(Float32(2)), 24, 12)              # a struct that holds a radius
```

A grid sampled from a function of `u` and `v`, each from zero to one. The function returns a point in meters. There are `slices` cells along `u` and `stacks` cells along `v`, and each cell is two triangles. The texture coordinate of a vertex is its `(u, v)`.

The surface is a type, not a closure. Any struct that implements `ParametricSurface` is a surface: it has `point(self, u, v) -> Vector3`. `SurfaceFunction[f]` makes a surface from a plain function `def f(u: Float32, v: Float32) -> Vector3`. A surface that needs its own numbers is a struct that holds them.

The normals are three.js's finite differences. A vertex asks for a second point `EPS` away along `u`, and a third along `v`. The normal is the cross product of the two differences, made unit length. At the first row and column the step goes forward, so the function never gets a negative number.

The arithmetic is `Float32`, and three.js uses `Float64`. A step of `1e-5` in `Float32` loses digits, so a normal can differ from three.js by a few parts in a thousand. The positions agree.

`klein`, `mobius`, `mobius3d` and `parametric_plane` are three.js's `ParametricFunctions`. `klein` swaps the names of its arguments, as three.js does.

## Convex hull

```mojo
from geometries.convex import convex
from math.convex_hull import ConvexHull

var pebble = convex(points)                  # a List[Vector3]
var hull = ConvexHull(points)
var inside = hull.contains_point(Vector3(0, 0, 0))
```

`convex` returns the smallest convex solid that holds every point. Points inside it are left out. Each face is a triangle with three vertices of its own, and all three carry the face's normal. So the hull shades flat. There is no index and no texture coordinate, as in three.js.

`ConvexHull` is three.js's quickhull, step by step. It starts from a tetrahedron of four extreme points. It adds the farthest point that a face can see, again and again, until no face can see a point.

| Member | Meaning |
|---|---|
| `face_count() -> Int` | The number of triangles. |
| `face_vertex(face, corner) -> Int` | Which input point is at one corner. |
| `face_normal(face) -> Vector3` | The outward unit normal of one face. |
| `contains_point(point) -> Bool` | Whether no face can see the point. |
| `tolerance` | How far outside a face a point must be before the face can see it. |

The hull does its arithmetic in `Float64`, as JavaScript does. The tolerance is three.js's: three times the `Float64` epsilon, times the size of the point set. Coplanar faces are not merged, as in three.js.

three.js returns an empty hull for fewer than four points. It returns a flat or broken hull for points on one line or one plane. This port raises in all three cases. `setFromObject` and `intersectRay` are not ported.

## Decal

```mojo
from geometries.decal import decal

var sticker = decal(
    head_geometry,
    scene.world_matrix(head_node),
    Vector3(0.1, 1.6, 0.2),                                 # the center of the box
    Euler(Angle(0, DEGREE), Angle(30, DEGREE), Angle(0, DEGREE), XYZ),
    Length(0.2, METER),                                     # width, along the box's x
    Length(0.2, METER),                                     # height, along its y
    Length(0.3, METER),                                     # depth, along its z
)
```

The part of a mesh inside a box, with texture coordinates from the box. The box is the projector. It stands at a position with an orientation, and it projects the image along its own z axis. `u` runs across its width and `v` across its height.

Each triangle of the mesh moves into the frame of the box. Then it is cut against the six faces of the box, in three.js's order. A triangle with one corner outside a face becomes two triangles. A triangle with two corners outside becomes one. A triangle with three corners outside is dropped.

A new corner gets the normal that is the same blend of the two ends' normals. three.js does not make that normal unit length again, and this port does not.

The result is in world space, as in three.js. Put it on a mesh with no transform. Draw it with a polygon offset, or it fights the surface under it for depth.

The mesh's normals are carried through its normal matrix when it has them. The result has no `normal` attribute when the mesh has none, or when nothing is inside the box. three.js takes a `Mesh`. This port takes the geometry and the world matrix, because a mesh here holds ids and the scene holds its matrix.

## Rounded box

```mojo
from geometries.rounded_box import rounded_box

var soft = rounded_box(Length(2, METER), Length(1, METER), Length(1, METER))   # 2 segments, 0.1 m radius
var pill = rounded_box(Length(1, METER), Length(1, METER), Length(1, METER), 4, Length(0.5, METER))
```

A box with rounded edges and corners, centered on the origin: three.js's `RoundedBoxGeometry` addon. `segments` is the number of cells round each edge. `radius` is the radius of the edges. A radius larger than half the shortest side is cut down to that half.

The builder starts from a unit box with `2 * segments + 1` cells each way on every face. Each vertex gets a normal from the center of that box, pulled half a cell in on each axis. The vertex moves to the corner of a box smaller by the radius, plus the radius along the normal. The middle band of each face stays flat.

The texture coordinates are three.js's. They measure the arc of each rounded edge and the flat band between, so a texture is not squeezed where the surface bends.

The geometry has no index. It has six groups, one for each face, in three.js's order: right, left, top, bottom, front, back. This order is not the order of `box`.

three.js returns a unit box for zero segments, whatever the size. This port raises.

## Edges and wireframes

`geometries/edges.mojo` reads a surface of triangles and gives back a geometry of points, two per segment. Draw it with a [`Line`](Lines) in `SEGMENTS` mode.

```mojo
from geometries.edges import edges_geometry, wireframe_geometry
from objects.line import Line, SEGMENTS

var outline = assets.geometries.add(edges_geometry(cube(Length(1, METER))))
scene.add_line(Line(outline, ink, node, mode=SEGMENTS))
```

| Builder | What it keeps |
|---|---|
| `wireframe_geometry(geometry)` | Every edge, once each. |
| `edges_geometry(geometry, threshold)` | The edges that show the shape. |
| `triangle_edges(geometry)` | Each edge once, paired by vertex index. |
| `welded_points(geometry)` | Which welded point each vertex stands on. |

`edges_geometry` keeps an edge when the two faces meeting at it turn by at least `threshold`, and when it has one face and no neighbor. A cube keeps its twelve edges and drops the diagonal across each face. `threshold` is one degree unless said otherwise, as three.js defaults `thresholdAngle`.

`triangle_edges` is what a [wireframe material](Materials#wireframe) draws. It pairs by vertex index rather than by welded position, as three.js pairs the two rules. A wireframe is drawn from the mesh's own vertices, and two indices that stand at one place are still two vertices with their own colors. A cube has thirty edges by index and eighteen by position.

`edges_geometry` finds creases and boundaries, not silhouettes. It is given no camera, and its answer does not move when one does. What it keeps of a sphere depends on how finely the sphere is divided. Twenty-four segments turn fifteen degrees a facet, so the default threshold keeps most of those edges rather than none.

The comparison is inclusive. An edge turning exactly as far as the threshold is kept. `ANGLE_SLACK` is what makes that true in practice. An `Angle` holds radians as a `Float32`, so an authored 90 degrees has a cosine of −4.37e−8 rather than zero. Two perpendicular faces give a dot product of exactly zero. Without the slack a cube asked for its right angles lost all twelve.

### Welding first

Both weld by position before they pair. Two triangles that meet along an edge often hold two copies of each of its ends. A corner carries a normal and a texture coordinate as well as a position, and the two faces disagree about those. Pairing by vertex index would then find no shared edge anywhere.

`WELD` is the tolerance: a tenth of a millimeter, in meters. It is a distance and not a fraction, which is the bargain three.js makes with its four-decimal position hash. A geometry built at a scale far from one meter has to be welded at its own scale, and neither library does that for you.

A welded cube has eighteen unique edges, not thirty-six: twelve around the shape and one diagonal in each face.

## Merge, weld and tangents

`geometries/utils.mojo` holds three.js's `BufferGeometryUtils`. Three more operations are methods of `BufferGeometry`, as in three.js.

```mojo
from geometries.utils import merge_geometries, merge_vertices, to_creased_normals

var parts = List[BufferGeometry]()
parts.append(cube(Length(1, METER)))
parts.append(sphere(Length(1, METER), 24, 16))
var both = merge_geometries(parts, use_groups=True)

var welded = merge_vertices(loose)                          # tolerance 1e-4
var creased = to_creased_normals(welded, Angle(30.0, DEGREE))
creased.compute_tangents()
creased.center()
```

| Function | What it does |
|---|---|
| `merge_geometries(geometries, use_groups)` | Joins parts into one geometry. |
| `merge_vertices(geometry, tolerance)` | Welds vertices that agree on every attribute, and adds an index. |
| `to_creased_normals(geometry, crease_angle)` | Smooths normals across gentle edges and keeps creases sharp. |
| `geometry.to_non_indexed()` | Gives every triangle its own three corners. |
| `geometry.center()` | Centers the bounding box on the origin. |
| `geometry.compute_tangents()` | Writes a four-number `tangent` for normal maps. |

### Merge

`merge_geometries` joins the attributes end to end, in the first part's order. It moves each part's index entries past the vertices of the parts before it. It joins morph targets target by target. All parts must be indexed, or none. They must carry the same attributes, with the same item sizes, and the same morph targets.

With `use_groups`, the result gets one group per part, and part `i` wears material index `i`. The parts' own groups are not kept, as in three.js.

### Groups

A group is a run of the triangle stream that wears one material: three.js's `addGroup`. `start` and `count` count index entries, or vertices for a geometry without an index. `MaterialIndex` is a position in a list of materials. It is a type, so a bare integer cannot stand in for it.

The renderer draws a mesh in one material. It does not read groups yet. `merge_geometries` writes them and `compute_tangents` reads them.

### Weld

`merge_vertices` scales every number of every attribute by one over the tolerance, and truncates it. Two vertices whose numbers all give the same keys are one vertex. Normals and texture coordinates count, so a cube keeps its twenty-four vertices. The same cube with positions only welds into eight.

The rounding is three.js's own. A number is moved by half a step and truncated toward zero, as JavaScript's `~~` does. Two numbers less than a step apart can fall either side of a boundary and stay apart, in three.js and here.

The tolerance is a plain number and not a `Length`. It applies to every attribute in that attribute's own units. A tolerance of zero is raised to `EPSILON`, as in three.js. The morph targets move with the kept vertices, but they do not decide what welds.

A key is clamped to `KEY_LIMIT`, nine times ten to the eighteenth. JavaScript's `~~` wraps at two to the thirty-first instead. The two differ only for a tolerance far below any real one.

The result is indexed. Its index must hold whole triangles, so a geometry of loose points that is not a multiple of three raises.

### Creased normals

`to_creased_normals` makes the geometry non-indexed first. Many triangles can meet at the position of a corner. The corner's normal is the sum of the normals of those that turn from its own triangle by less than the crease angle. The crease angle is sixty degrees unless you give another, as in three.js.

Positions are matched by key, not by distance. The key is each coordinate times one hundred, truncated, as in three.js. Points closer than about a centimeter share a key, whatever the scale of the geometry.

The triangles are summed one by one, and a face of two triangles can count once or twice at a corner. So a rounded cube corner leans toward some faces more than others. three.js gives the same result.

three.js changes a geometry without an index in place and returns it. This port returns a new geometry and leaves the one you give alone.

### Non-indexed

`to_non_indexed` reads every attribute and every morph target through the index. A vertex that four triangles share becomes four vertices. The groups do not change, because an index entry and a vertex of the result count the same. three.js returns the geometry itself when it has no index. This port returns a copy.

### Center

`center` moves the positions so that the bounding box is centered on the origin. Normals and tangents are directions, and a move does not turn them.

Morph targets that hold finished positions move with the base, so a worn target lands in the same place on the shape. three.js moves the base and leaves those targets behind. Targets that hold offsets do not move, because an offset is the same wherever the shape is.

### Tangents

`compute_tangents` is three.js's `computeTangents`, step for step. Each triangle gives the directions in which `u` and `v` grow across it. They are added at its three corners. At each vertex the `u` sum is made square to the normal and unit length.

The fourth number is the handedness. It is minus one where the `v` sum points against the normal crossed with the `u` sum, and one otherwise. A mirrored texture needs it.

A triangle whose texture coordinates have no area gives no direction, and is skipped. A vertex that no triangle uses gets four zeros. With groups, only the triangles in the groups are visited, as in three.js.

three.js refuses a geometry without an index. This port reads one three corners at a time, as the renderer does. It is three.js's `computeTangents` and not MikkTSpace: three.js's `computeMikkTSpaceTangents` needs a WebAssembly module and is not ported.

## Morph targets

```mojo
var head = sphere(Length(1.0, METER), 24, 16)
head.add_morph_target(smiling)                 # a BufferAttribute of positions
head.add_morph_target(frowning, frown_normals) # positions and normals

var face = Mesh(assets.geometries.add(head^), skin, node)
face.set_morph_influence(0, 0.7)               # seven tenths of a smile
```

A morph target is a second set of positions for the same vertices. The mesh gives each one a weight, and the vertex drawn is the base vertex moved toward the targets by their weights. That is how a face smiles: one geometry, one target per expression, and a number per expression.

three.js: `BufferGeometry.morphAttributes`, `Mesh.morphTargetInfluences`, `morphTargetsRelative`.

| Member | Meaning |
|---|---|
| `geometry.add_morph_target(positions)` | Add a target that moves vertices only. |
| `geometry.add_morph_target(positions, normals)` | Add one that turns them too. |
| `geometry.morph_count() -> Int` | How many targets the geometry carries. |
| `geometry.has_morph_normals() -> Bool` | Whether the targets carry normals. |
| `geometry.morph_relative` | Whether a target holds destinations or offsets. |
| `mesh.set_morph_influence(target, weight)` | How much of one target to wear. |
| `mesh.morph_influence(target) -> Float32` | What it is wearing. |
| `mesh.is_morphed() -> Bool` | Whether any target is worn at all. |

The targets live on the geometry and the weights live on the mesh. That is what lets two meshes share one head and pull different faces. It is the same split that puts `position` on the geometry and the transform on the node.

### Targets add, they do not compound

Every target is measured from the *unmorphed* vertex, so wearing two of them at half each lands half way between both. Measuring each from where the last one left it would land somewhere neither names.

### Destinations or offsets

`morph_relative` is three.js's `morphTargetsRelative`. False, the default, means a target holds the finished positions and the mesh moves from the base toward them. True means it holds the offsets to add. Exporters write both.

### Normals

Either every target carries normals or none does. A geometry whose targets carry none keeps the base normal however far the positions move, which is what three.js's shader does when `morphAttributes.normal` is absent.

### What is drawn is what is picked

`core/deform.mojo` answers where a vertex is once its targets are worn, and both the renderer and the [raycaster](Raycasting) ask it. They did not always. Rendering wore the targets and picking did not, so a morphed mesh was drawn in one place and clicked in another.

### A worn mesh is not culled

A mesh wearing a target is not where its geometry's bounding sphere says it is, so the renderer does not measure it against the frustum. three.js culls it anyway, and clips morphed meshes at the edge of the view for exactly this reason.

Eight targets is this port's ceiling, not three.js's. Older three.js had the same number, from how many attribute slots a WebGL program has. Current three.js passes its targets in a texture and is bounded by memory. Eight is here because a mesh holds its weights in a fixed row rather than a list, which is what keeps a `Mesh` copyable.

## Interleaved buffers

```mojo
var buffer = InterleavedBuffer(numbers^, 8)            # 8 floats a vertex
geometry.set_attribute(POSITION, BufferAttribute(buffer, 3, 0))
geometry.set_attribute(NORMAL, BufferAttribute(buffer, 3, 3))
geometry.set_attribute(UV, BufferAttribute(buffer, 2, 6))
```

An interleaved buffer holds the attributes of a vertex side by side in one array. The stride is the number of floats one vertex takes. Each attribute on the buffer gives its item size and its offset in that run. Item `i` starts at float `i * stride + offset`.

three.js: `InterleavedBuffer`, `InterleavedBufferAttribute`.

| Member | Meaning |
|---|---|
| `InterleavedBuffer(array, stride)` | A buffer that advances per vertex. |
| `buffer.count() -> Int` | The number of runs of `stride` floats. |
| `buffer.value(at)`, `buffer.set_value(at, value)` | Read or write one float of the array. |
| `buffer.shares_with(other) -> Bool` | Whether two handles name one array. |
| `buffer.clone() -> InterleavedBuffer` | A buffer with a copy of the floats. |
| `BufferAttribute(buffer, item_size, offset)` | An attribute that reads the buffer. |
| `attribute.interleaved_buffer()` | A handle on the buffer, three.js's `data`. |
| `attribute.offset()`, `attribute.stride()` | Where an item starts in its run, and the run length. |

An interleaved attribute is a `BufferAttribute`, not a second type. `count`, `component`, `vector3` and `set_component` use the stride. So every reader works without a change: the renderer, the raycaster, the morph and skin evaluators, the utilities and the exporters.

### One array, many handles

A copy of an `InterleavedBuffer` is a second handle on the same floats, as a JavaScript reference is. A write through one attribute shows through every other attribute on the buffer. `clone` copies the floats.

A copy of an interleaved attribute also shares the buffer. `clone_attribute` and `attribute.clone()` give a plain attribute with its own array, as three.js's `clone()` does. `BufferGeometry.clone` copies each buffer once, so attributes that shared a buffer share the copy.

`data` is empty on an interleaved attribute. Read `packed()` to get the floats in item order. `to_non_indexed`, `gather` and the merge utilities give plain attributes.

### The loaders and the exporters

The [JSON loader](Scene-JSON) reads `interleavedBuffers` and `arrayBuffers` as three.js writes them. Attributes that name one buffer share it. The glTF loader reads a strided buffer view into plain attributes.

The exporters write an interleaved attribute as its own floats. three.js does the same when it writes one attribute alone. The file then has no shared buffer, but the values are the same.

## Instanced buffer geometry

```mojo
var grass = BufferGeometry(instanced=True)             # InstancedBufferGeometry
grass.set_attribute(POSITION, blade_positions^)
grass.set_attribute("offset", BufferAttribute(offsets^, 3, mesh_per_attribute=1))
grass.set_attribute(COLOR, BufferAttribute(colors^, 3, mesh_per_attribute=1))
scene.add_mesh(Mesh(assets.geometries.add(grass^), paint, node))
```

An instanced geometry is drawn once for each instance. A per-instance attribute advances once for each instance, not once for each vertex. `mesh_per_attribute` is the number of instances in a row that read one item.

three.js: `InstancedBufferGeometry`, `instanceCount`, `InstancedBufferAttribute`, `InstancedInterleavedBuffer`, `meshPerAttribute`.

| Member | Meaning |
|---|---|
| `BufferGeometry(instanced=True)` | An instanced geometry. |
| `geometry.set_instance_count(count)` | Draw `count` instances. |
| `geometry.instance_count` | The count, or none for as many as the attributes hold. |
| `geometry.drawn_instances() -> Int` | How many instances a mesh draws. |
| `BufferAttribute(data, item_size, mesh_per_attribute=n)` | A per-instance attribute. |
| `InterleavedBuffer(array, stride, mesh_per_attribute=n)` | A per-instance interleaved buffer. |

### What each instance reads

A mesh draws the instances. Each instance is a separate draw, so it is sorted and culled at its own place. The renderer reads two per-instance attributes:

- `offset` moves each instance before the mesh's transform. three.js has no built-in `offset`. Its instancing examples add one in their own shader, and this port does the same work without a shader.
- `color` colors each instance when the material has `vertex_colors`. That is three.js's behavior for a divided `color` attribute.

A per-instance `position`, `normal`, `uv` or `tangent` is refused when drawn. The renderer has no shader that reads them per instance. A draw that is not an instance reads the first per-instance color, as WebGL does.

### How many instances

`drawn_instances` is the instance count, capped by what the per-instance attributes hold. Each attribute holds `count() * mesh_per_attribute()` instances. The cap is the smallest of these. three.js takes the cap from the first attribute its shader reads, which a port without shaders cannot ask. An unbounded count with no per-instance attribute is refused.

### Where this port differs

- A line and points draw an instanced geometry once, not once per instance. Only a mesh draws the instances.
- The raycaster tests the base geometry, as three.js does. It does not test each instance.
- `to_non_indexed` keeps the per-instance attributes as they are. three.js reads them through the index.
- `merge_geometries` and `merge_vertices` refuse an instanced geometry.
- The JSON loader reads `instanceCount` and `meshPerAttribute`. three.js's loader leaves both at their defaults.
- A clone of an instanced attribute keeps its instancing.

## Errors

- A negative or zero extent raises.
- A sphere with too few segments or rings raises.
- A plane with fewer than one segment raises.
- A circle needs a positive radius and at least three segments.
- A ring needs an inner radius of zero or more, a larger outer radius, three segments around and one across.
- A cylinder needs a positive height, radii that are not negative and not both zero, three segments around and one down the side.
- A cone needs a positive radius and a positive height.
- A torus needs positive radii and three segments each way.
- A torus knot needs positive radii, three segments each way, and `p` and `q` of at least one.
- A polyhedron needs a positive radius, a detail of zero or more, whole vertices and faces, and faces that name vertices it has.
- A capsule needs a positive radius, a length of zero or more, one cap row, three segments around and one row up its side.
- A lathe needs at least two points, one segment, and a sweep of at most one turn. No point can have a negative `x`, and no two consecutive points can be the same. A profile that turns straight back to the point before raises, because that corner has no normal.
- A tube needs at least two points, or three when closed, no two consecutive the same, a positive radius and three segments around. A path that returns to the point before the last raises, because that tangent is zero. A path that folds straight back on itself raises, because there is no axis to turn the frame about.
- A sweep must be positive and at most one turn.
- A morph target must cover every vertex, three numbers each, and a geometry holds at most eight.
- Either every morph target carries normals or none does.
- A morph influence must be a number, and there are eight of them.
- A shape's contour needs three corners and an area. A contour drawn in a line, or out and back, has neither.
- A shape's hole must lie inside its outline, and not inside another hole.
- An outline that crosses itself raises, because it has no inside and runs out of ears.
- An extrusion needs a positive depth, one step and one curve segment. A bevel needs a positive thickness, a size that is not negative, and one band.
- A text needs the same options as an extrusion and a positive size. Every character needs a glyph, or the font needs a `?` glyph.
- An extrusion along a path needs one step, one curve segment and a curve path with one curve. The curve must have a frame at each step.
- A parametric surface needs one slice and one stack, and its function must give finite points.
- A convex hull needs four finite points, not all on one point, one line or one plane.
- A decal needs positive extents. A mesh with normals needs a world matrix that does not flatten a dimension.
- A rounded box needs positive extents, one segment and a radius that is not negative.
- An index entry beyond the last vertex raises.
- A group needs a start and a count that are not negative, and a material index of zero or more.
- A merge needs one geometry at least. The parts must all be indexed or none, and carry the same attributes, item sizes and morph targets.
- A weld tolerance must be finite and not negative. A crease angle must be finite and not negative.
- `compute_tangents` needs `position`, `normal` and `uv`.
- A slot outside the triangle stream raises.
- `compute_vertex_normals`, `bounding_box` and `bounding_sphere` raise on a geometry with no positions.
- An interleaved buffer needs a positive stride and whole runs of it. An interleaved attribute needs a positive item size and an item inside the stride.
- A per-instance attribute or buffer needs a `mesh_per_attribute` of one or more.
- An instance count cannot be negative, and only an instanced geometry has one. An instanced geometry needs a count or a per-instance attribute.
- The renderer refuses a per-instance `position`, `normal`, `uv` or `tangent`.
- A merge and a weld refuse an instanced geometry.
