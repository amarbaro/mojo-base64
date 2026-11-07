# mojo-base64

<!-- badges -->
[![ci](https://github.com/amarbaro/mojo-base64/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/amarbaro/mojo-base64/actions/workflows/ci.yml) [![latest release](https://img.shields.io/github/v/release/amarbaro/mojo-base64)](https://github.com/amarbaro/mojo-base64/releases/latest) [![license](https://img.shields.io/github/license/amarbaro/mojo-base64)](https://github.com/amarbaro/mojo-base64/blob/main/LICENSE)
<!-- /badges -->

Base16, Base32, Base32hex and Base64 byte codecs for Mojo. Allocating calls
return List[Byte]; `_into` calls append to caller-owned buffers. Oracle tests
compare bytes and full error messages with CPython 3.14.8/3.14.9.

Install with `uv sync`; from a clone compile with `-I src`.

```mojo
from base64 import b64encode, b64decode
from std.testing import assert_equal

def main() raises:
    var data = List[Byte]()
    data.append(97)
    var encoded = b64encode(data)
    assert_equal(b64decode(encoded), data)
    print("YQ==")
```

Run the checked example: `scripts/capped.sh .venv/bin/mojo run -I src examples/quickstart.mojo`.

| Calls | Behavior |
|---|---|
| b64encode / b64decode | Base64; decode supports altchars and validate |
| standard_b64encode / standard_b64decode | Standard alphabet |
| urlsafe_b64encode / urlsafe_b64decode | URL-safe alphabet |
| b32encode / b32decode | Base32; decode supports casefold and map01 |
| b32hexencode / b32hexdecode | Base32hex; decode supports casefold |
| b16encode / b16decode | Uppercase hex; decode supports casefold |

Each call has an `_into` variant. All inputs are byte spans.

## Limits

Performance (docs/design.md, medians, one pinned core): b64 encode 1.23 vs CPython
0.77 GB/s at 64 MiB and 2.0 vs 1.1 at 1 KiB; decode 1.28 vs 0.64 and 1.19 vs 0.80;
b16 faster than CPython in every size measured. Base32 is not tuned. Peak RSS of
the b64 benchmark is 7.7% above CPython (270 vs 251 MB, allocator retention).
Encode altchars, String inputs, Base85 and wrapped-line APIs are outside this API.
Empty altchars/map01 lists mean None; nonempty lists require lengths 2/1.
Error uses Mojo Error, not Python exception classes.
Strict padding follows the tested CPython maintenance versions.

Tested toolchains: Mojo 1.2.0 and the nightly version recorded by scripts/nightly.sh.
Run `MOJO=.venv/bin/mojo scripts/ci.sh` for oracle, golden, brute, mutants, API and
example checks. Run `scripts/nightly.sh` for nightly. See [API](docs/api.md),
[design and benchmark commands](docs/design.md), [skill](skills/mojo-base64/SKILL.md),
and the [library index](../mojo-libs/README.md).

License: Apache-2.0; CPython-derived constants and behavior carry the PSF notice
in [LICENSE-PSF](LICENSE-PSF) and [NOTICE](NOTICE).
