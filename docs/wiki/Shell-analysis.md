# Shell analysis

`extensions/structure/shell.mojo` gives a three-node flat shell for linear-elastic analysis. It adds a constant-strain membrane, the discrete Kirchhoff plate triangle of Batoz, Bathe and Ho, and a small drilling stiffness. Shells and frame members share nodes in one `StructuralModel`. [Frame analysis](Frame-analysis) covers the model, the solvers and the units.

![A simply supported square plate bends under a growing pressure](out/shell-analysis.png)

## Add shells

Add three nodes, then a shell over them. The normal follows the right hand rule over the three corners.

```mojo
var a = model.add_node(Vec3d(0, 0, 3))
var b = model.add_node(Vec3d(4, 0, 3))
var c = model.add_node(Vec3d(0, 4, 3))
var slab = model.add_shell(a, b, c, Length64(0.2, METER), concrete())
model.add_pressure(live, slab, Pressure64(2.4, KILOPASCAL))
```

A positive pressure pushes against the normal. Each corner takes a third of the resultant, with no moments. `add_self_weight` puts a third of ρ t A g at each corner, along -z.

After a static solve, `result.shell_resultants[s]` gives the shell's local axes, membrane stresses and moments. `model.shell_element(s)` gives the element itself, with its stiffness, transformation and corner coordinates.

## The element

The local x axis runs from the first corner to the second. The local z axis is the normal. The local y axis is z × x. Each corner has six degrees of freedom, the same as a frame node.

| Part | Formulation |
|---|---|
| Membrane | The constant-strain triangle, A t Bᵀ D B, with D for plane stress |
| Plate | The discrete Kirchhoff triangle (DKT). The rotations are quadratic, and the Kirchhoff constraint holds at the corners and the side midpoints. |
| Plate integration | Three interior Gauss points, at (1/6, 1/6), (2/3, 1/6) and (1/6, 2/3), with weight A / 3. They integrate the DKT exactly. |
| Drilling | A penalty ties each corner's rotation about the normal to the membrane rotation ω = (∂v/∂x - ∂u/∂y) / 2. Its modulus is 0.001 G t. |
| Transformation | Six copies of the 3 by 3 rotation. A global matrix is Tᵀ K T. |
| Mass | Lumped: ρ t A / 3 on each translation of each corner, and that mass times t² / 12 on each rotation |

The rotation about the local x axis is ∂w/∂y. The rotation about the local y axis is -∂w/∂x. These are right-handed rotations, the same as the frame element's.

The drilling penalty follows Hughes and Brezzi. A rigid rotation gives no drilling strain, so the patch tests stay exact. A flat mesh has no free drilling mode, so a coplanar slab is not a mechanism.

## Resultants

`ShellResultants` gives the values in the shell's local axes.

| Field | Meaning |
|---|---|
| `sigma_x`, `sigma_y`, `tau_xy` | The membrane stresses, constant over the element |
| `m_x` | -D (∂²w/∂x² + ν ∂²w/∂y²), at the centroid, in newton meters per meter |
| `m_y` | -D (∂²w/∂y² + ν ∂²w/∂x²), at the centroid |
| `m_xy` | -D (1 - ν) ∂²w/∂x∂y, at the centroid |

D is E t³ / (12 (1 - ν²)). The moment fields carry the `Force64` type, because a moment per length has the dimension of a force.

## Supports for a plate model

A flat plate model with only out-of-plane loads still has membrane degrees of freedom. Fix `UX`, `UY` and `RZ` at enough nodes to stop the in-plane rigid motions, or at every node for a pure bending problem. For a simply supported edge, fix `UZ` at the edge nodes. For a clamped edge, also fix `RX` and `RY`.

## Validation

Each row is a test in `tests/test_structure_shell.mojo`. The error is the measured relative difference from the reference.

| Case | Reference | Error |
|---|---|---|
| Membrane patch test, irregular patch, uniform tension | σx = σ, σy = τxy = 0 in every element; u = σ x / E, v = -ν σ y / E | Below 1e-6 |
| Plate patch test, irregular patch, constant curvature | Interior nodes from the field; mx, my and mxy constant | Below 1e-9 |
| Rigid translation and rotation of a tilted element | No force, no stress | Below 1e-9 |
| Tilted shell under pressure and its own weight | Reactions sum to p A n plus ρ t A g | Below 1e-9 |
| Simply supported square plate, uniform load, 4, 8 and 16 divisions per side | w = 0.00406 q a⁴ / D, ν = 0.3 | -4.2%, -1.3%, -0.29% |
| Clamped square plate, uniform load, 4, 8 and 16 divisions per side | w = 0.00126 q a⁴ / D, ν = 0.3 | +10.2%, +3.0%, +1.1% |
| Simply supported square plate, first frequency, 12 divisions | ω = 2 π² / a² sqrt(D / (ρ t)) | -0.33% |

Each plate mesh splits each square into two triangles. The plate tests fix `UX`, `UY` and `RZ` at every node.

## Limits

- The element is flat. A curved shell needs many small elements.
- The membrane is a constant-strain triangle. It is stiff in in-plane bending, so a shear wall or a deep beam needs a fine mesh.
- The material is isotropic and in plane stress. Layers of a construction are not modeled one by one.
- The plate has no transverse shear deformation. It is for thin plates.
- A pressure is uniform over each element and lumped at the corners.
- The mass is lumped, not consistent.

## References

- Batoz, Bathe and Ho, "A study of three-node triangular plate bending elements", International Journal for Numerical Methods in Engineering 15, 1980.
- Hughes and Brezzi, "On drilling degrees of freedom", Computer Methods in Applied Mechanics and Engineering 72, 1989.
- Irons and Razzaque, "Experience with the patch test for convergence of finite elements", 1972.
- Timoshenko and Woinowsky-Krieger, "Theory of Plates and Shells", 2nd edition, McGraw-Hill, 1959: tables 8 and 35.
- Leissa, "Vibration of Plates", NASA SP-160, 1969.
- Cook, Malkus, Plesha and Witt, "Concepts and Applications of Finite Element Analysis", 4th edition, 2002: chapter 15.
