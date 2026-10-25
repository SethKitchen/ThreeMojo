# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Replace one executable token fragment without following a comment decoy."""
import tokenize

import source_contracts as sources


def replace_token_fragment(source, before, after):
    """Mutate one exact executable fragment independent of formatter wrapping.

    Retain actual function selection and every operator/name/literal. Comments
    and whitespace cannot redirect the mutation to a textual decoy. No pin or
    semantic assertion is weakened by this test-fixture normalization.
    """
    ignored = {tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
               tokenize.DEDENT, tokenize.ENDMARKER}

    def executable(text):
        result = [token for token in sources.tokens(text) if token.type not in ignored]
        # The formatter may add a final comma when it wraps call arguments.
        # This is mutation-location matching only, never a production gate.
        return [token for index, token in enumerate(result)
                if not (token.string == ',' and index + 1 < len(result)
                        and result[index + 1].string in (')', ']'))]

    actual = executable(source)
    wanted = [(token.type, token.string) for token in executable(before)]
    values = [(token.type, token.string) for token in actual]
    matches = [i for i in range(len(actual)) if values[i:i + len(wanted)] == wanted]
    if len(matches) != 1:
        raise AssertionError('missing or ambiguous executable mutation fragment: ' + before)
    lines = source.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    first, last = actual[matches[0]], actual[matches[0] + len(wanted) - 1]
    start = offsets[first.start[0] - 1] + first.start[1]
    end = offsets[last.end[0] - 1] + last.end[1]
    return source[:start] + after.lstrip(' \t') + source[end:]
