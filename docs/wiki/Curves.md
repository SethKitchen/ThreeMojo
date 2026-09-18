# Curves and paths

`math/curve.mojo` and `math/path.mojo`. A curve is a function from a number between zero and one to a point in the plane. A path is a run of curves that meet end to end. A shape is a closed path with holes in it.

three.js: `Curve`, `LineCurve`, `QuadraticBezierCurve`, `CubicBezierCurve`, `SplineCurve`, `CurvePath`, `Path`, `Shape`.

## Curve

`Curve(kind, points)` holds a kind and its control points. Every kind is one struct with a tag, because a `Path` must hold a list of one type.

| Kind | Points | What it draws |
|---|---|---|
| `LINE` | 2 | The straight run from the first to the second. |
| `QUADRATIC` | 3 | A Bezier curve pulled toward one control point. |
| `CUBIC` | 4 | A Bezier curve pulled toward two control points. |
| `SPLINE` | 2 or more | A Catmull-Rom curve through every point. |

Four functions build the four kinds and read better at a call site:

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
| `spaced_points(divisions) -> List[Vector2]` | Points at equal distances along the curve. |

### Two parameters

`t` runs from zero to one over the curve's formula. `u` runs from zero to one over its length. They are not the same number.

A Bezier with its control points bunched at one end crawls there and races at the other. Equal steps in `t` give points that bunch up. Equal steps in `u` give points that are equally far apart.

Use `point` and `sample` to draw a curve. Use `point_at` and `spaced_points` to move something along it.

`length` and `point_at` read a table of `ARC_DIVISIONS` straight runs, which is 200, as three.js's `ARC_LENGTH_DIVISIONS` is. That table is the only approximation here.

### Tangents are exact

three.js measures a tangent across two samples a short step apart. Here each kind is a polynomial, so the derivative is another polynomial, and `tangent` evaluates it.

The reason is precision. These numbers are `Float32`, and subtracting two nearby samples cancels most of the digits they have.

Being exact makes a cusp exact too. A quadratic that starts and ends at one point turns back half way along. There is no direction there, and `tangent` raises rather than returning one that is nearly zero.

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
| `close_path()` | Add the straight run back to the start. |
| `is_closed() -> Bool` | True if the path ends where it began. |
| `sample(divisions) -> List[Vector2]` | The whole path as points, `divisions` per curve. |
| `length() -> Length` | The sum of its curves' lengths. |
| `curve_count() -> Int` | How many curves the path is made of. |
| `current() -> Vector2` | Where the pen is. |

`sample` leaves out each curve's first point, because it is where the curve before it ended. A repeated point is a run of no length for whatever reads the list.

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

The winding does not matter. A geometry built from a shape turns the outline counter-clockwise and each hole clockwise first.

## What is refused

| Mistake | Answer |
|---|---|
| A kind that is not one of the four. | An error at construction. |
| Points that do not match the kind. | An error at construction. |
| Every point the same point. | An error at construction. |
| `t` or `u` outside zero through one. | An error. |
| A tangent where the curve turns back. | An error. |
| Fewer than one division. | An error. |
| Drawing before the pen is down. | An error. |
| Moving the pen after it has drawn. | An error. |
| Closing an empty or a closed path. | An error. |
| An open outline or an open hole. | An error. |

three.js clamps `t`, returns an empty list, or builds a shape with no area. Each of those hides a caller that has lost track of the order.

## See also

- [Math](Math) has `Vector2`, which a curve is made of.
- [Geometry](Geometry) has the builders that turn points into a mesh.
