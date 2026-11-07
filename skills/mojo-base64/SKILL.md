---
name: mojo-base64
description: Base16/32/64 byte codecs with CPython 3.14.8/3.14.9 oracle checks.
metadata:
  version: 0.1.1
---

# mojo-base64

## When to use

Use for Base64, URL-safe Base64, Base32, Base32hex and Base16 byte data.
Not for Base85, line wrapping, String input, or encode altchars.

## Install

Run `uv sync`; use relative `-I src` from a clone.

## Common calls

- `b64encode(s)` returns List[Byte].
- `b64decode(s, altchars, validate)` decodes with optional alphabet/strictness.
- `urlsafe_b64encode(s)` / `urlsafe_b64decode(s)` use the URL-safe alphabet.
- `b32decode(s, casefold, map01)` supports lowercase and digit mapping.
- `b16encode(s)` / `b16decode(s, casefold)` encode/decode uppercase hex.

Base32hex and standard Base64 variants are also exported.
Every codec has `_into` to append to a caller List, preserving its prefix.
Inputs are Span[UInt8]; List[Byte] converts to a span.

## Gotchas

Empty altchars/map01 means None; nonempty lengths must be 2/1.
validate and casefold default False. map01 is applied before casefold.
Errors use Mojo Error, with oracle-checked byte-input messages.
CPython maintenance releases changed padding semantics; see docs/design.md.
Codecs allocate nothing but the result (decode errors leave `out` untouched); never pass a span of `out` as input to its own `_into` call.

## Gate

`MOJO=.venv/bin/mojo scripts/ci.sh` runs the full stable gate.
`scripts/nightly.sh` runs nightly precompile, golden, brute, API and example.
