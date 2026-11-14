# Tetrahedral FEM

`extensions/fem/` solves static linear elasticity on meshes of four-node and ten-node tetrahedra. It meshes a box, or the voxels of one label of a label map. It applies supports, nodal forces and surface pressures, and it solves for displacements, stresses and reactions. It draws the deformed surface colored by von Mises stress. It is a library for research and teaching. Its results are not validated for the design of a structure or of a medical device.

![A steel cantilever of ten-node tetrahedra, bent by a load at its tip and colored by von Mises stress](out/tetrahedral-fem.png)

`examples/tetrahedral_fem.mojo` makes this picture. A steel beam 600 mm long and 60 mm square is clamped at one end and meshed with 1620 ten-node tetrahedra. A force of 20 kN pulls its tip down 6.66 mm. Beam theory gives 6.67 mm. The picture shows the beam at 40 times its deflection. The colors run from 0 MPa in blue to 300 MPa in red.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `NodeId`, `ElementId`, `MaterialId`, `DofAxis`, `ElementOrder` and `CapacityKind` |
| `mesh` | `TetMesh`, `box_mesh`, `voxel_mesh`, `voxel_mesh_labels`, `quadratic_mesh`, `boundary_faces`, `edge_pairs` and `signed_volume` |
| `elasticity` | `IsotropicMaterial`, `shape_gradients`, `element_stiffness`, `quadratic_gradients`, `quadratic_stiffness`, `gauss_points`, `element_strain`, `stress_of`, `von_mises`, `principal_stresses` and `PrincipalStress` |
| `static` | `StaticProblem`, `StaticResult`, `assemble` and `solve_static` |
| `post` | `stress_geometry`, `stress_color`, `mode_geometry`, `temperature_geometry` and `dose_geometry` |
| `summary` | `stress_summary`, `MaterialStress` and `strain_energy` |
| `quality` | `element_quality`, `ElementQuality`, `mesh_quality` and `MeshQuality` |
| `probe` | `locate_point`, `MeshPoint`, `sample_field`, `sample_temperature` and `sample_displacement` |
| `dose` | `thermal_dose` and `dose_volume` |
| `export` | `vtk_mesh`, `vtk_result`, `vtk_modes`, `vtk_temperatures`, `vtk_heat`, `vtk_record`, `vtk_series` and `series_names` |
| `density` | `CtDensityLaw`, `element_ct`, `density_materials` and `DensityMaterials` |
| `modal` | `natural_modes`, `ModalResult`, `assemble_mass` and `mass_coefficients` |
| `thermal` | `ThermalMaterial`, `ThermalProblem`, `solve_thermal`, `ThermalResult`, `ThermalCapacity`, `solve_transient`, `TransientResult`, `held_heat`, `HeatRates`, `heat_flux` and `HeatFluxes` |

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

### Mesh quality

A flat or needle-like element makes the stiffness matrix ill conditioned, and the stress near it wrong. `mesh_quality(mesh)` gives the worst shapes of a mesh, and `element_quality(mesh, element)` gives the shape of one element.

```mojo
var q = mesh_quality(problem.mesh)
print(q.worst_ratio, q.worst_element.value, q.smallest_angle.to(DEGREE64), q.largest_angle.to(DEGREE64))
```

| Measure | What it is | Regular tetrahedron |
|---|---|---|
| Radius ratio | `3 r / R`, with `r` the radius of the inscribed sphere and `R` of the circumscribed sphere | 1 |
| Dihedral angle | The angle between the two faces of an edge | `arccos(1/3)`, about 70.5 degrees |

The radius ratio falls toward 0 as an element flattens. A sliver has a dihedral angle near 0 or near 180 degrees. The Kuhn tetrahedra of cubic cells have a radius ratio of `sqrt(3) / (1 + sqrt(2))`, about 0.717. Their dihedral angles are from 45 to 90 degrees. A cell that is not a cube gives other values. A ten-node element is measured by its corners.

A `MeshQuality` holds the least radius ratio and its element, the smallest and largest dihedral angles, and the mean radius ratio.

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
| `heat(expansions, changes)` | Adds the thermal strain of a temperature change at each node |

`press_plane` gives a face of area `A` a force of `stress * A / 3` on each of three nodes. In a linear mesh these are its corners. In a quadratic mesh they are its edge nodes, and its corners get nothing. These are the consistent loads of three-node and six-node triangles. A positive stress pulls along the axis. A force spread over the nodes of a face by hand is not consistent, and its stress is not uniform.

`apply_gravity` gives an element of weight `W` its consistent loads. A four-node element puts `W / 4` on each corner. A ten-node element puts `-W / 20` on each corner and `W / 5` on each edge node.

```mojo
problem.apply_gravity([Density64(1900, KILOGRAM_PER_CUBIC_METER)],
    Acceleration64(9.80665, METER_PER_SECOND_SQUARED), v3(0, 0, -1))
```

`heat(expansions, changes)` takes a coefficient of thermal expansion for each material and a temperature change for each node. Each element grows by `alpha * dT` along each axis, with `dT` the change at its centroid. Where its growth is held, it is stressed: `solve_static` takes the stress from the strain less this thermal strain. Use the temperatures of `solve_thermal`, less the start temperature, for the stress of a heated part.

```mojo
problem.heat([ThermalExpansion64(1.2e-5, PER_KELVIN)], changes)
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

### Summarize the stress of each material

`stress_summary(mesh, result, threshold)` gives a few numbers for each material of a solved model. Use it to report a model of several materials, such as bone with cortical and trabecular labels.

```mojo
for row in stress_summary(problem.mesh, result, Pressure64(100, MEGAPASCAL)):
    print(row.material.value, row.peak.to(MEGAPASCAL), row.mean.to(MEGAPASCAL), row.over.to(CUBIC_METER))
```

| Field | What it holds |
|---|---|
| `elements`, `volume` | The elements of the material, and their volume |
| `peak` | The largest von Mises stress of one element |
| `mean` | The mean von Mises stress, with each element weighted by its volume |
| `over` | The volume of the elements at or above the threshold, such as a yield stress |

A material without elements has no row. The peak of one element depends on the mesh, most at a corner or a stair step of a voxel mesh. The mean and the volume above a stress change less with the mesh.

`strain_energy(problem, result)` gives the work stored in the deformed model, `U = u K u / 2`, as an `Energy64`. It uses the assembled stiffness, so it is exact for both element orders. A model pressed by a prescribed displacement `d` has the apparent stiffness `2 U / d^2`. Studies of whole bones report it.

```mojo
var energy = strain_energy(problem, result).to(JOULE)
var stiffness = 2 * energy / (press * press)
```

## Principal stresses

`result.principal(element)` gives the principal stresses of one element, and `principal_stresses(stress)` gives them for any six stresses in Voigt order. Use them for a brittle material or for bone, which fail by the largest tension or compression.

```mojo
var principal = result.principal(ElementId(12))
print(principal.values[0].to(MEGAPASCAL), principal.values[2].to(MEGAPASCAL))
var along = principal.directions[0]
```

The three `values` run from the largest to the smallest. Each of the `directions` is a unit vector, and the three are square to each other. A direction has an arbitrary sign. When two principal stresses are equal, any two square directions in their plane are correct. The cyclic Jacobi method finds the values and the directions. It runs ten sweeps, and a 3 by 3 tensor reaches rounding within five.

## Natural frequencies

`natural_modes(problem, densities, count, tolerance, max_iterations)` gives the lowest natural frequencies of a problem and their mode shapes. The supports of the problem hold during the vibration. Its loads do not matter.

```mojo
var modes = natural_modes(problem, [Density64(7850, KILOGRAM_PER_CUBIC_METER)],
    3, 1e-10, 200)
print(modes.frequencies[0].to(PER_SECOND), "Hz")
```

Mode `i` solves `K phi = omega^2 M phi`, and its frequency is `omega / (2 pi)`. `M` is the consistent mass from `assemble_mass(mesh, densities)`, with one density for each material. The integrals of the shape functions are exact. `mass_coefficients(nodes)` gives them for an element of unit mass:

| Element | Pair of nodes | Coefficient |
|---|---|---|
| Four nodes | The same node, or two nodes | 1/10, or 1/20 |
| Ten nodes | The same corner, or two corners | 6/420, or 1/420 |
| Ten nodes | A corner and an edge that holds it, or another edge | -4/420, or -6/420 |
| Ten nodes | The same edge, two edges with a shared corner, or opposite edges | 32/420, 16/420, or 8/420 |

The prescribed degrees of freedom are removed, and the subspace iteration of the [Numerics](Numerics) extension solves for the lowest modes. A Sturm check makes sure that no lower mode was missed. Each shape has `phi^T M phi = 1`, and is zero where a degree of freedom is prescribed. Use ten-node elements for bending modes. Four-node elements are too stiff in bending, as in a static problem.

![The first three modes of a steel tuning fork, colored by motion from blue at rest to red](out/fem-modes.png)

`examples/fem_modes.mojo` makes this picture. A steel tuning fork of 5 mm voxels has two tines 80 mm long, 15 mm apart. Ten-node elements fill it, and the bottom of its stem is clamped. The first two modes sway the tines together, at 254 Hz in the plane of the fork and at 256 Hz across it. The third mode, at 485 Hz, moves the tines toward each other. This is the mode that a tuning fork rings in.

The dense fallback of the Sturm check takes at most 4096 free degrees of freedom. Keep a modal mesh below that size.

`mode_geometry(mesh, shape, amplitude)` draws one mode. A mode shape has no size of its own, so the shape is scaled until the node that moves most moves by `amplitude`. Each vertex takes the color of how far its node moves, from blue at rest to red at `amplitude`. `vtk_modes(mesh, modes)` writes every shape for ParaView. See [Export to ParaView](#export-to-paraview).

## Heat conduction

`solve_thermal(problem, tolerance, max_iterations)` gives the steady temperature of each node. The temperature solves

```
div(k grad T) + q + c (T_a - T) = 0
```

where `k` is the conductivity and `q` a heat source per volume, such as the metabolism of tissue or the power of a probe. The term `c (T_a - T)` is Pennes' bioheat term: blood at the arterial temperature `T_a` carries heat away from warmer tissue. The coefficient `c` is the perfusion rate times the density and the specific heat of blood.

```mojo
var tissue = ThermalMaterial(ThermalConductivity64(0.5, WATT_PER_METER_KELVIN),
    PowerDensity64(400, WATT_PER_CUBIC_METER),
    PerfusionCoefficient64(1890, WATT_PER_CUBIC_METER_KELVIN))
var problem = ThermalProblem(mesh^, [tissue], Temperature64(37, CELSIUS))
problem.fix(probe, Temperature64(90, CELSIUS))
var result = solve_thermal(problem, 1e-10, 5000)
```

`fix(node, temperature)` holds a node at a temperature. `convect_plane(axis, at, tolerance, coefficient, ambient)` lets the outer faces on a plane lose `h (T - T_ambient)` per area to a fluid. Each integral is exact for both element orders. Something must set the level of the temperatures: a fixed node, convection or perfusion. Without one, `solve_thermal` refuses the problem.

Pennes' model is a simple model of perfusion. The results are for research and teaching. They are not validated for treatment planning.

### Heat in time

`solve_transient(problem, capacities, initial, step, steps, every, tolerance, max_iterations, capacity)` follows the temperatures from a start. Give a `ThermalCapacity` for each material: its density and its specific heat. Give a start temperature for each node.

```mojo
var water = ThermalCapacity(Density64(1000, KILOGRAM_PER_CUBIC_METER),
    SpecificHeatCapacity64(4000, JOULE_PER_KILOGRAM_KELVIN))
var history = solve_transient(problem, [water], start,
    Duration64(10, SECOND), 360, 30, 1e-10, 5000)
```

Each step is a step of the backward Euler method: `(C / dt + K) T_next = C / dt T + F`, where `C` is the capacity matrix. The method is stable for every step, and its error falls with the step. The fixed nodes hold their temperatures from the first step on. `history.times` gives the time of each record in seconds, and `history.temperatures` the temperature of each node in kelvin. The start is the first record, and then every `every` steps. A step that does not converge within its budget raises an error.

The last argument sets the capacity, `CONSISTENT_CAPACITY` by default or `LUMPED_CAPACITY`:

```mojo
var history = solve_transient(problem, [water], start,
    Duration64(10, SECOND), 360, 30, 1e-10, 5000, LUMPED_CAPACITY)
```

The consistent capacity integrates the products of the shape functions. It is the more accurate. Near a sudden change, a step that is short against `h^2 / alpha` can make it undershoot. `h` is the size of an element, and `alpha` is the conductivity over the density and the specific heat. The temperatures then dip below their bounds for a few steps.

The lumped capacity puts the heat of each element on its nodes in proportion to the consistent diagonal. This is the method of Hinton, Rock and Zienkiewicz. A four-node element gives a quarter of its heat to each corner. A ten-node element gives 1/36 to each corner and 4/27 to each edge node. On four-node elements without obtuse angles, such as the cubes of `box_mesh`, a lumped step keeps each temperature between its bounds. Both kinds keep the heat of an insulated block.

![Half of a block of perfused tissue, cut through a needle held at 70 C, colored from 37 C to 70 C](out/bioheat.png)

`examples/bioheat.mojo` makes this picture. A needle at 70 C enters a block of tissue 40 mm on a side from the top, and stops at the center. The tissue conducts 0.5 W/(m K), makes 400 W/m^3 of metabolic heat, and has a perfusion coefficient of 1890 W/(m^3 K). The block is cut in half through the needle. The tissue is 55 C at 2 mm below the tip, 45 C at 5 mm and 42 C at 10 mm. The needle supplies 0.64 W.

The example reads the temperatures with `sample_temperature`. A point at 2 mm lies between the nodes, which are 2.5 mm apart.

### Heat flux and held heat

`heat_flux(problem, result)` gives the conducted flux `-k grad T` of each element, in W/m^2. `held_heat(problem, result)` gives the heat that each held node supplies to the body, in watts.

```mojo
var flux = heat_flux(problem, result)
print(flux.component(0, DOF_X).to(WATT_PER_SQUARE_METER), flux.magnitude(0).to(WATT_PER_SQUARE_METER))
var rates = held_heat(problem, result)
print(rates.total().to(WATT), "W")
```

A four-node element has one gradient. A ten-node element takes its gradient at its centroid. The flux runs from hot to cold.

The heat rate at a held node is its row of `K T - F`. It is the heat that the held temperature supplies to keep its value. Positive heat enters the body, and a free node has zero. `rates.at(node)` gives one node, and `rates.total()` gives the sum. In a steady state, the sum balances the sources, the perfusion and the convection. Use it with a steady result only.

The bioheat example models half of the block, so the needle supplies twice the total of its held nodes.

`vtk_heat(problem, result)` writes a steady result with both the temperatures and the `heat_flux` cell vectors. Use the Glyph filter of ParaView on `heat_flux` to draw arrows from hot to cold. meshio 5.3.5 read the file of a heated rod, with the exact 410 K at its far end and the flux `q (L - x)` at each centroid. That check is not part of the test suite.

`temperature_geometry(mesh, result, low, high)` colors the outer surface by the temperature of each node, from blue at `low` to red at `high`. `vtk_temperatures(mesh, result)` writes the temperatures for ParaView.

### Thermal dose

`thermal_dose(result)` gives the thermal dose of each node over the records of `solve_transient`, in cumulative equivalent minutes at 43 C (CEM43). `dose_volume(mesh, doses, threshold)` gives the volume of the elements whose corner nodes all reach a dose. Use them for the ablated volume around a heated needle, at the common threshold of 240 minutes.

```mojo
var history = solve_transient(problem, capacities, start, Duration64(1, SECOND), 600, 5, 1e-10, 2000)
var doses = thermal_dose(history)
var ablated = dose_volume(problem.mesh, doses, Duration64(240, MINUTE))
```

Heat kills tissue by the time that it spends hot, and above 43 C each degree doubles the rate. The method of Sapareto and Dewey sums `R^(43 - T) dt` over the intervals, with `T` in Celsius and `dt` in minutes. `R` is 0.5 at or above 43 C, and 0.25 below. Ten minutes at 44 C give 20 minutes, and ten minutes at 42 C give 2.5.

Each interval between two records counts at the mean of its two temperatures. This is exact for a steady temperature. Record often enough that the temperature changes little within one interval.

`dose_geometry(mesh, doses, low, high)` colors the outer surface by the dose of each node. The scale is logarithmic, because doses span many powers of ten. It runs from blue at `low` to red at `high`, such as 1 and 240 minutes.

![A needle heats perfused tissue for six minutes: the final temperatures, and the thermal dose with the ablated zone in red](out/ablation.png)

`examples/ablation.mojo` makes this picture. The block, the needle and the tissue are those of the bioheat example. The tissue starts at 37 C, and the needle holds 90 C for six minutes in steps of two seconds. The left panel is the temperature at the end, and the right panel the dose from 1 to 240 minutes. After six minutes, 0.70 mL reach 240 minutes. At 5 mm below the tip, the tissue is at 44.6 C with a dose of 6.8 minutes.

## Sample a field at a point

`sample_temperature(mesh, result, point)` gives the temperature at a point inside the mesh, such as the place of a thermocouple. `sample_displacement(mesh, result, point)` gives the displacement there, in meters.

```mojo
var probe = v3(0.02, 0.02, 0.018)
print(sample_temperature(problem.mesh, result, probe).to(CELSIUS))
var at = locate_point(mesh, probe)
var values = sample_field(mesh, at, result.displacements, 3)
```

`locate_point(mesh, point)` finds the element that holds the point, and the point's four volume coordinates in it. `sample_field(mesh, at, values, components)` gives any nodal field there, with `components` numbers per node. The value comes from the shape functions of the element. So a four-node element samples a linear field exactly, and a ten-node element samples a quadratic field exactly.

A point counts as inside an element when each volume coordinate is at least `-1e-9`. A point on a face that two elements share is in both, and the element with the lower index counts. The field is continuous across the face, so both elements give the same value to rounding.

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
| `temperature` | Point scalar | The temperature of a node, in kelvin, from `vtk_temperatures` and `vtk_heat` |
| `heat_flux` | Cell vector | The conducted heat flux of an element, in W/m^2, from `vtk_heat` |
| `first_direction` | Cell vector | The direction of the largest principal stress |
| `stress` | Cell tensor | The symmetric stress tensor, in pascals |
| `displacement` | Point vector | The node's displacement, in meters |

`vtk_modes(mesh, modes)` writes the mesh with one point vector per mode shape, `mode_1`, `mode_2` and on. The title line gives the frequencies in hertz. Use the Warp By Vector filter of ParaView to animate a shape.

Each number is written in full, so it reads back exactly. meshio 5.3.5 read the linear and the quadratic files of a pressed bar, with the expected stress and stretch. It also read the principal fields of a bent beam, which match the eigenvalues that numpy 2.1.3 gives to a relative 1e-15. It also read the mode shapes of a rod as `mode_1` and `mode_2` on 81 points. These checks are not part of the test suite.

## Write a time series

Write a transient history as a file series to play it in ParaView. Write one VTK file for each record, and one series file that lists them.

```mojo
var names = series_names("heat", len(history.times))
for k in range(len(names)):
    Path(names[k]).write_text(vtk_record(problem.mesh, history, k))
Path("heat.vtk.series").write_text(vtk_series(names, history))
```

`series_names(stem, count)` gives the names `heat_0000.vtk`, `heat_0001.vtk` and on. The number has more digits when the count needs them. `vtk_record(mesh, history, record)` writes one record as `vtk_temperatures` does, with its time in the title line.

`vtk_series(names, history)` writes the series file in JSON, version 1.0. It lists each name with its time in seconds. ParaView 5.5 and later opens a file whose name ends in `.vtk.series` as one data set in time. A name is relative to the series file. A name must not hold a quote, a backslash or a control character.

meshio 5.3.5 read the five records of a heated bar, with 99 points and the temperature field of each. Python's JSON reader read the series file with the five times. These checks are not part of the test suite.

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
- A free bar heated by 50 K grows by `alpha dT` times each distance, with no stress. Held at both ends, it has a uniaxial stress of exactly `-E alpha dT`, for both element orders.
- A rod that is fixed at one end moves along its axis only. It rings at `c / (4 L)` to a relative 1e-6, and at `3 c / (4 L)` to 1e-4.
- A steel cantilever is 0.6 m long and 60 mm square. With ten-node elements it bends at 136.9 Hz with 10 cells and 136.2 Hz with 20. Euler-Bernoulli gives 135.9 Hz. The two bending modes of the square section agree to 1 percent.
- The consistent mass coefficients sum to one, and a rigid move carries the whole mass.
- A drawn rod mode moves its free end by the amplitude, in red, and leaves the clamp blue.
- A linear temperature between two fixed ends is exact, and convection at one end gives the exact line, for both element orders.
- A uniform source gives the exact parabola `q x (L - x) / (2 k)` at every node of ten-node elements.
- A sine between two held ends decays as `exp(-t / tau)` within 0.2 percent. Very long steps reach the steady state, and a uniform start in an insulated block stays uniform.
- A bar starts at 310 K, and its end is held at 330 K. With a consistent capacity and steps of 30 s, it dips more than 1 K below its start. With a lumped capacity, it stays between 310 K and 330 K to the solver's tolerance. An insulated bar from 310 K to 320 K evens out at 315 K with a lumped capacity, for both element orders.
- A rod between 310 K and 330 K has the flux `-k dT/dx` in every element, for both orders. Its VTK file holds that flux in each cell after the materials. `k A dT / L` enters at its hot end and leaves at its cold end, to 1e-9. A uniform source `q` in a rod held at both ends sends `q V` out through the ends, half at each.
- A probe in perfused tissue gives the `cosh` profile of Pennes' equation within 1 percent. Without a fixed node, perfusion holds the tissue at `T_a + q / c`.
- A column of four voxels with four CT numbers, under 1 MPa, shortens by `p * sum(h / E)`, as springs in series, to a relative 1e-9. One bin takes the mean modulus and the mean density.
- The regular tetrahedron has a radius ratio of 1 and every dihedral angle `arccos(1/3)`. A path through a cube has the ratio `sqrt(3) / (1 + sqrt(2))` and angles from 45 to 90 degrees. So does every element of a box of cubes, for both orders. A sliver is the worst element of its mesh.
- A pulled bar of 200 GPa, 2 m long and 1 m square, stretched 2 mm, stores 200 kJ, for both element orders. Its apparent stiffness `2 U / d^2` is `E A / L`, 100 GN/m.
- Given stresses on a box of two cubes give each material's count, volume, peak, mean and volume above a threshold exactly. A material without elements has no row. A pulled bar at 200 MPa has that stress as its peak and its mean, with its whole volume above 199 MPa.
- A linear field sampled at 12 points between the nodes of a box is exact on both orders. A quadratic field is exact on ten-node elements. At a node, the sample is the node's value. A point on a face lies in two elements, the lower one counts, and both give one value. Steady conduction from 300 K to 400 K samples to its straight line at every point.
- Ten minutes at 43, 44, 42 and 37 C give doses of 10, 20 and 2.5 minutes, and `10 / 4^6`. An interval from 42 to 44 C counts at 43 C. A block held at 50 C through `solve_transient` for two minutes has a dose of 256 minutes at every node. Its dosed volume is the whole block, or one cube when only that cube's nodes reach the threshold.
- On a dose map, a dose below the low end takes the scale's blue, and a dose past the high end its red. A mesh without nodes draws nothing.
- The VTK text of a one-element mesh is exact, and a pulled bar's file holds its stress and displacement.
- A record of a history is the temperature file of its values, with its time in the title. A series file lists each name with its time, and names get a fifth digit past 10000 records.

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
| A result is not for its mesh, or a stress threshold is negative or not finite | `stress_summary`, `strain_energy` |
| A mesh has no element, or an element id names no element | `mesh_quality`, `element_quality` |
| A dose has fewer than two records, times that do not rise, records of other sizes, doses that do not fit the mesh, or a bad threshold or scale | `thermal_dose`, `dose_volume`, `dose_geometry` |
| No element holds a point, or a field or a mesh point does not fit the mesh | `locate_point`, `sample_field`, `sample_temperature`, `sample_displacement` |
| A result is not for its problem, or an element, a node or an axis is out of range | `held_heat`, `heat_flux`, `HeatRates`, `HeatFluxes` |
| The capacities or the start do not fit the problem, a step or a count is out of range, or a capacity kind is not valid | `solve_transient`, `ThermalCapacity` |
| A record is outside its history, or a series name is empty or holds a quote, a backslash or a control character | `vtk_record`, `vtk_series`, `series_names` |

## Limits

- The strains are small, and the materials are linear and isotropic.
- Four-node tetrahedra are stiff in bending. Both orders lock for a Poisson's ratio near 0.5, the four-node ones much more.
- Ten-node tetrahedra have straight edges. A curved boundary is a set of flat faces.
- The elastic loads are static. There is no damping, contact or response to a load in time.
- A consistent capacity can undershoot near a sudden change, when the step is short against `h^2 / alpha`. Use `LUMPED_CAPACITY` or a finer mesh. A lumped capacity keeps the bounds on four-node elements without obtuse angles only.
- The solver is iterative. A large or badly conditioned problem needs a large budget.
- A voxel mesh has stair steps on curved surfaces. The stress at a stair step is not the stress of the smooth shape.
- A thermal dose of 240 minutes is a threshold from research, and tissues differ. A dosed volume is not a prediction of a treatment.

## References

- Zienkiewicz, Taylor and Zhu, "The Finite Element Method: Its Basis and Fundamentals", 7th edition, 2013.
- Hughes, "The Finite Element Method: Linear Static and Dynamic Finite Element Analysis", 2000.
- Kuhn, "Some combinatorial lemmas in topology", 1960.
- van Rietbergen and others, "A new method to determine trabecular bone elastic properties and loading using micromechanical finite-element models", 1995.
- Hestenes and Stiefel, "Methods of conjugate gradients for solving linear systems", 1952.
- Morgan, Bayraktar and Keaveny, "Trabecular bone modulus-density relationships depend on anatomic site", 2003.
- Bathe, "Finite Element Procedures", 2nd edition, 2014, sections 10.2 and 11.6.
- Hinton, Rock and Zienkiewicz, "A note on mass lumping and related processes in the finite element method", 1976.
- Pennes, "Analysis of tissue and arterial blood temperatures in the resting human forearm", 1948.
- Sapareto and Dewey, "Thermal dose determination in cancer therapy", International Journal of Radiation Oncology, Biology, Physics, 1984.
