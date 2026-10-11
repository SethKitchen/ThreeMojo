# CCD cost for interacting moving spheres (#635)

This report measures moving spheres that hit each other under continuous collision, which [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635) asks for. On these scenes a CCD step costs about 1.5 to 17 discrete steps. No sphere passed through another or into the floor.

These are local results. Hosted CI compiles the bench but does not run it.

## Method

`bench/physics_ccd_pairs_bench.mojo` places 64 groups of spheres 6 m apart above a flat floor. Each sphere has a radius of 0.1 m and friction 0.3. Masses alternate between 1 kg and 2 kg. Gravity is off. Each step is 0.01 s, and each step starts every group from the same state:

- `pairs`: two spheres 0.3 m apart close head-on at 30 m/s each. Restitution is 0.5.
- `chains`: four spheres 0.3 m apart in a row. The first moves at 30 m/s into the others. Restitution is 1, so the impacts pass energy along the chain.
- `stacks`: a sphere rests on the floor. A second sphere 0.4 m above it falls onto it at 30 m/s. Restitution is 0, so the impact and the floor contact settle together at one instant.

Each moving sphere also moves sideways at 0.5 m/s. Each scene runs one warm-up step, then twenty timed steps. After each timed step, outside the timing, the bench checks every group with its own code, which shares nothing with the solver:

- **Overlap.** The deepest overlap of two members, or of a member with the floor.
- **Crossing.** Whether two neighbors turned round along the motion, which means that they passed through each other.
- **Momentum.** In a CCD row, linear momentum along the motion is kept, except in stacks, where the floor acts.
- **Energy.** In a CCD row, kinetic energy does not rise.

A CCD row passes when no overlap is deeper than 1 mm and no group crossed. That tolerance is this bench's numerical allowance for Float32 positions near 50 m.

Controls run first. The checks reject two members inside each other, a member in the floor, two members in the wrong order and a faster member.

The bench also times a step that cannot finish. Each stack needs three impacts, and the impact limit is set to one, so the step rolls back.

Run it with `mojo run -I . bench/physics_ccd_pairs_bench.mojo`. The output of three runs, with the revision and the hardware, is in [ccd-pairs-635-bench.txt](ccd-pairs-635-bench.txt).

Hardware: AMD Ryzen 9 5900X, WSL 2 on Windows 11, Mojo 1.1.0 (`8189361e`). The world steps on one thread.

## Results

The table gives the median of three runs of the mean step. The other columns were the same in each run.

| Scene | Spheres | Discrete step | CCD step | CCD impacts a step | Discrete crossed groups | Discrete deepest overlap | CCD deepest overlap |
|---|---:|---:|---:|---:|---:|---:|---:|
| pairs | 128 | 0.054 ms | 0.360 ms | 64 | 64 of 64 | none | none |
| chains | 256 | 0.111 ms | 1.92 ms | 128 | 0 of 64 | 0.200 m | none |
| stacks | 128 | 0.841 ms | 1.29 ms | 192 | 0 of 64 | 0.100 m | 0 m |

In the discrete rows, every head-on pair passes through, each chain ends with spheres 20 cm inside each other, and each falling sphere ends 10 cm inside the one below. In the CCD rows, each pair rebounds, each chain passes its energy along without overlap, and each stack settles in contact.

A rolled-back stack step took 1.10 ms. A step keeps 100 bytes of rollback state for each body: 12,900 bytes for these 129 bodies, with the floor. It also keeps a copy of the previous events and of the primitive order.

## Limits

These are synthetic sphere probes. CCD still refuses boxes and convex hulls, so the bench measures no vehicle chassis. Rotation-locked capsules must still be alone in their group. The [walker report](ccd-walker-728.md) measures walkers that never meet. The numbers describe this machine. They are not a real-time capacity claim.
