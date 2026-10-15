# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CI planner runs what a change can reach, and fails closed.

No test runs the Mojo compiler or a native suite. The plans use a small
source tree. The tests of `run` and of the inventory use `make`.
"""

from std.collections import Set
from std.os import setenv, unsetenv
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.ci_scope import (
    Graph,
    JOBS,
    Plan,
    aggregate,
    changed_paths,
    inventories,
    kind,
    main_with,
    make_command,
    plan,
    read_plan,
    selection_makefile,
    source_tree,
    validate,
    workflow_errors,
)


def _sources() -> Dict[String, String]:
    """Return the fixture tree of the planner tests."""
    var sources = Dict[String, String]()
    sources["core/common.mojo"] = "def common():\n    pass\n"
    sources[
        "core/used.mojo"
    ] = "from core.common import common\ndef used():\n    pass\n"
    sources[
        "core/consumer.mojo"
    ] = "from core.used import used\ndef consumer():\n    pass\n"
    sources["core/other.mojo"] = "def other():\n    pass\n"
    sources["tests/_helper.mojo"] = "from core.used import used\n"
    sources[
        "tests/test_a.mojo"
    ] = "from tests._helper import used\nfrom core.common import common\n"
    sources["tests/test_b.mojo"] = "from core.common import common\n"
    sources["tests/test_consumer.mojo"] = "from core.consumer import consumer\n"
    sources["tests/test_other.mojo"] = "from core.other import other\n"
    sources["examples/used.mojo"] = "from core.used import used\n"
    sources["render/gpu.mojo"] = 'from core.used import used\n# "assets/gpu/"\n'
    sources["tests/test_gpu.mojo"] = "from render.gpu import gpu\n"
    sources["tests/test_gpu_layout.mojo"] = "from render.gpu import gpu\n"
    sources["coverage/runtime.mojo"] = "def runtime():\n    pass\n"
    sources[
        "tests/test_coverage.mojo"
    ] = "from coverage.runtime import runtime\n"
    return sources^


def _change(paths: List[String], deleted: Bool = False) -> Dict[String, Bool]:
    """Return a change of the given paths."""
    var changed = Dict[String, Bool]()
    for path in paths:
        changed[path] = deleted
    return changed^


def _plan(
    changed: Dict[String, Bool],
    sources: Dict[String, String] = _sources(),
) raises -> Plan:
    """Return the plan of a change, with no baseline sources."""
    return plan(".", changed.copy(), "", Dict[String, String](), sources)


def _full() raises -> Plan:
    """Return the full plan of the fixture tree."""
    return plan(".", None, "", Dict[String, String](), _sources())


def _with_old(
    changed: Dict[String, Bool],
    sources: Dict[String, String],
    old: Dict[String, String],
) raises -> Plan:
    """Return the plan of a change against baseline sources."""
    return plan(".", changed.copy(), "", old.copy(), sources)


def _on(value: Plan) raises -> String:
    """Return the names of the set flags, sorted, joined by spaces."""
    var names = List[String]()
    for entry in value.flags.items():
        if entry.value:
            names.append(entry.key)
    sort(names)
    return " ".join(names)


def _no_files(value: Plan) -> Bool:
    """Return whether every list of a plan is empty."""
    for entry in value.files.items():
        if len(entry.value) > 0:
            return False
    return True


def _files(value: Plan, name: String) raises -> String:
    """Return one list of a plan, joined by spaces."""
    return " ".join(value.files[name])


def _has(value: Plan, name: String, path: String) raises -> Bool:
    """Return whether a list of a plan holds a path."""
    for item in value.files[name]:
        if item == path:
            return True
    return False


def _same(left: Plan, right: Plan) -> Bool:
    """Return whether two plans store the same JSON."""
    return left.json() == right.json()


# --- routing -------------------------------------------------------------------


def _with_anatomy_tools() -> Dict[String, String]:
    """Return the fixture tree with the anatomy tools and their suites."""
    var sources = _sources()
    sources["tools/_imports.mojo"] = "def resolve():\n    pass\n"
    sources["tools/anatomy_validity.mojo"] = (
        "from tools._imports import resolve\n"
        'comptime INVENTORY = "docs/validation/anatomy-provenance.json"\n'
        "def main():\n    pass\n"
    )
    sources["tools/anatomy_overlaps.mojo"] = (
        "from tools.anatomy_validity import prepare_probe\n"
        "def main():\n    pass\n"
    )
    sources[
        "tests/test_anatomy_validity_tool.mojo"
    ] = "from tools.anatomy_validity import report\n"
    sources[
        "tests/test_anatomy_overlaps_tool.mojo"
    ] = "from tools.anatomy_overlaps import build\n"
    sources["tests/test_anatomy_report_binding_tool.mojo"] = (
        "from tools.anatomy_validity import bound_paths\n"
        'comptime REPORT = "docs/validation/anatomy-template-report.json"\n'
    )
    return sources^


def test_anatomy_evidence_runs_the_suites_that_bind_it() raises:
    # The report and its inventory are bound evidence, not documents. A
    # change runs each Mojo source that quotes the path, and its importers.
    var sources = _with_anatomy_tools()
    var inventory = _plan(
        _change(["docs/validation/anatomy-provenance.json"]), sources
    )
    assert_equal(kind("docs/validation/anatomy-provenance.json"), "native")
    assert_false(inventory.full)
    assert_true(inventory.flag("tools"))
    assert_equal(
        _files(inventory, "cpu_tests"),
        (
            "tests/test_anatomy_overlaps_tool.mojo"
            " tests/test_anatomy_report_binding_tool.mojo"
            " tests/test_anatomy_validity_tool.mojo"
        ),
    )
    assert_equal(_files(inventory, "covered"), "")
    var report = _plan(
        _change(["docs/validation/anatomy-template-report.json"]), sources
    )
    assert_equal(kind("docs/validation/anatomy-template-report.json"), "native")
    assert_false(report.full)
    assert_true(report.flag("tools"))
    assert_equal(
        _files(report, "cpu_tests"),
        "tests/test_anatomy_report_binding_tool.mojo",
    )
    # Other validation documents stay documentation.
    assert_equal(kind("docs/validation/water-gpu-300.md"), "docs")
    assert_equal(kind("docs/validation/anatomy-overlaps-595.json"), "docs")


def test_anatomy_tools_select_their_suites() raises:
    # The anatomy tools are Mojo tools: a change runs the suites that import
    # them. It measures no library.
    var sources = _with_anatomy_tools()
    var value = _plan(_change(["tools/anatomy_overlaps.mojo"]), sources)
    assert_false(value.full)
    assert_equal(_on(value), "cpu lint native tools")
    assert_equal(
        _files(value, "cpu_tests"), "tests/test_anatomy_overlaps_tool.mojo"
    )
    assert_equal(_files(value, "covered"), "")
    value = _plan(_change(["tools/anatomy_validity.mojo"]), sources)
    assert_false(value.full)
    assert_equal(
        _files(value, "cpu_tests"),
        (
            "tests/test_anatomy_overlaps_tool.mojo"
            " tests/test_anatomy_report_binding_tool.mojo"
            " tests/test_anatomy_validity_tool.mojo"
        ),
    )
    # The removed Python tools are not exempt.
    for path in ["tools/anatomy_validity.py", "tools/anatomy_overlaps.py"]:
        assert_true(_plan(_change([path]), sources).full, path)


def test_gallery_table_selects_the_tool_checks() raises:
    # The first tools shard runs `make repository-check`, which checks it.
    assert_equal(kind("examples/gallery.mk"), "tools")
    var value = _plan(_change(["examples/gallery.mk"]))
    assert_false(value.full)
    assert_true(value.flag("tools"))


def test_the_build_tools_and_their_imports_select_the_full_audit() raises:
    var sources = _sources()
    sources[
        "tools/suite_key.mojo"
    ] = "from tools._imports import closure\n\ndef main():\n    pass\n"
    sources["tools/_imports.mojo"] = "from loaders.json import parse_json\n"
    sources["loaders/json.mojo"] = "def parse_json():\n    pass\n"
    sources["loaders/other.mojo"] = "def other():\n    pass\n"
    for path in [
        "tools/suite_key.mojo",
        "tools/_imports.mojo",
        "loaders/json.mojo",
        "tools/affected.mojo",
        "tools/tool.sh",
    ]:
        assert_true(_plan(_change([path]), sources).full, path)
    assert_false(_plan(_change(["loaders/other.mojo"]), sources).full)


def _with_carla_tools() -> Dict[String, String]:
    """Return the fixture tree with the CARLA asset tools, their helpers and
    their suites."""
    var sources = _sources()
    sources["tools/_carla_files.mojo"] = "def files():\n    pass\n"
    sources[
        "tools/_carla_assets.mojo"
    ] = "from tools._carla_files import files\n"
    sources[
        "tools/carla_assets.mojo"
    ] = "from tools._carla_assets import load\ndef main():\n    pass\n"
    sources[
        "tools/carla_export_zip_packages.mojo"
    ] = "from tools._carla_assets import load\ndef main():\n    pass\n"
    sources[
        "tests/test_carla_assets_tool.mojo"
    ] = "from tools.carla_assets import run\n"
    sources[
        "tests/test_carla_export_tool.mojo"
    ] = "from tools.carla_export_zip_packages import zip_packages\n"
    return sources^


def test_carla_asset_tools_run_their_suites_and_documentation() raises:
    # The asset manager is a Mojo tool: a change runs the suite that
    # imports it, and the documentation checks with its page.
    var sources = _with_carla_tools()
    var value = _plan(_change(["tools/carla_assets.mojo"]), sources)
    assert_false(value.full)
    assert_equal(_on(value), "cpu lint native tools")
    assert_equal(
        _files(value, "cpu_tests"), "tests/test_carla_assets_tool.mojo"
    )
    assert_equal(_files(value, "covered"), "")
    var paths: List[String] = [
        "tools/carla_assets.mojo",
        "docs/wiki/CARLA-assets.md",
    ]
    value = _plan(_change(paths), sources)
    assert_equal(_on(value), "cpu docs lint native tools")
    # The shared helper reaches both suites.
    var shared = _plan(_change(["tools/_carla_assets.mojo"]), sources)
    assert_true(_has(shared, "cpu_tests", "tests/test_carla_assets_tool.mojo"))
    assert_true(_has(shared, "cpu_tests", "tests/test_carla_export_tool.mojo"))


def test_carla_packaging_keeps_native_export_and_unknown_routing() raises:
    var sources = _sources()
    sources["core/asset_user.mojo"] = '# "assets/carla/"\n'
    sources[
        "tests/test_assets.mojo"
    ] = "from core.asset_user import something\n"
    # The removed Python tools have no exemption: under assets/ they are
    # assets, as any new file there is.
    for path in [
        "assets/carla/manifest.json",
        "assets/carla/fixture.bin",
        "assets/carla/tools/new_tool.py",
        "assets/carla/tools/carla_assets.py",
        "assets/carla/tools/test_carla_assets.py",
    ]:
        assert_equal(kind(path), "native", path)
        var single = _plan(_change([path]), sources)
        assert_true(
            single.flag("native")
            and single.flag("cpu")
            and single.flag("coverage"),
            path,
        )
    var export: List[String] = ["assets/carla/tools/export/build_towns.py"]
    assert_true(_plan(_change(export)).flag("export"))
    # The ported export scripts are not exempt either.
    for path in [
        "assets/carla/tools/export/zip_packages.py",
        "assets/carla/tools/export/manifest_towns.py",
    ]:
        assert_equal(kind(path), "export", path)
    for path in ["Makefile", "tools/unknown.py"]:
        var paths = export.copy()
        paths.append(path)
        assert_true(_plan(_change(paths)).full, path)
    var used = export.copy()
    used.append("core/used.mojo")
    assert_true(_plan(_change(used)).flag("export"))


def _with_fidelity_suite() -> Dict[String, String]:
    """Return the fixture tree with the snapshot tool and its suite."""
    var sources = _sources()
    sources["tools/_python_json.mojo"] = "def loads():\n    pass\n"
    sources[
        "tools/humanoid_fidelity.mojo"
    ] = "from tools._python_json import loads\ndef run():\n    pass\n"
    sources[
        "tests/test_humanoid_fidelity_tool.mojo"
    ] = "from tools.humanoid_fidelity import run\n"
    return sources^


def test_humanoid_snapshot_tool_runs_its_suite_and_its_docs() raises:
    # The snapshot tool is a Mojo tool: a change runs the tool checks and
    # the suite that imports it. It measures no library.
    for path in ["tools/humanoid_fidelity.mojo", "tools/_python_json.mojo"]:
        var value = _plan(_change([path]), _with_fidelity_suite())
        assert_false(value.full, path)
        assert_equal(_on(value), "cpu lint native tools", path)
        assert_equal(
            _files(value, "cpu_tests"),
            "tests/test_humanoid_fidelity_tool.mojo",
        )
        assert_equal(_files(value, "covered"), "")
    var paths: List[String] = [
        "tools/humanoid_fidelity.mojo",
        "docs/wiki/Humanoid-fidelity.md",
    ]
    var value = _plan(_change(paths), _with_fidelity_suite())
    assert_false(value.full)
    assert_equal(_on(value), "cpu docs lint native tools")


def test_removed_humanoid_snapshot_python_is_not_exempt() raises:
    # The removed Python tool and unknown names select the full audit.
    for path in [
        "tools/humanoid_fidelity.py",
        "tools/humanoid_fidelity_new.py",
        "tools/humanoid_fidelity.mojo.extra",
    ]:
        assert_true(_plan(_change([path])).full, path)
    # A Python tool test still routes to the tool checks by its name.
    var value = _plan(_change(["tools/test_humanoid_fidelity.py"]))
    assert_false(value.full)
    assert_equal(_on(value), "lint tools")
    assert_true(_no_files(value))


def test_tool_tests_and_the_workflow_only_run_tools() raises:
    var value = _plan(
        _change(
            [
                "tools/test_build_tools.py",
                "tools/test_coverage_lifecycle.py",
                "tools/test_ci_policy.py",
                ".github/workflows/ci.yml",
            ]
        )
    )
    assert_false(value.full)
    assert_equal(_on(value), "lint tools")
    assert_true(_no_files(value))


def test_the_planner_runs_its_own_suite() raises:
    var sources = _sources()
    sources["tools/ci_scope.mojo"] = "def main():\n    pass\n"
    sources[
        "tests/test_ci_scope_tool.mojo"
    ] = "from tools.ci_scope import main\n"
    var value = _plan(_change(["tools/ci_scope.mojo"]), sources)
    assert_false(value.full)
    assert_equal(_files(value, "cpu_tests"), "tests/test_ci_scope_tool.mojo")


def _with_replay_suite(name: String) -> Dict[String, String]:
    """Return the fixture tree with a control generator and its suite."""
    var sources = _sources()
    sources["tools/_carla_controls.mojo"] = "def bracket():\n    pass\n"
    sources[
        "tools/generate_carla_" + name + "_controls.mojo"
    ] = "from tools._carla_controls import bracket\ndef run():\n    pass\n"
    sources["tests/test_carla_control_replay_tool.mojo"] = (
        "from tools.generate_carla_" + name + "_controls import run\n"
    )
    return sources^


def test_carla_control_generators_select_their_replay_suite() raises:
    # The generators are Mojo tools: a change runs the tool checks and the
    # suites that import them. It measures no library.
    for name in [
        "lane_distance",
        "power",
        "directed",
        "index",
        "distance",
        "fixed_s",
        "lane_orientation",
    ]:
        var tool = "tools/generate_carla_" + name + "_controls.mojo"
        var value = _plan(_change([tool]), _with_replay_suite(name))
        assert_false(value.full, tool)
        assert_equal(_on(value), "cpu lint native tools", tool)
        assert_equal(
            _files(value, "cpu_tests"),
            "tests/test_carla_control_replay_tool.mojo",
        )
        assert_equal(_files(value, "covered"), "")
    # The removed Python generators and unknown names are not exempt.
    for path in [
        "tools/generate_carla_power_controls.py",
        "tools/generate_carla_distance_controls.py",
        "tools/generate_carla_fixed_s_controls.py",
        "tools/generate_carla_lane_orientation_controls.py",
        "tools/generate_carla_unknown_controls.py",
        "tools/generate_carla_power_controls.mojo.extra",
    ]:
        assert_true(_plan(_change([path])).full, path)


def test_carla_generated_fixtures_keep_native_consumers() raises:
    for name in [
        "lane_distance_fraction",
        "power_fraction",
        "directed_fraction",
        "index_admission",
        "curve_distance_fraction",
        "fixed_s_fraction",
    ]:
        var fixture = "tests/test_carla_" + name + ".mojo"
        var sources = _with_replay_suite("power")
        sources[fixture] = "from core.used import used\n"
        sources["tests/test_replay_consumer.mojo"] = (
            "from tests.test_carla_" + name + " import used\n"
        )
        var value = _plan(_change([fixture]), sources)
        assert_false(value.full)
        assert_true(value.flag("native") and value.flag("cpu"))
        var expected: List[String] = [
            fixture,
            "tests/test_replay_consumer.mojo",
        ]
        sort(expected)
        assert_equal(_files(value, "cpu_tests"), " ".join(expected))
        var mixed = _plan(
            _change([fixture, "tools/generate_carla_power_controls.mojo"]),
            sources,
        )
        assert_false(mixed.full)
        expected.append("tests/test_carla_control_replay_tool.mojo")
        sort(expected)
        assert_equal(_files(mixed, "cpu_tests"), " ".join(expected))


def test_coverage_transport_and_proofs_run_the_coverage_tools() raises:
    for path in [
        "tools/coverage_hit_cache.c",
        "tools/fixtures/coverage_hit_transport_faults.c",
        "tools/coverage_hit_faults.py",
        "tools/check_coverage_loop_proofs.py",
        "tools/coverage_loop_proofs.py",
        "tools/carla_lane_oracle/source_contracts.py",
    ]:
        var value = _plan(_change([path]))
        assert_true(value.flag("coverage_tools"), path)
        assert_false(value.flag("coverage") or value.flag("cpu"), path)


# --- selection -----------------------------------------------------------------


def test_production_changes_follow_consumers_not_shared_dependencies() raises:
    var value = _plan(_change(["core/used.mojo", "tests/test_a.mojo"]))
    assert_equal(
        _files(value, "cpu_tests"), "tests/test_a.mojo tests/test_consumer.mojo"
    )
    assert_equal(_files(value, "covered"), "core/consumer.mojo core/used.mojo")
    assert_equal(_files(value, "coverage_tests"), _files(value, "cpu_tests"))
    assert_true(value.flag("gpu"))


def test_an_edited_test_runs_without_measuring_unchanged_library() raises:
    var value = _plan(_change(["tests/test_a.mojo"]))
    assert_equal(_files(value, "cpu_tests"), "tests/test_a.mojo")
    assert_equal(_files(value, "covered"), "")
    assert_false(value.flag("coverage"))


def test_an_edited_helper_selects_its_importers_only() raises:
    var value = _plan(_change(["tests/_helper.mojo"]))
    assert_equal(_files(value, "cpu_tests"), "tests/test_a.mojo")
    assert_equal(_files(value, "covered"), "")


def test_examples_and_benchmark_results_do_not_gate_library_coverage() raises:
    var value = _plan(
        _change(
            [
                "examples/used.mojo",
                "tools/bench_examples.mojo",
                "bench/results-linux.json",
                "docs/wiki/Examples.md",
            ]
        )
    )
    assert_equal(_files(value, "cpu_entries"), "examples/used.mojo")
    assert_false(value.flag("cpu") or value.flag("coverage"))
    assert_true(value.flag("native") and value.flag("docs"))


def _with_bench_examples() -> Dict[String, String]:
    """Return the fixture tree with the example benchmark and its suite."""
    var sources = _sources()
    sources["tools/_json_tree.mojo"] = "def parse():\n    pass\n"
    sources[
        "tools/bench_examples.mojo"
    ] = "from tools._json_tree import parse\ndef main():\n    pass\n"
    sources[
        "tests/test_bench_examples_tool.mojo"
    ] = "from tools.bench_examples import run\n"
    return sources^


def test_the_example_benchmark_runs_its_suite() raises:
    # The example benchmark is a Mojo tool: a change runs the suite that
    # imports it. It measures no library.
    var value = _plan(
        _change(["tools/bench_examples.mojo"]), _with_bench_examples()
    )
    assert_false(value.full)
    assert_equal(_on(value), "cpu lint native tools")
    assert_equal(
        _files(value, "cpu_tests"), "tests/test_bench_examples_tool.mojo"
    )
    assert_equal(_files(value, "covered"), "")
    # The results file stays a tool input.
    assert_equal(kind("bench/results-linux.json"), "tools")
    # The removed Python tool is not exempt.
    assert_true(_plan(_change(["tools/bench_examples.py"])).full)


def test_a_removed_import_keeps_its_former_coverage() raises:
    var sources = _sources()
    sources["tests/test_a.mojo"] = "def test_nothing():\n    pass\n"
    var value = _with_old(_change(["tests/test_a.mojo"]), sources, _sources())
    assert_equal(_files(value, "covered"), "core/common.mojo core/used.mojo")
    assert_true(_has(value, "coverage_tests", "tests/test_b.mojo"))
    assert_false(_has(value, "cpu_tests", "tests/test_b.mojo"))


def test_a_deleted_test_keeps_its_obligations_without_running() raises:
    var sources = _sources()
    _ = sources.pop("tests/test_a.mojo")
    var value = _with_old(
        _change(["tests/test_a.mojo"], True), sources, _sources()
    )
    assert_false(_has(value, "cpu_tests", "tests/test_a.mojo"))
    assert_true(_has(value, "covered", "core/used.mojo"))
    assert_true(_has(value, "coverage_tests", "tests/test_b.mojo"))


def test_a_removed_helper_import_and_package_reexport_survive() raises:
    var before = _sources()
    before["core/__init__.mojo"] = "from core.facade import used\n"
    before["core/facade.mojo"] = "from core.used import used\n"
    before["tests/_helper.mojo"] = "from core import used\n"
    var after = before.copy()
    after["tests/_helper.mojo"] = "def unrelated():\n    pass\n"
    var value = _with_old(_change(["tests/_helper.mojo"]), after, before)
    assert_true(_has(value, "covered", "core/used.mojo"))
    assert_true(_has(value, "covered", "core/common.mojo"))


def test_a_new_sibling_cannot_erase_a_removed_import_obligation() raises:
    var before = Dict[String, String]()
    before["core/module.mojo"] = "def foo():\n    pass\n"
    before["tests/test_a.mojo"] = "from core.module import foo\n"
    var after = before.copy()
    after["tests/test_a.mojo"] = "def empty():\n    pass\n"
    after["tests/core/module.mojo"] = "def foo():\n    pass\n"
    var value = _with_old(
        _change(["tests/test_a.mojo", "tests/core/module.mojo"]), after, before
    )
    assert_equal(_files(value, "covered"), "core/module.mojo")
    assert_true(value.flag("coverage"))


def test_a_deleted_shared_module_selects_cpu_and_gpu_consumers() raises:
    var sources = _sources()
    _ = sources.pop("core/used.mojo")
    var value = _plan(_change(["core/used.mojo"], True), sources)
    assert_true(value.flag("gpu"))
    assert_true(_has(value, "cpu_tests", "tests/test_a.mojo"))
    assert_true(_has(value, "covered", "core/consumer.mojo"))


def test_a_quoted_gpu_asset_selects_its_quoting_module() raises:
    var value = _plan(_change(["assets/gpu/file with spaces\n雪.bin"]))
    assert_true(value.flag("gpu"))
    assert_false(value.flag("cpu") or value.flag("coverage"))


def test_docs_and_empty_changes_skip_all_native_work() raises:
    for path in [
        "",
        "README.md",
        "coverage/README.md",
        "tools/carla_lane_oracle/README.md",
        "assets/gpu/README.md",
    ]:
        var changed = Dict[String, Bool]()
        if path:
            changed[path] = False
        var value = _plan(changed)
        for name in [
            "native",
            "cpu",
            "coverage",
            "gpu",
            "coverage_tools",
            "portability",
        ]:
            assert_false(value.flag(name), path + " " + name)


def test_unknown_inputs_select_the_full_audit() raises:
    assert_true(_full().full)
    for path in [
        "Makefile",
        "unknown.cfg",
        "tools/new_runtime.py",
        "tools/test_environment.py",
        ".github/workflows/other.yml",
        "new_package/module.mojo",
        "untracked.mojo",
    ]:
        assert_true(_plan(_change([path])).full, path)


def test_the_benchmark_report_keeps_only_its_tools_gate() raises:
    var value = _plan(_change(["bench/results-linux.json"]))
    assert_true(value.flag("tools"))
    assert_false(value.flag("native") or value.flag("coverage"))


def test_portability_embedded_protocol_and_export_dependencies() raises:
    var sources = _sources()
    sources["tests/portability_probe.mojo"] = "from core.used import used\n"
    assert_true(_plan(_change(["core/used.mojo"]), sources).flag("portability"))
    assert_true(_plan(_change(["render/tasks.mojo"])).flag("coverage_tools"))
    assert_true(
        _plan(_change(["assets/carla/tools/export/build_towns.py"])).flag(
            "export"
        )
    )


def _with_device_tools() -> Dict[String, String]:
    """Return the fixture tree with the GPU status, AIR and portability
    tools, their helpers and their suites."""
    var sources = _sources()
    sources["tools/_cli.mojo"] = "def parse():\n    pass\n"
    sources["tools/_gpu_status.mojo"] = "from tools._cli import parse\n"
    sources[
        "tools/gpu_status.mojo"
    ] = "from tools._gpu_status import parse\ndef main():\n    pass\n"
    sources[
        "tools/check_air_calls.mojo"
    ] = "from tools._cli import parse\ndef main():\n    pass\n"
    sources[
        "tools/check_portability.mojo"
    ] = "from tools._cli import parse\ndef main():\n    pass\n"
    sources[
        "tests/test_gpu_status_tool.mojo"
    ] = "from tools._gpu_status import parse\n"
    sources[
        "tests/test_check_air_calls_tool.mojo"
    ] = "from tools.check_air_calls import main\n"
    sources[
        "tests/test_check_portability_tool.mojo"
    ] = "from tools.check_portability import main\n"
    return sources^


def test_device_tools_select_their_jobs() raises:
    var sources = _with_device_tools()
    # The status tool needs MAX: CPU lint leaves it to the GPU job.
    var status = _plan(_change(["tools/gpu_status.mojo"]), sources)
    assert_false(status.full)
    assert_equal(_on(status), "gpu lint native tools")
    assert_equal(_files(status, "cpu_entries"), "")
    var report = _plan(_change(["tools/_gpu_status.mojo"]), sources)
    assert_equal(_on(report), "cpu gpu lint native tools")
    assert_equal(_files(report, "cpu_tests"), "tests/test_gpu_status_tool.mojo")
    # The AIR checker runs in the GPU job, and its suite on the CPU.
    var air = _plan(_change(["tools/check_air_calls.mojo"]), sources)
    assert_equal(_on(air), "cpu gpu lint native tools")
    assert_equal(
        _files(air, "cpu_tests"), "tests/test_check_air_calls_tool.mojo"
    )
    assert_equal(_files(air, "covered"), "")
    # The portability checker selects its own check.
    var port = _plan(_change(["tools/check_portability.mojo"]), sources)
    assert_equal(_on(port), "cpu lint native portability tools")
    assert_equal(
        _files(port, "cpu_tests"), "tests/test_check_portability_tool.mojo"
    )
    # The shared command-line helper reaches all three.
    var shared = _plan(_change(["tools/_cli.mojo"]), sources)
    assert_equal(_on(shared), "cpu gpu lint native portability tools")
    # The removed Python tools select the full audit.
    for path in [
        "tools/gpu_status.py",
        "tools/check_air_calls.py",
        "tools/check_portability.py",
    ]:
        assert_true(_plan(_change([path]), sources).full, path)


def test_unavailable_test_history_is_the_full_audit() raises:
    var tree = Tree()
    var value = plan(
        tree.root, _change(["tests/test_a.mojo"]), "missing", None, _sources()
    )
    assert_true(value.full)
    tree.close()


def test_an_unreadable_source_is_an_error() raises:
    var tree = Tree()
    tree.write("core/bad.mojo", "")
    Path(tree.root + "/core/bad.mojo").write_bytes([UInt8(0xFF)])
    with assert_raises():
        _ = source_tree(tree.root)
    tree.close()


def test_an_unsafe_file_name_fails_before_make() raises:
    var sources = _sources()
    sources["tests/test_$(shell touch BAD).mojo"] = "pass\n"
    with assert_raises(contains="Unsafe"):
        _ = plan(".", None, "", Dict[String, String](), sources)


def test_the_graph_resolves_from_entry_directories() raises:
    var sources = Dict[String, String]()
    var probe = (
        "from pkg.one import value\n\n\ndef main():\n    print(value())\n"
    )
    sources["tools/probe.mojo"] = probe
    sources["tests/test_probe.mojo"] = probe
    sources["pkg/one.mojo"] = "from helper import value\n"
    sources["helper.mojo"] = "def value() -> Int:\n    return 1\n"
    sources["pkg/helper.mojo"] = "def value() -> Int:\n    return 1\n"
    var graph = Graph(sources)
    assert_equal(len(graph.imports["pkg/one.mojo"]), 1)
    assert_true("helper.mojo" in graph.imports["pkg/one.mojo"])
    assert_false("pkg/helper.mojo" in graph.users)
    # A module named like a package prefix stays a dependency.
    sources["tools/pkg.mojo"] = "def main():\n    pass\n"
    graph = Graph(sources)
    assert_true("tools/pkg.mojo" in graph.imports["tools/probe.mojo"])
    assert_true("pkg/one.mojo" in graph.imports["tools/probe.mojo"])
    for deleted in [False, True]:
        var current = sources.copy()
        if deleted:
            _ = current.pop("tools/pkg.mojo")
        var value = _plan(_change(["tools/pkg.mojo"], deleted), current)
        assert_false(value.full)
        assert_true(_has(value, "cpu_entries", "tools/probe.mojo"))
        assert_true(_has(value, "cpu_tests", "tests/test_probe.mojo"))
        assert_equal(_has(value, "cpu_entries", "tools/pkg.mojo"), not deleted)


def test_a_removed_import_keeps_a_hidden_dependency() raises:
    var old = Dict[String, String]()
    var probe = (
        "from pkg.one import value\n\n\ndef main():\n    print(value())\n"
    )
    old["tools/probe.mojo"] = probe
    old["tests/test_probe.mojo"] = probe
    old["pkg/one.mojo"] = "from helper import value\n"
    old["helper.mojo"] = "def value() -> Int:\n    return 1\n"
    old["tools/pkg.mojo"] = "from core.hidden import value\n"
    old["core/hidden.mojo"] = "def value() -> Int:\n    return 1\n"
    old[
        "tests/test_hidden.mojo"
    ] = "from core.hidden import value\n\ndef main():\n    print(value())\n"
    var sources = old.copy()
    sources["tests/test_probe.mojo"] = "def main():\n    pass\n"
    var value = _with_old(_change(["tests/test_probe.mojo"]), sources, old)
    assert_false(value.full)
    assert_equal(_files(value, "covered"), "core/hidden.mojo")
    assert_true(_has(value, "coverage_tests", "tests/test_hidden.mojo"))
    assert_false(_has(value, "cpu_tests", "tests/test_hidden.mojo"))


# --- git -----------------------------------------------------------------------


def _repository() raises -> Tree:
    """Return a committed repository of the fixture tree."""
    var tree = Tree()
    for entry in _sources().items():
        tree.write(entry.key, entry.value)
    tree.commit()
    return tree^


def test_nul_paths_deletion_and_untracked_sources() raises:
    var tree = _repository()
    tree.write('assets/quotes "x"\n雪.bin', "a")
    tree.commit()
    tree.write('assets/quotes "x"\n雪.bin', "b")
    tree.remove("core/other.mojo")
    tree.write("tools/new.py", "")
    tree.write("notes.txt", "")
    var changed = changed_paths(tree.root, "HEAD")
    assert_true(Bool(changed))
    var value = changed.value().copy()
    assert_equal(len(value), 3)
    assert_false(value['assets/quotes "x"\n雪.bin'])
    assert_true(value["core/other.mojo"])
    assert_false(value["tools/new.py"])
    tree.close()


def test_unknown_and_divergent_history_is_the_full_audit() raises:
    var tree = _repository()
    assert_false(Bool(changed_paths(tree.root, "no-such-ref")))
    _ = tree.git(["checkout", "-q", "-b", "side"])
    tree.write("core/side.mojo", "")
    tree.commit()
    _ = tree.git(["checkout", "-q", "-"])
    # A base that is not an ancestor of HEAD is unknown history.
    assert_false(Bool(changed_paths(tree.root, "side")))
    var other = Tree()
    assert_false(Bool(changed_paths(other.root, "HEAD")))
    other.close()
    tree.close()


def test_a_renamed_test_keeps_its_baseline_obligations() raises:
    var tree = _repository()
    _ = tree.git(["mv", "tests/test_a.mojo", "tests/test_renamed.mojo"])
    var changed = changed_paths(tree.root, "HEAD")
    var value = changed.value().copy()
    assert_true(value["tests/test_a.mojo"])
    assert_false(value["tests/test_renamed.mojo"])
    var result = plan(tree.root, value^, "HEAD", None, source_tree(tree.root))
    assert_false(result.full)
    assert_true(_has(result, "covered", "core/used.mojo"))
    assert_true(_has(result, "cpu_tests", "tests/test_renamed.mojo"))
    tree.close()


# --- the stored plan, make and the final check ---------------------------------


def _needs(
    value: Plan, var override: String = "", var result: String = ""
) raises -> String:
    """Return a `needs` context that matches a plan, with one job changed.

    An override result of `drop` leaves the job out.
    """
    var text = String('{"scope": {"result": "success"}')
    if override == "scope":
        text = String("{")
        if result != "drop":
            text += '"scope": {"result": "' + result + '"}'
    var first = override == "scope"
    for job in materialize[JOBS]():
        var wanted = String("success") if value.flag(job[1]) else String(
            "skipped"
        )
        if job[0] == override:
            if result == "drop":
                continue
            wanted = result
        if not first or text != "{":
            text += ", "
        first = False
        text += '"' + job[0] + '": {"result": "' + wanted + '"}'
    return text + "}"


def test_aggregate_requires_success_only_for_applicable_jobs() raises:
    for value in [
        _plan(_change(["tools/test_build_tools.py"])),
        _full(),
        _plan(Dict[String, Bool]()),
    ]:
        aggregate(value, _needs(value))
        var names: List[String] = ["scope"]
        for job in materialize[JOBS]():
            names.append(job[0])
        for name in names:
            for status in [
                "failure",
                "cancelled",
                "skipped",
                "success",
                "drop",
            ]:
                var needs = _needs(value, name, status)
                if needs == _needs(value):
                    continue
                with assert_raises():
                    aggregate(value, needs)
    with assert_raises(contains="expected success, got None"):
        var value = _full()
        aggregate(
            value,
            _needs(value).replace(
                '"gpu-host": {"result": "success"}', '"gpu-host": {}'
            ),
        )


def test_an_invalid_plan_cannot_become_a_quiet_success() raises:
    var value = _plan(_change(["core/used.mojo"]))
    assert_true(_same(read_plan(value.json()), value))
    for text in [
        "null",
        "{}",
        '{"schema": 1}',
        value.json().replace('"schema":1', '"schema":2'),
        value.json().replace('"tools":true', '"tools":1'),
        value.json().replace(',"lint":true', ""),
    ]:
        with assert_raises():
            _ = read_plan(text)
    var wrong = value.copy()
    wrong.flags["cpu"] = False
    with assert_raises(contains="disagrees"):
        validate(wrong)
    for path in [
        "../evil.mojo",
        "/tmp/evil.mojo",
        "core/a b.mojo",
        "core/$(shell evil).mojo",
    ]:
        wrong = value.copy()
        wrong.files["cpu_tests"] = [path]
        with assert_raises(contains="Unsafe"):
            validate(wrong)
    wrong = value.copy()
    wrong.files["covered"] = ["core/used.mojo", "core/used.mojo"]
    with assert_raises(contains="Duplicate"):
        validate(wrong)


def _make(tree: Tree, command: List[String]) raises -> String:
    """Run a command in the tree with no make settings from outside."""
    var full: List[String] = [
        "env",
        "-u",
        "MAKEFLAGS",
        "-u",
        "MFLAGS",
        "-u",
        "MAKELEVEL",
        "-u",
        "MAKEFILES",
        "-u",
        "MAKEOVERRIDES",
        "-u",
        "GNUMAKEFLAGS",
        "-u",
        "AFFECTED",
    ]
    full.extend(command.copy())
    var result = run_program(full, 5, merge_errors=False, directory=tree.root)
    assert_equal(result.status, 0, result.output + result.errors)
    return result.output


def test_make_reads_the_scoped_lists_before_the_hash_and_in_recursion() raises:
    var value = _plan(_change(["core/used.mojo"]))
    var tree = Tree()
    tree.write(
        "Makefile",
        "CPU_TESTS := original\nCOVERED := original\n"
        + "COVERAGE_TESTS := $(CPU_TESTS)\nHASH := $(CPU_TESTS):$(COVERED)\n"
        + "test-cpu: probe\nprobe:\n\t@echo"
        ' "$(HASH)|$(COVERAGE_TESTS)|$(AFFECTED)"\n'
        + "\t@$(MAKE) --no-print-directory child\n"
        + 'child:\n\t@echo "$(CPU_TESTS)|$(COVERAGE_TESTS)"\n',
    )
    tree.write("selection.mk", selection_makefile(value, ["coverage-report"]))
    var output = _make(
        tree,
        # Make splits MAKEFILES at spaces, and the tree's path has some.
        make_command(
            value, ["--no-print-directory", "test-cpu"], "selection.mk"
        ),
    )
    for path in value.files["coverage_tests"]:
        assert_true(output.find(path) >= 0, path)
    assert_true(output.find("original") < 0)
    tree.close()


def test_tool_targets_get_no_list_overrides() raises:
    var value = _plan(_change(["tools/test_build_tools.py"]))
    for target in [
        "test-tools",
        "test-coverage-tool",
        "test-portability",
        "docs-check",
        "compile-gpu",
        "test-gpu-host",
        "check-gpu-air",
    ]:
        var command = make_command(value, [target], "/tmp/selection.mk")
        assert_equal(command[len(command) - 1], "MAKEFILES=")
    var native = make_command(
        _plan(_change(["core/used.mojo"])), ["test-cpu"], "/tmp/s.mk"
    )
    assert_equal(native[len(native) - 1], "MAKEFILES=/tmp/s.mk")
    var full = make_command(_full(), ["test-cpu"], "/tmp/s.mk")
    assert_equal(full[len(full) - 1], "MAKEFILES=")


def test_the_stored_plan_runs_make_and_its_hash_is_checked() raises:
    var tree = Tree()
    tree.write(
        "Makefile",
        'test-cpu:\n\t@test -n "$(CPU_TESTS)"\nfail:\n\t@exit 3\n',
    )
    var value = _plan(_change(["core/used.mojo"]))
    tree.write(".cache/ci-selection.json", value.json())
    with assert_raises(contains="does not match"):
        _ = setenv("CI_SELECTION_SHA256", "0" * 64)
        _ = main_with(tree.root, ["run", "--", "test-cpu"])
    _ = setenv("CI_SELECTION_SHA256", sha256_hex(value.json().as_bytes()))
    assert_equal(main_with(tree.root, ["run", "--", "test-cpu"]), 0)
    # Make exits with 2 when a recipe fails.
    assert_equal(main_with(tree.root, ["run", "--", "fail"]), 2)
    with assert_raises(contains="No Make target"):
        _ = main_with(tree.root, ["run", "--"])
    _ = setenv("CI_NEEDS", _needs(value))
    assert_equal(main_with(tree.root, ["aggregate"]), 0)
    _ = unsetenv("CI_NEEDS")
    _ = unsetenv("CI_SELECTION_SHA256")
    tree.remove(".cache/ci-selection.json")
    with assert_raises():
        _ = main_with(tree.root, ["aggregate"])
    tree.close()


def test_plan_writes_the_selection_and_the_github_outputs() raises:
    var tree = _repository()
    tree.write(
        "core/used.mojo",
        "from core.common import common\ndef used():\n    return\n",
    )
    _ = setenv("GITHUB_OUTPUT", tree.root + "/outputs")
    assert_equal(main_with(tree.root, ["plan", "--base", "HEAD"]), 0)
    _ = unsetenv("GITHUB_OUTPUT")
    var stored = tree.read(".cache/ci-selection.json")
    var value = read_plan(stored)
    assert_false(value.full)
    var outputs = tree.read("outputs")
    assert_true(
        outputs.startswith(
            "selection=" + sha256_hex(stored.as_bytes()) + "\ntools=true\n"
        )
    )
    assert_true(outputs.endswith("export=false\nlint=true\n"))
    assert_equal(main_with(tree.root, ["plan", "--full"]), 0)
    assert_true(read_plan(tree.read(".cache/ci-selection.json")).full)
    with assert_raises(contains="unknown argument"):
        _ = main_with(tree.root, ["plan", "--fast"])
    with assert_raises(contains="expected plan"):
        _ = main_with(tree.root, ["publish"])
    tree.close()


def test_the_inventory_matches_the_makefile() raises:
    var variables = [
        ("formatted", "FORMATTED"),
        ("cpu_entries", "CPU_ENTRY_POINTS"),
        ("cpu_docs", "CPU_DOC_SOURCES"),
        ("cpu_tests", "CPU_TESTS"),
        ("compile_fail", "COMPILE_FAIL_RUN"),
        ("covered", "COVERED"),
        ("coverage_tests", "COVERAGE_TESTS"),
    ]
    var tree = Tree()
    var wrapper = String("include Makefile\ninventory:\n")
    for entry in variables:
        wrapper += "\t@printf '%s\\n' '" + entry[0] + "=$(" + entry[1] + ")'\n"
    tree.write("inventory.mk", wrapper)
    var result = run_program(
        [
            "env",
            "-u",
            "MAKEFLAGS",
            "-u",
            "MFLAGS",
            "-u",
            "MAKEOVERRIDES",
            "-u",
            "MAKELEVEL",
            "-u",
            "MAKEFILES",
            "-u",
            "GNUMAKEFLAGS",
            "-u",
            "AFFECTED",
            "make",
            "-s",
            "-f",
            tree.root + "/inventory.mk",
            "inventory",
            "TOOLCHAIN=none",
            "NATIVE_TOOLCHAIN=none",
            "HASH=test",
        ],
        60,
        merge_errors=False,
    )
    assert_equal(result.status, 0, result.errors)
    var expected = inventories(source_tree("."))
    var count = 0
    for line in result.output.split("\n"):
        var text = String(line)
        var equals = text.find("=")
        if equals < 0:
            continue
        var name = String(text[byte=:equals])
        var actual = Set[String]()
        for path in String(text[byte = equals + 1 :]).split():
            actual.add(String(path))
        assert_equal(len(actual), len(expected[name]), name)
        for path in actual:
            assert_true(path in expected[name], name + ": " + path)
        count += 1
    assert_equal(count, len(variables))
    tree.close()


def test_the_full_plan_is_larger_than_one_argument_and_still_runs() raises:
    # The real inventory is longer than Linux's limit for one argument, so
    # it must travel in a file.
    var full = plan(".", None, "", Dict[String, String](), source_tree("."))
    assert_true(full.json().byte_length() > 131072)
    var broad = full.copy()
    broad.full = False
    var tree = Tree()
    tree.write(
        "Makefile",
        (
            "test-cpu: probe\nprobe:\n\t@true\n\t@$(MAKE) --no-print-directory"
            " child\nchild:\n\t@true\n"
        ),
    )
    for value in [full.copy(), broad.copy()]:
        tree.write("selection.mk", selection_makefile(value, ["test-cpu"]))
        _ = _make(tree, make_command(value, ["test-cpu"], "selection.mk"))
    tree.close()


def test_the_workflow_guards_each_job_with_its_flag() raises:
    var lines = String("name: check\njobs:\n  scope:\n    runs-on: x\n")
    for job in materialize[JOBS]():
        lines += (
            "  "
            + job[0]
            + ":\n    needs: scope\n    if: needs.scope.outputs.run_"
            + job[1]
            + " == 'true'\n"
        )
    lines += "  required:\n    needs: [scope]\n  wiki:\n    needs: required\n"
    assert_equal(len(workflow_errors(lines)), 0)
    var broken = lines.replace("run_gpu", "run_cpu").replace(
        "  lint-macos:\n", "  lint-mac:\n"
    )
    var errors = workflow_errors(broken)
    assert_equal(len(errors), 3, "\n".join(errors))
    assert_equal(errors[0], "lint-macos: no such job")
    assert_equal(errors[1], "gpu-host: guard is not run_gpu")
    assert_equal(errors[2], "lint-mac: not in the planner's JOBS")
    assert_equal(
        len(workflow_errors(Path(".github/workflows/ci.yml").read_text())), 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
