# Units

`units/quantity.mojo` and `units/si.mojo`. Every measurement carries its dimension in its type. The compiler checks dimensions and erases them. A `Quantity` is the size of the `Float32` inside it.

![A clock delta turns a cube by an angle in radians](out/units.png)

three.js has no units. It leaves world units to the application. Here world space is meters.

## Quantity

`Quantity[length, mass, time, angle]` holds one `Float32` in canonical units: meters, kilograms, seconds and radians. The four parameters are exponents.

| Alias | Exponents |
|---|---|
| `Scalar` | 0, 0, 0, 0 |
| `Length` | 1, 0, 0, 0 |
| `Area` | 2, 0, 0, 0 |
| `Volume` | 3, 0, 0, 0 |
| `Mass` | 0, 1, 0, 0 |
| `Duration` | 0, 0, 1, 0 |
| `Angle` | 0, 0, 0, 1 |
| `Velocity` | 1, 0, -1, 0 |
| `Acceleration` | 1, 0, -2, 0 |
| `AngularVelocity` | 0, 0, -1, 1 |
| `Density` | -3, 1, 0, 0 |
| `Force` | 1, 1, -2, 0 |
| `Pressure` | -1, 1, -2, 0 |

Angle is a base dimension here. Strict SI treats a radian as dimensionless. The deviation makes degrees-for-radians a compile error.

## Units

A `Unit` is a factor to the canonical unit and a symbol.

| Dimension | Units |
|---|---|
| Length | `METER`, `KILOMETER`, `CENTIMETER`, `MILLIMETER`, `YARD`, `FOOT`, `INCH`, `MILE` |
| Area | `SQUARE_METER`, `SQUARE_FOOT` |
| Volume | `CUBIC_METER`, `CUBIC_CENTIMETER` |
| Mass | `KILOGRAM`, `GRAM`, `POUND` |
| Density | `KILOGRAM_PER_CUBIC_METER`, `GRAM_PER_CUBIC_CENTIMETER` |
| Acceleration | `METER_PER_SECOND_SQUARED` |
| Force | `NEWTON`, `POUND_FORCE` |
| Pressure | `PASCAL`, `MEGAPASCAL`, `GIGAPASCAL` |
| Duration | `SECOND`, `MILLISECOND`, `MINUTE`, `HOUR` |
| Angle | `RADIAN`, `DEGREE`, `TURN` |

`STANDARD_GRAVITY` is 9.80665 meters per second squared. Weight on Earth is mass times that acceleration.

## Use them

```mojo
var height = Length(1.0, METER)
height.to(FOOT)                           # 3.2808399
var area = height * Length(2.0, METER)    # Area
var side = area.sqrt()                    # Length
var total = Length(1.0, METER) + Length(1.0, FOOT)   # 1.3048 m
var turn = Angle(90.0, DEGREE)
turn.value                                # radians
```

| Operation | Result |
|---|---|
| `a + b`, `a - b` | Same dimension only. |
| `a * b`, `a / b` | Exponents add or subtract. |
| `a.sqrt()` | Exponents halve. Even exponents only. |
| `a.to(unit)` | The value in that unit, as a `Float32`. |
| `a.scaled(f)`, `-a`, `abs(a)` | Same dimension. |
| `==`, `<`, `<=`, `>`, `>=` | Same dimension only. |

## Compile errors

```mojo
Length(1.0, METER) + Duration(1.0, SECOND)   # error
Length(1.0, METER).to(SECOND)                # error
Volume(8.0).sqrt()                           # error: odd exponent
rotation_z(90.0)                             # error: needs an Angle
```

A test suite cannot contain these lines. Each lives in `tests/compile_fail/`, and `make compile-fail` asserts that the compiler rejects every one.

## Clock

`core/clock.mojo`. A `Clock` measures the time an animation loop runs, in `Duration`s. It reads a monotonic counter, so an interval never runs backwards. three.js's `Clock`.

| Member | Meaning |
|---|---|
| `Clock(auto_start=True)` | A stopped clock. It starts on its first question unless told not to. |
| `start()`, `stop()` | Start, or restart, from now. Stop, keeping the elapsed time. |
| `delta() -> Duration` | The time since the last question. Zero when stopped. |
| `elapsed() -> Duration` | The time since the clock started. |
| `start_at(ns)`, `stop_at(ns)`, `delta_at(ns)`, `elapsed_at(ns)` | The same at a given counter reading, for tests. |

The clock keeps whole nanoseconds. The elapsed time is the counter's reading less the start. It does not drift with the frame rate, as a sum of deltas does. Seconds are made only in the answer.

```mojo
var clock = Clock()
var step = clock.delta()                     # a Duration
var moved = Velocity(2.0) * step             # a Length: two meters per second, for one step
node.position.x += moved.value
```
