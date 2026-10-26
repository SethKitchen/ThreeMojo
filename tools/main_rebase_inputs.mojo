# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed main rebase inputs.

18 inputs keep their reviewed digests. A changed main input is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _fail(message: String) raises:
    """Raise a main-rebase input error.

    Args:
        message: The failure text.

    Raises:
        Error: A main input changed.
    """
    raise Error(message)


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


def _input(root: String, path: String, expected: String) raises:
    """Require one main input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The input path.
        expected: The reviewed digest.

    Raises:
        Error: The main input changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("main input changed: " + path)


def main_rebase_inputs(root: String) raises:
    """Require the reviewed main-rebase input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A main input changed.
    """
    var base = _root(root)
    _input(
        base,
        "examples/streamline.mojo",
        "21dd83274a80642ab1e6584bff0be6b1c680ae33f6df8c286c0eaf33f9a750cd",
    )
    _input(
        base,
        "extensions/streamline/__init__.mojo",
        "6adec518df30a78f8e3a1ef6616d752f93c320f65b6bbf492e6c20f8bfec81d2",
    )
    _input(
        base,
        "extensions/streamline/constants.mojo",
        "b615c90fbdda9d403273875fa457c96e8ca2ae464ff6c74ae17f846a4ef358a2",
    )
    _input(
        base,
        "extensions/streamline/kinds.mojo",
        "33d193bbce007e2c1b9f0a937b4ab6eb03dc2e2434e2901fff210351adbcf9c2",
    )
    _input(
        base,
        "extensions/streamline/options.mojo",
        "286512fe326badfa8ee4ab5da380f2d882da5762f9571e4813ac23e528b38999",
    )
    _input(
        base,
        "extensions/streamline/tags.mojo",
        "683876ad1f74491cc22ad6ef5879f6e93ac92af2537f140e95dab4d6466b9e34",
    )
    _input(
        base,
        "tests/compile_fail/a_buffer_kind_is_not_a_bare_int.mojo",
        "ee03b16868a7c24fba3651ee682ab0861b8ab893c7d97b508b1ba9019f284fb9",
    )
    _input(
        base,
        "tests/compile_fail/a_denoiser_preset_is_not_a_bare_int.mojo",
        "361cbc3bb49b183ce42f7db30ffdf2a3b6a99b50fe96afe3f6f8890fa3aaf617",
    )
    _input(
        base,
        "tests/compile_fail/a_dlss_feature_is_not_a_bare_int.mojo",
        "bc64dbc64b72053756e0cdef165fe44bf11735429232a2fd2f982a99441f30d8",
    )
    _input(
        base,
        "tests/compile_fail/a_dlss_mode_is_not_a_bare_int.mojo",
        "81b777d7e3b730c96b6923b8b6c36a6f86c9f01eccbca081e9a5dd8f804f8eba",
    )
    _input(
        base,
        "tests/compile_fail/a_motion_vector_space_is_not_a_bare_int.mojo",
        "279d76407e55570f803f1154a926bb28e7fac7cf279267b328fdf9ce51563806",
    )
    _input(
        base,
        "tests/compile_fail/a_normal_roughness_mode_is_not_a_bare_int.mojo",
        "a2c5f2f982c320772bceab8bad80bfc7cceb4ce40db86ca48bf8d2490f05b65b",
    )
    _input(
        base,
        "tests/compile_fail/a_super_resolution_preset_is_not_a_bare_int.mojo",
        "d815bbc02df24e36e199eda2118311e92de5a07ae16c3c79597d83ac27a7dc20",
    )
    _input(
        base,
        "tests/test_streamline_constants.mojo",
        "ee26d8e6c980d4f5ebb768b10c01badd8e3ba4d4589a67da00235778d9c69425",
    )
    _input(
        base,
        "tests/test_streamline_kinds.mojo",
        "ee6c3d9e4fadac58ef8cf5783175450dd93b85bfcdcd708c7358b010af67f973",
    )
    _input(
        base,
        "tests/test_streamline_options.mojo",
        "9233973ed85436859b2b13f49f198e4352b7931cf6a5eeb6b94949e9bcdb4f3b",
    )
    _input(
        base,
        "tests/test_streamline_tags.mojo",
        "0bc1b868a5c820c188b5b93b624687994fc64eb4258549025e37aa7b7f907825",
    )
    _input(
        base,
        "tools/carla_lane_oracle/typed_boundary_contracts.py",
        "59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362",
    )


def main() raises:
    """Check the main rebase inputs of this repository.

    Raises:
        Error: A main input changed.
    """
    main_rebase_inputs(".")
