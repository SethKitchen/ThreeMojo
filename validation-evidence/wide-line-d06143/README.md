# Wide-line CPU qualification evidence

Commit: d06143b149ba31ab44afaa690c93289b57bc1778
Tree: 9dc0ba7e858c067f76f222c8fbc945317f7dfd02

44 existing tests passed; 0 failed; 0 skipped. These are focused CPU results, not a full audit, coverage proof, GPU qualification, or issue #732 completion.

- test_wide_line_workers: 2 passed, build 45.149 s; runner wall 1.503 s; largest test 904.951 ms.
- test_wide_lines: 36 passed, build 67.345 s; runner wall 0.502 s; largest test 1.159 ms.
- test_renderer_resources: 6 passed, build 49.219 s; runner wall 0.502 s; largest test 83.036 ms.

All final build/run exit codes are 0. The maintained tools/run_suite.py enforced the unchanged 5-second per-test gate and its unchanged suite hang budget. The supervisor allowed five extra seconds only for runner overhead. Separate 300-second compile bounds were not reached. No maintained source, fixture, workload, or cap changed.

## Compiler and target

Official Mojo 1.1.0 (8189361e), Python 3.12.14. The exact commands use build -I . --Werror -o OUTPUT SOURCE. No explicit optimization or target flags were supplied. The pinned compiler's captured build --help states optimization defaults to level 3 and triple/CPU/features default to the host. Thus this run used compiler-default optimization level 3 and host target settings, not explicit -O3 or a manually selected target. Host uname was Linux 6.18.44 x86_64; no separate effective CPU-feature/triple dump was captured. See qualified/compiler-build-help.txt and qualified/results.json.

The official receipt-matched mojo.run._mojo_env() supplied SDK/import/driver paths to the pinned compiler payload. MODULAR_TELEMETRY_ENABLED=false was explicit. HOME, MODULAR_CACHE_DIR, XDG_CACHE_HOME and XDG_DATA_HOME were workspace-local. SDK binary/runtime/library/entrypoint hashes and Python executable hash were checked against the restored identity receipt. See qualified/identity.json and sdk-restored-receipt.json.

## Source and process integrity

3948 archived entries were checked against their exact Git object identities before execution. All tracked source file contents were unchanged afterward. The donor checkout remained clean. source-git-tree.txt preserves exact input blob seals; qualified/identity.json preserves the checks. Native binaries are not bundled; qualified/verified-summary.json seals them with SHA-256.

qualified/results.json records exact commands, working directories, timestamps, elapsed times, exit codes and process-group/descendant cleanup. Raw logs retain real compiler and TestSuite output. Descendant traces sample bounded owned process trees; they are not a complete trace of every transient process. No owned process groups or observed live descendants remained at each recorded command completion.

## Scope limitation

The worker test covers three runs plus a tail, serial versus workers=8, solid/dashed/strand output, and refused-dash propagation. Its fixture has one uniform surface, and corner comparison uses Corner-derived fields. It does not establish correct remapping of distinct preceding Surface records or all Surface-derived fields. No race detector was run. These passing tests do not close issue #732.

## Distinct setup attempts

setup-attempt1 retains initial missing-std diagnostics from a raw compiler invocation without SDK environment. The first build failed with exit 1; the second was interrupted before a final exit record. No tests ran and no pass/skip is claimed for that attempt. Telemetry was unset in that initial launch; it was explicitly disabled in all later launches.

setup-attempt2 supplied official SDK environment and explicitly disabled telemetry, but all three builds failed on an unwritable default cache directory. No tests ran. Workspace-local cache/data locations resolved that setup failure in the qualified run. Nothing in these setup failures is represented as a source failure or a passing test.

## File guide

- qualified/: verified final execution identities, logs, commands, timestamps, process traces, parsed test summary and pinned compiler help.
- setup-attempt1/ and setup-attempt2/: distinct raw setup failures.
- sdk-restored-receipt.json: original SDK/Python identity receipt.
- source-git-tree.txt: exact source Git object seals.
- qualification-harness.py: actual final execution supervisor.
- MANIFEST.sha256: SHA-256 integrity seals for every bundled evidence file except itself.

No caches, binaries, credentials, private notes, or repository writes are included.
