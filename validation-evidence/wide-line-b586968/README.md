# Fresh wide-line CPU qualification

44/44 existing tests passed; 0 failed; 0 skipped.

Commit: b58696822061877236383642380068fb61346b54
Tree: 097409976c4c3bc628b09642044c4de0dd756a34

## Results
- test_wide_line_workers: 2 passed; --Werror build 43.653 s, runner wall 1.504 s, largest test 1243.334 ms.
- test_wide_lines: 36 passed; --Werror build 57.677 s, runner wall 0.501 s, largest test 1.903 ms.
- test_renderer_resources: 6 passed; --Werror build 48.657 s, runner wall 0.502 s, largest test 69.347 ms.

All six build/run exit codes are 0. No owned process groups or observed live descendants remained. Traces sample bounded owned process trees, not every transient process.

## Source and SDK
The isolated archive contained 3949 Git entries. All source blobs matched exact Git object seals before execution and all tracked source files were unchanged afterward. The donor checkout was clean before and after. source-git-tree.txt preserves exact source seals.
Official Mojo 1.1.0 (8189361e), Python 3.12.14. Compiler, std.mojoc, runtime, official Python entrypoint payloads and Python executable were checked against sdk-restored-receipt.json. identity.json records actual launcher/compiler/Python hashes and checks.
The official virtualenv/bin/mojo launcher supplied SDK paths. Telemetry was explicitly disabled with MODULAR_TELEMETRY_ENABLED=false. Ambient SDK, library and Python overrides were removed. HOME/MODULAR_CACHE_DIR/XDG_CACHE_HOME/XDG_DATA_HOME were new workspace-local directories. This run reused neither prior binaries nor prior results.

## Flags and bounds
Exact builds use: mojo build -I . --Werror -o OUTPUT SOURCE, through maintained compiler_telemetry.py and native_test_support.py. There are no explicit optimization or target flags. Captured pinned compiler build --help states optimization defaults to level 3 and target triple/CPU/features default to the host. This is compiler-default level 3 and host-target qualification, not an explicit -O3 or manually selected target. Host uname: Linux 6.18.44 x86_64. No separate effective CPU-feature/triple dump was captured.
The unchanged maintained run_suite.py enforces 5 seconds per test and its source-count-derived suite hang budget. The outer supervisor adds five seconds only for runner overhead. Separate 300-second compile hang bounds were not reached. No source, fixture, workload or maintained cap was edited.

## Scope
The strengthened worker fixture exercises a distinct preceding dashed-line material/surface, serial-versus-parallel corner surface indices and selected Surface state, three wide-line runs plus a tail, solid/dashed/strand output, an empty first run, and refusal propagation. This is focused CPU evidence for the existing fixture. It is not a race-detector result, full audit, full coverage, GPU qualification, or full issue-closure claim.

## Evidence guide
- identity.json: source/SDK/environment checks and final cleanliness.
- results.json: literal commands, working directories, timestamps, exit codes, timings and descendant cleanup.
- *.build.log / *.run.log: raw compiler and TestSuite output.
- *.descendants.jsonl: bounded owned-process observations.
- verified-summary.json: parsed passing results and native binary hashes.
- source-git-tree.txt and sdk-restored-receipt.json: input seals.
- compiler-build-help.txt: actual pinned compiler default documentation.
- qualification-harness.py: actual supervising harness.
- MANIFEST.sha256: SHA-256 of every bundled file except itself.

No failed setup attempts occurred in this fresh qualification. Old revision attempts/results are not bundled. No caches, binaries, private notes, or external repository writes are included.
