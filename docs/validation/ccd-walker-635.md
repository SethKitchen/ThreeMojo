# CCD cost for walkers and spinning spheres (#635)

This report measures the two CCD contracts that came after the sphere probes: rotation-locked capsules and spheres with an anisotropic inertia tensor. [Issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635) asks for walker and vehicle workloads. A CCD step costs about two discrete steps on these scenes, and no body passes below the terrain.

## Method

`bench/physics_ccd_walker_bench.mojo` builds a rolling terrain of 4 m cells. The corner heights are 0 to 0.16 m. Bodies stand 6 m apart. Each step starts every body just above the terrain and moves it into the terrain at 30 m/s, with a small sideways speed. The step is 0.01 s, so a body travels 0.3 m in one step. Gravity is on.

- `walker` and `walker-crowd`: capsules of radius 0.3 m and half height 0.6 m, mass 70 kg, with every inverse inertia element zero. Friction is 0.8 and restitution is 0.
- `spinning-probe` and `spinning-fleet`: spheres of radius 0.1 m with the inverse tensor diag(250, 500, 125). They spin at (3, 1, -2) rad/s. Friction is 0.5 and restitution is 0.2.

Each scene runs one warm-up step, then twenty timed steps. Each CCD row asserts that every body touched the terrain and that no body went below its floor. The floor is 0.9 m for a capsule center and 0.1 m for a sphere center. The bodies are collision probes. They are not validated walker or vehicle models.

Run it with `mojo run -I . bench/physics_ccd_walker_bench.mojo`.

Hardware: AMD Ryzen 9 5900X, WSL 2 on Windows 11, Mojo 1.1.0 (`8189361e`). The world steps on one thread.

## Results

The table gives the median of three runs of the mean step. The last column is the lowest body center over all steps of one run.

| Scene | Triangles | Bodies | Discrete step | CCD step | Discrete lowest | CCD lowest |
|---|---:|---:|---:|---:|---:|---:|
| walker | 2,048 | 1 | 0.0016 ms | 0.0049 ms | 0.849 m | 0.901 m |
| walker-crowd | 8,192 | 64 | 0.251 ms | 0.545 ms | 0.849 m | 0.901 m |
| spinning-probe | 2,048 | 1 | 0.0020 ms | 0.0045 ms | 0.049 m | 0.111 m |
| spinning-fleet | 8,192 | 64 | 0.241 ms | 0.430 ms | 0.049 m | 0.111 m |

The longest CCD step of 64 walkers took 0.71 ms. The longest CCD step of 64 spinning spheres took 0.52 ms.

Discrete steps leave walkers 5 cm into the terrain and spheres 5 cm below their surface. CCD stops every body at its floor or above it.

## Limits

These rows do not measure interacting moving bodies, because CCD refuses bodies whose reachable regions overlap. They do not measure rollback storage separately. The [acceleration report](continuous-collision-636.md) times a failed step with rollback for sphere probes, and the capsule path saves the same body state. The numbers describe this machine. They are not a real-time capacity claim.
