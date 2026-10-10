"""Reference original native controls; never run a compiler, suite, or old binary.

This external qualification bridge preserves receipt bytes and original argv/time.
The fresh supervisor runs only this audit and the five newly selected suites.
"""
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), "Missing or symlinked evidence: " + str(path))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def snapshot(folder):
    folder = Path(folder)
    result = {}
    for path in sorted(folder.rglob("*")):
        relative = path.relative_to(folder)
        if any(part in ("__pycache__", ".cache") for part in relative.parts):
            continue
        if relative.parts[:2] == ("coverage", "build"):
            continue
        require(not path.is_symlink(), "Source symlink: " + str(path))
        if path.is_file():
            result[str(relative)] = sha(path)
    return result


def check_pins(spec):
    for path, digest in spec["pinned_files"].items():
        require(sha(path) == digest, "Pinned evidence changed: " + path)


def check_pass(result, name):
    require(result["sequence_completed"] is True and result["failure"] is None,
            name + " sequence did not pass")
    require(result["source_seal_unchanged"] is True and result["sdk_identity_unchanged"] is True,
            name + " identity changed")
    require(result["remaining_owned_descendants"] == [], name + " descendants remain")


def check_log(log, suite_path, expected_count):
    text = log.read_text(encoding="utf-8", errors="strict")
    number = r"[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    lines = text.splitlines()
    headers, summaries, results = [], [], []
    for index, line in enumerate(lines):
        match = re.fullmatch(r"\s*Running\s+(\d+)\s+tests?\s+for\s+(.+?)\s*", line)
        if match:
            headers.append((index, int(match[1]), match[2]))
        match = re.fullmatch(r"\s*Summary\s*\[\s*" + number + r"\s*\]\s*"
                            r"(\d+)\s+tests?\s+run:\s*(\d+)\s+passed\s*,\s*"
                            r"(\d+)\s+failed\s*,\s*(\d+)\s+skipped\s*", line)
        if match:
            summaries.append((index, tuple(map(int, match.groups()))))
        match = re.fullmatch(r"\s*(PASS|FAIL|SKIP)\s*\[\s*(" + number + r")\s*\]\s*(\S+)\s*", line)
        if match:
            results.append((index, match[1], float(match[2]), match[3]))
    require(len(headers) == len(summaries) == 1, "Missing/duplicate native summary")
    require(headers[0][1:] == (expected_count, str(suite_path)), "Native header identity/count differs")
    require(summaries[0][1] == (expected_count, expected_count, 0, 0), "Native summary has deficits/skips")
    require(len(results) == expected_count, "Native result count differs")
    require(all(headers[0][0] < index < summaries[0][0] and status == "PASS" and duration <= 5000
                for index, status, duration, name in results), "Native ordering/pass/5-second cap differs")
    names = [name for _, _, _, name in results]
    defined = re.findall(r"^def\s+(test_\w*)\s*\(", suite_path.read_text(), re.MULTILINE)
    require(len(set(names)) == expected_count and sorted(names) == sorted(defined),
            "Native complete maintained test identity differs")
    return {"runtime_tests": expected_count, "passed": expected_count, "failed": 0, "skipped": 0}


def main():
    require(not sys.flags.optimize and len(sys.argv) == 1, "Unoptimized fixed invocation required")
    here = Path(__file__).resolve().parent
    spec_path = here / "reuse-spec.json"
    spec = read(spec_path)
    require(sha(__file__) == spec["helper_sha256"], "Reuse helper changed")
    check_pins(spec)
    old = Path(spec["original_native"])
    new = Path(spec["new_native"])
    old_clone = Path(spec["original_clone"])
    new_clone = Path(spec["new_clone"])
    original = read(old / "RESULT.json")
    check_pass(original, "Original native")
    check_pass(read(spec["new_prepare_result"]), "Second preparation")
    expected = read(spec["source_seal"])
    require(read(old / "SOURCE-SEAL.json") == read(new / "SOURCE-SEAL.json") == expected,
            "Native source manifests differ")
    require(snapshot(old_clone) == snapshot(new_clone) == expected, "Complete old/new clone manifests differ")
    sdk = read(old / "SDK-BEFORE.json")
    require(sdk == read(old / "SDK-AFTER.json") == read(new / "SDK-BEFORE.json")
            == read(spec["new_prepare_sdk"]) == read(spec["official_sdk_receipt"]), "Official SDK identities differ")
    for folder in (old, new):
        window = read(folder / "WINDOW-START.json")
        require(window["python_optimize"] == 0 and window["runtime_gate_seconds"] == 5
                and window["source_seal_sha256"] == spec["source_seal_sha256"]
                and window["supervisor_sha256"] == spec["supervisor_sha256"], "Supervisor identity/cap differs")
    old_config = read(spec["original_config"])
    stages = old_config["stages"]
    require(len(stages) == len(original["stages"]) == 20, "Original stage inventory differs")
    copies, suites = [], []
    for index, suite in enumerate(spec["reused_suites"]):
        name = Path(suite["path"]).stem
        require(expected[suite["path"]] == suite["sha256"], "Suite source identity differs")
        entries = []
        for offset, mode, cap in ((0, "build", 180), (1, "run", 15)):
            label = name + "-" + mode
            stage = stages[index * 2 + offset]
            path = old / (label + "-RESULT.json")
            record = read(path)
            require(stage["label"] == label and stage["seconds"] == cap
                    and not stage.get("accept_nonzero", False), "Original stage contract differs")
            require(record == original["stages"][index * 2 + offset], "Receipt differs from original global result")
            require(record["label"] == label and record["argv"] == stage["command"]
                    and record["cwd"] == stage["cwd"] == str(old_clone), "Original command identity differs")
            require(record["source_seal_sha256"] == spec["source_seal_sha256"]
                    and record["stage_timeout_seconds"] == cap and record["returncode"] == 0
                    and record["timed_out"] is False and record["leader_reaped"] is True
                    and record["remaining_owned_descendants"] == [], "Original native control failed")
            log = old / (label + ".log")
            require(sha(log) == record["log_sha256"], "Original native log differs")
            if mode == "run":
                command = record["argv"]
                require(command[1] == str(old_clone / "tools/run_suite.py")
                        and command[2:4] == ["--seconds", "5"]
                        and command[4:6] == ["--suite", str(old_clone / suite["path"])], "Original watchdog differs")
                outcome = check_log(log, old_clone / suite["path"], suite["source_test_definitions"])
            for item in (path, log):
                target = new / item.name
                require(not target.exists() and not target.is_symlink(), "Refusing to overwrite evidence: " + str(target))
                copies.append((item, target))
                entries.append({"original": str(item), "referenced_copy": str(target), "sha256": sha(item)})
        suites.append({"suite": suite["path"], "source_sha256": suite["sha256"],
                       "execution": "historical; not rerun in this phase", "outcome": outcome, "files": entries})
    require(len(suites) == 10 and sum(s["outcome"]["runtime_tests"] for s in suites) == 68,
            "Reused control inventory differs")
    manifest = new / "REUSED-NATIVE-CONTROLS.json"
    require(not manifest.exists(), "Reuse manifest already exists")
    check_pins(spec)
    for source, target in copies:
        data = source.read_bytes()
        require(hashlib.sha256(data).hexdigest() == spec["pinned_files"][str(source)], "Copy source changed")
        with target.open("xb") as stream:
            stream.write(data)
        require(sha(target) == sha(source), "Historical receipt/log copy differs")
    check_pins(spec)
    receipt = {"schema": "carla-native-reference-reuse-v1", "validation_complete": True,
               "validated_utc": datetime.now(timezone.utc).isoformat(),
               "claim": "68 previously executed controls referenced; zero old suites executed in this stage.",
               "original_global_result": str(old / "RESULT.json"),
               "original_global_result_sha256": sha(old / "RESULT.json"),
               "source_seal_sha256": spec["source_seal_sha256"],
               "source_manifests_equal": True, "official_sdk_equal": True,
               "new_tests_to_execute": 19, "new_suites_to_execute": spec["new_suites"],
               "spec_sha256": sha(spec_path), "helper_sha256": sha(__file__),
               "original_evidence_sha256": spec["pinned_files"], "reused_controls": suites}
    with manifest.open("x") as stream:
        json.dump(receipt, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print("Validated and referenced 10 historical suites / 68 tests; none re-executed.")
    print("Reference manifest: " + str(manifest))


if __name__ == "__main__":
    main()
