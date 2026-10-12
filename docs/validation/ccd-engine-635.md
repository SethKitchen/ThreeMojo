# CCD cost for turning boxes, walkers and interacting bodies (#635)

This report measures the conservative-advancement engine of [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635). It times a turning box chassis, turning capsule walkers in pairs, and a chassis that lands on a resting ball and cube. It also times a rolled-back step and gives its rollback storage. On these scenes a CCD step costs about 1.3 to 8 discrete steps. Piles in which a light cube grinds under a sliding chassis cost about 40 to 90. No body sank into the terrain by more than two tolerances.

These are local results from one shared cloud machine. Hosted CI compiles the bench but does not run it. The chassis is a collision probe for a vehicle body, not a validated vehicle model. It has no wheels, suspension or tire forces.

## Method

`bench/physics_ccd_engine_bench.mojo` builds the rolling terrain of the [walker report](ccd-walker-728.md): 4 m cells, corner heights 0 to 0.16 m and slopes of at most 0.06. Gravity is on, and each step is 0.01 s. Each scene runs one warm-up step, then twenty timed steps. Each step starts every group from the same state:

- `chassis-drive`: 32 chassis, 12 m apart, drive level at 20 m/s and yaw at 0.5 rad/s, clear of the terrain. A chassis is a 1500 kg box, 4.5 m by 2 m by 1.5 m, with its own anisotropic tensor.
- `chassis` and `chassis-fleet`: one and 32 chassis start 0.35 m above the terrain, tilted. They fall at 40 m/s while they move at 20 m/s and turn at (1.5, -1, 2) rad/s.
- `walker-pairs`: 32 pairs of turning capsules walk into each other at 3 m/s each while they fall at 40 m/s. A walker has radius 0.3 m, half height 0.6 m and mass 70 kg. Each pair is one group.
- `pile`: 16 piles 48 m apart. A falling chassis lands on a 20 kg ball and a 200 kg cube that rest on the terrain.
- `pile-crowd`: the same piles 12 m apart. The ball is light, so the group's energy bound reaches far and joins all 48 bodies into one group.
- `rollback`: the `pile` step with an impact limit of one. Each step fails and restores the world.

The pile scenes raise the impact limit to 1024 and the sub-step limit to 65536. A light cube that a sliding chassis rolls along the terrain closes on it again as it turns. Each re-closing costs a response.

After each timed step, outside the timing, the bench checks every body:

- **Contact.** In a CCD row, except `chassis-drive`, an event must name every body.
- **Clearance.** The bench finds the height of each box corner, or of the lowest point of a sphere or capsule, over the terrain plane under it. It uses its own code. The terrain slopes at most 0.06, so a vertical depth is at most 1.002 times the depth along the normal.

A CCD row passes when no body is deeper than two of its tolerances. A body that another body presses on can deepen an overlap by one tolerance in a sub-step before its response opens it. A chassis has a tolerance of 2.5 mm, a cube 0.85 mm, a ball 0.39 mm and a walker 0.29 mm.

Controls run first. The checks reject a missing contact and a chassis 5 cm inside a raised corner. They pass a chassis 2 mm above it.

The rollback storage is the step state of every body, the previous events and the body order, in bytes.

Run it with `mojo run -I . bench/physics_ccd_engine_bench.mojo`. The output of three runs, with the revision and the hardware, is in [ccd-engine-635-bench.txt](ccd-engine-635-bench.txt).

Hardware: Intel Xeon at 2.8 GHz, a 4-vCPU shared cloud VM, Mojo 1.1.0 (`8189361e`). The world steps on one thread. Other work on the shared machine adds noise, so each table value is the median of three runs.

## Results

The table gives the median of three runs of the mean step. The gap columns give the least clearance over all steps and bodies of a run, which was the same in each run. A negative gap is a depth.

| Scene | Triangles | Bodies | Discrete step | CCD step | Discrete least gap | CCD least gap | Rollback storage |
|---|---:|---:|---:|---:|---:|---:|---:|
| chassis-drive | 8,192 | 32 | 1.72 ms | 2.31 ms | +0.284 m | +0.284 m | 3,556 B |
| chassis | 2,048 | 1 | 0.020 ms | 0.158 ms | -0.177 m | +0.0026 m | 272 B |
| chassis-fleet | 8,192 | 32 | 1.41 ms | 9.62 ms | -0.257 m | +0.0026 m | 6,628 B |
| walker-pairs | 8,192 | 64 | 0.40 ms | 2.43 ms | -0.350 m | +0.0002 m | 12,324 B |
| pile | 8,192 | 48 | 1.52 ms | 66.0 ms | +0.0002 m | -0.0007 m | 63,908 B |
| pile-crowd | 8,192 | 48 | 1.37 ms | 122.9 ms | +0.0002 m | +0.0000004 m | 57,060 B |
| rollback | 8,192 | 48 | | 162.2 ms | | | 5,284 B |

The rollback storage is measured after the last step, and the reports of that step count in it. The failed step of the `rollback` row keeps the reports of the step before it.

Discrete steps leave a landing chassis up to 26 cm and a walker up to 35 cm inside the terrain. CCD stops every chassis and walker at contact or above it. In the `pile` rows the chassis presses a cube 0.73 mm into the terrain. That is within two of its 0.85 mm tolerances. The discrete `pile` rows stop the chassis on the pile before it reaches the terrain.

A driving chassis that keeps clear of the terrain costs 1.3 discrete steps. A tumbling landing costs 7 to 8, and a walker pair 6. A pile costs 40 to 90, because each grinding re-closing is a response. The `rollback` step fails late, after most piles have finished, so it costs about as much as a successful `pile` step.

## Limits

The numbers describe this machine. They are not a real-time capacity claim. The chassis rows show collision cost only.

Persistent contacts are the expensive case. A body that turns while it stays in contact needs a response each time it closes again. The `pile` rows show tens to hundreds of responses for one landing. The energy-based groups also join light bodies near heavy fast ones, and a large group costs more than its parts. Compare `pile` with `pile-crowd`.

The bench does not measure rays, cold index construction or the scenes of the earlier reports.
