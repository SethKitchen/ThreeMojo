# Curves and paths

`math/curve.mojo`, `math/path.mojo` and `math/curve3.mojo`. A curve is a function from a number between zero and one to a point in the plane or in space. A path is a run of curves that meet end to end. A shape is a closed path with holes in it.

![A tube follows one cubic Bezier curve](out/curves.png)

three.js: `Curve`, `LineCurve`, `QuadraticBezierCurve`, `CubicBezierCurve`, `SplineCurve`, `EllipseCurve`, `ArcCurve`, `CurvePath`, `Path`, `Shape`, `LineCurve3`, `QuadraticBezierCurve3`, `CubicBezierCurve3`, `CatmullRomCurve3`.

## Curve

`Curve(kind, points)` holds a kind and its control points. Every kind is one struct with a tag, because a `Path` must hold a list of one type.

| Kind | Points | What it draws |
|---|---|---|
| `LINE` | 2 | The straight run from the first to the second. |
| `QUADRATIC` | 3 | A Bezier curve pulled toward one control point. |
| `CUBIC` | 4 | A Bezier curve pulled toward two control points. |
| `SPLINE` | 2 or more | A Catmull-Rom curve through every point. |
| `ELLIPSE` | 1, the center | An arc of an ellipse. See [Ellipses and arcs](#ellipses-and-arcs). |

Four functions build the first four kinds and read better at a call site:

```mojo
from math.curve import cubic_bezier, line, quadratic_bezier, spline
from math.vector2 import Vector2

var run = line(Vector2(0, 0), Vector2(4, 0))
var arc = quadratic_bezier(Vector2(0, 0), Vector2(1, 2), Vector2(2, 0))
var bend = cubic_bezier(
    Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
)
var through = spline([Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)])
```

| Member | Meaning |
|---|---|
| `point(t) -> Vector2` | The point at `t`, the curve's own parameter. |
| `tangent(t) -> Vector2` | The unit direction at `t`, from the exact derivative. |
| `sample(divisions) -> List[Vector2]` | `divisions + 1` points at equal steps in `t`. |
| `length() -> Length` | How long the curve is. |
| `lengths(divisions) -> List[Float32]` | How far along each sample is, from zero. |
| `point_at(u) -> Vector2` | The point `u` of the way along by distance. |
| `tangent_at(u) -> Vector2` | The unit direction `u` of the way along by distance. |
| `spaced_points(divisions) -> List[Vector2]` | Points at equal distances along the curve. |

The three.js names are `getPoint`, `getTangent`, `getPoints`, `getLength`, `getLengths`, `getPointAt`, `getTangentAt` and `getSpacedPoints`, in the same order.

### Two parameters

`t` runs from zero to one over the curve's formula. `u` runs from zero to one over its length. They are not the same number.

A Bezier with its control points bunched at one end crawls there and races at the other. Equal steps in `t` give points that bunch up. Equal steps in `u` give points that are equally far apart.

Use `point` and `sample` to draw a curve. Use `point_at` and `spaced_points` to move something along it.

`length` and `point_at` read a table of straight runs across the curve. That table is the only approximation here, and how good it is depends on there being enough runs to follow the curve.

three.js uses 200 for every curve. A Bezier has one arc and 200 runs follow it closely. A spline has one arc per segment. 200 runs across a spline with 400 segments do not sample it sparsely. They land at the same place in every other segment, and measure a curve that is not there. So the count is `ARC_DIVISIONS` or `SEGMENT_SAMPLES` per segment, whichever is larger, and `arc_divisions()` reports it.

### Tangents are exact

three.js measures a tangent across two samples a short step apart. Here every kind has an exact derivative, and `tangent` evaluates it. A Bezier or a spline is a polynomial, and an ellipse is a sine and a cosine.

The reason is precision. These numbers are `Float32`, and subtracting two nearby samples cancels most of the digits they have.

Being exact makes a cusp exact too. A quadratic that starts and ends at one point turns back half way along. There is no direction there, and `tangent` raises rather than returning one that is nearly zero.

### Ellipses and arcs

`ellipse` makes three.js's `EllipseCurve`, and `arc` makes its `ArcCurve`. The radii are a `Length` and the angles are an `Angle`.

```mojo
from math.curve import arc, ellipse
from math.vector2 import Vector2
from std.math import pi
from units.si import Angle, Length, METER, RADIAN

var half = arc(
    Vector2(0, 0),
    Length(1, METER),
    Angle(0, RADIAN),
    Angle(Float32(pi), RADIAN),
)
var oval = ellipse(
    Vector2(1, 2),
    Length(3, METER),
    Length(1.5, METER),
    Angle(0.25, RADIAN),
    Angle(2, RADIAN),
    clockwise=False,
    rotation=Angle(0.5, RADIAN),
)
```

| Argument | Meaning |
|---|---|
| `center` | The middle of the ellipse. |
| `x_radius`, `y_radius` | The radii along the ellipse's own axes. `arc` takes one `radius`. |
| `start`, `end` | The angles the arc runs between, from the ellipse's own x axis. |
| `clockwise` | True to run the way the angle falls. The default is False. |
| `rotation` | How far the ellipse's axes turn, anticlockwise. The default is zero. |

The sweep follows the three.js rule. The difference between the two angles is brought into the range zero through one whole turn. A difference of zero there, from two angles that differ, is a whole turn. A clockwise arc then loses one whole turn, so it runs the other way.

A whole turn ends exactly where it starts. In `Float32`, the three.js formula ends a part in ten million away, and a circle used as an outline does not close.

## Path

`Path` is a pen. It starts somewhere, and every call after that leaves from where the last one stopped.

```mojo
from math.path import Path
from math.vector2 import Vector2

var pen = Path(Vector2(0, 0))
pen.line_to(Vector2(2, 0))
pen.quadratic_to(Vector2(3, 0), Vector2(3, 1))
pen.cubic_to(Vector2(3, 2), Vector2(2, 3), Vector2(0, 3))
pen.close_path()
```

| Member | Meaning |
|---|---|
| `move_to(start)` | Put the pen down. Refused once the path has drawn. |
| `line_to(end)` | Add a `LINE` curve to `end`. |
| `quadratic_to(control, end)` | Add a `QUADRATIC` curve to `end`. |
| `cubic_to(first, second, end)` | Add a `CUBIC` curve to `end`. |
| `spline_thru(points)` | Add a `SPLINE` from here through every point. |
| `abs_arc(center, radius, start, end, clockwise)` | Add an arc about `center`. |
| `abs_ellipse(center, x_radius, y_radius, start, end, clockwise, rotation)` | Add an arc of an ellipse about `center`. |
| `arc(offset, radius, start, end, clockwise)` | Add an arc about a center `offset` from the pen. |
| `ellipse(offset, x_radius, y_radius, start, end, clockwise, rotation)` | Add an arc of an ellipse about a center `offset` from the pen. |
| `close_path()` | Add the straight run back to the start. |
| `is_closed() -> Bool` | True if the path ends where it began. |
| `sample(divisions) -> List[Vector2]` | The whole path as points, `divisions` per curve. |
| `length() -> Length` | The sum of its curves' lengths. |
| `curve_count() -> Int` | How many curves the path is made of. |
| `current() -> Vector2` | Where the pen is. |

`sample` leaves out each curve's first point, because it is where the curve before it ended. A repeated point is a run of no length for whatever reads the list. An ellipse gets twice `divisions` runs, as in three.js.

### Arcs on a path

An arc does not have to start where the pen is. If it starts somewhere else, the path adds a straight run to the start of the arc first. That is the three.js `absellipse` rule.

On an empty path, the path starts where the arc starts, and the pen does not have to be down. A whole circle is then a closed outline:

```mojo
from math.path import Path, Shape
from math.vector2 import Vector2
from std.math import pi
from units.si import Angle, Length, METER, RADIAN

var rim = Path()
rim.abs_arc(
    Vector2(0, 0),
    Length(1, METER),
    Angle(0, RADIAN),
    Angle(Float32(2 * pi), RADIAN),
)
var disc = Shape(rim^)
```

### One run, not several

three.js lets `moveTo` start a second run in the middle of a path. Nothing here can draw that, because a broken outline has no inside. `move_to` is refused once the path has a curve on it, and a second run must be a second path.

## Shape

`Shape` is a closed path with holes. `ShapeGeometry` and `ExtrudeGeometry` are built from one.

```mojo
from math.path import Path, Shape
from math.vector2 import Vector2

var outline = Path(Vector2(0, 0))
outline.line_to(Vector2(4, 0))
outline.line_to(Vector2(4, 4))
outline.line_to(Vector2(0, 4))
outline.close_path()

var hole = Path(Vector2(1, 1))
hole.line_to(Vector2(3, 1))
hole.line_to(Vector2(3, 3))
hole.line_to(Vector2(1, 3))
hole.close_path()

var plate = Shape(outline^)
plate.add_hole(hole^)
```

| Member | Meaning |
|---|---|
| `add_hole(hole)` | Cut a closed path out of the shape. |
| `hole_count() -> Int` | How many holes the shape has. |
| `outline_points(divisions)` | The outline as points. |
| `hole_points(index, divisions)` | One hole as points. |

The winding does not matter. `shape_geometry` turns the outline counter-clockwise and each hole clockwise before it cuts them up.

## Curves in space

`math/curve3.mojo` has `Curve3`, the three.js curves in space. It has the same members as `Curve`, with `Vector3` in place of `Vector2`.

| Kind | Points | Function | three.js |
|---|---|---|---|
| `LINE3` | 2 | `line3(start, end)` | `LineCurve3` |
| `QUADRATIC3` | 3 | `quadratic_bezier3(start, control, end)` | `QuadraticBezierCurve3` |
| `CUBIC3` | 4 | `cubic_bezier3(start, first, second, end)` | `CubicBezierCurve3` |
| `CATMULL_ROM3` | 2 or more | `catmull_rom3(points, closed, curve_type, tension)` | `CatmullRomCurve3` |

```mojo
from math.curve3 import CHORDAL, catmull_rom3
from math.vector3 import Vector3

var track = catmull_rom3(
    [Vector3(0, 0, 0), Vector3(1, 2, 0), Vector3(3, 2, 1), Vector3(4, 0, 2)],
    closed=True,
    curve_type=CHORDAL,
)
var middle = track.point_at(0.5)
```

### Catmull-Rom types

`curve_type` is a `CatmullRomType`. It sets how the spline spaces its points.

| Type | three.js | Spacing |
|---|---|---|
| `CENTRIPETAL` | `'centripetal'` | The square root of the distance between two points. This is the default. |
| `CHORDAL` | `'chordal'` | The distance between two points. |
| `CATMULLROM` | `'catmullrom'` | Even spacing. `tension` sets the pull toward the neighbors. The default is 0.5. |

Use `CENTRIPETAL` for points that are far apart in some places and close in others. The uniform spline makes loops where two points are close.

An open spline has no point before its first point or after its last point. three.js reflects the neighbor through the end to make one. It keeps both of these points in one scratch vector. On a curve of two points, the second overwrites the first. Here each end has its own point, so a curve of two points is a straight run.

### Frames

`frenet_frames(segments, closed)` is the three.js `computeFrenetFrames`. It returns a `FrenetFrames` with `segments + 1` tangents, normals and binormals, at equal distances along the curve.

Parallel transport carries each frame to the next, so the frames do not twist where the curve bends. For a closed curve, the twist that builds up is spread back along the curve, so the last frame meets the first. `transport_frames(tangents, closed)` does this for any list of unit tangents.

### A tube along a curve

`tube(curve, radius, tubular_segments, radial_segments, closed)` in `geometries/tube.mojo` is the three.js `TubeGeometry`. It puts `tubular_segments + 1` rings at equal distances along the curve, in the frames of the curve. The defaults are the three.js defaults: 64 along and 8 around.

```mojo
from geometries.tube import tube
from units.si import Length, METER

var pipe = tube(track, Length(0.1, METER), 64, 8, closed=True)
```

`tube(points, radius, radial_segments, closed)` still takes a list of points. Both forms use the same frames.

`extrude(shape, curve, steps)` sweeps a `Shape` along a `Curve3` or a `CurvePath3` in the same frames. See [Extrude along a path](Geometry#along-a-path).

### CurvePath3

`CurvePath3` is the three.js `CurvePath` for curves in space. As in three.js, nothing makes one curve start where the last one ended.

| Member | Meaning |
|---|---|
| `add(curve)` | Add a curve to the end. |
| `close_path()` | Add a `LINE3` from the end back to the start. |
| `curve_lengths() -> List[Float32]` | The running total of the lengths, one per curve. |
| `length() -> Length` | The whole length. |
| `point(t) -> Vector3` | The point `t` of the way along by distance. |
| `tangent(t) -> Vector3` | The unit direction `t` of the way along by distance. |
| `sample(divisions) -> List[Vector3]` | One run for a line, `divisions` for any other curve. A repeated point is left out. |
| `spaced_points(divisions) -> List[Vector3]` | Points at equal distances along the path. |
| `frenet_frames(segments, closed)` | Frames at equal distances along the path. |

## What is refused

| Mistake | Answer |
|---|---|
| A kind or a Catmull-Rom type that does not exist. | An error at construction. |
| Points that do not match the kind. | An error at construction. |
| Every point the same point. | An error at construction. |
| An ellipse with a radius that is not positive. | An error at construction. |
| An ellipse whose two angles are the same. | An error at construction. |
| A closed `Curve3` that is not a Catmull-Rom spline. | An error at construction. |
| `t` or `u` outside zero through one. | An error. |
| A tangent where the curve turns back. | An error. |
| Fewer than one division. | An error. |
| Drawing before the pen is down. | An error. |
| Moving the pen after it has drawn. | An error. |
| Closing an empty or a closed path. | An error. |
| Frames where two steps point opposite ways. | An error. |
| An open outline or an open hole. | An error. |

three.js clamps `t`, returns an empty list, or builds a shape with no area. Each of those hides a caller that has lost track of the order.

## See also

- [Math](Math) has `Vector2`, which a curve is made of.
- [Geometry](Geometry) fills a `Shape` in, gives it thickness, and sweeps a tube along a curve.
