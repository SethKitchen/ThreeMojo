# CCD cost for walkers and spinning spheres (#728)

This report measures the two CCD contracts that came after the sphere probes: rotation-locked capsules and spheres with an anisotropic inertia tensor. [Issue 728](https://github.com/SethKitchen/ThreeMojo/issues/728) asks for these walker and spinning-body workloads, split from [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635). On these scenes a CCD step costs about two to three discrete steps. Every body touched the terrain and stayed clear of it within 1 mm.

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

Hardware: Intel Xeon processor at 2.80 GHz, a 4-vCPU cloud Linux virtual machine (kernel 6.18), Mojo 1.1.0 (`8189361e`). The world steps on one thread.

## Results

Each scene runs with 1 and with 64 bodies on 2,048 and on 8,192 triangles, so the body count and the triangle count change one at a time. The step columns give the median of three runs. "Mean" is the mean of a run's twenty timed steps, and "max" is its longest timed step. The last two columns give the least gap over all steps and bodies of a run. Those values were the same in each run.

| Scene | Triangles | Bodies | Discrete mean | Discrete max | CCD mean | CCD max | Discrete least gap | CCD least gap |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| walker | 2,048 | 1 | 0.0018 ms | 0.0033 ms | 0.0066 ms | 0.0110 ms | -0.049 m | -2.5e-8 m |
| walker | 8,192 | 1 | 0.0039 ms | 0.0061 ms | 0.0087 ms | 0.0131 ms | -0.049 m | -2.5e-8 m |
| walker-crowd | 2,048 | 64 | 0.225 ms | 0.291 ms | 0.481 ms | 0.796 ms | -0.200 m | -1.2e-7 m |
| walker-crowd | 8,192 | 64 | 0.285 ms | 0.345 ms | 0.629 ms | 0.827 ms | -0.200 m | -1.2e-7 m |
| spinning-probe | 2,048 | 1 | 0.0019 ms | 0.0035 ms | 0.0062 ms | 0.0102 ms | -0.049 m | +0.0084 m |
| spinning-probe | 8,192 | 1 | 0.0049 ms | 0.0198 ms | 0.0084 ms | 0.0125 ms | -0.049 m | +0.0084 m |
| spinning-fleet | 2,048 | 64 | 0.106 ms | 0.141 ms | 0.315 ms | 0.374 ms | -0.200 m | +0.0084 m |
| spinning-fleet | 8,192 | 64 | 0.254 ms | 0.419 ms | 0.506 ms | 0.766 ms | -0.200 m | +0.0084 m |

On this virtual machine one maximum can be several times its mean, because other work shares the host. Use the means to compare rows.

Discrete steps leave bodies up to 20 cm inside raised terrain. CCD stops each walker at contact, and each sphere rebounds a little above the terrain. The least gaps do not change with the terrain size, because the terrain repeats.

An earlier version of this report ran only the 1-body scenes on 2,048 triangles and the 64-body scenes on 8,192 triangles, on an AMD Ryzen 9 5900X under WSL 2. Its means were in the same range.

## Limits

These rows measure bodies that never meet. The [interacting-sphere report](ccd-pairs-635.md) measures pairs, chains and struck stacks, and a rolled-back step with its rollback storage. Rollback storage is not measured separately here. The [acceleration report](continuous-collision-636.md) times a failed step with rollback for sphere probes. The numbers describe this machine. They are not a real-time capacity claim.
