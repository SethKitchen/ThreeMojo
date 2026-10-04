# Frame analysis

`extensions/structure/` analyzes linear-elastic frames and flat shells in three dimensions. It gives static displacements, support reactions, member end forces and natural modes. `extensions/building/views/structural.mojo` turns a building model into a frame with gravity loads. This page covers frames and the building view. [Shell analysis](Shell-analysis) covers the shell element.

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
| Consistent mass | ρ A L / 420 times the Hermite matrix, plus rotary inertia ρ I / (30 L) times its matrix in each plane, plus the polar inertia ρ (Iy + Iz) L in torsion |
| Uniform load w | w L / 2 at each node and moments of w L² / 12 |
| Transformation | Four copies of the 3 by 3 rotation, with the local axes as rows. A global matrix is Tᵀ K T. |

A line load and a member's weight become consistent nodal loads. The rotation about the local y axis is -dw/dx and the rotation about the local z axis is dv/dx. Both are right-handed.

## The structural view of a building

`structural_view(building, options)` returns a `StructuralView`. It holds a `StructuralModel`, its `dead` and `live` load cases, the building element of each member and shell, and `notes` on what it dropped.

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

Each row is a test in `tests/test_structure_frame.mojo`, `tests/test_structure_modal.mojo` or `tests/test_structural_view.mojo`. The error is the measured relative difference from the reference.

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
| The structure is a mechanism | `StaticSolver`, `solve_static`, `solve_modes` |
| The mode count is out of range | `solve_modes` |
| The view options are not valid, or a column or beam has no section | `structural_view` |

## Limits

- The analysis is linear and elastic. It has no second-order effects, no buckling and no material nonlinearity.
- The members have no shear deformation, no end releases, no offsets and no warping torsion.
- A support fixes a degree of freedom at zero. The model has no springs and no settlements.
- A member load is uniform along the member and acts along a global axis.
- The view uses uniform tributary loads on beams. It does not model walls as shear walls or as loads.
- `lowest_modes` can fail to factor its projected mass when an added mass is thousands of times the member mass on few elements. Use more elements or a smaller mass ratio.

## References

- Przemieniecki, "Theory of Matrix Structural Analysis", McGraw-Hill, 1968: sections 5.6 and 11.3.
- Bathe, "Finite Element Procedures", 2nd edition, 2014: sections 4.2 and 10.3.
- Hibbeler, "Structural Analysis", chapter 11, the slope-deflection method.
- Blevins, "Formulas for Natural Frequency and Mode Shape", 1979: table 8-1.
- ASCE/SEI 7-16, "Minimum Design Loads and Associated Criteria for Buildings and Other Structures", table 4.3-1.
