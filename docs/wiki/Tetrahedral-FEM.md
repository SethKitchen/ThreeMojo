# Tetrahedral FEM

`extensions/fem/` solves static linear elasticity on meshes of four-node and ten-node tetrahedra. It meshes a box, or the voxels of one label of a label map. It applies supports, nodal forces and surface pressures, and it solves for displacements, stresses and reactions. It draws the deformed surface colored by von Mises stress. It is a library for research and teaching. Its results are not validated for the design of a structure or of a medical device.

![A steel cantilever of ten-node tetrahedra, bent by a load at its tip and colored by von Mises stress](out/tetrahedral-fem.png)

`examples/tetrahedral_fem.mojo` makes this picture. A steel beam 600 mm long and 60 mm square is clamped at one end and meshed with 1620 ten-node tetrahedra. A force of 20 kN pulls its tip down 6.66 mm. Beam theory gives 6.67 mm. The picture shows the beam at 40 times its deflection. The colors run from 0 MPa in blue to 300 MPa in red.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `NodeId`, `ElementId`, `MaterialId`, `DofAxis` and `ElementOrder` |
| `mesh` | `TetMesh`, `box_mesh`, `voxel_mesh`, `quadratic_mesh`, `boundary_faces`, `edge_pairs` and `signed_volume` |
| `elasticity` | `IsotropicMaterial`, `shape_gradients`, `element_stiffness`, `quadratic_gradients`, `quadratic_stiffness`, `gauss_points`, `element_strain`, `stress_of` and `von_mises` |
| `static` | `StaticProblem`, `StaticResult`, `assemble` and `solve_static` |
| `post` | `stress_geometry` and `stress_color` |

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

Each cube becomes six tetrahedra that share the diagonal from its low corner to its high corner. This is the Kuhn split. Neighbor cubes then share whole faces, so the mesh is conforming.

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

`press_plane` gives a face of area `A` a force of `stress * A / 3` on each of three nodes. In a linear mesh these are its corners. In a quadratic mesh they are its edge nodes, and its corners get nothing. These are the consistent loads of three-node and six-node triangles. A positive stress pulls along the axis. A force spread over the nodes of a face by hand is not consistent, and its stress is not uniform.

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

## Draw the result

`stress_geometry(mesh, result, scale, low, high)` returns the outer surface. It moves each node by its displacement times `scale`. Each face takes the color of the von Mises stress of its element. The scale runs through blue, cyan, green, yellow and red from `low` to `high`. Each face has its own vertices, so the colors and normals are flat.

## Verification

The tests check these results:

- A bar of 96 elements on symmetry supports is pulled 1 mm along x. Every element has a stress of 100 MPa, to within 1 mPa. The bar narrows by Poisson's ratio, and its end reaction is 100 MN.
- The same bar under a pressure of 9 MPa stretches 90 micrometers, as `sigma L / E` gives.
- An element stiffness is symmetric. A translation and a small rotation cause no force.
- `von_mises` gives the stress for a uniaxial stress and `sqrt(3) tau` for a pure shear.
- The six tetrahedra of each voxel fill its volume exactly.
- A quadratic bar under a pull or a pressure has the exact uniform stress and stretch.
- A quadratic cantilever of 60 elements bends to 98 percent of beam theory.
- A quadratic element stiffness is symmetric, and its ten shape gradients sum to zero.

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
