# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed coverage-invariant record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.carla_invariant_gate import (
    invariant_digest,
    invariant_pair,
    invariant_pin_predecessor,
    invariant_pin_predecessor_pair,
    invariant_places,
    invariant_record,
    _reject_duplicate_keys,
    _require_pin_pair,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="coverage invariant successor: unreviewed migration record"
    ):
        invariant_record(
            String("").as_bytes(), String("").as_bytes(), "", False
        )


def test_a_changed_runtime_pin_is_refused() raises:
    """A different runtime pin digest fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        invariant_digest(
            String("nope").as_bytes(), "00", "after", "runtime-source-pins.json"
        )


def test_a_changed_reconstruction_is_refused() raises:
    """A different reconstructed pin digest fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: historical pin reconstruction"
            " failed: sum2-guard-pins.json"
        )
    ):
        invariant_digest(
            String("nope").as_bytes(), "00", "before", "sum2-guard-pins.json"
        )


def test_a_reordered_pin_pair_is_refused() raises:
    """A pin-file order other than runtime then guard fails closed."""
    var directory = "/tmp/invariant-pair-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '["sum2-guard-pins.json","runtime-source-pins.json"]'
    )
    with assert_raises(
        contains="coverage invariant successor: wrong fixed ordered pin pair"
    ):
        invariant_pair(directory)


def test_a_repeated_pin_placement_is_refused() raises:
    """A repeated pointer fails closed before later values are checked."""
    var directory = "/tmp/invariant-places-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"duplicate":false,"actual":"aa","expected":"aa"},'
        + '{"duplicate":true,"actual":"","expected":"bb"}]'
    )
    with assert_raises(
        contains="coverage invariant successor: duplicate pin placement"
    ):
        invariant_places(directory)


def _pin() -> String:
    """Return one active coverage-invariant pin."""
    return '{\n  "schema": 1,\n  "accepted": "new"\n}\n'


def _restored() -> String:
    """Return the historical pin for `_pin`."""
    return '{\n  "schema": 1,\n  "accepted": "old"\n}\n'


def _request(label: String, before: String, after_token: String) -> String:
    """Return one predecessor request.

    Args:
        label: The pin filename.
        before: The required predecessor digest.
        after_token: The active token stored in the pin.

    Returns:
        The request JSON.
    """
    return (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"'
        + before
        + '","label":"'
        + label
        + '","transitions":[{"pointer":["accepted"],"after":"'
        + after_token
        + '","before":"old"}]}'
    )


def test_a_restored_invariant_pin_matches_its_predecessor() raises:
    """The historical token replaces the active token in one check."""
    var restored = _restored()
    assert_equal(
        invariant_pin_predecessor(
            _pin().as_bytes(),
            _request(
                "runtime-source-pins.json",
                sha256_hex(restored.as_bytes()),
                "new",
            ),
        ),
        restored,
    )


def test_a_changed_invariant_pin_digest_is_refused() raises:
    """A wrong active digest fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        _ = invariant_pin_predecessor(
            _pin().as_bytes(),
            _request("runtime-source-pins.json", "00", "new").replace(
                sha256_hex(_pin().as_bytes()), "00"
            ),
        )


def test_a_repeated_invariant_pointer_is_refused() raises:
    """A repeated pointer fails closed."""
    var request = (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"00","label":"runtime-source-pins.json","transitions":['
        + '{"pointer":["accepted"],"after":"new","before":"old"},'
        + '{"pointer":["accepted"],"after":"new","before":"old"}]}'
    )
    with assert_raises(
        contains="coverage invariant successor: duplicate pin placement"
    ):
        _ = invariant_pin_predecessor(_pin().as_bytes(), request)


def test_a_changed_invariant_placement_is_refused() raises:
    """A placement whose current token changed fails closed."""
    with assert_raises(
        contains="coverage invariant successor: active pin placement mismatch"
    ):
        _ = invariant_pin_predecessor(
            _pin().as_bytes(),
            _request("runtime-source-pins.json", "00", "absent"),
        )


def test_a_missing_invariant_pointer_is_refused() raises:
    """A pointer that leaves the pin fails closed."""
    var request = (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"00","label":"sum2-guard-pins.json","transitions":['
        + '{"pointer":["missing"],"after":"new","before":"old"}]}'
    )
    with assert_raises(contains="KeyError: 'missing'"):
        _ = invariant_pin_predecessor(_pin().as_bytes(), request)


def test_a_changed_invariant_predecessor_digest_is_refused() raises:
    """A restored pin whose digest changed fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: historical pin reconstruction"
            " failed: sum2-guard-pins.json"
        )
    ):
        _ = invariant_pin_predecessor(
            _pin().as_bytes(),
            _request("sum2-guard-pins.json", "00", "new"),
        )


def test_an_escaping_component_name_fails_before_the_record() raises:
    """A name outside the directory fails before the migration digest."""
    var directory = "/tmp/invariant-component-escape"
    makedirs(directory, exist_ok=True)
    Path(directory + "/names.json").write_text('["ok.json","a/b"]')
    Path(directory + "/0").write_bytes(String("x").as_bytes())
    Path(directory + "/1").write_bytes(String("y").as_bytes())
    with assert_raises(
        contains="coverage invariant successor: component record changed: a/b"
    ):
        invariant_record(
            String("not-the-record").as_bytes(),
            String("prior").as_bytes(),
            directory,
            True,
        )


def test_a_confined_component_name_checks_the_record_next() raises:
    """A direct file name reaches the migration digest."""
    var directory = "/tmp/invariant-component-confined"
    makedirs(directory, exist_ok=True)
    Path(directory + "/names.json").write_text('["ok.json"]')
    Path(directory + "/0").write_bytes(String("x").as_bytes())
    with assert_raises(
        contains="coverage invariant successor: unreviewed migration record"
    ):
        invariant_record(
            String("not-the-record").as_bytes(),
            String("prior").as_bytes(),
            directory,
            True,
        )


def test_indexed_component_bytes_keep_the_reviewed_digests() raises:
    """The reviewed components match when each payload is stored by index."""
    var directory = "/tmp/invariant-component-index"
    makedirs(directory, exist_ok=True)
    var folder = "tools/carla_lane_oracle/"
    Path(directory + "/names.json").write_text(
        '["curve-support-dispatch-migration.json",'
        + '"grouped-table-contract.json","lane-control-migration.json"]'
    )
    Path(directory + "/0").write_bytes(
        Path(folder + "curve-support-dispatch-migration.json").read_bytes()
    )
    Path(directory + "/1").write_bytes(
        Path(folder + "grouped-table-contract.json").read_bytes()
    )
    Path(directory + "/2").write_bytes(
        Path(folder + "lane-control-migration.json").read_bytes()
    )
    invariant_record(
        Path(folder + "coverage-invariant-migration.json").read_bytes(),
        Path(folder + "frozen-arc-producer-migration.json").read_bytes(),
        directory,
        True,
    )
    Path(directory + "/0").write_bytes(String("changed").as_bytes())
    with assert_raises(
        contains=(
            "coverage invariant successor: component record changed: "
            "curve-support-dispatch-migration.json"
        )
    ):
        invariant_record(
            Path(folder + "coverage-invariant-migration.json").read_bytes(),
            Path(folder + "frozen-arc-producer-migration.json").read_bytes(),
            directory,
            True,
        )


def test_the_ordered_pin_pair_follows_the_component_digests() raises:
    """A reviewed record accepts the pair, and a bad component still fails first.
    """
    var directory = "/tmp/invariant-component-pair"
    makedirs(directory, exist_ok=True)
    var folder = "tools/carla_lane_oracle/"
    Path(directory + "/names.json").write_text(
        '["curve-support-dispatch-migration.json",'
        + '"grouped-table-contract.json","lane-control-migration.json"]'
    )
    Path(directory + "/0").write_bytes(
        Path(folder + "curve-support-dispatch-migration.json").read_bytes()
    )
    Path(directory + "/1").write_bytes(
        Path(folder + "grouped-table-contract.json").read_bytes()
    )
    Path(directory + "/2").write_bytes(
        Path(folder + "lane-control-migration.json").read_bytes()
    )
    invariant_record(
        Path(folder + "coverage-invariant-migration.json").read_bytes(),
        Path(folder + "frozen-arc-producer-migration.json").read_bytes(),
        directory,
        True,
        True,
    )
    Path(directory + "/0").write_bytes(String("changed").as_bytes())
    with assert_raises(
        contains=(
            "coverage invariant successor: component record changed: "
            "curve-support-dispatch-migration.json"
        )
    ):
        invariant_record(
            Path(folder + "coverage-invariant-migration.json").read_bytes(),
            Path(folder + "frozen-arc-producer-migration.json").read_bytes(),
            directory,
            True,
            True,
        )
    var swapped = PyJson.parse(
        '{"pin_files":{"sum2-guard-pins.json":{},"runtime-source-pins.json":{}}}'
    )
    with assert_raises(
        contains="coverage invariant successor: wrong fixed ordered pin pair"
    ):
        _require_pin_pair(swapped)


def test_the_runtime_and_guard_predecessors_are_one_check() raises:
    """Both predecessors match the single-pin results, runtime first."""
    var restored = _restored()
    var digest = sha256_hex(restored.as_bytes())
    var runtime_request = _request("runtime-source-pins.json", digest, "new")
    var guard_request = _request("sum2-guard-pins.json", digest, "new")
    var framed = invariant_pin_predecessor_pair(
        _pin().as_bytes(), runtime_request, _pin().as_bytes(), guard_request
    )
    var runtime = invariant_pin_predecessor(_pin().as_bytes(), runtime_request)
    var guard = invariant_pin_predecessor(_pin().as_bytes(), guard_request)
    assert_equal(
        framed,
        String(len(runtime.as_bytes()))
        + "\n"
        + runtime
        + String(len(guard.as_bytes()))
        + "\n"
        + guard,
    )


def test_a_wrong_digest_fails_before_a_repeated_key() raises:
    """A repeated key is not reported when the pin digest is wrong."""
    var payload = String('{"a":1,"a":2}')
    var request = (
        '{"after":"00","before":"00","label":"runtime-source-pins.json",'
        + '"transitions":[]}'
    )
    with assert_raises(
        contains=(
            "coverage invariant successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        _ = invariant_pin_predecessor(payload.as_bytes(), request)


def test_a_repeated_key_fails_before_placement() raises:
    """A repeated key fails after the digest and before placement."""
    var payload = String('{"a":1,"a":2}')
    var request = (
        '{"after":"'
        + sha256_hex(payload.as_bytes())
        + '","before":"00","label":"runtime-source-pins.json","transitions":[]}'
    )
    with assert_raises(contains="duplicate runtime source pin key: a"):
        _ = invariant_pin_predecessor(payload.as_bytes(), request)


def test_a_repeated_pin_key_is_refused() raises:
    """A repeated object key fails before that pin is placed."""
    with assert_raises(contains="duplicate runtime source pin key: a"):
        _reject_duplicate_keys(String('{"a":1,"a":2}').as_bytes())
    with assert_raises(contains="duplicate runtime source pin key: b"):
        _reject_duplicate_keys(String('{"a":{"b":1,"b":2}}').as_bytes())


def test_a_runtime_predecessor_fails_before_the_guard_pin() raises:
    """A runtime reconstruction failure is reported before the guard key."""
    var runtime = String('{"schema":1}').as_bytes()
    var guard = String('{"a":1,"a":2}').as_bytes()
    var runtime_request = (
        '{"after":"'
        + sha256_hex(runtime)
        + '","before":"00","label":"runtime-source-pins.json","transitions":[]}'
    )
    var guard_request = (
        '{"after":"'
        + sha256_hex(guard)
        + '","before":"11","label":"sum2-guard-pins.json","transitions":[]}'
    )
    with assert_raises(
        contains=(
            "coverage invariant successor: historical pin reconstruction"
            " failed: runtime-source-pins.json"
        )
    ):
        _ = invariant_pin_predecessor_pair(
            runtime, runtime_request, guard, guard_request
        )


def main() raises:
    """Run the coverage-invariant gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
