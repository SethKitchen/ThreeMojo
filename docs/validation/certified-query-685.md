# Certified lane query: what #685's items save (#685)

This report measures the opt-in certified lane query on `assets/carla/town.xodr` and decides each open item of [issue 685](https://github.com/SethKitchen/ThreeMojo/issues/685) by its measured gain. Item 1 is merged: each segment keeps its own curve deviation, and the query skips a candidate by it. The skip removes 44 percent of the candidate certifications and gives the same answers on every town query. Items 2, 3, 4 and 6 do not pay on this town, so they keep the present code with the reasons below. Items 5, 7 and 8 were completed earlier.

These are local results. Hosted CI compiles the bench but does not run it.

## Method

`bench/carla_certified_query_bench.mojo` loads the town and builds two queries for each of its 987 lane segments: the segment's midpoint, and that point moved 0.7 m to the side and 0.3 m up. It runs `_closest_lane_certificate_with_work`, the search under `certified_waypoint`, on all 1,974 queries. One pass warms up, then three passes are timed. It reads the query's work counters: refined nodes, candidate lanes, quadrature terms and index pops.

Each run measures three states of one map in one process:

- **Certified.** The query as built, with the per-segment skip.
- **Global deviation.** Every segment carries the global deviation. The per-segment test then equals the early stop, which has already failed, so this is the code path before item 1. The bench compares the waypoint, its station and both certified bounds of every query in the two states and prints the number that differ.
- **Zero-deviation bound.** The global deviation set to zero. This bounds any further gain from tighter deviations. Its answers are not trusted; only its time and work are reported.

It also times one center evaluation over 100,000 calls, for item 6.

Run it with `mojo run -I . bench/carla_certified_query_bench.mojo`. The output of three runs is in [certified-query-685-bench.txt](certified-query-685-bench.txt), with the earlier measurement below it.

Hardware: Intel Xeon processor at 2.80 GHz, a shared 4-vCPU cloud VM, Linux 6.18, Mojo 1.1.0 (`8189361e`). The query runs on one thread. Other jobs kept the load average at 15 to 18 during the runs, so the times are slow and noisy. The work counts do not depend on the machine.

## Results

The table gives the median of three runs. Work counts are per query and were the same in each run.

| Run | Mean | Median | p95 | Nodes | Candidates | Terms | Index pops |
|---|---:|---:|---:|---:|---:|---:|---:|
| Global deviation (before item 1) | 1,575 µs | 261 µs | 8,651 µs | 38.8 | 2.99 | 1,983 | 43.7 |
| Certified, item 1 | 1,406 µs | 184 µs | 8,489 µs | 32.7 | 1.68 | 1,855 | 43.7 |
| Zero-deviation bound | 1,261 µs | 118 µs | 7,652 µs | 29.0 | 1.20 | 1,564 | 24.4 |

All 1,974 answers were the same in the first two states in each run. The town's global curve deviation is 1.0 m, set by one strongly curved segment. One center evaluation takes 0.48 µs on this machine.

An earlier measurement on an AMD Ryzen 9 5900X under WSL 2 had the same work counts. Its medians were 169 µs before item 1 and 125 µs with it, and its means 390 µs and 358 µs.

## Decisions

- **Item 1, per-segment deviation: fixed.** Each segment stores its own certified deviation, and the map keeps their maximum. After the existing early stop, which keeps the global deviation, a candidate whose own lower bound is strictly greater than the best radius is skipped. The skip comes before candidate admission and refinement. It removes 44 percent of the candidate certifications and 16 percent of the refined nodes. The median query is 30 percent faster on this machine and 26 percent faster on the earlier one; the mean is 11 and 8 percent faster. The tree still walks to the global stop, so index pops do not change. Folding the deviation into the tree's own boxes could reach the zero-deviation bound, but it would change the pinned R-tree and its proofs as well. The source edge has its own reviewed lane-oracle record, `tools/carla_lane_oracle/map_deviation_contracts.py`, and `tests/test_carla_segment_deviation.mojo` checks the same answers and lower work on town subsets and the #302 offset-lane probes.
- **Item 2, keep closed cells: keep the reset.** The 2026-10-09 research kept every reset, recheck and work debit. It measured 64 to 89 percent gains on constructed 8, 64 and 256-cell states, but −1.4 to +2.1 percent on the town queries, which is noise. No public town query reaches the many-cell states where the reset costs time.
- **Item 3, moment-table frame: keep the table as it is.** The table serves a spiral with zero heading and zero start curvature, and the general evaluator serves every other spiral with the same certificates. The town has one spiral, and it has zero heading and zero start curvature. So a general frame would change no town answer and no town cost. It would only speed up maps with other spirals.
- **Item 4, duplicated moment-proof code: keep it.** The duplicate costs no query time. Removing it changes the spiral moment table and proof, which 16 and 22 lane-oracle records and proofs pin, for no measured gain.
- **Item 6, endpoint centers: keep the evaluations.** Carrying endpoint centers on the pending entry saves at most two center evaluations for each refined node. With item 1 that is 2 × 0.48 µs × 32.7, about 31 µs a query on this machine and 10 µs on the earlier one. That is 2 to 3 percent of the mean. It would change the pinned refinement for no material gain.

These numbers describe these machines and this town. Maps with longer curved roads or many spirals can weigh the items differently.
