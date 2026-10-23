# Security Policy

## Supported versions

mbrotli is pre-1.0. Security fixes land on `master` and ship in a new patch
release of the latest minor version; older minor versions are not patched.

| Version | Supported |
| ------- | --------- |
| 0.5.x   | yes       |
| < 0.5   | no        |

## What counts as a vulnerability

Production code in the `mbrotli` crate forbids `unsafe`, so memory corruption
there should be impossible; a report that shows otherwise is especially
welcome. Please report privately anything that lets untrusted input cause:

- memory unsafety, including in the `mbrotli-ffi` C ABI;
- a panic, abort, or infinite loop in the decoder, the framed decoder, or any
  other API that accepts untrusted input;
- memory or CPU use beyond the limits a caller configured (`DecodeLimits`,
  `FramedDecodeLimits`, window limits), such as a decompression bomb that
  escapes those limits;
- decoded output that silently differs from the original data without an
  error.

Encoder output that differs from Google Brotli but still decodes correctly is a
correctness bug rather than a vulnerability; open a regular issue with the
"Output differs from Google Brotli" template.

Code under `brotli-ffi/vendor/` is upstream Google Brotli and is used only as a
test and benchmark oracle. Report issues in it to the
[Brotli project](https://github.com/google/brotli/security).

## Reporting a vulnerability

Do not open a public issue, pull request, or discussion.

Report it through GitHub's private vulnerability reporting:
[open a security advisory][advisory]. Include:

- the affected version or commit and the enabled crate features;
- the API you called and its configuration (quality, window, limits,
  dictionaries, framing options);
- a minimal input that reproduces the problem (attach it to the advisory) and
  what you observed;
- your assessment of the impact.

## What to expect

- An acknowledgement within 7 days.
- An initial assessment, and a fix plan if the report is confirmed, within
  30 days.
- A coordinated release: the fix is published together with a GitHub security
  advisory and a [RustSec](https://rustsec.org/) advisory where appropriate,
  and you are credited unless you ask not to be.

Please give us a reasonable time to release a fix before disclosing the issue
publicly.

[advisory]: https://github.com/M-Compressors/mbrotli/security/advisories/new
