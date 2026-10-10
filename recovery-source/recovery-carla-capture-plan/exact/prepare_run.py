"""Emit reviewable supervisor configs. This program never runs repository code."""
import argparse
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORK = ROOT.parent


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--source-seal", type=Path, required=True)
    parser.add_argument("--source-seal-sha256", required=True)
    parser.add_argument("--tier", choices=("core", "expanded"), default="expanded")
    args = parser.parse_args()
    if not re.fullmatch(r"carla-[a-z0-9-]+", args.label):
        parser.error("label must be a fresh carla-... name")
    plan = json.loads((HERE / "plan.json").read_text())
    source = args.source_root.resolve()
    seal = args.source_seal.resolve()
    expected_seal = args.source_seal_sha256
    if not re.fullmatch(r"[0-9a-f]{64}", expected_seal):
        parser.error("Supply the parent's independently recorded exact final source-seal digest")
    if hashlib.sha256(seal.read_bytes()).hexdigest() != expected_seal:
        raise ValueError("Final qualified source-seal identity differs")
    for name, digest in plan["frozen_hashes"].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest:
            raise ValueError("Frozen source changed: " + name)
    suites = [s["path"] for s in plan["suites"]
              if args.tier == "expanded" or s["tier"] == "core"]
    out = HERE / "prepared" / args.label
    out.mkdir(parents=True, exist_ok=False)
    prep = ROOT / "evidence" / (args.label + "-prepare")
    native = ROOT / "evidence" / (args.label + "-native")
    capture = ROOT / "evidence" / (args.label + "-capture")
    for folder in (prep, native, capture):
        if folder.exists():
            raise ValueError("Never overwrite an earlier attempt: " + str(folder))
    clone, build = prep / "source", prep / "source/coverage/build"
    mojo = WORK / "restored-toolchain/official-venv/bin/mojo"
    python = mojo.parent / "python"
    helper = HERE / "capture_support.py"
    settings = {"source": str(source), "source_seal": str(seal),
                "source_seal_sha256": expected_seal,
                "clone": str(clone), "build": str(build), "prepare": str(prep),
                "native": str(native), "capture": str(capture),
                "mojo": str(mojo), "python": str(python),
                "flags": "-I .", "profile": "aot-hits",
                "coverage_group_seconds": 9000, "suites": suites,
                "plan": str(HERE / "plan.json"),
                "helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
                "plan_sha256": hashlib.sha256((HERE / "plan.json").read_bytes()).hexdigest(),
                "tier": args.tier}
    settings_path = out / "settings.json"
    dump(settings_path, settings)

    def stage(label, command, seconds=180, cwd=None, accept_nonzero=False):
        item = {"label": label, "command": list(map(str, command)), "seconds": seconds}
        if cwd is not None:
            item["cwd"] = str(cwd)
        if accept_nonzero:
            item["accept_nonzero"] = True
        return item

    def support(action, seconds=180):
        return stage(action, [python, helper, action, "--settings", settings_path], seconds)

    def config(suffix, stages, window, extra=False):
        result = {"source": str(source), "seal": str(seal),
                  "phase": args.label + "-" + suffix,
                  "window_seconds": window, "stages": stages,
                  "scope": "Fresh maintained CARLA targeted qualification on the explicitly sealed final snapshot. "
                           "No full-repository 100% claim and no main reconciliation."}
        if extra:
            result["additional_sources"] = [
                {"source": str(clone), "seal": str(seal)},
                {"source": str(build), "seal": str(prep / "STAGED-SEAL.json")},
                {"source": str(prep / "frozen-target"),
                 "seal": str(prep / "TARGET-SEAL.json")}]
        dump(out / (suffix + ".json"), result)

    prepare = [support("copy-source"), support("begin-generation"),
               stage("instrument", [mojo, "run", "-I", ".",
                     "coverage/build_cli.mojo", build, *plan["measured_modules"]],
                     cwd=clone),
               support("copy-passthrough"), support("seal-generation"),
               support("freeze-targets")]
    config("prepare", prepare, 1200)
    controls = []
    for suite in suites:
        name = Path(suite).stem
        binary = native / (name + "-bin")
        controls.append(stage(name + "-build", [python, clone / "tools/native_test_support.py",
            "run", "--root", clone, "--suite", clone / suite,
            "--cache", native / "fixture-cache", "--", mojo, "build", "-I", clone,
            "--num-threads", "1", "--target-triple=x86_64-unknown-linux-gnu",
            "--target-cpu=x86-64-v3", "--Werror", clone / suite, "-o", binary], cwd=clone))
        controls.append(stage(name + "-run", [python, clone / "tools/run_suite.py",
            "--seconds", "5", "--suite", clone / suite, "--", binary], 15, clone))
    config("native", controls, len(suites) * 195 + 300, extra=True)
    reports = [
        stage("reporter-build", [mojo, "build", "--Werror", "-I", build,
              build / "coverage/report_cli.mojo", "-o", capture / "reporter"], cwd=build),
        stage("maintained-captures", [python, clone / "tools/coverage_io.py", "group",
              "--seconds", "9000", "--", python, helper, "capture-batch",
              "--settings", settings_path], 9030, clone),
        stage("targeted-report", [python, helper, "targeted-report", "--settings", settings_path],
              180, clone, accept_nonzero=True),
        stage("whole-measured-modules-report", [python, helper, "whole-report",
              "--settings", settings_path], 180, clone),
        support("final-summary")]
    config("capture", reports, 10000, extra=True)
    instructions = ["Prepared only. Obtain the parent's execution lane approval first.",
                    "Run these in order. Stop on a failed phase; keep every receipt."]
    for phase in ("prepare", "native", "capture"):
        instructions.append(f"{python} -B {ROOT / 'run_stage.py'} {out / (phase + '.json')}")
    instructions.append("Inspect FINAL-TARGETED-RESULT.json and all supervisor RESULT.json files. "
                        "A completed supervisor sequence alone is not a passed target report.")
    (out / "COMMANDS.txt").write_text("\n".join(instructions) + "\n")
    print(out)


if __name__ == "__main__":
    main()
