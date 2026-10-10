# CCD cost for walkers and spinning spheres (#728)

This report measures the two CCD contracts that came after the sphere probes: rotation-locked capsules and spheres with an anisotropic inertia tensor. [Issue 728](https://github.com/SethKitchen/ThreeMojo/issues/728) asks for these walker and spinning-body workloads, split from [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635). On these scenes a CCD step costs about two discrete steps. Every body touched the terrain and stayed clear of it within 1 mm.

These are local results. Hosted CI compiles the bench but does not run it.

## Method

`bench/physics_ccd_walker_bench.mojo` builds a rolling terrain of 4 m cells. The corner heights are 0 to 0.16 m, and no triangle slopes more than 0.06. Bodies stand 6 m apart. Each step starts every body 0.1 m above the highest terrain and moves it into the terrain at 30 m/s, with a small sideways speed. The step is 0.01 s, so a body travels 0.3 m in one step. Gravity is on.

- `walker` and `walker-crowd`: upright capsules of radius 0.3 m and half height 0.6 m, mass 70 kg, with every inverse inertia element zero. Friction is 0.8 and restitution is 0.
- `spinning-probe` and `spinning-fleet`: spheres of radius 0.1 m with the inverse tensor diag(250, 500, 125). They spin at (3, 1, -2) rad/s. Friction is 0.5 and restitution is 0.2.

Each scene runs one warm-up step, then twenty timed steps. After each timed step, outside the timing, the bench checks every body:

- **Contact.** In a CCD row, a collision event must pair each body with the terrain. A body with several events counts once.
- **Clearance.** The bench finds the body's gap to the terrain with its own Float64 point-to-triangle distance, which shares no code with the CCD sweep. It measures from the sphere center or from the lower end of the capsule axis to the nine nearest cells, less the radius. The terrain slopes at most 0.06, so the lower end of an upright axis is its nearest point.
- **Local height.** A body whose lowest point is under the terrain height at its own position gets a negative gap.

A CCD row passes when its least gap is above -1 mm. That tolerance is this bench's numerical allowance for Float32 positions near 100 m. It is not the solver's 5 mm contact slop. The measured CCD gaps are within 1.2e-7 m of contact or clear of it.

Controls run first:

- Three events for one body leave another body counted as missing.
- A body 5 cm inside a 0.16 m corner is rejected. The old check, a global floor at the lowest terrain height, passed that body.

Run it with `mojo run -I . bench/physics_ccd_walker_bench.mojo`.

Hardware: AMD Ryzen 9 5900X, WSL 2 on Windows 11, Mojo 1.1.0 (`8189361e`). The world steps on one thread.

## Results

The table gives the median of three runs of the mean step. The last two columns give the least gap over all steps and bodies of a run. Those values were the same in each run.

| Scene | Triangles | Bodies | Discrete step | CCD step | Discrete least gap | CCD least gap |
|---|---:|---:|---:|---:|---:|---:|
| walker | 2,048 | 1 | 0.0016 ms | 0.0048 ms | -0.049 m | -2.5e-8 m |
| walker-crowd | 8,192 | 64 | 0.239 ms | 0.528 ms | -0.200 m | -1.2e-7 m |
| spinning-probe | 2,048 | 1 | 0.0018 ms | 0.0044 ms | -0.049 m | +0.0084 m |
| spinning-fleet | 8,192 | 64 | 0.204 ms | 0.390 ms | -0.200 m | +0.0084 m |

The longest CCD step took 0.62 ms for 64 walkers and 0.48 ms for 64 spinning spheres.

Discrete steps leave bodies up to 20 cm inside raised terrain. CCD stops each walker at contact, and each sphere rebounds a little above the terrain.

## Limits

These rows do not measure interacting moving bodies, because CCD refuses bodies whose reachable regions overlap. That work stays in issue 635. Rollback storage is not measured separately here. The [acceleration report](continuous-collision-636.md) times a failed step with rollback for sphere probes. The numbers describe this machine. They are not a real-time capacity claim.
