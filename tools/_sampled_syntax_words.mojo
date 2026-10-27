# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the sampled syntax keywords and the generic messages.

Python still parses the syntax tree. These words only say which names are
removed and which generic refusal each check reports.
"""


def sampled_syntax_words() -> String:
    """Return the sampled syntax keywords and the generic messages.

    Returns:
        JSON with the keywords, the struct and class words, and the messages.
    """
    return (
        '{"keywords":["var","mut","out","ref","comptime","raises"],'
        + '"struct_word":"struct","class_word":"class","def_word":"def",'
        + '"unclosed":"unclosed Mojo generic declaration",'
        + '"ambiguous":"ambiguous generic declaration",'
        + '"parsed":"ambiguous parsed generic declaration",'
        + '"primitive_class":"_JetExpression","type_params":"type_params",'
        + '"mojo_parameters":"mojo_type_parameters"}'
    )
