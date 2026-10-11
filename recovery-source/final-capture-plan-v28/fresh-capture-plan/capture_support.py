"""Prepared source-bound qualification support; execute only in the approved lane.

Target bytes are frozen before captures. Maintained proof/capture validation is
never replaced. A structured validated coverage deficit is not a tool failure.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
REPORT_SCHEMA = "carla-maintained-report-result-v1"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dump(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def dump_new(path, value):
    with Path(path).open("x") as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + "\n")


def snapshot(root):
    # Match run_stage exactly. Do not cache a source-admission result.
    return {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob("*"))
            if p.is_file()
            and not any(part in ("__pycache__", ".cache") for part in p.relative_to(root).parts)
            and p.relative_to(root).parts[:2] != ("coverage", "build")}


def load_tools(clone):
    sys.path.insert(0, str(clone / "tools"))
    import coverage_loop_proofs
    import coverage_io
    for module in (coverage_loop_proofs, coverage_io):
        if Path(module.__file__).resolve().parent != clone / "tools":
            raise ValueError("Wrong executing maintained tool")
    return coverage_loop_proofs, coverage_io


def target_material(plan, clone, build, envelope):
    """Compute only from source, original manifest, and verified proof; no hits."""
    raw = (build / "manifest.txt").read_bytes()
    proofs, _ = load_tools(clone)
    derived = proofs.masked_manifest(raw, envelope)
    selected, ownership, decisions, executed_lines = [], {}, set(), set()
    for target in plan["targets"]:
        path = clone / (target["module"] + ".mojo")
        text = path.read_text().splitlines(keepends=True)
        span = "".join(text[target["first_line"] - 1:target["last_line"]]).encode()
        if sha(path) != target["source_sha256"] or hashlib.sha256(span).hexdigest() != target["span_sha256"]:
            raise ValueError("Target source span changed")
    for line in derived.decode().splitlines():
        bits = line.split()
        if bits[0] == "P":
            selected.append(line)
            continue
        owners = [t["id"] for t in plan["targets"] if bits[1] == t["module"]
                  and t["first_line"] <= int(bits[2]) <= t["last_line"]]
        if owners:
            selected.append(line)
            ownership[line] = owners
            if bits[1] == "extensions/carla/lane_refinement":
                if bits[0] in ("B", "R"):
                    decisions.add(int(bits[2]))
                elif bits[0] == "L":
                    executed_lines.add(int(bits[2]))
    if not set(plan["center_new_decision_lines"]) <= decisions:
        raise ValueError("Trusted manifest omitted a planned center decision")
    if not set(plan["center_success_exit_lines"]) <= executed_lines:
        raise ValueError("Trusted manifest omitted a center success return L row")
    present = {owner for owners in ownership.values() for owner in owners}
    required = {t["id"] for t in plan["targets"] if t["id"] != "center-declarations"}
    if not required <= present:
        raise ValueError("An executable target span has no manifest rows")
    target_bytes = ("\n".join(selected) + "\n").encode()
    counts = Counter(line.split()[0] for line in selected)
    total = counts["L"] + 2 * counts["B"] + 2 * counts["C"] + counts["M"] + counts["R"]
    metadata = {"schema": "carla-frozen-target-denominator-v1",
                "scope": "Explicit targeted denominator, not the full original manifest.",
                "selected_manifest_sha256": hashlib.sha256(target_bytes).hexdigest(),
                "selected_rows": ownership, "original_manifest_sha256": hashlib.sha256(raw).hexdigest(),
                "original_manifest_rows": len(raw.decode().splitlines()),
                "current_proof_sha256": envelope["sha256"], "kind_counts": dict(counts),
                "required_targeted_obligations": total}
    return target_bytes, metadata


def check_frozen(cfg, plan, clone, build, prep, envelope=None):
    """Check frozen bytes and their independently carried supervisor binding."""
    folder = prep / "frozen-target"
    seal = json.loads((prep / "TARGET-SEAL.json").read_text())
    if snapshot(folder) != seal:
        raise ValueError("Frozen target files changed")
    receipt = json.loads((folder / "FREEZE-RECEIPT.json").read_text())
    metadata = json.loads((folder / "TARGET-DENOMINATOR.json").read_text())
    expected = {"schema": "carla-pre-capture-target-freeze-v1",
                "source_seal_sha256": cfg["source_seal_sha256"],
                "plan_sha256": cfg["plan_sha256"], "helper_sha256": cfg["helper_sha256"],
                "manifest_sha256": sha(folder / "target-manifest.txt"),
                "denominator_sha256": sha(folder / "TARGET-DENOMINATOR.json"),
                "proof_sha256": metadata["current_proof_sha256"],
                "capture_directory_absent_at_freeze": True}
    if receipt != expected or metadata["selected_manifest_sha256"] != expected["manifest_sha256"]:
        raise ValueError("Invalid pre-capture target binding")
    if metadata["original_manifest_sha256"] != sha(build / "manifest.txt"):
        raise ValueError("Original manifest changed after target freeze")
    if envelope is not None:
        target_bytes, regenerated = target_material(plan, clone, build, envelope)
        if target_bytes != (folder / "target-manifest.txt").read_bytes() or regenerated != metadata:
            raise ValueError("Frozen target differs from current source/proof derivation")
    return {"schema": "carla-pre-capture-target-binding-v1",
            "target_seal_sha256": sha(prep / "TARGET-SEAL.json"),
            "freeze_receipt_sha256": sha(folder / "FREEZE-RECEIPT.json"),
            "manifest_sha256": expected["manifest_sha256"],
            "denominator_sha256": expected["denominator_sha256"],
            "proof_sha256": expected["proof_sha256"]}, metadata


def classify_report(status, raw, denominator):
    """Accept only a complete report or the current CLI's exact deficit exit."""
    if type(status) is not int or status not in (0, 1):
        raise ValueError("Reporter failed or was terminated; not an ordinary deficit")
    text = raw.decode("utf-8", errors="strict")
    if "Coverage replay failed:" in text or "Traceback (most recent call last):" in text:
        raise ValueError("Report replay/wrapper failure")
    totals = re.findall(r"^TOTAL\s+(\d+)/(\d+)\s+(\d+)%\s*$", text, re.MULTILINE)
    if len(totals) != 1:
        raise ValueError("Missing or duplicate report TOTAL")
    covered, required, percent = map(int, totals[0])
    if required != denominator or required <= 0 or not 0 <= covered <= required or percent != covered * 100 // required:
        raise ValueError("Inconsistent report summary or denominator")
    diagnostics = re.findall(r"^Unhandled exception caught during execution: (.*)$", text, re.MULTILINE)
    deficit = re.fullmatch(r"Coverage is incomplete: (\d+) of (\d+) items never covered\.",
                           diagnostics[0]) if len(diagnostics) == 1 else None
    if status == 0:
        if covered != required or diagnostics or "Coverage is incomplete:" in text:
            raise ValueError("Success status contradicts coverage output")
        state = "complete"
    else:
        if covered == required or deficit is None or tuple(map(int, deficit.groups())) != (required - covered, required):
            raise ValueError("Nonzero report is not the exact ordinary coverage deficit")
        if text.count("Coverage is incomplete:") != 1:
            raise ValueError("Duplicate or ambiguous incomplete-coverage diagnostic")
        state = "incomplete_coverage"
    return {"coverage_state": state, "covered": covered, "required": required,
            "missing": required - covered, "reporter_returncode": status}


def report_log(path, call):
    """Keep exact combined output while leaving the maintained reporter unchanged."""
    sys.stdout.flush()
    sys.stderr.flush()
    saved = (os.dup(1), os.dup(2))
    try:
        with path.open("xb") as output:
            os.dup2(output.fileno(), 1)
            os.dup2(output.fileno(), 2)
            try:
                return call()
            finally:
                sys.stdout.flush()
                sys.stderr.flush()
    finally:
        os.dup2(saved[0], 1)
        os.dup2(saved[1], 2)
        os.close(saved[0])
        os.close(saved[1])
        if path.exists():
            sys.stdout.buffer.write(path.read_bytes())
            sys.stdout.buffer.flush()



def load_runtime_results(clone):
    sys.path.insert(0, str(clone / "tools"))
    import run_suite
    if Path(run_suite.__file__).resolve() != clone / "tools/run_suite.py":
        raise ValueError("Wrong executing maintained result validator")
    return run_suite


def actual_results(clone, path, *, native):
    """Use actual complete TestSuite output; never infer execution from source."""
    validator = load_runtime_results(clone)
    output = path.read_text(encoding="utf-8", errors="strict")
    errors = validator.result_errors(output)
    if native:
        errors += ["Native test exceeded five seconds: " + name
                   for name, _ in validator.slow_tests(output, 5)]
    if errors:
        raise ValueError("Invalid runtime results: " + "; ".join(errors))
    clean = validator.COLOR.sub("", output)
    summaries = [validator.SUMMARY.fullmatch(line) for line in clean.splitlines()]
    summary = next(match for match in summaries if match)
    total, passed, failed, skipped = map(int, summary.groups())
    if skipped:
        raise ValueError("A skipped control cannot qualify this fixed selection")
    tests = [match.group(3) for line in clean.splitlines()
             if (match := validator.RESULT.match(line))]
    if len(tests) != len(set(tests)):
        raise ValueError("Duplicate runtime test identities")
    return {"total": total, "passed": passed, "failed": failed, "skipped": skipped,
            "tests": tests, "output_sha256": sha(path),
            "timing_scope": "five seconds per native test" if native else
                            "instrumented transport under the maintained group deadline"}


def daz_witness(path):
    """Do not treat a passing Arm capability notice as the x86 DAZ witness."""
    text = path.read_text(encoding="utf-8", errors="strict")
    if "LAST_DAZ_CAPABILITY_UNAVAILABLE" in text:
        raise ValueError("Last-end DAZ witness unavailable; Arm is not equivalent")
    modes = re.findall(r"^LAST_REFUSAL_LEDGER\s+([56])\s+5\s+5000000005\s+1\s+0\s*$",
                       text, re.MULTILINE)
    if sorted(modes) != ["5", "6"]:
        raise ValueError("Both actual last-end DAZ mode ledgers are required")
    if not re.search(r"^REFUSAL_LEDGER\s+5\s+5000000005\s+1\s+0\s*$", text, re.MULTILINE):
        raise ValueError("First-end unsupported-state ledger is missing")
    return {"last_end_daz_modes": [5, 6], "actual_ledgers_verified": True,
            "system": platform.system(), "machine": platform.machine(), "arm_qualified": False}



def require_native_module_identity(affected, suite_key, native_test_support):
    """Reject duplicate module instances even when their __file__ paths agree."""
    if (sys.modules.get("affected") is not affected
            or sys.modules.get("suite_key") is not suite_key
            or sys.modules.get("native_test_support") is not native_test_support
            or suite_key.affected is not affected
            or suite_key.native_test_support is not native_test_support):
        raise ValueError("Native closure tools do not share the consumed module instances")


def native_inventory(cfg, plan, clone, prep):
    sys.path.insert(0, str(clone / "tools"))
    import affected
    import suite_key
    import native_test_support
    for module in (affected, suite_key, native_test_support):
        if Path(module.__file__).resolve().parent != clone / "tools":
            raise ValueError("Native closure tool resolved outside sealed clone")
    require_native_module_identity(affected, suite_key, native_test_support)
    previous = affected.ROOT
    try:
        affected.ROOT = str(clone)
        known, imports = set(affected.mojo_files()), {}
        assets = suite_key.asset_files()
        entries, union = [], set()
        for suite in cfg["suites"]:
            files = suite_key.closure(suite, known, imports)
            quoted = {prefix for name in files for prefix in imports[name][1]}
            used = [name for name in assets if any(name.startswith(prefix) for prefix in quoted)]
            fixtures = native_test_support.fixture_inputs(files)
            # Exercise the native helper's own root-aware dependency path.
            # Its local imports must resolve to the same shared objects.
            require_native_module_identity(affected, suite_key, native_test_support)
            consumed_fixtures = native_test_support.dependency_inputs(clone, clone / suite)
            require_native_module_identity(affected, suite_key, native_test_support)
            if affected.ROOT != str(clone) or consumed_fixtures != fixtures:
                raise ValueError("Native helper did not consume the intended sealed source root")
            entries.append({"suite": suite, "mojo_inputs": files, "assets": used, "fixtures": fixtures})
            union.update([*files, *used, *fixtures])
        hashes = {name: sha(clone / name) for name in sorted(union)}
        if entries != plan["native_closure"]["suites"] or hashes != plan["native_closure"]["union"]:
            raise ValueError("Fresh maintained native closure differs from reviewed 95 inputs")
        record = {"schema": "carla-fresh-native-inventory-v1", "suites": entries, "union": hashes,
                  "mojo_inputs": sum(name.endswith(".mojo") for name in union),
                  "total_inputs": len(union), "source_seal_sha256": cfg["source_seal_sha256"],
                  "consumed_module_instances_identical": True,
                  "native_dependency_root": str(clone),
                  "native_dependency_inputs_checked_for_all_suites": True,
                  "tool_hashes": {str(Path(module.__file__).relative_to(clone)): sha(module.__file__)
                                  for module in (affected, suite_key, native_test_support)}}
        dump_new(prep / "NATIVE-INVENTORY.json", record)
    finally:
        affected.ROOT = previous


def native_summary(cfg, clone, optimization):
    native = Path(cfg["native_phases"][optimization])
    records = []
    totals = Counter()
    for suite in cfg["suites"]:
        stem = Path(suite).stem
        stage_receipts = {}
        for suffix, cap in (("build", 180), ("run", 15)):
            result = native / (stem + "-" + suffix + "-RESULT.json")
            record = json.loads(result.read_text())
            log = native / (stem + "-" + suffix + ".log")
            if (record["returncode"] or record["timed_out"] or record["remaining_owned_descendants"]
                    or record["stage_timeout_seconds"] != cap or record["log_sha256"] != sha(log)
                    or record["source_seal_sha256"] != sha(native / "SOURCE-SEAL.json")):
                raise ValueError("Native stage did not pass with original bounds: " + str(result))
            if suffix == "build" and "-O" + optimization[-1] not in record["argv"]:
                raise ValueError("Native optimization control does not match its receipt")
            stage_receipts[suffix] = {"path": str(result), "sha256": sha(result),
                                      "log_sha256": sha(log)}
        log = native / (stem + "-run.log")
        actual = actual_results(clone, log, native=True)
        totals.update({key: actual[key] for key in ("total", "passed", "failed", "skipped")})
        item = {"suite": suite, "stage_receipts": stage_receipts,
                "binary_sha256": sha(native / (stem + "-bin")), "actual": actual}
        if stem == "test_carla_junction_endpoint_refusals":
            item["daz_witness"] = daz_witness(log)
        records.append(item)
    return {"schema": "carla-fresh-native-summary-v1", "optimization": optimization,
            "source_seal_sha256": cfg["source_seal_sha256"], "suites": records,
            "actual_totals": dict(totals), "arm_qualified": False,
            "native_inventory_sha256": sha(Path(cfg["prepare"]) / "NATIVE-INVENTORY.json"),
            "fixture_cache_files": snapshot(native / "fixture-cache")}


def prior_phase_receipts(cfg):
    records = {}
    for phase in ("prepare", "native-o3", "native-o0", "capture"):
        folder = Path(cfg["evidence_phases"][phase])
        result = json.loads((folder / "RESULT.json").read_text())
        before = json.loads((folder / "SDK-BEFORE.json").read_text())
        after = json.loads((folder / "SDK-AFTER.json").read_text())
        if (not result["sequence_completed"] or result["failure"] is not None
                or result["source_seal_unchanged"] is not True
                or result["sdk_identity_unchanged"] is not True
                or result["remaining_owned_descendants"] or before != after
                or json.loads((folder / "SOURCE-SEAL.json").read_text()) !=
                   json.loads(Path(cfg["source_seal"]).read_text())):
            raise ValueError("Prior phase did not complete with intact source/SDK: " + phase)
        records[phase] = {name: sha(folder / name) for name in
                          ("RESULT.json", "SDK-BEFORE.json", "SDK-AFTER.json", "SOURCE-SEAL.json")}
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("copy-source", "begin-generation", "copy-passthrough",
        "seal-generation", "freeze-targets", "capture-batch", "targeted-report", "whole-report", "final-summary",
        "native-inventory", "native-summary"))
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--optimization", choices=("o3", "o0"))
    args = parser.parse_args()
    cfg = json.loads(args.settings.read_text())
    if sys.flags.optimize or sha(__file__) != cfg["helper_sha256"]:
        raise ValueError("Qualification helper identity or Python mode changed")
    if sha(cfg["plan"]) != cfg["plan_sha256"]:
        raise ValueError("Target plan changed")
    plan = json.loads(Path(cfg["plan"]).read_text())
    source, clone, build = map(Path, (cfg["source"], cfg["clone"], cfg["build"]))
    prep, capture = map(Path, (cfg["prepare"], cfg["capture"]))
    if sha(cfg["supervisor"]) != cfg["supervisor_sha256"]:
        raise ValueError("Parent supervisor changed")
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("This plan qualifies Linux x86-64 only; do not infer Arm capability")
    if snapshot(Path(cfg["prepared_bundle"])) != json.loads(Path(cfg["prepared_bundle_seal"]).read_text()):
        raise ValueError("Prepared execution bundle changed")
    if sha(cfg["source_seal"]) != cfg["source_seal_sha256"]:
        raise ValueError("Final source-seal file changed")
    expected = json.loads(Path(cfg["source_seal"]).read_text())
    if snapshot(source) != expected:
        raise ValueError("Original frozen source changed")
    for suite in plan["suites"]:
        if suite["path"] in cfg["suites"] and sha(source / suite["path"]) != suite["sha256"]:
            raise ValueError("Maintained suite changed")
    if args.action == "copy-source":
        clone.mkdir(exist_ok=False)
        for name, digest in expected.items():
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Invalid source-seal path")
            original, target = source / relative, clone / relative
            if original.is_symlink():
                raise ValueError("Unreviewed source symlink")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, target)
            if sha(target) != digest:
                raise ValueError("Copy mismatch")
        if snapshot(clone) != expected:
            raise ValueError("Complete source materialization differs")
        dump(prep / "MATERIALIZATION.json", {"source_seal_sha256": sha(cfg["source_seal"]),
              "file_count": len(expected), "complete": True})
        return 0
    if snapshot(clone) != expected:
        raise ValueError("Complete qualification root changed")
    if args.action == "native-inventory":
        native_inventory(cfg, plan, clone, prep)
        return 0
    if args.action == "native-summary":
        if args.optimization is None:
            raise ValueError("An explicit native optimization phase is required")
        dump_new(Path(cfg["native_phases"][args.optimization]) / "NATIVE-SUMMARY.json",
                 native_summary(cfg, clone, args.optimization))
        return 0
    if args.action == "copy-passthrough":
        for name in expected:
            if name in plan["measured_modules"]:
                continue
            target = build / name
            if target.exists():
                raise ValueError("Passthrough would overwrite generated input: " + name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(clone / name, target)
        return 0
    if args.action == "capture-batch":
        # One inherited official deadline includes every capture and queued suite.
        if "THREEMOJO_COVERAGE_DEADLINE" not in os.environ:
            raise ValueError("Use the maintained coverage_io group command")
        binding, _ = check_frozen(cfg, plan, clone, build, prep)
        dump_new(capture / "PRE-CAPTURE-TARGET-BINDING.json", binding)
        print("Frozen target before first capture: " + json.dumps(binding, sort_keys=True), flush=True)
        hits = capture / "hits"
        hits.mkdir(exist_ok=False)
        for suite in cfg["suites"]:
            stem = Path(suite).stem
            command = [cfg["python"], str(clone / "tools/coverage_hit_aot.py"),
                       "--profile", cfg["profile"], "--root", str(build), "--suite", str(build / suite),
                       "--cache", str(capture / "fixture-cache"), "--", cfg["mojo"],
                       "run", "-I", str(build), str(build / suite)]
            wrapped = [cfg["python"], str(clone / "tools/coverage_io.py"), "capture",
                       "--out", str(hits / (stem + ".out")),
                       "--err", str(hits / (stem + ".txt.gz")),
                       "--loop-proof", str(build / "loop-proofs.json"),
                       "--loop-proof-root", str(clone), "--", *command]
            status = subprocess.run(wrapped, cwd=clone, check=False).returncode
            if status:
                return status if status > 0 else 128 - status
            try:
                actual = actual_results(clone, hits / (stem + ".out"), native=False)
                if stem == "test_carla_junction_endpoint_refusals":
                    actual["daz_witness"] = daz_witness(hits / (stem + ".out"))
                dump_new(hits / (stem + "-SUMMARY.json"), actual)
            except BaseException as error:
                dump_new(hits / (stem + "-SUMMARY-ERROR.json"), {"exception": repr(error)})
                raise
        return 0

    proofs, io = load_tools(clone)
    compiler_path = prep / "COMPILER-VERSION.txt"
    if args.action == "begin-generation":
        compiler = subprocess.run([cfg["mojo"], "--version"], capture_output=True,
                                  text=True, check=True, timeout=15).stdout.strip()
        compiler_path.write_text(compiler + "\n")
        for name in plan["measured_modules"]:
            (build / name).parent.mkdir(parents=True, exist_ok=True)
        proofs.begin_generation(clone, build, compiler, cfg["flags"],
                                mojo=cfg["mojo"], sources=plan["measured_modules"])
        return 0
    compiler = compiler_path.read_text().strip()
    settings = {"mojo": cfg["mojo"], "capture_cache": str(capture / "fixture-cache"),
                "suites": cfg["suites"]}
    if args.action == "seal-generation":
        envelope = proofs.seal(clone, build, compiler, cfg["flags"], **settings)
        dump(prep / "STAGED-SEAL.json", snapshot(build))
        dump(prep / "GENERATION-RESULT.json", {"proof_sha256": envelope["sha256"],
             "full_manifest_sha256": sha(build / "manifest.txt"),
             "scope": "Complete generated manifests for five measured modules with complete passthrough root."})
        return 0
    envelope = proofs.verify(build / "loop-proofs.json", clone, build, compiler, cfg["flags"], **settings)
    io._check_proof_consumer(envelope)
    if args.action == "freeze-targets":
        if capture.exists():
            raise ValueError("Freeze must precede the entire capture phase and all hits")
        target_bytes, metadata = target_material(plan, clone, build, envelope)
        folder = prep / "frozen-target"
        folder.mkdir(exist_ok=False)
        (folder / "target-manifest.txt").write_bytes(target_bytes)
        dump_new(folder / "TARGET-DENOMINATOR.json", metadata)
        receipt = {"schema": "carla-pre-capture-target-freeze-v1",
                   "source_seal_sha256": cfg["source_seal_sha256"],
                   "plan_sha256": cfg["plan_sha256"], "helper_sha256": cfg["helper_sha256"],
                   "manifest_sha256": sha(folder / "target-manifest.txt"),
                   "denominator_sha256": sha(folder / "TARGET-DENOMINATOR.json"),
                   "proof_sha256": envelope["sha256"], "capture_directory_absent_at_freeze": True}
        after = proofs.verify(build / "loop-proofs.json", clone, build, compiler, cfg["flags"], **settings)
        if after != envelope or capture.exists():
            raise ValueError("Generation changed or capture began during target freeze")
        dump_new(folder / "FREEZE-RECEIPT.json", receipt)
        dump_new(prep / "TARGET-SEAL.json", snapshot(folder))
        print(json.dumps(receipt, sort_keys=True), flush=True)
        return 0

    binding, target_metadata = check_frozen(cfg, plan, clone, build, prep, envelope)
    if json.loads((capture / "PRE-CAPTURE-TARGET-BINDING.json").read_text()) != binding:
        raise ValueError("Target does not match the binding recorded before capture")
    captures = sorted((capture / "hits").glob("*.txt.gz"))
    if {p.name.removesuffix(".txt.gz") for p in captures} != {Path(s).stem for s in cfg["suites"]}:
        raise ValueError("Missing or extra selected suite capture")
    proofs.verify_captures(captures, envelope)
    inventory = [{"capture": str(p), "capture_sha256": sha(p),
                  "receipt_sha256": sha(proofs.capture_receipt_path(p))} for p in captures]
    if args.action == "final-summary":
        results = {}
        for name in ("TARGET", "WHOLE"):
            path = capture / (name + "-REPORT-RESULT.json")
            record = json.loads(path.read_text())
            required = (target_metadata["required_targeted_obligations"] if name == "TARGET"
                        else envelope["receipt"]["denominator"]["required_total"])
            log = capture / (name + "-REPORT.raw.log")
            expected_keys = {"schema", "kind", "validation_complete", "proof_sha256", "target_binding",
                             "capture_receipts", "raw_log_sha256", "covered", "required", "missing",
                             "coverage_state", "reporter_returncode"}
            if (set(record) != expected_keys or record["schema"] != REPORT_SCHEMA or record["kind"] != name
                    or record["validation_complete"] is not True or record["proof_sha256"] != envelope["sha256"]
                    or record["target_binding"] != binding or record["capture_receipts"] != inventory
                    or record["raw_log_sha256"] != sha(log)
                    or (capture / (name + "-REPORT-ERROR.json")).exists()):
                raise ValueError("Invalid or failed report completion receipt: " + name)
            classification = classify_report(record["reporter_returncode"], log.read_bytes(), required)
            if any(record[key] != value for key, value in classification.items()):
                raise ValueError("Report receipt classification changed")
            results[name] = {"receipt_sha256": sha(path), **record}
        phases = prior_phase_receipts(cfg)
        records = {}
        test_identities = {}
        for optimization in ("o3", "o0"):
            record = native_summary(cfg, clone, optimization)
            path = Path(cfg["native_phases"][optimization]) / "NATIVE-SUMMARY.json"
            if json.loads(path.read_text()) != record:
                raise ValueError("Native summary changed")
            records[optimization] = {"summary_sha256": sha(path), **record}
            identities = {item["suite"]: sorted(item["actual"]["tests"]) for item in record["suites"]}
            if test_identities and identities != test_identities:
                raise ValueError("O3 and O0 did not execute the same test identities")
            test_identities = identities
        capture_results = []
        capture_totals = Counter()
        for suite in cfg["suites"]:
            stem = Path(suite).stem
            output = capture / "hits" / (stem + ".out")
            actual = actual_results(clone, output, native=False)
            if stem == "test_carla_junction_endpoint_refusals":
                actual["daz_witness"] = daz_witness(output)
            summary = capture / "hits" / (stem + "-SUMMARY.json")
            if json.loads(summary.read_text()) != actual or sorted(actual["tests"]) != test_identities[suite]:
                raise ValueError("Capture runtime summary/identities differ from native controls")
            capture_totals.update({key: actual[key] for key in ("total", "passed", "failed", "skipped")})
            capture_results.append({"suite": suite, "summary_sha256": sha(summary), **actual})
        result = {"targeted_complete": results["TARGET"]["coverage_state"] == "complete",
                  "whole_measured_modules_coverage_state": results["WHOLE"]["coverage_state"],
                  "source_root": str(source), "source_seal_sha256": cfg["source_seal_sha256"],
                  "official_capture_receipts_verified": True, "frozen_target_binding": binding,
                  "scope": "Only the explicit target denominator; whole-module deficits remain visible; not global 100%.",
                  "native_controls": records, "reports": results, "completed_phase_receipts": phases,
                  "instrumented_actual_totals": dict(capture_totals),
                  "instrumented_results": capture_results, "arm_qualified": False,
                  "required_final_action": "Check finish-phase SDK-after/source seals, no owned descendants, and exact-head hosted CI."}
        dump_new(capture / "FINAL-TARGETED-RESULT.json", result)
        return 0 if result["targeted_complete"] else 1

    kind = "WHOLE" if args.action == "whole-report" else "TARGET"
    log = capture / (kind + "-REPORT.raw.log")
    required = (envelope["receipt"]["denominator"]["required_total"] if kind == "WHOLE"
                else target_metadata["required_targeted_obligations"])
    try:
        if kind == "WHOLE":
            # This returns only after the maintained wrapper's post-validation.
            status = report_log(log, lambda: io.report_with_loop_proofs(
                [str(capture / "reporter"), str(build / "manifest.txt")], captures,
                root=clone, build=build, compiler=compiler, flags=cfg["flags"], **settings))
        else:
            status = report_log(log, lambda: io.report(
                [str(capture / "reporter"), str(prep / "frozen-target/target-manifest.txt")], captures))
        after = proofs.verify(build / "loop-proofs.json", clone, build, compiler, cfg["flags"], **settings)
        proofs.verify_captures(captures, after)
        after_binding, _ = check_frozen(cfg, plan, clone, build, prep, after)
        if after != envelope or after_binding != binding:
            raise ValueError("Report source/proof/frozen target changed during reporting")
        classification = classify_report(status, log.read_bytes(), required)
        record = {"schema": REPORT_SCHEMA, "kind": kind, "validation_complete": True,
                  "proof_sha256": envelope["sha256"], "target_binding": binding,
                  "capture_receipts": inventory, "raw_log_sha256": sha(log), **classification}
        dump_new(capture / (kind + "-REPORT-RESULT.json"), record)
    except BaseException as error:
        dump_new(capture / (kind + "-REPORT-ERROR.json"),
                 {"validation_complete": False, "exception": repr(error),
                  "raw_log_sha256": sha(log) if log.exists() else None})
        raise
    # Whole-module deficits are retained as structured, fully validated results.
    # Exceptions and crashes never reach this return or obtain a success receipt.
    return 0 if kind == "WHOLE" else status


if __name__ == "__main__":
    raise SystemExit(main())
