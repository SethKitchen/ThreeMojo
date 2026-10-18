<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Security policy

## Report a vulnerability

Send a private email to `seth.kitchen+anthropicoss@seth.kitchen`. Do not open a public issue or pull request for a vulnerability.

Put these items in the report:

- The file, loader or module that is affected.
- The smallest input that shows the problem. A crafted file is best.
- The output of `mojo --version`.

Keep the report private until a fix is on `main`.

## Supported versions

ThreeMojo has no releases. Fixes go to the `main` branch only.

## What counts as a vulnerability

The loaders in `loaders/` read files that an attacker can control. A crash, a hang, unbounded memory use or a read or write outside a buffer on such an input is a vulnerability. A loader that raises an error on bad input is correct behavior.

The file [`.oss-scanner/threat_model.md`](.oss-scanner/threat_model.md) states what is in scope and how severity is rated.

## Reports from Anthropic's OSS Scanner

[Anthropic's OSS Scanner](https://github.com/anthropics/oss-scanner) sends its reports to the same address. A model writes those reports. A human has not reviewed them.
