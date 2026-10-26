# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed dependency checker bytes.

Fifteen executing checkers keep their reviewed digests. Six public checkers
keep their reviewed digests. A changed checker or a linked public checker is
refused.
"""

from std.pathlib import Path

from tools._carla_files import path_is_link
from tools._sha256 import sha256_hex


comptime _PREFIX = "full-audit cleanup successor: "


def _fail(message: String) raises:
    """Raise a dependency-checker error.

    Args:
        message: The failure text.

    Raises:
        Error: A checker changed.
    """
    raise Error(_PREFIX + message)


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _digest(
    root: String, path: String, expected: String, message: String
) raises:
    """Require one checker file to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The checker path.
        expected: The reviewed digest.
        message: The refusal prefix for this checker.

    Raises:
        Error: The checker changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail(message + path)


def _public(root: String, path: String, expected: String) raises:
    """Require one public checker to be a regular file with its digest.

    Args:
        root: The repository root.
        path: The checker path.
        expected: The reviewed digest.

    Raises:
        Error: The public checker changed or is a link.
    """
    var full = root + "/" + path
    if path_is_link(full):
        _fail("unreviewed public consumer checker bytes: " + path)
    _digest(root, path, expected, "unreviewed public consumer checker bytes: ")


def dependency_checker_bytes(root: String) raises:
    """Require the reviewed dependency-checker digests.

    Args:
        root: The repository root.

    Raises:
        Error: A checker changed.
    """
    var base = _root(root)
    _digest(
        base,
        "tools/carla_lane_oracle/source_contracts.py",
        "6a1f6f3efed801d586976fb3f7acff672d61409fbc61c957b8bf7cd808d3fda8",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/sum2_guard_contracts.py",
        "8c1d646c1dd70e1e7c9453077b63060ca506f76d2493137af0dd0a9a68012570",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/affected.py",
        "dcf533b9cd995902f53578aa93b98a32ca732643ccfa6ab7e30f95fd8b321eb3",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/cache_key.py",
        "ec06247feb8fe079c30b6da19fc655ffec363f1ce8e3372d063bf728e8c804c4",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/consumer_successor_ledger.py",
        "ce9a639084dfcc1442c6ac7535060cf5a123c2eb96683d2f35816ec26b0599ed",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/map_station_contracts.py",
        "caca22f46767ced3037d839a7941cb73a8ccf816238ad2037e28715f060055b7",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/shared_helper_contracts.py",
        "70b070d0bd5117b146a71470a46cb7a02c7fc31dfac1a5236eed50faf75b468e",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/runtime_view_contracts.py",
        "67316129402fac643be3c6e49ceef94bcb25c1ef92f81fd764a6abb583f89e34",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/map_deviation_contracts.py",
        "741a95b3fd3d0d51253dfef36327997c19ac90b9230a73942dd4697dcefffd39",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/witness_format_contracts.py",
        "a76ba6d5bf18be80c151fd03ea7a7ebeb75af1c1ed8af1600037d5f75ac13cb3",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/typed_boundary_contracts.py",
        "59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/conditioned_cubic_contracts.py",
        "df99ea0826d5efa936c56e4ece9aa79b41806b60e52121c4f564a8de5d5b0198",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/scaled_float32_contracts.py",
        "e3a59a9f8d5a9394007c03fab6ac696e04998812dad5843a22e721bfbe57c2a1",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/pr760_arithmetic_stage.py",
        "03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359",
        "unreviewed dependency checker bytes: ",
    )
    _digest(
        base,
        "tools/carla_lane_oracle/pr780_source_successor.py",
        "dca8c3bd13f27f6d2ae5e4f45c39f67ae7e0a4ae8043945064ade107ed3ce671",
        "unreviewed dependency checker bytes: ",
    )
    _public(
        base,
        "tools/carla_lane_oracle/winner_sign_contracts.py",
        "f850902634073364fe2407b00d12e9fdfb2ecfc6cf2a03414269fbb7984a8a7f",
    )
    _public(
        base,
        "tools/carla_lane_oracle/border_parser_contracts.py",
        "734d7b24aaf4e9f537cd7f0d7c7b8094d9c29106770b66c4a7a24cab74604dd4",
    )
    _public(
        base,
        "tools/carla_lane_oracle/lane_order_contracts.py",
        "314b1fae1f274c7223ab5dec50ad4cb97760c31926844ca92e1e6aa8560b4889",
    )
    _public(
        base,
        "tools/carla_lane_oracle/cache_key_contracts.py",
        "87233ebca3701e3a79b57b324afd48fcffb38b87cb3988859b6ae36bd63d919f",
    )
    _public(
        base,
        "tools/carla_lane_oracle/rounded_line_selector_contracts.py",
        "e47ff613bc198bc5cb629940fc0bcbe3c9517a153cd8e799e65ff0215f7b12bb",
    )
    _public(
        base,
        "tools/carla_lane_oracle/seed_count_contracts.py",
        "daa8f391a18e54a3fae958150673c134897db52ce5de87291f613f84df7c6d90",
    )


def main() raises:
    """Check the dependency checker bytes of this repository.

    Raises:
        Error: A checker changed.
    """
    dependency_checker_bytes(".")
