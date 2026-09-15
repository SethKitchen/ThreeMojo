# Units

`units/quantity.mojo` and `units/si.mojo`. Every measurement carries its dimension in its type. The compiler checks dimensions and erases them. A `Quantity` is the size of the `Float32` inside it.

three.js has no units. It leaves world units to the application. Here world space is metres.

## Quantity

`Quantity[length, mass, time, angle]` holds one `Float32` in canonical units: metres, kilograms, seconds and radians. The four parameters are exponents.

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

Angle is a base dimension here. Strict SI treats a radian as dimensionless. The deviation makes degrees-for-radians a compile error.

## Units

A `Unit` is a factor to the canonical unit and a symbol.

| Dimension | Units |
|---|---|
| Length | `METRE`, `KILOMETRE`, `CENTIMETRE`, `MILLIMETRE`, `YARD`, `FOOT`, `INCH`, `MILE` |
| Area | `SQUARE_METRE`, `SQUARE_FOOT` |
| Mass | `KILOGRAM`, `GRAM`, `POUND` |
| Duration | `SECOND`, `MILLISECOND`, `MINUTE`, `HOUR` |
| Angle | `RADIAN`, `DEGREE`, `TURN` |

## Use them

```mojo
var height = Length(1.0, METRE)
height.to(FOOT)                           # 3.2808399
var area = height * Length(2.0, METRE)    # Area
var side = area.sqrt()                    # Length
var total = Length(1.0, METRE) + Length(1.0, FOOT)   # 1.3048 m
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
Length(1.0, METRE) + Duration(1.0, SECOND)   # error
Length(1.0, METRE).to(SECOND)                # error
Volume(8.0).sqrt()                           # error: odd exponent
rotation_z(90.0)                             # error: needs an Angle
```

A test suite cannot contain these lines. Each lives in `tests/compile_fail/`, and `make compile-fail` asserts that the compiler rejects every one.
