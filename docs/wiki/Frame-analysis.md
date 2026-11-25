# Frame analysis

`extensions/structure/` analyzes linear-elastic frames and flat shells in three dimensions. It gives static displacements, support reactions, member end forces and natural modes. `extensions/building/views/structural.mojo` turns a building model into a frame with gravity loads. This page covers frames and the building view. [Shell analysis](Shell-analysis) covers the shell element.

![A generated tower frame sways in its first natural mode](out/frame-analysis.png)

## Modules

| Module | What it gives |
|---|---|
| `ids` | `NodeId`, `MemberId`, `ShellId` and `LoadCaseId` |
| `kinds` | `Dof` and the six degrees of freedom `UX`, `UY`, `UZ`, `RX`, `RY`, `RZ` |
| `frame` | `LocalAxes`, `member_axes`, the local stiffness and mass, the transformation and the consistent loads of a uniform load |
| `shell` | `ShellElement` and `ShellResultants` |
| `model` | `StructuralModel`, with nodes, supports, members, shells, load cases, loads and added masses |
| `static` | `StaticSolver`, `solve_static`, `StaticResult`, `MemberForces` and the assembly functions |
| `modal` | `solve_modes`, `ModalResult` and `assemble_mass` |
| `buckling` | `solve_buckling`, `BucklingResult`, `solve_second_order`, `SecondOrderOptions`, `frame_geometric_stiffness` and `assemble_geometric_stiffness` |
| `spectrum` | `solve_response_spectrum`, `SpectrumResult`, `ResponseSpectrum`, `CombinationRule` with `SRSS` and `CQC`, `combine_modes` and `modal_correlation` |
| `section` | `FiberSection`, `ConcreteLaw`, `moment_curvature`, `CurvaturePoint`, `section_response`, `SectionResponse` and `concrete_response` |
| `nonlinear` | `TrussModel`, `TrussState`, `SteelLaw`, `load_step`, `displacement_step`, `NewtonOptions`, `bar_response`, `BarState`, `BarResponse`, `assemble_truss` and `TrussTangent` |
| `transient` | `start_motion`, `dynamic_step`, `set_ground_motion_load` and `TrussMotion` |
| `dynamic` | `solve_load_history`, `solve_ground_motion`, `TimeHistory`, `newmark`, `TimeSeries`, `GroundMotion`, `HistoryOptions`, `NewmarkMethod` and `RayleighDamping` |

## Units and axes

Coordinates are meters, with z up. Gravity acts along -z. The loads and the results at the API carry unit types: `Force64`, `Moment64`, `LineLoad64`, `Pressure64`, `Length64`, `Angle64`, `Mass64` and `Frequency64`.

Each node has six degrees of freedom. A `Dof` names one. Its value is also its offset in the node's block of a global vector, so entry `6 n + d` is degree of freedom `d` of node `n`. The raw vectors of a result hold meters, radians, newtons and newton meters.

## Build a model

Add nodes, then members between them. A member takes a `Section` and a `BuildingMaterial` from `extensions/building/`. Fix degrees of freedom with `add_support` or `fix`. Add a load case, then loads in it.

```mojo
var model = StructuralModel()
var base = model.add_node(Vec3d(0, 0, 0))
var tip = model.add_node(Vec3d(3, 0, 0))
_ = model.add_member(base, tip, rectangle(Length64(0.1, METER), Length64(0.2, METER)), steel(), Vec3d(0, 0, 1))
model.fix(base)
var wind = model.add_load_case("wind")
model.add_force(wind, tip, UY, Force64(10, KILONEWTON))
model.add_line_load(wind, MemberId(0), UZ, LineLoad64(-2, KILONEWTON_PER_METER))
model.add_self_weight(wind, Acceleration64(9.80665, METER_PER_SECOND_SQUARED))
```

| Method | Adds |
|---|---|
| `add_node(at)` | A free node |
| `add_support(node, dofs)`, `fix(node)` | Fixed degrees of freedom, at zero displacement |
| `add_member(start, end, section, material, reference)` | A frame member |
| `add_shell(a, b, c, thickness, material)` | A flat three-node shell |
| `add_load_case(name)` | An empty load case |
| `add_force(case, node, dof, force)` | A force along `UX`, `UY` or `UZ` |
| `add_moment(case, node, dof, moment)` | A moment about `RX`, `RY` or `RZ` |
| `add_line_load(case, member, dof, load)` | A uniform load per member length, along a global axis |
| `add_pressure(case, shell, pressure)` | A uniform pressure on a shell |
| `add_self_weight(case, acceleration)` | The weight of every member and shell |
| `add_mass(node, mass)` | A point mass on the three translations, for modal analysis only |

## Solve a static case

`StaticSolver` takes the model, assembles the stiffness, removes the fixed degrees of freedom and factors the rest once. `solve(case)` then gives one load case. `solve_static(model, case)` does both for one case.

```mojo
var solver = StaticSolver(model^)
var result = solver.solve(wind)
var sway = result.translation(tip, UY)
var base_moment = result.reaction_moment(base, RZ)
var axial = result.member_forces[0].end.axial
```

| Result | Holds |
|---|---|
| `translation(node, dof)`, `rotation(node, dof)` | One displacement or rotation |
| `reaction_force(node, dof)`, `reaction_moment(node, dof)` | The force or moment the support applies, or zero at a free degree of freedom |
| `member_forces[m]` | The member's local axes and the end forces at its start and end |
| `shell_resultants[s]` | The shell's membrane stresses and moments |
| `displacements`, `reactions`, `loads` | The raw global vectors, six entries per node |

An `EndForces` value holds the force and moment that a node applies to a member end, along the member's local axes. Its fields are `axial`, `shear_y`, `shear_z`, `torque`, `moment_y` and `moment_z`. At the end node a positive axial force is tension. At the start node a positive axial force is compression. The member's own loads are taken out, so the end forces include the fixed-end forces.

A structure that can move without strain is a mechanism. Its stiffness is singular or not positive definite. `StaticSolver` raises an error that names the mechanism. Add supports or members to fix it.

## Find natural modes

`solve_modes(model, count)` gives the lowest natural frequencies, in hertz, and their mode shapes. The supports apply. Each shape has six entries per node and is normalized so that φᵀ M φ = 1.

```mojo
model.add_mass(roof, Mass64(20000, KILOGRAM))
var modes = solve_modes(model, 3)
var first = modes.frequencies[0]
```

The mass matrix adds the consistent mass of each member, the lumped mass of each shell and the added masses. The eigensolver is `lowest_modes` of [Numerics](Numerics): subspace iteration with a Sturm check.

## Follow a model in time

`solve_load_history(model, case, series, options)` gives the motion of a model under a load case that changes in time. `solve_ground_motion(model, motion, options)` gives the motion relative to a ground that accelerates. Both start from rest. Both integrate M a + C v + K u = s f(t) with Newmark's method.

```mojo
var record = TimeSeries(Duration64(0.02, SECOND), accelerations_in_g)
var motion = GroundMotion(UX, record, Acceleration64(9.80665, METER_PER_SECOND_SQUARED))
var modes = solve_modes(model, 3)
var damping = rayleigh_damping(0.05, modes.frequencies[0], modes.frequencies[2])
var options = HistoryOptions(Duration64(0.01, SECOND), 3000, average_acceleration(), damping)
var history = solve_ground_motion(model, motion, options)
var drift = history.peak_translation(roof, UX)
```

A `TimeSeries` holds factors at equal intervals from time zero. The factor is linear between two values. It is zero after the last value. `constant_series(duration)` is one up to the duration, so it makes a load case a step load.

A `GroundMotion` holds a translation, a series and a scale. The ground acceleration is the series value times the scale. Every support moves with the ground. The effective load is -M r a(t), where r is one at each translation along the axis.

| Option | Meaning |
|---|---|
| `step` | The time step |
| `steps` | The number of steps, from 1 to 1048576 |
| `method` | `average_acceleration()` has γ = 1/2 and β = 1/4. `linear_acceleration()` has γ = 1/2 and β = 1/6. `NewmarkMethod(gamma, beta)` sets both. |
| `damping` | `RayleighDamping(a, b)` gives C = a M + b K. `no_damping()` gives zero. `rayleigh_damping(ratio, first, second)` gives one damping ratio at two frequencies. |

The average acceleration method is stable for every step. It keeps the energy of an undamped model. The linear acceleration method is more accurate. It is stable only when the step is below 0.551 of the shortest period of the model, so use it on small models only. `NewmarkMethod.is_valid()` is true for a method that is stable for every step.

| Result | Holds |
|---|---|
| `count()`, `time(i)` | The number of times, and the time of entry `i` |
| `translation(i, node, dof)` | One displacement at one time |
| `peak_translation(node, dof)` | The largest absolute displacement of the history |
| `displacements`, `velocities`, `accelerations` | One raw global vector per time, six entries per node |

The solver factors the effective stiffness K + γ/(β Δt) C + M/(β Δt²) once. Each step then costs one substitution. The mass must be positive definite, as for `solve_modes`.

`newmark(k, m, shape, series, options)` runs the same integrator on any stiffness and mass in consistent units. Use it for a model that is not a `StructuralModel`.

The load pattern with a time series, the uniform ground motion, the Rayleigh damping and the Newmark integrator follow the analysis objects of OpenSees. The code is original.

## Combine modes with a response spectrum

`solve_response_spectrum(model, spectrum, direction, modes, rule, damping)` gives the peak response of a model to a ground motion that a response spectrum describes. The ground moves along one global axis.

```mojo
var spectrum = ResponseSpectrum([0.0, 0.1, 0.5, 1.0, 2.0], [0.4, 1.0, 1.0, 0.5, 0.25], Acceleration64(9.80665, METER_PER_SECOND_SQUARED))
var result = solve_response_spectrum(model, spectrum, UX, 6, CQC, 0.05)
var drift = result.translation(roof, UX)
var shear = result.base_shear()
```

A `ResponseSpectrum` holds a pseudo-acceleration at each period. It is linear between two periods and keeps its end value outside them. The value at a period is the list value times the scale, so a spectrum in units of g has a scale of 9.80665 m/s².

For each mode φ, with φᵀ M φ = 1 and r the rigid motion along the axis, the solver finds these values:

| Value | Formula |
|---|---|
| Participation factor | Γ = φᵀ M r |
| Effective mass | Γ² |
| Peak base shear of the mode | Γ² S_a |
| Peak displacement of the mode | Γ φ S_a / ω² |

The peaks of the modes do not occur at one time. `SRSS` combines them as the square root of the sum of the squares. `CQC` adds the cross terms of each pair of modes, with the correlation of Der Kiureghian for one damping ratio. Use `CQC` when two modes have close frequencies. The two rules agree when the frequencies are far apart.

| Result | Holds |
|---|---|
| `translation(node, dof)` | The combined peak displacement, relative to the ground. It has no sign. |
| `base_shear()` | The combined peak base shear |
| `effective_mass(mode)` | The effective mass of a mode |
| `frequencies`, `participation`, `effective_masses`, `modal_shears`, `displacements` | The raw values of each mode, and the combined peak of each degree of freedom |

The effective masses of all the modes add to the mass that the ground motion moves. Use enough modes for their sum to reach most of that mass. Building codes ask for 90%.

## Find buckling loads

`solve_buckling(model, case, count)` gives the lowest buckling factors of a load case. A factor λ means that λ times the load case buckles the structure. The result also holds one shape per factor, with its largest entry at one.

```mojo
var push = model.add_load_case("push")
model.add_force(push, top, UZ, Force64(-100, KILONEWTON))
var buckling = solve_buckling(model, push, 2)
var critical_load = 100 * buckling.factors[0]
```

The solver uses these steps:

1. A linear static solution gives the axial force of each member.
2. The axial forces give the geometric stiffness Kg. Tension adds stiffness and compression removes it.
3. The factors solve (K + λ Kg) φ = 0.

Only positive factors are returned. A load case that puts every member in tension has none, and the function raises an error. A load case with no axial force raises an error too.

The eigenproblem is solved in the shifted form (K + s Kg) φ = γ K φ, with λ = s / (1 - γ). The scale s keeps the left matrix positive definite. The lowest γ are the lowest positive λ. So `lowest_modes` of [Numerics](Numerics) finds them, and its Sturm check proves that no factor was missed.

## Solve with second-order effects

`solve_second_order(model, case, options)` solves a load case with the geometric stiffness of its own axial forces. The result is a `StaticResult`. It holds the P-Delta effect: an axial compression makes the sway and the moments larger.

```mojo
var result = solve_second_order(model, wind_and_gravity, default_second_order())
var amplified_sway = result.translation(roof, UX)
```

The first solution is linear. Each later solution uses the axial forces of the solution before it. The iteration stops when the largest displacement changes by less than the tolerance. `default_second_order()` has a tolerance of 1e-10 and a budget of 50 solutions. `SecondOrderOptions(tolerance, iterations)` sets both.

The function raises an error when the load case is at or above its buckling load. Run `solve_buckling` first to find the factor.

The member end forces include the geometric stiffness. So the moment at the base of a column includes the axial force times the sway. The kinematics stay linear, so the method is for small displacements.

CalculiX has this buckling analysis as its `*BUCKLE` procedure. OpenSees has the second-order analysis as its P-Delta transformation. The code is original.

## Follow a truss past yield

`extensions/structure/nonlinear.mojo` follows a truss whose bars yield. A `TrussModel` holds nodes, supports, bars and a reference load. Each node has the three translations only. A `TrussState` holds the displacements, the load factor and the plastic state of each bar.

```mojo
var steel = SteelLaw(Pressure64(200, GIGAPASCAL), Pressure64(250, MEGAPASCAL), 0.01)
var model = TrussModel()
var top = model.add_node(Vec3d(0, 0, 2))
var joint = model.add_node(Vec3d(0, 0, 0))
model.add_support(top, [UX, UY, UZ])
model.add_support(joint, [UX, UY])
_ = model.add_bar(top, joint, Area64(1e-3, SQUARE_METER), steel)
model.add_load(joint, UZ, Force64(-1, KILONEWTON))
var state = TrussState(model)
load_step(model, state, 200, default_newton())
displacement_step(model, state, joint, UZ, Length64(-1, MILLIMETER), default_newton())
var load = state.load_factor
```

A `SteelLaw` is bilinear. The bar is elastic up to its yield stress. Then it follows the modulus times the hardening ratio. A ratio of zero gives a perfectly plastic bar. The hardening is kinematic: the elastic range keeps its size of twice the yield stress and moves with the plastic strain. So a bar that has yielded in tension yields sooner in compression.

The applied load is the reference load times the load factor. The two step functions change the state only when they converge.

| Function | What it does |
|---|---|
| `load_step(model, state, factor_change, options)` | Changes the load factor by an amount. A negative change unloads. |
| `displacement_step(model, state, node, dof, change, options)` | Moves one free translation by an amount and finds the load factor |

`load_step` cannot pass a collapse load. There the tangent stiffness is singular, and the function raises an error. `displacement_step` follows a path through a plateau, if the bars have some hardening.

| State | Holds |
|---|---|
| `load_factor` | The applied load over the reference load |
| `translation(node, dof)` | One displacement |
| `bar_force(bar)` | The axial force of a bar. Tension is positive. |
| `has_yielded(bar)` | Whether the bar has a plastic strain |
| `iterations` | The Newton iterations of the last step |

Each step is a Newton iteration with the consistent tangent. It stops when the unbalanced force is below the tolerance times the forces in balance. `default_newton()` has a tolerance of 1e-10 and a budget of 25 iterations. `bar_response(law, state, strain)` gives the stress, the tangent and the new state of one bar. It is the return map of Simo and Hughes.

### Large displacements

`model.set_corotational(True)` gives each bar its exact geometry. The bar takes its strain from its current length, and it pushes along its current axis. So the analysis is exact for any displacement and any rotation. The tangent of a bar gets a geometric part: its force over its length, on the directions normal to the bar.

```mojo
model.set_corotational(True)
displacement_step(model, state, apex, UZ, Length64(-10, MILLIMETER), default_newton())
```

A shallow truss under a growing load reaches a limit load and snaps through. `load_step` cannot hold a load above the limit on the first branch. `displacement_step` follows the whole path, because the sag grows all the way. Past the limit the tangent is not positive definite, and the solver takes that. This is the corotational truss of OpenSees.

### A truss in time

`extensions/structure/transient.mojo` follows a truss under a load that changes in time, while its bars yield. Give each free node a mass with `model.add_mass(node, mass)`. `start_motion(model, state)` gives the motion at time zero, from rest. `dynamic_step` advances the state and the motion by one time step.

```mojo
model.add_mass(roof, Mass64(20000, KILOGRAM))
var state = TrussState(model)
var motion = start_motion(model, state)
for step in range(1, 501):
    dynamic_step(model, state, motion, load_at(step), Duration64(0.01, SECOND), average_acceleration(), damping, default_newton())
```

The equation of motion is M a + C v + f(u) = λ(t) P. The load factor λ is the argument of each step, so any record in time can drive the truss. The damping is Rayleigh damping, a M + b K₀, with K₀ the tangent stiffness at the start of the motion.

Each step is a Newmark step. The velocity and the acceleration at the end follow from the displacement there. So the step solves for the displacement by Newton iteration, with the matrix K + γ/(β Δt) C + M/(β Δt²). The state and the motion change only when the step converges.

`set_ground_motion_load(model, dof)` makes the reference load minus the mass of each node along one axis. The load factor of a step is then the acceleration of the ground, in meters per second squared. The motion is relative to the ground, and every support moves with it.

A `TrussMotion` holds the velocities, the accelerations and the time. `assemble_truss(model, state, u)` gives the internal forces and the tangent stiffness at trial displacements.

OpenSees does this analysis with its Newmark integrator and its Newton algorithm.

The parts follow the OpenSees objects: a uniaxial material with a committed state, a truss element, the Newton algorithm, and the LoadControl and DisplacementControl integrators. The law gives the response of the OpenSees material Steel01 with no isotropic hardening. The code is original.

## Find the moment-curvature curve of a section

`extensions/structure/section.mojo` gives the moment capacity and the ductility of a section of steel or of reinforced concrete. A `FiberSection` is a stack of fibers. Each fiber has an area, a height above a reference axis, and a law.

```mojo
var concrete = ConcreteLaw(Pressure64(30, MEGAPASCAL), 0.002, Pressure64(6, MEGAPASCAL), 0.006)
var steel = SteelLaw(Pressure64(200, GIGAPASCAL), Pressure64(420, MEGAPASCAL), 0.01)
var section = FiberSection()
section.add_concrete_patch(Length64(-0.25, METER), Length64(0.25, METER), Length64(0.3, METER), 100, concrete)
section.add_steel(Length64(-0.19, METER), Area64(1500e-6, SQUARE_METER), steel)
var curve = moment_curvature(section, Force64(0, NEWTON), InverseLength64(0.06, PER_METER), 120, 1e-9)
```

| Method | Adds |
|---|---|
| `add_concrete_patch(bottom, top, width, layers, law)` | A rectangle of concrete, cut into equal layers |
| `add_steel_patch(bottom, top, width, layers, law)` | A rectangle of steel, cut into equal layers |
| `add_steel(y, area, law)` | One fiber of steel, such as a layer of bars |

Plane sections stay plane. At an axial strain ε₀ and a curvature κ, the strain of a fiber at a height y is ε₀ - κ y. So a positive curvature shortens the top. The axial force is the sum of σ A, with tension positive. The moment is minus the sum of σ A y.

A `ConcreteLaw` is the envelope of Kent and Park. With x the compressive strain over the peak strain, the stress is the strength times 2 x - x² up to the peak. Then it falls on a line to the crushing strength and stays there. The concrete carries no tension. The law has no memory, so it is for a curvature that grows in one direction.

`moment_curvature(section, axial, last_curvature, steps, tolerance)` raises the curvature from zero in equal steps under a constant axial force. At each step it finds the axial strain that gives the force, by Newton iteration. The steel keeps its plastic state from each step to the next. Each `CurvaturePoint` holds the curvature, the moment and the axial strain.

A compression is a negative axial force. The function raises an error when no axial strain carries the force. That happens when the force is above the capacity, or when the section has no axial stiffness left.

`section_response(section, states, strain, curvature)` gives the forces of one state. A steel fiber does not take concrete away, so a bar in concrete counts its area twice. This is the usual small error of a fiber model.

OpenSees does this analysis with a fiber section of Concrete01 and Steel01 in a zero-length element. The concrete here is the monotonic envelope of Concrete01. The code is original.

## The frame element

The member is the two-node Euler-Bernoulli element of Przemieniecki, with twelve degrees of freedom. It has no shear deformation and no end releases.

The local x axis runs from the start node to the end node. The local z axis is the part of the reference vector normal to x. It is the direction of the section depth. The local y axis is z × x, the direction of the section width.

If the reference vector is parallel to the member, the global z axis is used instead. If the member is vertical too, the global x axis is used. So a column always has its depth along x, the same as `Building.add_column`.

| Term | Value |
|---|---|
| Axial | E A / L |
| Torsion | G J / L, with Saint-Venant's constant J from `Section.torsion_constant` |
| Bending in the x-z plane | 12 E Iy / L³, 6 E Iy / L², 4 E Iy / L and 2 E Iy / L, with Iy the strong second moment |
| Bending in the x-y plane | The same terms with Iz, the weak second moment |
| Geometric stiffness | N / (30 L) times 36, 3 L, 4 L² and -L² in each bending plane, with N the axial tension |
| Consistent mass | ρ A L / 420 times the Hermite matrix, plus rotary inertia ρ I / (30 L) times its matrix in each plane, plus the polar inertia ρ (Iy + Iz) L in torsion |
| Uniform load w | w L / 2 at each node and moments of w L² / 12 |
| Transformation | Four copies of the 3 by 3 rotation, with the local axes as rows. A global matrix is Tᵀ K T. |

A line load and a member's weight become consistent nodal loads. The rotation about the local y axis is -dw/dx and the rotation about the local z axis is dv/dx. Both are right-handed.

## The structural view of a building

`structural_view(building, options)` returns a `StructuralView`. It holds a `StructuralModel`, its `dead` and `live` load cases, the building element of each member and shell, and `notes` on what it dropped. The view validates the canonical building before it reads model references or creates structural nodes. Invalid public-field edits raise `Error`.

```mojo
var view = structural_view(building, default_options())
var solver = StaticSolver(view.model.copy())
var dead = solver.solve(view.dead)
var live = solver.solve(view.live)
```

The view builds the model in these steps:

1. Each column and beam becomes frame members. Ends closer than the tolerance share one node.
2. A member is split at each node that lies on it, so a beam that passes a column is connected to it.
3. The columns with the lowest base are fixed in all six degrees of freedom.
4. The dead case holds the weight of the members and of each floor and roof construction. The construction weight is g times the sum of ρ t over its layers.
5. The live case holds the live load of the space above each floor, and the roof live load on each roof.

The walls, the openings and the ground slabs are dropped. The notes give the count of each. A ground slab bears on the ground, so it carries no load to the frame.

With `shell_divisions` at zero, each floor and roof loads the beams at its level by tributary area. The method is this:

1. A 32 by 32 grid of points covers the slab's bounding box.
2. Each point inside the slab, and the face centroid, goes to the nearest beam in plan.
3. A beam takes the share of the slab area that its points have, as a uniform load along its length.

The sum of the loads equals the slab load exactly. The load along each beam is uniform, not triangular or trapezoidal. A slab with no beam at its level loses its load, and a note says so.

With `shell_divisions` from 1 to 16, each floor and roof becomes a mesh of flat shells instead. The view cuts the slab polygon into triangles with `earcut` and splits each triangle into that many divisions per side. The shell takes the material of the thickest layer and the total thickness of the construction. Its density is set so that its mass per area equals the construction's. The beams are split at the shell corners on them.

The live loads are typical values from ASCE/SEI 7-16, table 4.3-1. They are not design values. A project must use the loads of its own code and occupancy.

| Use | Live load |
|---|---|
| `OFFICE` | 2.40 kPa |
| `CORRIDOR`, `CORE`, `LOBBY`, `RETAIL`, `MEETING` | 4.79 kPa |
| `LIVING`, `BEDROOM`, `KITCHEN`, `BATHROOM` | 1.92 kPa |
| `STORAGE` | 6.00 kPa, light storage |
| `MECHANICAL` | 7.18 kPa. The table has no row for it, so the view uses the library stack-room value. |
| A roof | 0.96 kPa, an ordinary flat roof |

`live_load(use)` and `roof_live_load()` give these values. `StructuralViewOptions` holds the tolerance, the shell divisions and the gravity. `default_options()` gives a 1 mm tolerance, tributary loads and standard gravity.

## Validation

Each row is a test in `tests/test_structure_frame.mojo`, `tests/test_structure_modal.mojo`, `tests/test_structure_dynamic.mojo`, `tests/test_structure_buckling.mojo`, `tests/test_structure_nonlinear.mojo`, `tests/test_structure_transient.mojo`, `tests/test_structure_spectrum.mojo`, `tests/test_structure_section.mojo`, `tests/test_structure_opensees.mojo` or `tests/test_structural_view.mojo`. The error is the measured relative difference from the reference.

| Case | Reference | Error |
|---|---|---|
| Cantilever, tip load, both bending planes | P L³ / (3 E I) and P L² / (2 E I) | Below 1e-9 |
| Cantilever, axial load and torque | P L / (E A) and T L / (G J) | Below 1e-9 |
| Cantilever under its own weight | q L⁴ / (8 E I) | Below 1e-9 |
| Fixed-fixed beam, uniform load | w L⁴ / (384 E I) at midspan and w L² / 12 at the ends | Below 1e-9 |
| Simply supported beam, uniform load | 5 w L⁴ / (384 E I) and w L² / 8 | Below 1e-9 |
| Inclined cantilever along (2, 3, 6) | Axial and transverse parts of the tip load | Below 1e-9 |
| Portal frame, 4 m by 6 m, lateral load | Slope-deflection method, which ignores axial strain | 1.47% |
| The same frame, ten times larger | Slope-deflection method | 0.015% |
| Cantilever, first frequency, 2, 4 and 8 elements | 1.8751² sqrt(E I / (m L⁴)) / (2π) | +0.047%, +0.0018%, -0.0013% |
| Simply supported beam, first three frequencies, 10 elements | (n π)² sqrt(E I / (m L⁴)) / (2π) | -0.011%, -0.035%, -0.049% |
| Cantilever with a tip mass ten times the beam mass | Rayleigh's method with 0.2357 m L | -0.002% |
| Column, 8 elements: cantilever, pinned ends, fixed ends, fixed and pinned ends | Euler load π² E I / (K L)² with K = 2, 1, 0.5 and 0.699 | 0.0007%, 0.003%, 0.05% and 0.014% |
| Vertical cantilever in space, first three factors | Weak axis, strong axis, second weak mode | 0.0007%, 0.0007% and 0.05% |
| Cantilever beam-column at half its Euler load | H L³ / (3 E I) times 3 (tan u - u) / u³, and a base moment of H L tan u / u | Below 0.001% |
| The same member in tension at twice its Euler load | 3 (u - tanh u) / u³ | Below 0.01% |
| Frame with a shell slab, second order | Sum of reactions equals the loads | Below 1e-6 |
| Steel rectangle, perfectly plastic, 200 layers | E I κ, then M_y (3 - (κ_y / κ)²) / 2 | Below 0.01% |
| The same rectangle with 0.4 of its squash load, 400 layers | A plastic moment of M_p (1 - (N / N_y)²) | Below 0.1% |
| Singly reinforced concrete beam, peak moment | ACI 318: A_s f_y (d - a / 2) with the rectangular stress block | Below 3% |
| Kent and Park envelope at six strains | 0.75 of the strength at half the peak strain, and the line after the peak | Below 1e-6 Pa |
| Elastoplastic system under a half-sine pulse, 9 steps | Chopra, table E5.5 | Equal to the four decimals of the table |
| The same system with no yield, by mass and by stiffness damping | Chopra, table E5.3 | Equal to the four decimals of the table |
| Elastic chain of two bars and two masses, 200 steps | Energy balance | Below 1e-9 of the strain energy |
| Elastoplastic system on ground that accelerates | The same system under the force -m a | Below 1e-12 |
| Shallow two-bar truss of von Mises, corotational, 50 steps of 10 mm | The closed form of the load at each sag, through the flat state and the mirror state | Below 0.01 N of a limit load of 76 kN |
| The same truss, load control to 0.8 of the limit | The closed-form sag | Below 1e-4 N |
| Three-bar truss with 1% hardening, 34 steps down, up and down again | OpenSees Truss elements of Steel01 under DisplacementControl | Below 1e-9 of 1 MN |
| Shallow corotational truss, 50 steps through the snap | OpenSees corotTruss | Below 1e-9 |
| Elastoplastic oscillator under a harmonic force, 300 steps | OpenSees Newmark and Steel01 | Below 1e-9 |
| Two yielding bars and two masses under a ground acceleration, 300 steps | OpenSees UniformExcitation, with Rayleigh damping of the mass and the initial stiffness | Below 1e-9 m |
| Steel rectangle at 0.4 of its squash load, 80 steps | An OpenSees fiber section of Steel01 in a zeroLengthSection | Below 1e-9 |
| Reinforced concrete beam, 120 steps | An OpenSees fiber section of Concrete01 and Steel01 | Below 1e-9 up to the yield of the steel. Then 0.10% in the moment and 0.58% in the axial strain |
| The same truss with small displacements | The linear stiffness 2 E A h² / L³ | Below 1e-12 m |
| One floor on one column, flat spectrum | S_a / ω² and m S_a | Below 0.05% |
| Shear building of two equal storeys, SRSS | Effective masses of 1.8944 m and 0.1056 m, and the base shear and roof sway from them | Below 0.2% |
| The same building, CQC at 5% damping | SRSS, because the frequencies are far apart | Below 0.5% |
| Combination rules on given peaks | SRSS of 3 and 4 is 5. CQC is the absolute sum at equal frequencies and SRSS at zero damping. | Below 1e-12 |
| One bar, strained past yield and back | The bilinear law, and a second yield at 290 - 500 = -210 MPa | Below 1e-3 Pa |
| Three-bar truss, perfectly plastic, load control | Bar forces before and after first yield at σ A (1 + 2 cos³ θ). A load above σ A (1 + 2 cos θ) is refused. | Below 1e-4 N |
| The same truss, loaded to 550 kN and unloaded | The residual bar forces, which balance | Below 1e-4 N |
| The same truss with 1% hardening, displacement control | The load at each sag from the bilinear law, and the elastic slope of a step back | Below 1e-3 N |
| One degree of freedom, half-sine pulse, average acceleration | Chopra, table E5.3 | Equal to the four decimals of the table |
| The same system, linear acceleration | Chopra, table E5.4 | Equal to the four decimals of the table |
| Two degrees of freedom, step load, steps of 0.1 s and 0.05 s | Modal solution | The error falls by a factor of 4 |
| The same system, 300 steps of 0.7 s | Energy balance | Below 1e-11 |
| Bar with one free degree of freedom, step load | (P / k) (1 - cos ω t) | Below 0.1% of P / k |
| Cantilever on ground that accelerates at g, critical damping | Static deflection under self-weight | Below 1e-8 |
| Two-storey frame view, tributary and shell slabs | Sum of reactions equals the dead and live loads | Below 1e-9 |
| L-shaped roof view | Sum of reactions equals the dead and live loads | Below 1e-9 |

The portal frame difference falls by a factor of 100 when the frame is ten times larger. That is the share of axial strain, which the hand method ignores. The small negative frequency errors come from rotary inertia, which the Euler-Bernoulli formulas ignore.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| An id is out of range | All methods that take an id |
| A position, load or mass is not finite | `add_node`, the `add_` load methods, `add_mass` |
| A force is not along a translation, or a moment is not about a rotation | `add_force`, `add_moment`, `add_line_load`, the result accessors |
| A member's ends are at one point, or its reference is zero | `add_member`, `member_axes` |
| A section or material is not valid | `add_member`, `add_shell` |
| The structure is a mechanism | `StaticSolver`, `solve_static`, `solve_modes`, `solve_load_history`, `solve_ground_motion`, `solve_buckling`, `solve_second_order` |
| The mode count is out of range | `solve_modes`, `solve_buckling`, `solve_response_spectrum` |
| A spectrum has no period, periods that do not ascend, or a negative value | `ResponseSpectrum` |
| A combination rule or a damping ratio is not valid | `solve_response_spectrum`, `combine_modes` |
| The load case has no axial force, or fewer positive factors than the count | `solve_buckling` |
| The load case is at or above its buckling load, or the iteration does not converge | `solve_second_order` |
| A truss is a mechanism or at its collapse load, or a step does not converge | `load_step`, `displacement_step` |
| A free node has no mass, or the motion does not fit the model | `start_motion`, `dynamic_step` |
| A concrete law, a fiber or a patch is not valid | `ConcreteLaw`, `FiberSection` |
| No axial strain carries the axial force of a section | `moment_curvature` |
| A steel law, a bar area or a step size is not valid | `SteelLaw`, `TrussModel.add_bar`, `load_step`, `displacement_step` |
| A time step, a step count, a method or a damping is not valid | `HistoryOptions` |
| A series is empty, or its interval or a value is not valid | `TimeSeries` |
| A ground motion is not along a translation | `GroundMotion` |
| The mass is not positive definite | `newmark`, `solve_load_history`, `solve_ground_motion` |
| The building or view options are not valid | `structural_view` |

## Limits

- The material of a frame member and of a shell is linear and elastic. Only the bars of a `TrussModel` yield.
- A fiber section bends about one axis. It is not yet the section of a frame member.
- The displacements of a frame are small. `solve_second_order` adds the geometric stiffness, but it has no large rotations. Only a corotational `TrussModel` has an exact geometry.
- Displacement control needs a degree of freedom that grows along the whole path. The module has no arc-length control.
- A shell has no geometric stiffness. Its membrane stress does not change a buckling factor.
- The members have no shear deformation, no end releases, no offsets and no warping torsion.
- A support fixes a degree of freedom at zero. The model has no springs and no settlements.
- A member load is uniform along the member and acts along a global axis.
- A response spectrum analysis has one ground direction and one damping ratio. It gives displacements and the base shear, not member forces.
- The time history of a truss has lumped masses. Its ground motion has one axis, and every support has the same motion.
- A time history starts from rest. It has Rayleigh damping only, and every support has the same ground motion.
- The view uses uniform tributary loads on beams. It does not model walls as shear walls or as loads.

## References

- Przemieniecki, "Theory of Matrix Structural Analysis", McGraw-Hill, 1968: sections 5.6 and 11.3.
- Bathe, "Finite Element Procedures", 2nd edition, 2014: sections 4.2 and 10.3.
- Hibbeler, "Structural Analysis", chapter 11, the slope-deflection method.
- McGuire, Gallagher and Ziemian, "Matrix Structural Analysis", 2nd edition, 2000: chapter 9, the geometric stiffness.
- Timoshenko and Gere, "Theory of Elastic Stability", 2nd edition, 1961: chapters 1 and 2.
- Dhondt, "The Finite Element Method for Three-Dimensional Thermomechanical Applications", Wiley, 2004: the theory of CalculiX.
- Der Kiureghian, "A response spectrum method for random vibration analysis of MDF systems", Earthquake Engineering and Structural Dynamics 9, 1981: the CQC correlation.
- Kent and Park, "Flexural members with confined concrete", Journal of the Structural Division, ASCE, 1971: the concrete envelope.
- ACI 318-19, "Building Code Requirements for Structural Concrete", section 22.2: the rectangular stress block.
- Simo and Hughes, "Computational Inelasticity", Springer, 1998: chapter 1, the return map of one-dimensional plasticity.
- Chen and Han, "Plasticity for Structural Engineers", Springer, 1988: limit analysis of the three-bar truss.
- Newmark, "A method of computation for structural dynamics", Journal of the Engineering Mechanics Division, ASCE, 1959.
- Chopra, "Dynamics of Structures", 4th edition, 2012: sections 5.4, 11.4, 13.7 and 13.8, and tables E5.3 and E5.4.
- McKenna, Scott and Fenves, "Nonlinear finite-element analysis software architecture using object composition", Journal of Computing in Civil Engineering, 2010: the OpenSees analysis objects.
- Blevins, "Formulas for Natural Frequency and Mode Shape", 1979: table 8-1.
- ASCE/SEI 7-16, "Minimum Design Loads and Associated Criteria for Buildings and Other Structures", table 4.3-1.
