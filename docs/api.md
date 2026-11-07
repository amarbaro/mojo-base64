# API

All `s` inputs are `Span[UInt8, _]`. Results are owned `List[Byte]`.
`out` is a mutable `List[Byte]`; every `_into` call appends, preserving its prefix.
`altchars` and `map01` are `List[Byte]`; empty means Python None.
Encode calls do not raise. Decode calls raise Mojo `Error` with the full
CPython 3.14.8/3.14.9 message for byte inputs. Python exception types differ.

| Signature | Description |
|---|---|
| b64encode(s) -> List[Byte] | Standard Base64 |
| b64encode_into(s, mut out) | Append encoded bytes |
| b64decode(s, altchars=empty, validate=False) raises -> List[Byte] | Optional alphabet translation, strict checks |
| b64decode_into(s, mut out, altchars=empty, validate=False) raises | Append decoded bytes |
| standard_b64encode(s) -> List[Byte] | Standard encoding |
| standard_b64encode_into(s, mut out) | Append standard encoding |
| standard_b64decode(s, validate=False) raises -> List[Byte] | Standard decoding |
| standard_b64decode_into(s, mut out, validate=False) raises | Append standard decoding |
| urlsafe_b64encode(s) -> List[Byte] | '-' and '_' alphabet |
| urlsafe_b64encode_into(s, mut out) | Append URL-safe encoding |
| urlsafe_b64decode(s, validate=False) raises -> List[Byte] | Translate URL-safe alphabet |
| urlsafe_b64decode_into(s, mut out, validate=False) raises | Append URL-safe decoding |
| b32encode(s) -> List[Byte] | Padded Base32 |
| b32encode_into(s, mut out) | Append Base32 encoding |
| b32decode(s, casefold=False, map01=empty) raises -> List[Byte] | Optional lowercase and 0/1 mapping |
| b32decode_into(s, mut out, casefold=False, map01=empty) raises | Append Base32 decoding |
| b32hexencode(s) -> List[Byte] | Extended hex Base32 |
| b32hexencode_into(s, mut out) | Append Base32hex encoding |
| b32hexdecode(s, casefold=False) raises -> List[Byte] | Base32hex decoding |
| b32hexdecode_into(s, mut out, casefold=False) raises | Append Base32hex decoding |
| b16encode(s) -> List[Byte] | Uppercase hexadecimal |
| b16encode_into(s, mut out) | Append uppercase hex |
| b16decode(s, casefold=False) raises -> List[Byte] | Decode hex |
| b16decode_into(s, mut out, casefold=False) raises | Append decoded hex |

Base64 rejects nonempty altchars lengths other than 2 using CPython's bytes
repr text. In strict mode padding and nonalphabet errors follow current
binascii branch order; invalid-length messages count data characters only.
Permissive mode ignores nonalphabet and excess padding, then checks tail length.
Duplicate altchars use the last mapping. altchars are validated and applied before
the leading-padding check, as CPython translates first. Encoders have no altchars parameter.

Base32 checks input length divisible by 8 before map01 length (must be 1).
It applies map01 before casefold, rejects nonalphabet before validating terminal
padchars in {0,1,3,4,6}. Base32hex has casefold but no map01.
Base16 rejects nonalphabet before odd-length input; lowercase needs casefold.

String inputs, encode altchars, Base85 and line-wrapping APIs are not supported.
The vectors in tests/golden/basic.txt contain the exact resulting error texts.
