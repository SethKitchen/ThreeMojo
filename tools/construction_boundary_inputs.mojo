# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed construction-boundary inputs.

24 inputs keep their reviewed digests. A changed construction-boundary
input is refused.
"""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _fail(message: String) raises:
    """Raise a construction-boundary input error.

    Args:
        message: The failure text.

    Raises:
        Error: A construction-boundary input changed.
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
    """Require one construction-boundary input to keep its reviewed digest.

    Args:
        root: The repository root.
        path: The input path.
        expected: The reviewed digest.

    Raises:
        Error: The construction-boundary input changed.
    """
    if sha256_hex(Path(root + "/" + path).read_bytes()) != expected:
        _fail("construction boundary input changed: " + path)


def construction_boundary_inputs(root: String) raises:
    """Require the reviewed construction-boundary input digests.

    Args:
        root: The repository root.

    Raises:
        Error: A construction-boundary input changed.
    """
    var base = _root(root)
    _input(
        base,
        "extensions/__init__.mojo",
        "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479",
    )
    _input(
        base,
        "extensions/carla/__init__.mojo",
        "13bda95e7b80d111a65052af5508e95af88c7a17871fcf33f3eaf5dc75fd1a2d",
    )
    _input(
        base,
        "extensions/carla/curve_frozen_arc.mojo",
        "fe4a9b4bca0cd23dc2a128fbcb9ff3b4604a870dc0b2b4ff4f8deeb766d2db50",
    )
    _input(
        base,
        "extensions/carla/curve_interval.mojo",
        "ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040",
    )
    _input(
        base,
        "extensions/carla/curve_minimizer_support.mojo",
        "bdf79d12f2b3b784574fbd95e2e773ddeb29eb9586cf826c2b6142646341292e",
    )
    _input(
        base,
        "extensions/carla/curve_sum2.mojo",
        "2f732d49a891c9b603ccf05fb74779ea79422d74b4c33723ffe40f99e6c54a67",
    )
    _input(
        base,
        "extensions/carla/curve_trig.mojo",
        "3715caa64a81433a615f82e1eea4aa50e6e719e7450316fccc9d318f6994c909",
    )
    _input(
        base,
        "extensions/carla/lane_distance.mojo",
        "9d0aacab9fccb0a34f8d5c3a5edca1a1fd7ebcded961fc579ec6a44f3880497d",
    )
    _input(
        base,
        "extensions/carla/map_search.mojo",
        "53c5a1369203b2f57c915f4cacfe2935360bd6f4a676934f1a5dc67df69956a3",
    )
    _input(
        base,
        "extensions/carla/map_validation.mojo",
        "c8457abae67e989ae6de1131e3d30c8f101a0ae6fee9ec4f0afabc0f67be7bef",
    )
    _input(
        base,
        "extensions/carla/rtree.mojo",
        "be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460",
    )
    _input(
        base,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
        "ab0016a54e8a0d2d2dc8235e5954c111f1738ce08868d1c6fc30d454811d7a57",
    )
    _input(
        base,
        "extensions/carla/spiral_moment_proof.mojo",
        "f42f436b6e616e39bc2cda70491abf2e441aa40d5d8d1aa7f7ecffe3d0b0d5ac",
    )
    _input(
        base,
        "extensions/carla/spiral_moment_table.mojo",
        "1c5a3a21216eaecb42b3947ccb5ec0479d8a120c714d79ebe25f11da5f1096c8",
    )
    _input(
        base,
        "extensions/carla/spiral_moment_table_data.mojo",
        "63b07b8aa1567ad3e1c8b09a71e5619073e5255b4dc6f733d4ef6bf6b7088c8c",
    )
    _input(
        base,
        "extensions/carla/spiral_roundoff_proof.mojo",
        "66903c0cfba3315c46e8f48c9af0b3c118db4194236a7e4fe3e893a986c90b0c",
    )
    _input(
        base,
        "extensions/carla/transform.mojo",
        "c74c11819f95870d45cf37e7aa013fd72bc9673a4088c3e657efaa6b22999e56",
    )
    _input(
        base,
        "loaders/__init__.mojo",
        "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479",
    )
    _input(
        base,
        "math/__init__.mojo",
        "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479",
    )
    _input(
        base,
        "math/matrix_determinant.mojo",
        "c5b25179893fd2903dbda5de68914a50e662e3428107ef2c3424ef42cafcde19",
    )
    _input(
        base,
        "math/random.mojo",
        "f8a00ee7d03897a7c35f2f23d157fb65ce2c2b3fde5e4c91f21e7a764fab1655",
    )
    _input(
        base,
        "math/remainder.mojo",
        "b7575b2fde7a212433498422a121c66b12a85e7109614093bb783ad1cc043e58",
    )
    _input(
        base,
        "units/__init__.mojo",
        "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479",
    )
    _input(
        base,
        "units/quantity.mojo",
        "bb77541cdb757cd63b59ac01134c6a6ebce88863bee69c84ff77b8c03aff6223",
    )


def main() raises:
    """Check the construction-boundary inputs of this repository.

    Raises:
        Error: A construction-boundary input changed.
    """
    construction_boundary_inputs(".")
