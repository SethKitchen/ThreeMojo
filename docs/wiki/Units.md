# Units

`units/quantity.mojo`, `units/si.mojo` and `units/temperature.mojo`. Every measurement carries its dimension in its type. The compiler checks dimensions and erases them. A `Quantity` is the size of the float inside it.

![A clock delta turns a cube by an angle in radians](out/units.png)

three.js has no units. It leaves world units to the application. Here world space is meters.

## Quantity

`Quantity[length, mass, time, angle, temperature, dtype]` holds one float in canonical units: meters, kilograms, seconds, radians and kelvin. The first five parameters are exponents. The temperature exponent defaults to zero, so `Quantity[1, 0, 0, 0]` is a length. The `dtype` parameter defaults to `DType.float32`.

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

### Heat, structure and flow

The engineering extensions use these aliases. A temperature exponent of one is a temperature difference in kelvin.

| Alias | Exponents | Meaning |
|---|---|---|
| `Energy` | 2, 1, -2, 0 | Work or heat, in joules |
| `Power` | 2, 1, -3, 0 | A heating load, in watts |
| `HeatFlux` | 0, 1, -3, 0 | Power per area |
| `ThermalConductivity` | 1, 1, -3, 0, -1 | Power per length per kelvin |
| `ThermalTransmittance` | 0, 1, -3, 0, -1 | A U-value, power per area per kelvin |
| `ThermalResistance` | 0, -1, 3, 0, 1 | An R-value, the inverse of a U-value |
| `SpecificHeatCapacity` | 2, 0, -2, 0, -1 | Energy per mass per kelvin |
| `HeatCapacity` | 2, 1, -2, 0, -1 | Energy per kelvin |
| `ThermalConductance` | 2, 1, -3, 0, -1 | Power per kelvin |
| `ThermalExpansion` | 0, 0, 0, 0, -1 | Strain per kelvin |
| `Moment` | 2, 1, -2, 0 | A bending moment |
| `LineLoad` | 0, 1, -2, 0 | Force per length |
| `SecondMomentOfArea` | 4, 0, 0, 0 | The bending stiffness of a section shape |
| `VolumeFlowRate` | 3, 0, -1, 0 | An air flow |
| `MassFlowRate` | 0, 1, -1, 0 | Mass per time |

### Float64 quantities

Use a `Float64` quantity for engineering analysis. A `Float32` keeps about seven digits, and a stiffness matrix loses more than that. Each alias above, and each base alias, has a `64` form: `Length64`, `Force64`, `ThermalConductivity64`.

```mojo
var span = Length64(0.3048, METER)           # every digit kept
var coarse = span.cast[DType.float32]()      # a Length
```

Two quantities combine only when their `dtype` is the same. A `Length64` plus a `Length` is a compile error. Use `cast` to change the float type.

A `Unit` holds its factor as a `Float64`. A `Float32` quantity rounds the factor once, when it reads or writes a value. A `Float64` quantity keeps the exact factor.

## Units

A `Unit` is a factor to the canonical unit and a symbol.

| Dimension | Units |
|---|---|
| Length | `METER`, `KILOMETER`, `CENTIMETER`, `MILLIMETER`, `YARD`, `FOOT`, `INCH`, `MILE` |
| Area | `SQUARE_METER`, `SQUARE_FOOT` |
| Volume | `CUBIC_METER`, `CUBIC_CENTIMETER` |
| Mass | `KILOGRAM`, `GRAM`, `POUND` |
| Density | `KILOGRAM_PER_CUBIC_METER`, `GRAM_PER_CUBIC_CENTIMETER` |
| Force | `NEWTON`, `POUND_FORCE` |
| Pressure | `PASCAL`, `MEGAPASCAL`, `GIGAPASCAL` |
| Moment of inertia | `KILOGRAM_SQUARE_METER` |
| Duration | `SECOND`, `MILLISECOND`, `MINUTE`, `HOUR` |
| Angle | `RADIAN`, `DEGREE`, `TURN` |
| Velocity | `METER_PER_SECOND` |
| Acceleration | `METER_PER_SECOND_SQUARED` |

| Energy | `JOULE`, `KILOWATT_HOUR` |
| Power | `WATT`, `KILOWATT` |
| Heat flux | `WATT_PER_SQUARE_METER` |
| Thermal conductivity | `WATT_PER_METER_KELVIN` |
| Thermal transmittance | `WATT_PER_SQUARE_METER_KELVIN` |
| Thermal resistance | `SQUARE_METER_KELVIN_PER_WATT` |
| Specific heat capacity | `JOULE_PER_KILOGRAM_KELVIN` |
| Heat capacity | `JOULE_PER_KELVIN` |
| Thermal conductance | `WATT_PER_KELVIN` |
| Thermal expansion | `PER_KELVIN` |
| Moment | `NEWTON_METER`, `KILONEWTON_METER` |
| Force, structural | `KILONEWTON` |
| Line load | `NEWTON_PER_METER`, `KILONEWTON_PER_METER` |
| Pressure, structural | `KILOPASCAL` |
| Second moment of area | `METER_TO_THE_FOURTH` |
| Flow | `CUBIC_METER_PER_SECOND`, `KILOGRAM_PER_SECOND` |

`STANDARD_GRAVITY` is 9.80665 meters per second squared. Weight on Earth is mass times that acceleration.

## Temperature

`units/temperature.mojo`. A `Temperature` is an absolute temperature, kept in kelvin. It is not a `Quantity`, because the Celsius scale has a different zero. `KELVIN` and `CELSIUS` are its scales.

| Member | Meaning |
|---|---|
| `Temperature(v, unit)` | A reading on a scale, in a `Float32`. |
| `Temperature64(v, unit)` | The same in a `Float64`. |
| `t.to(unit)` | The reading on a scale. |
| `a - b` | A `TemperatureDifference`, which is a `Quantity` with a temperature exponent of one. |
| `t + d` | A temperature raised by a difference. |
| `a < b` | True when `a` is the colder. |
| `t.is_valid()` | True when the value is finite and not below absolute zero. |

```mojo
var inside = Temperature64(20, CELSIUS)
var outside = Temperature64(-5, CELSIUS)
var drop = inside - outside                   # 25 K, a TemperatureDifference64
var k = ThermalConductivity64(0.8, WATT_PER_METER_KELVIN)
var flux = k * drop / Length64(0.2, METER)    # 100 W/m^2, a HeatFlux64
```

Two temperatures do not add. Only a difference adds to a temperature. `KELVIN_DIFFERENCE` is the unit of a difference.

## Light

`units/photometry.mojo`. Light has its own two types, because the luminous intensity is not one of the four dimensions of `Quantity`.

| Type | Meaning | Units |
|---|---|---|
| `Illuminance` | Light that falls on a surface | `LUX`, `KILOLUX`, `FOOT_CANDLE` |
| `Luminance` | Light that a surface sends toward the eye | `NIT` (candela per square meter) |

Each type adds, subtracts and compares with its own type only. A `Float32` scales either type from the left or the right. The ratio of two of the same type is a `Float32`. `diffuse_luminance(e)` gives the luminance of a white diffuse surface under the illuminance `e`: `e / pi`.

```mojo
var noon = Illuminance(100, KILOLUX)
noon.to(LUX)                                 # 100000
diffuse_luminance(noon).to(NIT)              # 31831
```

A bare `Float32` in place of either type is a compile error. A `Luminance` in place of an `Illuminance` is a compile error too.

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
| `a.to(unit)` | The value in that unit, in the quantity's float type. |
| `a.scaled(f)`, `-a`, `abs(a)` | Same dimension. |
| `==`, `<`, `<=`, `>`, `>=` | Same dimension only. |

`abs(a)` clears the sign of the stored value, including negative zero and NaN. It keeps the dimension.

## Compile errors

```mojo
Length(1.0, METER) + Duration(1.0, SECOND)   # error
Length(1.0, METER).to(SECOND)                # error
Volume(8.0).sqrt()                           # error: odd exponent
Length64(1.0, METER) + Length(1.0, METER)    # error: dtype differs
inside + outside                             # error: two temperatures
rotation_z(90.0)                             # error: needs an Angle
```

A test suite cannot contain these lines. Each lives in `tests/compile_fail/`, and `make compile-fail` checks that the compiler rejects every one.

The check first builds a valid control. Each negative case must then produce
a source error in that case. A missing compiler, missing import, error in a
dependency, crash or timeout fails the check. A failed build alone is not a
valid rejection.

Each case has expected error locations and messages in
`tools/compile_fail_expectations.json`. An unexpected source error also fails.
Review the case before you update an expectation. Do not accept new errors
just to make the check pass.
Use the explicit [regeneration workflow](How-to-run-the-checks#regenerate-negative-diagnostics)
for selected cases. Normal checks never update the manifest.

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

## Timer

`core/timer.mojo`. A `Timer` gives an animation loop one delta per frame, scaled by a time scale. three.js's `Timer`, which three.js recommends over `Clock`. Call `update` once a frame. Every question after it in the same frame gets the same answer.

| Member | Meaning |
|---|---|
| `Timer()` | A timer that starts now, with a time scale of one. |
| `update()` | Take this frame's delta. three.js's `update`. |
| `delta() -> Duration` | The time between the last two updates, times the time scale. Zero before the first update. |
| `elapsed() -> Duration` | The sum of every delta. |
| `set_timescale(s)` | Multiply each later delta by `s`. Two is double speed, zero pauses, and a negative scale runs the elapsed time back. A scale that is not finite is refused. |
| `reset()` | Measure the next delta from now. The elapsed time is kept. |
| `set_hidden(hidden)` | Tell the timer that the window is hidden or shown. |
| `Timer(start=ns)`, `update_at(ns)`, `reset_at(ns)`, `set_hidden_at(hidden, ns)` | The same at a given counter reading. `update_at` is three.js's `update(timestamp)`. |

A hidden window gives a delta of zero. Showing it again resets the timer, so the first frame back does not jump. three.js does this when `connect` gives it the page's document. There is no document here, so `set_hidden` takes the place of the `visibilitychange` event.

```mojo
var timer = Timer()
timer.set_timescale(0.5)                     # slow motion
# In the loop:
timer.update()
var step = timer.delta()                     # the same Duration until the next update
```
