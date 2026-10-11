# Certified lane query: what #685's items save (#685)

This report measures the opt-in certified lane query on `assets/carla/town.xodr` and decides each open item of [issue 685](https://github.com/SethKitchen/ThreeMojo/issues/685) by its measured gain. Item 1 pays: skipping candidates by their own curve deviation cuts the median query by about 26 percent with identical answers. Items 2, 3, 4 and 6 do not pay on this town, so they keep the present code with the reasons below.

These are local results. Hosted CI compiles the bench but does not run it.

## Method

`bench/carla_certified_query_bench.mojo` loads the town and builds two queries for each of its 987 lane segments: the segment's midpoint, and that point moved 0.7 m to the side and 0.3 m up. It runs `_closest_lane_certificate_with_work`, the search under `certified_waypoint`, on all 1,974 queries. One pass warms up, then three passes are timed. It reads the query's work counters: refined nodes, candidate lanes, quadrature terms and index pops.

It also bounds two items without changing a pinned source:

- **Item 1.** The same queries with the global curve deviation set to zero. A per-segment deviation lies between zero and the global value, so the difference bounds its gain. The zero-deviation answers are not trusted; only their time and work are reported.
- **Item 6.** The cost of one center evaluation, timed over 100,000 calls, times two evaluations for each refined node.

Run it with `mojo run -I . bench/carla_certified_query_bench.mojo`. The output of three runs before and after item 1, with the revision and the hardware, is in [certified-query-685-bench.txt](certified-query-685-bench.txt).

Hardware: AMD Ryzen 9 5900X, WSL 2 on Windows 11, Mojo 1.1.0 (`8189361e`). The query runs on one thread.

## Results

The table gives the median of three runs. Work counts are per query and were the same in each run.

| Run | Mean | Median | p95 | Nodes | Candidates | Terms | Index pops |
|---|---:|---:|---:|---:|---:|---:|---:|
| Certified, before | 390 µs | 169 µs | 1,274 µs | 38.8 | 2.99 | 1,983 | 43.7 |
| Zero-deviation bound | 311 µs | 75 µs | 1,205 µs | 29.0 | 1.20 | 1,564 | 24.4 |
| Certified, item 1 | 358 µs | 125 µs | 1,245 µs | 32.7 | 1.68 | 1,855 | 43.7 |

The town's global curve deviation is 1.0 m, set by one strongly curved segment. One center evaluation takes 0.15 µs.

## Decisions

- **Item 1, per-segment deviation: fix.** Each segment stores its own certified deviation. After the existing early stop, which keeps the global deviation, a candidate whose own lower bound exceeds the best radius is skipped. That skips about 44 percent of candidate certifications and cuts the median query by 26 percent and the mean by 8 percent. On all 2,961 town queries of the comparison, the answers are identical, including the same four that exhaust the work limit. The tree still walks to the global stop, so index pops do not change. Folding the deviation into the tree's own boxes could reach the zero-deviation bound, but it would change the pinned R-tree and its proofs as well.
- **Item 2, keep closed cells: keep the reset.** The 2026-10-09 research kept every reset, recheck and work debit. It measured 64 to 89 percent gains on constructed 8, 64 and 256-cell states, but −1.4 to +2.1 percent on the town queries, which is noise. No public town query reaches the many-cell states where the reset costs time.
- **Item 3, moment-table frame: keep the table as it is.** The table serves a spiral with zero heading and zero start curvature, and the general evaluator serves every other spiral with the same certificates. The town has one spiral, and it has zero heading and zero start curvature. So a general frame would change no town answer and no town cost. It would only speed up maps with other spirals.
- **Item 4, duplicated moment-proof code: keep it.** The duplicate costs no query time. Removing it changes the spiral moment table and proof, which 16 and 22 lane-oracle records and proofs pin, for no measured gain.
- **Item 6, endpoint centers: keep the evaluations.** Carrying endpoint centers on the pending entry saves at most two center evaluations for each refined node: 2 × 0.15 µs × 38.8, about 12 µs a query. That is about 3 percent of the mean. It would change the pinned refinement for no material gain.

These numbers describe this machine and this town. Maps with longer curved roads or many spirals can weigh the items differently.
