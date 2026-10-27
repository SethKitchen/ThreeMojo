# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the render-actor and runtime-boundary refusal messages.

The live bytes still come from the repository. These messages only say
which consumer or bound test changed.
"""


def bound_consumer_messages() -> String:
    """Return the render-actor and runtime-boundary refusal messages.

    Returns:
        JSON with the four messages, each ending in a space.
    """
    return (
        '{"render_consumer":"unreviewed render actor consumer: ",'
        + '"render_test":"bound render actor test changed: ",'
        + '"runtime_consumer":"unreviewed runtime boundary consumer: ",'
        + '"runtime_test":"bound runtime boundary test changed: "}'
    )
