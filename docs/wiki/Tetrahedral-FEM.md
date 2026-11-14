# Tetrahedral FEM

`extensions/fem/` solves static linear elasticity on meshes of four-node and ten-node tetrahedra. It meshes a box, or the voxels of one label of a label map. It applies supports, nodal forces and surface pressures, and it solves for displacements, stresses and reactions. It draws the deformed surface colored by von Mises stress. It is a library for research and teaching. Its results are not validated for the design of a structure or of a medical device.

![A steel cantilever of ten-node tetrahedra, bent by a load at its tip and colored by von Mises stress](out/tetrahedral-fem.png)

`examples/tetrahedral_fem.mojo` makes this picture. A steel beam 600 mm long and 60 mm square is clamped at one end and meshed with 1620 ten-node tetrahedra. A force of 20 kN pulls its tip down 6.66 mm. Beam theory gives 6.67 mm. The picture shows the beam at 40 times its deflection. The colors run from 0 MPa in blue to 300 MPa in red.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `NodeId`, `ElementId`, `MaterialId`, `DofAxis` and `ElementOrder` |
| `mesh` | `TetMesh`, `box_mesh`, `voxel_mesh`, `voxel_mesh_labels`, `quadratic_mesh`, `boundary_faces`, `edge_pairs` and `signed_volume` |
| `elasticity` | `IsotropicMaterial`, `shape_gradients`, `element_stiffness`, `quadratic_gradients`, `quadratic_stiffness`, `gauss_points`, `element_strain`, `stress_of`, `von_mises`, `principal_stresses` and `PrincipalStress` |
| `static` | `StaticProblem`, `StaticResult`, `assemble` and `solve_static` |
| `post` | `stress_geometry` and `stress_color` |
| `export` | `vtk_mesh` and `vtk_result` |
| `density` | `CtDensityLaw`, `element_ct`, `density_materials` and `DensityMaterials` |

## Solve a problem

Make a mesh, give it materials, then add supports and loads. Then solve.

```mojo
var mesh = box_mesh(Length64(2, METER), Length64(1, METER),
    Length64(1, METER), 4, 2, 2)
var steel = IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.3)
var problem = StaticProblem(mesh^, [steel])
var near = Length64(1e-9, METER)
for node in problem.mesh.nodes_on_plane(DOF_X, Length64(0, METER), near):
    problem.fix(node, DOF_X, Length64(0, METER))
_ = problem.press_plane(DOF_X, Length64(2, METER), near,
    Pressure64(9, MEGAPASCAL))
var result = solve_static(problem, 1e-12, 2000)
```

A real problem needs supports on all three axes. The fragment above holds only x. The tests add symmetry supports on the y and z faces.

## Meshes

A `TetMesh` holds nodes in meters and elements of four nodes each. Each element names a material by a `MaterialId`. `add_element` turns an element inside out when its volume is negative, so every element has a positive volume. It refuses a flat element.

`box_mesh(size_x, size_y, size_z, nx, ny, nz)` fills a box from the origin with a grid of cubes. `voxel_mesh(map, label)` fills the voxels of one label of a label map from the imaging extension. Its voxel `(i, j, k)` is the box of one voxel around the center at `(i * spacing_x, j * spacing_y, k * spacing_z)`. This is the volume frame of [Medical imaging](Medical-imaging).

`voxel_mesh_labels(map, labels)` meshes several labels at once. Each label is a material: an element's material index is its label's place in the list. The labels share nodes where they touch, so the materials join at their interfaces.

Each cube becomes six tetrahedra that share the diagonal from its low corner to its high corner. This is the Kuhn split. Neighbor cubes then share whole faces, so the mesh is conforming.

## Materials from CT density

The stiffness of bone follows its density. `density_materials(mesh, volume, law, bins)` gives each element a material from the CT number of its voxel. A calibration line turns the CT number into an apparent density, and a power law turns the density into a modulus:

```
rho = intercept + slope * CT
E = coefficient * (rho / (1 g/cm^3))^exponent
```

```mojo
var law = CtDensityLaw(Density64(0, GRAM_PER_CUBIC_CENTIMETER),
    Density64(0.001, GRAM_PER_CUBIC_CENTIMETER), Pressure64(6850, MEGAPASCAL),
    1.49, Density64(0.01, GRAM_PER_CUBIC_CENTIMETER), 0.3)
var made = density_materials(mesh, volume, law, 64)
var problem = StaticProblem(mesh^, made.materials.copy())
problem.apply_gravity(made.densities, gravity, v3(0, 0, -1))
```

The law here is Morgan's for the human femoral neck: 6850 MPa at 1 g/cm^3, with an exponent of 1.49. Get the calibration line from a phantom of known densities in the same scan. A density below the minimum is held at it, so air and fat give a small positive modulus.

`element_ct(mesh, volume)` reads the voxel that holds the centroid of each element. The mesh must be in the volume frame, as `voxel_mesh` makes it. The elements go in bins of equal modulus width. Each bin that holds an element becomes one material, with the mean modulus and the mean density of its elements, weighted by volume. More bins follow the density more closely.

## Find nodes and faces

`nodes_on_plane(axis, at, tolerance)` gives the nodes whose coordinate on an axis is near a value. Use it to find the nodes of a support or a load. `boundary_faces(mesh)` gives the faces that only one element has, each turned to face out of its element.

## Elements

A four-node tetrahedron has linear shape functions, so its strain is constant inside it. Its stiffness is its volume times the integrand of an isotropic material:

```text
K[3a + i, 3b + j] = V (lambda g_a[i] g_b[j] + mu g_a[j] g_b[i] + mu delta_ij g_a . g_b)
```

Here `g_a` is the gradient of the shape function of node `a`, and `lambda` and `mu` are the Lame constants. `IsotropicMaterial(young, poisson)` gives them by `lame()`. Young's modulus must be positive. Poisson's ratio must be above -1 and below 0.5.

A strain or a stress has six parts in Voigt order: xx, yy, zz, yz, xz and xy. The shear parts of a strain are engineering shears, twice the tensor parts.

## Quadratic elements

`quadratic_mesh(mesh)` adds a node at the middle of each edge of a linear mesh. Elements that share an edge share its node. Each element then has ten nodes: its four corners, then edges 0-1, 1-2, 0-2, 0-3, 1-3 and 2-3. The mesh's `order` is `QUADRATIC`.

A corner node `i` has the shape function `L_i (2 L_i - 1)`, and the node of edge `i-j` has `4 L_i L_j`, where `L` are the volume coordinates. The strain then varies linearly through the element, so the element can bend. The edges stay straight, and a four-point rule integrates the stiffness exactly.

```mojo
var mesh = quadratic_mesh(box_mesh(Length64(0.6, METER),
    Length64(0.06, METER), Length64(0.06, METER), 10, 1, 1))
```

The stress of a quadratic element is the stress at its centroid. A quadratic mesh refuses `add_element`, which makes four-node elements.

## Supports and loads

| Method | What it does |
|---|---|
| `fix(node, axis, displacement)` | Prescribes the displacement of one node along one axis |
| `load(node, axis, force)` | Adds a force on one node along one axis |
| `press_plane(axis, at, tolerance, stress)` | Adds a uniform normal stress on the outer faces of a plane |
| `apply_gravity(densities, gravity, direction)` | Adds the weight of each element, from a density per material |

`press_plane` gives a face of area `A` a force of `stress * A / 3` on each of three nodes. In a linear mesh these are its corners. In a quadratic mesh they are its edge nodes, and its corners get nothing. These are the consistent loads of three-node and six-node triangles. A positive stress pulls along the axis. A force spread over the nodes of a face by hand is not consistent, and its stress is not uniform.

`apply_gravity` gives an element of weight `W` its consistent loads. A four-node element puts `W / 4` on each corner. A ten-node element puts `-W / 20` on each corner and `W / 5` on each edge node.

```mojo
problem.apply_gravity([Density64(1900, KILOGRAM_PER_CUBIC_METER)],
    Acceleration64(9.80665, METER_PER_SECOND_SQUARED), v3(0, 0, -1))
```

The supports must stop the mesh from moving as a rigid body. A mesh that can still move has a singular stiffness. The solve then raises, or it runs out of iterations.

## The solve

`solve_static(problem, tolerance, max_iterations)` assembles the global stiffness into a sparse matrix of the [Numerics](Numerics) extension. It moves the prescribed displacements to the right-hand side. It then solves the free degrees of freedom by conjugate gradients with a Jacobi preconditioner.

| Field of `StaticResult` | What it holds |
|---|---|
| `displacements` | Three per node, in meters |
| `strains` | Six per element |
| `stresses` | Six per element, in pascals |
| `von_mises` | One `Pressure64` per element |
| `reactions` | Three per node, in newtons, zero where nothing is prescribed |
| `iterations`, `relative_residual`, `status` | How the solve ended |

Check `status`. A solve that runs out of iterations returns its last iterate with `BUDGET_EXHAUSTED`.

## Principal stresses

`result.principal(element)` gives the principal stresses of one element, and `principal_stresses(stress)` gives them for any six stresses in Voigt order. Use them for a brittle material or for bone, which fail by the largest tension or compression.

```mojo
var principal = result.principal(ElementId(12))
print(principal.values[0].to(MEGAPASCAL), principal.values[2].to(MEGAPASCAL))
var along = principal.directions[0]
```

The three `values` run from the largest to the smallest. Each of the `directions` is a unit vector, and the three are square to each other. A direction has an arbitrary sign. When two principal stresses are equal, any two square directions in their plane are correct. The cyclic Jacobi method finds the values and the directions. It runs ten sweeps, and a 3 by 3 tensor reaches rounding within five.

## Draw the result

`stress_geometry(mesh, result, scale, low, high)` returns the outer surface. It moves each node by its displacement times `scale`. Each face takes the color of the von Mises stress of its element. The scale runs through blue, cyan, green, yellow and red from `low` to `high`. Each face has its own vertices, so the colors and normals are flat.

## From CT slices to stresses

![Half of a bone segment from CT: its smoothed label surfaces, and its voxel mesh under a platen colored by von Mises stress](out/ct-to-fem.png)

`examples/ct_to_fem.mojo` makes this picture. It takes a synthetic CT of a bone segment through each step from the scanner files to the stresses:

1. Write each slice as an RLE Lossless DICOM file in memory. Read the files back, and stack them with `stack_slices`.
2. Label the cortical bone from 700 HU and the trabecular bone from 100 HU to 700 HU with `threshold`.
3. Smooth the surface of each label with `smooth_surface`, for the left panel.
4. Mesh the two labels as two materials with `voxel_mesh_labels`.
5. Hold the base on rollers. Press the top with a frictionless platen to a strain of 0.001.
6. Solve, and draw the stresses with `stress_geometry` for the right panel.

The cortical bone has a modulus of 17 GPa and the trabecular bone 1 GPa. Both have a Poisson ratio of 0.3. With one Poisson ratio, the exact solution is a uniform strain, and linear tetrahedra hold it exactly. The platen force must then equal the rule of mixtures, `strain * sum(E * A)`. The example prints 1310.0000000001 N against 1310 N. The cortical shell carries 93 percent of the load, and its stress is 17 MPa against 1 MPa in the core.

## Export to ParaView

`vtk_result(mesh, result)` returns a legacy VTK file that ParaView and other analysis tools read. `vtk_mesh(mesh)` returns the mesh alone.

```mojo
Path("bar.vtk").write_text(vtk_result(problem.mesh, result))
```

The file is an ASCII `UNSTRUCTURED_GRID` in meters. A four-node element is cell type 10. A ten-node element is cell type 24, in VTK's edge order: 0-1, 1-2, 2-0, 0-3, 1-3 and 2-3.

| Field | Kind | What it holds |
|---|---|---|
| `material` | Cell scalar | The element's material index |
| `von_mises` | Cell scalar | The von Mises stress, in pascals |
| `principal` | Cell scalar of 3 | The principal stresses from the largest, in pascals |
| `first_direction` | Cell vector | The direction of the largest principal stress |
| `stress` | Cell tensor | The symmetric stress tensor, in pascals |
| `displacement` | Point vector | The node's displacement, in meters |

Each number is written in full, so it reads back exactly. meshio 5.3.5 read the linear and the quadratic files of a pressed bar, with the expected stress and stretch. It also read the principal fields of a bent beam, which match the eigenvalues that numpy 2.1.3 gives to a relative 1e-15. These checks are not part of the test suite.

## Verification

The tests check these results:

- A bar of 96 elements on symmetry supports is pulled 1 mm along x. Every element has a stress of 100 MPa, to within 1 mPa. The bar narrows by Poisson's ratio, and its end reaction is 100 MN.
- The same bar under a pressure of 9 MPa stretches 90 micrometers, as `sigma L / E` gives.
- An element stiffness is symmetric. A translation and a small rotation cause no force.
- Each principal stress and direction is an eigen-pair of its tensor, and the directions are square. The trace and the von Mises stress do not change. A pure shear `tau` gives `tau`, 0 and `-tau`, and a plane stress gives the center plus and minus the radius of Mohr's circle.
- `von_mises` gives the stress for a uniaxial stress and `sqrt(3) tau` for a pure shear.
- The six tetrahedra of each voxel fill its volume exactly.
- A quadratic bar under a pull or a pressure has the exact uniform stress and stretch.
- A quadratic cantilever of 60 elements bends to 98 percent of beam theory.
- A quadratic element stiffness is symmetric, and its ten shape gradients sum to zero.
- A column standing under its own weight puts all of it on its base. With ten-node elements, its top drops by exactly `rho g L^2 / (2 E)`.
- Two labels meshed together share the nodes of their interface, and each has its own material.
- A column of four voxels with four CT numbers, under 1 MPa, shortens by `p * sum(h / E)`, as springs in series, to a relative 1e-9. One bin takes the mean modulus and the mean density.
- The VTK text of a one-element mesh is exact, and a pulled bar's file holds its stress and displacement.

The example `ct_to_fem` meets the rule of mixtures to 12 digits. See [From CT slices to stresses](#from-ct-slices-to-stresses).

## Bending accuracy

Use quadratic elements for any part that bends. A four-node tetrahedron has a constant strain, so it cannot bend inside itself, and a coarse mesh of them is far too stiff. The tables show the tip deflection of the example's cantilever. Euler-Bernoulli beam theory gives `F L^3 / (3 E I)` = 6.67 mm.

| Linear mesh | Tetrahedra | Tip deflection (mm) | Fraction of beam theory |
|---|---|---|---|
| 20 by 2 by 2 | 480 | 3.38 | 0.51 |
| 40 by 4 by 4 | 3840 | 5.29 | 0.79 |
| 60 by 6 by 6 | 12960 | 5.96 | 0.89 |
| 80 by 8 by 8 | 30720 | 6.25 | 0.94 |

| Quadratic mesh | Tetrahedra | Tip deflection (mm) | Fraction of beam theory |
|---|---|---|---|
| 10 by 1 by 1 | 60 | 6.56 | 0.98 |
| 20 by 2 by 2 | 480 | 6.64 | 1.00 |
| 30 by 3 by 3 | 1620 | 6.66 | 1.00 |
| 40 by 4 by 4 | 3840 | 6.66 | 1.00 |

Shear adds about 0.05 mm to the beam theory value. Check a result against a finer mesh.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| An id names no node, element or material | `add_element`, `fix`, `load`, `displacement`, `StaticProblem` |
| An element is flat | `add_element` |
| A size, a count, a material constant or a load is out of range | `box_mesh`, `IsotropicMaterial`, `fix`, `load`, `press_plane` |
| A label has no voxels | `voxel_mesh` |
| A mesh has a node that no element holds, or is free to move | `solve_static` |
| A result is not for its mesh | `stress_geometry` |

## Limits

- The strains are small, and the materials are linear and isotropic.
- Four-node tetrahedra are stiff in bending. Both orders lock for a Poisson's ratio near 0.5, the four-node ones much more.
- Ten-node tetrahedra have straight edges. A curved boundary is a set of flat faces.
- The loads are static. There is no mass, damping, contact or time.
- The solver is iterative. A large or badly conditioned problem needs a large budget.
- A voxel mesh has stair steps on curved surfaces. The stress at a stair step is not the stress of the smooth shape.

## References

- Zienkiewicz, Taylor and Zhu, "The Finite Element Method: Its Basis and Fundamentals", 7th edition, 2013.
- Hughes, "The Finite Element Method: Linear Static and Dynamic Finite Element Analysis", 2000.
- Kuhn, "Some combinatorial lemmas in topology", 1960.
- van Rietbergen and others, "A new method to determine trabecular bone elastic properties and loading using micromechanical finite-element models", 1995.
- Hestenes and Stiefel, "Methods of conjugate gradients for solving linear systems", 1952.
- Morgan, Bayraktar and Keaveny, "Trabecular bone modulus-density relationships depend on anatomic site", 2003.
